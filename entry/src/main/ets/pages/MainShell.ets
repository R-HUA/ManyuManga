import { HdsNavigation, HdsTabs } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@ohos.arkui.modifier';
import { JmBrowsePage } from './jm/JmBrowsePage';
import { SourceBrowsePage } from './SourceBrowsePage';
import { ReadingStatsPage } from './ReadingStatsPage';
import { LibraryPage } from './LibraryPage';
import { UpdatesPage } from './UpdatesPage';
import { SourcesPage } from './SourcesPage';
import { ProfilePage } from './ProfilePage';
import { SearchAllPage } from './SearchAllPage';
import { WorkDetailPage } from './WorkDetailPage';
import { ReaderPage } from './ReaderPage';
import { DownloadsPage } from './DownloadsPage';
import { ChapterPreviewPage } from './ChapterPreviewPage';
import { JmSourceSettingsPage } from './JmSourceSettingsPage';
import { EhBrowsePage } from './eh/EhBrowsePage';
import { BlockRulesPage } from './settings/BlockRulesPage';
import { HDS_NATIVE_MATERIAL } from '../common/ImmersiveMaterials';
import { ROUTE_SEARCH, ROUTE_ALBUM, ROUTE_READER, ROUTE_DOWNLOADS, ROUTE_PREVIEW, ROUTE_JM_SETTINGS, ROUTE_JM_BROWSE, ROUTE_EH_BROWSE, ROUTE_BLOCK_RULES, ROUTE_STATS, ROUTE_SOURCE_BROWSE, NAV_STACK_DEPTH_KEY } from '../common/Route';
import { BG, CARD, SUB_CARD, DIVIDER, TEXT_SUB, PRIMARY, PRIMARY_SOFT } from '../common/Theme';

@Component
export struct MainShell {
  @Provide('navPathStack') stack: NavPathStack = new NavPathStack();
  @StorageLink('mainTabIndex') tab: number = 0;
  @StorageProp('currentBreakpoint') breakpoint: string = 'sm';
  @StorageProp('topRectHeight') topInset: number = 0;
  @StorageProp('bottomRectHeight') bottom: number = 0;
  @StorageProp('librarySelection') selecting: boolean = false;
  @State visible: boolean = true;
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
    } else if (name === ROUTE_PREVIEW) {
      ChapterPreviewPage()
    } else if (name === ROUTE_JM_BROWSE) {
      JmBrowsePage()
    } else if (name === ROUTE_EH_BROWSE) {
      EhBrowsePage()
    } else if (name === 'jmSettings' || name === ROUTE_JM_SETTINGS) {
      JmSourceSettingsPage()
    } else if (name === ROUTE_STATS) {
      ReadingStatsPage()
    } else if (name === ROUTE_SOURCE_BROWSE) {
      SourceBrowsePage()
    } else if (name === ROUTE_BLOCK_RULES) {
      BlockRulesPage()
    }
  }

  private tabStyle(title: string, icon: Resource): BottomTabBarStyle {
    return BottomTabBarStyle.of({ normal: new SymbolGlyphModifier(icon), selected: new SymbolGlyphModifier(icon) }, title);
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
      this.RailItem('图源', $r('sys.symbol.square_grid_2x2'), 2)
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
        HdsTabs({ index: this.tab }) {
          TabContent() { LibraryPage() }.tabBar(this.tabStyle('书架', $r('sys.symbol.books_vertical_fill')))
          TabContent() { UpdatesPage() }.tabBar(this.tabStyle('动态', $r('sys.symbol.clock')))
          TabContent() { SourcesPage() }.tabBar(this.tabStyle('图源', $r('sys.symbol.square_grid_2x2')))
          TabContent() { ProfilePage() }.tabBar(this.tabStyle('我的', $r('sys.symbol.person')))
        }
        .barPosition(BarPosition.End)
        .scrollable(false)
        .barMode(BarMode.Fixed)
        // 负值恢复 HDS 悬浮页签的原生高度，隐藏时才覆盖为零。
        .barHeight(this.breakpoint === 'lg' || this.selecting ? 0 : -1)
        .barOverlap(this.breakpoint !== 'lg')
        .barBackgroundColor(Color.Transparent)
        .barFloatingStyle({
          barWidth: { smallWidth: 264, mediumWidth: 288, largeWidth: 304 },
          barBottomMargin: this.bottom,
          systemMaterialEffect: HDS_NATIVE_MATERIAL
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
