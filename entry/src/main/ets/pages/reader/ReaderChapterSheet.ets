/**
 * entry/src/main/ets/pages/reader/ReaderChapterSheet.ets
 * 阅读器二级「目录/预览」抽屉：同一抽屉内用分段控件切换本章页面缩略图与全部章节目录，
 * 章节行采用清爽平铺列表与细分割线，不叠加卡片底与胶囊色块。
 */
import { BasicDataSource } from '../../common/DataSource';
import { SkeletonGrid } from '../../common/Components';
import { SegmentButton, SegmentButtonOptions, SegmentButtonItemTuple } from '@kit.ArkUI';
import { IMMERSIVE_REGULAR_MATERIAL } from '../../common/ImmersiveMaterials';
import { DIVIDER, PRIMARY, PRIMARY_SOFT, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
import { Chapter, ReadingProgress } from '../../models/Models';
import { PageThumbItem } from './ReaderImageItem';

@Component
export struct ReaderChapterSheet {
  @Link bookmarks: Array<ReadingProgress>;
  @Link sheetVisible: boolean;
  @Link chapters: Array<Chapter>;
  loadChapter: (chapterIdx: number, targetPage: number, preserveAttempts?: boolean) => Promise<void> =
    async (_chapterIdx: number, _targetPage: number, _preserveAttempts: boolean = false): Promise<void> => {};
  chapterSource: BasicDataSource<Chapter> = new BasicDataSource<Chapter>();
  @Link chapterIndex: number;
  @Link pages: Array<string>;
  @Link currentPage: number;
  @Link scrambleId: number;
  photoId: string = '';
  jumpToPage: (page: number) => void = (page: number): void => {};
  flushProgress: () => void = (): void => {};
  @State private viewIndexes: number[] = [0];
  @State private viewOptions: SegmentButtonOptions = SegmentButtonOptions.capsule({
    multiply: false,
    buttons: [{ text: '本章页面' }, { text: '全部章节目录' }] as SegmentButtonItemTuple,
    backgroundSystemMaterial: IMMERSIVE_REGULAR_MATERIAL
  });

  build() {
    Column({ space: 10 }) {
      Text(this.viewIndexes[0] === 0 ? `共 ${this.pages.length} 页` : `共 ${this.chapters.length} 话`)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_SUB)
        .width('100%')
        .padding({ left: 18 })

      Column() {
        SegmentButton({
          options: this.viewOptions,
          selectedIndexes: $viewIndexes
        })
      }
      .width('100%')
      .padding({ left: 18, right: 18 })

      if (this.viewIndexes[0] === 0) {
        this.PageGrid()
      } else {
        this.ChapterList()
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 本章页面缩略图：骨架屏占位，点击原地跳页 */
  @Builder
  private PageGrid() {
    if (this.pages.length === 0) {
      SkeletonGrid({ columns: 4, rows: 3 })
    } else {
      Grid() {
        ForEach(this.pages, (filename: string, index?: number) => {
          GridItem() {
            Column({ space: 3 }) {
              PageThumbItem({
                photoId: this.photoId,
                filename: filename,
                scrambleId: this.scrambleId
              })
                .width('100%')
                .aspectRatio(0.72)
              Text(`${(index === undefined ? 0 : index) + 1}`)
                .fontSize(10)
                .fontWeight((index === undefined ? 0 : index) === this.currentPage
                  ? FontWeight.Bold : FontWeight.Medium)
                .fontColor((index === undefined ? 0 : index) === this.currentPage ? PRIMARY : TEXT_SUB)
            }
            .width('100%')
          }
          .onClick(() => {
            this.sheetVisible = false;
            this.jumpToPage(index === undefined ? 0 : index);
          })
        }, (filename: string, index: number): string => `pg_${index}_${filename}`)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .columnsGap(8)
      .rowsGap(10)
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 18, right: 18, top: 6, bottom: 18 })
      .scrollBar(BarState.Off)
    }
  }

  @Builder
  private ChapterList() {
    if (this.bookmarks.length > 0) {
      Column({ space: 6 }) {
        Text('已存书签')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SUB)
          .padding({ left: 18 })
          .width('100%')
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.bookmarks, (bookmark: ReadingProgress) => {
              Button(`第${bookmark.chapterIndex + 1}话 P.${bookmark.page + 1}`,
                { type: ButtonType.Capsule, stateEffect: true })
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(PRIMARY)
                .backgroundColor(PRIMARY_SOFT)
                .height(30)
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
        .align(Alignment.Start)
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
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(PRIMARY)
            }
          }
          .width('100%')
          .constraintSize({ minHeight: 48 })
          .padding({ left: 18, right: 18, top: 12, bottom: 12 })
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
    .padding({ bottom: 12 })
    .divider({ strokeWidth: 0.5, color: DIVIDER, startMargin: 18, endMargin: 18 })
    .scrollBar(BarState.Auto)
  }
}
