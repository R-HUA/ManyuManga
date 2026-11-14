import { ReaderController } from './reader/ReaderController';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { ReaderHud, ReaderPanelKind } from './reader/ReaderHud';
import { ReaderZoneOverlay } from './reader/ReaderZoneOverlay';
import { ReaderImageItem } from './reader/ReaderImageItem';
import { HDS_TITLE_STYLE, READER_BAR_MATERIAL, readerBarBackground } from '../common/ImmersiveMaterials';
import { EmptyView } from '../common/Components';
import { READER_BG, PRIMARY, eyeComfortTint, readerHudPalette } from '../common/Theme';
import { Chapter, ReadingProgress, ReaderMode, asNumber, asRecord, asString } from '../models/Models';
import { ReaderOptions, ReaderSheetKind } from '../data/ReaderOptions';
import { MangaRouteParams, ROUTE_SEARCH } from '../common/Route';
/** 默认乱序参数 */
const SCRAMBLE_DEFAULT: number = 220980;
/** 护眼米黄背景 */
const PAPER_BG: string = '#F5EFE2';
/** 自绘顶栏与底栏入口行的高度 */
const READER_TOP_BAR_HEIGHT: number = 56;
const READER_ENTRY_ROW_HEIGHT: number = 56;

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
  @State @Watch('onHudIdle') panel: ReaderPanelKind = 'none';
  @State sheetKind: ReaderSheetKind = 'index';
  @State @Watch('onHudIdle') sheetVisible: boolean = false;
  @State zoneEditorVisible: boolean = false;
  @State tapTurn: boolean = true;
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
  @State private readerActive: boolean = true;
  private controller: ReaderController = new ReaderController(this);

  aboutToAppear(): void { this.controller.aboutToAppear(); }
  aboutToDisappear(): void { this.controller.aboutToDisappear(); }
  private backgroundChanged(): void { this.controller.backgroundChanged(); }

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
            paper: this.bgPaper,
            active: this.readerActive && !this.inBackground,
            onDisplayed: (chapter: string, filename: string, visible: boolean): void => { this.controller.pageDisplayed(chapter, filename, visible); },
            onFailure: (filename: string, error: Error): void => { this.controller.pageFailed(filename, error); }
          })
        }
      }, (filename: string) => filename)
      ListItem() {
        Column({ space: 14 }) {
          Text('本章完')
            .fontSize(14)
            .fontColor(readerHudPalette(this.bgPaper).textSub)
          Row({ space: 12 }) {
            if (this.chapterIndex > 0) {
              Button('上一章', { buttonStyle: ButtonStyleMode.NORMAL, controlSize: ControlSize.NORMAL })
                .onClick(() => {
                  this.controller.goChapter(-1);
                })
            }
            if (this.chapterIndex < this.chapters.length - 1) {
              Button('下一章', { buttonStyle: ButtonStyleMode.EMPHASIZED, controlSize: ControlSize.NORMAL })
                .onClick(() => {
                  this.controller.goChapter(1);
                })
            }
          }
          if (this.chapters.length <= 1) {
            Text('本作品仅此一话')
              .fontSize(12)
              .fontColor(readerHudPalette(this.bgPaper).faint)
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
    .enableScrollInteraction(this.zoomScale <= 1.05)
    .cachedCount(this.preloadCount)
    .onScrollStart(() => { this.controller.tapGuard.motion(true, Date.now()); })
    .onScrollStop(() => { this.controller.tapGuard.motion(false, Date.now()); })
    .onDidScroll(() => { this.controller.tapGuard.motionTick(Date.now()); })
    .onScrollIndex((first: number) => {
      if (first !== this.currentPage) {
        this.currentPage = first;
        this.controller.prefetchAhead(first);
        this.controller.scheduleProgressSave();
      }
    })
  }

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
                paper: this.bgPaper,
                active: this.readerActive && !this.inBackground,
                onDisplayed: (chapter: string, filename: string, visible: boolean): void => { this.controller.pageDisplayed(chapter, filename, visible); },
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
    .disableSwipe(this.zoomScale > 1.05)
    .indicator(false)
    .duration(240)
    .cachedCount(Math.max(2, this.preloadCount))
    .width('100%')
    .height('100%')
    .onAppear(() => {
      const targetIdx: number = Math.max(0, this.controller.pageToSpreadIndex(this.currentPage));
      this.controller.swiperController.changeIndex(targetIdx, false);
    })
    .onGestureSwipe(() => { this.controller.tapGuard.motionTick(Date.now()); })
    .onAnimationStart(() => { this.controller.tapGuard.motion(true, Date.now()); })
    .onAnimationEnd(() => { this.controller.tapGuard.motion(false, Date.now()); })
    .onChange((index: number) => {
      const page: number = this.controller.spreadIndexToPage(index);
      if (page !== this.currentPage) {
        this.currentPage = page;
      }
      this.controller.prefetchAhead(page);
      this.controller.scheduleProgressSave();
    })
  }

  @Builder
  private LoadingView() {
    Column({ space: 14 }) {
      LoadingProgress().width(38).height(38).color(PRIMARY)
      Text('正在加载章节…')
        .fontSize(14)
        .fontColor(readerHudPalette(this.bgPaper).textSub)
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
      Button('跨源匹配其他可用书源', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
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
      panel: this.$panel,
      pages: this.$pages,
      currentPage: this.$currentPage,
      maxPanelHeight: Math.max(120, this.canvasHeightVp - this.topSafeVp - this.bottomSafeVp -
        READER_TOP_BAR_HEIGHT - READER_ENTRY_ROW_HEIGHT - 24),
      bottomInset: this.bottomSafeVp,
      sliderDragging: this.$sliderDragging,
      sliderValue: this.$sliderValue,
      scrambleId: this.$scrambleId,
      chapterIndex: this.$chapterIndex,
      goChapter: (delta: number): void => this.controller.goChapter(delta),
      mode: this.$mode,
      jumpToPage: (page: number): void => this.controller.jumpToPage(page),
      chapters: this.$chapters,
      switchMode: (m: ReaderMode): void => this.controller.switchMode(m),
      cycleMode: (): void => this.controller.cycleMode(),
      openSheet: (kind: ReaderSheetKind): void => this.controller.openSheet(kind),
      options: this.$options,
      brightnessValue: this.$brightnessValue,
      bgPaper: this.$bgPaper,
      preloadCount: this.$preloadCount,
      buildSpreads: (): void => this.controller.buildSpreads(),
      scrollToPageDelayed: (page: number): void => this.controller.scrollToPageDelayed(page),
      persistOptions: (): Promise<void> => this.controller.persistOptions(),
      toggleBackground: (paper: boolean): void => this.controller.toggleBackground(paper),
      setPreload: (n: number): void => this.controller.setPreload(n),
      openZoneEditor: (): void => this.controller.openZoneEditor(),
      onHudTouch: (down: boolean): void => this.controller.onHudTouch(down),
      bookmarks: this.$bookmarks,
      tapTurn: this.$tapTurn,
      setTapTurn: (on: boolean): void => { this.controller.setTapTurn(on); },
      chapterSource: this.controller.chapterSource,
      loadChapter: (chapterIdx: number, targetPage: number): Promise<void> =>
        this.controller.loadChapter(chapterIdx, targetPage),
      flushProgress: (): void => this.controller.flushProgress()
    })
  }

  private onHudIdle(): void {
    if (!this.hudVisible && (this.panel !== 'none' || this.sliderDragging)) {
      this.panel = 'none';
      this.sliderDragging = false;
      this.controller.onHudTouch(false);
    }
    this.controller.syncHudTimer();
    this.controller.syncStatusBar();
  }

  private onCurrentBookmark(): boolean {
    return this.bookmarks.some((item: ReadingProgress): boolean =>
      item.chapterId === this.controller.currentChapterId() && item.page === this.currentPage);
  }

  @Builder
  private BarIcon(symbol: Resource, label: string, onTap: () => void) {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      SymbolGlyph(symbol).fontSize(22).fontColor([$r('sys.color.icon_primary')])
    }
    .width(40)
    .height(40)
    .accessibilityText(label)
    .onClick(() => { onTap(); })
  }

  /**
   * 自绘顶栏：固定贴顶，深色沉浸光感，顶部按状态栏高度避让。
   * 取代 HDS 标题栏，使上下两栏共用同一材质与深色配色。
   */
  @Builder
  private TopBar() {
    Column() {
      Row({ space: 4 }) {
        this.BarIcon($r('sys.symbol.chevron_left'), '返回', (): void => {
          this.controller.flushProgress();
          this.pageStack.pop();
        })
        Text(this.chapters[this.chapterIndex]?.title || this.albumTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.zoomScale > 1) {
          this.BarIcon($r('sys.symbol.arrow_counterclockwise'), '复位缩放', (): void => {
            this.controller.resetZoom(true);
          })
        }
        this.BarIcon(this.onCurrentBookmark() ? $r('sys.symbol.bookmark_fill') : $r('sys.symbol.bookmark'), '书签',
          (): void => { this.controller.toggleBookmark(); })
      }
      .width('100%')
      .height(READER_TOP_BAR_HEIGHT)
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .padding({ top: this.topSafeVp })
    .backgroundColor(readerBarBackground())
    .systemMaterial(READER_BAR_MATERIAL)
    .onClick(() => {
      // 阻断顶栏点击穿透到画布
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.controller.onHudTouch(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.controller.onHudTouch(false);
      }
    })
  }

  /** 记录每段触摸的位移、指数与时长，供点按判定排除滑动、捏合与长按。 */
  private trackTouch(event: TouchEvent): void {
    const touch: TouchObject | undefined = event.changedTouches.length > 0 ? event.changedTouches[0] : event.touches[0];
    if (touch === undefined) {
      return;
    }
    const now: number = Date.now();
    if (event.type === TouchType.Down) {
      this.controller.tapGuard.down(touch.x, touch.y, event.touches.length, now);
    } else if (event.type === TouchType.Move) {
      this.controller.tapGuard.move(touch.x, touch.y, event.touches.length);
    } else if (event.type === TouchType.Up) {
      this.controller.tapGuard.up(touch.x, touch.y, now);
    } else if (event.type === TouchType.Cancel) {
      this.controller.tapGuard.cancel();
    }
  }

  private tapPoint(event: GestureEvent): Array<number> {
    return event.tapLocation === undefined ? [this.canvasWidthVp / 2, this.canvasHeightVp / 2]
      : [event.tapLocation.x, event.tapLocation.y];
  }

  /** HUD 隐藏时的微型常驻页码胶囊 */
  @Builder
  private PagePill() {
    Column() {
      Text(`${this.controller.chapterTitle()} P.${Math.min(this.currentPage + 1, this.pages.length)}/${this.pages.length}`)
        .fontSize(12)
        .fontColor(readerHudPalette(this.bgPaper).text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '72%' })
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor(readerHudPalette(this.bgPaper).capsule)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.End)
    .padding({ right: 12, bottom: this.bottomSafeVp + 10 })
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    HdsNavDestination() {
      Stack() {
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
          .translate({ x: this.zoomOffsetX, y: this.zoomOffsetY })
        }
        .width('100%')
        .height('100%')
        .onTouch((event: TouchEvent): void => { this.trackTouch(event); })
        .onGestureJudgeBegin((info: GestureInfo, _event: BaseGestureEvent): GestureJudgeResult => {
          // 未放大时不让画面拖动手势抢占列表滚动或翻页。
          if (info.tag === 'readerZoomPan' && this.zoomScale <= 1.05) {
            return GestureJudgeResult.REJECT;
          }
          return GestureJudgeResult.CONTINUE;
        })
        .gesture(
          GestureGroup(GestureMode.Parallel,
            GestureGroup(GestureMode.Exclusive,
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
            ),
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
            PanGesture({ fingers: 1, distance: 3 })
              .tag('readerZoomPan')
              .onActionStart((event: GestureEvent): void => {
                if (this.zoomScale > 1.05) {
                  this.controller.onTwoFingerPanStart(event);
                }
              })
              .onActionUpdate((event: GestureEvent): void => {
                if (this.zoomScale > 1.05) {
                  this.controller.onTwoFingerPanUpdate(event);
                }
              })
              .onActionEnd((): void => {
                if (this.zoomScale > 1.05) {
                  this.controller.bounceZoomBack();
                }
              })
          )
        )
        if (this.options.eyeComfort > 0) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(eyeComfortTint(this.options.eyeComfort))
            .hitTestBehavior(HitTestMode.None)
        }
        if (this.brightnessValue < 100) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(`rgba(0,0,0,${(((100 - this.brightnessValue) / 100) * 0.72).toFixed(2)})`)
            .hitTestBehavior(HitTestMode.None)
        }
        if (!this.hudVisible && !this.zoneEditorVisible && this.loadState === 'ready' && this.pages.length > 0) {
          this.PagePill()
        }
        if (this.hudVisible) {
          Column().width('100%').height('100%').hitTestBehavior(HitTestMode.Block)
            .onClick(() => {
              // 目录浮层打开时，点击面板外只收起浮层，保留上下栏。
              if (this.panel === 'index') { this.panel = 'none'; } else { this.panel = 'none'; this.hudVisible = false; }
            })
        }
        // 上下栏固定贴边：外层 WithTheme(DARK) 让栏内系统色恒为深色，阅读画布本身不受影响。
        if (this.hudVisible) {
          Column() {
            WithTheme({ colorMode: ThemeColorMode.DARK }) {
              this.TopBar()
            }
          }
          .width('100%')
          .position({ left: 0, top: 0 })
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.move(TransitionEdge.TOP))
            .animation({ duration: 200, curve: Curve.FastOutSlowIn }))
          Column() {
            WithTheme({ colorMode: ThemeColorMode.DARK }) {
              this.HudLayer()
            }
          }
          .width('100%')
          .position({ left: 0, bottom: 0 })
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.move(TransitionEdge.BOTTOM))
            .animation({ duration: 200, curve: Curve.FastOutSlowIn }))
        }
        if (this.zoneEditorVisible) {
          ReaderZoneOverlay({
            options: this.$options,
            topSafeVp: this.$topSafeVp,
            persistOptions: (): Promise<void> => this.controller.persistOptions(),
            close: (): void => {
              this.zoneEditorVisible = false;
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.bgPaper ? PAPER_BG : READER_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const w: number = Number(newArea.width);
        const h: number = Number(newArea.height);
        if (!Number.isNaN(w) && w > 0) {
          this.canvasWidthVp = w;
        }
        if (!Number.isNaN(h) && h > 0) {
          this.canvasHeightVp = h;
        }
      })
    }
    .titleBar({ content: { title: { mainTitle: this.chapters[this.chapterIndex]?.title || this.albumTitle } },
      style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true, enableComponentSafeArea: false })
    .titleMode(HdsNavDestinationTitleMode.MINI)
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
          this.controller.routeChapterId = asString(rec['chapterId']);
          this.controller.routeChapterIndex = asNumber(rec['chapterIndex'], -1);
          this.controller.routePage = asNumber(rec['page'], -1);
        }
      }
      this.controller.initAfterParams();
    })
    .onShown(() => {
      this.controller.readerVisible = true;
      this.readerActive = true;
      if (this.controller.paramReady && this.controller.readingResolved && this.loadState === 'loading') { this.controller.retryLoad(); }
      this.controller.syncStatusBar(true);
    })
    .onHidden(() => {
      this.hudVisible = false;
      this.panel = 'none';
      this.sheetVisible = false;
      this.readerActive = false;
      this.controller.flushProgress();
      this.controller.activitySince = 0; this.controller.readerVisible = false; this.controller.chapterToken++;
    })
    .onWillDisappear(() => {
      this.controller.flushProgress();
      this.controller.restoreSystemBarToTheme();
    })
    .onBackPressed(() => {
      if (this.hudVisible) {
        if (this.panel !== 'none') { this.panel = 'none'; } else { this.hudVisible = false; }
        return true;
      }
      this.controller.flushProgress();
      return false;
    })
  }
}
