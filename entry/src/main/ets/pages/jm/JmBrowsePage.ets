import { HdsNavDestination, HdsNavDestinationTitleMode, HdsTabs } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@ohos.arkui.modifier';
import { ExplorePage } from '../ExplorePage';
import { CategoryPage } from '../CategoryPage';
import { HDS_NATIVE_MATERIAL, HDS_TITLE_STYLE } from '../../common/ImmersiveMaterials';
import { BG } from '../../common/Theme';
import { MangaRouteParams, ROUTE_SEARCH, ROUTE_JM_SETTINGS } from '../../common/Route';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

@Component
export struct JmBrowsePage {
  @Consume('navPathStack') stack: NavPathStack;
  @State private tab: number = 0;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  private exploreScroller: Scroller = new Scroller();
  private categoryScroller: Scroller = new Scroller();

  build() {
    HdsNavDestination() {
      HdsTabs({ index: this.tab }) {
        TabContent() { ExplorePage({ embeddedInShell: true, sourceIdValue: 'jm', scroller: this.exploreScroller }) }
          .tabBar(BottomTabBarStyle.of({ normal: new SymbolGlyphModifier($r('sys.symbol.star')), selected: new SymbolGlyphModifier($r('sys.symbol.star_fill')) }, '精选'))
        TabContent() { CategoryPage({ embeddedInShell: true, sourceIdValue: 'jm', scroller: this.categoryScroller }) }
          .tabBar(BottomTabBarStyle.of({ normal: new SymbolGlyphModifier($r('sys.symbol.square_grid_2x2')), selected: new SymbolGlyphModifier($r('sys.symbol.square_grid_2x2')) }, '分类'))
      }.barPosition(BarPosition.End).barOverlap(true).barMode(BarMode.Fixed).scrollable(false)
      .barFloatingStyle({ barWidth: { smallWidth: 144, mediumWidth: 152, largeWidth: 160 },
        barBottomMargin: this.bottomInset, systemMaterialEffect: HDS_NATIVE_MATERIAL })
      .onChange((index: number): void => { this.tab = index; }).width('100%').height('100%')
    }.titleBar({ content: { title: { mainTitle: '禁漫天堂' }, menu: { value: [
      { content: { icon: $r('sys.symbol.magnifyingglass'), label: '搜索', action: (): void => { this.stack.pushPathByName(ROUTE_SEARCH, { sourceId: 'jm', scope: 'source' } as MangaRouteParams); } } },
      { content: { icon: $r('sys.symbol.gearshape'), label: '设置', action: (): void => { this.stack.pushPathByName(ROUTE_JM_SETTINGS, {} as MangaRouteParams); } } }
    ] } }, style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true, enableComponentSafeArea: true }).titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.tab === 0 ? this.exploreScroller : this.categoryScroller]).backgroundColor(BG)
  }
}
