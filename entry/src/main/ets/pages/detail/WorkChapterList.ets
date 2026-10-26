import { Album, Chapter, ReadingProgress, CommentItem } from '../../models/Models';
import { sourceId } from '../../data/Sources';
import { capabilitiesForSourceId } from '../../data/source/SourceContracts';
import { IconCircleButton } from '../../common/Components';
import { CARD, PRIMARY, PRIMARY_SOFT, TEXT_MAIN, TEXT_SUB, DIVIDER } from '../../common/Theme';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

@Component
export struct WorkChapterList {
  @Link album: Album | null;
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

  private chapters(): Array<Chapter> {
    if (this.album === null) {
      return [];
    }
    const readIndex: number = this.progress === null ? -1 : this.progress.chapterIndex;
    const list: Array<Chapter> = this.album.episodes.filter((c: Chapter, i: number) =>
      c.title.includes(this.filter) && (!this.unread || i > readIndex || (i === readIndex && this.progress!.page < this.progress!.totalPages - 1)));
    return this.ascending ? list : list.slice().reverse();
  }
  @Link ascending: boolean;
  @Link unread: boolean;
  @Link filter: string;
  @Link progress: ReadingProgress | null;
  read: (chapter?: Chapter) => void = (chapter?: Chapter): void => {};
  preview: (chapter: Chapter) => void = (chapter: Chapter): void => {};
  @Prop aid: string = '';
  @Link comments: Array<CommentItem>;
  @Prop commentsDone: boolean = false;
  loadComments: () => Promise<void> = async (): Promise<void> => {};
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text('章节目录')
          .fontSize(18)
          .fontColor(TEXT_MAIN)
          .fontWeight(FontWeight.Bold)
        if (this.album !== null) {
          Text(`${this.chapters().length} / ${this.album.episodes.length}`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(PRIMARY)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
            .backgroundColor(PRIMARY_SOFT)
        }
        Blank()
        Text(this.ascending ? '正序' : '倒序')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_MAIN)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor(CARD)
          .border({ width: 0.5, color: DIVIDER })
          .onClick(() => {
            this.ascending = !this.ascending;
          })
        Text(this.unread ? '仅未读' : '全部章节')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.unread ? Color.White : TEXT_MAIN)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor(this.unread ? PRIMARY : CARD)
          .border({ width: 0.5, color: this.unread ? PRIMARY : DIVIDER })
          .onClick(() => {
            this.unread = !this.unread;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.album !== null && this.album.episodes.length > 12) {
        Row() {
          TextInput({ text: this.filter, placeholder: '筛选章节号或关键词…' })
            .height(38)
            .borderRadius(14)
            .backgroundColor(CARD)
            .fontColor(TEXT_MAIN)
            .placeholderColor(TEXT_SUB)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.filter = value;
            })
          if (this.filter !== '') {
            IconCircleButton({
              symbol: $r('sys.symbol.xmark'),
              btnSize: 32,
              iconSize: 14,
              onTap: (): void => {
                this.filter = '';
              }
            })
              .margin({ left: 6 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      ForEach(this.chapters(), (chapter: Chapter) => {
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Row({ space: 6 }) {
              if (this.progress?.chapterId === chapter.id) {
                Text('阅读中')
                  .fontSize(10)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(6)
                  .backgroundColor(PRIMARY)
              }
              Text(chapter.title || `第 ${chapter.sort} 章`)
                .fontColor(this.progress?.chapterId === chapter.id ? PRIMARY : TEXT_MAIN)
                .fontWeight(this.progress?.chapterId === chapter.id ? FontWeight.Bold : FontWeight.Medium)
                .fontSize(14)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')

            if (this.progress?.chapterId === chapter.id) {
              Text(`上次读至第 ${this.progress!.page + 1} / ${Math.max(1, this.progress!.totalPages)} 页`)
                .fontSize(11)
                .fontColor(TEXT_SUB)
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .onClick(() => {
            this.read(chapter);
          })

          IconCircleButton({
            glyph: $r('sys.symbol.eye'),
            btnSize: 34,
            iconSize: 16,
            onTap: (): void => {
              this.preview(chapter);
            }
          })
        }
        .width('100%')
        .padding({ left: 16, right: 12, top: 12, bottom: 12 })
        .backgroundColor(CARD)
        .borderRadius(16)
        .border({
          width: this.progress?.chapterId === chapter.id ? 1 : 0.5,
          color: this.progress?.chapterId === chapter.id ? PRIMARY : DIVIDER
        })
      }, (chapter: Chapter) => `${chapter.id}_${this.progress?.chapterId === chapter.id}`)

      if (this.chapters().length === 0) {
        Text('暂无符合条件的章节')
          .fontSize(13)
          .fontColor(TEXT_SUB)
          .padding(32)
          .width('100%')
          .textAlign(TextAlign.Center)
      }

      // 评论 Section（JM 漫评 / EH 画廊评论）
      if (this.album !== null && this.commentsAvailable()) {
        Column({ space: 12 }) {
          Row() {
            Text('读者漫评')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_MAIN)
              .layoutWeight(1)
            if (this.commentsDone && this.comments.length === 0) {
              Text('暂无评论')
                .fontSize(12)
                .fontColor(TEXT_SUB)
            } else if (this.commentsDone) {
              Text('已全部加载')
                .fontSize(12)
                .fontColor(TEXT_SUB)
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
          .margin({ top: 12 })

          ForEach(this.comments, (comment: CommentItem) => {
            Column({ space: 6 }) {
              Row() {
                Text(comment.nickname)
                  .fontColor(PRIMARY)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .layoutWeight(1)
                if (comment.time !== '') {
                  Text(comment.time)
                    .fontColor(TEXT_SUB)
                    .fontSize(11)
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
            .border({ width: 0.5, color: DIVIDER })
          }, (comment: CommentItem, idx: number) => `${comment.id}_${idx}`)
        }
        .width('100%')
      }
    }
    .padding({ left: 16, right: 16, top: 8, bottom: 32 + this.bottomInset })
    .width('100%')
  }
}
