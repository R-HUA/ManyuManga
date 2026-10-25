import { ChipOption } from './ReaderControls';
import uiMaterial from '@ohos.arkui.uiMaterial';
import { PRIMARY, ACCENT } from '../../common/Theme';
import { ReaderOptions } from '../../data/ReaderOptions';

const PANEL_BG: string = 'rgba(28,28,32,0.82)';

@Component
export struct ReaderSettingsPanel {
  @Link options: ReaderOptions;
  buildSpreads: () => void = (): void => {};
  scrollToPageDelayed: (page: number) => void = (page: number): void => {};
  @Link currentPage: number;
  persistOptions: () => Promise<void> = async (): Promise<void> => {};
  @Link preloadCount: number;
  setPreload: (n: number) => void = (n: number): void => {};

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Text('双页模式封面独占首页')
            .fontSize(13)
            .fontColor(Color.White)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.options.coverOffset })
            .selectedColor(PRIMARY)
            .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
            .onChange((value: boolean) => {
              this.options.coverOffset = value;
              this.buildSpreads();
              this.scrollToPageDelayed(this.currentPage);
              this.persistOptions();
            })
        }
        .width('100%')

        Row() {
          Text('智能裁切页面四周白边')
            .fontSize(13)
            .fontColor(Color.White)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.options.cropWhite })
            .selectedColor(PRIMARY)
            .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
            .onChange((value: boolean) => {
              this.options.cropWhite = value;
              this.persistOptions();
            })
        }
        .width('100%')

        Row() {
          Text('夜间暖色温护眼滤镜')
            .fontSize(13)
            .fontColor(Color.White)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.options.eyeComfort })
            .selectedColor(PRIMARY)
            .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
            .onChange((value: boolean) => {
              this.options.eyeComfort = value;
              this.persistOptions();
            })
        }
        .width('100%')

        Column({ space: 8 }) {
          Row() {
            Text('九宫格触控热区（点按格子切换动作）')
              .fontSize(12)
              .fontColor('rgba(255,255,255,0.78)')
              .layoutWeight(1)
            Text('恢复默认')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor(PRIMARY)
              .onClick(() => {
                this.options.taps = [1, 0, 2, 1, 0, 2, 1, 0, 2];
                this.persistOptions();
              })
          }
          .width('100%')

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8], (index: number) => {
              Column({ space: 2 }) {
                Text(this.tapActionLabel(this.options.taps[index]))
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
              }
              .width('31.5%')
              .height(38)
              .margin({ bottom: 6 })
              .justifyContent(FlexAlign.Center)
              .borderRadius(10)
              .backgroundColor(this.tapActionColor(this.options.taps[index]))
              .border({ width: 0.5, color: 'rgba(255,255,255,0.16)' })
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
              .onClick(() => {
                const taps: Array<number> = this.options.taps.slice();
                taps[index] = (taps[index] + 1) % 5;
                this.options.taps = taps;
                this.persistOptions();
              })
            }, (index: number) => `tap_${index}_${this.options.taps[index]}`)
          }
          .width('100%')
        }
        .width('100%')

        Column({ space: 8 }) {
          Text('后台预加载页数档位')
            .fontSize(12)
            .fontColor('rgba(255,255,255,0.78)')
            .width('100%')
          Row({ space: 8 }) {
            ChipOption({
              label: '省流 1页', selected: this.preloadCount === 1,
              onTap: (): void => {
                this.setPreload(1);
              }
            })
            ChipOption({
              label: '标准 3页', selected: this.preloadCount === 3,
              onTap: (): void => {
                this.setPreload(3);
              }
            })
            ChipOption({
              label: '进取 5页', selected: this.preloadCount === 5,
              onTap: (): void => {
                this.setPreload(5);
              }
            })
            ChipOption({
              label: '极速 8页', selected: this.preloadCount === 8,
              onTap: (): void => {
                this.setPreload(8);
              }
            })
          }
          .width('100%')
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .borderRadius(18)
      .backgroundColor(PANEL_BG)
      .border({ width: 0.5, color: 'rgba(255,255,255,0.12)' })
    }
    .constraintSize({ maxHeight: 390 })
    .scrollBar(BarState.Off)
    .width('100%')
  }

  private tapActionLabel(action: number): string {
    const labels: Array<string> = ['呼出菜单', '上一页', '下一页', '上一话', '下一话'];
    return labels[action] ?? '呼出菜单';
  }

  private tapActionColor(action: number): ResourceColor {
    if (action === 0) {
      return PRIMARY;
    }
    if (action === 2 || action === 4) {
      return ACCENT;
    }
    return 'rgba(255,255,255,0.22)';
  }
}
