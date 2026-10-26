import { ChipOption } from './ReaderControls';
import { IMMERSIVE_REGULAR_MATERIAL } from '../../common/ImmersiveMaterials';
import { PRIMARY } from '../../common/Theme';
import { Prefs } from '../../util/Prefs';

const PANEL_BG: string = 'rgba(28,28,32,0.82)';

@Component
export struct ReaderDisplayPanel {
  @Link brightnessValue: number;
  @Link bgPaper: boolean;
  toggleBackground: (paper: boolean) => void = (paper: boolean): void => {};

  build() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text('亮度')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F2F2F4')
          .width(38)
        Slider({ value: this.brightnessValue, min: 10, max: 100, step: 1, style: SliderStyle.OutSet })
          .selectedColor(PRIMARY)
          .trackColor('rgba(255,255,255,0.25)')
          .blockColor(Color.White)
          .systemMaterial(IMMERSIVE_REGULAR_MATERIAL)
          .layoutWeight(1)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.brightnessValue = value;
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              Prefs.getInstance()
                .then((p: Prefs): Promise<void> => p.setBrightness(value))
                .catch((e: Error): void => {
                });
            }
          })
        Text(`${Math.round(this.brightnessValue)}%`)
          .fontSize(12)
          .fontColor('rgba(255,255,255,0.75)')
          .width(36)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      Row({ space: 10 }) {
        Text('画布')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F2F2F4')
          .width(38)
        ChipOption({
          label: '深色纯黑', selected: !this.bgPaper,
          onTap: (): void => {
            this.toggleBackground(false);
          }
        })
        ChipOption({
          label: '纸质护眼', selected: this.bgPaper,
          onTap: (): void => {
            this.toggleBackground(true);
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius(18)
    .backgroundColor(PANEL_BG)
    .border({ width: 0.5, color: 'rgba(255,255,255,0.12)' })
  }
}
