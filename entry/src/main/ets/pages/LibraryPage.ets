import promptAction from '@ohos.promptAction';
import { MangaRouteParams } from '../common/Route';
import { library, LibraryWork } from '../data/Library';
import { sourceApi } from '../data/SourceApi';
import { readProgressStore } from '../data/Stores';
import { downloadManager, DownloadTask } from '../data/DownloadManager';
import { ReadingProgress, errorMessage } from '../models/Models';
import { SourceCover } from '../common/SourceCover';
import { BG, CARD, PRIMARY, TEXT_MAIN, TEXT_SUB, CHIP_BG } from '../common/Theme';
import { ROUTE_ALBUM, ROUTE_SEARCH, ROUTE_READER } from '../common/Route';
import { Prefs } from '../util/Prefs';

@Component
export struct LibraryPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp('bookshelfDataVersion') @Watch('load') version: number = 0;
  @StorageProp('topRectHeight') topInset: number = 0;
  @StorageProp('librarySelection') selecting: boolean = false;
  @State works: Array<LibraryWork> = [];
  @State progress: Array<ReadingProgress> = [];
  @State query: string = '';
  @State category: string = '';
  @State categories: Array<string> = [];
  @State selected: Array<string> = [];
  @State downloaded: Array<string> = [];
  @State columns: number = 3;
  @State sort: number = 0;
  @State readFilter: number = 0;
  @State downloadFilter: number = 0;
  @State sheet: boolean = false;
  @State categorySheet: boolean = false;
  @State categoryName: string = '';
  @State error: string = '';
  aboutToAppear(): void { this.load(); }
  aboutToDisappear(): void { this.selected = []; AppStorage.setOrCreate('librarySelection', false); }
  private async load(): Promise<void> {
    try {
      this.works = await library.list();
      this.progress = await readProgressStore.list();
      await downloadManager.init();
      this.downloaded = downloadManager.tasks.filter((t: DownloadTask) => t.state === 'done').map((t: DownloadTask) => t.albumId);
      const categories: Array<string> = [];
      for (const work of this.works) { for (const c of work.categories) { if (!categories.includes(c)) { categories.push(c); } } }
      this.categories = categories;
      this.columns = await (await Prefs.getInstance()).getNumber('library_columns', 3);
      this.error = '';
    } catch (e) { this.error = errorMessage(e as Error); }
  }
  private filtered(): Array<LibraryWork> {
    return this.works.filter((w: LibraryWork) =>
      `${w.title} ${w.author}`.toLowerCase().includes(this.query.toLowerCase()) &&
      (this.category === '' || w.categories.includes(this.category)) &&
      (this.readFilter === 0 || (this.readFilter === 1 ? w.read : !w.read)) &&
      (this.downloadFilter === 0 || (this.downloadFilter === 1 ? this.downloaded.includes(w.activeKey) : !this.downloaded.includes(w.activeKey))))
      .sort((a: LibraryWork, b: LibraryWork) => this.sort === 1 ? a.title.localeCompare(b.title, 'zh')
        : this.sort === 2 ? this.lastRead(b) - this.lastRead(a) : b.addedAt - a.addedAt);
  }
  private lastRead(work: LibraryWork): number {
    return this.progress.find((p: ReadingProgress) => work.albums.some((a) => a.id === p.aid))?.at ?? 0;
  }
  private toggle(work: LibraryWork): void {
    this.selected = this.selected.includes(work.id) ? this.selected.filter((id: string) => id !== work.id) : this.selected.concat([work.id]);
    AppStorage.setOrCreate('librarySelection', this.selected.length > 0);
  }
  private async action(kind: string): Promise<void> {
    try {
      if (kind === 'remove') { await library.remove(this.selected); }
      else if (kind === 'read') { await library.markRead(this.selected, true); }
      else if (kind === 'category') { await library.categorize(this.selected, this.categoryName); this.categorySheet = false; }
      else if (kind === 'download') {
        for (const work of this.works.filter((w: LibraryWork) => this.selected.includes(w.id))) {
          await downloadManager.enqueue(await sourceApi.album(work.activeKey));
        }
        promptAction.showToast({ message: '已加入下载队列' });
      }
      this.selected = [];
      AppStorage.setOrCreate('librarySelection', false);
      await this.load();
    } catch (e) { this.error = errorMessage(e as Error); }
  }
  @Builder
  private FilterSheet() {
    Column({ space: 18 }) {
      Text('筛选与显示').fontSize(22).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN)
      Select([{ value: '全部阅读状态' }, { value: '已读' }, { value: '未读' }]).selected(this.readFilter)
        .onSelect((index: number) => { this.readFilter = index; })
      Select([{ value: '全部下载状态' }, { value: '已下载' }, { value: '未下载' }]).selected(this.downloadFilter)
        .onSelect((index: number) => { this.downloadFilter = index; })
      Select([{ value: '最近加入' }, { value: '作品名称' }, { value: '最近阅读' }]).selected(this.sort)
        .onSelect((index: number) => { this.sort = index; })
      Text(`每行 ${this.columns} 本`).fontColor(TEXT_MAIN)
      Slider({ value: this.columns, min: 2, max: 6, step: 1 }).onChange((value: number) => {
        this.columns = value;
        (async (): Promise<void> => { await (await Prefs.getInstance()).putNumber('library_columns', value); })()
          .catch((e: Error) => { this.error = errorMessage(e); });
      })
      Button('完成').onClick(() => { this.sheet = false; }).backgroundColor(PRIMARY).width('100%')
    }.padding(24).width('100%')
  }
  @Builder
  private CategorySheet() {
    Column({ space: 20 }) {
      Text('移动到分类').fontSize(22).fontColor(TEXT_MAIN)
      TextInput({ text: this.categoryName, placeholder: '分类名称，留空移出分类' }).onChange((text: string) => { this.categoryName = text; })
      ForEach(this.categories, (category: string) => {
        Button(category).onClick(() => { this.categoryName = category; })
      })
      Button('保存').width('100%').backgroundColor(PRIMARY).onClick(() => { this.action('category'); })
    }.padding(24).width('100%')
  }
  @Builder
  private Cover(work: LibraryWork) {
    Column({ space: 7 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        SourceCover({ url: work.cover })
        if (this.selected.includes(work.id)) {
          Text('✓').fontColor(Color.White).padding(6).backgroundColor(PRIMARY).borderRadius(16).margin(6)
        } else if (work.newChapters > 0) {
          Text(`${work.newChapters}`).fontColor(Color.White).fontSize(11).padding(6).backgroundColor(PRIMARY).borderRadius(10).margin(6)
        }
      }.width('100%')
      Text(work.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor(TEXT_MAIN).maxLines(2).width('100%')
      Text(work.author || (work.read ? '已读' : '未读')).fontSize(11).fontColor(TEXT_SUB).maxLines(1).width('100%')
    }.alignItems(HorizontalAlign.Start).width('100%')
    .onClick(() => {
      if (this.selected.length > 0) { this.toggle(work); }
      else { this.stack.pushPathByName(ROUTE_ALBUM, { aid: work.activeKey } as MangaRouteParams); }
    })
    .gesture(LongPressGesture().onAction(() => { this.toggle(work); }))
  }
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: 12 }) {
        Row() {
          Text(this.selected.length > 0 ? `已选择 ${this.selected.length} 本` : '书架').fontSize(30).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN).layoutWeight(1)
          if (this.selected.length > 0) {
            Button('取消').onClick(() => { this.selected = []; AppStorage.setOrCreate('librarySelection', false); })
          } else {
            Button('搜索').onClick(() => { this.stack.pushPathByName(ROUTE_SEARCH, {} as MangaRouteParams); })
            Button('筛选').margin({ left: 8 }).onClick(() => { this.sheet = true; })
          }
        }.width('100%').padding({ left: 20, right: 20, top: this.topInset + 12 })
        TextInput({ text: this.query, placeholder: '搜索书架' }).margin({ left: 20, right: 20 }).onChange((text: string) => { this.query = text; })
        Scroll() {
          Row({ space: 10 }) {
            Button('全部').fontColor(this.category === '' ? Color.White : TEXT_MAIN).backgroundColor(this.category === '' ? PRIMARY : CARD)
              .onClick(() => { this.category = ''; })
            ForEach(this.categories, (c: string) => {
              Button(c).fontColor(this.category === c ? Color.White : TEXT_MAIN).backgroundColor(this.category === c ? PRIMARY : CARD)
                .onClick(() => { this.category = c; })
            })
          }.padding({ left: 20, right: 20 })
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        if (this.error !== '') { Text(this.error).fontColor(TEXT_SUB).padding(16).onClick(() => { this.load(); }) }
        if (this.progress.length > 0 && this.selected.length === 0) {
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text('继续阅读').fontColor(PRIMARY).fontSize(12)
              Text(this.progress[0].title).fontColor(TEXT_MAIN).maxLines(1).fontWeight(FontWeight.Bold)
              Text(`第 ${this.progress[0].page + 1} / ${this.progress[0].totalPages} 页`).fontSize(12).fontColor(TEXT_SUB)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Button('继续').backgroundColor(PRIMARY).onClick(() => { this.stack.pushPathByName(ROUTE_READER, { aid: this.progress[0].aid } as MangaRouteParams); })
          }.padding(16).margin({ left: 20, right: 20 }).backgroundColor(CARD).borderRadius(20)
        }
        if (this.filtered().length === 0) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.book')).fontSize(48).fontColor([TEXT_SUB])
            Text(this.works.length === 0 ? '把喜欢的漫画加入书架' : '没有符合条件的漫画').fontColor(TEXT_MAIN)
            if (this.works.length === 0) { Button('浏览书源').onClick(() => { AppStorage.setOrCreate('mainTabIndex', 2); }) }
          }.layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
        } else {
          Grid() {
            ForEach(this.filtered(), (work: LibraryWork) => { GridItem() { this.Cover(work) } }, (work: LibraryWork) => work.id)
          }.columnsTemplate(`repeat(${this.columns}, 1fr)`).columnsGap(12).rowsGap(18).layoutWeight(1)
          .padding({ left: 20, right: 20, bottom: 110 }).width('100%')
        }
      }.width('100%').height('100%')
      if (this.selected.length > 0) {
        Row({ space: 6 }) {
          Button('分类').onClick(() => { this.categorySheet = true; })
          Button('已读').onClick(() => { this.action('read'); })
          Button('下载').onClick(() => { this.action('download'); })
          Button('换源').onClick(() => {
            const work: LibraryWork = this.works.find((w: LibraryWork) => w.id === this.selected[0])!;
            this.stack.pushPathByName(ROUTE_ALBUM, { aid: work.activeKey, match: true } as MangaRouteParams);
          })
          Button('移除').onClick(() => { AlertDialog.show({ title: '移出书架', message: '阅读记录与已下载文件会保留。',
            primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '移除', action: () => { this.action('remove'); } } }); })
        }.padding(12).width('100%').backgroundColor(CARD).margin({ bottom: 24 })
      }
    }.width('100%').height('100%').backgroundColor(BG)
    .bindSheet($$this.sheet, this.FilterSheet(), { height: 460, dragBar: true })
    .bindSheet($$this.categorySheet, this.CategorySheet(), { height: 420, dragBar: true })
  }
}
