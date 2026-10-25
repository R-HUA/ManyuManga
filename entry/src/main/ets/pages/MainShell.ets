import { HdsNavigation } from '@kit.UIDesignKit';
import { uiMaterial } from '@kit.ArkUI';
import { LibraryPage } from './LibraryPage';
import { UpdatesPage } from './UpdatesPage';
import { SourcesPage } from './SourcesPage';
import { SettingsPage } from './SettingsPage';
import { ProfilePage } from './ProfilePage';
import { SearchAllPage } from './SearchAllPage';
import { WorkDetailPage } from './WorkDetailPage';
import { ReaderPage } from './ReaderPage';
import { DownloadsPage } from './DownloadsPage';
import { ExplorePage } from './ExplorePage';
import { CategoryPage } from './CategoryPage';
import { ROUTE_SEARCH, ROUTE_ALBUM, ROUTE_READER, ROUTE_DOWNLOADS, NAV_STACK_DEPTH_KEY } from '../common/Route';
import { BG, CARD, TEXT_SUB, PRIMARY } from '../common/Theme';

@Component
export struct MainShell {
  @Provide('navPathStack') stack: NavPathStack = new NavPathStack();
  @StorageLink('mainTabIndex') tab: number = 0;
  @StorageProp('currentBreakpoint') breakpoint: string = 'sm';
  @StorageProp('bottomRectHeight') bottom: number = 0;
  @StorageProp('librarySelection') selecting: boolean = false;
  @State visible: boolean = true;
  @StorageProp('crashErrorMessage') @Watch('showError') crash: string = '';
  private showError(): void {
    if (this.crash !== '') {
      AlertDialog.show({ title: '操作未完成', message: this.crash,
        confirm: { value: '确定', action: () => { AppStorage.setOrCreate('crashErrorMessage', ''); } } });
    }
  }
  private material: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THIN });
  @Builder
  private PageMap(name: string) {
    if (name === ROUTE_SEARCH) { SearchAllPage() }
    else if (name === ROUTE_ALBUM) { WorkDetailPage() }
    else if (name === ROUTE_READER) { ReaderPage() }
    else if (name === ROUTE_DOWNLOADS) { DownloadsPage() }
    else if (name === 'jmBrowse') {
      NavDestination() {
        Tabs() {
          TabContent() { ExplorePage() }.tabBar('发现')
          TabContent() { CategoryPage() }.tabBar('分类')
        }.width('100%').height('100%')
      }.title('JMcomic')
    } else if (name === 'jmSettings') {
      NavDestination() { SettingsPage({ sourceOnly: true }) }.title('设置')
    }
  }
  @Builder
  private Label(title: string, icon: Resource, index: number) {
    Column({ space: 4 }) {
      SymbolGlyph(icon).fontSize(24).fontColor([this.tab === index ? PRIMARY : TEXT_SUB])
      Text(title).fontSize(11).fontColor(this.tab === index ? PRIMARY : TEXT_SUB)
    }.width('100%').height(56).justifyContent(FlexAlign.Center)
  }
  @Builder
  private RailItem(title: string, icon: Resource, index: number) {
    Column() { this.Label(title, icon, index) }.width('100%').onClick(() => { this.tab = index; })
  }
  @Builder
  private Rail() {
    Column({ space: 14 }) {
      this.RailItem('书架', $r('sys.symbol.book'), 0)
      this.RailItem('更新', $r('sys.symbol.clock'), 1)
      this.RailItem('书源', $r('sys.symbol.square_grid_2x2'), 2)
      this.RailItem('我的', $r('sys.symbol.person'), 3)
    }.width(72).height('100%').padding({ top: 72 }).backgroundColor(CARD)
  }
  build() {
    Row() {
      if (this.breakpoint === 'lg' && this.visible) { this.Rail() }
      HdsNavigation(this.stack) {
        Tabs({ barPosition: BarPosition.End, index: this.tab }) {
          TabContent() { LibraryPage() }.tabBar(this.Label('书架', $r('sys.symbol.book'), 0))
          TabContent() { UpdatesPage() }.tabBar(this.Label('更新', $r('sys.symbol.clock'), 1))
          TabContent() { SourcesPage() }.tabBar(this.Label('书源', $r('sys.symbol.square_grid_2x2'), 2))
          TabContent() { ProfilePage() }.tabBar(this.Label('我的', $r('sys.symbol.person'), 3))
        }.scrollable(false).barMode(BarMode.Fixed)
        .barHeight(this.breakpoint === 'lg' || this.selecting ? 0 : 64)
        .barOverlap(true)
        .barFloatingStyle({ barWidth: { mediumBarWidth: 480, largeBarWidth: 480 }, barSideMargin: 20,
          barBottomMargin: this.bottom + 8, systemMaterial: this.material })
        .onChange((index: number) => { this.tab = index; }).width('100%').height('100%')
      }.mode(NavigationMode.Stack).hideTitleBar(true).hideToolBar(true).navDestination(this.PageMap)
      .onNavBarStateChange((visible: boolean) => { this.visible = visible; AppStorage.setOrCreate(NAV_STACK_DEPTH_KEY, visible ? 0 : Math.max(1, this.stack.size())); })
      .layoutWeight(1).height('100%').backgroundColor(BG)
    }.width('100%').height('100%').backgroundColor(BG)
  }
}
