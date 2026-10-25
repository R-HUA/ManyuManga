/**
 * 全局复用组件
 */
import { uiMaterial } from '@kit.ArkUI';
import {
  PRIMARY,
  PRIMARY_SOFT,
  TEXT_MAIN,
  TEXT_SUB,
  CHIP_BG,
  SUB_CARD,
  DIVIDER,
  COVER_R,
  CHIP_R,
  COVER_ASPECT_RATIO
} from './Theme';
import { sourceApi as jmApi } from '../data/SourceApi';

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
  @Prop bg: ResourceColor = SUB_CARD;
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
    .border({ width: 0.5, color: this.active ? PRIMARY : DIVIDER })
    .onClick(() => {
      this.onTap();
    })
  }
}

/**
 * 官方风格设置下拉行（对齐系统设置选项规范）
 */
@Component
export struct SettingSelectRow {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop options: Array<string> = [];
  @Prop selectedIndex: number = 0;
  onChanged: (index: number) => void = () => {};

  private selectOptions(): Array<SelectOption> {
    return this.options.map((item: string): SelectOption => ({ value: item }));
  }

  build() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Select(this.selectOptions())
        .selected(this.selectedIndex)
        .value(this.options[this.selectedIndex] ?? '')
        .font({ size: 14, weight: FontWeight.Normal })
        .fontColor($r('sys.color.font_secondary'))
        .selectedOptionFont({ size: 15, weight: FontWeight.Medium })
        .selectedOptionFontColor(PRIMARY)
        .optionFont({ size: 15, weight: FontWeight.Normal })
        .backgroundColor(Color.Transparent)
        .menuSystemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR
        }))
        .onSelect((index: number) => {
          this.onChanged(index);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .alignItems(VerticalAlign.Center)
  }
}

/**
 * 漫画卡片
 */
@Component
export struct ComicCard {
  @Prop coverUrl: string = '';
  @Prop aid: string = '';
  @Prop title: string = '';
  @Prop author: string = '';
  @Prop badge: string = '';
  @Prop loading: boolean = false;
  onCardClick: () => void = () => {};

  @State skelAlpha: number = 1.0;
  @State coverRetry: number = 0;

  private coverSrc(): string {
    if (this.coverRetry > 0 && this.aid !== '') {
      return jmApi.albumThumbUrl(this.aid, this.coverRetry);
    }
    return this.coverUrl;
  }

  private startSkeletonPulse(): void {
    this.getUIContext().animateTo(
      { duration: 800, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate },
      () => {
        this.skelAlpha = 0.35;
      }
    );
  }

  @Builder
  private CoverSkeleton() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(DIVIDER)
      .opacity(this.skelAlpha)
      .onAppear(() => {
        this.startSkeletonPulse();
      })
  }

  @Builder
  private Badge() {
    Text(this.badge)
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor(Color.White)
      .maxLines(1)
      .constraintSize({ maxWidth: '80%' })
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .backgroundColor('rgba(14,17,26,0.78)')
      .borderRadius(8)
      .margin(6)
  }

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (this.loading) {
          this.CoverSkeleton()
        } else {
          Image(this.coverSrc())
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .backgroundColor(CHIP_BG)
            .onError(() => {
              if (this.coverRetry < 3 && this.aid !== '') {
                this.coverRetry += 1;
              }
            })
          if (this.badge !== '') {
            this.Badge()
          }
        }
      }
      .width('100%')
      .aspectRatio(COVER_ASPECT_RATIO)
      .borderRadius(COVER_R)
      .clip(true)
      .border({ width: 0.5, color: DIVIDER })

      if (this.loading) {
        Column()
          .height(13)
          .width('88%')
          .borderRadius(4)
          .backgroundColor(DIVIDER)
          .opacity(this.skelAlpha)
          .onAppear(() => {
            this.startSkeletonPulse();
          })
        Column()
          .height(11)
          .width('55%')
          .borderRadius(4)
          .backgroundColor(DIVIDER)
          .opacity(this.skelAlpha)
      } else {
        Text(this.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_MAIN)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.author !== '') {
          Text(this.author)
            .fontSize(11)
            .fontColor(TEXT_SUB)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .onClick(() => {
      this.onCardClick();
    })
  }
}

/**
 * 区块标题：左侧强调竖条 + 标题 + 右侧操作
 */
@Component
export struct SectionTitle {
  @Prop title: string = '';
  @Prop actionText: string = '';
  onAction: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      Row()
        .width(4)
        .height(16)
        .borderRadius(2)
        .backgroundColor(PRIMARY)
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.actionText !== '') {
        Text(this.actionText)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(PRIMARY)
          .maxLines(1)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(PRIMARY_SOFT)
          .borderRadius(12)
          .onClick(() => {
            this.onAction();
          })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

/**
 * 空态/错误态视图
 */
@Component
export struct EmptyView {
  @Prop message: string = '暂无内容';
  @Prop retryText: string = '重试';
  @Prop showRetry: boolean = true;
  onRetry: () => void = () => {};

  build() {
    Column({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(32)
          .fontColor([TEXT_SUB])
      }
      .width(68)
      .height(68)
      .borderRadius(34)
      .backgroundColor(SUB_CARD)
      .border({ width: 0.5, color: DIVIDER })

      Text(this.message)
        .fontSize(14)
        .fontColor(TEXT_SUB)
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .lineHeight(20)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.showRetry) {
        Button(this.retryText, { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
          .height(36)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY)
          .backgroundColor(PRIMARY_SOFT)
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
 * 标签胶囊
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
      .fontColor(this.selected ? Color.White : TEXT_SUB)
      .maxLines(1)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.selected ? PRIMARY : SUB_CARD)
      .borderRadius(CHIP_R)
      .border({ width: 0.5, color: this.selected ? PRIMARY : DIVIDER })
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
