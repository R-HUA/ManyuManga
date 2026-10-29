/**
 * entry/src/main/ets/pages/reader/ReaderCatalogPanel.ets
 * 阅读器「目录 | 缩略图」浮层：作为 HUD 胶囊上方的同材质面板展开，不再使用半模态。
 * 目录自动定位到当前章节；缩略图为横向列表并定位到当前页。点击面板外由宿主遮罩关闭。
 */
import { BasicDataSource } from '../../common/DataSource';
import { DIVIDER, PRIMARY, PRIMARY_SOFT, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
import { Chapter, ReadingProgress } from '../../models/Models';
import { PageThumbItem } from './ReaderImageItem';

@Component
export struct ReaderCatalogPanel {
  @Link bookmarks: Array<ReadingProgress>;
  @Link chapters: Array<Chapter>;
  @Link chapterIndex: number;
  @Link pages: Array<string>;
  @Link currentPage: number;
  @Link scrambleId: number;
  chapterSource: BasicDataSource<Chapter> = new BasicDataSource<Chapter>();
  photoId: string = '';
  loadChapter: (chapterIdx: number, targetPage: number) => Promise<void> =
    async (_chapterIdx: number, _targetPage: number): Promise<void> => {};
  jumpToPage: (page: number) => void = (_page: number): void => {};
  flushProgress: () => void = (): void => {};
  close: () => void = (): void => {};
  @State private catalogTab: number = 0;
  private chapterScroller: Scroller = new Scroller();
  private thumbScroller: Scroller = new Scroller();

  private openChapter(idx: number, page: number): void {
    this.close();
    if (idx !== this.chapterIndex || page > 0) {
      this.flushProgress();
      this.loadChapter(idx, page).catch((): void => {});
    }
  }

  private locateChapter(): void {
    if (this.chapterIndex >= 0 && this.chapterIndex < this.chapters.length) {
      this.chapterScroller.scrollToIndex(Math.max(0, this.chapterIndex - 2), false);
    }
  }

  private locateThumb(): void {
    if (this.currentPage >= 0 && this.currentPage < this.pages.length) {
      this.thumbScroller.scrollToIndex(Math.max(0, this.currentPage - 1), false);
    }
  }

  build() {
    Tabs({ barPosition: BarPosition.Start, index: this.catalogTab }) {
      TabContent() {
        this.ChapterList()
      }
      .tabBar(SubTabBarStyle.of('目录'))

      TabContent() {
        this.ThumbList()
      }
      .tabBar(SubTabBarStyle.of('缩略图'))
    }
    .barHeight(40)
    .barMode(BarMode.Fixed)
    .barBackgroundColor(Color.Transparent)
    .scrollable(false)
    .animationDuration(200)
    .width('100%')
    .height('100%')
    .onChange((index: number): void => {
      this.catalogTab = index;
      if (index === 1) {
        this.locateThumb();
      } else {
        this.locateChapter();
      }
    })
  }

  @Builder
  private ChapterList() {
    Column({ space: 6 }) {
      if (this.bookmarks.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.bookmarks, (bookmark: ReadingProgress) => {
              Button(`第${bookmark.chapterIndex + 1}话 P.${bookmark.page + 1}`,
                { type: ButtonType.Capsule, stateEffect: true })
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(PRIMARY)
                .backgroundColor(PRIMARY_SOFT)
                .height(28)
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
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(index === this.chapterIndex ? PRIMARY : TEXT_SUB)
                .width(32)
              Text(ch.title !== '' ? ch.title : `第 ${(index === undefined ? 0 : index) + 1} 話`)
                .fontSize(14)
                .fontWeight(index === this.chapterIndex ? FontWeight.Bold : FontWeight.Medium)
                .fontColor(index === this.chapterIndex ? PRIMARY : TEXT_MAIN)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
            .constraintSize({ minHeight: 44 })
            .padding({ left: 6, right: 6, top: 10, bottom: 10 })
            .onClick(() => {
              this.openChapter(index === undefined ? 0 : index, 0);
            })
          }
        }, (ch: Chapter) => `ch_${ch.id}`)
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: DIVIDER, startMargin: 6, endMargin: 6 })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .padding({ top: 6 })
  }

  @Builder
  private ThumbList() {
    Column() {
      if (this.pages.length === 0) {
        Text('本章暂无页面')
          .fontSize(13)
          .fontColor(TEXT_SUB)
      } else {
        List({ scroller: this.thumbScroller, space: 8, initialIndex: Math.max(0, this.currentPage - 1) }) {
          ForEach(this.pages, (filename: string, index: number) => {
            ListItem() {
              Column({ space: 4 }) {
                PageThumbItem({
                  photoId: this.photoId,
                  filename: filename,
                  scrambleId: this.scrambleId
                })
                  .width(84)
                  .height(118)
                  .borderRadius(8)
                  .clip(true)
                  .border({ width: index === this.currentPage ? 2 : 0, color: PRIMARY, radius: 8 })
                Text(`${index + 1}`)
                  .fontSize(11)
                  .fontWeight(index === this.currentPage ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(index === this.currentPage ? PRIMARY : TEXT_SUB)
              }
              .onClick(() => {
                this.close();
                this.jumpToPage(index);
              })
            }
          }, (filename: string, index: number): string => `pg_${index}_${filename}`)
        }
        .listDirection(Axis.Horizontal)
        .height(144)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
