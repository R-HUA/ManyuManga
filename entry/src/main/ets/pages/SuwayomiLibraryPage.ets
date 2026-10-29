import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { SegmentButton, SegmentButtonOptions, SegmentButtonItemTuple } from '@kit.ArkUI';
import { EMPTY_MATERIAL, HDS_TITLE_STYLE } from '../common/ImmersiveMaterials';
import { ComicGrid } from '../common/ComicGrid';
import { EmptyView, SkeletonGrid } from '../common/Components';
import { BG, CARD, DIVIDER, PRIMARY, PRIMARY_SOFT, SUB_CARD, TEXT_MAIN, TEXT_SUB } from '../common/Theme';
import { MangaRouteParams, ROUTE_ALBUM, ROUTE_SOURCE_SETTINGS } from '../common/Route';
import { BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';
import { sourceStore, SourceEntry, copySource } from '../data/Sources';
import { sourceApi } from '../data/SourceApi';
import { suwayomiLibrary, RemoteCategory, RemoteSource, RemoteManga, RemoteMangaPage, LibrarySort } from '../data/SuwayomiLibrary';
import { AlbumLite, asRecord, asString, errorMessage } from '../models/Models';
import { RequestAbortGroup, isRequestCancelled } from '../util/RequestAbort';
import { SearchGroup, SearchGroupResults } from './search/SearchGroupResults';

/** 一个服务对应一个书库；扩展身份只在内部检索和作品路由中使用。 */
@Component
export struct SuwayomiLibraryPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp('sourceVersion') @Watch('connectionChanged') sourceVersion: number = 0;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  @State categories: Array<RemoteCategory> = [];
  @State albums: Array<AlbumLite> = [];
  @State groups: Array<SearchGroup> = [];
  @State query: string = '';
  @State editing: boolean = false;
  @State submitted: string = '';
  @State categoryId: number = -1;
  @State sort: LibrarySort = 'added';
  @State explore: boolean = false;
  @State @Watch('scopeChanged') scopeIndexes: number[] = [0];
  @State scopeOptions: SegmentButtonOptions = SegmentButtonOptions.capsule({
    multiply: false,
    buttons: [{ text: $r('app.string.remote_library') }, { text: $r('app.string.remote_sources') }] as SegmentButtonItemTuple,
    fontColor: TEXT_SUB, selectedFontColor: TEXT_MAIN, fontSize: 14, selectedFontSize: 14,
    backgroundColor: SUB_CARD, selectedBackgroundColor: CARD,
    buttonPadding: { top: 6, bottom: 6, left: 12, right: 12 }
  });
  @State hideSaved: boolean = false;
  @State connected: boolean = false;
  @State loading: boolean = false;
  @State more: boolean = false;
  @State error: string = '';
  private gateway: SourceEntry | null = null;
  private cursor: string = '';
  private generation: number = 0;
  private requests: RequestAbortGroup = new RequestAbortGroup();
  private active: boolean = false;
  private ready: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToDisappear(): void { this.hide(); }

  private hide(): void {
    this.active = false;
    this.generation++;
    this.requests.abortAll();
    this.loading = false;
  }

  private connectionChanged(): void {
    this.generation++;
    this.requests.abortAll();
    if (this.active) { this.initialize(); }
  }

  private renew(): number {
    this.requests.abortAll();
    this.requests = new RequestAbortGroup();
    return ++this.generation;
  }

  private current(ticket: number): boolean { return this.active && ticket === this.generation; }

  private async initialize(): Promise<void> {
    const ticket: number = this.renew();
    this.loading = true;
    this.error = '';
    this.albums = [];
    this.groups = [];
    this.more = false;
    try {
      const gateway: SourceEntry | null = await sourceStore.gateway();
      if (!this.current(ticket)) { return; }
      this.gateway = gateway;
      this.connected = gateway !== null;
      if (gateway === null) { this.categories = []; return; }
      const categories: Array<RemoteCategory> = await suwayomiLibrary.categories(gateway, this.requests);
      if (!this.current(ticket)) { return; }
      this.categories = categories;
      if (this.categoryId !== -1 && !categories.some((item: RemoteCategory): boolean => item.id === this.categoryId)) {
        this.categoryId = -1;
      }
      await this.reload();
    } catch (e) {
      if (this.current(ticket) && !isRequestCancelled(e as Error)) { this.error = errorMessage(e as Error); }
    } finally {
      if (this.current(ticket)) { this.loading = false; }
    }
  }

  private async reload(): Promise<void> {
    const ticket: number = this.renew();
    this.cursor = '';
    this.albums = [];
    this.groups = [];
    this.more = false;
    this.error = '';
    this.loading = false;
    if (this.gateway === null) { return; }
    if (this.editing) { return; }
    if (!this.explore) { await this.loadLibrary(ticket); return; }
    if (this.submitted === '') { return; }
    this.loading = true;
    try {
      const sources: Array<RemoteSource> = await suwayomiLibrary.serverSources(this.gateway, this.requests);
      if (!this.current(ticket)) { return; }
      const gateway: SourceEntry = this.gateway;
      this.groups = sources.map((source: RemoteSource): SearchGroup => {
        const group: SearchGroup = new SearchGroup();
        group.source = copySource(gateway);
        group.source.remoteId = source.id;
        group.source.id = `${gateway.instanceId}_${source.id}`;
        group.source.name = source.displayName;
        group.query = this.submitted;
        return group;
      });
      const groups: Array<SearchGroup> = this.groups;
      let index: number = 0;
      const worker = async (): Promise<void> => {
        while (this.current(ticket) && index < groups.length) {
          await this.loadRemote(groups[index++], ticket);
        }
      };
      await Promise.all([worker(), worker(), worker()]);
    } catch (e) {
      if (this.current(ticket) && !isRequestCancelled(e as Error)) { this.error = errorMessage(e as Error); }
    } finally {
      if (this.current(ticket)) { this.loading = false; }
    }
  }

  private async loadLibrary(ticket: number = this.generation): Promise<void> {
    if (this.loading || this.gateway === null || !this.current(ticket)) { return; }
    this.loading = true;
    this.error = '';
    try {
      const page: RemoteMangaPage = await sourceApi.remoteLibrary(this.gateway, this.categoryId,
        this.submitted, this.sort, this.cursor, this.requests);
      if (!this.current(ticket)) { return; }
      this.albums = this.albums.concat(page.albums.filter((item: AlbumLite): boolean =>
        !this.albums.some((old: AlbumLite): boolean => old.id === item.id)));
      this.cursor = page.endCursor;
      this.more = page.hasNextPage;
    } catch (e) {
      if (this.current(ticket) && !isRequestCancelled(e as Error)) { this.error = errorMessage(e as Error); }
    } finally {
      if (this.current(ticket)) { this.loading = false; }
    }
  }

  private async loadRemote(group: SearchGroup, ticket: number = this.generation): Promise<void> {
    if (this.gateway === null || !this.current(ticket)) { return; }
    group.loading = true;
    group.error = '';
    const hideSaved: boolean = this.hideSaved;
    try {
      const result: RemoteMangaPage = await sourceApi.remoteSearch(this.gateway, group.source.remoteId,
        group.query, group.page + 1, this.requests);
      if (!this.current(ticket)) { return; }
      const saved: Array<string> = result.items.filter((item: RemoteManga): boolean => item.inLibrary)
        .map((item: RemoteManga): string => item.key);
      const shown: Array<AlbumLite> = result.albums.filter((item: AlbumLite): boolean => !hideSaved || !saved.includes(item.id));
      group.items = group.items.concat(shown.filter((item: AlbumLite): boolean =>
        !group.items.some((old: AlbumLite): boolean => old.id === item.id)));
      group.page++;
      group.more = result.hasNextPage;
    } catch (e) {
      if (this.current(ticket) && !isRequestCancelled(e as Error)) { group.error = errorMessage(e as Error); }
    } finally {
      if (this.current(ticket)) { group.loading = false; this.groups = this.groups.slice(); }
    }
  }

  private editQuery(value: string): void {
    if (this.query === value) { return; }
    this.query = value;
    this.editing = value.trim() !== '';
    this.renew();
    this.loading = false;
    this.more = false;
    this.albums = [];
    this.groups = [];
    this.error = '';
    if (!this.editing) { this.submit(); }
  }

  private submit(): void { this.editing = false; this.submitted = this.query.trim(); this.reload(); }
  private scopeChanged(): void {
    const explore: boolean = this.scopeIndexes[0] === 1;
    if (this.explore !== explore) { this.explore = explore; this.submit(); }
  }
  private openSettings(): void {
    this.stack.pushPathByName(ROUTE_SOURCE_SETTINGS, { sourceId: 'suwayomi' } as MangaRouteParams);
  }
  private openAlbum(item: AlbumLite): void {
    this.stack.pushPathByName(ROUTE_ALBUM, { aid: item.id } as MangaRouteParams);
  }

  @Builder
  private CategoryChip(label: ResourceStr, id: number) {
    Button(label, { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
      .height(32).fontSize(13).fontWeight(this.categoryId === id ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.categoryId === id ? PRIMARY : TEXT_SUB)
      .backgroundColor(this.categoryId === id ? PRIMARY_SOFT : SUB_CARD)
      .padding({ left: 12, right: 12 })
      .responseRegion({ x: 0, y: -4, width: '100%', height: 40 })
      .onClick(() => { if (this.categoryId !== id) { this.categoryId = id; this.reload(); } })
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          if (this.connected) {
            Search({ value: this.query, placeholder: this.explore ? $r('app.string.remote_search_hint') : $r('app.string.library_search_hint') })
              .defaultFocus(false)
              .onChange((value: string) => this.editQuery(value))
              .onSubmit(() => this.submit())
              .margin({ left: 16, right: 16 })
            Row() {
              SegmentButton({ options: this.scopeOptions, selectedIndexes: $scopeIndexes })
            }.width('100%').padding({ left: 16, right: 16 })
            if (this.explore) {
              Row() {
                Text($r('app.string.hide_remote_saved')).fontSize(14).fontColor(TEXT_MAIN).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.hideSaved })
                  .onChange((on: boolean) => { this.hideSaved = on; this.reload(); })
              }.padding({ left: 16, right: 16 }).width('100%')
            } else {
              Row({ space: 8 }) {
                Scroll() {
                  Row({ space: 8 }) {
                    this.CategoryChip($r('app.string.all_categories'), -1)
                    ForEach(this.categories, (category: RemoteCategory) => {
                      this.CategoryChip(category.id === 0 && category.name === 'Default' ?
                        $r('app.string.default_category') : category.name, category.id)
                    }, (category: RemoteCategory): string => `${category.id}`)
                  }.height(40)
                }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).layoutWeight(1)
                Divider().vertical(true).height(18).strokeWidth('1px').color(DIVIDER)
                Select([{ value: $r('app.string.sort_added') }, { value: $r('app.string.sort_title') }])
                  .selected(this.sort === 'added' ? 0 : 1)
                  .value(this.sort === 'added' ? $r('app.string.sort_added') : $r('app.string.sort_title'))
                  .font({ size: 14, weight: FontWeight.Regular }).fontColor(TEXT_SUB)
                  .systemMaterial(EMPTY_MATERIAL).menuSystemMaterial(EMPTY_MATERIAL)
                  .backgroundColor(Color.Transparent)
                  .onSelect((index: number) => { this.sort = index === 0 ? 'added' : 'title'; this.reload(); })
              }.height(40).padding({ left: 16, right: 16 }).width('100%')
            }
          }
          Column({ space: 16 }) {
            if (this.error !== '') {
              EmptyView({ message: this.error, retryText: $r('app.string.retry_action'), quiet: true, onRetry: (): void => {
                if (this.gateway === null || this.categories.length === 0) { this.initialize(); }
                else if (this.explore) { this.reload(); } else { this.loadLibrary(); }
              } })
            }
            if (this.loading && this.albums.length === 0 && this.groups.length === 0) {
              SkeletonGrid({ columns: 3, rows: 3 })
            } else if (!this.connected && !this.loading && this.error === '') {
              EmptyView({ message: $r('app.string.remote_disconnected'), retryText: $r('app.string.connection_settings'),
                onRetry: (): void => this.openSettings(), quiet: true })
            } else if (this.editing) {
              EmptyView({ message: $r('app.string.remote_search_submit'), showRetry: false, quiet: true })
            } else if (this.explore) {
              if (this.submitted === '') {
                EmptyView({ message: $r('app.string.remote_query_prompt'), showRetry: false, quiet: true })
              } else {
                ForEach(this.groups, (group: SearchGroup) => {
                  SearchGroupResults({ group: group, summary: false,
                    onOpen: (item: AlbumLite): void => this.openAlbum(item),
                    onRetry: (): void => { this.loadRemote(group); } })
                  if (group.more && !group.loading && group.error === '') {
                    Button($r('app.string.load_more_action'), { buttonStyle: ButtonStyleMode.NORMAL })
                      .onClick(() => { this.loadRemote(group); })
                  }
                }, (group: SearchGroup): string => group.source.id)
                if (!this.loading && this.groups.length === 0 && this.error === '') {
                  EmptyView({ message: $r('app.string.remote_sources_empty'), showRetry: false, quiet: true })
                }
              }
            } else {
              ComicGrid({ items: this.albums, onOpen: (item: AlbumLite): void => this.openAlbum(item) })
              if (!this.loading && this.albums.length === 0 && this.error === '') {
                EmptyView({ message: this.submitted === '' ? $r('app.string.remote_library_empty') : $r('app.string.no_search_results'),
                  showRetry: false, quiet: true })
              }
              if (this.more && !this.loading && this.error === '') {
                Button($r('app.string.load_more_action'), { buttonStyle: ButtonStyleMode.NORMAL }).onClick(() => { this.loadLibrary(); })
              }
            }
            if (this.loading && (this.albums.length > 0 || this.groups.length > 0)) { LoadingProgress().width(32).height(32) }
          }.width('100%').padding({ left: 16, right: 16, bottom: 24 + this.bottomInset })
        }.width('100%')
      }
      .width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Off).clip(false)
      .onReachEnd(() => { if (!this.explore && this.more && !this.loading && this.error === '') { this.loadLibrary(); } })
    }
    .titleBar({ content: { title: { mainTitle: $r('app.string.suwayomi_library_title') },
      menu: { value: [{ content: { icon: $r('sys.symbol.gearshape'), label: $r('app.string.connection_settings'), action: (): void => this.openSettings() } }] } },
      style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavDestinationTitleMode.MINI).bindToScrollable([this.scroller]).backgroundColor(BG)
    .onReady((context: NavDestinationContext) => {
      const params: Record<string, Object> | null = asRecord(context.pathInfo.param as Object);
      this.query = params === null ? '' : asString(params['query']);
      this.submitted = this.query;
      this.ready = true;
      this.active = true;
      this.initialize();
    })
    .onShown(() => { if (this.ready && !this.active) { this.active = true; this.initialize(); } })
    .onHidden(() => this.hide())
  }
}
