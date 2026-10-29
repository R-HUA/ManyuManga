import { sourceStore, SourceEntry, SourceKind } from '../data/Sources';
import { capabilitiesFor, SourceSearchOptions } from '../data/source/SourceContracts';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { IMMERSIVE_CONTROL_MATERIAL, IMMERSIVE_SHEET_MATERIAL } from '../common/ImmersiveMaterials';
import { SearchGroup, SearchGroupResults } from './search/SearchGroupResults';
import { SearchFilterSheet } from './search/SearchFilterSheet';
import { SearchHistory } from './search/SearchHistory';
import { MangaRouteParams, ROUTE_ALBUM, ROUTE_SEARCH, ROUTE_SUWAYOMI_LIBRARY, SearchScope, SearchSelection, searchSelectionFromObject } from '../common/Route';
import { RemoteMangaPage } from '../data/SuwayomiLibrary';
import { RequestAbortGroup } from '../util/RequestAbort';
import { sourceApi } from '../data/SourceApi';
import { library, LibraryWork } from '../data/Library';
import { searchLibraryWorks } from '../data/SearchQuery';
import { LibrarySearchResults } from './search/LibrarySearchResults';
import { highConfidence } from '../data/Matching';
import { Album, AlbumLite, SearchResult, asRecord, asString, errorMessage } from '../models/Models';
import { BG, PRIMARY, PRIMARY_SOFT, DANGER, TEXT_SUB } from '../common/Theme';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';
import { SearchSuggestField } from './search/SearchSuggestField';
import { searchHistoryStore } from '../data/stores/FilterStores';

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
  @State scope: SearchScope = 'all';
  @State sourceName: string = '当前图源';
  @State libraryWorks: Array<LibraryWork> = [];
  @State libraryLoading: boolean = false;
  @State selection: SearchSelection | null = null;
  @State private searchKind: SourceKind | null = null;
  @State private searchOptions: SourceSearchOptions = new SourceSearchOptions();
  @State private filterSheet: boolean = false;
  /** 单源搜索里由“应用筛选”发起的空关键词检索。 */
  @State private filterSearch: boolean = false;

  @State private submitted: string = '';
  private ticket: number = 0;
  private onlySource: string = '';
  private matchAid: string = '';
  private origin: Album | null = null;
  private active: boolean = true;
  private pending: boolean = false;
  private resumeSearch: boolean = false;
  private remoteRequests: RequestAbortGroup = new RequestAbortGroup();

  aboutToDisappear(): void {
    this.hideSearch();
  }

  private hideSearch(): void {
    this.remoteRequests.abortAll();
    this.resumeSearch = this.pending || this.groups.some((group: SearchGroup) => group.loading);
    this.active = false;
    this.ticket++;
  }

  private showSearch(): void {
    this.active = true;
    if (this.resumeSearch) {
      this.resumeSearch = false;
      this.search();
    }
  }

  private hasActiveFilter(): boolean {
    if (this.searchKind === 'jm') {
      return this.searchOptions.jm.order !== 'mr' || this.searchOptions.jm.time !== 'a';
    }
    if (this.searchKind === 'eh') {
      return this.searchOptions.eh.hasActiveFilter();
    }
    return false;
  }

  private editQuery(): void {
    this.remoteRequests.abortAll();
    this.submitted = '';
    this.filterSearch = false;
    this.resumeSearch = false;
    this.matching = false;
    this.selection = null;
    this.ticket++;
    this.pending = false;
    this.groups = [];
    this.libraryWorks = [];
    this.libraryLoading = false;
    this.error = '';
  }

  private sourcesChanged(): void {
    this.ticket++;
    if (!this.hasSubmission()) { return; }
    if (this.active) {
      this.search();
    } else {
      this.resumeSearch = true;
    }
  }

  private hasSubmission(): boolean {
    return this.submitted !== '' || this.filterSearch;
  }

  private filterAvailable(): boolean {
    return this.scope === 'source' && (this.searchKind === 'jm' || this.searchKind === 'eh');
  }

  /** allowEmpty：单源筛选面板点“应用筛选”时，即使关键词为空也按筛选条件发起一次检索。 */
  private async search(allowEmpty: boolean = false): Promise<void> {
    const emptyAllowed: boolean = allowEmpty && this.scope === 'source';
    if (this.query.trim() === '' && !emptyAllowed && !(this.filterSearch && this.scope === 'source')) {
      this.editQuery(); return;
    }
    const ticket: number = ++this.ticket;
    this.remoteRequests.abortAll();
    this.remoteRequests = new RequestAbortGroup();
    const query: string = this.query.trim();
    this.submitted = query;
    this.filterSearch = query === '';
    const selection: SearchSelection | null = this.selection;
    this.pending = true;
    try {
      this.error = '';
      this.groups = [];
      if (query !== '') { await searchHistoryStore.record(query); }
      if (ticket !== this.ticket || !this.active) { return; }
      if (this.scope === 'library') {
        this.libraryLoading = true;
        this.libraryWorks = [];
        const works: Array<LibraryWork> = await library.list();
        if (ticket === this.ticket && this.active) {
          this.libraryWorks = searchLibraryWorks(works, query, selection);
          this.libraryLoading = false;
        }
        return;
      }
      const sources: Array<SourceEntry> = this.scope === 'source' ?
        [await sourceStore.get(this.onlySource)] :
        await sourceApi.searchEntries();
      if (ticket !== this.ticket) {
        return;
      }
      this.groups = sources.map((source: SourceEntry): SearchGroup => {
        const group: SearchGroup = new SearchGroup();
        group.source = source;
        group.query = selection === null || (source.kind === 'suwayomi' && source.remoteId === '') ? query : sourceApi.searchExpression(source,
          selection.term.namespace, selection.term.value, selection.field);
        group.options = this.searchOptions.copy();
        return group;
      });
      this.sourceName = this.scope === 'source' ? sources[0].name : '';
      this.searchKind = this.scope === 'source' ? sources[0].kind : null;
      this.error = sources.length === 0 ? '没有已启用的图源' : '';
      let cursor: number = 0;
      const work = async (): Promise<void> => {
        while (ticket === this.ticket && cursor < sources.length) {
          const index: number = cursor++;
          await this.loadGroup(index, 1, ticket);
        }
      };
      await Promise.all([work(), work(), work()]);
      if (ticket === this.ticket && this.origin !== null) {
        await this.associateConfident(ticket);
      }
    } catch (e) {
      if (ticket === this.ticket) {
        this.error = errorMessage(e as Error);
        this.libraryLoading = false;
      }
    } finally {
      if (ticket === this.ticket) { this.pending = false; }
    }
  }

  private async loadGroup(index: number, page: number, ticket: number = this.ticket): Promise<void> {
    const group: SearchGroup = this.groups[index];
    group.loading = true;
    group.error = '';
    this.groups = this.groups.slice();
    try {
      if (group.source.kind === 'suwayomi' && group.source.remoteId === '') {
        const remote: RemoteMangaPage = await sourceApi.remoteLibrary(group.source, -1, group.query, 'added',
          page === 1 ? '' : group.remoteCursor, this.remoteRequests);
        if (ticket !== this.ticket || !this.active) { return; }
        group.items = page === 1 ? remote.albums : group.items.concat(remote.albums.filter((item: AlbumLite): boolean =>
          !group.items.some((existing: AlbumLite): boolean => existing.id === item.id)));
        group.page = page;
        group.remoteCursor = remote.endCursor;
        group.more = remote.hasNextPage;
        return;
      }
      const result: SearchResult = await sourceApi.searchSource(group.source, group.query, page, group.options);
      if (ticket !== this.ticket || !this.active) {
        return;
      }
      group.items = page === 1
        ? result.list
        : group.items.concat(result.list.filter((a: AlbumLite) => !group.items.some((b: AlbumLite) => a.id === b.id)));
      group.page = page;
      group.more = capabilitiesFor(group.source.kind).searchPaging && result.list.length > 0 &&
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

  /** 图源内搜索必须先拿到图源元数据（名称、kind 决定的搜索能力），再发起首次搜索。 */
  async openScopedSource(): Promise<void> {
    const ticket: number = ++this.ticket;
    try {
      const source: SourceEntry = await sourceStore.get(this.onlySource);
      if (ticket !== this.ticket || !this.active) { return; }
      this.sourceName = source.name;
      this.searchKind = source.kind;
      if (this.query.trim() !== '') {
        this.search();
      }
    } catch (e) {
      if (ticket === this.ticket && this.active) { this.error = errorMessage(e as Error); }
    }
  }

  @Builder
  private SearchTitle() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([$r('sys.color.font_primary')])
      }.width(40).height(40).backgroundColor(Color.Transparent).systemMaterial(IMMERSIVE_CONTROL_MATERIAL)
      .accessibilityText('返回').onClick((): void => { this.stack.pop(); })
      SearchSuggestField({ text: this.$query, sourceId: this.onlySource, selection: this.selection,
        showSearchButton: !this.filterAvailable(),
        placeholder: this.scope === 'library' ? '搜索书架' : this.scope === 'source' ? `搜索${this.sourceName}` : '搜索全部图源',
        onEdit: (): void => this.editQuery(),
        onSubmit: (text: string, selection: SearchSelection | null): void => {
          this.query = text; this.selection = selection; this.search();
        } }).layoutWeight(1)
      if (this.filterAvailable()) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
          SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
            .fontSize(20)
            .fontColor([this.hasActiveFilter() ? PRIMARY : $r('sys.color.font_primary')])
        }
        .width(40)
        .height(40)
        .backgroundColor(this.hasActiveFilter() ? PRIMARY_SOFT : Color.Transparent)
        .systemMaterial(IMMERSIVE_CONTROL_MATERIAL)
        .accessibilityText('筛选')
        .onClick((): void => {
          this.filterSheet = true;
        })
      }
    }.width('100%').height(56).padding({ left: 16, right: 16 })
  }

  @Builder
  private FilterSheetPanel() {
    SearchFilterSheet({
      kind: this.searchKind ?? 'jm',
      options: this.searchOptions,
      onApply: (options: SourceSearchOptions): void => {
        this.searchOptions = options;
        this.filterSheet = false;
        // 应用筛选即发起一次检索，关键词为空时按纯筛选条件检索该图源。
        this.search(true);
      },
      onClose: (): void => {
        this.filterSheet = false;
      }
    })
  }

  build() {
    HdsNavDestination() {
      Navigation() {
        Column() {
          Scroll() {
            Column({ space: 20 }) {
              if (this.query.trim() === '' && !this.filterSearch) {
                SearchHistory({ onSubmit: (text: string): void => { this.query = text; this.selection = null; this.search(); } })
              }
              if (this.error !== '') { Text(this.error).fontColor(DANGER).fontSize(13).width('100%') }
              if (this.matching) { Text('正在核对关联作品').fontColor(TEXT_SUB).fontSize(13).width('100%') }
              if (this.hasSubmission()) {
                if (this.groups.length > 1) {
                  Row({ space: 8 }) {
                    Toggle({ type: ToggleType.Checkbox, isOn: this.onlyHits })
                      .onChange((value: boolean): void => { this.onlyHits = value; })
                    Text('仅看有结果').fontColor(TEXT_SUB).fontSize(13)
                  }.width('100%')
                }
                if (this.scope === 'library') { LibrarySearchResults({ works: this.libraryWorks, loading: this.libraryLoading }) }
                ForEach(this.visibleGroups(), (group: SearchGroup) => {
                  SearchGroupResults({ group: group, summary: this.scope === 'all',
                    onOpen: (item: AlbumLite): void => { this.choose(item); },
                    onViewAll: (): void => {
                      if (group.source.kind === 'suwayomi' && group.source.remoteId === '') {
                        this.stack.pushPathByName(ROUTE_SUWAYOMI_LIBRARY, { query: this.submitted } as MangaRouteParams);
                        return;
                      }
                      this.stack.pushPathByName(ROUTE_SEARCH, { sourceId: group.source.id, scope: 'source',
                        query: this.submitted, selection: this.selection === null ? undefined : this.selection } as MangaRouteParams);
                    },
                    onRetry: (): void => { this.loadGroup(this.groups.indexOf(group), Math.max(1, group.page)); } })
                }, (group: SearchGroup) => group.source.id)
              }
            }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, bottom: 32 + this.bottomInset })
          }.width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Off)
          .onReachEnd(() => {
            if (this.scope === 'source' && this.groups.length === 1 && this.groups[0].more && !this.groups[0].loading) { this.loadGroup(0, this.groups[0].page + 1); }
          })
        }.width('100%').height('100%')
      }.mode(NavigationMode.Stack).titleMode(NavigationTitleMode.Mini).hideBackButton(true)
      .title({ builder: (): void => this.SearchTitle(), height: TitleHeight.MainOnly }, { backgroundColor: Color.Transparent })
      .width('100%').height('100%').padding({ top: this.topInset })
    }.hideTitleBar(true).backgroundColor(BG)
    .bindSheet($$this.filterSheet, this.FilterSheetPanel(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      systemMaterial: IMMERSIVE_SHEET_MATERIAL
    })
    .onReady((context: NavDestinationContext) => {
      const params: Record<string, Object> | null = asRecord(context.pathInfo.param as Object);
      this.query = params === null ? '' : asString(params['query']);
      this.onlySource = params === null ? '' : asString(params['sourceId']);
      const scope: string = params === null ? '' : asString(params['scope']);
      this.scope = scope === 'library' ? 'library' : scope === 'all' ? 'all' :
        this.onlySource !== '' ? 'source' : 'all';
      if (this.scope !== 'source') { this.onlySource = ''; }
      this.selection = params === null ? null : searchSelectionFromObject(params['selection']);
      this.matchAid = params === null ? '' : asString(params['matchAid']);
      this.active = true;
      if (this.matchAid !== '') {
        this.scope = 'all';
        this.onlySource = '';
        this.selection = null;
        const ticket: number = ++this.ticket;
        sourceApi.album(this.matchAid).then((album: Album) => {
          if (ticket !== this.ticket || !this.active) { return; }
          this.origin = album;
          this.query = album.name;
          this.search();
        }).catch((e: Error) => {
          if (ticket === this.ticket && this.active) { this.error = errorMessage(e); }
        });
      } else if (this.scope === 'source') {
        this.openScopedSource();
      } else if (this.query.trim() !== '') {
        this.search();
      }
    })
    .onHidden(() => {
      this.hideSearch();
    })
    .onShown(() => {
      this.showSearch();
    })
  }
}
