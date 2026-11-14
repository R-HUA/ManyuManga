import { PRIMARY, PRESS_CELL } from '../../common/Theme';

/**
 * 阅读器底栏入口：图标 + 文字，48vp 热区。颜色取系统 token，由外层 WithTheme(DARK) 固定为深色栏配色。
 */
@Component
export struct HudButton {
  @Prop symbol: Resource = $r('sys.symbol.list_bullet');
  @Prop label: string = '';
  @Prop accessibilityLabel: string = '';
  @Prop active: boolean = false;
  onTap: () => void = (): void => {
  };

  build() {
    Column({ space: 2 }) {
      SymbolGlyph(this.symbol)
        .fontSize(22)
        .fontColor([this.active ? PRIMARY : $r('sys.color.font_primary')])
      Text(this.label)
        .fontSize(12)
        .fontColor(this.active ? PRIMARY : $r('sys.color.font_secondary'))
        .maxLines(1)
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .accessibilityText(this.accessibilityLabel !== '' ? this.accessibilityLabel : this.label)
    .clickEffect(PRESS_CELL)
    .onClick(() => {
      this.onTap();
    })
  }
}
