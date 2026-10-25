/**
 * common/Components.ets —— 全局复用组件（工程架构师维护）。
 *
 * 用法示例（页面内）：
 *   import { ComicCard, SectionTitle, EmptyView, TagChip, SkeletonGrid } from '../common/Components';
 *   ComicCard({ coverUrl: a.cover, title: a.title, author: a.author, badge: '中字',
 *               loading: false, onCardClick: (): void => { this.openAlbum(a.aid) } })
 */
import { PRIMARY, TEXT_MAIN, TEXT_SUB, CHIP_BG, DIVIDER, COVER_R, CHIP_R, COVER_ASPECT_RATIO } from './Theme';
import { sourceApi as jmApi } from '../data/SourceApi';

/**
 * 漫画卡片：3:4 圆角封面 + 右上角毛玻璃胶囊角标 + 两行标题 + 作者副题 + 骨架占位。
 * 宽度由父容器网格决定（本组件 width('100%')），封面按 3:4 比例自动撑高。
 * 封面容错（评审 Step3）：加载失败时按 aid 轮换备用图床（最多 3 次），避免灰块死角。
 */
@Component
export struct ComicCard {
  @Prop coverUrl: string = '';
  /** 本子 id（封面失败换备用图床用）；空串则不轮换 */
  @Prop aid: string = '';
  @Prop title: string = '';
  @Prop author: string = '';
  /** 右上角胶囊角标文案，如 中字/日漫/韩漫/全彩；空串不显示 */
  @Prop badge: string = '';
  /** true 时整体显示骨架占位 */
  @Prop loading: boolean = false;
  onCardClick: () => void = () => {};

  @State skelAlpha: number = 1.0;
  /** 封面图床轮换序号：0 用传入 coverUrl，1~3 走 jmApi.albumThumbUrl(aid, retry) */
  @State coverRetry: number = 0;

  private coverSrc(): string {
    if (this.coverRetry > 0 && this.aid !== '') {
      return jmApi.albumThumbUrl(this.aid, this.coverRetry);
    }
    return this.coverUrl;
  }

  private startSkeletonPulse(): void {
    this.getUIContext().animateTo({ duration: 800, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate }, () => {
      this.skelAlpha = 0.35;
    });
  }

  @Builder
  private CoverSkeleton() {
    Column()
      .width('100%')
      .aspectRatio(COVER_ASPECT_RATIO)
      .borderRadius(COVER_R)
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
      .fontColor(Color.White)
      .maxLines(1)
      .constraintSize({ maxWidth: '80%' })
      .padding({ left: 6, right: 6, top: 3, bottom: 3 })
      .backgroundColor('rgba(20,20,20,0.35)')
      .backgroundBlurStyle(BlurStyle.Thin)
      .borderRadius(9)
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
            .aspectRatio(COVER_ASPECT_RATIO)
            .objectFit(ImageFit.Cover)
            .borderRadius(COVER_R)
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
      .borderRadius(COVER_R)
      .clip(true)
      .border({ width: 0.5, color: 'rgba(255,255,255,0.15)' })

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
    .onClick(() => {
      this.onCardClick();
    })
  }
}

/**
 * 区块标题：左侧粗标题 + 右侧可选操作文案（如「换一批」「查看全部 >」）。
 */
@Component
export struct SectionTitle {
  @Prop title: string = '';
  @Prop actionText: string = '';
  onAction: () => void = () => {};

  build() {
    Row() {
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.actionText !== '') {
        Text(this.actionText)
          .fontSize(13)
          .fontColor(PRIMARY)
          .maxLines(1)
          .padding({ left: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.onAction();
          })
      }
    }
    .width('100%')
  }
}

/**
 * 空态/错误态视图：图标 + 文案 + 重试按钮（错误态复用时改 message 即可）。
 */
@Component
export struct EmptyView {
  @Prop message: string = '暂无内容';
  @Prop retryText: string = '重试';
  @Prop showRetry: boolean = true;
  onRetry: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Text('🗂')
        .fontSize(44)
        .opacity(0.6)
      Text(this.message)
        .fontSize(14)
        .fontColor(TEXT_SUB)
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.showRetry) {
        Button(this.retryText)
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor(PRIMARY)
          .borderRadius(CHIP_R)
          .padding({ left: 26, right: 26, top: 8, bottom: 8 })
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
 * 标签胶囊：分类/筛选场景通用；selected 态品牌粉反白。
 */
@Component
export struct TagChip {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  onChipClick: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(12)
      .fontColor(this.selected ? Color.White : TEXT_SUB)
      .maxLines(1)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(this.selected ? PRIMARY : CHIP_BG)
      .borderRadius(CHIP_R)
      .onClick(() => {
        this.onChipClick();
      })
  }
}

/**
 * 卡片网格骨架：rows × columns 的 3:4 封面块 + 两行文字占位，带脉冲呼吸动画。
 * 直接放进 Scroll/Column 使用，无需额外高度。
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
      this.getUIContext().animateTo({ duration: 800, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate }, () => {
        this.skelAlpha = 0.35;
      })
    })
  }
}
