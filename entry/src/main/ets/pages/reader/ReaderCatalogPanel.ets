/**
 * entry/src/main/ets/pages/reader/ReaderCatalogPanel.ets
 * 阅读器「目录」：底栏上行的章节列表（不含预览，预览留在详情页左滑与长按）。
 * 自动定位到当前章节；高度由宿主按章节数收缩。点击面板外由宿主遮罩关闭。
 */
import { BasicDataSource } from '../../common/DataSource';
import { DIVIDER, PRIMARY, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
import { Chapter, ReadingProgress } from '../../models/Models';
import { CATALOG_ROW_HEIGHT } from '../../data/ReaderLayout';

@Component
export struct ReaderCatalogPanel {
  @Link bookmarks: Array<ReadingProgress>;
  @Link chapters: Array<Chapter>;
  @Link chapterIndex: number;
  chapterSource: BasicDataSource<Chapter> = new BasicDataSource<Chapter>();
  loadChapter: (chapterIdx: number, targetPage: number) => Promise<void> =
    async (_chapterIdx: number, _targetPage: number): Promise<void> => {};
  flushProgress: () => void = (): void => {};
  close: () => void = (): void => {};
  private chapterScroller: Scroller = new Scroller();

  private openChapter(idx: number, page: number): void {
    this.close();
    if (idx !== this.chapterIndex || page > 0) {
      this.flushProgress();
      this.loadChapter(idx, page).catch((): void => {});
    }
  }

  build() {
    this.ChapterList()
  }

  @Builder
  private ChapterList() {
    Column({ space: 6 }) {
      if (this.bookmarks.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.bookmarks, (bookmark: ReadingProgress) => {
              Button(`第${bookmark.chapterIndex + 1}话 P.${bookmark.page + 1}`,
                { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
                .height(40)
                .onClick(() => {
                  const index: number = this.chapters.findIndex((c: Chapter) => c.id === bookmark.chapterId);
                  if (index >= 0) {
                    this.openChapter(index, bookmark.page);
                  }
                })
            }, (bookmark: ReadingProgress) => `${bookmark.chapterId}_${bookmark.page}`)
          }
          .padding({ left: 4, right: 4 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .align(Alignment.Start)
        .width('100%')
      }

      List({ scroller: this.chapterScroller, initialIndex: Math.max(0, this.chapterIndex - 2) }) {
        LazyForEach(this.chapterSource, (ch: Chapter, index?: number) => {
          ListItem() {
            Row({ space: 10 }) {
              Text(`${(index === undefined ? 0 : index) + 1}`)
                .fontSize(12)
                .fontColor(index === this.chapterIndex ? PRIMARY : TEXT_SUB)
                .width(32)
              Text(ch.title !== '' ? ch.title : `第 ${(index === undefined ? 0 : index) + 1} 話`)
                .fontSize(16)
                .fontColor(index === this.chapterIndex ? PRIMARY : TEXT_MAIN)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
            .height(CATALOG_ROW_HEIGHT)
            .padding({ left: 6, right: 6 })
            .onClick(() => {
              this.openChapter(index === undefined ? 0 : index, 0);
            })
          }
        }, (ch: Chapter) => `ch_${ch.id}`)
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: '1px', color: DIVIDER, startMargin: 6, endMargin: 6 })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .padding({ top: 6 })
  }
}
