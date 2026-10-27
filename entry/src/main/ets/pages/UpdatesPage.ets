import { HdsNavigation, HdsNavigationTitleMode, TitleSize } from '@kit.UIDesignKit';
import { HDS_TITLE_STYLE } from '../common/ImmersiveMaterials';
import promptAction from '@ohos.promptAction';
import { library, LibraryWork } from '../data/Library';
import { MangaRouteParams, ROUTE_ALBUM, ROUTE_READER, ROUTE_DOWNLOADS } from '../common/Route';
import { sourceApi } from '../data/SourceApi';
import { readProgressStore, historyStore } from '../data/Stores';
import { ReadingProgress, HistoryItem, Album, errorMessage } from '../models/Models';
import { SourceCover } from '../common/SourceCover';
import { BG, SUB_CARD, TEXT_MAIN, TEXT_SUB, PRIMARY, PRIMARY_SOFT, DANGER, DIVIDER, TAB_BAR_HEIGHT } from '../common/Theme';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

interface UpdatesSegmentOptions {
  label: string;
  count: number;
  index: number;
}

@Component
export struct UpdatesPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 0;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  @StorageProp('currentBreakpoint') breakpoint: string = 'sm';
  @StorageProp('mainTabIndex') @Watch('tabChanged') tab: number = 0;
  @StorageProp('bookshelfDataVersion') @Watch('load') version: number = 0;

  @State works: Array<LibraryWork> = [];
  @State recent: Array<ReadingProgress> = [];
  @State history: Array<HistoryItem> = [];
  @State errors: Array<string> = [];
  @State busy: boolean = false;
  @State section: number = 0;

  private scroller: Scroller = new Scroller();
  private generation: number = 0;
  private loadGeneration: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    this.generation++;
    this.loadGeneration++;
  }

  private tabChanged(): void {
    if (this.tab === 1) {
      this.refresh();
    } else {
      this.generation++;
      this.busy = false;
    }
  }

  private async load(): Promise<void> {
    const ticket: number = ++this.loadGeneration;
    try {
      const works: Array<LibraryWork> = await library.list();
      const recent: Array<ReadingProgress> = await readProgressStore.list();
      const history: Array<HistoryItem> = (await historyStore.getList()).filter((h: HistoryItem): boolean =>
        recent.some((p: ReadingProgress): boolean => p.aid === h.id && p.chapterId !== '' && p.totalPages > 0 && p.page >= 0 && p.page < p.totalPages));
      if (ticket !== this.loadGeneration) { return; }
      this.works = works; this.recent = recent; this.history = history;
    } catch (e) {
      if (ticket === this.loadGeneration) { this.errors = [errorMessage(e as Error)]; }
    }
  }

  private async refresh(): Promise<void> {
    if (this.busy) {
      return;
    }
    const ticket: number = ++this.generation;
    this.busy = true;
    this.errors = [];
    try {
      const works: Array<LibraryWork> = await library.list();
      let cursor: number = 0;
      const worker = async (): Promise<void> => {
        while (cursor < works.length && ticket === this.generation) {
          const work: LibraryWork = works[cursor++];
          try {
            const album: Album = await sourceApi.album(work.activeKey, true);
            if (ticket !== this.generation) {
              return;
            }
            await library.updateSnapshot(album);
          } catch (e) {
            if (ticket === this.generation) {
              this.errors = this.errors.concat([`${work.title}：${errorMessage(e as Error)}`]);
            }
          }
        }
      };
      await Promise.all([worker(), worker(), worker()]);
      if (ticket === this.generation) {
        await this.load();
      }
    } catch (e) {
      if (ticket === this.generation) {
        this.errors = [errorMessage(e as Error)];
      }
    } finally {
      if (ticket === this.generation) {
        this.busy = false;
      }
    }
  }

  private updatedWorks(): Array<LibraryWork> {
    return this.works.filter((w: LibraryWork) => w.newChapters > 0);
  }

  private clearHistory(): void {
    this.getUIContext().showAlertDialog({
      title: '清空阅读历史', message: '确定清空全部阅读历史？续读进度将保留。',
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: { value: '清空', fontColor: DANGER, action: (): void => {
        historyStore.clear().then((): void => { this.loadGeneration++; this.history = []; }).catch((e: Error): void => { this.errors = [errorMessage(e)]; });
      } }
    });
  }

  private historySubtitle(item: HistoryItem): string {
    const progress: ReadingProgress | undefined = this.recent.find((p: ReadingProgress): boolean => p.aid === item.id);
    return progress === undefined ? '' : `第 ${progress.page + 1} / ${progress.totalPages} 页`;
  }

  @Builder
  private SegmentPill($$: UpdatesSegmentOptions) {
    Button({ type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL }) {
      Row({ space: 6 }) {
        Text($$.label).fontSize(13).fontWeight(this.section === $$.index ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.section === $$.index ? PRIMARY : TEXT_SUB)
        if ($$.count > 0) {
          Text(`${$$.count}`).fontSize(10).fontWeight(FontWeight.Bold).fontColor(this.section === $$.index ? PRIMARY : TEXT_SUB)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(8)
            .backgroundColor(this.section === $$.index ? PRIMARY_SOFT : SUB_CARD)
        }
      }.justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1).height(36)
    .backgroundColor(this.section === $$.index ? BG : Color.Transparent)
    .onClick(() => { this.section = $$.index; })
  }

  @Builder
  private Entry(title: string, cover: string, subtitle: string, key: string, reading: boolean) {
    Row({ space: 14 }) {
      Row({ space: 14 }) {
      Column() { SourceCover({ url: cover, sourceKey: key, radius: 10 }) }.width(56).aspectRatio(0.75)
      Column({ space: 6 }) {
        Text(title).fontColor(TEXT_MAIN).fontSize(15).fontWeight(FontWeight.Bold)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(subtitle).fontColor(TEXT_SUB).fontSize(12).maxLines(1).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1)
      .onClick(() => this.stack.pushPathByName(ROUTE_ALBUM, { aid: key } as MangaRouteParams))
      if (reading) {
        Button('继续阅读', { buttonStyle: ButtonStyleMode.NORMAL }).fontSize(13).fontColor(PRIMARY).backgroundColor(PRIMARY_SOFT)
          .onClick((): void => {
            this.stack.pushPathByName(ROUTE_READER, { aid: key } as MangaRouteParams);
          })
      }
    }.padding({ top: 12, bottom: 12 }).width('100%')
  }

  build() {
    HdsNavigation() {
      Column() {
        Row({ space: 4 }) {
          this.SegmentPill({ label: '更新', count: this.updatedWorks().length, index: 0 })
          this.SegmentPill({ label: '阅读历史', count: this.history.length, index: 1 })
        }.padding(3).borderRadius(21).backgroundColor(SUB_CARD)
        .border({ width: 0.5, color: DIVIDER }).margin({ left: 16, right: 16, bottom: 12 })
        Scroll(this.scroller) {
          Column({ space: 8 }) {
            if (this.busy) { Text('正在检查更新').fontSize(13).fontColor(TEXT_SUB) }
            ForEach(this.errors, (error: string) => { Text(error).fontSize(13).fontColor(DANGER).width('100%') }, (error: string) => error)
            if (this.section === 0) {
              ForEach(this.updatedWorks(), (work: LibraryWork) => {
                this.Entry(work.title, work.cover, `发现 ${work.newChapters} 个新章节`, work.activeKey, false)
              }, (work: LibraryWork) => work.id)
              if (this.updatedWorks().length === 0) { Text('暂无新章节').fontSize(14).fontColor(TEXT_SUB).padding({ top: 36 }).width('100%') }
            } else {
              ForEach(this.history, (item: HistoryItem) => {
                this.Entry(item.title, item.coverUrl, this.historySubtitle(item), item.id, true)
              }, (item: HistoryItem) => item.id)
              if (this.history.length === 0) { Text('暂无阅读历史').fontSize(14).fontColor(TEXT_SUB).padding({ top: 36 }).width('100%') }
            }
          }.padding({ left: 16, right: 16, bottom: (this.breakpoint === 'lg' ? 28 : TAB_BAR_HEIGHT + 28) + this.bottomInset })
          .width('100%').alignItems(HorizontalAlign.Start)
        }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Off).clip(false)
      }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
    }
    .titleBar({ content: { title: { mainTitle: '动态', mainTitleSize: TitleSize.TITLE_ML }, menu: { value: [
      { content: { icon: $r('sys.symbol.arrow_clockwise'), label: '检查更新', action: (): void => { this.refresh(); } } },
      { content: { icon: $r('sys.symbol.arrow_down_circle'), label: '下载', action: (): void => { this.stack.pushPathByName(ROUTE_DOWNLOADS, {} as MangaRouteParams); } } },
      { content: { icon: $r('sys.symbol.trash'), label: '清空阅读历史', action: (): void => this.clearHistory() } }
    ] } }, style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavigationTitleMode.MINI)
    .mode(NavigationMode.Stack).hideBackButton(true).bindToScrollable([this.scroller]).width('100%').height('100%').backgroundColor(BG)
  }
}
