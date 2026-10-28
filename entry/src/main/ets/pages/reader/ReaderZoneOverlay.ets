/**
 * entry/src/main/ets/pages/reader/ReaderZoneOverlay.ets
 * 阅读器三级触控热区校准蒙层：35% 低透明彩色网格直接覆盖真实漫画画布，
 * 点按任意格子循环其动作，顶部提供恢复默认与完成保存。
 */
import { DEFAULT_TAPS, ReaderOptions, TAP_ACTIONS } from '../../data/ReaderOptions';
import {
  HUD_BORDER, HUD_CAPSULE, HUD_TEXT, HUD_TEXT_SUB,
  PRIMARY, ZONE_MENU, ZONE_NEXT, ZONE_IDLE, ZONE_PREV
} from '../../common/Theme';

@Component
export struct ReaderZoneOverlay {
  @Link options: ReaderOptions;
  @Link topSafeVp: number;
  persistOptions: () => Promise<void> = async (): Promise<void> => {};
  close: () => void = (): void => {};

  build() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('触控热区')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(HUD_TEXT)
          Text('点按格子切换该区域动作')
            .fontSize(11)
            .fontColor(HUD_TEXT_SUB)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button('恢复默认', { type: ButtonType.Capsule, stateEffect: true })
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(HUD_TEXT)
          .backgroundColor(HUD_CAPSULE)
          .border({ width: 0.5, color: HUD_BORDER })
          .height(32)
          .onClick(() => {
            this.options.taps = DEFAULT_TAPS.slice();
            this.persistOptions();
          })
        Button('完成', { type: ButtonType.Capsule, stateEffect: true })
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor(PRIMARY)
          .height(32)
          .onClick(() => {
            this.persistOptions();
            this.close();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .borderRadius(20)
      .backgroundColor(HUD_CAPSULE)
      .border({ width: 0.5, color: HUD_BORDER })
      .alignItems(VerticalAlign.Center)

      Grid() {
        ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8], (index: number) => {
          GridItem() {
            Column({ space: 3 }) {
              Text(TAP_ACTIONS[this.actionAt(index)])
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(HUD_TEXT)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.zoneHint(this.actionAt(index)))
                .fontSize(10)
                .fontColor(HUD_TEXT_SUB)
                .maxLines(1)
            }
            .justifyContent(FlexAlign.Center)
            .width('100%')
            .height('100%')
            .backgroundColor(this.zoneColor(this.actionAt(index)))
            .borderRadius(10)
            .border({ width: 0.5, color: HUD_BORDER })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
            .onClick(() => {
              const taps: Array<number> = this.options.taps.slice();
              taps[index] = (taps[index] + 1) % TAP_ACTIONS.length;
              this.options.taps = taps;
            })
          }
        }, (index: number): string => `zone_${index}_${this.actionAt(index)}`)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .rowsTemplate('1fr 1fr 1fr')
      .columnsGap(8)
      .rowsGap(8)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: this.topSafeVp + 10, bottom: 20 })
    .backgroundColor('rgba(8,10,16,0.35)')
    .hitTestBehavior(HitTestMode.Block)
  }

  private actionAt(index: number): number {
    const value: number = this.options.taps[index];
    return value >= 0 && value < TAP_ACTIONS.length ? value : 0;
  }

  private zoneColor(action: number): string {
    if (action === 0) {
      return ZONE_MENU;
    }
    if (action === 1 || action === 3) {
      return ZONE_PREV;
    }
    if (action === 2 || action === 4) {
      return ZONE_NEXT;
    }
    return ZONE_IDLE;
  }

  private zoneHint(action: number): string {
    if (action === 0) {
      return '菜单';
    }
    if (action === 3 || action === 4) {
      return '跨话';
    }
    return '翻页';
  }
}
