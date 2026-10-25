import { MangaRouteParams, ROUTE_SEARCH } from '../../common/Route';
import { Album, Chapter, ReadingProgress } from '../../models/Models';
import { sourceId } from '../../data/Sources';
import { LibraryWork } from '../../data/Library';
import { SourceCover } from '../../common/SourceCover';
import { BG, CARD, PRIMARY, PRIMARY_SOFT, TEXT_MAIN, TEXT_SUB, DIVIDER } from '../../common/Theme';

@Component
export struct WorkHeroInfo {
  @Link album: Album | null;
  @Link coverTint: string;
  @StorageProp('currentBreakpoint') breakpoint: string = 'sm';
  @Consume('navPathStack') stack: NavPathStack;
  @Link sourceName: string;
  @Prop aid: string = '';
  @Link work: LibraryWork | null;
  @Link sourceSheet: boolean;
  @Link progress: ReadingProgress | null;
  read: (chapter?: Chapter) => void = (chapter?: Chapter): void => {};
  add: () => Promise<void> = async (): Promise<void> => {};
  download: () => Promise<void> = async (): Promise<void> => {};
  @Link descExpanded: boolean;

  build() {
    if (this.album !== null) {
      Column({ space: 16 }) {
        // Hero Row: Cover + Metadata
        Row({ space: 16 }) {
          Column() {
            SourceCover({
              url: this.album.coverUrl,
              radius: 14,
              deriveColor: true,
              onColor: (color: string): void => {
                this.coverTint = color;
              }
            })
          }
          .width(this.breakpoint === 'sm' ? 118 : 148)
          .aspectRatio(0.75)

          Column({ space: 8 }) {
            Text(this.album.name)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_MAIN)
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            if (this.album.author.length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.album.author, (author: string) => {
                  Text(author)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(PRIMARY)
                    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    .margin({ right: 6, bottom: 6 })
                    .borderRadius(12)
                    .backgroundColor(PRIMARY_SOFT)
                    .onClick(() => {
                      this.stack.pushPathByName(ROUTE_SEARCH, { query: author } as MangaRouteParams);
                    })
                }, (author: string) => author)
              }
            }

            // Multi-Source Aggregation Capsule
            Row({ space: 6 }) {
              Text(this.sourceName || sourceId(this.aid).toUpperCase())
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(8)
                .backgroundColor(PRIMARY)

              Text(this.work !== null && this.work.albums.length > 1
                ? `已关联 ${this.work.albums.length} 个书源 · 点击换源`
                : '更多书源 · 点击比对')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(TEXT_MAIN)
            }
            .padding({ left: 6, right: 10, top: 5, bottom: 5 })
            .borderRadius(12)
            .backgroundColor(CARD)
            .border({ width: 0.5, color: DIVIDER })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
            .onClick(() => {
              this.sourceSheet = true;
            })

            Row({ space: 12 }) {
              Text(`共 ${this.album.episodes.length} 话`)
                .fontSize(12)
                .fontColor(TEXT_SUB)
              if (this.album.views !== '') {
                Text(`${this.album.views} 阅读`)
                  .fontSize(12)
                  .fontColor(TEXT_SUB)
              }
              if (this.album.likes !== '') {
                Text(`${this.album.likes} 喜欢`)
                  .fontSize(12)
                  .fontColor(TEXT_SUB)
              }
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        // Primary CTA Row
        Row({ space: 10 }) {
          Text(this.progress === null
            ? '开始阅读'
            : `继续阅读 · P.${this.progress.page + 1}`)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .layoutWeight(2)
            .height(44)
            .borderRadius(22)
            .backgroundColor(PRIMARY)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
            .onClick(() => {
              this.read();
            })

          Text(this.work === null ? '加入书架' : '已在书架')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.work === null ? PRIMARY : TEXT_SUB)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(44)
            .borderRadius(22)
            .backgroundColor(this.work === null ? PRIMARY_SOFT : CARD)
            .border({ width: 0.5, color: this.work === null ? PRIMARY : DIVIDER })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
            .onClick(() => {
              if (this.work === null) {
                this.add();
              } else {
                this.sourceSheet = true;
              }
            })
        }
        .width('100%')

        // Secondary Action Bar
        Row({ space: 10 }) {
          Text('下载全本')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT_MAIN)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(38)
            .borderRadius(19)
            .backgroundColor(CARD)
            .border({ width: 0.5, color: DIVIDER })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
            .onClick(() => {
              this.download();
            })

          Text('换源与关联')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT_MAIN)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(38)
            .borderRadius(19)
            .backgroundColor(CARD)
            .border({ width: 0.5, color: DIVIDER })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
            .onClick(() => {
              this.sourceSheet = true;
            })
        }
        .width('100%')

        // Description
        if (this.album.description !== '') {
          Column({ space: 6 }) {
            Text(this.album.description)
              .fontColor(TEXT_SUB)
              .fontSize(13)
              .lineHeight(20)
              .maxLines(this.descExpanded ? 50 : 3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .padding(14)
          .borderRadius(16)
          .backgroundColor(CARD)
          .border({ width: 0.5, color: DIVIDER })
          .width('100%')
          .onClick(() => {
            this.descExpanded = !this.descExpanded;
          })
        }

        // Clickable Tags
        if (this.album.tags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.album.tags, (tag: string) => {
              Text(tag)
                .fontColor(TEXT_MAIN)
                .fontSize(12)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .margin({ right: 8, bottom: 8 })
                .backgroundColor(CARD)
                .borderRadius(14)
                .border({ width: 0.5, color: DIVIDER })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
                .onClick(() => {
                  this.stack.pushPathByName(ROUTE_SEARCH, { query: tag } as MangaRouteParams);
                })
            }, (tag: string) => tag)
          }
          .width('100%')
        }
      }
      .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .linearGradient({
        angle: 180,
        colors: [[this.coverTint, 0.0], [BG, 1.0]]
      })
    }
  }
}
