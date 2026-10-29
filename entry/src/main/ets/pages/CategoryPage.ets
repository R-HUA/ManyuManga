import { CategoryBrowseQuery } from './jm/CategoryBrowseQuery';
import { ComicCard } from '../common/ComicCard';
import { badgeForAlbum, formatCount, langBadgeFor } from '../common/ComicBadge';
import { BasicDataSource } from '../common/DataSource';
import { FONT_CAPTION, PRIMARY, SPACE_L, SPACE_M, SPACE_S, TEXT_SUB, TAB_BAR_HEIGHT, comicColumns } from '../common/Theme';
import { EmptyView, SkeletonGrid } from '../common/Components';
import { ROUTE_ALBUM } from '../common/Route';
import { AlbumLite, errorMessage } from '../models/Models';
import { sourceApi } from '../data/SourceApi';
import { sourceId, sourceStore } from '../data/Sources';
import { blockTagsStore } from '../data/Stores';
import { BOTTOM_RECT_HEIGHT_KEY, CURRENT_BREAKPOINT_KEY } from '../entryability/EntryAbility';
export { formatCount, langBadgeFor } from '../common/ComicBadge';

class AlbumRouteParam {
  aid: string = '';
}

export class ChipOption {
  code: string;
  label: string;

  constructor(code: string, label: string) {
    this.code = code;
    this.label = label;
  }
}

export class AlbumSource extends BasicDataSource<AlbumLite> {
  setItems(items: Array<AlbumLite>): void { this.setList(items); }
  count(): number { return this.totalCount(); }
}

@Component
export struct CategoryPage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @Prop embeddedInShell: boolean = false;
  @Prop sourceIdValue: string = '';
  @Prop @Watch('onQueryChanged') query: CategoryBrowseQuery = new CategoryBrowseQuery();

  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 16;
  @StorageProp(CURRENT_BREAKPOINT_KEY) bp: string = 'sm';
  @StorageProp('blockTagsVersion') @Watch('onBlockTagsChanged') blockVer: number = 0;

  @State firstLoading: boolean = true;
  @State firstError: string = '';
  @State emptyResult: boolean = false;
  @State loadingMore: boolean = false;
  @State moreError: boolean = false;
  @State finished: boolean = false;
  @State loadedCount: number = 0;
  @State private contentWidth: number = 328;
  @State private refreshing: boolean = false;

  private source: AlbumSource = new AlbumSource();
  scroller: Scroller = new Scroller();
  private page: number = 1;
  private requestSeq: number = 0;
  private rawItems: Array<AlbumLite> = [];
  private pageSeenIds: Set<string> = new Set<string>();
  private dupPageStreak: number = 0;

  aboutToAppear(): void {
    sourceApi.init().catch((e: Error) => {
      console.info(`[CategoryPage] sourceApi.init: ${errorMessage(e)}`);
    });
    this.reload();
  }

  aboutToDisappear(): void { this.requestSeq++; }

  private onQueryChanged(): void {
    this.reload();
  }

  private async filterBlocked(list: Array<AlbumLite>): Promise<Array<AlbumLite>> {
    const out: Array<AlbumLite> = [];
    for (const it of list) {
      const owner: string = it.id.indexOf('~') > 0 ? sourceId(it.id) : '';
      const blocked: boolean =
        await blockTagsStore.isBlocked(it.title, it.author, it.category, it.categorySub, owner);
      if (!blocked) {
        out.push(it);
      }
    }
    return out;
  }

  private onBlockTagsChanged(): void {
    this.refilterBlocked().catch((e: Error) => {
      console.info(`[CategoryPage] 屏蔽词重过滤失败: ${errorMessage(e)}`);
    });
  }

  private async refilterBlocked(): Promise<void> {
    if (this.rawItems.length === 0) {
      return;
    }
    const visible: Array<AlbumLite> = await this.filterBlocked(this.rawItems);
    this.source.setItems(visible);
    this.loadedCount = this.source.count();
    this.emptyResult = this.source.count() === 0;
  }

  private async reload(): Promise<void> {
    if (this.loadedCount > 0) { this.scroller.scrollTo({ xOffset: 0, yOffset: 0 }); }
    this.loadingMore = false;
    this.page = 1;
    this.finished = false;
    this.moreError = false;
    this.emptyResult = false;
    this.firstError = '';
    this.firstLoading = true;
    this.loadedCount = 0;
    this.rawItems = [];
    this.pageSeenIds = new Set<string>();
    this.dupPageStreak = 0;
    this.source.setItems([]);
    await this.fetchPage(1);
  }

  private async loadMore(): Promise<void> {
    if (this.firstLoading || this.loadingMore || this.finished || this.moreError) {
      return;
    }
    this.loadingMore = true;
    this.moreError = false;
    await this.fetchPage(this.page + 1);
  }

  private retryMore(): void {
    this.moreError = false;
    this.loadMore();
  }

  private dedupById(list: Array<AlbumLite>): Array<AlbumLite> {
    const local: Set<string> = new Set<string>();
    const out: Array<AlbumLite> = [];
    for (const it of list) {
      if (it.id !== '') {
        if (this.pageSeenIds.has(it.id) || local.has(it.id)) {
          continue;
        }
        local.add(it.id);
      }
      out.push(it);
    }
    return out;
  }

  private rememberIds(list: Array<AlbumLite>): void {
    for (const it of list) {
      if (it.id !== '') {
        this.pageSeenIds.add(it.id);
      }
    }
  }

  private async fetchPage(target: number): Promise<void> {
    const seq: number = ++this.requestSeq;
    const snapshot: CategoryBrowseQuery = this.query;
    const slug: string = snapshot.categoryId === '' || snapshot.categorySlug === '' ? '0' : snapshot.categorySlug;
    const query: string = snapshot.customQuery;
    const order: string = snapshot.order;
    try {
      const raw: Array<AlbumLite> = query === '' ? await sourceApi.ranking(this.sourceIdValue, slug, order, target) :
        (await sourceApi.searchSource(await sourceStore.get(this.sourceIdValue), query, target)).list;
      if (seq !== this.requestSeq) {
        return;
      }
      const fresh: Array<AlbumLite> = this.dedupById(raw);
      const visible: Array<AlbumLite> = await this.filterBlocked(fresh);
      if (seq !== this.requestSeq) {
        return;
      }
      if (target === 1) {
        this.rememberIds(fresh);
        this.rawItems = fresh.slice();
        this.source.setItems(visible);
        this.emptyResult = fresh.length === 0;
        this.dupPageStreak = 0;
      } else if (raw.length === 0) {
        this.finished = true;
      } else if (fresh.length === 0) {
        this.dupPageStreak++;
        if (this.dupPageStreak >= 2) {
          this.finished = true;
        }
      } else {
        this.dupPageStreak = 0;
        this.rememberIds(fresh);
        this.rawItems = this.rawItems.concat(fresh);
        this.source.appendItems(visible);
      }
      if (fresh.length > 0 || (target > 1 && raw.length > 0 && !this.finished)) {
        this.page = target;
      }
      this.loadedCount = this.source.count();
    } catch (e) {
      if (seq !== this.requestSeq) {
        return;
      }
      const msg: string = errorMessage(e as Error);
      if (target === 1 && this.source.count() === 0) {
        this.firstError = msg;
      } else {
        this.moreError = true;
      }
    } finally {
      if (seq === this.requestSeq) {
        this.firstLoading = false;
        this.loadingMore = false;
        this.refreshing = false;
      }
    }
  }

  private gridColumns(): number {
    return comicColumns(this.contentWidth);
  }

  private columnsTemplateStr(): string {
    const parts: Array<string> = [];
    for (let i: number = 0; i < this.gridColumns(); i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  private openAlbum(item: AlbumLite): void {
    const p: AlbumRouteParam = new AlbumRouteParam();
    p.aid = item.id;
    this.navPathStack.pushPathByName(ROUTE_ALBUM, p);
  }

  @Builder
  private Content() {
    if (this.firstLoading) {
      Column() {
        SkeletonGrid({ columns: this.gridColumns(), rows: 3 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: SPACE_L, right: SPACE_L, top: 8 })
    } else if (this.firstError !== '') {
      Column() {
        EmptyView({
          message: this.firstError,
          retryText: '重试',
          showRetry: true,
          onRetry: (): void => {
            this.reload();
          }
        })
      }
      .width('100%')
      .height('100%')
      .padding({ top: 8 })
    } else if (this.emptyResult) {
      Column() {
        EmptyView({
          message: '这个分类下暂时没有作品',
          showRetry: false
        })
      }
      .width('100%')
      .height('100%')
      .padding({ top: 8 })
    } else {
      WaterFlow({ scroller: this.scroller, footer: (): void => this.Footer() }) {
        LazyForEach(this.source, (item: AlbumLite) => {
          FlowItem() {
            ComicCard({
              aid: item.id,
              coverUrl: item.coverUrl,
              title: item.title,
              author: item.author,
              badge: badgeForAlbum(item),
              onCardClick: (): void => {
                this.openAlbum(item);
              }
            })
          }.width((this.contentWidth - SPACE_M * (this.gridColumns() - 1)) / this.gridColumns())
        }, (item: AlbumLite) => item.id)
      }
      .columnsTemplate(this.columnsTemplateStr())
      .columnsGap(SPACE_M)
      .rowsGap(14)
      .padding({ left: SPACE_L, right: SPACE_L, top: 8, bottom: SPACE_S })
      .cachedCount(Math.max(4, this.gridColumns()), true)
      .clip(false)
      .width('100%')
      .height('100%')
      .onReachEnd(() => {
        this.loadMore();
      })
    }
  }

  @Builder
  private Footer() {
    Column() {
      Row({ space: SPACE_S }) {
        if (this.loadingMore) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(PRIMARY)
          Text('加载中…')
            .fontSize(FONT_CAPTION)
            .fontColor(TEXT_SUB)
        } else if (this.moreError) {
          Text('加载失败，点击重试')
            .fontSize(FONT_CAPTION)
            .fontColor(PRIMARY)
            .onClick(() => {
              this.retryMore();
            })
        } else if (this.finished) {
          Text('— 没有更多了 —')
            .fontSize(FONT_CAPTION)
            .fontColor(TEXT_SUB)
        } else {
          Text('上拉加载更多')
            .fontSize(FONT_CAPTION)
            .fontColor(TEXT_SUB)
        }
      }
      .width('100%')
      .height(40)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ bottom: (this.embeddedInShell ? TAB_BAR_HEIGHT : 0) + this.bottomInset + SPACE_S })
  }

  build() {
    Refresh({ refreshing: $$this.refreshing }) {
      this.Content()
    }
    .width('100%')
    .height('100%')
    .onRefreshing(() => { this.reload(); })
    .onAreaChange((_old: Area, area: Area): void => { this.contentWidth = Number(area.width) - 32; })
  }
}
