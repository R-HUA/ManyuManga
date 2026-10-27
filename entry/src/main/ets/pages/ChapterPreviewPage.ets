import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HDS_TITLE_STYLE } from '../common/ImmersiveMaterials';
import { IMMERSIVE_REGULAR_MATERIAL } from '../common/ImmersiveMaterials';
import { ROUTE_READER, MangaRouteParams } from '../common/Route';
import { asRecord, asString, errorMessage } from '../models/Models';
import { sourceApi } from '../data/SourceApi';
import { isRequestCancelled, RequestAbortGroup } from '../util/RequestAbort';
import { PagePreview } from '../common/PagePreview';
import { EmptyView } from '../common/Components';
import { BG, SUB_CARD, PRIMARY, TEXT_SUB, DIVIDER, COVER_R } from '../common/Theme';
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
  @State loading: boolean = true;
  @State error: string = '';
  @State gridWidthVp: number = 360;
  private loadToken: number = 0;
  private loadSignal: RequestAbortGroup = new RequestAbortGroup();

  aboutToDisappear(): void {
    this.cancelLoad();
  }

  private cancelLoad(): void {
    this.loadToken++;
    this.loadSignal.abortAll();
  }

  /** 按设备宽度计算列数：最小 3 列，宽屏自动扩展 */
  private columnsCount(): number {
    return Math.max(3, Math.floor((this.gridWidthVp - 32) / 112));
  }

  private columnsTemplateStr(): string {
    const cols: number = this.columnsCount();
    const parts: Array<string> = [];
    for (let i = 0; i < cols; i++) {
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
          Grid() {
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
                      .fontSize(10)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(6)
                      .backgroundColor('rgba(14,17,26,0.75)')
                      .margin(6)
                  }
                  .width('100%')
                  .aspectRatio(0.72)
                  .borderRadius(COVER_R)
                  .clip(true)
                  .backgroundColor(SUB_CARD)
                  .border({ width: 0.5, color: DIVIDER })
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
          .padding({ left: 16, right: 16, top: 12, bottom: 16 + this.bottomInset })
          .width('100%')
          .layoutWeight(1)
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            const w: number = Number(newArea.width);
            if (!Number.isNaN(w) && w > 0) {
              this.gridWidthVp = w;
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)
    }
    .titleBar({ content: { title: { mainTitle: this.chapterTitle || '章节速览' }, menu: { value: [{ content: { label: '从头阅读', isEnabled: this.allPages.length > 0, action: (): void => this.openReaderAt(0) } }] } }, style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavDestinationTitleMode.MINI)
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

