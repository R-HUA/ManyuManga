/**
 * E-Hentai / ExHentai 专属画廊广场：瀑布流 + 游标分页 + 分类色标。
 * 复用 HarmonyOS-EhViewer 的瀑布流卡片设计（按页数动态高度、10 大分类色标、星级），
 * 交互与视觉对齐漫语沉浸光感主题；列表数据全部经 EhSource 适配器（里站未登录自动回退表站）。
 */
import { MangaRouteParams, ROUTE_ALBUM } from '../../common/Route';
import { ehSource, EhListPage } from '../../data/EhSource';
import { EhSettings } from '../../data/eh/EhSettings';
import { EhSearchFilter } from '../../data/eh/EhSearchFilter';
import { EhFilterSheet } from './EhFilterSheet';
import { GallerySite } from '../../data/eh/EhNative';
import { RequestAbortGroup, isRequestCancelled } from '../../util/RequestAbort';
import { AlbumLite, errorMessage } from '../../models/Models';
import { IconCircleButton } from '../../common/Components';
import { ComicCard } from '../../common/ComicCard';
import { SearchSuggestField } from '../search/SearchSuggestField';
import { searchHistoryStore, withoutBlockedAlbums } from '../../data/stores/FilterStores';
import { BasicDataSource } from '../../common/DataSource';
import {
  BG,
  CARD,
  SUB_CARD,
  PRIMARY,
  PRIMARY_SOFT,
  TEXT_MAIN,
  TEXT_SUB,
  DIVIDER,
  BAR_LIGHT
} from '../../common/Theme';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

const COLUMN_GAP: number = 10;
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
  @State siteLabel: string = 'E-HENTAI';
  @State containerWidth: number = 0;
  @State filter: EhSearchFilter = new EhSearchFilter();
  @State filterSheet: boolean = false;
  private ticket: number = 0;
  private listGate: RequestAbortGroup = new RequestAbortGroup();
  private gallerySource: BasicDataSource<AlbumLite> = new BasicDataSource<AlbumLite>();

  aboutToAppear(): void {
    this.siteLabel = EhSettings.site() === GallerySite.EX ? 'EXHENTAI' : 'E-HENTAI';
    this.bootstrap();
  }

  private async bootstrap(): Promise<void> {
    this.filter = await EhSearchFilter.load();
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
      }
    }
  }

  private open(item: AlbumLite): void {
    this.stack.pushPathByName(ROUTE_ALBUM, { aid: item.id } as MangaRouteParams);
  }

  // ─────────────── 瀑布流布局（列数/高度确定性计算） ───────────────

  private columnCount(): number {
    const width: number = this.containerWidth;
    if (width <= 0) {
      return 2;
    }
    const columns: number = Math.floor((width + COLUMN_GAP) / (PREFERRED_ITEM_WIDTH + COLUMN_GAP));
    return Math.max(2, columns);
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
  private TabChip(label: string, index: number) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.tab === index ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.tab === index ? PRIMARY : TEXT_SUB)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .borderRadius(16)
      .backgroundColor(this.tab === index ? PRIMARY_SOFT : SUB_CARD)
      .onClick(() => {
        if (this.tab !== index) {
          this.tab = index;
          this.query = '';
          this.searchMode = false;
          this.load('reset');
        }
      })
  }

  @Builder
  private PagerButton(label: string, enabled: boolean, onTap: () => void) {
    Text(label)
      .fontSize(13)
      .fontWeight(FontWeight.Bold)
      .fontColor(enabled ? PRIMARY : TEXT_SUB)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 9, bottom: 9 })
      .borderRadius(16)
      .backgroundColor(SUB_CARD)
      .opacity(enabled ? 1.0 : 0.45)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
      .onClick(() => {
        if (enabled) {
          onTap();
        }
      })
  }

  @Builder
  private GalleryCard(item: AlbumLite) {
    Column() {
      ComicCard({
        coverUrl: item.coverUrl,
        aid: item.id,
        title: item.title,
        author: item.author,
        badge: item.category,
        onCardClick: (): void => {
          this.open(item);
        }
      })
    }
    .width('100%')
    .padding(10)
    .backgroundColor(CARD)
    .borderRadius(16)
    .border({ width: 0.5, color: DIVIDER })
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
      WaterFlow() {
        LazyForEach(this.gallerySource, (item: AlbumLite) => {
          FlowItem() {
            this.GalleryCard(item)
          }
          .width('100%')
        }, (item: AlbumLite) => item.id)
      }
      .cachedCount(4)
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
    NavDestination() {
      Column() {
        // 单一沉浸顶栏：返回 + 站点/入口标题 + 搜索
        Row({ space: 12 }) {
          IconCircleButton({
            symbol: $r('sys.symbol.chevron_left'),
            onTap: (): void => {
              this.stack.pop();
            }
          })

          Column({ space: 2 }) {
            Text(`E-Hentai · ${this.siteLabel === 'EXHENTAI' ? '里站' : '表站'}`)
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_MAIN)
              .maxLines(1)
            Text(EhSettings.exDowngraded() ? '里站未登录，已临时回退表站' : '画廊广场 · 热门 · 关注 · 云端收藏')
              .fontSize(11)
              .fontColor(TEXT_SUB)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          IconCircleButton({
            symbol: $r('sys.symbol.slider_horizontal_2'),
            active: this.filter.hasActiveFilter(),
            onTap: (): void => {
              this.filterSheet = true;
            }
          })

          IconCircleButton({
            symbol: $r('sys.symbol.magnifyingglass'),
            active: this.searchMode,
            onTap: (): void => {
              this.searchMode = !this.searchMode;
              if (!this.searchMode && this.query !== '') {
                this.query = '';
                this.load('reset');
              }
            }
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topInset + 8, bottom: 8 })
        .backgroundColor(BAR_LIGHT)
        .backgroundBlurStyle(BlurStyle.Regular)
        .border({ width: { bottom: 0.5 }, color: DIVIDER })

        if (this.searchMode) {
          SearchSuggestField({
            text: this.$query,
            sourceId: 'eh',
            placeholder: '搜索画廊，支持 artist:xxx / language:chinese 语法…',
            onSubmit: (val: string): void => {
              this.query = val;
              if (val.trim() !== '') {
                searchHistoryStore.record(val.trim()).catch((): void => {});
              }
              this.load('reset');
            }
          })
            .margin({ left: 16, right: 16, top: 8 })
        }

        // 入口页签
        Row({ space: 8 }) {
          this.TabChip('最新', 0)
          this.TabChip('热门', 1)
          this.TabChip('关注', 2)
          this.TabChip('收藏', 3)
          Blank()
          if (this.totalLabel !== '') {
            Text(`共 ${this.totalLabel} 个`)
              .fontSize(11)
              .fontColor(TEXT_SUB)
              .maxLines(1)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 4 })

        Column() {
          this.ListBody()
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16 })
        .onAreaChange((_old: Area, newArea: Area) => {
          const width: number = ehLengthToNumber(newArea.width);
          if (width > 0 && Math.abs(width - this.containerWidth) >= 1) {
            this.containerWidth = width;
          }
        })

        if (this.error !== '' && this.items.length > 0) {
          Text(this.error)
            .fontSize(12)
            .fontColor(TEXT_SUB)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ left: 16, right: 16, top: 4 })
        }

        if (this.items.length > 0 && (this.nextUrl !== '' || this.prevUrl !== '' || this.firstUrl !== '')) {
          Row({ space: 10 }) {
            this.PagerButton('首页', this.firstUrl !== '', () => {
              this.load('first');
            })
            this.PagerButton('重载', true, () => {
              this.load('reset');
            })
            this.PagerButton('加载更多', this.nextUrl !== '' && !this.loading, () => {
              this.load('more');
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.bottomInset })
      .backgroundColor(BG)
      .bindSheet($$this.filterSheet, this.FilterSheetPanel(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        backgroundColor: CARD
      })
    }
    .hideTitleBar(true)
  }
}
