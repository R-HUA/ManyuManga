/**
 * E-Hentai / ExHentai 专属画廊广场：瀑布流 + 游标分页 + 分类色标。
 * 复用 HarmonyOS-EhViewer 的瀑布流卡片设计（按页数动态高度、10 大分类色标、星级），
 * 交互与视觉对齐漫语沉浸光感主题；列表数据全部经 EhSource 适配器（里站未登录自动回退表站）。
 */
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { MangaRouteParams, ROUTE_ALBUM, ROUTE_SEARCH } from '../../common/Route';
import { ehSource, EhListPage } from '../../data/EhSource';
import { EhSettings } from '../../data/eh/EhSettings';
import { EhSearchFilter } from '../../data/eh/EhSearchFilter';
import { EhFilterSheet } from './EhFilterSheet';
import { GallerySite } from '../../data/eh/EhNative';
import { RequestAbortGroup, isRequestCancelled } from '../../util/RequestAbort';
import { AlbumLite, errorMessage } from '../../models/Models';
import { ComicCard } from '../../common/ComicCard';
import { IMMERSIVE_REGULAR_MATERIAL, IMMERSIVE_SHEET_MATERIAL, HDS_TITLE_STYLE } from '../../common/ImmersiveMaterials';
import { withoutBlockedAlbums } from '../../data/stores/FilterStores';
import { BasicDataSource } from '../../common/DataSource';
import { BG, comicColumns, CARD, PRIMARY, PRIMARY_SOFT, TEXT_SUB } from '../../common/Theme';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

const COLUMN_GAP: number = 12;
const ROW_GAP: number = 12;
const PREFERRED_ITEM_WIDTH: number = 176;

/** Area.width 可能是 number/'100%'，安全转数值。 */
function ehLengthToNumber(value: Length): number {
  if (typeof value === 'number') {
    return value;
  }
  if (typeof value === 'string') {
    const parsed: number = Number.parseFloat(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

@Component
export struct EhBrowsePage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 0;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;

  @State tab: number = 0;
  @State query: string = '';
  @State searchMode: boolean = false;
  @State items: Array<AlbumLite> = [];
  @State firstUrl: string = '';
  @State prevUrl: string = '';
  @State nextUrl: string = '';
  @State totalLabel: string = '';
  @State loading: boolean = false;
  @State error: string = '';
  @State siteLabel: string = 'E-Hentai';
  @State containerWidth: number = 0;
  @State filter: EhSearchFilter = new EhSearchFilter();
  @State filterSheet: boolean = false;
  @State refreshing: boolean = false;
  private ticket: number = 0;
  private scroller: Scroller = new Scroller();
  private listGate: RequestAbortGroup = new RequestAbortGroup();
  private gallerySource: BasicDataSource<AlbumLite> = new BasicDataSource<AlbumLite>();

  aboutToAppear(): void {
    this.siteLabel = EhSettings.site() === GallerySite.EX ? 'ExHentai' : 'E-Hentai';
    this.bootstrap();
  }

  private async bootstrap(): Promise<void> {
    this.filter = new EhSearchFilter();
    await this.load('reset');
  }

  aboutToDisappear(): void {
    this.ticket++;
    this.listGate.abortAll();
  }

  private baseUrl(): string {
    if (this.tab === 1) {
      return ehSource.popularUrl();
    }
    if (this.tab === 2) {
      return this.filter.buildListUrl(ehSource.watchedUrl());
    }
    if (this.tab === 3) {
      return this.filter.buildListUrl(ehSource.favoritesUrl());
    }
    return this.filter.buildListUrl(ehSource.homeUrl());
  }

  /** 加载模式：reset 回到当前入口/搜索首页；more 沿 nextUrl 游标追加；first 回列表头。 */
  private async load(mode: string): Promise<void> {
    if (mode === 'more' && (this.nextUrl === '' || this.loading)) {
      return;
    }
    this.listGate.abortAll();
    this.listGate = new RequestAbortGroup();
    const ticket: number = ++this.ticket;
    let url: string = '';
    if (mode === 'more') {
      url = this.nextUrl;
    } else if (mode === 'first') {
      url = this.firstUrl !== '' ? this.firstUrl
        : (this.query.trim() !== '' ? this.filter.buildUrl(this.query.trim()) : this.baseUrl());
    } else {
      url = this.query.trim() !== '' ? this.filter.buildUrl(this.query.trim()) : this.baseUrl();
    }
    this.loading = true;
    this.error = '';
    try {
      const page: EhListPage = await ehSource.list(url, this.listGate.control());
      if (ticket !== this.ticket) {
        return;
      }
      const incoming: Array<AlbumLite> = await withoutBlockedAlbums(page.items, 'eh');
      if (ticket !== this.ticket) {
        return;
      }
      if (mode === 'more' && this.items.length > 0) {
        const fresh: Array<AlbumLite> = incoming.filter((a: AlbumLite): boolean =>
          !this.items.some((b: AlbumLite): boolean => b.id === a.id));
        this.items = this.items.concat(fresh);
        this.gallerySource.appendItems(fresh);
      } else {
        this.items = incoming;
        this.gallerySource.setList(incoming);
      }
      this.nextUrl = page.nextUrl;
      this.prevUrl = page.prevUrl;
      this.firstUrl = page.firstUrl;
      this.totalLabel = page.totalLabel;
      this.siteLabel = EhSettings.site() === GallerySite.EX ? 'EXHENTAI' : 'E-HENTAI';
    } catch (e) {
      if (isRequestCancelled(e as Error) || ticket !== this.ticket) {
        return;
      }
      this.error = errorMessage(e as Error);
      if (mode !== 'more') {
        this.items = [];
        this.gallerySource.setList([]);
        this.nextUrl = '';
        this.prevUrl = '';
        this.firstUrl = '';
      }
    } finally {
      if (ticket === this.ticket) {
        this.loading = false;
        this.refreshing = false;
      }
    }
  }

  private open(item: AlbumLite): void {
    this.stack.pushPathByName(ROUTE_ALBUM, { aid: item.id } as MangaRouteParams);
  }

  // ─────────────── 瀑布流布局（列数/高度确定性计算） ───────────────

  private columnCount(): number {
    return comicColumns(this.containerWidth - 32);
  }

  private columnsTemplate(): string {
    const count: number = this.columnCount();
    let template: string = '';
    for (let index: number = 0; index < count; index++) {
      template = template.length === 0 ? '1fr' : `${template} 1fr`;
    }
    return template;
  }

  @Builder
  private GalleryCard(item: AlbumLite) {
    ComicCard({ aid: item.id, coverUrl: item.coverUrl, title: item.title, author: item.author, badge: item.category,
      onCardClick: (): void => this.open(item) })
  }

  @Builder
  private FlowFooter() {
    Row({ space: 8 }) {
      if (this.loading && this.items.length > 0) {
        LoadingProgress().width(18).height(18).color(PRIMARY)
        Text('正在加载下一组画廊…').fontSize(12).fontColor(TEXT_SUB)
      } else if (this.error !== '' && this.items.length > 0) {
        Text('加载失败，点击重试')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY)
          .onClick(() => {
            this.load('more');
          })
      } else if (this.items.length > 0 && this.nextUrl === '') {
        Text('— 没有更多了 —').fontSize(12).fontColor(TEXT_SUB)
      }
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ListBody() {
    if (this.loading && this.items.length === 0) {
      Column({ space: 10 }) {
        LoadingProgress().width(28).height(28).color(PRIMARY)
        Text('正在连接画廊广场…')
          .fontSize(13)
          .fontColor(TEXT_SUB)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.error !== '' && this.items.length === 0) {
      Column({ space: 12 }) {
        Text(this.error)
          .fontSize(13)
          .fontColor(TEXT_SUB)
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24 })
        Text('重试')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY)
          .padding({ left: 20, right: 20, top: 9, bottom: 9 })
          .borderRadius(16)
          .backgroundColor(PRIMARY_SOFT)
          .onClick(() => {
            this.load('reset');
          })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.items.length === 0) {
      Column() {
        Text(this.tab === 2 ? '关注订阅为空：登录后在我的标签页添加关注标签' :
          (this.tab === 3 ? '云端收藏为空：登录账号后可查看 E-Hentai 收藏夹' : '暂无画廊'))
          .fontSize(13)
          .fontColor(TEXT_SUB)
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      WaterFlow({ scroller: this.scroller, footer: (): void => this.FlowFooter() }) {
        LazyForEach(this.gallerySource, (item: AlbumLite) => {
          FlowItem() {
            this.GalleryCard(item)
          }
          .width('100%')
        }, (item: AlbumLite) => item.id)
      }
      .cachedCount(4)
      .clip(false)
      .width('100%')
      .layoutWeight(1)
      .columnsTemplate(this.columnsTemplate())
      .columnsGap(COLUMN_GAP)
      .rowsGap(ROW_GAP)
      .edgeEffect(EdgeEffect.Spring)
      .onReachEnd(() => {
        this.load('more');
      })
    }
  }

  @Builder
  private FilterSheetPanel() {
    EhFilterSheet({
      filter: this.filter,
      apply: (next: EhSearchFilter): void => {
        this.filter = next;
        this.load('reset');
      },
      close: (): void => {
        this.filterSheet = false;
      }
    })
  }

  build() {
    HdsNavDestination() {
      Column({ space: 12 }) {
        Select([{ value: '最新' }, { value: '热门' }, { value: '关注' }, { value: '收藏' }])
          .selected(this.tab).value(['最新', '热门', '关注', '收藏'][this.tab]).systemMaterial(IMMERSIVE_REGULAR_MATERIAL)
          .onSelect((index: number): void => { if (this.tab !== index) { this.tab = index; this.query = ''; this.load('reset'); } })
          .margin({ left: 16, right: 16 })
        if (EhSettings.exDowngraded()) { Text('里站未登录，已切换到表站').fontSize(13).fontColor(TEXT_SUB).padding({ left: 16, right: 16 }) }
        Refresh({ refreshing: $$this.refreshing }) {
          Column() { this.ListBody() }.width('100%').height('100%')
        }.layoutWeight(1).width('100%').padding({ left: 16, right: 16 })
        .onRefreshing(() => { this.load('reset'); })
        .onAreaChange((_old: Area, area: Area): void => { this.containerWidth = ehLengthToNumber(area.width); })
      }.width('100%').height('100%').alignItems(HorizontalAlign.Start).padding({ bottom: this.bottomInset })
      .bindSheet($$this.filterSheet, this.FilterSheetPanel(), { height: SheetSize.MEDIUM, dragBar: true, systemMaterial: IMMERSIVE_SHEET_MATERIAL })
    }.titleBar({ content: { title: { mainTitle: this.siteLabel }, menu: { value: [
      { content: { icon: $r('sys.symbol.magnifyingglass'), label: '搜索', action: (): void => { this.stack.pushPathByName(ROUTE_SEARCH, { sourceId: 'eh', scope: 'source' } as MangaRouteParams); } } },
      { content: { icon: $r('sys.symbol.slider_horizontal_2'), label: '筛选', action: (): void => { this.filterSheet = true; } } }
    ] } }, style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true, enableComponentSafeArea: true }).titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller]).backgroundColor(BG)
  }
}
