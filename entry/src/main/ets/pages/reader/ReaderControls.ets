import { HUD_TEXT, PRIMARY } from '../../common/Theme';

/**
 * 一级 HUD 底栏纯图标入口：遵循华为阅读极简悬浮胶囊风格，无文字标签，配备无障碍语义与 48vp 热区。
 */
@Component
export struct HudButton {
  @Prop symbol: Resource = $r('sys.symbol.list_bullet');
  @Prop accessibilityLabel: string = '';
  @Prop active: boolean = false;
  @Prop textColor: ResourceColor = HUD_TEXT;
  onTap: () => void = (): void => {
  };

  build() {
    Column() {
      SymbolGlyph(this.symbol)
        .fontSize(22)
        .fontColor([this.active ? PRIMARY : this.textColor])
    }
    .layoutWeight(1)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .accessibilityText(this.accessibilityLabel)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
    .onClick(() => {
      this.onTap();
    })
  }
}

@Component
export struct ChipOption {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  onTap: () => void = (): void => {
  };

  build() {
    Text(this.label)
      .fontSize(12)
      .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.selected ? Color.White : 'rgba(255,255,255,0.78)')
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(this.selected ? PRIMARY : 'rgba(255,255,255,0.10)')
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
      .onClick(() => {
        this.onTap();
      })
  }
}
