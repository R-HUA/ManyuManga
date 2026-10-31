import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HDS_TITLE_STYLE, IMMERSIVE_SHEET_MATERIAL } from '../common/ImmersiveMaterials';
import { WorkSourceSheet } from './detail/WorkSourceSheet';
import { WorkChapterList } from './detail/WorkChapterList';
import { WorkHeroInfo } from './detail/WorkHeroInfo';
import promptAction from '@ohos.promptAction';
import { MangaRouteParams, ROUTE_READER, ROUTE_PREVIEW } from '../common/Route';
import { Album, Chapter, ReadingProgress, CommentItem, CommentsResult, asRecord, asString, errorMessage } from '../models/Models';
import { sourceApi } from '../data/SourceApi';
import { sourceId, nativeId, SourceEntry, sourceStore } from '../data/Sources';
import { suwayomiLibrary } from '../data/SuwayomiLibrary';
import { library, LibraryWork } from '../data/Library';
import { readProgressStore, albumCacheStore } from '../data/Stores';
import { downloadManager, DownloadTask } from '../data/DownloadManager';
import { ChapterDownloadInfo, markedProgress, pickDownloadChapters } from './detail/ChapterRows';
import { prepareSourceSwitch, switchedProgress, SourceSwitchResult, discoverSources, SourceDiscovery } from '../data/SourceSwitch';
import { matchingChapter } from '../data/Matching';
import { BG, CARD, PRIMARY, DANGER, TEXT_MAIN, TEXT_SUB, HDS_TITLE_BAR_HEIGHT } from '../common/Theme';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';
import { isRequestCancelled, RequestAbortGroup } from '../util/RequestAbort';

@Component
export struct WorkDetailPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp('currentBreakpoint') breakpoint: string = 'sm';
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 0;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;

  @State album: Album | null = null;
  @State work: LibraryWork | null = null;
  @State progress: ReadingProgress | null = null;
  @State error: string = '';
  @State sourceName: string = '';
  @State filter: string = '';
  @State unread: boolean = false;
  @State ascending: boolean = true;
  @State descExpanded: boolean = false;
  @State sourceSheet: boolean = false;
  @State fromLibrary: boolean = false;
  @State comments: Array<CommentItem> = [];
  @State commentPage: number = 0;
  @State commentsDone: boolean = false;
  @State loadingComments: boolean = false;
  @State busy: boolean = false;
  @State remoteAvailable: boolean = false;
  @State remoteSaved: boolean = false;
  @State remoteReady: boolean = false;
  @State remoteBusy: boolean = false;
  @State remoteError: string = '';
  @State downloadStamp: number = 0;
  @State selecting: boolean = false;
  @State selectionStamp: number = 0;
  @State selectedCount: number = 0;
  private downloadMap: Map<string, ChapterDownloadInfo> = new Map<string, ChapterDownloadInfo>();
  private selected: Set<string> = new Set<string>();
  private downloadListener: (task: DownloadTask) => void = (task: DownloadTask): void => {
    if (this.album !== null && task.albumId === this.album.id) {
      this.refreshDownloads();
    }
  };
  private remoteGeneration: number = 0;

  private aid: string = '';
  private generation: number = 0;
  private detailRequests: RequestAbortGroup = new RequestAbortGroup();
  private commentRequests: RequestAbortGroup = new RequestAbortGroup();
  private mainScroller: Scroller = new Scroller();
  private chaptersScroller: Scroller = new Scroller();

  private cancelRequests(): void {
    this.remoteGeneration++;
    this.remoteBusy = false;
    this.detailRequests.abortAll();
    this.commentRequests.abortAll();
    this.loadingComments = false;
  }

  private renewRequests(): void {
    this.cancelRequests();
    this.detailRequests = new RequestAbortGroup();
    this.commentRequests = new RequestAbortGroup();
  }

  aboutToAppear(): void {
    downloadManager.onChange(this.downloadListener);
  }

  aboutToDisappear(): void {
    this.generation++;
    this.cancelRequests();
    downloadManager.offChange(this.downloadListener);
  }

  private refreshDownloads(): void {
    this.downloadMap = this.album === null ? new Map<string, ChapterDownloadInfo>() :
      downloadManager.chapterStates(this.album);
    this.downloadStamp++;
  }

  private async load(key: string): Promise<void> {
    this.renewRequests();
    const ticket: number = ++this.generation;
    this.busy = true;
    this.error = '';
    try {
      const album: Album = await sourceApi.album(key, false, this.detailRequests);
      if (ticket !== this.generation) {
        return;
      }
      const source: SourceEntry = await sourceStore.get(sourceId(key), false);
      const work: LibraryWork | null = await library.workFor(key);
      const progress: ReadingProgress | null = await readProgressStore.get(key);
      if (ticket !== this.generation || this.detailRequests.aborted()) {
        return;
      }
      this.album = album;
      this.aid = album.id;
      this.refreshDownloads();
      this.sourceName = source.name;
      this.work = work;
      this.progress = progress;
      this.remoteAvailable = source.kind === 'suwayomi';
      this.remoteReady = false;
      this.remoteBusy = false;
      this.remoteError = '';
      if (this.remoteAvailable) { this.loadRemoteShelf(); }
      await albumCacheStore.put(album);
    } catch (e) {
      if (ticket === this.generation && !isRequestCancelled(e as Error)) {
        if (this.album === null) {
          this.error = errorMessage(e as Error);
        } else {
          this.notifyError('刷新详情失败', e as Error);
        }
      }
    } finally {
      if (ticket === this.generation) {
        this.busy = false;
      }
    }
  }

  private async refresh(): Promise<void> {
    if (this.aid === '') {
      return;
    }
    try {
      this.work = await library.workFor(this.aid);
      this.progress = await readProgressStore.get(this.aid);
      if (this.remoteAvailable && !this.remoteBusy) { this.loadRemoteShelf(); }
    } catch (e) {
      this.notifyError('刷新书架状态失败', e as Error);
    }
  }

  private async toggleShelf(): Promise<void> {
    if (this.work === null) {
      await this.add();
    } else {
      const workId: string = this.work.id;
      this.getUIContext().showAlertDialog({
        title: '移出书架',
        message: `确认将《${this.album?.name ?? ''}》移出书架吗？阅读记录与离线文件将保留。`,
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: {
          value: '移出',
          fontColor: DANGER,
          action: () => {
            library.remove([workId]).then(async () => {
              await this.refresh();
              promptAction.showToast({ message: '已移出书架' });
            }).catch((e: Error) => {
              this.notifyError('移出书架失败', e);
            });
          }
        }
      });
    }
  }

  /** 远程收藏独立加载，不改变本地书架按钮及其持久化语义。 */
  private async loadRemoteShelf(): Promise<void> {
    const ticket: number = ++this.remoteGeneration;
    const key: string = this.aid;
    const requests: RequestAbortGroup = this.detailRequests;
    this.remoteBusy = true;
    this.remoteError = '';
    try {
      const source: SourceEntry = await sourceStore.get(sourceId(key));
      if (ticket !== this.remoteGeneration) { return; }
      const saved: boolean = await suwayomiLibrary.inLibrary(source, Number(nativeId(key)), requests);
      if (ticket !== this.remoteGeneration || key !== this.aid) { return; }
      this.remoteSaved = saved;
      this.remoteReady = true;
    } catch (e) {
      if (ticket === this.remoteGeneration && !isRequestCancelled(e as Error)) { this.remoteError = errorMessage(e as Error); }
    } finally {
      if (ticket === this.remoteGeneration) { this.remoteBusy = false; }
    }
  }

  private toggleRemoteShelf(): void {
    if (this.remoteBusy || !this.remoteReady) { return; }
    if (!this.remoteSaved) { this.saveRemoteShelf(true); return; }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.remove_remote_title'), message: $r('app.string.remove_remote_message'),
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: { value: '移出', fontColor: DANGER, action: (): void => { this.saveRemoteShelf(false); } }
    });
  }

  private async saveRemoteShelf(saved: boolean): Promise<void> {
    if (this.remoteBusy) { return; }
    const ticket: number = ++this.remoteGeneration;
    const key: string = this.aid;
    this.remoteBusy = true;
    this.remoteError = '';
    try {
      const source: SourceEntry = await sourceStore.get(sourceId(key));
      if (ticket !== this.remoteGeneration) { return; }
      const actual: boolean = await suwayomiLibrary.setInLibrary(source, Number(nativeId(key)), saved);
      if (ticket !== this.remoteGeneration || key !== this.aid) { return; }
      this.remoteSaved = actual;
    } catch (e) {
      if (ticket === this.remoteGeneration) { this.remoteError = errorMessage(e as Error); }
    } finally {
      if (ticket === this.remoteGeneration) { this.remoteBusy = false; }
    }
  }

  private async add(): Promise<void> {
    const ticket: number = this.generation;
    try {
      const current: Album = this.album!;
      await library.add(current);
      await this.refresh();
      promptAction.showToast({ message: '已加入书架，正在后台匹配多源…' });
      const discovered: SourceDiscovery = await discoverSources(current, (): boolean => ticket === this.generation);
      for (const album of discovered.albums) {
        if (ticket !== this.generation) {
          return;
        }
        await library.associate(current.id, album);
      }
      if (ticket === this.generation) {
        await this.refresh();
        if (discovered.failures.length > 0) {
          // 多源匹配失败不影响收藏本身，只记日志，不打断用户。
          hilog.warn(0x0000, 'WorkDetail', 'discoverSources failures: %{public}s', discovered.failures.join('；'));
        }
      }
    } catch (e) {
      this.notifyError('加入书架失败', e as Error);
    }
  }

  /** 下载范围选择：全部未下载 / 未读 / 接下来 N 章 / 自定义多选。 */
  private async download(): Promise<void> {
    if (this.album === null) {
      return;
    }
    await downloadManager.init().catch((): void => {});
    this.refreshDownloads();
    const missing: Array<string> = pickDownloadChapters(this.album, this.progress, 'missing', 0, this.downloadMap);
    const unread: Array<string> = pickDownloadChapters(this.album, this.progress, 'unread', 0, this.downloadMap);
    const next5: Array<string> = pickDownloadChapters(this.album, this.progress, 'next', 5, this.downloadMap);
    const next10: Array<string> = pickDownloadChapters(this.album, this.progress, 'next', 10, this.downloadMap);
    try {
      const picked: promptAction.ActionMenuSuccessResponse = await this.getUIContext().getPromptAction().showActionMenu({
        title: '下载章节',
        buttons: [
          { text: `全部未下载（${missing.length}）`, color: $r('sys.color.font_primary') },
          { text: `未读章节（${unread.length}）`, color: $r('sys.color.font_primary') },
          { text: `接下来 5 章（${next5.length}）`, color: $r('sys.color.font_primary') },
          { text: `接下来 10 章（${next10.length}）`, color: $r('sys.color.font_primary') },
          { text: '自定义选择…', color: $r('sys.color.font_primary') }
        ]
      });
      if (picked.index === 4) {
        this.startSelecting();
        return;
      }
      const choices: Array<Array<string>> = [missing, unread, next5, next10];
      if (picked.index >= 0 && picked.index < choices.length) {
        await this.downloadIds(choices[picked.index]);
      }
    } catch (e) {
      // 用户取消菜单不提示。
    }
  }

  private async downloadIds(ids: Array<string>): Promise<void> {
    if (this.album === null) {
      return;
    }
    if (ids.length === 0) {
      promptAction.showToast({ message: '没有需要下载的章节' });
      return;
    }
    try {
      await downloadManager.enqueueChapters(this.album, ids);
      promptAction.showToast({ message: `已加入下载队列：${ids.length} 章` });
    } catch (e) {
      this.notifyError('加入下载队列失败', e as Error);
    } finally {
      this.refreshDownloads();
    }
  }

  private downloadChapter(chapter: Chapter): void {
    this.downloadIds([chapter.id]);
  }

  private startSelecting(): void {
    this.selected = new Set<string>();
    this.selectedCount = 0;
    this.selecting = true;
    this.selectionStamp++;
  }

  private stopSelecting(): void {
    this.selecting = false;
    this.selected = new Set<string>();
    this.selectedCount = 0;
    this.selectionStamp++;
  }

  private toggleSelect(chapter: Chapter): void {
    if (this.selected.has(chapter.id)) {
      this.selected.delete(chapter.id);
    } else {
      this.selected.add(chapter.id);
    }
    this.selectedCount = this.selected.size;
    this.selectionStamp++;
  }

  private selectedIds(): Array<string> {
    const ids: Array<string> = [];
    if (this.album !== null) {
      for (const chapter of this.album.episodes) {
        if (this.selected.has(chapter.id)) {
          ids.push(chapter.id);
        }
      }
    }
    return ids;
  }

  private async downloadSelected(): Promise<void> {
    const ids: Array<string> = this.selectedIds().filter((id: string): boolean => {
      const info: ChapterDownloadInfo | undefined = this.downloadMap.get(id);
      return info === undefined || info.state === 'none' || info.state === 'failed';
    });
    this.stopSelecting();
    await this.downloadIds(ids);
  }

  private async markSelected(read: boolean): Promise<void> {
    if (this.album === null) {
      return;
    }
    const next: ReadingProgress | null = markedProgress(this.album, this.progress, this.selectedIds(), read);
    this.stopSelecting();
    if (next === this.progress) {
      return;
    }
    try {
      if (next === null) {
        await readProgressStore.remove(this.album.id);
      } else {
        await readProgressStore.save(next);
      }
      this.progress = next;
    } catch (e) {
      this.notifyError(read ? '标记已读失败' : '标记未读失败', e as Error);
    }
  }

  private async chooseSource(target: Album): Promise<void> {
    this.renewRequests();
    const ticket: number = ++this.generation;
    this.busy = true;
    try {
      const album: Album = await sourceApi.album(target.id, false, this.detailRequests);
      if (ticket !== this.generation) {
        return;
      }
      if (this.progress !== null && this.album !== null) {
        const chapter: Chapter | undefined = this.album.episodes.find((c: Chapter) => c.id === this.progress!.chapterId);
        if (chapter !== undefined) {
          if (matchingChapter(chapter, album.episodes) === null) {
            this.comments = [];
            this.commentPage = 0;
            this.commentsDone = false;
            this.album = album;
            this.aid = album.id;
            this.progress = await readProgressStore.get(album.id);
            this.sourceName = (await sourceStore.get(sourceId(album.id), false)).name;
            this.sourceSheet = false;
            promptAction.showToast({ message: '目标源章节命名不同，请手动点选对应章节继续阅读' });
            return;
          }
          const result: SourceSwitchResult = await prepareSourceSwitch(album, chapter, this.progress.page, this.progress.totalPages);
          if (ticket !== this.generation) {
            return;
          }
          await readProgressStore.save(switchedProgress(result));
          if (result.proportional) {
            promptAction.showToast({ message: '章节页数不同，已按阅读比例智能定位' });
          }
        }
      }
      await library.activate(album.id);
      this.sourceSheet = false;
      this.comments = [];
      this.commentPage = 0;
      this.commentsDone = false;
      await this.load(album.id);
      promptAction.showToast({ message: `已切换至 ${this.sourceName}` });
    } catch (e) {
      if (ticket === this.generation) {
        this.notifyError('切换图源失败', e as Error);
      }
    } finally {
      if (ticket === this.generation) {
        this.busy = false;
      }
    }
  }

  /** 操作类错误统一用 Toast 提示，详细原因写入日志，不再插入挤压布局的页内横幅。 */
  private notifyError(action: string, e: Error): void {
    hilog.error(0x0000, 'WorkDetail', '%{public}s: %{public}s', action, errorMessage(e));
    promptAction.showToast({ message: `${action}：${errorMessage(e)}` });
  }

  private readFromStart(): void {
    this.stack.pushPathByName(ROUTE_READER, { aid: this.aid, chapterIndex: 0, page: 0 } as MangaRouteParams);
  }

  private read(chapter?: Chapter): void {
    if (chapter === undefined) {
      this.stack.pushPathByName(ROUTE_READER, { aid: this.aid } as MangaRouteParams);
    } else {
      this.stack.pushPathByName(ROUTE_READER, { aid: this.aid, chapterId: chapter.id, page: 0 } as MangaRouteParams);
    }
  }

  private preview(chapter: Chapter): void {
    this.stack.pushPathByName(ROUTE_PREVIEW, {
      aid: this.aid,
      chapterId: chapter.id,
      query: chapter.title || `第 ${chapter.sort} 章`
    } as MangaRouteParams);
  }

  private async loadComments(): Promise<void> {
    if (this.loadingComments || this.commentsDone) {
      return;
    }
    this.loadingComments = true;
    if (this.commentRequests.aborted()) {
      this.commentRequests = new RequestAbortGroup();
    }
    const requests: RequestAbortGroup = this.commentRequests;
    const ticket: number = this.generation;
    const key: string = this.aid;
    try {
      const result: CommentsResult = await sourceApi.comments(key, this.commentPage + 1, requests);
      if (ticket !== this.generation || key !== this.aid || requests.aborted()) {
        return;
      }
      if (result.list.length > 0) {
        this.comments = this.comments.concat(result.list);
        this.commentPage++;
      }
      this.commentsDone = !result.hasNext;
    } catch (e) {
      if (ticket === this.generation && !isRequestCancelled(e as Error)) {
        this.notifyError('评论加载失败', e as Error);
      }
    } finally {
      if (ticket === this.generation && requests === this.commentRequests) {
        this.loadingComments = false;
      }
    }
  }

  sourceMenuLabel(): string {
    return this.work !== null && this.work.albums.length > 1 ? `换源（${this.work.albums.length}源）` : '换源';
  }

  remoteMenuLabel(): string {
    return this.remoteSaved ? '移出远程书架' : '加入远程书架';
  }

  @Builder
  private Info() {
    Column({ space: 8 }) {
      WorkHeroInfo({
      album: this.$album,
      sourceName: this.$sourceName,
      aid: this.aid,
      fromLibrary: this.fromLibrary,
      work: this.$work,
      sourceSheet: this.$sourceSheet,
      progress: this.$progress,
      read: (chapter?: Chapter): void => this.read(chapter),
      reread: (): void => this.readFromStart(),
      add: (): Promise<void> => this.add(),
      toggleShelf: (): Promise<void> => this.toggleShelf(),
      download: (): Promise<void> => this.download(),
      descExpanded: this.$descExpanded,
      topInset: this.topInset + HDS_TITLE_BAR_HEIGHT
      })
      if (this.remoteAvailable && (this.remoteBusy || this.remoteError !== '')) {
        Row({ space: 8 }) {
          if (this.remoteBusy) { LoadingProgress().width(20).height(20) }
          if (this.remoteError !== '') {
            Text(this.remoteError).fontSize(12).fontColor(DANGER).layoutWeight(1)
            Button($r('app.string.retry_action'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .onClick(() => { this.loadRemoteShelf(); })
          }
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })
      }
    }.width('100%')
  }

  @Builder
  private Chapters(withHero: boolean) {
    WorkChapterList({
      album: this.$album,
      ascending: this.$ascending,
      unread: this.$unread,
      filter: this.$filter,
      progress: this.$progress,
      read: (chapter?: Chapter): void => this.read(chapter),
      preview: (chapter: Chapter): void => this.preview(chapter),
      aid: this.aid,
      comments: this.$comments,
      commentsDone: this.commentsDone,
      loadComments: (): Promise<void> => this.loadComments(),
      scroller: withHero ? this.mainScroller : this.chaptersScroller,
      topOffset: withHero ? 0 : this.topInset + HDS_TITLE_BAR_HEIGHT,
      bottomOffset: this.selecting ? 88 + this.bottomInset : this.bottomInset + 16,
      chapterDownloads: true,
      downloadStamp: this.downloadStamp,
      downloads: (): Map<string, ChapterDownloadInfo> => this.downloadMap,
      downloadChapter: (chapter: Chapter): void => this.downloadChapter(chapter),
      selecting: this.selecting,
      selectionStamp: this.selectionStamp,
      selection: (): Set<string> => this.selected,
      toggleSelect: (chapter: Chapter): void => this.toggleSelect(chapter)
    }) {
      if (withHero) {
        this.Info()
      }
    }
  }

  @Builder
  private ToolAction(icon: Resource, label: string, enabled: boolean, action: () => void) {
    Column({ space: 2 }) {
      SymbolGlyph(icon).fontSize(20).fontColor([enabled ? TEXT_MAIN : TEXT_SUB])
      Text(label).fontSize(11).fontColor(enabled ? TEXT_MAIN : TEXT_SUB)
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .enabled(enabled)
    .accessibilityText(label)
    .onClick(() => {
      action();
    })
  }

  @Builder
  private SelectionBar() {
    Row() {
      this.ToolAction($r('sys.symbol.arrow_down_circle'), `下载（${this.selectedCount}）`, this.selectedCount > 0,
        (): void => { this.downloadSelected(); })
      this.ToolAction($r('sys.symbol.checkmark'), '标记已读', this.selectedCount > 0,
        (): void => { this.markSelected(true); })
      this.ToolAction($r('sys.symbol.arrow_counterclockwise'), '标记未读', this.selectedCount > 0,
        (): void => { this.markSelected(false); })
      this.ToolAction($r('sys.symbol.xmark'), '取消', true, (): void => { this.stopSelecting(); })
    }
    .width('100%')
    .height(64)
    .padding({ left: 8, right: 8 })
    .borderRadius(32)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .shadow(ShadowStyle.OUTER_DEFAULT_SM)
  }

  @Builder
  private SourcesSheet() {
    WorkSourceSheet({
      work: this.$work,
      aid: this.aid,
      busy: this.$busy,
      chooseSource: (target: Album): Promise<void> => this.chooseSource(target),
      refresh: (): Promise<void> => this.refresh(),
      error: this.$error,
      sourceSheet: this.$sourceSheet,
      add: (): Promise<void> => this.add()
    })
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.busy && this.album === null) {
          Column({ space: 12 }) {
            LoadingProgress().width(40).height(40).color(PRIMARY)
            Text('正在解析作品详情与章节列表…')
              .fontSize(13)
              .fontColor(TEXT_SUB)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .width('100%')
        } else if (this.album === null && this.error !== '') {
          // 只有详情本身加载失败才占满内容区显示错误与重试。
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(40)
              .fontColor([DANGER])
            Text(this.error)
              .fontSize(13)
              .fontColor(TEXT_SUB)
              .textAlign(TextAlign.Center)
              .padding({ left: 32, right: 32 })
            Button('重试')
              .onClick(() => {
                this.load(this.aid);
              })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .width('100%')
        } else if (this.breakpoint !== 'sm') {
          Row() {
            Scroll(this.mainScroller) {
              this.Info()
            }
            .width('42%')
            .height('100%')
            .scrollBar(BarState.Off)
            .align(Alignment.TopStart)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

            Column() {
              this.Chapters(false)
            }
            .width('58%')
            .height('100%')
          }
          .layoutWeight(1)
          .width('100%')
        } else {
          this.Chapters(true)
        }
        if (this.selecting) {
          Column() {
            this.SelectionBar()
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: this.bottomInset + 12 })
          .position({ left: 0, bottom: 0 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)
      .bindSheet($$this.sourceSheet, this.SourcesSheet(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        showClose: false,
        systemMaterial: IMMERSIVE_SHEET_MATERIAL
      })
    }
    .titleBar({ content: { title: { mainTitle: this.album === null ? '漫画详情' : this.album.name },
      menu: { value: this.fromLibrary && this.remoteAvailable ? [
        { content: { icon: $r('sys.symbol.arrow_left_arrow_right'), label: this.sourceMenuLabel(),
          action: (): void => { this.sourceSheet = true; } } },
        { content: { icon: this.remoteSaved ? $r('sys.symbol.cloud_fill') : $r('sys.symbol.cloud'),
          label: this.remoteMenuLabel(), isEnabled: this.remoteReady && !this.remoteBusy,
          action: (): void => { this.toggleRemoteShelf(); } } }
      ] : this.fromLibrary ? [
        { content: { icon: $r('sys.symbol.arrow_left_arrow_right'), label: this.sourceMenuLabel(),
          action: (): void => { this.sourceSheet = true; } } }
      ] : this.remoteAvailable ? [
        { content: { icon: this.remoteSaved ? $r('sys.symbol.cloud_fill') : $r('sys.symbol.cloud'),
          label: this.remoteMenuLabel(), isEnabled: this.remoteReady && !this.remoteBusy,
          action: (): void => { this.toggleRemoteShelf(); } } }
      ] : [] } },
      style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true, enableComponentSafeArea: false })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.mainScroller, this.chaptersScroller])
    .backgroundColor(BG)
    .onReady((context: NavDestinationContext) => {
      const params: Record<string, Object> | null = asRecord(context.pathInfo.param as Object);
      this.aid = params === null ? '' : asString(params['aid']);
      this.fromLibrary = params !== null && (params['fromLibrary'] === true || params['match'] === true);
      this.load(this.aid);
      this.sourceSheet = params !== null && params['match'] === true;
    })
    .onShown(() => {
      if (this.detailRequests.aborted()) {
        this.renewRequests();
        this.busy = false;
        if (this.album === null && this.aid !== '') {
          this.load(this.aid);
          return;
        }
      }
      this.refresh();
    })
    .onHidden(() => {
      this.generation++;
      this.cancelRequests();
    })
  }
}
