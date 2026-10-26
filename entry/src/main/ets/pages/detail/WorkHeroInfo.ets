import { MetadataSearchChip } from '../search/MetadataSearchChip';
import { Album, Chapter, ReadingProgress, MetadataTerm } from '../../models/Models';
import { sourceId } from '../../data/Sources';
import { capabilitiesForSourceId } from '../../data/source/SourceContracts';
import { presentationFor } from '../../data/source/SourceCatalog';
import { LibraryWork } from '../../data/Library';
import { SourceCover } from '../../common/SourceCover';
import { BG, CARD, PRIMARY, PRIMARY_SOFT, DANGER, TEXT_MAIN, TEXT_SUB, DIVIDER } from '../../common/Theme';

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
  reread: () => void = (): void => {};
  add: () => Promise<void> = async (): Promise<void> => {};
  toggleShelf: () => Promise<void> = async (): Promise<void> => {};
  download: () => Promise<void> = async (): Promise<void> => {};
  @Link descExpanded: boolean;

  private canContinue(): boolean {
    const saved: ReadingProgress | null = this.progress;
    if (saved === null) {
      return false;
    }
    return saved.chapterId !== '' && saved.totalPages > 0 && saved.page >= 0 && saved.page < saved.totalPages;
  }

  private continueLabel(): string {
    const saved: ReadingProgress | null = this.progress;
    if (saved === null) {
      return '继续阅读';
    }
    return `继续阅读 P.${saved.page + 1}`;
  }

  private sourceBadge(): string {
    if (this.sourceName !== '') {
      return this.sourceName;
    }
    try {
      return presentationFor(capabilitiesForSourceId(sourceId(this.aid)).kind).shortLabel;
    } catch (e) {
      return '';
    }
  }

  build() {
    if (this.album !== null) {
      Column({ space: 16 }) {
        // Hero Row: Cover + Metadata
        Row({ space: 16 }) {
          Column() {
            SourceCover({
              url: this.album.coverUrl,
              sourceKey: this.aid,
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
                ForEach(this.album.author, (author: MetadataTerm) => {
                  MetadataSearchChip({ term: author, field: 'author', sourceId: sourceId(this.aid),
                    sourceName: this.sourceName })
                }, (author: MetadataTerm) => JSON.stringify([author.namespace, author.value]))
              }
            }

            // Multi-Source Aggregation Capsule
            Row({ space: 6 }) {
              Text(this.sourceBadge())
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(8)
                .backgroundColor(PRIMARY)

              Text(this.work !== null && this.work.albums.length > 1
                ? `已关联 ${this.work.albums.length} 个书源`
                : '查看更多书源')
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

        // 统一单行黄金动作栏：主阅读 CTA + 收藏 / 换源 / 下载
        Row({ space: 10 }) {
          Button(this.canContinue() ? this.continueLabel() : '开始阅读', { buttonStyle: ButtonStyleMode.NORMAL })
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor(PRIMARY)
            .layoutWeight(1)
            .height(46)
            .borderRadius(23)
            .shadow({ radius: 16, color: 'rgba(10, 89, 247, 0.22)', offsetY: 4 })
            .onClick(() => { this.read(); })

          // 1. 收藏/在架切换
          Column({ space: 2 }) {
            SymbolGlyph(this.work !== null ? $r('sys.symbol.bookmark_fill') : $r('sys.symbol.bookmark'))
              .fontSize(19)
              .fontColor([this.work !== null ? PRIMARY : TEXT_MAIN])
            Text(this.work !== null ? '已在架' : '收藏')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.work !== null ? PRIMARY : TEXT_SUB)
          }
          .width(54)
          .height(46)
          .justifyContent(FlexAlign.Center)
          .borderRadius(16)
          .backgroundColor(this.work !== null ? PRIMARY_SOFT : CARD)
          .border({ width: 0.5, color: this.work !== null ? PRIMARY : DIVIDER })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
          .onClick(() => {
            this.toggleShelf();
          })

          // 2. 换源与多源角标（唯一主换源入口）
          Column({ space: 2 }) {
            SymbolGlyph($r('sys.symbol.arrow_left_arrow_right'))
              .fontSize(19)
              .fontColor([this.work !== null && this.work.albums.length > 1 ? PRIMARY : TEXT_MAIN])
            Text(this.work !== null && this.work.albums.length > 1 ? `${this.work.albums.length} 源` : '换源')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.work !== null && this.work.albums.length > 1 ? PRIMARY : TEXT_SUB)
          }
          .width(54)
          .height(46)
          .justifyContent(FlexAlign.Center)
          .borderRadius(16)
          .backgroundColor(CARD)
          .border({ width: 0.5, color: DIVIDER })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
          .onClick(() => {
            this.sourceSheet = true;
          })

          // 3. 离线下载
          Column({ space: 2 }) {
            SymbolGlyph($r('sys.symbol.arrow_down_circle'))
              .fontSize(19)
              .fontColor([TEXT_MAIN])
            Text('下载')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(TEXT_SUB)
          }
          .width(54)
          .height(46)
          .justifyContent(FlexAlign.Center)
          .borderRadius(16)
          .backgroundColor(CARD)
          .border({ width: 0.5, color: DIVIDER })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
          .onClick(() => {
            this.download();
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
            ForEach(this.album.tags, (tag: MetadataTerm) => {
              MetadataSearchChip({ term: tag, sourceId: sourceId(this.aid), sourceName: this.sourceName })
            }, (tag: MetadataTerm) => JSON.stringify([tag.namespace, tag.value]))
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
