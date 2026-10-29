/**
 * 设置子页共用的列表行：配合 List + ListItemGroup({ header, footer }) 使用，行间分隔由 ListItemGroup.divider 提供。
 */
import { IMMERSIVE_REGULAR_MATERIAL } from '../../common/ImmersiveMaterials';
import { CARD, PRIMARY, TEXT_MAIN, TEXT_SUB, DANGER } from '../../common/Theme';

export const SETTINGS_ROW_RADIUS: number = 16;

/** 同组首尾两行圆角，组内其余行直角，使整组呈现为一张卡片。 */
export function settingsRowRadius(index: number, count: number): BorderRadiuses {
  const top: number = index === 0 ? SETTINGS_ROW_RADIUS : 0;
  const bottom: number = index === count - 1 ? SETTINGS_ROW_RADIUS : 0;
  const radius: BorderRadiuses = { topLeft: top, topRight: top, bottomLeft: bottom, bottomRight: bottom };
  return radius;
}

export const SETTINGS_CARD: ResourceColor = CARD;

@Component
export struct SettingsToggleRow {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop isOn: boolean = false;
  @Prop switchEnabled: boolean = true;
  onToggle: (value: boolean) => void = (_value: boolean): void => {};

  build() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_MAIN)
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor(TEXT_SUB)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(PRIMARY)
        .systemMaterial(IMMERSIVE_REGULAR_MATERIAL)
        .enabled(this.switchEnabled)
        .onChange((value: boolean) => {
          this.onToggle(value);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct SettingsActionRow {
  @Prop title: string = '';
  @Prop value: string = '';
  @Prop danger: boolean = false;
  @Prop showChevron: boolean = true;
  @Prop rowEnabled: boolean = true;
  onTap: () => void = (): void => {};

  build() {
    Row({ space: 12 }) {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.danger ? DANGER : TEXT_MAIN)
        .layoutWeight(1)
      if (this.value !== '') {
        Text(this.value)
          .fontSize(14)
          .fontColor(TEXT_SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.showChevron) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([TEXT_SUB])
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center)
    .opacity(this.rowEnabled ? 1 : 0.5)
    .onClick(() => {
      if (this.rowEnabled) {
        this.onTap();
      }
    })
  }
}
