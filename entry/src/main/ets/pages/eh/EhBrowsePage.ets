import { HdsNavDestination, HdsNavDestinationTitleMode, HdsTabs } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@ohos.arkui.modifier';
import { MangaRouteParams, ROUTE_ALBUM, ROUTE_SEARCH } from '../../common/Route';
import { EhSettings } from '../../data/eh/EhSettings';
import { EhSearchFilter } from '../../data/eh/EhSearchFilter';
import { EhFilterSheet } from './EhFilterSheet';
import { EhGalleryPane } from './EhGalleryPane';
import { SourceSettingsSheet } from '../sources/SourceSettingsSheet';
import { GallerySite } from '../../data/eh/EhNative';
import { AlbumLite } from '../../models/Models';
import { IMMERSIVE_SHEET_MATERIAL, HDS_NATIVE_MATERIAL, HDS_TITLE_STYLE } from '../../common/ImmersiveMaterials';
import { BG } from '../../common/Theme';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

@Component
export struct EhBrowsePage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;

  @State tab: number = 0;
  @State siteLabel: string = 'E-Hentai';
  @State filter: EhSearchFilter = new EhSearchFilter();
  @State filterSheet: boolean = false;
  @State private settingsSheet: boolean = false;

  private scrollers: Array<Scroller> = [
    new Scroller(),
    new Scroller(),
    new Scroller(),
    new Scroller()
  ];

  aboutToAppear(): void {
    this.siteLabel = EhSettings.site() === GallerySite.EX ? 'ExHentai' : 'E-Hentai';
  }

  private open(item: AlbumLite): void {
    this.stack.pushPathByName(ROUTE_ALBUM, { aid: item.id } as MangaRouteParams);
  }

  private tabStyle(title: string, icon: Resource): BottomTabBarStyle {
    return BottomTabBarStyle.of({
      normal: new SymbolGlyphModifier(icon),
      selected: new SymbolGlyphModifier(icon)
    }, title);
  }

  @Builder
  private FilterSheetPanel() {
    EhFilterSheet({
      filter: this.filter,
      searchFilters: false,
      apply: (next: EhSearchFilter): void => {
        this.filter = next;
      },
      close: (): void => {
        this.filterSheet = false;
      }
    })
  }

  @Builder
  private SettingsPanel() {
    SourceSettingsSheet({
      token: 'eh.site',
      close: (): void => {
        this.settingsSheet = false;
        this.siteLabel = EhSettings.site() === GallerySite.EX ? 'ExHentai' : 'E-Hentai';
      }
    })
  }

  build() {
    HdsNavDestination() {
      HdsTabs({ index: this.tab }) {
        TabContent() {
          EhGalleryPane({
            galleryIndex: 0,
            scroller: this.scrollers[0],
            filter: this.filter,
            onOpen: (item: AlbumLite): void => this.open(item)
          })
        }.tabBar(this.tabStyle('最新', $r('sys.symbol.clock')))

        TabContent() {
          EhGalleryPane({
            galleryIndex: 1,
            scroller: this.scrollers[1],
            filter: this.filter,
            onOpen: (item: AlbumLite): void => this.open(item)
          })
        }.tabBar(this.tabStyle('热门', $r('sys.symbol.flame')))

        TabContent() {
          EhGalleryPane({
            galleryIndex: 2,
            scroller: this.scrollers[2],
            filter: this.filter,
            onOpen: (item: AlbumLite): void => this.open(item)
          })
        }.tabBar(this.tabStyle('关注', $r('sys.symbol.eye')))

        TabContent() {
          EhGalleryPane({
            galleryIndex: 3,
            scroller: this.scrollers[3],
            filter: this.filter,
            onOpen: (item: AlbumLite): void => this.open(item)
          })
        }.tabBar(this.tabStyle('收藏', $r('sys.symbol.heart')))
      }
      .barPosition(BarPosition.End)
      .scrollable(false)
      .barMode(BarMode.Fixed)
      .barOverlap(true)
      .barBackgroundColor(Color.Transparent)
      .barFloatingStyle({
        barWidth: { smallWidth: 264, mediumWidth: 288, largeWidth: 304 },
        barBottomMargin: this.bottomInset,
        systemMaterialEffect: HDS_NATIVE_MATERIAL
      })
      .onChange((index: number) => {
        this.tab = index;
      })
      .width('100%')
      .height('100%')
    }
    .titleBar({
      content: {
        title: {
          mainTitle: this.siteLabel,
          subTitle: EhSettings.exDowngraded() ? '已降级为表站' : ''
        },
        menu: {
          value: [
            {
              content: {
                icon: $r('sys.symbol.slider_horizontal_2'),
                label: '筛选',
                action: (): void => {
                  this.filterSheet = true;
                }
              }
            },
            {
              content: {
                icon: $r('sys.symbol.magnifyingglass'),
                label: '搜索',
                action: (): void => {
                  this.stack.pushPathByName(ROUTE_SEARCH, { sourceId: 'eh', scope: 'source' } as MangaRouteParams);
                }
              }
            },
            {
              content: {
                icon: $r('sys.symbol.gearshape'),
                label: '设置',
                action: (): void => {
                  this.settingsSheet = true;
                }
              }
            }
          ]
        }
      },
      style: HDS_TITLE_STYLE,
      avoidLayoutSafeArea: true
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable(this.scrollers)
    .backgroundColor(BG)
    .bindSheet($$this.filterSheet, this.FilterSheetPanel(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      systemMaterial: IMMERSIVE_SHEET_MATERIAL
    })
    .bindSheet($$this.settingsSheet, this.SettingsPanel(), {
      height: SheetSize.LARGE,
      dragBar: true,
      showClose: false,
      systemMaterial: IMMERSIVE_SHEET_MATERIAL
    })
  }
}
