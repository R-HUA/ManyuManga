import { ehSource, EhListPage } from '../../data/EhSource';
import { EhSearchFilter } from '../../data/eh/EhSearchFilter';
import { RequestAbortGroup, isRequestCancelled } from '../../util/RequestAbort';
import { AlbumLite, errorMessage } from '../../models/Models';
import { ComicCard } from '../../common/ComicCard';
import { withoutBlockedAlbums } from '../../data/stores/FilterStores';
import { BasicDataSource } from '../../common/DataSource';
import { comicColumns, PRIMARY, PRIMARY_SOFT, TEXT_SUB, HDS_TITLE_BAR_HEIGHT } from '../../common/Theme';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

const COLUMN_GAP: number = 12;
const ROW_GAP: number = 12;

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
export struct EhGalleryPane {
  @Prop galleryIndex: number = 0;
  @Prop @Watch('onFilterChanged') filter: EhSearchFilter = new EhSearchFilter();
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 38;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  onOpen: (item: AlbumLite) => void = (_item: AlbumLite): void => {};

  @State items: Array<AlbumLite> = [];
  @State firstUrl: string = '';
  @State prevUrl: string = '';
  @State nextUrl: string = '';
  @State totalLabel: string = '';
  @State loading: boolean = false;
  @State error: string = '';
  @State containerWidth: number = 360;
  @State refreshing: boolean = false;

  private ticket: number = 0;
  private listGate: RequestAbortGroup = new RequestAbortGroup();
  private gallerySource: BasicDataSource<AlbumLite> = new BasicDataSource<AlbumLite>();

  aboutToAppear(): void {
    this.load('reset');
  }

  aboutToDisappear(): void {
    this.ticket++;
    this.listGate.abortAll();
  }

  private onFilterChanged(): void {
    this.load('reset');
  }

  private baseUrl(): string {
    if (this.galleryIndex === 1) {
      return ehSource.popularUrl();
    }
    if (this.galleryIndex === 2) {
      return this.filter.buildListUrl(ehSource.watchedUrl());
    }
    if (this.galleryIndex === 3) {
      return this.filter.buildListUrl(ehSource.favoritesUrl());
    }
    return this.filter.buildListUrl(ehSource.homeUrl());
  }

  public async load(mode: string): Promise<void> {
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
      url = this.firstUrl !== '' ? this.firstUrl : this.baseUrl();
    } else {
      url = this.baseUrl();
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

  build() {
    Refresh({ refreshing: $$this.refreshing }) {
      if (this.loading && this.items.length === 0) {
        Column({ space: 10 }) {
          LoadingProgress().width(28).height(28).color(PRIMARY)
          Text('正在连接画廊广场…')
            .fontSize(13)
            .fontColor(TEXT_SUB)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.error !== '' && this.items.length === 0) {
        Column({ space: 12 }) {
          Text(this.error)
            .fontSize(13)
            .fontColor(TEXT_SUB)
            .textAlign(TextAlign.Center)
            .padding({ left: 24, right: 24 })
          Button('重试', { buttonStyle: ButtonStyleMode.NORMAL, controlSize: ControlSize.SMALL })
            .onClick(() => {
              this.load('reset');
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.items.length === 0) {
        Column() {
          Text(this.galleryIndex === 2 ? '关注订阅为空：登录后在我的标签页添加关注标签' :
            (this.galleryIndex === 3 ? '云端收藏为空：登录账号后可查看 E-Hentai 收藏夹' : '暂无画廊'))
            .fontSize(13)
            .fontColor(TEXT_SUB)
            .textAlign(TextAlign.Center)
            .padding({ left: 24, right: 24 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        WaterFlow({ scroller: this.scroller, footer: (): void => this.FlowFooter() }) {
          LazyForEach(this.gallerySource, (item: AlbumLite) => {
            FlowItem() {
              ComicCard({
                aid: item.id,
                coverUrl: item.coverUrl,
                title: item.title,
                author: item.author,
                badge: item.category,
                onCardClick: (): void => {
                  this.onOpen(item);
                }
              })
            }
            .width((this.containerWidth - 32 - COLUMN_GAP * (this.columnCount() - 1)) / this.columnCount())
          }, (item: AlbumLite) => item.id)
        }
        .cachedCount(4)
        .clip(false)
        .columnsTemplate(this.columnsTemplate())
        .columnsGap(COLUMN_GAP)
        .rowsGap(ROW_GAP)
        .padding({ left: 16, right: 16, top: this.topInset + HDS_TITLE_BAR_HEIGHT + 12, bottom: 64 + this.bottomInset })
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .height('100%')
        .onReachEnd(() => {
          this.load('more');
        })
      }
    }
    .width('100%')
    .height('100%')
    .onRefreshing(() => {
      this.load('reset');
    })
    .onAreaChange((_old: Area, area: Area): void => {
      this.containerWidth = ehLengthToNumber(area.width);
    })
  }
}
