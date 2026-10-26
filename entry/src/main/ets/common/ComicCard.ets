import { TEXT_MAIN, TEXT_SUB, DIVIDER, CHIP_BG, COVER_R, COVER_ASPECT_RATIO } from './Theme';
import { SourceCover } from './SourceCover';
import { sourceApi } from '../data/SourceApi';
import { sourceId } from '../data/Sources';
import { capabilitiesForSourceId } from '../data/source/SourceContracts';
@Component
export struct ComicCard {
  @Prop @Watch('onCoverUrl') coverUrl: string = '';
  @Prop aid: string = '';
  @Prop title: string = '';
  @Prop author: string = '';
  @Prop badge: string = '';
  @Prop loading: boolean = false;
  onCardClick: () => void = () => {};

  @State skelAlpha: number = 1.0;
  @State coverRetry: number = 0;

  private onCoverUrl(): void {
    this.coverRetry = 0;
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
