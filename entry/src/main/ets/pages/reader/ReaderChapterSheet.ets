import { BasicDataSource } from '../../common/DataSource';
import { PRIMARY } from '../../common/Theme';
import { Chapter, ReadingProgress } from '../../models/Models';

@Component
export struct ReaderChapterSheet {
  @Link bookmarks: Array<ReadingProgress>;
  @Link sheetVisible: boolean;
  @Link chapters: Array<Chapter>;
  loadChapter: (chapterIdx: number, targetPage: number, preserveAttempts?: boolean) => Promise<void> = async (chapterIdx: number, targetPage: number, preserveAttempts: boolean = false): Promise<void> => {};
  chapterSource: BasicDataSource<Chapter> = new BasicDataSource<Chapter>();
  @Link chapterIndex: number;
  flushProgress: () => void = (): void => {};

  build() {
    Column() {
      if (this.bookmarks.length > 0) {
        Column({ space: 6 }) {
          Text('已存书签')
            .fontSize(12)
            .fontColor('rgba(255,255,255,0.55)')
            .padding({ left: 18 })
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.bookmarks, (bookmark: ReadingProgress) => {
                Text(`第 ${bookmark.chapterIndex + 1} 话 P.${bookmark.page + 1}`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(14)
                  .backgroundColor('rgba(58,122,254,0.24)')
                  .border({ width: 0.5, color: PRIMARY })
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
        .padding({ top: 10 })
        .width('100%')
      }
      Row({ space: 8 }) {
        Text('章节目录')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2F2F4')
          .layoutWeight(1)
        Text(`共 ${this.chapters.length} 话`)
          .fontSize(12)
          .fontColor('rgba(255,255,255,0.55)')
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 14, bottom: 10 })
      List() {
        LazyForEach(this.chapterSource, (ch: Chapter, index?: number) => {
          ListItem() {
            Row({ space: 10 }) {
              Text(`${(index === undefined ? 0 : index) + 1}`)
                .fontSize(13)
                .fontColor('rgba(255,255,255,0.45)')
                .width(34)
              Text(ch.title !== '' ? ch.title : `第 ${(index === undefined ? 0 : index) + 1} 話`)
                .fontSize(14)
                .fontWeight(index === this.chapterIndex ? FontWeight.Bold : FontWeight.Regular)
                .fontColor(index === this.chapterIndex ? '#FFFFFF' : 'rgba(255,255,255,0.75)')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (index === this.chapterIndex) {
                Text('阅读中')
                  .fontSize(10)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(8)
                  .backgroundColor(PRIMARY)
              }
            }
            .width('100%')
            .padding({ left: 18, right: 18, top: 13, bottom: 13 })
            .onClick(() => {
              const idx: number = index === undefined ? 0 : index;
              this.sheetVisible = false;
              if (idx !== this.chapterIndex) {
                this.flushProgress();
                this.loadChapter(idx, 0).catch((e: Error): void => {
                });
              }
            })
          }
        }, (ch: Chapter) => `ch_${ch.id}`)
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: 'rgba(255,255,255,0.08)', startMargin: 18, endMargin: 18 })
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
  }
}
