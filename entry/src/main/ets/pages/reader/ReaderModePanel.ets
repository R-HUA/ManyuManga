import { ModeOptionRow } from './ReaderControls';
import { ReaderMode } from '../../models/Models';

const PANEL_BG: string = 'rgba(28,28,32,0.82)';

@Component
export struct ReaderModePanel {
  @Link mode: ReaderMode;
  switchMode: (m: ReaderMode) => void = (m: ReaderMode): void => {};

  build() {
    Column({ space: 6 }) {
      ModeOptionRow({
        label: '纵向条漫', sub: '上下连续瀑布流滚动', selected: this.mode === 'vertical',
        onPick: (): void => {
          this.switchMode('vertical');
        }
      })
      ModeOptionRow({
        label: '纵向翻页', sub: '上下整屏滑动逐页阅读', selected: this.mode === 'pagedVertical',
        onPick: (): void => { this.switchMode('pagedVertical'); }
      })
      ModeOptionRow({
        label: '左右翻页', sub: '从左向右单页整屏适配', selected: this.mode === 'horizontal',
        onPick: (): void => {
          this.switchMode('horizontal');
        }
      })
      ModeOptionRow({
        label: '日漫右翻', sub: '从右向左的自然手势翻页（进度条自动镜像）', selected: this.mode === 'rtl',
        onPick: (): void => {
          this.switchMode('rtl');
        }
      })
      ModeOptionRow({
        label: '双页拼合', sub: '封面单页 + 跨页自动识别并排', selected: this.mode === 'double',
        onPick: (): void => {
          this.switchMode('double');
        }
      })
    }
    .width('100%')
    .padding(12)
    .borderRadius(18)
    .backgroundColor(PANEL_BG)
    .border({ width: 0.5, color: 'rgba(255,255,255,0.12)' })
  }
}
