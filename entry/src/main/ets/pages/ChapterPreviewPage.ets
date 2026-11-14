import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HDS_TITLE_STYLE } from '../common/ImmersiveMaterials';
import { ROUTE_READER, MangaRouteParams } from '../common/Route';
import { asRecord, asString, errorMessage } from '../models/Models';
import { sourceApi } from '../data/SourceApi';
import { isRequestCancelled, RequestAbortGroup } from '../util/RequestAbort';
import { PagePreview } from '../common/PagePreview';
import { EmptyView } from '../common/Components';
import { BG, CARD, SUB_CARD, PRIMARY, TEXT_MAIN, TEXT_SUB, DIVIDER, COVER_R, ON_OVERLAY, OVERLAY_SCRIM, PRESS_SURFACE } from '../common/Theme';
import { BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

@Component
export struct ChapterPreviewPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 16;

  @State aid: string = '';
  @State chapterId: string = '';
  @State chapterTitle: string = '';
  @State allPages: Array<string> = [];
  @State scrambleId: number = 220980;
  @State previewPage: number = 0;
  @State columns: number = 3;
  @State loading: boolean = true;
  @State error: string = '';
  @State private previewActive: boolean = true;
  private scroller: Scroller = new Scroller();
  private loadToken: number = 0;
  private loadSignal: RequestAbortGroup = new RequestAbortGroup();

  aboutToDisappear(): void {
    this.cancelLoad();
  }

  private cancelLoad(): void {
    this.loadToken++;
    this.loadSignal.abortAll();
  }

  private setColumns(columns: number): void {
    const first: number = this.previewPage * this.pageSize();
    this.columns = columns;
    this.previewPage = Math.floor(first / this.pageSize());
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  private showColumnsMenu(): void {
    this.getUIContext().showActionSheet({
      title: $r('app.string.preview_layout'),
      message: '',
      sheets: [
        { title: this.columns === 2 ? $r('app.string.preview_two_columns_selected') : $r('app.string.preview_two_columns'),
          action: (): void => this.setColumns(2) },
        { title: this.columns === 3 ? $r('app.string.preview_three_columns_selected') : $r('app.string.preview_three_columns'),
          action: (): void => this.setColumns(3) },
        { title: this.columns === 4 ? $r('app.string.preview_four_columns_selected') : $r('app.string.preview_four_columns'),
          action: (): void => this.setColumns(4) }
      ]
    });
  }

  private pageSize(): number { return this.columns * 3; }

  private pageCount(): number { return Math.max(1, Math.ceil(this.allPages.length / this.pageSize())); }

  private visiblePages(): Array<string> {
    return this.allPages.slice(this.previewPage * this.pageSize(), (this.previewPage + 1) * this.pageSize());
  }

  private changePage(delta: number): void {
    this.previewPage = Math.max(0, Math.min(this.pageCount() - 1, this.previewPage + delta));
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  private columnsTemplateStr(): string {
    const parts: Array<string> = [];
    for (let i: number = 0; i < this.columns; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  private async load(): Promise<void> {
    this.loadSignal.abortAll();
    const signal: RequestAbortGroup = new RequestAbortGroup();
    this.loadSignal = signal;
    const token: number = ++this.loadToken;
    const chapterId: string = this.chapterId;
    this.loading = true;
    this.error = '';
    try {
      const pages: Array<string> = await sourceApi.chapterImages(chapterId, signal);
      if (token !== this.loadToken || signal.aborted()) { return; }
      const scrambleId: number = await sourceApi.scrambleId(chapterId, signal);
      if (token !== this.loadToken || signal.aborted()) { return; }
      this.scrambleId = scrambleId;
      this.allPages = pages;
      this.previewPage = 0;
    } catch (e) {
      if (token === this.loadToken && !signal.aborted() && !isRequestCancelled(e as Error)) {
        this.error = errorMessage(e as Error);
      }
    } finally {
      if (token === this.loadToken && !signal.aborted()) { this.loading = false; }
    }
  }

  private openReaderAt(pageIdx: number): void {
    this.stack.pushPathByName(ROUTE_READER, {
      aid: this.aid,
      chapterId: this.chapterId,
      page: pageIdx
    } as MangaRouteParams);
  }

  @Builder
  private PaginationBar() {
    Column() {
      Divider().strokeWidth('1px').color(DIVIDER)
      Row({ space: 12 }) {
        Button($r('app.string.previous_page'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(48).fontSize(14).fontColor(TEXT_MAIN).enabled(this.previewPage > 0)
          .onClick((): void => this.changePage(-1))
        Text($r('app.string.preview_page_number', this.previewPage + 1, this.pageCount()))
          .fontSize(14).fontFeature('"tnum" 1').fontColor(TEXT_SUB)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Button($r('app.string.next_page'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(48).fontSize(14).fontColor(TEXT_MAIN).enabled(this.previewPage < this.pageCount() - 1)
          .onClick((): void => this.changePage(1))
      }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 + this.bottomInset })
    }
    .width('100%')
    .backgroundColor(CARD)
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress().width(36).height(36).color(PRIMARY)
            Text('正在加载章节预览…').fontSize(14).fontColor(TEXT_SUB)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.error !== '') {
          Column() {
            EmptyView({
              message: this.error,
              retryText: '重试',
              showRetry: true,
              onRetry: (): void => {
                this.load();
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Column() {
            Grid(this.scroller) {
              ForEach(this.visiblePages(), (filename: string, idx: number) => {
                GridItem() {
                  Column({ space: 4 }) {
                    Stack({ alignContent: Alignment.BottomStart }) {
                      PagePreview({
                        chapter: this.chapterId,
                        filename: filename,
                        scramble: this.scrambleId,
                        thumbWidth: 240,
                        active: this.previewActive,
                        onOpen: (): void => this.openReaderAt(this.previewPage * this.pageSize() + idx)
                      })
                        .width('100%')
                        .height('100%')

                      Text(`${this.previewPage * this.pageSize() + idx + 1}`)
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontFeature('"tnum" 1')
                        .fontColor(ON_OVERLAY)
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .borderRadius(4)
                        .backgroundColor(OVERLAY_SCRIM)
                        .margin(6)
                        .hitTestBehavior(HitTestMode.None)
                    }
                    .width('100%')
                    .aspectRatio(0.72)
                    .borderRadius(COVER_R)
                    .border({ width: '1px', color: DIVIDER })
                    .clip(true)
                    .backgroundColor(SUB_CARD)
                  }
                  .width('100%')
                  .clickEffect(PRESS_SURFACE)
                }
              }, (filename: string, idx: number) => `${this.previewPage * this.pageSize() + idx}_${filename}`)
            }
            .columnsTemplate(this.columnsTemplateStr())
            .columnsGap(10)
            .rowsGap(12)
            .padding({ left: 16, right: 16 })
            .contentStartOffset(12)
            .contentEndOffset(12)
            .width('100%')
            .layoutWeight(1)

            if (this.allPages.length > 0) {
              this.PaginationBar()
            }
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)
    }
    .titleBar({
      content: {
        title: { mainTitle: this.chapterTitle || '章节速览' },
        menu: {
          value: [{
            content: {
              icon: $r('sys.symbol.square_grid_2x2'),
              label: $r('app.string.preview_layout'),
              isEnabled: this.allPages.length > 0,
              action: (): void => this.showColumnsMenu()
            }
          }]
        }
      },
      style: HDS_TITLE_STYLE,
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller])
    .onHidden((): void => { this.previewActive = false; this.cancelLoad(); })
    .onShown((): void => {
      this.previewActive = true;
      if (this.loading && this.loadSignal.aborted()) { this.load(); }
    })
    .onReady((ctx: NavDestinationContext) => {
      const rec: Record<string, Object> | null = asRecord(ctx.pathInfo.param as Object);
      if (rec !== null) {
        this.aid = asString(rec['aid']);
        this.chapterId = asString(rec['chapterId']);
        this.chapterTitle = asString(rec['query']) || '章节预览';
      }
      this.load();
    })
  }
}
