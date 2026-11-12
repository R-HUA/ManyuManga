/**
 * entry/src/main/ets/pages/reader/ReaderPrefsSheet.ets
 * 阅读器底部「设置」浮卡内容：自适应高度，不使用固定行高的 ListItemStyle.CARD，消除内容截断与压叠错位。
 */
import { PRIMARY, SUB_CARD, TEXT_SUB } from '../../common/Theme';
import { LengthMetrics } from '@kit.ArkUI';
import { PRELOAD_LEVELS, ReaderOptions } from '../../data/ReaderOptions';
import { EMPTY_MATERIAL } from '../../common/ImmersiveMaterials';

@Component
export struct ReaderPrefsSheet {
  @Link options: ReaderOptions;
  @Link preloadCount: number;
  setPreload: (n: number) => void = (n: number): void => {};
  @Link tapTurn: boolean;
  setTapTurn: (on: boolean) => void = (_on: boolean): void => {};
  /** 热区自定义入口暂不开放，保留回调供后续恢复。 */
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
          Text('点击左右两侧翻页')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Text(this.tapTurn ? '左右各四分之一翻页，中间呼出菜单' : '点按任意位置只呼出菜单')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.tapTurn })
          .systemMaterial(EMPTY_MATERIAL)
          .selectedColor(PRIMARY)
          .onChange((value: boolean) => {
            this.setTapTurn(value);
          })
      }
      .width('100%')
      .constraintSize({ minHeight: 48 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }

}
