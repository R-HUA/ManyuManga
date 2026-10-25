import { sourceStore, SourceEntry } from '../data/Sources';
import { MangaRouteParams } from '../common/Route';
import { sourceApi } from '../data/SourceApi';
import { library } from '../data/Library';
import { highConfidence } from '../data/Matching';
import { Album, AlbumLite, SearchResult, asRecord, asString, errorMessage } from '../models/Models';
import { SourceCover } from '../common/SourceCover';
import { BG, CARD, PRIMARY, TEXT_MAIN, TEXT_SUB } from '../common/Theme';
import { ROUTE_ALBUM } from '../common/Route';

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
  @State query: string = '';
  @State groups: Array<SearchGroup> = [];
  @State error: string = '';
  @State matching: boolean = false;
  private ticket: number = 0;
  private onlySource: string = '';
  private matchAid: string = '';
  private origin: Album | null = null;
  private active: boolean = true;
  aboutToDisappear(): void { this.active = false; this.ticket++; }
  private sourcesChanged(): void { this.ticket++; if (this.active) { this.search(); } }
  private async search(): Promise<void> {
    const ticket: number = ++this.ticket;
    const query: string = this.query.trim();
    try {
      const sources: Array<SourceEntry> = (await sourceStore.list()).filter((s: SourceEntry) => s.enabled &&
        (this.onlySource === '' || s.id === this.onlySource));
      if (ticket !== this.ticket) { return; }
      this.groups = sources.map((source: SourceEntry): SearchGroup => { const group: SearchGroup = new SearchGroup(); group.source = source; return group; });
      this.error = sources.length === 0 ? '没有已启用的书源' : '';
      let cursor: number = 0;
      const work = async (): Promise<void> => {
        while (ticket === this.ticket && cursor < sources.length) {
          const index: number = cursor++;
          await this.loadGroup(index, 1, ticket, query);
        }
      };
      await Promise.all([work(), work(), work()]);
      if (ticket === this.ticket && this.origin !== null) { await this.associateConfident(ticket); }
    } catch (e) { if (ticket === this.ticket) { this.error = errorMessage(e as Error); } }
  }
  private async loadGroup(index: number, page: number, ticket: number = this.ticket, query: string = this.query.trim()): Promise<void> {
    const group: SearchGroup = this.groups[index];
    group.loading = true; group.error = ''; this.groups = this.groups.slice();
    try {
      const result: SearchResult = await sourceApi.searchSource(group.source, query, page);
      if (ticket !== this.ticket || !this.active) { return; }
      group.items = page === 1 ? result.list : group.items.concat(result.list.filter((a: AlbumLite) => !group.items.some((b: AlbumLite) => a.id === b.id)));
      group.page = page;
      group.more = group.source.kind !== 'local' && result.list.length > 0 &&
        (result.hasNext !== null ? result.hasNext : result.total === 0 || group.items.length < result.total);
    } catch (e) { if (ticket === this.ticket) { group.error = errorMessage(e as Error); } }
    finally { if (ticket === this.ticket) { group.loading = false; this.groups = this.groups.slice(); } }
  }
  private async associateConfident(ticket: number): Promise<void> {
    if (await library.workFor(this.matchAid) === null) { return; }
    this.matching = true;
    try {
      for (const group of this.groups) {
        if (this.origin === null || ticket !== this.ticket) { return; }
        const possible: Array<AlbumLite> = group.items.filter((a: AlbumLite) => a.title.trim() === this.origin!.name.trim());
        const matches: Array<Album> = [];
        for (const candidate of possible.slice(0, 5)) {
          const album: Album = await sourceApi.album(candidate.id);
          if (ticket !== this.ticket) { return; }
          if (album.id !== this.origin.id && highConfidence(this.origin, album)) { matches.push(album); }
        }
        if (matches.length === 1) { await library.associate(this.matchAid, matches[0]); }
      }
    } catch (e) { if (ticket === this.ticket) { this.error = errorMessage(e as Error); } }
    finally { if (ticket === this.ticket) { this.matching = false; } }
  }
  private async choose(item: AlbumLite): Promise<void> {
    if (this.matchAid === '') { this.stack.pushPathByName(ROUTE_ALBUM, { aid: item.id } as MangaRouteParams); return; }
    try {
      const album: Album = await sourceApi.album(item.id);
      AlertDialog.show({ title: '关联书源', message: `将《${album.name}》作为当前作品的另一个来源？`,
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: { value: '关联', action: () => {
          (async (): Promise<void> => {
            if (await library.workFor(this.matchAid) === null && this.origin !== null) { await library.add(this.origin); }
            await library.associate(this.matchAid, album); this.stack.pop();
          })().catch((e: Error) => { this.error = errorMessage(e); });
        } } });
    } catch (e) { this.error = errorMessage(e as Error); }
  }
  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Search({ value: this.query, placeholder: this.matchAid === '' ? '搜索全部书源' : '查找同一作品的其他书源' })
          .onChange((text: string) => { this.query = text; this.ticket++; })
          .onSubmit(() => { this.search(); }).searchButton('搜索').margin({ left: 16, right: 16 })
        if (this.error !== '') { Text(this.error).fontColor(TEXT_SUB).padding(16) }
        if (this.matching) { Text('正在核对作品信息…').fontColor(PRIMARY).fontSize(13) }
        Scroll() {
          Column({ space: 24 }) {
            ForEach(this.groups, (group: SearchGroup, index: number) => {
              Column({ space: 12 }) {
                Row() {
                  Text(group.source.name).fontSize(18).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN).layoutWeight(1)
                  if (group.loading) { LoadingProgress().width(24).height(24) }
                }.width('100%')
                if (group.error !== '') {
                  Text(group.error).fontColor(TEXT_SUB)
                  Button('重试此书源').onClick(() => { this.loadGroup(index, Math.max(1, group.page)); })
                } else if (!group.loading && group.items.length === 0) { Text('没有找到相关漫画').fontColor(TEXT_SUB).fontSize(13) }
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(group.items, (item: AlbumLite) => {
                    Column({ space: 8 }) {
                      SourceCover({ url: item.coverUrl })
                      Text(item.title).fontSize(13).fontColor(TEXT_MAIN).maxLines(2).width('100%')
                      if (item.author !== '') { Text(item.author).fontSize(11).fontColor(TEXT_SUB).maxLines(1).width('100%') }
                    }.width('31%').margin({ right: '2%', bottom: 16 }).onClick(() => { this.choose(item); })
                  }, (item: AlbumLite) => item.id)
                }.width('100%')
                if (group.more && !group.loading) { Button('加载更多').onClick(() => { this.loadGroup(index, group.page + 1); }) }
              }.padding(16).backgroundColor(CARD).borderRadius(20).width('100%').alignItems(HorizontalAlign.Start)
            }, (group: SearchGroup) => group.source.id)
          }.padding({ left: 16, right: 16, bottom: 32 }).width('100%')
        }.layoutWeight(1).width('100%')
      }.width('100%').height('100%').backgroundColor(BG)
    }.title(this.matchAid === '' ? '搜索' : '关联书源').onReady((context: NavDestinationContext) => {
      const params: Record<string, Object> | null = asRecord(context.pathInfo.param as Object);
      this.query = params === null ? '' : asString(params['query']);
      this.onlySource = params === null ? '' : asString(params['sourceId']);
      this.matchAid = params === null ? '' : asString(params['matchAid']);
      this.active = true;
      if (this.matchAid !== '') {
        sourceApi.album(this.matchAid).then((album: Album) => { this.origin = album; this.query = album.name; this.search(); })
          .catch((e: Error) => { this.error = errorMessage(e); });
      } else { this.search(); }
    }).onHidden(() => { this.active = false; this.ticket++; }).onShown(() => { this.active = true; })
  }
}
