import { HdsNavigation } from '@kit.UIDesignKit';
import { uiMaterial } from '@kit.ArkUI';
import { LibraryPage } from './LibraryPage';
import { UpdatesPage } from './UpdatesPage';
import { SourcesPage } from './SourcesPage';
import { ProfilePage } from './ProfilePage';
import { SearchAllPage } from './SearchAllPage';
import { WorkDetailPage } from './WorkDetailPage';
import { ReaderPage } from './ReaderPage';
import { DownloadsPage } from './DownloadsPage';
import { ExplorePage } from './ExplorePage';
import { CategoryPage } from './CategoryPage';
import { IconCircleButton } from '../common/Components';
import { ROUTE_SEARCH, ROUTE_ALBUM, ROUTE_READER, ROUTE_DOWNLOADS, NAV_STACK_DEPTH_KEY, MangaRouteParams } from '../common/Route';
import { BG, CARD, SUB_CARD, DIVIDER, TEXT_MAIN, TEXT_SUB, PRIMARY, PRIMARY_SOFT, BAR_TINT, TAB_BAR_HEIGHT } from '../common/Theme';

@Component
export struct MainShell {
  @Provide('navPathStack') stack: NavPathStack = new NavPathStack();
  @StorageLink('mainTabIndex') tab: number = 0;
  @StorageProp('currentBreakpoint') breakpoint: string = 'sm';
  @StorageProp('topRectHeight') topInset: number = 0;
  @StorageProp('bottomRectHeight') bottom: number = 0;
  @StorageProp('librarySelection') selecting: boolean = false;
  @State visible: boolean = true;
  @State jmTab: number = 0;
  @StorageProp('crashErrorMessage') @Watch('showError') crash: string = '';

  private showError(): void {
    if (this.crash !== '') {
      this.getUIContext().showAlertDialog({
        title: '操作未完成',
        message: this.crash,
        confirm: {
          value: '确定',
          action: () => {
            AppStorage.setOrCreate('crashErrorMessage', '');
          }
        }
      });
    }
  }

  private material: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    materialColor: BAR_TINT,
    colorInvert: true,
    applyShadow: true
  });

  @Builder
  private JmBrowseDestination() {
    NavDestination() {
      Column() {
        Row({ space: 12 }) {
          IconCircleButton({
            symbol: $r('sys.symbol.chevron_left'),
            btnSize: 38,
            iconSize: 18,
            onTap: (): void => {
              this.stack.pop();
            }
          })

          Row({ space: 4 }) {
            Text('精选发现')
              .fontSize(13)
              .fontWeight(this.jmTab === 0 ? FontWeight.Bold : FontWeight.Medium)
              .fontColor(this.jmTab === 0 ? Color.White : TEXT_SUB)
              .padding({ left: 16, right: 16, top: 7, bottom: 7 })
              .backgroundColor(this.jmTab === 0 ? PRIMARY : Color.Transparent)
              .borderRadius(16)
              .onClick(() => {
                this.jmTab = 0;
              })

            Text('分类片库')
              .fontSize(13)
              .fontWeight(this.jmTab === 1 ? FontWeight.Bold : FontWeight.Medium)
              .fontColor(this.jmTab === 1 ? Color.White : TEXT_SUB)
              .padding({ left: 16, right: 16, top: 7, bottom: 7 })
              .backgroundColor(this.jmTab === 1 ? PRIMARY : Color.Transparent)
              .borderRadius(16)
              .onClick(() => {
                this.jmTab = 1;
              })
          }
          .padding(3)
          .backgroundColor(SUB_CARD)
          .borderRadius(19)
          .border({ width: 0.5, color: DIVIDER })

          Blank()

          IconCircleButton({
            symbol: $r('sys.symbol.magnifyingglass'),
            btnSize: 38,
            iconSize: 17,
            onTap: (): void => {
              this.stack.pushPathByName(ROUTE_SEARCH, { sourceId: 'jm' } as MangaRouteParams);
            }
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topInset + 8, bottom: 8 })
        .backgroundColor(BG)
        .border({ width: { bottom: 0.5 }, color: DIVIDER })

        Stack() {
          if (this.jmTab === 0) {
            ExplorePage({ embeddedInShell: true })
          } else {
            CategoryPage({ embeddedInShell: true })
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)
    }
    .hideTitleBar(true)
  }

  @Builder
  private PageMap(name: string) {
    if (name === ROUTE_SEARCH) {
      SearchAllPage()
    } else if (name === ROUTE_ALBUM) {
      WorkDetailPage()
    } else if (name === ROUTE_READER) {
      ReaderPage()
    } else if (name === ROUTE_DOWNLOADS) {
      DownloadsPage()
    } else if (name === 'jmBrowse') {
      this.JmBrowseDestination()
    } else if (name === 'jmSettings') {
      NavDestination() {
        ProfilePage({ sourceOnly: true })
      }
      .hideTitleBar(true)
    }
  }

  @Builder
  private Label(title: string, icon: Resource, index: number) {
    Column({ space: 3 }) {
      SymbolGlyph(icon)
        .fontSize(21)
        .fontColor([this.tab === index ? PRIMARY : $r('sys.color.font_secondary')])
        .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.UP), this.tab === index)
      Text(title)
        .fontSize(11)
        .fontWeight(this.tab === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.tab === index ? PRIMARY : $r('sys.color.font_secondary'))
    }
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private RailItem(title: string, icon: Resource, index: number) {
    Column({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(21)
        .fontColor([this.tab === index ? PRIMARY : TEXT_SUB])
      Text(title)
        .fontSize(11)
        .fontWeight(this.tab === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.tab === index ? PRIMARY : TEXT_SUB)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .borderRadius(14)
    .backgroundColor(this.tab === index ? PRIMARY_SOFT : Color.Transparent)
    .onClick(() => {
      this.tab = index;
    })
  }

  @Builder
  private Rail() {
    Column({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.book_pages'))
          .fontSize(22)
          .fontColor([Color.White])
      }
      .width(42)
      .height(42)
      .borderRadius(12)
      .backgroundColor(PRIMARY)
      .margin({ bottom: 10 })

      this.RailItem('书架', $r('sys.symbol.books_vertical_fill'), 0)
      this.RailItem('动态', $r('sys.symbol.clock'), 1)
      this.RailItem('图源', $r('sys.symbol.compass'), 2)
      this.RailItem('我的', $r('sys.symbol.person'), 3)
      Blank()
    }
    .width(82)
    .height('100%')
    .padding({ top: this.topInset + 16, bottom: this.bottom + 16, left: 8, right: 8 })
    .backgroundColor(CARD)
    .border({ width: { right: 0.5 }, color: DIVIDER })
  }

  build() {
    Row() {
      if (this.breakpoint === 'lg' && this.visible) {
        this.Rail()
      }
      HdsNavigation(this.stack) {
        Tabs({ barPosition: BarPosition.End, index: this.tab }) {
          TabContent() { LibraryPage() }.tabBar(this.Label('书架', $r('sys.symbol.books_vertical_fill'), 0))
          TabContent() { UpdatesPage() }.tabBar(this.Label('动态', $r('sys.symbol.clock'), 1))
          TabContent() { SourcesPage() }.tabBar(this.Label('图源', $r('sys.symbol.compass'), 2))
          TabContent() { ProfilePage() }.tabBar(this.Label('我的', $r('sys.symbol.person'), 3))
        }
        .scrollable(false)
        .barMode(BarMode.Fixed)
        .barHeight(this.breakpoint === 'lg' || this.selecting ? 0 : TAB_BAR_HEIGHT)
        .barOverlap(this.breakpoint !== 'lg')
        .barBackgroundColor(Color.Transparent)
        .barFloatingStyle({
          barSideMargin: 24,
          barBottomMargin: 10,
          systemMaterial: this.material
        })
        .onChange((index: number) => {
          this.tab = index;
        })
        .width('100%')
        .height('100%')
      }
      .mode(NavigationMode.Stack)
      .hideTitleBar(true)
      .navDestination(this.PageMap)
      .onNavBarStateChange((visible: boolean) => {
        this.visible = visible;
        AppStorage.setOrCreate(NAV_STACK_DEPTH_KEY, visible ? 0 : 1);
      })
      .layoutWeight(1)
      .height('100%')
      .backgroundColor(BG)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
  }
}
