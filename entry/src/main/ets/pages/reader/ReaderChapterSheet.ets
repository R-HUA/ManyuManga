/**
 * entry/src/main/ets/pages/reader/ReaderChapterSheet.ets
 * 修复截图 10 (212531.png) 浅色模式下「白底白字」全盲事故：
 * 全面改用 TEXT_MAIN / TEXT_SUB / SUB_CARD / PRIMARY_SOFT 自适应语义色，
 * 严禁在挂载了 IMMERSIVE_SHEET_MATERIAL 的半模态内硬编码 #FFFFFF 白字！
 */
import { BasicDataSource } from '../../common/DataSource';
import { IconCircleButton } from '../../common/Components';
import { PRIMARY, PRIMARY_SOFT, SUB_CARD, TEXT_MAIN, TEXT_SUB, DIVIDER } from '../../common/Theme';
import { Chapter, ReadingProgress } from '../../models/Models';

@Component
export struct ReaderChapterSheet {
  @Link bookmarks: Array<ReadingProgress>;
  @Link sheetVisible: boolean;
  @Link chapters: Array<Chapter>;
  loadChapter: (chapterIdx: number, targetPage: number, preserveAttempts?: boolean) => Promise<void> =
    async (_chapterIdx: number, _targetPage: number, _preserveAttempts: boolean = false): Promise<void> => {};
  chapterSource: BasicDataSource<Chapter> = new BasicDataSource<Chapter>();
  @Link chapterIndex: number;
  flushProgress: () => void = (): void => {};

  build() {
    Column({ space: 10 }) {
      // 顶部标题栏（配合 bindSheet showClose: false）
      Row({ space: 8 }) {
        Text('章节目录')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)
        Text(`共 ${this.chapters.length} 话`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SUB)
          .margin({ right: 4 })
        IconCircleButton({
          glyph: $r('sys.symbol.xmark'),
          btnSize: 32,
          iconSize: 16,
          onTap: (): void => {
            this.sheetVisible = false;
          }
        })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12, bottom: 4 })
      .alignItems(VerticalAlign.Center)

      if (this.bookmarks.length > 0) {
        Column({ space: 6 }) {
          Text('已存书签')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT_SUB)
            .padding({ left: 18 })
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.bookmarks, (bookmark: ReadingProgress) => {
                Text(`第 ${bookmark.chapterIndex + 1} 话 · P.${bookmark.page + 1}`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PRIMARY)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(14)
                  .backgroundColor(PRIMARY_SOFT)
                  .onClick(() => {
                    this.sheetVisible = false;
                    const index: number = this.chapters.findIndex((c: Chapter) => c.id === bookmark.chapterId);
                    if (index >= 0) {
                      this.loadChapter(index, bookmark.page);
                    }
                  })
              }, (bookmark: ReadingProgress) => `${bookmark.chapterId}_${bookmark.page}`)
            }
            .padding({ left: 18, right: 18 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }

      List() {
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

              if (index === this.chapterIndex) {
                Text('阅读中')
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .borderRadius(10)
                  .backgroundColor(PRIMARY)
              }
            }
            .width('100%')
            .padding({ left: 18, right: 18, top: 13, bottom: 13 })
            .backgroundColor(index === this.chapterIndex ? PRIMARY_SOFT : Color.Transparent)
            .onClick(() => {
              const idx: number = index === undefined ? 0 : index;
              this.sheetVisible = false;
              if (idx !== this.chapterIndex) {
                this.flushProgress();
                this.loadChapter(idx, 0).catch((): void => {});
              }
            })
          }
        }, (ch: Chapter) => `ch_${ch.id}`)
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: DIVIDER, startMargin: 18, endMargin: 18 })
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
  }
}
