import promptAction from '@ohos.promptAction';
import { MangaRouteParams } from '../common/Route';
import { Album, Chapter, ReadingProgress, CommentItem, CommentsResult, asRecord, asString, errorMessage } from '../models/Models';
import { sourceApi } from '../data/SourceApi';
import { sourceId, sourceStore } from '../data/Sources';
import { library, LibraryWork } from '../data/Library';
import { readProgressStore, historyStore, albumCacheStore } from '../data/Stores';
import { downloadManager } from '../data/DownloadManager';
import { prepareSourceSwitch, switchedProgress, SourceSwitchResult, discoverSources, SourceDiscovery } from '../data/SourceSwitch';
import { matchingChapter } from '../data/Matching';
import { SourceCover } from '../common/SourceCover';
import { PagePreview } from '../common/PagePreview';
import { BG, CARD, PRIMARY, TEXT_MAIN, TEXT_SUB, CHIP_BG } from '../common/Theme';
import { ROUTE_READER, ROUTE_SEARCH } from '../common/Route';

@Component
export struct WorkDetailPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp('currentBreakpoint') breakpoint: string = 'sm';
  @State album: Album | null = null;
  @State work: LibraryWork | null = null;
  @State progress: ReadingProgress | null = null;
  @State error: string = '';
  @State sourceName: string = '';
  @State coverTint: string = 'rgba(10,114,245,0.2)';
  @State filter: string = '';
  @State unread: boolean = false;
  @State ascending: boolean = true;
  @State sourceSheet: boolean = false;
  @State previewSheet: boolean = false;
  @State previewChapter: string = '';
  @State previewPages: Array<string> = [];
  @State previewScramble: number = 0;
  @State comments: Array<CommentItem> = [];
  @State commentPage: number = 0;
  @State busy: boolean = false;
  private aid: string = '';
  private generation: number = 0;
  aboutToDisappear(): void { this.generation++; }
  private async load(key: string): Promise<void> {
    const ticket: number = ++this.generation;
    this.busy = true; this.error = '';
    try {
      const album: Album = await sourceApi.album(key);
      if (ticket !== this.generation) { return; }
      this.album = album; this.aid = album.id;
      this.sourceName = (await sourceStore.get(sourceId(key), false)).name;
      this.work = await library.workFor(key);
      this.progress = await readProgressStore.get(key);
      await albumCacheStore.put(album);
      await historyStore.record(album, album.coverUrl);
    } catch (e) { if (ticket === this.generation) { this.error = errorMessage(e as Error); } }
    finally { if (ticket === this.generation) { this.busy = false; } }
  }
  private async refresh(): Promise<void> {
    if (this.aid === '') { return; }
    try { this.work = await library.workFor(this.aid); this.progress = await readProgressStore.get(this.aid); }
    catch (e) { this.error = errorMessage(e as Error); }
  }
  private async add(): Promise<void> {
    const ticket: number = this.generation;
    try {
      const current: Album = this.album!;
      await library.add(current); await this.refresh();
      const discovered: SourceDiscovery = await discoverSources(current, (): boolean => ticket === this.generation);
      for (const album of discovered.albums) {
        if (ticket !== this.generation) { return; }
        await library.associate(current.id, album);
      }
      if (ticket === this.generation) { await this.refresh(); this.error = discovered.failures.join('；'); }
    }
    catch (e) { this.error = errorMessage(e as Error); }
  }
  private async download(): Promise<void> {
    try { await downloadManager.enqueue(this.album!); promptAction.showToast({ message: '已加入下载队列' }); }
    catch (e) { this.error = errorMessage(e as Error); }
  }
  private async chooseSource(target: Album): Promise<void> {
    const ticket: number = ++this.generation;
    this.busy = true;
    try {
      const album: Album = await sourceApi.album(target.id);
      if (ticket !== this.generation) { return; }
      if (this.progress !== null && this.album !== null) {
        const chapter: Chapter | undefined = this.album.episodes.find((c: Chapter) => c.id === this.progress!.chapterId);
        if (chapter !== undefined) {
          if (matchingChapter(chapter, album.episodes) === null) {
            this.album = album; this.aid = album.id; this.progress = await readProgressStore.get(album.id);
            this.sourceName = (await sourceStore.get(sourceId(album.id), false)).name;
            this.sourceSheet = false; this.error = '请选择对应章节继续阅读'; return;
          }
          const result: SourceSwitchResult = await prepareSourceSwitch(album, chapter, this.progress.page, this.progress.totalPages);
          if (ticket !== this.generation) { return; }
          await readProgressStore.save(switchedProgress(result));
          if (result.proportional) { promptAction.showToast({ message: '章节页数不同，已按阅读比例定位' }); }
        }
      }
      await library.activate(album.id);
      this.sourceSheet = false; this.comments = []; this.commentPage = 0;
      await this.load(album.id);
    } catch (e) { if (ticket === this.generation) { this.error = errorMessage(e as Error); } }
    finally { this.busy = false; }
  }
  private chapters(): Array<Chapter> {
    if (this.album === null) { return []; }
    const readIndex: number = this.progress === null ? -1 : this.progress.chapterIndex;
    const list: Array<Chapter> = this.album.episodes.filter((c: Chapter, i: number) =>
      c.title.includes(this.filter) && (!this.unread || i > readIndex || (i === readIndex && this.progress!.page < this.progress!.totalPages - 1)));
    return this.ascending ? list : list.reverse();
  }
  private read(chapter?: Chapter): void {
    if (chapter === undefined) { this.stack.pushPathByName(ROUTE_READER, { aid: this.aid } as MangaRouteParams); }
    else { this.stack.pushPathByName(ROUTE_READER, { aid: this.aid, chapterId: chapter.id, page: 0 } as MangaRouteParams); }
  }
  private async preview(chapter: Chapter): Promise<void> {
    try {
      const pages: Array<string> = await sourceApi.chapterImages(chapter.id);
      this.previewScramble = await sourceApi.scrambleId(chapter.id);
      this.previewChapter = chapter.id; this.previewPages = pages.slice(0, 4); this.previewSheet = true;
    } catch (e) { this.error = errorMessage(e as Error); }
  }
  private async loadComments(): Promise<void> {
    try {
      const result: CommentsResult = await sourceApi.comments(this.aid, this.commentPage + 1);
      this.comments = this.comments.concat(result.list); this.commentPage++;
    } catch (e) { this.error = errorMessage(e as Error); }
  }
  @Builder
  private Info() {
    if (this.album !== null) {
      Column({ space: 18 }) {
        Column() { SourceCover({ url: this.album.coverUrl, deriveColor: true, onColor: (color: string): void => { this.coverTint = color; } }) }.width(this.breakpoint === 'sm' ? 160 : 220).alignSelf(ItemAlign.Center)
        Text(this.album.name).fontSize(28).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN).width('100%')
        if (this.album.author.length > 0) { Text(this.album.author.join(' · ')).fontColor(TEXT_SUB).fontSize(14).width('100%') }
        Row({ space: 10 }) {
          Text(this.sourceName).fontColor(PRIMARY).fontSize(12).padding(8).backgroundColor(CHIP_BG).borderRadius(10)
          Text(`${this.album.episodes.length} 章`).fontSize(12).fontColor(TEXT_SUB)
        }.width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.album.tags, (tag: string) => { Text(tag).fontColor(TEXT_SUB).fontSize(11).padding(6).margin(3).backgroundColor(CARD).borderRadius(8) })
        }.width('100%')
        if (this.album.description !== '') { Text(this.album.description).fontColor(TEXT_SUB).fontSize(14).width('100%') }
        Row({ space: 10 }) {
          Button(this.progress === null ? '开始阅读' : '继续阅读').backgroundColor(PRIMARY).layoutWeight(1).onClick(() => { this.read(); })
          Button(this.work === null ? '加入书架' : '已在书架').enabled(this.work === null).onClick(() => { this.add(); })
        }.width('100%')
        Row({ space: 10 }) {
          Button('下载漫画').onClick(() => { this.download(); })
          Button('切换书源').onClick(() => { this.sourceSheet = true; })
        }.width('100%')
        if (sourceId(this.aid) === 'jm') {
          Button('查看评论').onClick(() => { this.loadComments(); })
          ForEach(this.comments, (comment: CommentItem) => {
            Column({ space: 6 }) { Text(comment.nickname).fontColor(PRIMARY).fontSize(12); Text(comment.content).fontColor(TEXT_MAIN).fontSize(13) }
              .alignItems(HorizontalAlign.Start).width('100%').padding(12).backgroundColor(CARD).borderRadius(12)
          })
        }
      }.padding(24).alignItems(HorizontalAlign.Start).width('100%').linearGradient({ angle: 180, colors: [[this.coverTint, 0], [BG, 1]] })
    }
  }
  @Builder
  private Chapters() {
    Column({ space: 12 }) {
      Row() {
        Text('章节').fontSize(22).fontColor(TEXT_MAIN).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button(this.ascending ? '正序' : '倒序').onClick(() => { this.ascending = !this.ascending; })
        Button(this.unread ? '仅未读' : '全部').onClick(() => { this.unread = !this.unread; })
      }.width('100%')
      TextInput({ text: this.filter, placeholder: '搜索章节或版本' }).onChange((value: string) => { this.filter = value; })
      ForEach(this.chapters(), (chapter: Chapter) => {
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text(chapter.title || `第 ${chapter.sort} 章`).fontColor(this.progress?.chapterId === chapter.id ? PRIMARY : TEXT_MAIN).fontSize(15).maxLines(2)
            if (this.progress?.chapterId === chapter.id) { Text(`读至第 ${this.progress!.page + 1} 页`).fontSize(11).fontColor(TEXT_SUB) }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(() => { this.read(chapter); })
          Button('预览').fontSize(12).onClick(() => { this.preview(chapter); })
        }.width('100%').padding(16).backgroundColor(CARD).borderRadius(16)
      }, (chapter: Chapter) => chapter.id)
      if (this.chapters().length === 0) { Text('暂无符合条件的章节').fontColor(TEXT_SUB).padding(32) }
    }.padding(20).width('100%')
  }
  @Builder
  private SourcesSheet() {
    Scroll() {
      Column({ space: 14 }) {
        Text('作品书源').fontColor(TEXT_MAIN).fontSize(24).fontWeight(FontWeight.Bold)
        if (this.work !== null) {
          ForEach(this.work.albums, (album: Album) => {
            Row() {
              Text(album.name).fontColor(TEXT_MAIN).layoutWeight(1).maxLines(2)
              Button(album.id === this.aid ? '当前' : '切换').enabled(album.id !== this.aid && !this.busy).onClick(() => { this.chooseSource(album); })
              if (this.work!.albums.length > 1) {
                Button('取消关联').onClick(() => { library.detach(album.id).then(() => { this.refresh(); }).catch((e: Error) => { this.error = errorMessage(e); }); })
              }
            }.width('100%')
          })
          Button('查找其他书源').width('100%').backgroundColor(PRIMARY).onClick(() => {
            this.sourceSheet = false; this.stack.pushPathByName(ROUTE_SEARCH, { matchAid: this.aid } as MangaRouteParams);
          })
        } else { Button('加入书架后关联书源').onClick(() => { this.add(); }) }
        if (this.error !== '') { Text(this.error).fontColor(TEXT_SUB) }
      }.padding(24).width('100%')
    }.width('100%')
  }
  @Builder
  private PreviewSheet() {
    Scroll() {
      Column({ space: 12 }) {
        ForEach(this.previewPages, (filename: string) => { PagePreview({ chapter: this.previewChapter, filename: filename, scramble: this.previewScramble }) })
      }.padding(20).width('100%')
    }.width('100%')
  }
  build() {
    NavDestination() {
      Column() {
        if (this.error !== '') { Text(this.error).fontColor(TEXT_SUB).padding(16).onClick(() => { this.load(this.aid); }) }
        if (this.busy && this.album === null) { LoadingProgress().width(40).height(40).margin(40) }
        if (this.breakpoint !== 'sm') {
          Row() {
            Scroll() { this.Info() }.width('40%').height('100%')
            Scroll() { this.Chapters() }.width('60%').height('100%')
          }.layoutWeight(1).width('100%')
        } else { Scroll() { Column() { this.Info(); this.Chapters() }.width('100%') }.layoutWeight(1).width('100%') }
      }.width('100%').height('100%').backgroundColor(BG)
      .bindSheet($$this.sourceSheet, this.SourcesSheet(), { height: '65%', dragBar: true })
      .bindSheet($$this.previewSheet, this.PreviewSheet(), { height: '80%', dragBar: true })
    }.title('漫画详情').onReady((context: NavDestinationContext) => {
      const params: Record<string, Object> | null = asRecord(context.pathInfo.param as Object);
      this.aid = params === null ? '' : asString(params['aid']);
      this.load(this.aid);
      this.sourceSheet = params !== null && params['match'] === true;
    }).onShown(() => { this.refresh(); }).onHidden(() => { this.generation++; })
  }
}
