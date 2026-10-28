import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { BasicDataSource } from '../common/DataSource';
import { ComicCard } from '../common/ComicCard';
import { comicColumns, BG, TEXT_SUB, DANGER, HDS_TITLE_BAR_HEIGHT } from '../common/Theme';
import { HDS_TITLE_STYLE } from '../common/ImmersiveMaterials';
import { MangaRouteParams, ROUTE_ALBUM, ROUTE_SEARCH } from '../common/Route';
import { sourceApi } from '../data/SourceApi';
import { sourceStore, SourceEntry } from '../data/Sources';
import { AlbumLite, SearchResult, asRecord, asString, errorMessage } from '../models/Models';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

@Component
export struct SourceBrowsePage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 38;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottom: number = 0;
  @State private title: string = '';
  @State private contentWidth: number = 328;
  @State private loading: boolean = false;
  @State private refreshing: boolean = false;
  @State private error: string = '';
  @State private more: boolean = true;
  private sourceId: string = '';
  private mode: string = '';
  private order: string = 'mv_t';
  private page: number = 0;
  private generation: number = 0;
  private items: Array<AlbumLite> = [];
  private data: BasicDataSource<AlbumLite> = new BasicDataSource<AlbumLite>();
  private scroller: Scroller = new Scroller();

  aboutToDisappear(): void { this.generation++; }

  private async initialize(context: NavDestinationContext): Promise<void> {
    try {
      const params: Record<string, Object> | null = asRecord(context.pathInfo.param as Object);
      this.sourceId = params === null ? '' : asString(params['sourceId']);
      this.mode = params === null ? '' : asString(params['browseMode']);
      this.order = params === null ? 'mv_t' : asString(params['order'], 'mv_t');
      const source: SourceEntry = await sourceStore.get(this.sourceId);
      this.title = this.mode === 'latest' ? '最新上架' : this.mode === 'ranking' ? '热门' : source.name;
      await this.load(true);
    } catch (e) { this.error = errorMessage(e as Error); }
  }

  private async load(reset: boolean): Promise<void> {
    if (!reset && (this.loading || !this.more)) { return; }
    const ticket: number = reset ? ++this.generation : this.generation;
    const page: number = reset ? 1 : this.page + 1;
    this.loading = true;
    this.error = '';
    try {
      let list: Array<AlbumLite>;
      let hasNext: boolean;
      if (this.mode === 'latest' || this.mode === 'ranking') {
        list = this.mode === 'latest' ? await sourceApi.latest(this.sourceId, page) : await sourceApi.ranking(this.sourceId, '', this.order, page);
        hasNext = list.length > 0;
      } else {
        const result: SearchResult = await sourceApi.browseSource(this.sourceId, page);
        list = result.list;
        hasNext = list.length > 0 && (result.hasNext !== null ? result.hasNext : result.total === 0 || (reset ? 0 : this.items.length) + list.length < result.total);
      }
      if (ticket !== this.generation) { return; }
      this.items = reset ? list : this.items.concat(list.filter((item: AlbumLite): boolean => !this.items.some((old: AlbumLite): boolean => old.id === item.id)));
      this.data.setList(this.items);
      this.page = page;
      this.more = hasNext;
    } catch (e) { if (ticket === this.generation) { this.error = errorMessage(e as Error); } }
    finally { if (ticket === this.generation) { this.loading = false; this.refreshing = false; } }
  }

  @Builder
  private Footer() {
    Column({ space: 8 }) {
      if (this.loading) { LoadingProgress().width(28).height(28) }
      else if (this.error !== '') {
        Text(this.error).fontSize(13).fontColor(DANGER)
        Button('重试', { buttonStyle: ButtonStyleMode.NORMAL }).onClick(() => this.load(this.page === 0))
      } else if (!this.more) { Text(this.items.length === 0 ? '暂无内容' : '没有更多了').fontSize(13).fontColor(TEXT_SUB) }
    }.width('100%').padding({ top: 20, bottom: 28 + this.bottom })
  }

  build() {
    HdsNavDestination() {
      Refresh({ refreshing: $$this.refreshing }) {
        WaterFlow({ scroller: this.scroller, footer: this.Footer }) {
          LazyForEach(this.data, (item: AlbumLite) => {
            FlowItem() {
              ComicCard({ aid: item.id, coverUrl: item.coverUrl, title: item.title, author: item.author, badge: item.category,
                onCardClick: (): void => { this.stack.pushPathByName(ROUTE_ALBUM, { aid: item.id } as MangaRouteParams); } })
            }.width((this.contentWidth - 12 * (comicColumns(this.contentWidth) - 1)) / comicColumns(this.contentWidth))
          }, (item: AlbumLite) => item.id)
        }.columnsTemplate(`1fr `.repeat(comicColumns(this.contentWidth))).columnsGap(12).rowsGap(16)
        .width('100%').height('100%').padding({ left: 16, right: 16, top: this.topInset + HDS_TITLE_BAR_HEIGHT + 12, bottom: 20 }).clip(false)
        .onAreaChange((_old: Area, area: Area): void => { this.contentWidth = Number(area.width) - 32; })
        .onReachEnd(() => { this.load(false); })
      }.onRefreshing(() => { this.load(true); })
    }.titleBar({ content: { title: { mainTitle: this.title }, menu: { value: [
      { content: { icon: $r('sys.symbol.magnifyingglass'), label: '搜索', action: (): void => { this.stack.pushPathByName(ROUTE_SEARCH, { sourceId: this.sourceId, scope: 'source' } as MangaRouteParams); } } }
    ] } }, style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true }).titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller]).backgroundColor(BG).onReady((context: NavDestinationContext): void => { this.initialize(context); })
  }
}
