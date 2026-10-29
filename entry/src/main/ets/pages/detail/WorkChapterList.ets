import { SegmentButton, SegmentButtonOptions, SegmentButtonItemTuple } from '@kit.ArkUI';
import { Album, Chapter, ReadingProgress, CommentItem } from '../../models/Models';
import { sourceId } from '../../data/Sources';
import { capabilitiesForSourceId } from '../../data/source/SourceContracts';
import { IconCircleButton } from '../../common/Components';
import {
  CARD, DANGER, DIVIDER, NEUTRAL_PROGRESS, PRIMARY, PRIMARY_SOFT, SUB_CARD, TEXT_MAIN, TEXT_SUB, TEXT_TERTIARY
} from '../../common/Theme';
import { settingsRowRadius } from '../settings/SettingsRows';
import {
  ChapterDataSource, ChapterDownloadInfo, ChapterRow, buildChapterRows, chapterLabel
} from './ChapterRows';

/**
 * 详情页唯一的滚动容器：首项为详情头部（由页面以尾随闭包传入），随后是章节 LazyForEach 与评论。
 * 章节排序 / 过滤用 SegmentButton 表达“当前状态”；预览改为左滑或长按。
 */
@Component
export struct WorkChapterList {
  @Link @Watch('rebuild') album: Album | null;
  @Link @Watch('rebuild') ascending: boolean;
  @Link @Watch('rebuild') unread: boolean;
  @Link @Watch('rebuild') filter: string;
  @Link @Watch('rebuild') progress: ReadingProgress | null;
  @Link comments: Array<CommentItem>;
  @Prop aid: string = '';
  @Prop commentsDone: boolean = false;
  @Prop topOffset: number = 0;
  @Prop bottomOffset: number = 0;
  @Prop chapterDownloads: boolean = false;
  @Prop @Watch('rebuild') downloadStamp: number = 0;
  @State rowCount: number = 0;
  @State @Watch('sortChanged') sortIndexes: number[] = [0];
  @State @Watch('scopeChanged') scopeIndexes: number[] = [0];
  @State sortOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [{ text: '正序' }, { text: '倒序' }] as SegmentButtonItemTuple,
    fontSize: 12, selectedFontSize: 12,
    buttonPadding: { top: 4, bottom: 4, left: 8, right: 8 }
  });
  @State scopeOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [{ text: '全部' }, { text: '未读' }] as SegmentButtonItemTuple,
    fontSize: 12, selectedFontSize: 12,
    buttonPadding: { top: 4, bottom: 4, left: 8, right: 8 }
  });
  scroller: Scroller = new Scroller();
  read: (chapter?: Chapter) => void = (_chapter?: Chapter): void => {};
  preview: (chapter: Chapter) => void = (_chapter: Chapter): void => {};
  downloadChapter: (chapter: Chapter) => void = (_chapter: Chapter): void => {};
  downloads: () => Map<string, ChapterDownloadInfo> = (): Map<string, ChapterDownloadInfo> =>
    new Map<string, ChapterDownloadInfo>();
  loadComments: () => Promise<void> = async (): Promise<void> => {};
  onHeroVisible: (visible: boolean) => void = (_visible: boolean): void => {};
  @BuilderParam hero: () => void = this.EmptyHero;
  private source: ChapterDataSource = new ChapterDataSource();

  aboutToAppear(): void {
    this.sortIndexes = [this.ascending ? 0 : 1];
    this.scopeIndexes = [this.unread ? 1 : 0];
    this.rebuild();
  }

  rebuild(): void {
    const rows: Array<ChapterRow> = buildChapterRows(this.album, this.progress, this.filter, this.unread,
      this.ascending, this.downloads());
    this.source.setRows(rows);
    this.rowCount = rows.length;
  }

  sortChanged(): void {
    const next: boolean = this.sortIndexes.length === 0 || this.sortIndexes[0] === 0;
    if (next !== this.ascending) { this.ascending = next; }
  }

  scopeChanged(): void {
    const next: boolean = this.scopeIndexes.length > 0 && this.scopeIndexes[0] === 1;
    if (next !== this.unread) { this.unread = next; }
  }

  private commentsAvailable(): boolean {
    if (this.aid === '') {
      return false;
    }
    try {
      return capabilitiesForSourceId(sourceId(this.aid)).comments;
    } catch (e) {
      return false;
    }
  }

  @Builder
  EmptyHero() {
  }

  @Builder
  private PreviewAction(chapter: Chapter) {
    Row() {
      SymbolGlyph($r('sys.symbol.eye')).fontSize(20).fontColor([Color.White])
    }
    .width(72)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(PRIMARY)
    .accessibilityText('预览本章页面')
    .onClick(() => {
      this.preview(chapter);
    })
  }

  @Builder
  private DownloadMark(row: ChapterRow) {
    if (row.download.state === 'done') {
      SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([TEXT_SUB])
        .accessibilityText('已下载')
    } else if (row.download.state === 'running') {
      Progress({ value: row.download.done, total: Math.max(1, row.download.total), type: ProgressType.Ring })
        .width(20).height(20).color(NEUTRAL_PROGRESS)
        .style({ strokeWidth: 2.5 })
    } else if (row.download.state === 'queued') {
      SymbolGlyph($r('sys.symbol.clock')).fontSize(16).fontColor([TEXT_SUB])
        .accessibilityText('排队中')
    } else if (row.download.state === 'failed') {
      IconCircleButton({
        glyph: $r('sys.symbol.exclamationmark_circle'), btnSize: 40, iconSize: 18, bg: Color.Transparent,
        iconColor: DANGER, onTap: (): void => { this.downloadChapter(row.chapter); }
      })
        .accessibilityText('下载失败，点按重试')
    } else if (this.chapterDownloads) {
      IconCircleButton({
        glyph: $r('sys.symbol.arrow_down_circle'), btnSize: 40, iconSize: 18, bg: Color.Transparent,
        iconColor: TEXT_SUB, onTap: (): void => { this.downloadChapter(row.chapter); }
      })
        .accessibilityText('下载本章')
    }
  }

  @Builder
  private ChapterLine(row: ChapterRow) {
    Row({ space: 10 }) {
      Column()
        .width(4)
        .height(row.current ? 28 : 0)
        .borderRadius(2)
        .backgroundColor(PRIMARY)
        .visibility(row.current ? Visibility.Visible : Visibility.Hidden)

      Text(chapterLabel(row.chapter))
        .fontColor(row.current ? PRIMARY : (row.read ? TEXT_TERTIARY : TEXT_MAIN))
        .fontWeight(row.current ? FontWeight.Bold : FontWeight.Regular)
        .fontSize(15)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (row.progressText !== '') {
        Text(row.progressText)
          .fontSize(12)
          .fontColor(TEXT_SUB)
      }

      Row() {
        this.DownloadMark(row)
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .constraintSize({ minHeight: 52 })
    .padding({ left: 8, right: 4 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private ChaptersHeader() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('章节')
          .fontSize(18)
          .fontColor(TEXT_MAIN)
          .fontWeight(FontWeight.Bold)
        if (this.album !== null) {
          Text(this.rowCount === this.album.episodes.length ? `${this.album.episodes.length}` :
            `${this.rowCount}/${this.album.episodes.length}`)
            .fontSize(13)
            .fontColor(TEXT_SUB)
        }
        Blank()
        Column() {
          SegmentButton({ options: this.sortOptions, selectedIndexes: $sortIndexes })
        }.width(108)
        Column() {
          SegmentButton({ options: this.scopeOptions, selectedIndexes: $scopeIndexes })
        }.width(108)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.album !== null && this.album.episodes.length > 12) {
        Row() {
          TextInput({ text: this.filter, placeholder: '筛选章节号或关键词…' })
            .height(38)
            .borderRadius(14)
            .backgroundColor(SUB_CARD)
            .fontColor(TEXT_MAIN)
            .placeholderColor(TEXT_SUB)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.filter = value;
            })
          if (this.filter !== '') {
            IconCircleButton({
              glyph: $r('sys.symbol.xmark'), btnSize: 40, iconSize: 14, bg: Color.Transparent,
              onTap: (): void => {
                this.filter = '';
              }
            })
              .margin({ left: 4 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 10 })
  }

  @Builder
  private CommentsHeader() {
    Row() {
      Text('读者漫评')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .layoutWeight(1)
      if (this.commentsDone && this.comments.length === 0) {
        Text('暂无评论').fontSize(12).fontColor(TEXT_SUB)
      } else if (this.commentsDone) {
        Text('已全部加载').fontSize(12).fontColor(TEXT_SUB)
      } else {
        Text(this.comments.length === 0 ? '加载漫评' : '加载更多')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor(PRIMARY_SOFT)
          .onClick(() => {
            this.loadComments();
          })
      }
    }
    .width('100%')
    .padding({ top: 20, bottom: 10 })
  }

  build() {
    List({ scroller: this.scroller }) {
      ListItem() {
        this.hero()
      }

      ListItemGroup({ header: this.ChaptersHeader() }) {
        LazyForEach(this.source, (row: ChapterRow, index: number) => {
          ListItem() {
            this.ChapterLine(row)
          }
          .backgroundColor(CARD)
          .borderRadius(settingsRowRadius(index, this.rowCount))
          .swipeAction({ end: { builder: (): void => { this.PreviewAction(row.chapter); } } })
          .onClick(() => {
            this.read(row.chapter);
          })
          .gesture(LongPressGesture().onAction(() => {
            this.preview(row.chapter);
          }))
        }, (row: ChapterRow) => row.key())
      }
      .padding({ left: 16, right: 16 })
      .divider({ strokeWidth: '1px', color: DIVIDER, startMargin: 22, endMargin: 12 })

      if (this.rowCount === 0) {
        ListItem() {
          Text('暂无符合条件的章节')
            .fontSize(13)
            .fontColor(TEXT_SUB)
            .padding(32)
            .width('100%')
            .textAlign(TextAlign.Center)
        }
      }

      if (this.album !== null && this.commentsAvailable()) {
        ListItemGroup({ header: this.CommentsHeader(), space: 8 }) {
          ForEach(this.comments, (comment: CommentItem) => {
            ListItem() {
              Column({ space: 6 }) {
                Row() {
                  Text(comment.nickname)
                    .fontColor(PRIMARY)
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .layoutWeight(1)
                  if (comment.time !== '') {
                    Text(comment.time).fontColor(TEXT_SUB).fontSize(11)
                  }
                }
                .width('100%')

                Text(comment.content)
                  .fontColor(TEXT_MAIN)
                  .fontSize(13)
                  .lineHeight(19)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding(14)
              .backgroundColor(CARD)
              .borderRadius(14)
            }
          }, (comment: CommentItem, idx: number) => `${comment.id}_${idx}`)
        }
        .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .contentStartOffset(this.topOffset)
    .contentEndOffset(this.bottomOffset)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .cachedCount(6)
    .onScrollIndex((start: number) => {
      this.onHeroVisible(start === 0);
    })
  }
}
