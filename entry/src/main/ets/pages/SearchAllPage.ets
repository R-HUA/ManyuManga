import { sourceStore, SourceEntry } from '../data/Sources';
import { MangaRouteParams, ROUTE_ALBUM } from '../common/Route';
import { sourceApi } from '../data/SourceApi';
import { library } from '../data/Library';
import { highConfidence } from '../data/Matching';
import { Album, AlbumLite, SearchResult, asRecord, asString, errorMessage } from '../models/Models';
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
  TEXT_MAIN,
  TEXT_SUB,
  DIVIDER
} from '../common/Theme';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

class SearchGroup {
  source: SourceEntry = new SourceEntry();
  items: Array<AlbumLite> = [];
  page: number = 0;
  more: boolean = false;
  loading: boolean = true;
  error: string = '';
}

@Component
export struct SearchAllPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp('sourceVersion') @Watch('sourcesChanged') sourceVersion: number = 0;
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 0;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;

  @State query: string = '';
  @State groups: Array<SearchGroup> = [];
  @State error: string = '';
  @State matching: boolean = false;
  @State onlyHits: boolean = false;

  private ticket: number = 0;
  private onlySource: string = '';
  private matchAid: string = '';
  private origin: Album | null = null;
  private active: boolean = true;

  aboutToDisappear(): void {
    this.active = false;
    this.ticket++;
  }

  private sourcesChanged(): void {
    this.ticket++;
    if (this.active) {
      this.search();
    }
  }

  private async search(): Promise<void> {
    const ticket: number = ++this.ticket;
    const query: string = this.query.trim();
    try {
      const sources: Array<SourceEntry> = (await sourceStore.list()).filter((s: SourceEntry) =>
        s.enabled && (this.onlySource === '' || s.id === this.onlySource));
      if (ticket !== this.ticket) {
        return;
      }
      this.groups = sources.map((source: SourceEntry): SearchGroup => {
        const group: SearchGroup = new SearchGroup();
        group.source = source;
        return group;
      });
      this.error = sources.length === 0 ? '没有已启用的书源，请先在「书源」页启用' : '';
      let cursor: number = 0;
      const work = async (): Promise<void> => {
        while (ticket === this.ticket && cursor < sources.length) {
          const index: number = cursor++;
          await this.loadGroup(index, 1, ticket, query);
        }
      };
      await Promise.all([work(), work(), work()]);
      if (ticket === this.ticket && this.origin !== null) {
        await this.associateConfident(ticket);
      }
    } catch (e) {
      if (ticket === this.ticket) {
        this.error = errorMessage(e as Error);
      }
    }
  }

  private async loadGroup(index: number, page: number, ticket: number = this.ticket, query: string = this.query.trim()): Promise<void> {
    const group: SearchGroup = this.groups[index];
    group.loading = true;
    group.error = '';
    this.groups = this.groups.slice();
    try {
      const result: SearchResult = await sourceApi.searchSource(group.source, query, page);
      if (ticket !== this.ticket || !this.active) {
        return;
      }
      group.items = page === 1
        ? result.list
        : group.items.concat(result.list.filter((a: AlbumLite) => !group.items.some((b: AlbumLite) => a.id === b.id)));
      group.page = page;
      group.more = group.source.kind !== 'local' && result.list.length > 0 &&
        (result.hasNext !== null ? result.hasNext : result.total === 0 || group.items.length < result.total);
    } catch (e) {
      if (ticket === this.ticket) {
        group.error = errorMessage(e as Error);
      }
    } finally {
      if (ticket === this.ticket) {
        group.loading = false;
        this.groups = this.groups.slice();
      }
    }
  }

  private async associateConfident(ticket: number): Promise<void> {
    if (await library.workFor(this.matchAid) === null) {
      return;
    }
    this.matching = true;
    try {
      for (const group of this.groups) {
        if (this.origin === null || ticket !== this.ticket) {
          return;
        }
        const possible: Array<AlbumLite> = group.items.filter((a: AlbumLite) => a.title.trim() === this.origin!.name.trim());
        const matches: Array<Album> = [];
        for (const candidate of possible.slice(0, 5)) {
          const album: Album = await sourceApi.album(candidate.id);
          if (ticket !== this.ticket) {
            return;
          }
          if (album.id !== this.origin.id && highConfidence(this.origin, album)) {
            matches.push(album);
          }
        }
        if (matches.length === 1) {
          await library.associate(this.matchAid, matches[0]);
        }
      }
    } catch (e) {
      if (ticket === this.ticket) {
        this.error = errorMessage(e as Error);
      }
    } finally {
      if (ticket === this.ticket) {
        this.matching = false;
      }
    }
  }

  private async choose(item: AlbumLite): Promise<void> {
    if (this.matchAid === '') {
      this.stack.pushPathByName(ROUTE_ALBUM, { aid: item.id } as MangaRouteParams);
      return;
    }
    try {
      const album: Album = await sourceApi.album(item.id);
      this.getUIContext().showAlertDialog({
        title: '关联备选图源',
        message: `确认将《${album.name}》作为当前作品的关联图源吗？`,
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: {
          value: '确认关联',
          fontColor: PRIMARY,
          action: () => {
            (async (): Promise<void> => {
              if (await library.workFor(this.matchAid) === null && this.origin !== null) {
                await library.add(this.origin);
              }
              await library.associate(this.matchAid, album);
              this.stack.pop();
            })().catch((e: Error) => {
              this.error = errorMessage(e);
            });
          }
        }
      });
    } catch (e) {
      this.error = errorMessage(e as Error);
    }
  }

  private visibleGroups(): Array<SearchGroup> {
    if (!this.onlyHits) {
      return this.groups;
    }
    return this.groups.filter((g: SearchGroup) => g.loading || g.items.length > 0 || g.error !== '');
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        // Custom TopBar
        Row({ space: 10 }) {
          IconCircleButton({
            glyph: $r('sys.symbol.chevron_left'),
            onTap: (): void => {
              this.stack.pop();
            }
          })

          Text(this.matchAid === '' ? '全源并发检索' : '跨源比对与关联')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_MAIN)
            .layoutWeight(1)

          if (this.groups.length > 1) {
            Text(this.onlyHits ? '仅看有结果' : '全部图源')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.onlyHits ? Color.White : PRIMARY)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(14)
              .backgroundColor(this.onlyHits ? PRIMARY : PRIMARY_SOFT)
              .onClick(() => {
                this.onlyHits = !this.onlyHits;
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topInset + 8, bottom: 4 })
        .alignItems(VerticalAlign.Center)

        // Search Bar
        Row({ space: 8 }) {
          Search({
            value: this.query,
            placeholder: this.matchAid === '' ? '输入书名、作者或标签并发检索…' : '查找同一作品的其他图源…'
          })
            .layoutWeight(1)
            .height(40)
            .backgroundColor(CARD)
            .onChange((text: string) => {
              this.query = text;
              this.ticket++;
            })
            .onSubmit(() => {
              this.search();
            })

          Text('检索')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .borderRadius(18)
            .backgroundColor(PRIMARY)
            .onClick(() => {
              this.search();
            })
        }
        .padding({ left: 16, right: 16 })
        .width('100%')

        if (this.error !== '') {
          Text(this.error)
            .fontColor(DANGER)
            .fontSize(12)
            .padding({ left: 16, right: 16 })
            .width('100%')
        }

        if (this.matching) {
          Row({ space: 8 }) {
            LoadingProgress().width(16).height(16).color(PRIMARY)
            Text('正在自动核对作者、语言与版本置信度…')
              .fontColor(PRIMARY)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 16, right: 16, top: 4, bottom: 4 })
          .width('100%')
        }

        Scroll() {
          Column({ space: 16 }) {
            ForEach(this.visibleGroups(), (group: SearchGroup) => {
              Column({ space: 12 }) {
                Row({ space: 8 }) {
                  Text(group.source.kind === 'jm' ? 'JM' : (group.source.kind === 'local' ? '本地' : '扩展'))
                    .fontSize(10)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(group.source.kind === 'jm' ? ACCENT : PRIMARY)
                    .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                    .borderRadius(8)
                    .backgroundColor(group.source.kind === 'jm' ? ACCENT_SOFT : PRIMARY_SOFT)

                  Text(group.source.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(TEXT_MAIN)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  if (group.loading) {
                    LoadingProgress().width(20).height(20).color(PRIMARY)
                  } else {
                    Text(`${group.items.length} 部`)
                      .fontSize(12)
                      .fontColor(TEXT_SUB)
                  }
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                if (group.error !== '') {
                  Row({ space: 10 }) {
                    Text(group.error)
                      .fontSize(12)
                      .fontColor(TEXT_SUB)
                      .layoutWeight(1)
                      .maxLines(2)
                    Text('重试此源')
                      .fontSize(12)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(PRIMARY)
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .borderRadius(14)
                      .backgroundColor(PRIMARY_SOFT)
                      .onClick(() => {
                        const idx: number = this.groups.indexOf(group);
                        if (idx >= 0) {
                          this.loadGroup(idx, Math.max(1, group.page));
                        }
                      })
                  }
                  .width('100%')
                  .padding(10)
                  .borderRadius(12)
                  .backgroundColor(SUB_CARD)
                } else if (!group.loading && group.items.length === 0) {
                  Text('该图源未检索到相关漫画')
                    .fontColor(TEXT_SUB)
                    .fontSize(12)
                    .padding({ top: 4, bottom: 4 })
                }

                if (group.items.length > 0) {
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                    ForEach(group.items, (item: AlbumLite) => {
                      Column({ space: 6 }) {
                        SourceCover({ url: item.coverUrl, radius: 10 })
                        Text(item.title)
                          .fontSize(12)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(TEXT_MAIN)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                        if (item.author !== '') {
                          Text(item.author)
                            .fontSize(10)
                            .fontColor(TEXT_SUB)
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                        }
                      }
                      .width('31%')
                      .margin({ right: '2%', bottom: 12 })
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
                      .onClick(() => {
                        this.choose(item);
                      })
                    }, (item: AlbumLite) => item.id)
                  }
                  .width('100%')
                }

                if (group.more && !group.loading) {
                  Text('加载更多结果')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(PRIMARY)
                    .textAlign(TextAlign.Center)
                    .width('100%')
                    .padding({ top: 9, bottom: 9 })
                    .borderRadius(14)
                    .backgroundColor(SUB_CARD)
                    .onClick(() => {
                      const idx: number = this.groups.indexOf(group);
                      if (idx >= 0) {
                        this.loadGroup(idx, group.page + 1);
                      }
                    })
                }
              }
              .padding(16)
              .backgroundColor(CARD)
              .borderRadius(20)
              .border({ width: 0.5, color: DIVIDER })
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }, (group: SearchGroup) => `${group.source.id}_${group.items.length}_${group.loading}_${group.error}`)
          }
          .padding({ left: 16, right: 16, bottom: 32 + this.bottomInset })
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)
    }
    .hideTitleBar(true)
    .backgroundColor(BG)
    .onReady((context: NavDestinationContext) => {
      const params: Record<string, Object> | null = asRecord(context.pathInfo.param as Object);
      this.query = params === null ? '' : asString(params['query']);
      this.onlySource = params === null ? '' : asString(params['sourceId']);
      this.matchAid = params === null ? '' : asString(params['matchAid']);
      this.active = true;
      if (this.matchAid !== '') {
        sourceApi.album(this.matchAid).then((album: Album) => {
          this.origin = album;
          this.query = album.name;
          this.search();
        }).catch((e: Error) => {
          this.error = errorMessage(e);
        });
      } else {
        this.search();
      }
    })
    .onHidden(() => {
      this.active = false;
      this.ticket++;
    })
    .onShown(() => {
      this.active = true;
    })
  }
}
