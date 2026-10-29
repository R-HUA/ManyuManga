import { BottomBuilderShowType, HdsNavDestination, HdsNavDestinationTitleMode, HdsTabs, HideMode } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@ohos.arkui.modifier';
import { ExplorePage } from '../ExplorePage';
import { CategoryPage } from '../CategoryPage';
import { CategoryFilterBar, CATEGORY_BAR_HEIGHT } from './CategoryFilterBar';
import { CategoryBrowseQuery } from './CategoryBrowseQuery';
import { CategoryItem, errorMessage } from '../../models/Models';
import { sourceApi } from '../../data/SourceApi';
import { customCatStore } from '../../data/Stores';
import { HDS_NATIVE_MATERIAL, HDS_TITLE_STYLE } from '../../common/ImmersiveMaterials';
import { BG } from '../../common/Theme';
import { MangaRouteParams, ROUTE_SEARCH, ROUTE_JM_SETTINGS } from '../../common/Route';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

const cachedCategories: Map<string, Array<CategoryItem>> = new Map();

@Component
export struct JmBrowsePage {
  @Consume('navPathStack') stack: NavPathStack;
  @State tab: number = 0;
  @State private categoryQuery: CategoryBrowseQuery = new CategoryBrowseQuery();
  @State private categories: Array<CategoryItem> = [];
  @State private customCats: Array<string> = [];
  @State private catsLoading: boolean = true;
  @State private catsError: string = '';
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  private exploreScroller: Scroller = new Scroller();
  private categoryScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadCategories();
    this.refreshCustomCats().catch((e: Error) => {
      console.info(`[JmBrowsePage] 自定义分类读取失败: ${errorMessage(e)}`);
    });
  }

  private async loadCategories(): Promise<void> {
    const cached: Array<CategoryItem> | undefined = cachedCategories.get('jm');
    if (cached !== undefined) {
      this.categories = cached;
      this.catsLoading = false;
      return;
    }
    this.catsLoading = true;
    this.catsError = '';
    try {
      const list: Array<CategoryItem> = await sourceApi.categories('jm');
      cachedCategories.set('jm', list);
      this.categories = list;
    } catch (e) {
      this.catsError = errorMessage(e as Error);
    } finally {
      this.catsLoading = false;
    }
  }

  private async refreshCustomCats(): Promise<void> {
    this.customCats = await customCatStore.getList();
  }

  private selectAll(): void {
    if (this.categoryQuery.categoryId === '') { return; }
    this.categoryQuery = new CategoryBrowseQuery();
  }

  private selectCategory(cat: CategoryItem): void {
    if (this.categoryQuery.categoryId === cat.id) { return; }
    this.categoryQuery = new CategoryBrowseQuery(cat.id, cat.name, cat.slug, cat.slug === '' ? 'mr' : 'mv');
  }

  private selectCustom(term: string): void {
    this.categoryQuery = new CategoryBrowseQuery(`custom:${term}`, term, '', 'mr', term);
  }

  private selectOrder(code: string): void {
    const query: CategoryBrowseQuery = this.categoryQuery;
    if (query.order === code) { return; }
    this.categoryQuery = new CategoryBrowseQuery(query.categoryId, query.categoryName, query.categorySlug, code, query.customQuery);
  }

  @Builder
  private CategoryHeader() {
    CategoryFilterBar({
      selectedCatId: this.categoryQuery.categoryId,
      categories: this.categories,
      customCats: this.customCats,
      order: this.categoryQuery.order,
      selectAll: (): void => this.selectAll(),
      selectCategory: (cat: CategoryItem): void => this.selectCategory(cat),
      selectCustom: (term: string): void => this.selectCustom(term),
      selectOrder: (code: string): void => this.selectOrder(code)
    })
  }

  build() {
    HdsNavDestination() {
      HdsTabs({ index: this.tab }) {
        TabContent() { ExplorePage({ embeddedInShell: true, sourceIdValue: 'jm', scroller: this.exploreScroller }) }
          .clip(false)
          .tabBar(BottomTabBarStyle.of({ normal: new SymbolGlyphModifier($r('sys.symbol.star_fill')), selected: new SymbolGlyphModifier($r('sys.symbol.star_fill')) }, '精选'))
        TabContent() { CategoryPage({ embeddedInShell: true, sourceIdValue: 'jm', scroller: this.categoryScroller, query: this.categoryQuery }) }
          .clip(false)
          .tabBar(BottomTabBarStyle.of({ normal: new SymbolGlyphModifier($r('sys.symbol.square_fill_grid_2x2')), selected: new SymbolGlyphModifier($r('sys.symbol.square_fill_grid_2x2')) }, '分类'))
      }.barPosition(BarPosition.End).barOverlap(true).barMode(BarMode.Fixed).scrollable(false)
      .clip(false)
      .barFloatingStyle({ barWidth: { smallWidth: 144, mediumWidth: 152, largeWidth: 160 },
        barBottomMargin: this.bottomInset, systemMaterialEffect: HDS_NATIVE_MATERIAL })
      .onChange((index: number): void => { this.tab = index; }).width('100%').height('100%')
    }.titleBar({
      content: {
        title: { mainTitle: '禁漫天堂' },
        bottomBuilder: this.tab === 1 ? {
          builder: (): void => this.CategoryHeader(),
          height: CATEGORY_BAR_HEIGHT,
          showType: BottomBuilderShowType.DIRECTLY_SHOW
        } : undefined,
        menu: {
          value: [
            { content: { icon: $r('sys.symbol.magnifyingglass'), label: '搜索', action: (): void => { this.stack.pushPathByName(ROUTE_SEARCH, { sourceId: 'jm', scope: 'source' } as MangaRouteParams); } } },
            { content: { icon: $r('sys.symbol.gearshape'), label: '设置', action: (): void => { this.stack.pushPathByName(ROUTE_JM_SETTINGS, {} as MangaRouteParams); } } }
          ]
        }
      },
      style: HDS_TITLE_STYLE,
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable(this.tab === 1 ? [this.categoryScroller] : [this.exploreScroller])
    .dynamicHideTitleBar({
      hideTitleArea: false,
      hideBottomBuilder: this.tab === 1,
      hideStatusBar: false,
      mode: HideMode.SCROLL_UP_TO,
      hideOffset: 0,
      hideRatio: 2
    })
    .backgroundColor(BG)
  }
}
