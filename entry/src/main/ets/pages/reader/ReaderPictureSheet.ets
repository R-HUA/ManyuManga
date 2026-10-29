/**
 * entry/src/main/ets/pages/reader/ReaderPictureSheet.ets
 * 阅读器底部「画面」浮卡内容：随底栏胶囊上方展开，与工具栏共享调色板，不占用整屏半模态。
 */
import { PRIMARY, PRIMARY_SOFT } from '../../common/Theme';
import { EMPTY_MATERIAL } from '../../common/ImmersiveMaterials';
import { ReaderOptions, EYE_COMFORT_DEFAULT, EYE_COMFORT_MAX, EYE_COMFORT_MIN } from '../../data/ReaderOptions';

@Component
export struct ReaderPictureSheet {
  @Link options: ReaderOptions;
  @Link brightnessValue: number;
  @Link bgPaper: boolean;
  buildSpreads: () => void = (): void => {};
  scrollToPageDelayed: (page: number) => void = (page: number): void => {};
  @Link currentPage: number;
  persistOptions: () => Promise<void> = async (): Promise<void> => {};
  toggleBackground: (paper: boolean) => void = (paper: boolean): void => {};

  build() {
    Column({ space: 10 }) {
      this.SliderRow('亮度', this.brightnessValue, '%', 10, 100, (value: number): void => {
        this.brightnessValue = value;
      })

      Row({ space: 10 }) {
        Text('画布底色')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
          .width(66)

        Row({ space: 8 }) {
          this.CanvasChip('深色画布', !this.bgPaper, (): void => {
            this.toggleBackground(false);
          })
          this.CanvasChip('纸质护眼', this.bgPaper, (): void => {
            this.toggleBackground(true);
          })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })

      Divider()
        .strokeWidth(0.5)
        .color($r('sys.color.comp_divider'))

      this.SwitchRow('双页模式封面独占首页', this.options.coverOffset, (value: boolean): void => {
        this.options.coverOffset = value;
        this.buildSpreads();
        this.scrollToPageDelayed(this.currentPage);
        this.persistOptions();
      })

      this.SwitchRow('智能裁切页面四周白边', this.options.cropWhite, (value: boolean): void => {
        this.options.cropWhite = value;
        this.persistOptions();
      })

      this.SwitchRow('夜间暖色温护眼滤镜', this.options.eyeComfort > 0, (value: boolean): void => {
        this.options.eyeComfort = value ? (this.options.eyeComfort > 0 ? this.options.eyeComfort
          : EYE_COMFORT_DEFAULT) : 0;
        this.persistOptions();
      })

      if (this.options.eyeComfort > 0) {
        this.SliderRow('滤镜强度', this.options.eyeComfort, '%', EYE_COMFORT_MIN, EYE_COMFORT_MAX,
          (value: number): void => {
            this.options.eyeComfort = value;
            this.persistOptions();
          })
      }
    }
    .width('100%')
  }

  @Builder
  private CanvasChip(label: string, active: boolean, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontWeight(active ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(active ? PRIMARY : $r('sys.color.font_secondary'))
    }
    .layoutWeight(1)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .borderRadius(17)
    .backgroundColor(active ? PRIMARY_SOFT : Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  private SwitchRow(label: string, isOn: boolean, onToggle: (value: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .systemMaterial(EMPTY_MATERIAL)
        .selectedColor(PRIMARY)
        .onChange((value: boolean) => {
          onToggle(value);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 40 })
  }

  @Builder
  private SliderRow(label: string, value: number, unit: string, min: number, max: number,
    onChange: (value: number) => void) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .width(66)
      Slider({ value: value, min: min, max: max, step: 1, style: SliderStyle.OutSet })
        .showTips(false)
        .systemMaterial(EMPTY_MATERIAL)
        .selectedColor(PRIMARY)
        .layoutWeight(1)
        .onChange((next: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click ||
            mode === SliderChangeMode.Moving) {
            onChange(Math.round(next));
          }
        })
      Text(`${Math.round(value)}${unit}`)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width(40)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .constraintSize({ minHeight: 36 })
  }
}
