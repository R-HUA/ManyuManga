/**
 * entry/src/main/ets/pages/reader/ReaderPrefsSheet.ets
 * 阅读器底部「设置」浮卡内容：自适应高度，不使用固定行高的 ListItemStyle.CARD，消除内容截断与压叠错位。
 */
import { PRIMARY, SUB_CARD, TEXT_SUB } from '../../common/Theme';
import { LengthMetrics } from '@kit.ArkUI';
import { DEFAULT_TAPS, PRELOAD_LEVELS, ReaderOptions } from '../../data/ReaderOptions';

@Component
export struct ReaderPrefsSheet {
  @Link options: ReaderOptions;
  @Link preloadCount: number;
  setPreload: (n: number) => void = (n: number): void => {};
  openZoneEditor: () => void = (): void => {};

  build() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text('后台预加载页数')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Text('数值越小越省流量，越大翻页越顺')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

      }
      .width('100%')
      .constraintSize({ minHeight: 48 })
      .alignItems(VerticalAlign.Center)

      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ForEach(PRELOAD_LEVELS, (count: number) => {
          Button(`${count}页`, { type: ButtonType.Capsule, buttonStyle: this.preloadCount === count ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.NORMAL })
            .height(40).fontSize(14)
            .backgroundColor(this.preloadCount === count ? PRIMARY : SUB_CARD)
            .fontColor(this.preloadCount === count ? Color.White : TEXT_SUB)
            .onClick(() => this.setPreload(count))
        }, (count: number): string => `${count}`)
      }.width('100%')

      Divider()
        .strokeWidth(0.5)
        .color($r('sys.color.comp_divider'))

      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text('触控热区分配')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Text(this.zonePresetLabel())
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([$r('sys.color.font_secondary')])
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

  private zonePresetLabel(): string {
    const isClassic: boolean = this.options.taps.every((value: number, index: number): boolean =>
      value === DEFAULT_TAPS[index]);
    return isClassic ? '经典左右翻页' : '已自定义';
  }
}
