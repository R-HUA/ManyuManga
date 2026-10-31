import { pasteboard } from '@kit.BasicServicesKit';
import { MeasureOptions } from '@kit.ArkUI';
import { MetadataSearchChip } from '../search/MetadataSearchChip';
import { WorkTags } from './WorkTags';
import { Album, Chapter, ReadingProgress, MetadataTerm } from '../../models/Models';
import { sourceId } from '../../data/Sources';
import { capabilitiesForSourceId } from '../../data/source/SourceContracts';
import { presentationFor } from '../../data/source/SourceCatalog';
import { LibraryWork } from '../../data/Library';
import { SourceCover } from '../../common/SourceCover';
import { BG, ON_PRIMARY, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';

const TITLE_MAX_LINES: number = 3;
const DESC_MAX_LINES: number = 3;
const DESC_LINE_HEIGHT: number = 21;
const POPUP_TITLE_LINE_HEIGHT: number = 24;
const POPUP_TITLE_MAX_LINES: number = 8;

interface TitlePopupState { isVisible: boolean; }

@Component
export struct WorkHeroInfo {
  @Link @Watch('albumChanged') album: Album | null;
  @StorageProp('currentBreakpoint') @Watch('closeTitlePopup') breakpoint: string = 'sm';
  @Consume('navPathStack') stack: NavPathStack;
  @Link sourceName: string;
  @Prop aid: string = '';
  @Prop fromLibrary: boolean = false;
  @Link work: LibraryWork | null;
  @Link sourceSheet: boolean;
  @Link progress: ReadingProgress | null;
  read: (chapter?: Chapter) => void = (chapter?: Chapter): void => {};
  @Link descExpanded: boolean;
  @Prop topInset: number = 0;
  @State titleWidth: number = 0;
  @State titleTruncated: boolean = false;
  @State titlePopup: boolean = false;
  @State descWidth: number = 0;
  @State descOverflow: boolean = false;
  private shownAlbumId: string = '';
  private shownTitle: string = '';
  private shownDescription: string = '';

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

  aboutToAppear(): void {
    this.albumChanged();
  }

  /** 作品切换时收起简介并关闭标题浮层；标题或简介文本变化时重新测量。 */
  private albumChanged(): void {
    const current: Album | null = this.album;
    const id: string = current === null ? '' : current.id;
    if (id !== this.shownAlbumId) {
      this.shownAlbumId = id;
      this.descExpanded = false;
      this.titlePopup = false;
    }
    const title: string = current === null ? '' : current.name;
    const description: string = current === null ? '' : current.description;
    if (title !== this.shownTitle) {
      this.shownTitle = title;
      this.measureTitle();
    }
    if (description !== this.shownDescription) {
      this.shownDescription = description;
      this.measureDescription();
    }
  }

  private closeTitlePopup(): void {
    this.titlePopup = false;
  }

  /** 与 Text 同字号、字重、约束宽度下分别测量不限行与限行高度（px），前者更高即被截断。 */
  private clipped(text: string, width: number, fontSize: string | Resource, weight: FontWeight,
    lineHeight: string, maxLines: number): boolean {
    if (text === '' || width <= 0) {
      return false;
    }
    try {
      const full: MeasureOptions = {
        textContent: text, constraintWidth: width, fontSize: fontSize, fontWeight: weight
      };
      const limited: MeasureOptions = {
        textContent: text, constraintWidth: width, fontSize: fontSize, fontWeight: weight, maxLines: maxLines
      };
      if (lineHeight !== '') {
        full.lineHeight = lineHeight;
        limited.lineHeight = lineHeight;
      }
      const fullSize: SizeOptions = this.getUIContext().getMeasureUtils().measureTextSize(full);
      const limitedSize: SizeOptions = this.getUIContext().getMeasureUtils().measureTextSize(limited);
      return Number(fullSize.height) > Number(limitedSize.height) + 0.5;
    } catch (e) {
      return false;
    }
  }

  private measureTitle(): void {
    const title: string = this.album === null ? '' : this.album.name;
    this.titleTruncated = this.clipped(title, this.titleWidth, '20fp', FontWeight.Bold, '', TITLE_MAX_LINES);
    if (!this.titleTruncated) {
      this.titlePopup = false;
    }
  }

  private measureDescription(): void {
    const description: string = this.album === null ? '' : this.album.description;
    this.descOverflow = this.clipped(description, this.descWidth, $r('sys.float.Body_M'), FontWeight.Regular,
      `${DESC_LINE_HEIGHT}fp`, DESC_MAX_LINES);
  }

  private copyTitle(): void {
    const title: string = this.album === null ? '' : this.album.name;
    if (title === '') {
      return;
    }
    try {
      pasteboard.getSystemPasteboard().setDataSync(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, title));
      this.getUIContext().getPromptAction().showToast({ message: '已复制' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '复制失败' });
    }
  }

  private authorNames(): Array<MetadataTerm> {
    return this.album === null ? [] : this.album.author;
  }

  @Builder
  private CopyMenu() {
    Menu() {
      MenuItem({ content: '复制标题' }).onClick(() => { this.copyTitle(); })
    }
  }

  @Builder
  private TitlePopupContent() {
    Scroll() {
      Text(this.album === null ? '' : this.album.name)
        .fontSize(16)
        .lineHeight(POPUP_TITLE_LINE_HEIGHT)
        .fontColor(TEXT_MAIN)
        .width('100%')
        .bindContextMenu(this.CopyMenu, ResponseType.LongPress)
    }
    .scrollBar(BarState.Auto)
    .align(Alignment.TopStart)
    .constraintSize({ maxHeight: POPUP_TITLE_LINE_HEIGHT * POPUP_TITLE_MAX_LINES + 24 })
    .padding(12)
  }

  @Builder
  private AuthorRow() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Text('作者').fontSize(13).fontColor(TEXT_SUB).margin({ right: 8 })
      ForEach(this.authorNames(), (author: MetadataTerm, index: number) => {
        if (index > 0) {
          Text('、').fontSize(13).fontColor(TEXT_SUB)
        }
        MetadataSearchChip({ term: author, field: 'author', sourceId: sourceId(this.aid),
          sourceName: this.sourceName, chipStyle: 'plain' })
      }, (author: MetadataTerm) => JSON.stringify([author.namespace, author.value]))
    }
    .width('100%')
  }

  build() {
    if (this.album !== null) {
      Column({ space: 16 }) {
        // 封面固定尺寸并决定头部高度；右侧信息列自然流动。
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
              .maxLines(TITLE_MAX_LINES)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .onClick(() => {
                if (this.titleTruncated) {
                  this.titlePopup = true;
                }
              })
              .bindContextMenu(this.CopyMenu, ResponseType.LongPress)
              .bindPopup(this.titlePopup, {
                builder: this.TitlePopupContent(),
                placement: Placement.BottomLeft,
                enableArrow: false,
                width: this.titleWidth,
                popupColor: $r('sys.color.comp_background_list_card'),
                backgroundBlurStyle: BlurStyle.NONE,
                shadow: ShadowStyle.OUTER_DEFAULT_SM,
                onStateChange: (event: TitlePopupState): void => {
                  if (!event.isVisible) {
                    this.titlePopup = false;
                  }
                }
              })

            if (this.album.author.length > 0) {
              this.AuthorRow()
            }

            if (this.fromLibrary) {
              Text(this.sourceBadge())
                .fontSize(13)
                .fontColor(TEXT_SUB)
                .accessibilityText(`当前来源 ${this.sourceBadge()}，点按换源`)
                .onClick(() => {
                  this.sourceSheet = true;
                })
            } else {
              Text(this.sourceBadge())
                .fontSize(13)
                .fontColor(TEXT_SUB)
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .onAreaChange((_old: Area, area: Area): void => {
            const width: number = Number(area.width);
            if (width !== this.titleWidth) {
              this.titleWidth = width;
              this.titlePopup = false;
              this.measureTitle();
            }
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        if (this.album.description !== '') {
          Column({ space: 4 }) {
            Text(this.album.description)
              .fontColor(TEXT_SUB)
              .fontSize($r('sys.float.Body_M'))
              .lineHeight(DESC_LINE_HEIGHT)
              .maxLines(this.descExpanded ? Number.MAX_SAFE_INTEGER : DESC_MAX_LINES)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .onAreaChange((_old: Area, area: Area): void => {
                const width: number = Number(area.width);
                if (width !== this.descWidth) {
                  this.descWidth = width;
                  this.measureDescription();
                }
              })
              .onClick(() => {
                if (this.descOverflow) {
                  this.descExpanded = !this.descExpanded;
                }
              })
            if (this.descOverflow) {
              Row() {
                Button(this.descExpanded ? '收起' : '展开',
                  { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
                  .onClick(() => {
                    this.descExpanded = !this.descExpanded;
                  })
              }
              .width('100%')
              .justifyContent(FlexAlign.End)
            }
          }
          .width('100%')
        }

        if (this.album.tags.length > 0) {
          WorkTags({ aid: this.aid, terms: this.album.tags, sourceId: sourceId(this.aid), sourceName: this.sourceName })
        }

        Button({ type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.EMPHASIZED }) {
          Text(this.canContinue() ? this.continueLabel() : '开始阅读')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ON_PRIMARY)
            .fontFeature('"tnum" 1')
            .maxLines(1)
        }
        .width('100%')
        .height(40)
        .onClick(() => { this.read(); })
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
