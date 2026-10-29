import { HdsNavigation, HdsNavigationTitleMode, TitleSize } from '@kit.UIDesignKit';
import {
  MangaRouteParams, ROUTE_APPEARANCE, ROUTE_BLOCK_RULES, ROUTE_DOWNLOADS, ROUTE_PRIVACY, ROUTE_READER_SETTINGS,
  ROUTE_SOURCE_SETTINGS, ROUTE_STATS, ROUTE_STORAGE
} from '../common/Route';
import { HDS_TITLE_STYLE } from '../common/ImmersiveMaterials';
import {
  SETTINGS_VERSION_KEY, SettingsSnapshot, loadSettings, privacySummary, readerSummary, themeSummary
} from '../data/SettingsService';
import { BG, CARD, TEXT_MAIN, TEXT_SUB, PRIMARY, DIVIDER, TAB_BAR_HEIGHT } from '../common/Theme';
import { errorMessage } from '../models/Models';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

/**
 * “我的”一级页：只放导航行，所有立即生效的设置都在二级页里修改，行尾仅显示当前值摘要。
 */
@Component
export struct ProfilePage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp(TOP_RECT_HEIGHT_KEY) top: number = 0;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  @StorageProp('currentBreakpoint') breakpoint: string = 'sm';
  @StorageProp(SETTINGS_VERSION_KEY) @Watch('load') settingsVersion: number = 0;

  @State readerLabel: string = '';
  @State themeLabel: string = '';
  @State privacyLabel: string = '';
  @State message: string = '';

  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.load();
  }

  async load(): Promise<void> {
    try {
      const snapshot: SettingsSnapshot = await loadSettings();
      this.readerLabel = readerSummary(snapshot);
      this.themeLabel = themeSummary(snapshot);
      this.privacyLabel = privacySummary(snapshot);
      this.message = '';
    } catch (e) {
      this.message = errorMessage(e as Error);
    }
  }

  open(route: string, params: MangaRouteParams): void {
    this.stack.pushPathByName(route, params);
  }

  @Builder
  private NavRow(icon: Resource, title: string, valueText: string, onTap: () => void) {
    Row({ space: 16 }) {
      SymbolGlyph(icon)
        .fontSize(24).fontWeight(FontWeight.Medium)
        .fontColor([PRIMARY])
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_MAIN)
        .layoutWeight(1)
      if (valueText !== '') {
        Text(valueText)
          .fontSize(14)
          .fontColor(TEXT_SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '50%' })
      }
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([TEXT_SUB])
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .alignItems(VerticalAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  private RowDivider() {
    Divider().strokeWidth('1px').color(DIVIDER).margin({ left: 40 })
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          Column() {
            this.NavRow($r('sys.symbol.clock'), '阅读统计', '', () => { this.open(ROUTE_STATS, {} as MangaRouteParams); })
            this.RowDivider()
            this.NavRow($r('sys.symbol.arrow_down_circle'), '离线下载与导出', '', () => {
              this.open(ROUTE_DOWNLOADS, {} as MangaRouteParams);
            })
          }
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .width('100%')
          .backgroundColor(CARD)
          .borderRadius(16)
          .border({ width: 0.5, color: DIVIDER })

          Column() {
            this.NavRow($r('sys.symbol.book_pages'), '阅读设置', this.readerLabel, () => {
              this.open(ROUTE_READER_SETTINGS, {} as MangaRouteParams);
            })
            this.RowDivider()
            this.NavRow($r('sys.symbol.sun_max'), '外观', this.themeLabel, () => {
              this.open(ROUTE_APPEARANCE, {} as MangaRouteParams);
            })
            this.RowDivider()
            this.NavRow($r('sys.symbol.square_grid_2x2'), '图源设置', '', () => {
              this.open(ROUTE_SOURCE_SETTINGS, {} as MangaRouteParams);
            })
            this.RowDivider()
            this.NavRow($r('sys.symbol.checkmark_shield'), '屏蔽规则', '仅在线图源', () => {
              this.open(ROUTE_BLOCK_RULES, { sourceId: '' } as MangaRouteParams);
            })
          }
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .width('100%')
          .backgroundColor(CARD)
          .borderRadius(16)
          .border({ width: 0.5, color: DIVIDER })

          Column() {
            this.NavRow($r('sys.symbol.lock_fill'), '隐私与安全', this.privacyLabel, () => {
              this.open(ROUTE_PRIVACY, {} as MangaRouteParams);
            })
            this.RowDivider()
            this.NavRow($r('sys.symbol.arrow_clockwise'), '存储与备份', '', () => {
              this.open(ROUTE_STORAGE, {} as MangaRouteParams);
            })
          }
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .width('100%')
          .backgroundColor(CARD)
          .borderRadius(16)
          .border({ width: 0.5, color: DIVIDER })

          Column({ space: 4 }) {
            Text('漫屿')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_MAIN)
            Text('Manyu Manga v1.0.0')
              .fontSize(11)
              .fontColor(TEXT_SUB)
          }
          .padding({ top: 8, bottom: 12 })
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }
        .padding({ left: 16, right: 16 })
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off).align(Alignment.TopStart).clip(false)
      .contentEndOffset((this.breakpoint === 'lg' ? 16 : TAB_BAR_HEIGHT + 16) + this.bottomInset)
    }
    .titleBar({ content: { title: { mainTitle: '我的', mainTitleSize: TitleSize.TITLE_ML } }, style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavigationTitleMode.MINI)
    .mode(NavigationMode.Stack).hideBackButton(true).bindToScrollable([this.scroller])
    .width('100%').height('100%').backgroundColor(BG)
  }
}
