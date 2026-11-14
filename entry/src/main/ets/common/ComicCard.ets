import { TEXT_MAIN, TEXT_SUB, DIVIDER, CHIP_BG, COVER_R, COVER_ASPECT_RATIO, ON_OVERLAY, OVERLAY_SCRIM } from './Theme';
import { SourceCover } from './SourceCover';
import { sourceApi } from '../data/SourceApi';
import { sourceId } from '../data/Sources';
import { capabilitiesForSourceId } from '../data/source/SourceContracts';
/** 本次运行中已经显示过的普通封面地址：再次出现（滚动回来、切换页签）时直接显示，不再淡入。 */
const shownCovers: Set<string> = new Set<string>();
const SHOWN_COVERS_CAP: number = 600;

function markCoverShown(src: string): void {
  if (shownCovers.size >= SHOWN_COVERS_CAP) {
    shownCovers.clear();
  }
  shownCovers.add(src);
}

@Component
export struct ComicCard {
  @Prop @Watch('onCoverUrl') coverUrl: string = '';
  @Prop aid: string = '';
  @Prop title: string = '';
  @Prop author: string = '';
  @Prop badge: string = '';
  @Prop loading: boolean = false;
  @Prop progressLabel: string = '';
  onCardClick: () => void = () => {};

  @State skelAlpha: number = 1.0;
  @State coverRetry: number = 0;
  /** 普通封面的透明度：首次加载完成后 200ms 淡入；已显示过的地址直接为 1。 */
  @State coverOpacity: number = 1;

  aboutToAppear(): void {
    this.coverOpacity = shownCovers.has(this.coverSrc()) ? 1 : 0;
  }

  private onCoverUrl(): void {
    this.coverRetry = 0;
    if (!shownCovers.has(this.coverSrc())) {
      this.coverOpacity = 0;
    }
  }

  private coverLoaded(src: string): void {
    if (shownCovers.has(src)) {
      this.coverOpacity = 1;
      return;
    }
    markCoverShown(src);
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.coverOpacity = 1;
    });
  }

  /** 需要图源身份的封面走 SourceCover。其余图源保留 Image，失败时换镜像。 */
  private signedCover(): boolean {
    if (this.aid === '') {
      return false;
    }
    try {
      return capabilitiesForSourceId(sourceId(this.aid)).signedCover;
    } catch (e) {
      return false;
    }
  }

  private coverSrc(): string {
    if (this.coverRetry > 0 && this.aid !== '' && !this.signedCover()) {
      return sourceApi.albumThumbUrl(this.aid, this.coverRetry);
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
      .fontColor(ON_OVERLAY)
      .maxLines(1)
      .constraintSize({ maxWidth: '80%' })
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .backgroundColor(OVERLAY_SCRIM)
      .borderRadius(8)
      .margin(6)
  }

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (this.loading) {
          this.CoverSkeleton()
        } else if (this.signedCover()) {
          SourceCover({ url: this.coverUrl, sourceKey: this.aid, radius: COVER_R })
          if (this.badge !== '') {
            this.Badge()
          }
        } else {
          Image(this.coverSrc())
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .opacity(this.coverOpacity)
            .onComplete(() => {
              this.coverLoaded(this.coverSrc());
            })
            .onError(() => {
              if (this.coverRetry < 3 && this.aid !== '') {
                this.coverRetry += 1;
              } else {
                this.coverOpacity = 1;
              }
            })
          if (this.badge !== '') {
            this.Badge()
          }
        }
        if (this.progressLabel !== '') {
          Column() {
            Blank()
            Text(this.progressLabel).fontSize(10).fontColor(ON_OVERLAY).maxLines(1)
              .width('100%').padding(6).backgroundColor(OVERLAY_SCRIM)
          }.width('100%').height('100%').hitTestBehavior(HitTestMode.None)
        }
      }
      .width('100%')
      .aspectRatio(COVER_ASPECT_RATIO)
      .backgroundColor(CHIP_BG)
      .borderRadius(COVER_R)
      .clip(true)

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
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_MAIN)
          .maxLines(2)
          .constraintSize({ minHeight: 36 })
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          Text(this.author)
            .fontSize(12)
            .fontColor(TEXT_SUB)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .constraintSize({ minHeight: 16 })
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
