import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { EMPTY_MATERIAL, HDS_TITLE_STYLE } from '../common/ImmersiveMaterials';
import { ROUTE_READER, MangaRouteParams } from '../common/Route';
import { asRecord, asString, errorMessage } from '../models/Models';
import { sourceApi } from '../data/SourceApi';
import { isRequestCancelled, RequestAbortGroup } from '../util/RequestAbort';
import { PagePreview } from '../common/PagePreview';
import { EmptyView } from '../common/Components';
import { BG, BAR_LIGHT, SUB_CARD, PRIMARY, TEXT_MAIN, TEXT_SUB, DIVIDER, COVER_R } from '../common/Theme';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

@Component
export struct ChapterPreviewPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 38;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 16;

  @State aid: string = '';
  @State chapterId: string = '';
  @State chapterTitle: string = '';
  @State allPages: Array<string> = [];
  @State scrambleId: number = 220980;
  @State currentPageIndex: number = 0;
  @State columns: number = 3;
  @State sliderDragging: boolean = false;
  @State loading: boolean = true;
  @State error: string = '';
  @State narrowBar: boolean = false;
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

  private cycleColumns(): void {
    if (this.columns === 2) {
      this.columns = 3;
    } else if (this.columns === 3) {
      this.columns = 4;
    } else {
      this.columns = 2;
    }
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
      this.currentPageIndex = 0;
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
  private ProgressSlider() {
      Slider({
        value: Math.min(this.currentPageIndex + 1, Math.max(this.allPages.length, 1)),
        min: 1,
        max: Math.max(this.allPages.length, 1),
        step: 1,
        style: SliderStyle.InSet
      })
        .selectedColor(PRIMARY)
        .trackColor(SUB_CARD)
        .trackThickness(24)
        .blockColor(Color.White)
        .systemMaterial(EMPTY_MATERIAL)
        .layoutWeight(1)
        .enabled(this.allPages.length > 1)
        .onChange((value: number, mode: SliderChangeMode) => {
          const targetIdx: number = Math.max(0, Math.min(this.allPages.length - 1, Math.round(value) - 1));
          this.currentPageIndex = targetIdx;
          if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
            this.sliderDragging = true;
            this.scroller.scrollToIndex(targetIdx, false);
          } else {
            this.sliderDragging = false;
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.scroller.scrollToIndex(targetIdx, true);
            }
          }
        })
  }

  @Builder
  private JumpBar() {
    Column({ space: 4 }) {
      if (this.narrowBar) {
        Row() { this.ProgressSlider() }.width('100%').height(32)
      }
      Row({ space: 8 }) {
        Button('从头阅读', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
          .height(36).fontSize(14).fontWeight(FontWeight.Medium)
          .backgroundColor(SUB_CARD).fontColor(TEXT_MAIN).padding({ left: 12, right: 12 })
          .responseRegion({ x: 0, y: -4, width: '100%', height: 44 })
          .onClick(() => this.openReaderAt(0))
        if (this.narrowBar) { Blank().layoutWeight(1) } else { this.ProgressSlider() }
        Button({ type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.EMPHASIZED }) {
          Text(`读 P.${Math.min(this.currentPageIndex + 1, Math.max(1, this.allPages.length))}/${this.allPages.length}`)
            .fontSize(14).fontWeight(FontWeight.Medium).fontFeature('"tnum" 1').fontColor(Color.White)
        }
        .height(36).padding({ left: 12, right: 12 })
        .width((64 + `${this.allPages.length}`.length * 16) * this.getUIContext().fp2px(1) / this.getUIContext().vp2px(1))
        .responseRegion({ x: 0, y: -4, width: '100%', height: 44 })
        .onClick(() => this.openReaderAt(this.currentPageIndex))
      }.width('100%').height(40)
    }
    .width('100%')
    .height(this.narrowBar ? 92 : 56)
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(28)
    .backgroundColor(BAR_LIGHT)
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .border({ width: '1px', color: DIVIDER })
    .shadow(ShadowStyle.OUTER_FLOATING_SM)
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress().width(36).height(36).color(PRIMARY)
            Text('正在加载章节预览…').fontSize(13).fontColor(TEXT_SUB)
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
          Stack({ alignContent: Alignment.Bottom }) {
            Grid(this.scroller) {
              ForEach(this.allPages, (filename: string, idx: number) => {
                GridItem() {
                  Column({ space: 4 }) {
                    Stack({ alignContent: Alignment.BottomStart }) {
                      PagePreview({
                        chapter: this.chapterId,
                        filename: filename,
                        scramble: this.scrambleId,
                        thumbWidth: 240
                      })
                        .width('100%')
                        .height('100%')

                      Text(`P.${idx + 1}`)
                        .fontSize(11)
                        .fontWeight(FontWeight.Medium)
                        .fontFeature('"tnum" 1')
                        .fontColor(Color.White)
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .borderRadius(6)
                        .backgroundColor('rgba(14,17,26,0.72)')
                        .margin(6)
                    }
                    .width('100%')
                    .aspectRatio(0.72)
                    .borderRadius(COVER_R)
                    .border({ width: '1px', color: DIVIDER })
                    .clip(true)
                    .backgroundColor(SUB_CARD)
                  }
                  .width('100%')
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
                  .onClick(() => {
                    this.openReaderAt(idx);
                  })
                }
              }, (filename: string, idx: number) => `${idx}_${filename}`)
            }
            .columnsTemplate(this.columnsTemplateStr())
            .columnsGap(10)
            .rowsGap(12)
            .padding({ left: 16, right: 16, top: 12 })
            .contentEndOffset((this.narrowBar ? 120 : 84) + this.bottomInset)
            .width('100%')
            .height('100%')
            .onScrollIndex((first: number) => {
              if (!this.sliderDragging && first >= 0 && first < this.allPages.length) {
                this.currentPageIndex = first;
              }
            })

            if (this.allPages.length > 0) {
              Column() {
                this.JumpBar()
              }
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 12 + this.bottomInset })
            }
          }
          .width('100%')
          .layoutWeight(1)
          .onAreaChange((_old: Area, area: Area) => {
            this.narrowBar = Number(area.width) < 360 * this.getUIContext().fp2px(1) / this.getUIContext().vp2px(1);
          })
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
              label: `${this.columns}列`,
              isEnabled: this.allPages.length > 0,
              action: (): void => this.cycleColumns()
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
    .onHidden((): void => { this.cancelLoad(); })
    .onShown((): void => {
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
