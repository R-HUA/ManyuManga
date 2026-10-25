import { CHIP_BG, CHIP_R, COVER_ASPECT_RATIO, COVER_R, FONT_BADGE, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
import { AlbumLite } from '../../models/Models';
import { sourceApi as jmApi } from '../../data/SourceApi';
import { langBadgeFor } from '../../common/ComicBadge';
@Component
export struct AlbumCard {
  @Prop item: AlbumLite = new AlbumLite();
  onCardClick: () => void = () => {};
  /** 封面图床轮换序号（评审 Step3：失败换备用图床，最多 3 次） */
  @State coverRetry: number = 0;

  /** retry>0 走 jmApi.albumThumbUrl(id, retry) 轮换域名；否则原 url（空 url 降级小图直链） */
  private coverSrc(): string {
    if (this.coverRetry > 0 && this.item.id !== '') {
      return jmApi.albumThumbUrl(this.item.id, this.coverRetry);
    }
    return this.item.coverUrl === '' ? jmApi.albumThumbUrl(this.item.id) : this.item.coverUrl;
  }

  private badge(): string {
    return langBadgeFor(this.item);
  }

  @Builder
  private Capsule(label: string) {
    Text(label)
      .fontSize(FONT_BADGE)
      .fontColor(TEXT_SUB)
      .maxLines(1)
      .padding({ left: 7, right: 7, top: 2, bottom: 2 })
      .backgroundColor(CHIP_BG)
      .borderRadius(CHIP_R)
  }

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(this.coverSrc())
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .backgroundColor(CHIP_BG)
          .onError(() => {
            if (this.coverRetry < 3 && this.item.id !== '') {
              this.coverRetry += 1;
            }
          })
        if (this.badge() !== '') {
          Text(this.badge())
            .fontSize(FONT_BADGE)
            .fontColor(Color.White)
            .maxLines(1)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor('rgba(14,17,26,0.78)')
            .borderRadius(9)
            .margin(6)
        }
      }
      .width('100%')
      .aspectRatio(COVER_ASPECT_RATIO)
      .borderRadius(COVER_R)
      .clip(true)
      .border({ width: 0.5, color: 'rgba(255,255,255,0.15)' })

      Text(this.item.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_MAIN)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (this.item.category !== '' || this.item.categorySub !== '') {
        Row({ space: 4 }) {
          if (this.item.category !== '') {
            this.Capsule(this.item.category)
          }
          if (this.item.categorySub !== '') {
            this.Capsule(this.item.categorySub)
          }
        }
        .width('100%')
      } else if (this.item.author !== '') {
        Text(this.item.author)
          .fontSize(11)
          .fontColor(TEXT_SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onCardClick();
    })
  }
}
