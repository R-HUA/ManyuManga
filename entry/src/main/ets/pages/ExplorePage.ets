import { ComicGrid } from '../common/ComicGrid';
import { MangaRouteParams, ROUTE_ALBUM, ROUTE_SOURCE_BROWSE } from '../common/Route';
import { BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';
import { PRIMARY, TEXT_MAIN, TEXT_SUB, DANGER, TAB_BAR_HEIGHT } from '../common/Theme';
import { EMPTY_MATERIAL } from '../common/ImmersiveMaterials';
import { AlbumLite, errorMessage } from '../models/Models';
import { sourceApi } from '../data/SourceApi';

type HomeSection = 'ranking' | 'random' | 'latest';

interface HomeSectionView {
  title: string;
  section: HomeSection;
  items: Array<AlbumLite>;
  loading: boolean;
  error: string;
}

@Component
export struct ExplorePage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @Prop embeddedInShell: boolean = false;
  @Prop sourceIdValue: string = '';
  scroller: Scroller = new Scroller();
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  @StorageProp('blockTagsVersion') @Watch('refresh') blockVersion: number = 0;
  @State currentRank: string = 'mv_t';
  @State rankItems: Array<AlbumLite> = [];
  @State randomItems: Array<AlbumLite> = [];
  @State latestItems: Array<AlbumLite> = [];
  @State rankLoading: boolean = false;
  @State randomLoading: boolean = false;
  @State latestLoading: boolean = false;
  @State rankError: string = '';
  @State randomError: string = '';
  @State latestError: string = '';
  @State refreshing: boolean = false;
  private generation: number = 0;
  private rankGeneration: number = 0;
  private readonly orders: Array<string> = ['mv_t', 'mv_w', 'mv_m', 'mv'];
  private readonly labels: Array<string> = ['日榜', '周榜', '月榜', '总榜'];

  aboutToAppear(): void { this.refresh(); }
  aboutToDisappear(): void { this.generation++; this.rankGeneration++; }

  private async refresh(): Promise<void> {
    const ticket: number = ++this.generation;
    await Promise.all([this.fetchSection('ranking'), this.fetchSection('random'), this.fetchSection('latest')]);
    if (ticket !== this.generation) { return; }
    this.refreshing = false;
  }

  async fetchSection(section: HomeSection): Promise<void> {
    const ticket: number = this.generation;
    const rankTicket: number = section === 'ranking' ? ++this.rankGeneration : this.rankGeneration;
    if (section === 'ranking') { this.rankLoading = true; this.rankError = ''; }
    else if (section === 'random') { this.randomLoading = true; this.randomError = ''; }
    else { this.latestLoading = true; this.latestError = ''; }
    try {
      const items: Array<AlbumLite> = section === 'ranking' ? await sourceApi.ranking(this.sourceIdValue, '', this.currentRank, 1) : section === 'random' ? await sourceApi.random(this.sourceIdValue) : await sourceApi.latest(this.sourceIdValue, 1);
      if (ticket !== this.generation || (section === 'ranking' && rankTicket !== this.rankGeneration)) { return; }
      if (section === 'ranking') { this.rankItems = items; }
      else if (section === 'random') { this.randomItems = items; }
      else { this.latestItems = items; }
    } catch (e) {
      if (ticket !== this.generation || (section === 'ranking' && rankTicket !== this.rankGeneration)) { return; }
      const message: string = errorMessage(e as Error);
      if (section === 'ranking') { this.rankError = message; }
      else if (section === 'random') { this.randomError = message; }
      else { this.latestError = message; }
    } finally {
      if (ticket === this.generation) {
        if (section === 'ranking' && rankTicket === this.rankGeneration) { this.rankLoading = false; }
        else if (section === 'random') { this.randomLoading = false; }
        else if (section === 'latest') { this.latestLoading = false; }
      }
    }
  }

  private browse(mode: string): void {
    this.navPathStack.pushPathByName(ROUTE_SOURCE_BROWSE, { sourceId: this.sourceIdValue, browseMode: mode, order: this.currentRank } as MangaRouteParams);
  }

  @Builder
  private Section($$: HomeSectionView) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text($$.title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
        if ($$.section === 'ranking') {
          Select(this.labels.map((label: string): SelectOption => { return { value: label }; }))
            .selected(this.orders.indexOf(this.currentRank))
            .value(this.labels[this.orders.indexOf(this.currentRank)])
            .backgroundColor(Color.Transparent)
            .borderWidth(0)
            .borderColor(Color.Transparent)
            .systemMaterial(EMPTY_MATERIAL)
            .onSelect((index: number): void => {
              this.currentRank = this.orders[index];
              this.fetchSection('ranking');
            })
        }
        Blank()
        Button($$.section === 'random' ? '换一批' : '查看全部', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .fontSize(13)
          .fontColor(PRIMARY)
          .enabled(!$$.loading)
          .onClick(() => {
            if ($$.section === 'random') {
              this.fetchSection($$.section);
            } else {
              this.browse($$.section);
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if ($$.error !== '') {
        Text($$.error).fontSize(13).fontColor(DANGER).width('100%')
        Button('重试', { buttonStyle: ButtonStyleMode.NORMAL }).onClick(() => this.fetchSection($$.section))
      }
      if ($$.loading && $$.items.length === 0) { LoadingProgress().width(28).height(28) }
      if (!$$.loading && $$.error === '' && $$.items.length === 0) { Text('暂无内容').fontSize(13).fontColor(TEXT_SUB).width('100%') }
      ComicGrid({ items: $$.items, rows: 2, onOpen: (item: AlbumLite): void => {
        this.navPathStack.pushPathByName(ROUTE_ALBUM, { aid: item.id } as MangaRouteParams);
      } })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Refresh({ refreshing: $$this.refreshing }) {
      Scroll(this.scroller) {
        Column({ space: 28 }) {
          this.Section({ title: '热门', section: 'ranking', items: this.rankItems, loading: this.rankLoading, error: this.rankError })
          this.Section({ title: '随机推荐', section: 'random', items: this.randomItems, loading: this.randomLoading, error: this.randomError })
          this.Section({ title: '最新上架', section: 'latest', items: this.latestItems, loading: this.latestLoading, error: this.latestError })
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 12,
          bottom: (this.embeddedInShell ? TAB_BAR_HEIGHT : 0) + 28 + this.bottomInset
        })
      }.width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Off).clip(false)
    }.width('100%').height('100%').onRefreshing(() => { this.refresh(); })
  }
}
