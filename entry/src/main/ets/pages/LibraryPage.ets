import { HdsNavigation, HdsNavigationMenuItemOptions, HdsNavigationTitleMode, TitleSize } from '@kit.UIDesignKit';
import { LibraryCoverCard } from './library/LibraryCoverCard';
import { LibraryCategorySheet } from './library/LibraryCategorySheet';
import { LibraryFilterSheet } from './library/LibraryFilterSheet';
import promptAction from '@ohos.promptAction';
import { IMMERSIVE_SHEET_MATERIAL, HDS_TITLE_STYLE } from '../common/ImmersiveMaterials';
import { MangaRouteParams, ROUTE_ALBUM, ROUTE_SEARCH } from '../common/Route';
import { library, LibraryWork } from '../data/Library';
import { albumMatchesText } from '../data/SearchQuery';
import { offlineStore } from '../data/OfflineStore';
import { downloadManager } from '../data/DownloadManager';
import { sourceApi } from '../data/SourceApi';
import { readProgressStore } from '../data/Stores';
import { Album, ReadingProgress, errorMessage } from '../models/Models';
import { BG, CARD, SUB_CARD, PRIMARY, PRIMARY_SOFT, DANGER, TEXT_MAIN, TEXT_SUB, TAB_BAR_HEIGHT, comicColumns } from '../common/Theme';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';
import { ToolBarOptions } from '@kit.ArkUI';
import { SelectionToolBar, ToolAction, buildToolBar, TOOLBAR_HEIGHT } from '../common/SelectionToolBar';

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
  @State category: string = '';
  @State categories: Array<string> = [];
  @State @Watch('syncToolbar') selected: Array<string> = [];
  @State toolbar: ToolBarOptions = new ToolBarOptions();
  @State downloaded: Array<string> = [];
  @State private contentWidth: number = 328;
  private scroller: Scroller = new Scroller();
  @State sort: number = 0;
  @State readFilter: number = 0;
  @State downloadFilter: number = 0;
  @State sheet: boolean = false;
  @State categorySheet: boolean = false;
  @State categoryName: string = '';
  @State error: string = '';

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
      this.downloaded = await offlineStore.albumIds();
      const categories: Array<string> = [];
      for (const work of this.works) {
        for (const c of work.categories) {
          if (!categories.includes(c)) {
            categories.push(c);
          }
        }
      }
      this.categories = categories;
      this.error = '';
    } catch (e) {
      this.error = errorMessage(e as Error);
    }
  }

  private filtered(): Array<LibraryWork> {
    return this.works.filter((w: LibraryWork) =>
      (`${w.title} ${w.author}`.toLowerCase().includes(this.query.toLowerCase()) ||
        w.albums.some((album: Album): boolean => albumMatchesText(album, this.query))) &&
      (this.category === '' || w.categories.includes(this.category)) &&
      (this.readFilter === 0 || (this.readFilter === 1 ? w.read : !w.read)) &&
      (this.downloadFilter === 0 || (this.downloadFilter === 1 ? this.downloaded.includes(w.activeKey) : !this.downloaded.includes(w.activeKey))))
      .sort((a: LibraryWork, b: LibraryWork) => this.sort === 1 ? a.title.localeCompare(b.title, 'zh')
        : this.sort === 2 ? this.lastRead(b) - this.lastRead(a) : b.addedAt - a.addedAt);
  }

  private lastRead(work: LibraryWork): number {
    return this.progress.find((p: ReadingProgress) => work.albums.some((a: Album) => a.id === p.aid))?.at ?? 0;
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
  private FilterSheet() {
    LibraryFilterSheet({
      category: this.$category,
      categories: this.$categories,
      readFilter: this.$readFilter,
      downloadFilter: this.$downloadFilter,
      sort: this.$sort,
      error: this.$error,
      sheet: this.$sheet
    })
  }

  @Builder
  private CategorySheet() {
    LibraryCategorySheet({
      categoryName: this.$categoryName,
      categories: this.$categories,
      categorySheet: this.$categorySheet,
      action: (kind: string): Promise<void> => this.action(kind)
    })
  }

  @Builder
  private Cover(work: LibraryWork) {
    LibraryCoverCard({
      selected: this.$selected,
      progress: this.$progress,
      toggle: (work: LibraryWork): void => this.toggle(work),
      work: work
    })
  }

  /** 多选工具栏：分类 / 下载 / 移除（红色警告色）+ 更多（标已读、换源），符合 4+1 上限。 */
  private syncToolbar(): void {
    this.toolbar = buildToolBar([
      new ToolAction('分类', $r('sys.symbol.label'), true, false, (): void => { this.categorySheet = true; }),
      new ToolAction('下载', $r('sys.symbol.arrow_down_circle'), true, false, (): void => { this.action('download'); }),
      new ToolAction('移除', $r('sys.symbol.trash'), true, true, (): void => { this.confirmRemove(); }),
      new ToolAction('更多', $r('sys.symbol.ellipsis_circle'), true, false, (): void => { this.showMore(); })
    ]);
  }

  private confirmRemove(): void {
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
  }

  private showMore(): void {
    const single: boolean = this.selected.length === 1;
    this.getUIContext().getPromptAction().showActionMenu({
      title: '更多',
      buttons: [{ text: '标为已读', color: TEXT_MAIN }, { text: single ? '换源' : '换源（仅限单选）', color: single ? TEXT_MAIN : TEXT_SUB }]
    }).then((picked: promptAction.ActionMenuSuccessResponse): void => {
      if (picked.index === 0) {
        this.action('read');
      } else if (picked.index === 1 && this.selected.length === 1) {
        const work: LibraryWork | undefined = this.works.find((w: LibraryWork) => w.id === this.selected[0]);
        if (work !== undefined) {
          this.stack.pushPathByName(ROUTE_ALBUM, { aid: work.activeKey, match: true, fromLibrary: true } as MangaRouteParams);
        }
      }
    }).catch((): void => {});
  }

  private headerMenus(): Array<HdsNavigationMenuItemOptions> {
    if (this.selected.length > 0) {
      return [
        { content: { icon: $r('sys.symbol.xmark'), label: '取消选择', action: (): void => { this.selected = []; AppStorage.setOrCreate('librarySelection', false); } } },
        { content: { icon: $r('sys.symbol.checkmark'), label: '全选', action: (): void => this.selectAllOrClear() } }
      ];
    }
    return [
      { content: { icon: $r('sys.symbol.magnifyingglass'), label: '搜索书架', action: (): void => { this.stack.pushPathByName(ROUTE_SEARCH, { scope: 'library' } as MangaRouteParams); } } },
      { content: { icon: $r('sys.symbol.slider_horizontal_2'), label: '筛选', action: (): void => { this.sheet = true; } } }
    ];
  }

  private bottomPadding(): number {
    if (this.selected.length > 0) { return TOOLBAR_HEIGHT + 12 + this.bottomInset; }
    const tabs: number = this.breakpoint === 'lg' ? 0 : TAB_BAR_HEIGHT;
    return 24 + tabs + this.bottomInset;
  }

  build() {
    HdsNavigation() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column({ space: 10 }) {
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
            Column({ space: 12 }) {
              Stack({ alignContent: Alignment.Center }) {
                SymbolGlyph($r('sys.symbol.books_vertical_fill'))
                  .fontSize(30)
                  .fontColor([PRIMARY])
              }
              .width(64)
              .height(64)
              .borderRadius(32)
              .backgroundColor(PRIMARY_SOFT)

              Text(this.works.length === 0 ? '书架还没有收藏漫画' : '没有符合当前筛选的漫画')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(TEXT_MAIN)
              Text(this.works.length === 0 ? '在图源中找到作品后可加入书架' : '请调整筛选条件')
                .fontSize(12)
                .fontColor(TEXT_SUB)
                .textAlign(TextAlign.Center)
                .padding({ left: 36, right: 36 })

              if (this.works.length > 0) {
                Button('重置筛选', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
                  .height(36)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .padding({ left: 20, right: 20 })
                  .onClick(() => {
                    this.query = '';
                    this.category = '';
                    this.readFilter = 0;
                    this.downloadFilter = 0;
                  })
              }
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .width('100%')
            .padding({ bottom: TAB_BAR_HEIGHT + this.bottomInset })
          } else {
            Grid(this.scroller) {
              ForEach(this.filtered(), (work: LibraryWork) => {
                GridItem() {
                  this.Cover(work)
                }
              }, (work: LibraryWork) => `${work.id}_${this.selected.includes(work.id)}_${work.newChapters}_${work.read}`)
            }
            .columnsTemplate(`repeat(${comicColumns(this.contentWidth)}, 1fr)`)
            .columnsGap(12)
            .rowsGap(16)
            .layoutWeight(1)
            .clip(false)
            .scrollBar(BarState.Off)
            .padding({
              left: 16,
              right: 16,
              top: 4,
              bottom: this.bottomPadding()
            })
            .width('100%')
            .onAreaChange((_old: Area, area: Area): void => {
              this.contentWidth = Number(area.width) - 32;
            })
          }
        }
        .width('100%')
        .height('100%')
        .bindSheet($$this.categorySheet, this.CategorySheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          systemMaterial: IMMERSIVE_SHEET_MATERIAL
        })

        // Bottom Batch Action Bar in Selection Mode
        if (this.selected.length > 0) {
          SelectionToolBar({ items: this.toolbar, bottomInset: this.bottomInset })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)
      .bindSheet($$this.sheet, this.FilterSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: false,
        systemMaterial: IMMERSIVE_SHEET_MATERIAL
      })
    }
    .titleBar({
      content: {
        title: { mainTitle: this.selected.length > 0 ? `已选 ${this.selected.length} 项` : '书架', mainTitleSize: TitleSize.TITLE_ML },
        menu: { value: this.headerMenus() }
      },
      style: HDS_TITLE_STYLE,
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .mode(NavigationMode.Stack)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .width('100%')
    .height('100%')
  }
}
