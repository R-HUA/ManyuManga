import { ReaderController } from './reader/ReaderController';
import { ReaderHud } from './reader/ReaderHud';
import { ReaderChapterSheet } from './reader/ReaderChapterSheet';
import { ReaderImageItem } from './reader/ReaderImageItem';
import display from '@ohos.display';
import { IMMERSIVE_SHEET_MATERIAL } from '../common/ImmersiveMaterials';
import { EmptyView } from '../common/Components';
import { READER_BG, PRIMARY, ACCENT, CHIP_R } from '../common/Theme';
import { Chapter, ReadingProgress, ReaderMode, asNumber, asRecord, asString } from '../models/Models';
import { ReaderOptions } from '../data/ReaderOptions';
import { MangaRouteParams, ROUTE_SEARCH } from '../common/Route';
/** 默认乱序参数 */
const SCRAMBLE_DEFAULT: number = 220980;
/** 护眼米黄背景 */
const PAPER_BG: string = '#F5EFE2';

// ───────────────────────── LazyForEach 数据源 ─────────────────────────

// ───────────────────────── 子组件 ─────────────────────────

// ───────────────────────── ReaderPage ─────────────────────────

@Component
export struct ReaderPage {
  @Consume('navPathStack') pageStack: NavPathStack;
  @StorageProp('appInBackground') @Watch('backgroundChanged') inBackground: boolean = false;
  @State options: ReaderOptions = new ReaderOptions();
  @State bookmarks: Array<ReadingProgress> = [];
  @State aid: string = '';
  @State albumTitle: string = '';
  @State authorLine: string = '';
  @State chapters: Array<Chapter> = [];
  @State chapterIndex: number = 0;
  @State pages: Array<string> = [];
  @State scrambleId: number = SCRAMBLE_DEFAULT;
  @State loadState: 'loading' | 'ready' | 'error' = 'loading';
  @State errorMsg: string = '';
  @State currentPage: number = 0;
  @State mode: ReaderMode = 'vertical';
  @State @Watch('onHudIdle') hudVisible: boolean = false;
  @State @Watch('onHudIdle') panel: 'none' | 'mode' | 'display' | 'settings' = 'none';
  @State @Watch('onHudIdle') sheetVisible: boolean = false;
  @State brightnessValue: number = 100;
  @State bgPaper: boolean = false;
  @State preloadCount: number = 3;
  @State sliderValue: number = 1;
  @State @Watch('onHudIdle') sliderDragging: boolean = false;
  @State canvasWidthVp: number = 0;
  @State canvasHeightVp: number = 0;
  @State topSafeVp: number = 38;
  @State bottomSafeVp: number = 18;
  @State zoomScale: number = 1;
  @State zoomOffsetX: number = 0;
  @State zoomOffsetY: number = 0;
  private controller: ReaderController = new ReaderController(this);

  aboutToAppear(): void { this.controller.aboutToAppear(); }
  aboutToDisappear(): void { this.controller.aboutToDisappear(); }
  private backgroundChanged(): void { this.controller.backgroundChanged(); }

              // ───────────────────────── 预加载─────────────────────────

          // ───────────────────────── 翻页 / 热区 / 模式─────────────────────────

    // ───────────────────────── 双指缩放─────────────────────────

              // ───────────────────────── 跨页序列（评审 Step4：rtl 右起 / double 双页并排）─────────────────────────

        // ───────────────────────── 画布─────────────────────────

  @Builder
  private VerticalList() {
    List({ scroller: this.controller.listScroller }) {
      LazyForEach(this.controller.pagesSource, (filename: string) => {
        ListItem() {
          ReaderImageItem({
            photoId: this.controller.currentChapterId(),
            filename: filename,
            scrambleId: this.scrambleId,
            targetWidth: this.controller.targetWidthPx,
            fitScreen: false,
            cropWhite: this.options.cropWhite,
            onFailure: (filename: string, error: Error): void => { this.controller.pageFailed(filename, error); }
          })
        }
      }, (filename: string) => filename)
      // 尾部：本章完 + 上一章/下一章（边界隐藏，ReaderScreen.kt:409-431）
      ListItem() {
        Column({ space: 14 }) {
          Text('—— 本章完 ——')
            .fontSize(13)
            .fontColor('rgba(255,255,255,0.45)')
          Row({ space: 12 }) {
            if (this.chapterIndex > 0) {
              Text('上一章')
                .fontSize(14)
                .fontColor('rgba(255,255,255,0.9)')
                .padding({ left: 22, right: 22, top: 9, bottom: 9 })
                .borderRadius(CHIP_R)
                .backgroundColor('rgba(255,255,255,0.12)')
                .onClick(() => {
                  this.controller.goChapter(-1);
                })
            }
            if (this.chapterIndex < this.chapters.length - 1) {
              Text('下一章')
                .fontSize(14)
                .fontColor(Color.White)
                .padding({ left: 22, right: 22, top: 9, bottom: 9 })
                .borderRadius(CHIP_R)
                .backgroundColor(ACCENT)
                .onClick(() => {
                  this.controller.goChapter(1);
                })
            }
          }
          if (this.chapters.length <= 1) {
            Text('本作品仅此一话')
              .fontSize(12)
              .fontColor('rgba(255,255,255,0.35)')
          }
        }
        .width('100%')
        .padding({ top: 28, bottom: 64 })
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .cachedCount(this.preloadCount)
    .onScrollIndex((first: number, end: number) => {
      if (first !== this.currentPage) {
        this.currentPage = first;
        this.controller.prefetchAhead(first);
        this.controller.scheduleProgressSave();
      }
    })
    .gesture(this.readingGesture())
  }

  /** 横向翻页（评审 Step4）：跨页序列渲染——horizontal 单页顺排 / rtl 倒排右起 / double 双页并排 */
  @Builder
  private HorizontalSwiper() {
    Swiper(this.controller.swiperController) {
      LazyForEach(this.controller.spreadSource, (spread: Array<string>) => {
        Row() {
          ForEach(spread, (filename: string) => {
            Column() {
              ReaderImageItem({
                photoId: this.controller.currentChapterId(),
                filename: filename,
                scrambleId: this.scrambleId,
                targetWidth: this.controller.targetWidthPx,
                fitScreen: true,
                cropWhite: this.options.cropWhite,
                onFailure: (filename: string, error: Error): void => { this.controller.pageFailed(filename, error); },
                onMeasured: (filename: string, aspect: number): void => { this.controller.measuredPage(filename, aspect); }
              })
            }
            .layoutWeight(1)
            .height('100%')
          }, (filename: string) => filename)
        }
        .width('100%')
        .height('100%')
      }, (spread: Array<string>, index?: number) => `${index}_${spread.join('_')}`)
    }
    .index(Math.max(0, this.controller.pageToSpreadIndex(this.currentPage)))
    .loop(false)
    .vertical(this.mode === 'pagedVertical')
    .indicator(false)
    .duration(240)
    .cachedCount(Math.max(2, this.preloadCount))
    .width('100%')
    .height('100%')
    .onChange((index: number) => {
      const page: number = this.controller.spreadIndexToPage(index);
      if (page !== this.currentPage) {
        this.currentPage = page;
      }
      this.controller.prefetchAhead(page);
      this.controller.scheduleProgressSave();
    })
    .gesture(this.readingGesture())
  }

  // ───────────────────────── 全屏状态（四态）─────────────────────────

  @Builder
  private LoadingView() {
    Column({ space: 14 }) {
      LoadingProgress().width(38).height(38).color(PRIMARY)
      Text('正在加载章节…')
        .fontSize(13)
        .fontColor('rgba(255,255,255,0.6)')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ErrorView() {
    Column({ space: 14 }) {
      EmptyView({
        message: this.errorMsg !== '' ? this.errorMsg : '加载失败，请检查网络后重试',
        retryText: '重试当前章节',
        showRetry: true,
        onRetry: (): void => {
          this.controller.retryLoad();
        }
      })
      Text('跨源匹配其他可用书源')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .padding({ left: 20, right: 20, top: 10, bottom: 10 })
        .borderRadius(20)
        .backgroundColor('rgba(255,255,255,0.14)')
        .border({ width: 0.5, color: 'rgba(255,255,255,0.22)' })
        .onClick(() => {
          this.pageStack.pushPathByName(ROUTE_SEARCH, { matchAid: this.aid } as MangaRouteParams);
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: this.topSafeVp })
  }

  @Builder
  private EmptyPagesView() {
    Column() {
      EmptyView({ message: '本章暂无内容', showRetry: false })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: this.topSafeVp })
  }

    @Builder
  private HudLayer() {
    ReaderHud({
      options: this.$options,
      brightnessValue: this.$brightnessValue,
      bgPaper: this.$bgPaper,
      preloadCount: this.$preloadCount,
      panel: this.$panel,
      hudVisible: this.$hudVisible,
      goBack: (): void => this.controller.goBack(),
      pages: this.$pages,
      albumTitle: this.$albumTitle,
      currentPage: this.$currentPage,
      zoomScale: this.$zoomScale,
      resetZoom: (animated: boolean): void => this.controller.resetZoom(animated),
      toggleBookmark: (): Promise<void> => this.controller.toggleBookmark(),
      topSafeVp: this.$topSafeVp,
      sliderDragging: this.$sliderDragging,
      sliderValue: this.$sliderValue,
      scrambleId: this.$scrambleId,
      chapterIndex: this.$chapterIndex,
      goChapter: (delta: number): void => this.controller.goChapter(delta),
      mode: this.$mode,
      jumpToPage: (page: number): void => this.controller.jumpToPage(page),
      chapters: this.$chapters,
      sheetVisible: this.$sheetVisible,
      bottomSafeVp: this.$bottomSafeVp,
      switchMode: (m: ReaderMode): void => this.controller.switchMode(m),
      toggleBackground: (paper: boolean): void => this.controller.toggleBackground(paper),
      buildSpreads: (): void => this.controller.buildSpreads(),
      scrollToPageDelayed: (page: number): void => this.controller.scrollToPageDelayed(page),
      persistOptions: (): Promise<void> => this.controller.persistOptions(),
      setPreload: (n: number): void => this.controller.setPreload(n),
      bookmarks: this.$bookmarks,
      onHudTouch: (down: boolean): void => this.controller.onHudTouch(down)
    })
  }

  private onHudIdle(): void {
    this.controller.syncHudTimer();
  }

  private readingGesture(): GestureType {
    return GestureGroup(GestureMode.Exclusive,
      TapGesture({ count: 2, fingers: 1 })
        .onAction((event: GestureEvent): void => {
          const point: Array<number> = this.tapPoint(event);
          this.controller.onDoubleTap(point[0], point[1]);
        }),
      TapGesture({ count: 1, fingers: 1 })
        .onAction((event: GestureEvent): void => {
          const point: Array<number> = this.tapPoint(event);
          this.controller.handleCanvasClick(point[0], point[1]);
        })
    );
  }

  private tapPoint(event: GestureEvent): Array<number> {
    if (event.fingerList.length === 0) {
      return [0, 0];
    }
    return [event.fingerList[0].localX, event.fingerList[0].localY];
  }

  /** HUD 隐藏时的微型常驻页码胶囊 */
  @Builder
  private PagePill() {
    Column() {
      Text(`${this.controller.chapterTitle()} · ${Math.min(this.currentPage + 1, this.pages.length)}/${this.pages.length}`)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor('rgba(255,255,255,0.86)')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '72%' })
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor('rgba(14, 17, 26, 0.72)')
        .border({ width: 0.5, color: 'rgba(255,255,255,0.14)' })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.End)
    .padding({ right: 12, bottom: this.bottomSafeVp + 10 })
    .hitTestBehavior(HitTestMode.None)
  }

  /** 章节目录半模态：点击直达对应话 */
  @Builder
  private ChapterSheet() {
    ReaderChapterSheet({
      bookmarks: this.$bookmarks,
      sheetVisible: this.$sheetVisible,
      chapters: this.$chapters,
      loadChapter: (chapterIdx: number, targetPage: number, preserveAttempts: boolean = false): Promise<void> => this.controller.loadChapter(chapterIdx, targetPage, preserveAttempts),
      chapterSource: this.controller.chapterSource,
      chapterIndex: this.$chapterIndex,
      flushProgress: (): void => this.controller.flushProgress()
    })
  }

  // ───────────────────────── 页面 ─────────────────────────

  build() {
    NavDestination() {
      Stack() {
        // 缩放画布：外层平移（父坐标系）+ 内层缩放 + 双指手势（不拦截单指滚动/翻页）
        Column() {
          Stack() {
            if (this.loadState === 'loading') {
              this.LoadingView()
            } else if (this.loadState === 'error') {
              this.ErrorView()
            } else if (this.pages.length === 0) {
              this.EmptyPagesView()
            } else if (this.mode === 'vertical') {
              this.VerticalList()
            } else {
              this.HorizontalSwiper()
            }
          }
          .width('100%')
          .height('100%')
          .scale({ x: this.zoomScale, y: this.zoomScale })
          .gesture(
            GestureGroup(GestureMode.Parallel,
              PinchGesture({ fingers: 2 })
                .onActionStart((event: GestureEvent): void => {
                  this.controller.onPinchStart(event);
                })
                .onActionUpdate((event: GestureEvent): void => {
                  this.controller.onPinchUpdate(event);
                })
                .onActionEnd((): void => {
                  this.controller.bounceZoomBack();
                }),
              PanGesture({ fingers: 2, distance: 1 })
                .onActionStart((event: GestureEvent): void => {
                  this.controller.onTwoFingerPanStart(event);
                })
                .onActionUpdate((event: GestureEvent): void => {
                  this.controller.onTwoFingerPanUpdate(event);
                })
                .onActionEnd((): void => {
                  this.controller.bounceZoomBack();
                })
            )
          )
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.zoomOffsetX, y: this.zoomOffsetY })
        if (this.options.eyeComfort) {
          Column().width('100%').height('100%').backgroundColor('rgba(255,185,85,0.16)').hitTestBehavior(HitTestMode.None)
        }
        // 亮度遮罩
        if (this.brightnessValue < 100) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(`rgba(0,0,0,${(((100 - this.brightnessValue) / 100) * 0.72).toFixed(2)})`)
            .hitTestBehavior(HitTestMode.None)
        }
        // 微型页码胶囊（HUD 隐藏时常驻）
        if (!this.hudVisible && this.loadState === 'ready' && this.pages.length > 0) {
          this.PagePill()
        }
        // 上下双层 HUD
        if (this.hudVisible) {
          this.HudLayer()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.bgPaper ? PAPER_BG : READER_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const w: number = Number(newArea.width);
        const h: number = Number(newArea.height);
        if (!Number.isNaN(w) && w > 0) {
          this.canvasWidthVp = w;
        }
        if (!Number.isNaN(h) && h > 0) {
          this.canvasHeightVp = h;
        }
      })
      .bindSheet($$this.sheetVisible, this.ChapterSheet(), {
        height: '62%',
        dragBar: true,
        systemMaterial: IMMERSIVE_SHEET_MATERIAL,
        onDisappear: (): void => {
          this.sheetVisible = false;
        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor(this.bgPaper ? PAPER_BG : READER_BG)
    .onReady((ctx: NavDestinationContext) => {
      if (this.controller.paramReady) {
        return;
      }
      this.controller.paramReady = true;
      const raw: Object | undefined = ctx.pathInfo.param as Object | undefined;
      if (raw !== undefined) {
        const rec: Record<string, Object> | null = asRecord(raw);
        if (rec !== null) {
          this.aid = asString(rec['aid']);
          // 契约参数 chapterId?: number，模型/Store 侧为 string —— asString 容忍数字统一转字符串
          this.controller.routeChapterId = asString(rec['chapterId']);
          this.controller.routeChapterIndex = asNumber(rec['chapterIndex'], -1);
          this.controller.routePage = asNumber(rec['page'], -1);
        }
      }
      this.controller.initAfterParams();
    })
    .onShown(() => {
      this.controller.readerVisible = true;
      if (this.controller.paramReady && this.controller.readingResolved && this.loadState === 'loading') { this.controller.retryLoad(); }
      if (this.loadState === 'ready' && !this.inBackground) { this.controller.activitySince = Date.now(); }
      // 阅读器画布恒深色（米黄除外）：进入即白字/米黄深字（评审 Step2 状态栏联动）
      this.controller.applySystemBarDarkText(this.bgPaper).catch((e: Error): void => {
      });
    })
    .onHidden(() => {
      this.controller.flushProgress();
      this.controller.activitySince = 0; this.controller.readerVisible = false; this.controller.chapterToken++;
    })
    .onWillDisappear(() => {
      this.controller.flushProgress();
      this.controller.restoreSystemBarToTheme();
    })
    .onBackPressed(() => {
      this.controller.flushProgress();
      return false;
    })
  }
}
