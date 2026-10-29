import { SymbolGlyphModifier } from '@ohos.arkui.modifier';
import { PRIMARY, PRIMARY_SOFT, TEXT_MAIN, TEXT_SUB, SUB_CARD, DIVIDER, COVER_R, COVER_ASPECT_RATIO } from './Theme';
/**
 * 全局复用组件
 */

/**
 * 原生规范圆形图标按钮（40vp 外径 + 22fp 居中 SymbolGlyph）
 */
@Component
export struct IconCircleButton {
  @Prop symbol?: Resource = undefined;
  @Prop glyph: Resource = $r('sys.symbol.ellipsis_circle');
  @Prop active: boolean = false;
  @Prop btnSize: number = 40;
  @Prop iconSize: number = 22;
  @Prop iconColor: ResourceColor = TEXT_MAIN;
  @Prop bg: ResourceColor = Color.Transparent;
  onTap: () => void = () => {};

  build() {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
      Row() {
        SymbolGlyph(this.symbol ?? this.glyph)
          .fontSize(this.iconSize)
          .fontWeight(FontWeight.Medium)
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .fontColor([this.active ? PRIMARY : this.iconColor])
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .width(this.btnSize)
    .height(this.btnSize)
    .backgroundColor(this.active ? PRIMARY_SOFT : this.bg)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
    .onClick(() => {
      this.onTap();
    })
  }
}

/**
 * 官方风格设置下拉行（对齐系统设置选项规范，带右侧勾选标记与无底色原生菜单）
 */
@Component
export struct SettingSelectRow {
  @Prop title: ResourceStr = '';
  @Prop subtitle: string = '';
  @Prop options: Array<ResourceStr> = [];
  @Prop selectedIndex: number = 0;
  onChanged: (index: number) => void = () => {};

  @Builder
  private DropdownMenu() {
    Menu() {
      ForEach(this.options, (item: ResourceStr, idx: number) => {
        MenuItem({
          content: item,
          symbolEndIcon: this.selectedIndex === idx ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
        })
          .onClick(() => {
            this.onChanged(idx);
          })
      })
    }
  }

  build() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row({ space: 4 }) {
        Text(this.options[this.selectedIndex] ?? '')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
        SymbolGlyph($r('sys.symbol.arrowtriangle_down_fill'))
          .fontSize(10)
          .fontColor([$r('sys.color.font_secondary')])
      }
      .constraintSize({ minHeight: 40 })
      .padding({ left: 8, top: 4, bottom: 4 })
      .alignItems(VerticalAlign.Center)
      .bindMenu(this.DropdownMenu)
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .alignItems(VerticalAlign.Center)
  }
}

/**
 * 空态/错误态视图
 */
@Component
export struct EmptyView {
  @Prop quiet: boolean = false;
  @Prop message: ResourceStr = '暂无内容';
  @Prop retryText: ResourceStr = '重试';
  @Prop showRetry: boolean = true;
  onRetry: () => void = () => {};

  build() {
    Column({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.folder_fill'))
          .fontSize(this.quiet ? 60 : 30)
          .fontColor([this.quiet ? $r('sys.color.icon_tertiary') : TEXT_SUB])
      }
      .width(64)
      .height(64)
      .borderRadius(32)
      .backgroundColor(this.quiet ? Color.Transparent : SUB_CARD)

      Text(this.message)
        .fontSize(14)
        .fontColor(this.quiet ? $r('sys.color.font_tertiary') : TEXT_SUB)
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .lineHeight(20)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.showRetry) {
        Button(this.retryText, { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
          .height(36)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .padding({ left: 24, right: 24 })
          .onClick(() => {
            this.onRetry();
          })
      }
    }
    .width('100%')
    .padding({ left: 32, right: 32, top: 48, bottom: 48 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

/**
 * 标签胶囊：选中态使用浅底 + 品牌色文字，不叠加实心色块与描边
 */
@Component
export struct TagChip {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  onChipClick: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(12)
      .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.selected ? PRIMARY : TEXT_MAIN)
      .maxLines(1)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .constraintSize({ minHeight: 32 })
      .backgroundColor(this.selected ? PRIMARY_SOFT : SUB_CARD)
      .borderRadius(16)
      .onClick(() => {
        this.onChipClick();
      })
  }
}

/**
 * 卡片网格骨架
 */
@Component
export struct SkeletonGrid {
  @Prop columns: number = 3;
  @Prop rows: number = 3;
  @State skelAlpha: number = 1.0;

  private rowIndexes(): number[] {
    const list: number[] = [];
    for (let i = 0; i < this.rows; i++) {
      list.push(i);
    }
    return list;
  }

  private columnIndexes(): number[] {
    const list: number[] = [];
    for (let i = 0; i < this.columns; i++) {
      list.push(i);
    }
    return list;
  }

  build() {
    Column({ space: 14 }) {
      ForEach(this.rowIndexes(), (rowIndex: number) => {
        Row({ space: 12 }) {
          ForEach(this.columnIndexes(), (colIndex: number) => {
            Column({ space: 6 }) {
              Column()
                .width('100%')
                .aspectRatio(COVER_ASPECT_RATIO)
                .borderRadius(COVER_R)
                .backgroundColor(DIVIDER)
                .opacity(this.skelAlpha)
              Column()
                .height(12)
                .width('85%')
                .borderRadius(4)
                .backgroundColor(DIVIDER)
                .opacity(this.skelAlpha)
              Column()
                .height(10)
                .width('55%')
                .borderRadius(4)
                .backgroundColor(DIVIDER)
                .opacity(this.skelAlpha)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }, (colIndex: number) => 'skel_c_' + colIndex.toString())
        }
        .width('100%')
      }, (rowIndex: number) => 'skel_r_' + rowIndex.toString())
    }
    .width('100%')
    .onAppear(() => {
      this.getUIContext().animateTo(
        { duration: 800, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate },
        () => {
          this.skelAlpha = 0.35;
        }
      );
    })
  }
}

export { ComicCard } from './ComicCard';
