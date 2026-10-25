import { library, LibraryWork } from '../data/Library';
import { MangaRouteParams } from '../common/Route';
import { sourceApi } from '../data/SourceApi';
import { readProgressStore, historyStore } from '../data/Stores';
import { ReadingProgress, HistoryItem, Album, errorMessage } from '../models/Models';
import { SourceCover } from '../common/SourceCover';
import { BG, CARD, TEXT_MAIN, TEXT_SUB, PRIMARY } from '../common/Theme';
import { ROUTE_ALBUM, ROUTE_READER, ROUTE_DOWNLOADS } from '../common/Route';

@Component
export struct UpdatesPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp('topRectHeight') topInset: number = 0;
  @StorageProp('mainTabIndex') @Watch('tabChanged') tab: number = 0;
  @StorageProp('bookshelfDataVersion') @Watch('load') version: number = 0;
  @State works: Array<LibraryWork> = [];
  @State recent: Array<ReadingProgress> = [];
  @State history: Array<HistoryItem> = [];
  @State errors: Array<string> = [];
  @State busy: boolean = false;
  @State section: number = 0;
  private generation: number = 0;
  aboutToAppear(): void { this.load(); }
  aboutToDisappear(): void { this.generation++; }
  private tabChanged(): void { if (this.tab === 1) { this.refresh(); } else { this.generation++; this.busy = false; } }
  private async load(): Promise<void> {
    try { this.works = await library.list(); this.recent = await readProgressStore.list(); this.history = await historyStore.getList(); }
    catch (e) { this.errors = [errorMessage(e as Error)]; }
  }
  private async refresh(): Promise<void> {
    const ticket: number = ++this.generation;
    this.busy = true; this.errors = [];
    try {
      const works: Array<LibraryWork> = await library.list();
      let cursor: number = 0;
      const worker = async (): Promise<void> => {
        while (cursor < works.length && ticket === this.generation) {
          const work: LibraryWork = works[cursor++];
          try {
            const album: Album = await sourceApi.album(work.activeKey, true);
            if (ticket !== this.generation) { return; }
            await library.updateSnapshot(album);
          } catch (e) { if (ticket === this.generation) { this.errors = this.errors.concat([`${work.title}：${errorMessage(e as Error)}`]); } }
        }
      };
      await Promise.all([worker(), worker(), worker()]);
      if (ticket === this.generation) { await this.load(); }
    } catch (e) { if (ticket === this.generation) { this.errors = [errorMessage(e as Error)]; } }
    finally { if (ticket === this.generation) { this.busy = false; } }
  }
  @Builder
  private Entry(title: string, cover: string, subtitle: string, key: string, reading: boolean) {
    Row({ space: 14 }) {
      Column() { SourceCover({ url: cover }) }.width(66)
      Column({ space: 6 }) {
        Text(title).fontColor(TEXT_MAIN).fontWeight(FontWeight.Bold).maxLines(2)
        Text(subtitle).fontColor(TEXT_SUB).fontSize(12)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('›').fontColor(PRIMARY).fontSize(24)
    }.padding(14).width('100%').backgroundColor(CARD).borderRadius(20)
    .onClick(() => { this.stack.pushPathByName(reading ? ROUTE_READER : ROUTE_ALBUM, { aid: key } as MangaRouteParams); })
  }
  build() {
    Column({ space: 16 }) {
      Row() {
        Text('更新').fontSize(30).fontColor(TEXT_MAIN).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button(this.busy ? '检查中…' : '检查更新').enabled(!this.busy).onClick(() => { this.refresh(); })
      }.padding({ left: 20, right: 20, top: this.topInset + 12 }).width('100%')
      Row({ space: 8 }) {
        Button('最新章节').backgroundColor(this.section === 0 ? PRIMARY : CARD).fontColor(this.section === 0 ? Color.White : TEXT_MAIN).onClick(() => { this.section = 0; })
        Button('最近阅读').backgroundColor(this.section === 1 ? PRIMARY : CARD).fontColor(this.section === 1 ? Color.White : TEXT_MAIN).onClick(() => { this.section = 1; })
        Button('浏览记录').backgroundColor(this.section === 2 ? PRIMARY : CARD).fontColor(this.section === 2 ? Color.White : TEXT_MAIN).onClick(() => { this.section = 2; })
        Button('下载').onClick(() => { this.stack.pushPathByName(ROUTE_DOWNLOADS, {} as MangaRouteParams); })
      }.width('100%').padding({ left: 16, right: 16 })
      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.errors, (error: string) => { Text(error).fontSize(12).fontColor(TEXT_SUB).width('100%') })
          if (this.section === 0) {
            ForEach(this.works.filter((w: LibraryWork) => w.newChapters > 0), (w: LibraryWork) => {
              this.Entry(w.title, w.cover, `${w.newChapters} 个新章节`, w.activeKey, false)
            })
            if (!this.works.some((w: LibraryWork) => w.newChapters > 0)) { Text('暂无新章节').fontColor(TEXT_SUB).padding(40) }
          } else if (this.section === 1) {
            ForEach(this.recent, (p: ReadingProgress) => {
              this.Entry(p.title, p.coverUrl, `${new Date(p.at).toLocaleDateString()} · 第 ${p.page + 1} / ${p.totalPages} 页`, p.aid, true)
            })
            if (this.recent.length === 0) { Text('还没有阅读记录').fontColor(TEXT_SUB).padding(40) }
          } else {
            ForEach(this.history, (h: HistoryItem) => { this.Entry(h.title, h.coverUrl, new Date(h.viewedAt).toLocaleDateString(), h.id, false) })
            if (this.history.length === 0) { Text('还没有浏览记录').fontColor(TEXT_SUB).padding(40) }
          }
        }.padding({ left: 20, right: 20, bottom: 110 }).width('100%')
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor(BG)
  }
}
