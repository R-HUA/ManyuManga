import { PRIMARY } from '../../common/Theme';

@Component
export struct HudButton {
  @Prop symbol: Resource = $r('sys.symbol.list_bullet');
  @Prop label: string = '';
  @Prop active: boolean = false;
  onTap: () => void = (): void => {
  };

  build() {
    Column({ space: 4 }) {
      SymbolGlyph(this.symbol)
        .fontSize(20)
        .fontColor([this.active ? Color.White : 'rgba(255,255,255,0.92)'])
      Text(this.label)
        .fontSize(11)
        .fontWeight(this.active ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.active ? Color.White : 'rgba(255,255,255,0.82)')
    }
    .layoutWeight(1)
    .height(52)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(16)
    .backgroundColor(this.active ? PRIMARY : 'rgba(255,255,255,0.08)')
    .border({ width: 0.5, color: this.active ? PRIMARY : 'rgba(255,255,255,0.12)' })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
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

@Component
export struct ModeOptionRow {
  @Prop label: string = '';
  @Prop sub: string = '';
  @Prop selected: boolean = false;
  onPick: () => void = (): void => {
  };

  build() {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(this.label)
          .fontSize(14)
          .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.selected ? PRIMARY : 'rgba(255,255,255,0.92)')
        Text(this.sub)
          .fontSize(11)
          .fontColor('rgba(255,255,255,0.52)')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.selected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([PRIMARY])
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .borderRadius(14)
    .backgroundColor(this.selected ? 'rgba(58,122,254,0.18)' : 'rgba(255,255,255,0.06)')
    .border({ width: 0.5, color: this.selected ? PRIMARY : 'rgba(255,255,255,0.08)' })
    .onClick(() => {
      this.onPick();
    })
  }
}
