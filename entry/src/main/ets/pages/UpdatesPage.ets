import { EmptyView } from '../common/Components';
import { BottomBuilderShowType, HdsNavigation, HdsNavigationTitleMode, TitleSize } from '@kit.UIDesignKit';
import { SegmentButton, SegmentButtonOptions, SegmentButtonTextItem, ItemRestriction } from '@kit.ArkUI';
import { HDS_TITLE_STYLE } from '../common/ImmersiveMaterials';
import promptAction from '@ohos.promptAction';
import { library, LibraryWork } from '../data/Library';
import { MangaRouteParams, ROUTE_ALBUM, ROUTE_READER, ROUTE_DOWNLOADS } from '../common/Route';
import { sourceApi } from '../data/SourceApi';
import { readProgressStore, historyStore } from '../data/Stores';
import { ReadingProgress, HistoryItem, Album, errorMessage } from '../models/Models';
import { SourceCover } from '../common/SourceCover';
import { BG, TEXT_MAIN, TEXT_SUB, DANGER, DIVIDER, TAB_BAR_HEIGHT } from '../common/Theme';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

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
  @State @Watch('segmentChanged') segmentIndexes: number[] = [0];
  @State segmentOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [{ text: '更新' }, { text: '阅读历史' }] as ItemRestriction<SegmentButtonTextItem>
  });

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

  private segmentChanged(): void {
    this.section = this.segmentIndexes.length > 0 ? this.segmentIndexes[0] : 0;
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

  /** 分段固定在标题栏下方，不随滚动隐藏。 */
  @Builder
  private SectionHeader() {
    Column() {
      SegmentButton({ options: this.segmentOptions, selectedIndexes: $segmentIndexes })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 8 })
  }

  /** 列表行：标题 16 两行、副文字 12；整行点按进入详情，历史行尾保留文字按钮「继续阅读」。 */
  @Builder
  private Entry(title: string, cover: string, subtitle: string, key: string, reading: boolean) {
    Row({ space: 12 }) {
      Column() { SourceCover({ url: cover, sourceKey: key, radius: 8 }) }.width(56).aspectRatio(0.75)
      Column({ space: 4 }) {
        Text(title).fontColor(TEXT_MAIN).fontSize(16)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        if (subtitle !== '') {
          Text(subtitle).fontColor(TEXT_SUB).fontSize(12).maxLines(1).width('100%')
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (reading) {
        Button('继续阅读', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .onClick((): void => {
            this.stack.pushPathByName(ROUTE_READER, { aid: key } as MangaRouteParams);
          })
      }
    }
    .padding({ top: 12, bottom: 12 }).width('100%')
    .onClick(() => this.stack.pushPathByName(ROUTE_ALBUM, { aid: key } as MangaRouteParams))
  }

  @Builder
  private RowDivider() {
    // 分隔线从封面右侧起：封面 56 + 间距 12。
    Divider().strokeWidth('1px').color(DIVIDER).margin({ left: 68 })
  }

  build() {
    HdsNavigation() {
      Column() {
        Scroll(this.scroller) {
          Column() {
            if (this.busy) { Text('正在检查更新').fontSize(14).fontColor(TEXT_SUB).padding({ top: 8, bottom: 8 }) }
            ForEach(this.errors, (error: string) => { Text(error).fontSize(14).fontColor(DANGER).width('100%') }, (error: string) => error)
            if (this.section === 0) {
              ForEach(this.updatedWorks(), (work: LibraryWork, index: number) => {
                if (index > 0) { this.RowDivider() }
                this.Entry(work.title, work.cover, `发现 ${work.newChapters} 个新章节`, work.activeKey, false)
              }, (work: LibraryWork) => work.id)
              if (this.updatedWorks().length === 0) { EmptyView({ quiet: true, message: '暂无新章节', showRetry: false }) }
            } else {
              ForEach(this.history, (item: HistoryItem, index: number) => {
                if (index > 0) { this.RowDivider() }
                this.Entry(item.title, item.coverUrl, this.historySubtitle(item), item.id, true)
              }, (item: HistoryItem) => item.id)
              if (this.history.length === 0) { EmptyView({ quiet: true, message: '暂无阅读历史', showRetry: false }) }
            }
          }.padding({ left: 16, right: 16, bottom: (this.breakpoint === 'lg' ? 28 : TAB_BAR_HEIGHT + 28) + this.bottomInset })
          .width('100%').alignItems(HorizontalAlign.Start)
        }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Off).clip(false)
      }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
    }
    .titleBar({ content: { title: { mainTitle: '动态', mainTitleSize: TitleSize.TITLE_ML },
      bottomBuilder: { builder: (): void => this.SectionHeader(), height: 52, showType: BottomBuilderShowType.DIRECTLY_SHOW },
      // 标题栏只露出「检查更新」，其余收进 HDS 自动生成的「更多」菜单。
      menu: { maxCount: 2, value: [
      { content: { icon: $r('sys.symbol.arrow_clockwise'), label: '检查更新', isEnabled: !this.busy, action: (): void => { this.refresh(); } } },
      { content: { icon: $r('sys.symbol.arrow_down_circle'), label: '下载', action: (): void => { this.stack.pushPathByName(ROUTE_DOWNLOADS, {} as MangaRouteParams); } } },
      { content: { icon: $r('sys.symbol.trash'), label: '清空阅读历史', isEnabled: this.section === 1 && this.history.length > 0,
        action: (): void => this.clearHistory() } }
    ] } }, style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavigationTitleMode.MINI)
    .mode(NavigationMode.Stack).hideBackButton(true).bindToScrollable([this.scroller]).width('100%').height('100%').backgroundColor(BG)
  }
}
