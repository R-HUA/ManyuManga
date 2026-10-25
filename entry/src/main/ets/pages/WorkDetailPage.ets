import promptAction from '@ohos.promptAction';
import uiMaterial from '@ohos.arkui.uiMaterial';
import {
  MangaRouteParams,
  ROUTE_READER,
  ROUTE_SEARCH,
  ROUTE_DOWNLOADS,
  ROUTE_PREVIEW
} from '../common/Route';
import {
  Album,
  Chapter,
  ReadingProgress,
  CommentItem,
  CommentsResult,
  asRecord,
  asString,
  errorMessage
} from '../models/Models';
import { sourceApi } from '../data/SourceApi';
import { sourceId, sourceStore } from '../data/Sources';
import { library, LibraryWork } from '../data/Library';
import { readProgressStore, historyStore, albumCacheStore } from '../data/Stores';
import { downloadManager } from '../data/DownloadManager';
import {
  prepareSourceSwitch,
  switchedProgress,
  SourceSwitchResult,
  discoverSources,
  SourceDiscovery
} from '../data/SourceSwitch';
import { matchingChapter } from '../data/Matching';
import { SourceCover } from '../common/SourceCover';
import { IconCircleButton } from '../common/Components';
import {
  BG,
  CARD,
  SUB_CARD,
  PRIMARY,
  PRIMARY_SOFT,
  ACCENT,
  ACCENT_SOFT,
  DANGER,
  DANGER_SOFT,
  TEXT_MAIN,
  TEXT_SUB,
  CHIP_BG,
  DIVIDER
} from '../common/Theme';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

@Component
export struct WorkDetailPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp('currentBreakpoint') breakpoint: string = 'sm';
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 0;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;

  @State album: Album | null = null;
  @State work: LibraryWork | null = null;
  @State progress: ReadingProgress | null = null;
  @State error: string = '';
  @State sourceName: string = '';
  @State coverTint: string = 'rgba(58,122,254,0.22)';
  @State filter: string = '';
  @State unread: boolean = false;
  @State ascending: boolean = true;
  @State descExpanded: boolean = false;
  @State sourceSheet: boolean = false;
  @State comments: Array<CommentItem> = [];
  @State commentPage: number = 0;
  @State loadingComments: boolean = false;
  @State busy: boolean = false;

  private aid: string = '';
  private generation: number = 0;

  aboutToDisappear(): void {
    this.generation++;
  }

  private async load(key: string): Promise<void> {
    const ticket: number = ++this.generation;
    this.busy = true;
    this.error = '';
    try {
      const album: Album = await sourceApi.album(key);
      if (ticket !== this.generation) {
        return;
      }
      this.album = album;
      this.aid = album.id;
      this.sourceName = (await sourceStore.get(sourceId(key), false)).name;
      this.work = await library.workFor(key);
      this.progress = await readProgressStore.get(key);
      await albumCacheStore.put(album);
      await historyStore.record(album, album.coverUrl);
    } catch (e) {
      if (ticket === this.generation) {
        this.error = errorMessage(e as Error);
      }
    } finally {
      if (ticket === this.generation) {
        this.busy = false;
      }
    }
  }

  private async refresh(): Promise<void> {
    if (this.aid === '') {
      return;
    }
    try {
      this.work = await library.workFor(this.aid);
      this.progress = await readProgressStore.get(this.aid);
    } catch (e) {
      this.error = errorMessage(e as Error);
    }
  }

  private async add(): Promise<void> {
    const ticket: number = this.generation;
    try {
      const current: Album = this.album!;
      await library.add(current);
      await this.refresh();
      promptAction.showToast({ message: '已加入书架，正在后台匹配多源…' });
      const discovered: SourceDiscovery = await discoverSources(current, (): boolean => ticket === this.generation);
      for (const album of discovered.albums) {
        if (ticket !== this.generation) {
          return;
        }
        await library.associate(current.id, album);
      }
      if (ticket === this.generation) {
        await this.refresh();
        if (discovered.failures.length > 0) {
          this.error = discovered.failures.join('；');
        }
      }
    } catch (e) {
      this.error = errorMessage(e as Error);
    }
  }

  private async download(): Promise<void> {
    try {
      await downloadManager.enqueue(this.album!);
      promptAction.showToast({ message: '已加入离线下载队列' });
    } catch (e) {
      this.error = errorMessage(e as Error);
    }
  }

  private async chooseSource(target: Album): Promise<void> {
    const ticket: number = ++this.generation;
    this.busy = true;
    try {
      const album: Album = await sourceApi.album(target.id);
      if (ticket !== this.generation) {
        return;
      }
      if (this.progress !== null && this.album !== null) {
        const chapter: Chapter | undefined = this.album.episodes.find((c: Chapter) => c.id === this.progress!.chapterId);
        if (chapter !== undefined) {
          if (matchingChapter(chapter, album.episodes) === null) {
            this.album = album;
            this.aid = album.id;
            this.progress = await readProgressStore.get(album.id);
            this.sourceName = (await sourceStore.get(sourceId(album.id), false)).name;
            this.sourceSheet = false;
            this.error = '目标源章节命名不同，请手动点选对应章节继续阅读';
            return;
          }
          const result: SourceSwitchResult = await prepareSourceSwitch(album, chapter, this.progress.page, this.progress.totalPages);
          if (ticket !== this.generation) {
            return;
          }
          await readProgressStore.save(switchedProgress(result));
          if (result.proportional) {
            promptAction.showToast({ message: '章节页数不同，已按阅读比例智能定位' });
          }
        }
      }
      await library.activate(album.id);
      this.sourceSheet = false;
      this.comments = [];
      this.commentPage = 0;
      await this.load(album.id);
      promptAction.showToast({ message: `已切换至 ${this.sourceName}` });
    } catch (e) {
      if (ticket === this.generation) {
        this.error = errorMessage(e as Error);
      }
    } finally {
      this.busy = false;
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

  private read(chapter?: Chapter): void {
    if (chapter === undefined) {
      this.stack.pushPathByName(ROUTE_READER, { aid: this.aid } as MangaRouteParams);
    } else {
      this.stack.pushPathByName(ROUTE_READER, { aid: this.aid, chapterId: chapter.id, page: 0 } as MangaRouteParams);
    }
  }

  private preview(chapter: Chapter): void {
    this.stack.pushPathByName(ROUTE_PREVIEW, {
      aid: this.aid,
      chapterId: chapter.id,
      query: chapter.title || `第 ${chapter.sort} 章`
    } as MangaRouteParams);
  }

  private async loadComments(): Promise<void> {
    if (this.loadingComments) {
      return;
    }
    this.loadingComments = true;
    try {
      const result: CommentsResult = await sourceApi.comments(this.aid, this.commentPage + 1);
      this.comments = this.comments.concat(result.list);
      this.commentPage++;
    } catch (e) {
      this.error = errorMessage(e as Error);
    } finally {
      this.loadingComments = false;
    }
  }

  @Builder
  private TopBar() {
    Row({ space: 10 }) {
      IconCircleButton({
        glyph: $r('sys.symbol.chevron_left'),
        onTap: (): void => {
          this.stack.pop();
        }
      })

      Text(this.album !== null ? this.album.name : '漫画详情')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      IconCircleButton({
        glyph: $r('sys.symbol.arrow_left_arrow_right'),
        active: this.work !== null && this.work.albums.length > 1,
        onTap: (): void => {
          this.sourceSheet = true;
        }
      })

      IconCircleButton({
        glyph: $r('sys.symbol.arrow_down_circle'),
        onTap: (): void => {
          this.stack.pushPathByName(ROUTE_DOWNLOADS, {} as MangaRouteParams);
        }
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topInset + 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private Info() {
    if (this.album !== null) {
      Column({ space: 16 }) {
        // Hero Row: Cover + Metadata
        Row({ space: 16 }) {
          Column() {
            SourceCover({
              url: this.album.coverUrl,
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
                ForEach(this.album.author, (author: string) => {
                  Text(author)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(PRIMARY)
                    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    .margin({ right: 6, bottom: 6 })
                    .borderRadius(12)
                    .backgroundColor(PRIMARY_SOFT)
                    .onClick(() => {
                      this.stack.pushPathByName(ROUTE_SEARCH, { query: author } as MangaRouteParams);
                    })
                }, (author: string) => author)
              }
            }

            // Multi-Source Aggregation Capsule
            Row({ space: 6 }) {
              Text(this.sourceName || sourceId(this.aid).toUpperCase())
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(8)
                .backgroundColor(PRIMARY)

              Text(this.work !== null && this.work.albums.length > 1
                ? `已关联 ${this.work.albums.length} 个书源 · 点击换源`
                : '更多书源 · 点击比对')
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

        // Primary CTA Row
        Row({ space: 10 }) {
          Text(this.progress === null
            ? '开始阅读'
            : `继续阅读 · P.${this.progress.page + 1}`)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .layoutWeight(2)
            .height(44)
            .borderRadius(22)
            .backgroundColor(PRIMARY)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
            .onClick(() => {
              this.read();
            })

          Text(this.work === null ? '加入书架' : '已在书架')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.work === null ? PRIMARY : TEXT_SUB)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(44)
            .borderRadius(22)
            .backgroundColor(this.work === null ? PRIMARY_SOFT : CARD)
            .border({ width: 0.5, color: this.work === null ? PRIMARY : DIVIDER })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
            .onClick(() => {
              if (this.work === null) {
                this.add();
              } else {
                this.sourceSheet = true;
              }
            })
        }
        .width('100%')

        // Secondary Action Bar
        Row({ space: 10 }) {
          Text('下载全本')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT_MAIN)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(38)
            .borderRadius(19)
            .backgroundColor(CARD)
            .border({ width: 0.5, color: DIVIDER })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
            .onClick(() => {
              this.download();
            })

          Text('换源与关联')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT_MAIN)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(38)
            .borderRadius(19)
            .backgroundColor(CARD)
            .border({ width: 0.5, color: DIVIDER })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
            .onClick(() => {
              this.sourceSheet = true;
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
            ForEach(this.album.tags, (tag: string) => {
              Text(tag)
                .fontColor(TEXT_MAIN)
                .fontSize(12)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .margin({ right: 8, bottom: 8 })
                .backgroundColor(CARD)
                .borderRadius(14)
                .border({ width: 0.5, color: DIVIDER })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
                .onClick(() => {
                  this.stack.pushPathByName(ROUTE_SEARCH, { query: tag } as MangaRouteParams);
                })
            }, (tag: string) => tag)
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

  @Builder
  private Chapters() {
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

      if (this.album !== null && this.album.episodes.length > 5) {
        TextInput({ text: this.filter, placeholder: '筛选章节号或关键词…' })
          .height(40)
          .borderRadius(14)
          .backgroundColor(CARD)
          .fontColor(TEXT_MAIN)
          .placeholderColor(TEXT_SUB)
          .onChange((value: string) => {
            this.filter = value;
          })
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

      // JM Comments Section
      if (this.album !== null && sourceId(this.aid) === 'jm') {
        Column({ space: 12 }) {
          Row() {
            Text('读者漫评')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_MAIN)
              .layoutWeight(1)
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

  @Builder
  private SourcesSheet() {
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Column({ space: 4 }) {
            Text('多源聚合与无缝换源')
              .fontColor(TEXT_MAIN)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
            Text('切换图源时将自动比对章节并按比例继承阅读页码')
              .fontColor(TEXT_SUB)
              .fontSize(12)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')

        if (this.work !== null) {
          ForEach(this.work.albums, (item: Album) => {
            Row({ space: 10 }) {
              Column({ space: 4 }) {
                Row({ space: 6 }) {
                  Text(sourceId(item.id).toUpperCase())
                    .fontSize(10)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(item.id === this.aid ? Color.White : PRIMARY)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(6)
                    .backgroundColor(item.id === this.aid ? PRIMARY : PRIMARY_SOFT)
                  Text(item.name)
                    .fontColor(TEXT_MAIN)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                }
                .width('100%')

                Text(`${item.episodes.length} 个章节 · ID: ${item.id}`)
                  .fontColor(TEXT_SUB)
                  .fontSize(11)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Text(item.id === this.aid ? '当前源' : '切换')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(item.id === this.aid ? TEXT_SUB : Color.White)
                .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                .borderRadius(16)
                .backgroundColor(item.id === this.aid ? CHIP_BG : PRIMARY)
                .onClick(() => {
                  if (item.id !== this.aid && !this.busy) {
                    this.chooseSource(item);
                  }
                })

              if (this.work!.albums.length > 1 && item.id !== this.aid) {
                IconCircleButton({
                  glyph: $r('sys.symbol.trash'),
                  btnSize: 32,
                  iconSize: 15,
                  onTap: (): void => {
                    library.detach(item.id).then(() => {
                      this.refresh();
                    }).catch((e: Error) => {
                      this.error = errorMessage(e);
                    });
                  }
                })
              }
            }
            .padding(14)
            .borderRadius(16)
            .backgroundColor(SUB_CARD)
            .width('100%')
          }, (item: Album) => item.id)

          Text('跨源搜索并关联新图源')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .width('100%')
            .height(44)
            .borderRadius(22)
            .backgroundColor(PRIMARY)
            .onClick(() => {
              this.sourceSheet = false;
              this.stack.pushPathByName(ROUTE_SEARCH, { matchAid: this.aid } as MangaRouteParams);
            })
        } else {
          Column({ space: 12 }) {
            Text('当前作品尚未加入书架。加入书架后将自动在所有已启用书源中检索同名作品并聚合备源。')
              .fontSize(13)
              .fontColor(TEXT_SUB)
              .lineHeight(19)
            Row({ space: 10 }) {
              Text('加入书架并自动发现')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(44)
                .borderRadius(22)
                .backgroundColor(PRIMARY)
                .onClick(() => {
                  this.add();
                })
              Text('手动跨源搜索')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(TEXT_MAIN)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(44)
                .borderRadius(22)
                .backgroundColor(SUB_CARD)
                .onClick(() => {
                  this.sourceSheet = false;
                  this.stack.pushPathByName(ROUTE_SEARCH, { matchAid: this.aid } as MangaRouteParams);
                })
            }
            .width('100%')
          }
          .padding(16)
          .borderRadius(16)
          .backgroundColor(SUB_CARD)
          .width('100%')
        }

        if (this.error !== '') {
          Text(this.error)
            .fontSize(12)
            .fontColor(DANGER)
            .width('100%')
        }
      }
      .padding({ left: 24, right: 24, top: 16, bottom: 28 + this.bottomInset })
      .width('100%')
    }
    .width('100%')
  }

  build() {
    NavDestination() {
      Column() {
        this.TopBar()

        if (this.error !== '') {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(16)
              .fontColor([DANGER])
            Text(this.error)
              .fontColor(TEXT_SUB)
              .fontSize(12)
              .layoutWeight(1)
            Text('重试')
              .fontColor(PRIMARY)
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .onClick(() => {
                this.load(this.aid);
              })
          }
          .padding(12)
          .margin({ left: 16, right: 16, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor(CARD)
        }

        if (this.busy && this.album === null) {
          Column({ space: 12 }) {
            LoadingProgress().width(40).height(40).color(PRIMARY)
            Text('正在解析作品详情与章节列表…')
              .fontSize(13)
              .fontColor(TEXT_SUB)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .width('100%')
        } else if (this.breakpoint !== 'sm') {
          Row() {
            Scroll() {
              this.Info()
            }
            .width('42%')
            .height('100%')
            .scrollBar(BarState.Off)

            Scroll() {
              this.Chapters()
            }
            .width('58%')
            .height('100%')
            .scrollBar(BarState.Off)
          }
          .layoutWeight(1)
          .width('100%')
        } else {
          Scroll() {
            Column() {
              this.Info()
              this.Chapters()
            }
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)
      .bindSheet($$this.sourceSheet, this.SourcesSheet(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        backgroundColor: CARD,
        systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK })
      })
    }
    .hideTitleBar(true)
    .backgroundColor(BG)
    .onReady((context: NavDestinationContext) => {
      const params: Record<string, Object> | null = asRecord(context.pathInfo.param as Object);
      this.aid = params === null ? '' : asString(params['aid']);
      this.load(this.aid);
      this.sourceSheet = params !== null && params['match'] === true;
    })
    .onShown(() => {
      this.refresh();
    })
    .onHidden(() => {
      this.generation++;
    })
  }
}
