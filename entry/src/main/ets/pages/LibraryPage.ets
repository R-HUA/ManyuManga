import promptAction from '@ohos.promptAction';
import uiMaterial from '@ohos.arkui.uiMaterial';
import { MangaRouteParams, ROUTE_ALBUM, ROUTE_SEARCH, ROUTE_READER } from '../common/Route';
import { library, LibraryWork } from '../data/Library';
import { sourceApi } from '../data/SourceApi';
import { localSource } from '../data/LocalSource';
import { readProgressStore } from '../data/Stores';
import { downloadManager, DownloadTask } from '../data/DownloadManager';
import { Album, ReadingProgress, errorMessage } from '../models/Models';
import { SourceCover } from '../common/SourceCover';
import { IconCircleButton } from '../common/Components';
import {
  BG,
  CARD,
  SUB_CARD,
  PRIMARY,
  PRIMARY_SOFT,
  ACCENT,
  DANGER,
  DANGER_SOFT,
  TEXT_MAIN,
  TEXT_SUB,
  CHIP_BG,
  DIVIDER,
  TAB_BAR_HEIGHT
} from '../common/Theme';
import { Prefs } from '../util/Prefs';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

@Component
export struct LibraryPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp('bookshelfDataVersion') @Watch('load') version: number = 0;
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 0;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  @StorageProp('currentBreakpoint') breakpoint: string = 'sm';
  @StorageProp('librarySelection') selecting: boolean = false;

  @State works: Array<LibraryWork> = [];
  @State progress: Array<ReadingProgress> = [];
  @State query: string = '';
  @State showSearch: boolean = false;
  @State hideContinueBanner: boolean = false;
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
  @State busyImport: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    this.selected = [];
    AppStorage.setOrCreate('librarySelection', false);
  }

  private async load(): Promise<void> {
    try {
      this.works = await library.list();
      this.progress = await readProgressStore.list();
      await downloadManager.init();
      this.downloaded = downloadManager.tasks
        .filter((t: DownloadTask) => t.state === 'done')
        .map((t: DownloadTask) => t.albumId);
      const categories: Array<string> = [];
      for (const work of this.works) {
        for (const c of work.categories) {
          if (!categories.includes(c)) {
            categories.push(c);
          }
        }
      }
      this.categories = categories;
      this.columns = await (await Prefs.getInstance()).getNumber('library_columns', 3);
      this.error = '';
    } catch (e) {
      this.error = errorMessage(e as Error);
    }
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
    return this.progress.find((p: ReadingProgress) => work.albums.some((a: Album) => a.id === p.aid))?.at ?? 0;
  }

  private workProgress(work: LibraryWork): ReadingProgress | undefined {
    return this.progress.find((p: ReadingProgress) => work.albums.some((a: Album) => a.id === p.aid));
  }

  private toggle(work: LibraryWork): void {
    this.selected = this.selected.includes(work.id)
      ? this.selected.filter((id: string) => id !== work.id)
      : this.selected.concat([work.id]);
    AppStorage.setOrCreate('librarySelection', this.selected.length > 0);
  }

  private selectAllOrClear(): void {
    const currentList: Array<LibraryWork> = this.filtered();
    if (this.selected.length >= currentList.length && currentList.length > 0) {
      this.selected = [];
      AppStorage.setOrCreate('librarySelection', false);
    } else {
      this.selected = currentList.map((w: LibraryWork) => w.id);
      AppStorage.setOrCreate('librarySelection', this.selected.length > 0);
    }
  }

  private async importLocalArchive(): Promise<void> {
    if (this.busyImport) {
      return;
    }
    this.busyImport = true;
    try {
      const album: Album | null = await localSource.importFiles('');
      if (album !== null) {
        await library.add(album);
        await this.load();
        promptAction.showToast({ message: `已导入《${album.name}》` });
      }
    } catch (e) {
      this.error = errorMessage(e as Error);
    } finally {
      this.busyImport = false;
    }
  }

  private async action(kind: string): Promise<void> {
    try {
      if (kind === 'remove') {
        await library.remove(this.selected);
      } else if (kind === 'read') {
        await library.markRead(this.selected, true);
      } else if (kind === 'unread') {
        await library.markRead(this.selected, false);
      } else if (kind === 'category') {
        await library.categorize(this.selected, this.categoryName.trim());
        this.categorySheet = false;
      } else if (kind === 'download') {
        for (const work of this.works.filter((w: LibraryWork) => this.selected.includes(w.id))) {
          await downloadManager.enqueue(await sourceApi.album(work.activeKey));
        }
        promptAction.showToast({ message: '已加入下载队列' });
      }
      this.selected = [];
      AppStorage.setOrCreate('librarySelection', false);
      await this.load();
    } catch (e) {
      this.error = errorMessage(e as Error);
    }
  }

  @Builder
  private SheetOptionPill(label: string, active: boolean, onTap: () => void) {
    Text(label)
      .fontSize(13)
      .fontWeight(active ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(active ? Color.White : TEXT_MAIN)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .borderRadius(16)
      .backgroundColor(active ? PRIMARY : SUB_CARD)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
      .onClick(() => {
        onTap();
      })
  }

  @Builder
  private FilterSheet() {
    Column({ space: 20 }) {
      Row() {
        Text('筛选与视图控制')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)
        if (this.readFilter !== 0 || this.downloadFilter !== 0 || this.sort !== 0) {
          Text('重置')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(PRIMARY)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor(PRIMARY_SOFT)
            .onClick(() => {
              this.readFilter = 0;
              this.downloadFilter = 0;
              this.sort = 0;
            })
        }
      }
      .width('100%')

      Column({ space: 10 }) {
        Text('排序方式')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SUB)
        Row({ space: 10 }) {
          this.SheetOptionPill('最近加入', this.sort === 0, () => { this.sort = 0; })
          this.SheetOptionPill('作品名称', this.sort === 1, () => { this.sort = 1; })
          this.SheetOptionPill('最近阅读', this.sort === 2, () => { this.sort = 2; })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Column({ space: 10 }) {
        Text('阅读状态')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SUB)
        Row({ space: 10 }) {
          this.SheetOptionPill('全部状态', this.readFilter === 0, () => { this.readFilter = 0; })
          this.SheetOptionPill('已读完', this.readFilter === 1, () => { this.readFilter = 1; })
          this.SheetOptionPill('未读完', this.readFilter === 2, () => { this.readFilter = 2; })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Column({ space: 10 }) {
        Text('离线状态')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SUB)
        Row({ space: 10 }) {
          this.SheetOptionPill('全部漫画', this.downloadFilter === 0, () => { this.downloadFilter = 0; })
          this.SheetOptionPill('已离线下载', this.downloadFilter === 1, () => { this.downloadFilter = 1; })
          this.SheetOptionPill('未离线', this.downloadFilter === 2, () => { this.downloadFilter = 2; })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Column({ space: 8 }) {
        Row() {
          Text('书架网格密度')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT_SUB)
            .layoutWeight(1)
          Text(`每行 ${this.columns} 部`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(PRIMARY)
        }
        .width('100%')

        Slider({ value: this.columns, min: 2, max: 6, step: 1, style: SliderStyle.OutSet })
          .selectedColor(PRIMARY)
          .trackColor(DIVIDER)
          .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
          .onChange((value: number) => {
            const cols: number = Math.round(value);
            this.columns = cols;
            (async (): Promise<void> => {
              await (await Prefs.getInstance()).putNumber('library_columns', cols);
            })().catch((e: Error) => {
              this.error = errorMessage(e);
            });
          })
      }
      .width('100%')

      Text('完成')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(44)
        .borderRadius(22)
        .backgroundColor(PRIMARY)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
        .onClick(() => {
          this.sheet = false;
        })
    }
    .padding({ left: 24, right: 24, top: 16, bottom: 28 + this.bottomInset })
    .width('100%')
  }

  @Builder
  private CategorySheet() {
    Column({ space: 18 }) {
      Text('设置作品分类')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .width('100%')

      TextInput({ text: this.categoryName, placeholder: '输入新分类名称（留空则移出分类）' })
        .height(44)
        .borderRadius(14)
        .backgroundColor(SUB_CARD)
        .fontColor(TEXT_MAIN)
        .placeholderColor(TEXT_SUB)
        .onChange((text: string) => {
          this.categoryName = text;
        })

      if (this.categories.length > 0) {
        Column({ space: 8 }) {
          Text('已有分类')
            .fontSize(12)
            .fontColor(TEXT_SUB)
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.categories, (cat: string) => {
              Text(cat)
                .fontSize(13)
                .fontColor(this.categoryName === cat ? Color.White : TEXT_MAIN)
                .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                .margin({ right: 8, bottom: 8 })
                .borderRadius(16)
                .backgroundColor(this.categoryName === cat ? PRIMARY : SUB_CARD)
                .onClick(() => {
                  this.categoryName = cat;
                })
            }, (cat: string) => cat)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }

      Row({ space: 12 }) {
        Text('取消')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_MAIN)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(44)
          .borderRadius(22)
          .backgroundColor(SUB_CARD)
          .onClick(() => {
            this.categorySheet = false;
          })
        Text('保存应用')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(44)
          .borderRadius(22)
          .backgroundColor(PRIMARY)
          .onClick(() => {
            this.action('category');
          })
      }
      .width('100%')
    }
    .padding({ left: 24, right: 24, top: 16, bottom: 28 + this.bottomInset })
    .width('100%')
  }

  @Builder
  private Cover(work: LibraryWork) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        SourceCover({ url: work.cover, radius: 12 })

        // Top-left & Top-right overlay row
        Row() {
          if (work.newChapters > 0) {
            Text(`+${work.newChapters}`)
              .fontColor(Color.White)
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .backgroundColor(PRIMARY)
              .borderRadius(9)
          } else if (work.albums.length > 1) {
            Text(`${work.albums.length} 源`)
              .fontColor(Color.White)
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .backgroundColor('rgba(14, 17, 26, 0.78)')
              .borderRadius(9)
          }
          Blank()
          if (this.selected.length > 0) {
            Stack({ alignContent: Alignment.Center }) {
              if (this.selected.includes(work.id)) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(13)
                  .fontColor([Color.White])
              }
            }
            .width(24)
            .height(24)
            .borderRadius(12)
            .backgroundColor(this.selected.includes(work.id) ? PRIMARY : 'rgba(14, 17, 26, 0.65)')
            .border({ width: 1.5, color: this.selected.includes(work.id) ? PRIMARY : 'rgba(255,255,255,0.65)' })
          }
        }
        .width('100%')
        .padding(7)

        // Bottom reading status bar inside cover
        if (this.workProgress(work) !== undefined) {
          Column() {
            Blank()
            Row() {
              Text(`读至 P.${this.workProgress(work)!.page + 1}`)
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor('rgba(255,255,255,0.92)')
                .maxLines(1)
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 14, bottom: 6 })
            .linearGradient({
              angle: 180,
              colors: [['rgba(0,0,0,0.0)', 0.0], ['rgba(8,10,16,0.84)', 1.0]]
            })
          }
          .width('100%')
          .height('100%')
          .borderRadius(12)
          .clip(true)
          .hitTestBehavior(HitTestMode.None)
        }
      }
      .width('100%')
      .aspectRatio(0.75)

      Text(work.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_MAIN)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(work.author || (work.read ? '已读完' : '未读'))
        .fontSize(11)
        .fontColor(TEXT_SUB)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .onClick(() => {
      if (this.selected.length > 0) {
        this.toggle(work);
      } else {
        this.stack.pushPathByName(ROUTE_ALBUM, { aid: work.activeKey } as MangaRouteParams);
      }
    })
    .gesture(LongPressGesture().onAction(() => {
      this.toggle(work);
    }))
  }

  @Builder
  private TopBar() {
    Row({ space: 10 }) {
      if (this.selected.length > 0) {
        IconCircleButton({
          glyph: $r('sys.symbol.xmark'),
          onTap: (): void => {
            this.selected = [];
            AppStorage.setOrCreate('librarySelection', false);
          }
        })
        Text(`已选 ${this.selected.length} 部`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)
        Text(this.selected.length >= this.filtered().length && this.filtered().length > 0 ? '清空' : '全选')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(PRIMARY)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(18)
          .backgroundColor(PRIMARY_SOFT)
          .onClick(() => {
            this.selectAllOrClear();
          })
      } else {
        Row({ space: 8 }) {
          Text('书架')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_MAIN)
          Text(`${this.filtered().length}`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(PRIMARY)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
            .backgroundColor(PRIMARY_SOFT)
        }
        .alignItems(VerticalAlign.Center)
        .layoutWeight(1)

        IconCircleButton({
          glyph: $r('sys.symbol.magnifyingglass'),
          active: this.showSearch || this.query !== '',
          onTap: (): void => {
            this.showSearch = !this.showSearch;
            if (!this.showSearch) {
              this.query = '';
            }
          }
        })
        IconCircleButton({
          glyph: $r('sys.symbol.square_grid_2x2'),
          onTap: (): void => {
            this.stack.pushPathByName(ROUTE_SEARCH, {} as MangaRouteParams);
          }
        })
        IconCircleButton({
          glyph: $r('sys.symbol.folder_badge_plus'),
          onTap: (): void => {
            this.importLocalArchive();
          }
        })
        IconCircleButton({
          glyph: $r('sys.symbol.slider_horizontal_2'),
          active: this.readFilter !== 0 || this.downloadFilter !== 0 || this.sort !== 0,
          onTap: (): void => {
            this.sheet = true;
          }
        })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topInset + 10, bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private CategoryCapsule(label: string, active: boolean, onTap: () => void) {
    Text(label)
      .fontSize(13)
      .fontWeight(active ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(active ? Color.White : TEXT_SUB)
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(active ? PRIMARY : CARD)
      .border({ width: 0.5, color: active ? PRIMARY : DIVIDER })
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
      .onClick(() => {
        onTap();
      })
  }

  @Builder
  private BatchActionPill(label: string, isDanger: boolean, enabled: boolean, onTap: () => void) {
    Text(label)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(!enabled ? TEXT_SUB : (isDanger ? DANGER : TEXT_MAIN))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 10, bottom: 10 })
      .borderRadius(16)
      .backgroundColor(isDanger ? DANGER_SOFT : SUB_CARD)
      .opacity(enabled ? 1.0 : 0.45)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
      .onClick(() => {
        if (enabled) {
          onTap();
        }
      })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: 10 }) {
        this.TopBar()

        if (this.showSearch || this.query !== '') {
          Row({ space: 8 }) {
            Search({ value: this.query, placeholder: '检索书架标题或作者…' })
              .layoutWeight(1)
              .height(40)
              .backgroundColor(CARD)
              .onChange((text: string) => {
                this.query = text;
              })
            if (this.query.trim() !== '') {
              Text('搜全源')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .borderRadius(18)
                .backgroundColor(PRIMARY)
                .onClick(() => {
                  this.stack.pushPathByName(ROUTE_SEARCH, { query: this.query.trim() } as MangaRouteParams);
                })
            }
          }
          .padding({ left: 16, right: 16 })
          .width('100%')
        }

        // Category & Quick Filter Capsule Rail
        Scroll() {
          Row({ space: 8 }) {
            this.CategoryCapsule('全部', this.category === '' && this.readFilter === 0 && this.downloadFilter === 0, () => {
              this.category = '';
              this.readFilter = 0;
              this.downloadFilter = 0;
            })
            this.CategoryCapsule('未读', this.readFilter === 2, () => {
              this.readFilter = this.readFilter === 2 ? 0 : 2;
            })
            this.CategoryCapsule('已离线', this.downloadFilter === 1, () => {
              this.downloadFilter = this.downloadFilter === 1 ? 0 : 1;
            })
            ForEach(this.categories, (c: string) => {
              this.CategoryCapsule(c, this.category === c, () => {
                this.category = this.category === c ? '' : c;
              })
            }, (c: string) => c)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')

        if (this.error !== '') {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(16)
              .fontColor([DANGER])
            Text(this.error)
              .fontSize(12)
              .fontColor(TEXT_SUB)
              .layoutWeight(1)
              .maxLines(2)
            Text('重试')
              .fontSize(12)
              .fontColor(PRIMARY)
              .onClick(() => {
                this.load();
              })
          }
          .padding(12)
          .margin({ left: 16, right: 16 })
          .borderRadius(14)
          .backgroundColor(CARD)
        }

        if (this.filtered().length === 0) {
          Column({ space: 14 }) {
            Stack({ alignContent: Alignment.Center }) {
              SymbolGlyph($r('sys.symbol.books_vertical_fill'))
                .fontSize(32)
                .fontColor([PRIMARY])
            }
            .width(68)
            .height(68)
            .borderRadius(34)
            .backgroundColor(PRIMARY_SOFT)

            Text(this.works.length === 0 ? '书架还没有收藏漫画' : '没有符合当前筛选的漫画')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_MAIN)
            Text(this.works.length === 0 ? '去图源发现广场探索，或直接导入本地 CBZ/ZIP 漫画包' : '可以尝试切换分类胶囊或重置筛选条件')
              .fontSize(12)
              .fontColor(TEXT_SUB)
              .textAlign(TextAlign.Center)
              .padding({ left: 36, right: 36 })

            Row({ space: 12 }) {
              if (this.works.length === 0) {
                Text('探索图源广场')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .padding({ left: 18, right: 18, top: 10, bottom: 10 })
                  .borderRadius(20)
                  .backgroundColor(PRIMARY)
                  .onClick(() => {
                    AppStorage.setOrCreate('mainTabIndex', 2);
                  })
                Text('导入本地漫画')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(TEXT_MAIN)
                  .padding({ left: 18, right: 18, top: 10, bottom: 10 })
                  .borderRadius(20)
                  .backgroundColor(CARD)
                  .border({ width: 0.5, color: DIVIDER })
                  .onClick(() => {
                    this.importLocalArchive();
                  })
              } else {
                Text('重置筛选')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .padding({ left: 18, right: 18, top: 10, bottom: 10 })
                  .borderRadius(20)
                  .backgroundColor(PRIMARY)
                  .onClick(() => {
                    this.query = '';
                    this.category = '';
                    this.readFilter = 0;
                    this.downloadFilter = 0;
                  })
              }
            }
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .padding({ bottom: TAB_BAR_HEIGHT + this.bottomInset })
        } else {
          Grid() {
            ForEach(this.filtered(), (work: LibraryWork) => {
              GridItem() {
                this.Cover(work)
              }
            }, (work: LibraryWork) => `${work.id}_${this.selected.includes(work.id)}_${work.newChapters}_${work.read}`)
          }
          .columnsTemplate(`repeat(${this.columns}, 1fr)`)
          .columnsGap(12)
          .rowsGap(16)
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({
            left: 16,
            right: 16,
            top: 4,
            bottom: (this.breakpoint === 'lg' ? 88 : TAB_BAR_HEIGHT + 92) + this.bottomInset
          })
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')

      // Floating L1 Continue Reading Capsule
      if (this.progress.length > 0 && this.selected.length === 0 && !this.hideContinueBanner) {
        Row({ space: 12 }) {
          Column() {
            SourceCover({ url: this.progress[0].coverUrl, radius: 8 })
          }
          .width(36)
          .height(48)

          Column({ space: 3 }) {
            Text(`继续阅读 · 第 ${this.progress[0].page + 1}/${Math.max(1, this.progress[0].totalPages)} 页`)
              .fontColor(PRIMARY)
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
            Text(this.progress[0].title)
              .fontColor(TEXT_MAIN)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Text('续读')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .borderRadius(16)
            .backgroundColor(PRIMARY)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
            .onClick(() => {
              this.stack.pushPathByName(ROUTE_READER, { aid: this.progress[0].aid } as MangaRouteParams);
            })

          IconCircleButton({
            glyph: $r('sys.symbol.xmark'),
            btnSize: 28,
            iconSize: 13,
            onTap: (): void => {
              this.hideContinueBanner = true;
            }
          })
        }
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .margin({
          left: 16,
          right: 16,
          bottom: (this.breakpoint === 'lg' ? 16 : TAB_BAR_HEIGHT + 14) + this.bottomInset
        })
        .borderRadius(20)
        .backgroundColor(CARD)
        .border({ width: 0.5, color: DIVIDER })
        .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
      }

      // Bottom Batch Action Bar in Selection Mode
      if (this.selected.length > 0) {
        Row({ space: 8 }) {
          this.BatchActionPill('分类', false, true, () => {
            this.categorySheet = true;
          })
          this.BatchActionPill('标已读', false, true, () => {
            this.action('read');
          })
          this.BatchActionPill('下载', false, true, () => {
            this.action('download');
          })
          this.BatchActionPill('换源', false, this.selected.length === 1, () => {
            const work: LibraryWork | undefined = this.works.find((w: LibraryWork) => w.id === this.selected[0]);
            if (work !== undefined) {
              this.stack.pushPathByName(ROUTE_ALBUM, { aid: work.activeKey, match: true } as MangaRouteParams);
            }
          })
          this.BatchActionPill('移除', true, true, () => {
            this.getUIContext().showAlertDialog({
              title: '移出书架',
              message: `确认将所选的 ${this.selected.length} 部漫画移出书架吗？阅读记录与已下载文件会保留。`,
              primaryButton: { value: '取消', action: () => {} },
              secondaryButton: {
                value: '移除',
                fontColor: DANGER,
                action: () => {
                  this.action('remove');
                }
              }
            });
          })
        }
        .padding({ left: 14, right: 14, top: 12, bottom: 12 + this.bottomInset })
        .width('100%')
        .backgroundColor(CARD)
        .border({ width: { top: 0.5 }, color: DIVIDER })
        .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK }))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
    .bindSheet($$this.sheet, this.FilterSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: CARD,
      systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK })
    })
    .bindSheet($$this.categorySheet, this.CategorySheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: CARD,
      systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK })
    })
  }
}
