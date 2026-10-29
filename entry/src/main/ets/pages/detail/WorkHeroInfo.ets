import { MetadataSearchChip } from '../search/MetadataSearchChip';
import { WorkTags } from './WorkTags';
import { Album, Chapter, ReadingProgress, MetadataTerm } from '../../models/Models';
import { sourceId } from '../../data/Sources';
import { capabilitiesForSourceId } from '../../data/source/SourceContracts';
import { presentationFor } from '../../data/source/SourceCatalog';
import { LibraryWork } from '../../data/Library';
import { SourceCover } from '../../common/SourceCover';
import { BG, CARD, SUB_CARD, PRIMARY, PRIMARY_SOFT, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';

@Component
export struct WorkHeroInfo {
  @Link album: Album | null;
  @StorageProp('currentBreakpoint') breakpoint: string = 'sm';
  @Consume('navPathStack') stack: NavPathStack;
  @Link sourceName: string;
  @Prop aid: string = '';
  @Prop fromLibrary: boolean = false;
  @Link work: LibraryWork | null;
  @Link sourceSheet: boolean;
  @Link progress: ReadingProgress | null;
  read: (chapter?: Chapter) => void = (chapter?: Chapter): void => {};
  reread: () => void = (): void => {};
  add: () => Promise<void> = async (): Promise<void> => {};
  toggleShelf: () => Promise<void> = async (): Promise<void> => {};
  download: () => Promise<void> = async (): Promise<void> => {};
  @Link descExpanded: boolean;
  @Prop topInset: number = 0;

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
              radius: 14
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

            if (this.fromLibrary) {
              Row({ space: 4 }) {
                Text(this.sourceBadge())
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PRIMARY)

                if (this.work !== null && this.work.albums.length > 1) {
                  Text(`（${this.work.albums.length}源）`)
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(PRIMARY)
                }
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(12)
                  .fontColor([PRIMARY])
              }
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(8)
              .backgroundColor(PRIMARY_SOFT)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
              .onClick(() => {
                this.sourceSheet = true;
              })
            } else {
              Row() {
                Text(this.sourceBadge())
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PRIMARY)
              }
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(8)
              .backgroundColor(PRIMARY_SOFT)
            }

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

        // 动作栏：主阅读 CTA + 收藏 + 下载（换源移至标题栏菜单）
        Row({ space: 8 }) {
          Button(this.canContinue() ? this.continueLabel() : '开始阅读', {
            type: ButtonType.Capsule,
            buttonStyle: ButtonStyleMode.EMPHASIZED
          })
            .layoutWeight(1)
            .height(42)
            .onClick(() => { this.read(); })

          Row() {
            SymbolGlyph(this.work !== null ? $r('sys.symbol.bookmark_fill') : $r('sys.symbol.bookmark'))
              .fontSize(20)
              .fontColor([this.work !== null ? PRIMARY : TEXT_MAIN])
          }
          .width(42)
          .height(42)
          .justifyContent(FlexAlign.Center)
          .borderRadius(21)
          .backgroundColor(this.work !== null ? PRIMARY_SOFT : SUB_CARD)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
          .accessibilityText(this.work !== null ? '已在书架，点按移出' : '加入书架')
          .onClick(() => {
            this.toggleShelf();
          })

          Row() {
            SymbolGlyph($r('sys.symbol.arrow_down_circle'))
              .fontSize(20)
              .fontColor([TEXT_MAIN])
          }
          .width(42)
          .height(42)
          .justifyContent(FlexAlign.Center)
          .borderRadius(21)
          .backgroundColor(SUB_CARD)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
          .accessibilityText('下载')
          .onClick(() => {
            this.download();
          })
        }
        .width('100%')

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
          .width('100%')
          .onClick(() => {
            this.descExpanded = !this.descExpanded;
          })
        }

        if (this.album.tags.length > 0) {
          WorkTags({ aid: this.aid, terms: this.album.tags, sourceId: sourceId(this.aid), sourceName: this.sourceName })
        }
      }
      .padding({ left: 16, right: 16, top: this.topInset + 12, bottom: 16 })
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .background(this.HeroBackdrop(), { align: Alignment.Top })
    }
  }

  /** 沉浸式头部背景：封面高斯模糊铺满标题栏下方，再以渐变过渡到页面底色。 */
  @Builder
  HeroBackdrop() {
    if (this.album !== null) {
      Stack({ alignContent: Alignment.Top }) {
        Column() {
          SourceCover({ url: this.album.coverUrl, sourceKey: this.aid, radius: 0 })
        }
        .width('100%')
        .blur(40)
        .opacity(0.55)

        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: [['rgba(0,0,0,0)', 0.0], [BG, 0.92]]
          })
      }
      .width('100%')
      .height(this.topInset + 240)
      .clip(true)
    }
  }
}
