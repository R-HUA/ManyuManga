import { WorkSourceSheet } from './detail/WorkSourceSheet';
import { WorkChapterList } from './detail/WorkChapterList';
import { WorkHeroInfo } from './detail/WorkHeroInfo';
import promptAction from '@ohos.promptAction';
import uiMaterial from '@ohos.arkui.uiMaterial';
import { MangaRouteParams, ROUTE_READER, ROUTE_DOWNLOADS, ROUTE_PREVIEW } from '../common/Route';
import { Album, Chapter, ReadingProgress, CommentItem, CommentsResult, asRecord, asString, errorMessage } from '../models/Models';
import { sourceApi } from '../data/SourceApi';
import { sourceId, sourceStore } from '../data/Sources';
import { library, LibraryWork } from '../data/Library';
import { readProgressStore, historyStore, albumCacheStore } from '../data/Stores';
import { downloadManager } from '../data/DownloadManager';
import { prepareSourceSwitch, switchedProgress, SourceSwitchResult, discoverSources, SourceDiscovery } from '../data/SourceSwitch';
import { matchingChapter } from '../data/Matching';
import { IconCircleButton } from '../common/Components';
import { BG, CARD, PRIMARY, DANGER, TEXT_MAIN, TEXT_SUB } from '../common/Theme';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

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
  @State coverTint: string = 'rgba(58,122,254,0.22)';
  @State filter: string = '';
  @State unread: boolean = false;
  @State ascending: boolean = true;
  @State descExpanded: boolean = false;
  @State sourceSheet: boolean = false;
  @State comments: Array<CommentItem> = [];
  @State commentPage: number = 0;
  @State loadingComments: boolean = false;
  @State busy: boolean = false;

  private aid: string = '';
  private generation: number = 0;

  aboutToDisappear(): void {
    this.generation++;
  }

  private async load(key: string): Promise<void> {
    const ticket: number = ++this.generation;
    this.busy = true;
    this.error = '';
    try {
      const album: Album = await sourceApi.album(key);
      if (ticket !== this.generation) {
        return;
      }
      this.album = album;
      this.aid = album.id;
      this.sourceName = (await sourceStore.get(sourceId(key), false)).name;
      this.work = await library.workFor(key);
      this.progress = await readProgressStore.get(key);
      await albumCacheStore.put(album);
      await historyStore.record(album, album.coverUrl);
    } catch (e) {
      if (ticket === this.generation) {
        this.error = errorMessage(e as Error);
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
    } catch (e) {
      this.error = errorMessage(e as Error);
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
          this.error = discovered.failures.join('；');
        }
      }
    } catch (e) {
      this.error = errorMessage(e as Error);
    }
  }

  private async download(): Promise<void> {
    try {
      await downloadManager.enqueue(this.album!);
      promptAction.showToast({ message: '已加入离线下载队列' });
    } catch (e) {
      this.error = errorMessage(e as Error);
    }
  }

  private async chooseSource(target: Album): Promise<void> {
    const ticket: number = ++this.generation;
    this.busy = true;
    try {
      const album: Album = await sourceApi.album(target.id);
      if (ticket !== this.generation) {
        return;
      }
      if (this.progress !== null && this.album !== null) {
        const chapter: Chapter | undefined = this.album.episodes.find((c: Chapter) => c.id === this.progress!.chapterId);
        if (chapter !== undefined) {
          if (matchingChapter(chapter, album.episodes) === null) {
            this.album = album;
            this.aid = album.id;
            this.progress = await readProgressStore.get(album.id);
            this.sourceName = (await sourceStore.get(sourceId(album.id), false)).name;
            this.sourceSheet = false;
            this.error = '目标源章节命名不同，请手动点选对应章节继续阅读';
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
      await this.load(album.id);
      promptAction.showToast({ message: `已切换至 ${this.sourceName}` });
    } catch (e) {
      if (ticket === this.generation) {
        this.error = errorMessage(e as Error);
      }
    } finally {
      this.busy = false;
    }
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
    if (this.loadingComments) {
      return;
    }
    this.loadingComments = true;
    try {
      const result: CommentsResult = await sourceApi.comments(this.aid, this.commentPage + 1);
      this.comments = this.comments.concat(result.list);
      this.commentPage++;
    } catch (e) {
      this.error = errorMessage(e as Error);
    } finally {
      this.loadingComments = false;
    }
  }

  @Builder
  private TopBar() {
    Row({ space: 10 }) {
      IconCircleButton({
        glyph: $r('sys.symbol.chevron_left'),
        onTap: (): void => {
          this.stack.pop();
        }
      })

      Text(this.album !== null ? this.album.name : '漫画详情')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      IconCircleButton({
        glyph: $r('sys.symbol.arrow_left_arrow_right'),
        active: this.work !== null && this.work.albums.length > 1,
        onTap: (): void => {
          this.sourceSheet = true;
        }
      })

      IconCircleButton({
        glyph: $r('sys.symbol.arrow_down_circle'),
        onTap: (): void => {
          this.stack.pushPathByName(ROUTE_DOWNLOADS, {} as MangaRouteParams);
        }
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topInset + 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private Info() {
    WorkHeroInfo({
      album: this.$album,
      coverTint: this.$coverTint,
      sourceName: this.$sourceName,
      aid: this.aid,
      work: this.$work,
      sourceSheet: this.$sourceSheet,
      progress: this.$progress,
      read: (chapter?: Chapter): void => this.read(chapter),
      add: (): Promise<void> => this.add(),
      download: (): Promise<void> => this.download(),
      descExpanded: this.$descExpanded
    })
  }

  @Builder
  private Chapters() {
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
      loadComments: (): Promise<void> => this.loadComments()
    })
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
    NavDestination() {
      Column() {
        this.TopBar()

        if (this.error !== '') {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(16)
              .fontColor([DANGER])
            Text(this.error)
              .fontColor(TEXT_SUB)
              .fontSize(12)
              .layoutWeight(1)
            Text('重试')
              .fontColor(PRIMARY)
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .onClick(() => {
                this.load(this.aid);
              })
          }
          .padding(12)
          .margin({ left: 16, right: 16, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor(CARD)
        }

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
        } else if (this.breakpoint !== 'sm') {
          Row() {
            Scroll() {
              this.Info()
            }
            .width('42%')
            .height('100%')
            .scrollBar(BarState.Off)

            Scroll() {
              this.Chapters()
            }
            .width('58%')
            .height('100%')
            .scrollBar(BarState.Off)
          }
          .layoutWeight(1)
          .width('100%')
        } else {
          Scroll() {
            Column() {
              this.Info()
              this.Chapters()
            }
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)
      .bindSheet($$this.sourceSheet, this.SourcesSheet(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        backgroundColor: CARD,
        systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK })
      })
    }
    .hideTitleBar(true)
    .backgroundColor(BG)
    .onReady((context: NavDestinationContext) => {
      const params: Record<string, Object> | null = asRecord(context.pathInfo.param as Object);
      this.aid = params === null ? '' : asString(params['aid']);
      this.load(this.aid);
      this.sourceSheet = params !== null && params['match'] === true;
    })
    .onShown(() => {
      this.refresh();
    })
    .onHidden(() => {
      this.generation++;
    })
  }
}
