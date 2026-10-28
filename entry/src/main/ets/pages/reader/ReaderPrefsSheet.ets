/**
 * entry/src/main/ets/pages/reader/ReaderPrefsSheet.ets
 * 阅读器底部「设置」浮卡内容：自适应高度，不使用固定行高的 ListItemStyle.CARD，消除内容截断与压叠错位。
 */
import { readerHudPalette } from '../../common/Theme';
import { EMPTY_MATERIAL } from '../../common/ImmersiveMaterials';
import { DEFAULT_TAPS, PRELOAD_LEVELS, ReaderOptions } from '../../data/ReaderOptions';

const PRELOAD_OPTIONS: Array<SelectOption> = PRELOAD_LEVELS.map((n: number): SelectOption => {
  const opt: SelectOption = { value: `${n}页` };
  return opt;
});

@Component
export struct ReaderPrefsSheet {
  @Link options: ReaderOptions;
  @Link preloadCount: number;
  @Prop bgPaper: boolean = false;
  setPreload: (n: number) => void = (n: number): void => {};
  openZoneEditor: () => void = (): void => {};

  build() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text('后台预加载页数')
            .fontSize(14)
            .fontColor(readerHudPalette(this.bgPaper).text)
          Text('数值越小越省流量，越大翻页越顺')
            .fontSize(12)
            .fontColor(readerHudPalette(this.bgPaper).textSub)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Select(PRELOAD_OPTIONS)
          .selected(this.preloadIndex())
          .value(`${this.preloadCount}页`)
          .backgroundColor(Color.Transparent)
          .borderWidth(0)
          .borderColor(Color.Transparent)
          .systemMaterial(EMPTY_MATERIAL)
          .onSelect((index: number) => {
            this.setPreload(PRELOAD_LEVELS[Math.min(index, PRELOAD_LEVELS.length - 1)]);
          })
      }
      .width('100%')
      .constraintSize({ minHeight: 48 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .strokeWidth(0.5)
        .color(readerHudPalette(this.bgPaper).divider)

      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text('触控热区分配')
            .fontSize(14)
            .fontColor(readerHudPalette(this.bgPaper).text)
          Text(this.zonePresetLabel())
            .fontSize(12)
            .fontColor(readerHudPalette(this.bgPaper).textSub)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([readerHudPalette(this.bgPaper).textSub])
      }
      .width('100%')
      .constraintSize({ minHeight: 48 })
      .alignItems(VerticalAlign.Center)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
      .onClick(() => {
        this.openZoneEditor();
      })
    }
    .width('100%')
  }

  private preloadIndex(): number {
    const found: number = PRELOAD_LEVELS.indexOf(this.preloadCount);
    return found < 0 ? 1 : found;
  }

  private zonePresetLabel(): string {
    const isClassic: boolean = this.options.taps.every((value: number, index: number): boolean =>
      value === DEFAULT_TAPS[index]);
    return isClassic ? '经典左右翻页' : '已自定义';
  }
}
