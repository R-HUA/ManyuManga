import { HdsNavDestination, HdsNavDestinationTitleMode, HdsTabs } from '@kit.UIDesignKit';
import { ExplorePage } from '../ExplorePage';
import { CategoryPage } from '../CategoryPage';
import { HDS_TITLE_STYLE } from '../../common/ImmersiveMaterials';
import { BG } from '../../common/Theme';
import { MangaRouteParams, ROUTE_SEARCH, ROUTE_JM_SETTINGS } from '../../common/Route';

@Component
export struct JmBrowsePage {
  @Consume('navPathStack') stack: NavPathStack;
  @State private tab: number = 0;
  private exploreScroller: Scroller = new Scroller();
  private categoryScroller: Scroller = new Scroller();

  build() {
    HdsNavDestination() {
      HdsTabs({ index: this.tab }) {
        TabContent() { ExplorePage({ embeddedInShell: true, sourceIdValue: 'jm', scroller: this.exploreScroller }) }.tabBar(SubTabBarStyle.of('精选'))
        TabContent() { CategoryPage({ embeddedInShell: true, sourceIdValue: 'jm', scroller: this.categoryScroller }) }.tabBar(SubTabBarStyle.of('分类'))
      }.barPosition(BarPosition.Start).barHeight(48).scrollable(false)
      .onChange((index: number): void => { this.tab = index; }).width('100%').height('100%')
    }.titleBar({ content: { title: { mainTitle: '禁漫天堂' }, menu: { value: [
      { content: { icon: $r('sys.symbol.magnifyingglass'), label: '搜索', action: (): void => { this.stack.pushPathByName(ROUTE_SEARCH, { sourceId: 'jm', scope: 'source' } as MangaRouteParams); } } },
      { content: { icon: $r('sys.symbol.gearshape'), label: '设置', action: (): void => { this.stack.pushPathByName(ROUTE_JM_SETTINGS, {} as MangaRouteParams); } } }
    ] } }, style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true, enableComponentSafeArea: true }).titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.tab === 0 ? this.exploreScroller : this.categoryScroller]).backgroundColor(BG)
  }
}
