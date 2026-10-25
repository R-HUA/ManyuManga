/**
 * 全屏沉浸式漫画阅读器。
 *
 */
import display from '@ohos.display';
import image from '@ohos.multimedia.image';
import uiMaterial from '@ohos.arkui.uiMaterial';

import { window } from '@kit.ArkUI';
import { EmptyView } from '../common/Components';
import {
  READER_BG, MASK_DARK, PRIMARY, PRIMARY_SOFT, ACCENT, ACCENT_SOFT, CHIP_R, CARD_R
} from '../common/Theme';
import {
  Album,
  Chapter,
  ReadingProgress,
  ReaderMode,
  asNumber,
  asRecord,
  asString,
  errorMessage
} from '../models/Models';
import { sourceApi as jmApi } from '../data/SourceApi';
import { library } from '../data/Library';
import { readerPreferences, ReaderOptions } from '../data/ReaderOptions';
import { readingActivity } from '../data/ReadingActivity';
import { fallbackSource, SourceSwitchResult, switchedProgress } from '../data/SourceSwitch';
import { makeSpreads, spreadForPage, lastPageInSpread } from '../data/ReaderLayout';
import { cropPageWhitespace } from '../data/ImageDecode';
import { MangaRouteParams, ROUTE_SEARCH } from '../common/Route';
import { loadPagePixelMap, releasePagePixelMap } from '../data/ImageDecode';
import { albumCacheStore, pagesCacheStore, readProgressStore } from '../data/Stores';
import { Prefs, getAppContext } from '../util/Prefs';
import { IS_DARK_MODE_KEY } from '../entryability/EntryAbility';

/** 默认乱序参数 */
const SCRAMBLE_DEFAULT: number = 220980;
/** 护眼米黄背景 */
const PAPER_BG: string = '#F5EFE2';
/** 单页占位底色（阅读器深色画布内的一次性色） */
const PLACEHOLDER_BG: string = '#16161A';
/** 单页失败占位底色 */
const FAILED_BG: string = '#201619';
/** HUD 内层面板底色（一次性深色 rgba） */
const PANEL_BG: string = 'rgba(28,28,32,0.82)';
/** 进度节流间隔 ms */
const SAVE_THROTTLE_MS: number = 2000;
/** 缩放范围 */
const ZOOM_MIN: number = 1;
const ZOOM_MAX: number = 5;

// ───────────────────────── LazyForEach 数据源 ─────────────────────────

/** 进度条拖动悬浮缩略图：240px 档缩略图，零拷贝缓存直读 */
@Component
struct PageThumbItem {
  @Prop @Watch('onSrcChanged') photoId: string = '';
  @Prop @Watch('onSrcChanged') filename: string = '';
  @Prop @Watch('onSrcChanged') scrambleId: number = SCRAMBLE_DEFAULT;
  @State pixelMap: image.PixelMap | undefined = undefined;
  private token: number = 0;

  aboutToAppear(): void {
    this.doLoad();
  }

  aboutToDisappear(): void {
    this.token++;
    this.releaseMap();
  }

  onSrcChanged(): void {
    this.doLoad();
  }

  private releaseMap(): void {
    const m: image.PixelMap | undefined = this.pixelMap;
    if (m !== undefined) {
      releasePagePixelMap(m);
      this.pixelMap = undefined;
    }
  }

  private async doLoad(): Promise<void> {
    if (this.photoId === '' || this.filename === '') {
      return;
    }
    const t: number = ++this.token;
    this.releaseMap();
    try {
      const pm: image.PixelMap | null = await loadPagePixelMap(this.photoId, this.filename, this.scrambleId, 240);
      if (t !== this.token) {
        if (pm !== null) {
          releasePagePixelMap(pm);
        }
        return;
      }
      this.pixelMap = pm === null ? undefined : pm;
    } catch (e) {
      // 缩略图失败保持占位底色
    }
  }

  build() {
    Stack() {
      if (this.pixelMap !== undefined) {
        Image(this.pixelMap)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(PLACEHOLDER_BG)
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(8)
    .clip(true)
  }
}

/** 章节图片文件名列表数据源 */
class PageListSource implements IDataSource {
  private list: Array<string> = [];
  private listeners: Array<DataChangeListener> = [];

  constructor(list: Array<string> = []) {
    this.list = list;
  }

  public totalCount(): number {
    return this.list.length;
  }

  public getData(index: number): string {
    return this.list[index];
  }

  public registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  public unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener);
  }

  public setList(list: Array<string>): void {
    this.list = list;
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }
}

/** 横向翻页跨页序列数据源：horizontal/rtl=单页序列（rtl 倒排）、double=双页并排序列 */
class SpreadListSource implements IDataSource {
  private list: Array<Array<string>> = [];
  private listeners: Array<DataChangeListener> = [];

  constructor(list: Array<Array<string>> = []) {
    this.list = list;
  }

  public totalCount(): number {
    return this.list.length;
  }

  public getData(index: number): Array<string> {
    return this.list[index];
  }

  public registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  public unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener);
  }

  public setList(list: Array<Array<string>>): void {
    this.list = list;
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }
}

/** 章节目录数据源 */
class ChapterSource implements IDataSource {
  private list: Array<Chapter> = [];
  private listeners: Array<DataChangeListener> = [];

  constructor(list: Array<Chapter> = []) {
    this.list = list;
  }

  public totalCount(): number {
    return this.list.length;
  }

  public getData(index: number): Chapter {
    return this.list[index];
  }

  public registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  public unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener);
  }

  public setList(list: Array<Chapter>): void {
    this.list = list;
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }
}

// ───────────────────────── 子组件 ─────────────────────────

/**
 * 单页渲染：字节 → 原尺寸反混淆 → 缩放为 PixelMap 再显示（ImageDecode 整链路）。
 * 三态：加载（灰底 + 转圈）/ 失败（点按重试，fetchPageBytes 内部自动换图床域名 3 次）/ 成功。
 * scrambleId/photoId/filename 变化时经 @Watch 触发重载（乱序参数后台回填场景）。
 */
@Component
struct ReaderImageItem {
  @Prop @Watch('onSourceChanged') photoId: string = '';
  @Prop @Watch('onSourceChanged') filename: string = '';
  @Prop @Watch('onSourceChanged') scrambleId: number = SCRAMBLE_DEFAULT;
  @Prop targetWidth: number = 0;
  /** true = 横向翻页整屏适配（ImageFit.Contain）；false = 纵向条漫整宽 */
  @Prop fitScreen: boolean = false;
  @Prop @Watch('onSourceChanged') cropWhite: boolean = false;
  onFailure: (filename: string, error: Error) => void = (): void => {};
  onMeasured: (filename: string, aspect: number) => void = (): void => {};
  @State pixelMap: image.PixelMap | undefined = undefined;
  @State loading: boolean = true;
  @State failed: boolean = false;
  @State aspect: number = 0.7;
  private loadToken: number = 0;

  aboutToAppear(): void {
    this.doLoad();
  }

  aboutToDisappear(): void {
    this.loadToken++;
    this.releaseMap();
  }

  onSourceChanged(): void {
    this.doLoad();
  }

  private releaseMap(): void {
    const m: image.PixelMap | undefined = this.pixelMap;
    if (m !== undefined) {
      releasePagePixelMap(m);
      this.pixelMap = undefined;
    }
  }

  private async doLoad(): Promise<void> {
    if (this.photoId === '' || this.filename === '') {
      this.loading = false;
      this.failed = true;
      return;
    }
    const token: number = ++this.loadToken;
    this.loading = true;
    this.failed = false;
    this.releaseMap();
    try {
      let map: image.PixelMap | null = await loadPagePixelMap(
        this.photoId, this.filename, this.scrambleId, this.targetWidth);
      if (token !== this.loadToken) {
        if (map !== null) {
          releasePagePixelMap(map);
        }
        return;
      }
      if (map === null) {
        this.loading = false;
        this.failed = true;
        this.onFailure(this.filename, new Error('页面解码失败'));
        return;
      }
      if (this.cropWhite) {
        const original: image.PixelMap = map;
        try { map = await cropPageWhitespace(original); }
        finally { releasePagePixelMap(original); }
        if (token !== this.loadToken) { await map.release(); return; }
      }
      const info: image.ImageInfo | undefined = map.getImageInfoSync();
      if (info === undefined || info.size === undefined || info.size.height <= 0) {
        releasePagePixelMap(map);
        throw new Error('图像尺寸无效，请重试');
      }
      this.aspect = info.size.width / info.size.height;
      this.onMeasured(this.filename, this.aspect);
      this.pixelMap = map;
      this.loading = false;
    } catch (e) {
      if (token === this.loadToken) {
        this.loading = false;
        this.failed = true;
        this.onFailure(this.filename, e as Error);
      }
    }
  }

  build() {
    Stack() {
      this.Content()
    }
    .width('100%')
    .height(this.fitScreen ? '100%' : 'auto')
  }

  @Builder
  private Content() {
    if (this.loading) {
      if (this.fitScreen) {
        Column() {
          LoadingProgress().width(26).height(26).color('rgba(255,255,255,0.45)')
        }
        .width('100%')
        .height('100%')
        .backgroundColor(PLACEHOLDER_BG)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          LoadingProgress().width(26).height(26).color('rgba(255,255,255,0.45)')
        }
        .width('100%')
        .aspectRatio(this.aspect)
        .backgroundColor(PLACEHOLDER_BG)
        .justifyContent(FlexAlign.Center)
      }
    } else if (this.failed) {
      if (this.fitScreen) {
        Column({ space: 8 }) {
          Text('加载失败').fontSize(14).fontColor('rgba(255,255,255,0.85)')
          Text('点按重试（自动切换线路）').fontSize(11).fontColor('rgba(255,255,255,0.5)')
        }
        .width('100%')
        .height('100%')
        .backgroundColor(FAILED_BG)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.doLoad();
        })
      } else {
        Column({ space: 8 }) {
          Text('加载失败').fontSize(14).fontColor('rgba(255,255,255,0.85)')
          Text('点按重试（自动切换线路）').fontSize(11).fontColor('rgba(255,255,255,0.5)')
        }
        .width('100%')
        .aspectRatio(this.aspect)
        .backgroundColor(FAILED_BG)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.doLoad();
        })
      }
    } else if (this.pixelMap !== undefined) {
      if (this.fitScreen) {
        Image(this.pixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.Medium)
      } else {
        Image(this.pixelMap)
          .width('100%')
          .aspectRatio(this.aspect)
          .objectFit(ImageFit.Fill)
          .interpolation(ImageInterpolation.Medium)
      }
    }
  }
}

/** HUD 四大金刚纯图标按钮（目录/模式/画面/设置，严禁图标文字混排与字符 Emoji） */
@Component
struct HudButton {
  @Prop symbol: Resource = $r('sys.symbol.list_bullet');
  @Prop label: string = '';
  @Prop active: boolean = false;
  onTap: () => void = (): void => {
  };

  build() {
    Column({ space: 4 }) {
      SymbolGlyph(this.symbol)
        .fontSize(20)
        .fontColor([this.active ? Color.White : 'rgba(255,255,255,0.92)'])
      Text(this.label)
        .fontSize(11)
        .fontWeight(this.active ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.active ? Color.White : 'rgba(255,255,255,0.82)')
    }
    .layoutWeight(1)
    .height(52)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(16)
    .backgroundColor(this.active ? PRIMARY : 'rgba(255,255,255,0.08)')
    .border({ width: 0.5, color: this.active ? PRIMARY : 'rgba(255,255,255,0.12)' })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
    .onClick(() => {
      this.onTap();
    })
  }
}

/** 通用选择胶囊（背景色 / 预加载档位），对齐 TagChip 规范 */
@Component
struct ChipOption {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  onTap: () => void = (): void => {
  };

  build() {
    Text(this.label)
      .fontSize(12)
      .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.selected ? Color.White : 'rgba(255,255,255,0.78)')
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(this.selected ? PRIMARY : 'rgba(255,255,255,0.10)')
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
      .onClick(() => {
        this.onTap();
      })
  }
}

/** 阅读模式选项行 */
@Component
struct ModeOptionRow {
  @Prop label: string = '';
  @Prop sub: string = '';
  @Prop selected: boolean = false;
  onPick: () => void = (): void => {
  };

  build() {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(this.label)
          .fontSize(14)
          .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.selected ? PRIMARY : 'rgba(255,255,255,0.92)')
        Text(this.sub)
          .fontSize(11)
          .fontColor('rgba(255,255,255,0.52)')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.selected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([PRIMARY])
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .borderRadius(14)
    .backgroundColor(this.selected ? 'rgba(58,122,254,0.18)' : 'rgba(255,255,255,0.06)')
    .border({ width: 0.5, color: this.selected ? PRIMARY : 'rgba(255,255,255,0.08)' })
    .onClick(() => {
      this.onPick();
    })
  }
}

// ───────────────────────── ReaderPage ─────────────────────────

@Component
export struct ReaderPage {
  /** 全局路由栈（MainShell @Provide） */
  @Consume('navPathStack') pageStack: NavPathStack;
  @StorageProp('appInBackground') @Watch('backgroundChanged') inBackground: boolean = false;
  @State options: ReaderOptions = new ReaderOptions();
  @State bookmarks: Array<ReadingProgress> = [];
  private currentAlbum: Album | null = null;
  private attemptedSources: Set<string> = new Set();
  private widePages: Set<string> = new Set();
  private switchingSource: boolean = false;
  private activitySince: number = 0;
  private readerVisible: boolean = true;
  private activityBookKey: string = '';

  // ── 路由参数──
  private routeChapterId: string = '';
  private routeChapterIndex: number = -1;
  private routePage: number = -1;
  private paramReady: boolean = false;

  // ── UI 状态 ──
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
  @State hudVisible: boolean = false;
  @State panel: 'none' | 'mode' | 'display' | 'settings' = 'none';
  @State sheetVisible: boolean = false;
  @State brightnessValue: number = 100;
  @State bgPaper: boolean = false;
  @State preloadCount: number = 3;
  @State sliderValue: number = 1;
  @State sliderDragging: boolean = false;
  @State canvasWidthVp: number = 0;
  @State canvasHeightVp: number = 0;
  @State topSafeVp: number = 38;
  @State bottomSafeVp: number = 18;

  // ── 双指缩放──
  @State zoomScale: number = 1;
  @State zoomOffsetX: number = 0;
  @State zoomOffsetY: number = 0;
  private pinchStartScale: number = 1;
  private panStartX: number = 0;
  private panStartY: number = 0;

  // ── 非渲染成员 ──
  private targetWidthPx: number = 1080;
  private pagesSource: PageListSource = new PageListSource();
  private spreadSource: SpreadListSource = new SpreadListSource();
  /** 跨页序列缓存（页码 ↔ 跨页序号映射用，与 spreadSource 同步重建） */
  private spreadsCache: Array<Array<string>> = [];
  private chapterSource: ChapterSource = new ChapterSource();
  private listScroller: Scroller = new Scroller();
  private swiperController: SwiperController = new SwiperController();
  private prefetched: Set<string> = new Set<string>();
  private chapterToken: number = 0;
  private albumToken: number = 0;
  private lastSavedAt: number = 0;
  private saveTimer: number = -1;
  private readingStarted: boolean = false;
  private readingResolved: boolean = false;
  private autoCacheOn: boolean = true;
  private destroyed: boolean = false;

  aboutToAppear(): void {
    try {
      this.targetWidthPx = display.getDefaultDisplaySync().width;
    } catch (e) {
      this.targetWidthPx = 1080;
    }
  }

  aboutToDisappear(): void {
    this.flushProgress();
    this.activitySince = 0;
    this.chapterToken++;
    this.albumToken++;
    this.destroyed = true;
  }

  private backgroundChanged(): void {
    if (this.inBackground) { this.flushProgress(); this.activitySince = 0; }
    else if (this.readerVisible && this.loadState === 'ready') { this.activitySince = Date.now(); }
  }
  private async persistOptions(): Promise<void> {
    this.options.mode = this.mode; this.options.preload = this.preloadCount; this.options.paper = this.bgPaper;
    try { await readerPreferences.save(this.aid, this.options); }
    catch (e) { this.toastMsg(`保存阅读偏好失败：${errorMessage(e as Error)}`); }
  }
  private async toggleBookmark(): Promise<void> {
    try { await readerPreferences.toggleBookmark(this.buildProgress()); this.bookmarks = await readerPreferences.bookmarks(this.aid); }
    catch (e) { this.toastMsg(errorMessage(e as Error)); }
  }
  private measuredPage(filename: string, aspect: number): void {
    if (aspect > 1.2 && !this.widePages.has(filename)) {
      this.widePages.add(filename); this.buildSpreads(); this.scrollToPageDelayed(this.currentPage);
    }
  }
  private pageFailed(filename: string, error: Error): void {
    if (this.pages[this.currentPage] === filename && !this.sliderDragging) { this.tryFallback(error, false); }
  }
  private async tryFallback(error: Error, fatalIfNoSource: boolean = true): Promise<boolean> {
    if (this.switchingSource || this.destroyed || !this.readerVisible || this.currentAlbum === null) { return false; }
    if (/登录|认证|401|403/.test(error.message)) {
      if (fatalIfNoSource) {
        this.errorMsg = error.message;
        this.hudVisible = true;
      }
      return false;
    }
    const chapter: Chapter | undefined = this.chapters[this.chapterIndex];
    if (chapter === undefined) { return false; }
    const token: number = this.chapterToken;
    this.switchingSource = true;
    this.attemptedSources.add(this.aid);
    try {
      const result: SourceSwitchResult = await fallbackSource(this.currentAlbum, chapter, this.currentPage,
        this.pages.length || (await readProgressStore.get(this.aid))?.totalPages || 0,
        this.attemptedSources, (): boolean => token === this.chapterToken && !this.destroyed && this.readerVisible);
      if (token !== this.chapterToken || this.destroyed) { return false; }
      this.flushProgress();
      await readProgressStore.save(switchedProgress(result));
      if (token !== this.chapterToken || this.destroyed || !this.readerVisible) { return false; }
      await library.activate(result.album.id);
      if (token !== this.chapterToken || this.destroyed || !this.readerVisible) { return false; }
      this.albumToken++;
      this.pages = []; this.aid = result.album.id; this.applyAlbum(result.album);
      await this.loadPrefs();
      if (token !== this.chapterToken || this.destroyed || !this.readerVisible) { return false; }
      await this.loadChapter(result.album.episodes.findIndex((c: Chapter) => c.id === result.chapter.id), result.page, true);
      this.toastMsg(result.proportional ? '已切换书源，已按阅读比例定位' : '已切换到可用书源');
      return true;
    } catch (e) {
      if (token === this.chapterToken && fatalIfNoSource) {
        this.errorMsg = `${error.message}；${errorMessage(e as Error)}`;
        this.loadState = 'error';
        this.hudVisible = true;
      }
      return false;
    } finally { this.switchingSource = false; }
  }

  // ───────────────────────── 初始化─────────────────────────

  private initAfterParams(): void {
    this.measureSafeAreas().catch((e: Error): void => {
    });
    this.loadPrefs().catch((e: Error): void => {
    });
    this.loadAlbum().catch((e: Error): void => {
    });
  }

  private async loadPrefs(): Promise<void> {
    try {
      const aid: string = this.aid;
      const prefs: Prefs = await Prefs.getInstance();
      const options: ReaderOptions = await readerPreferences.load(aid);
      const key: string = await readerPreferences.key(aid);
      const bookmarks: Array<ReadingProgress> = await readerPreferences.bookmarks(aid);
      const brightness: number = await prefs.brightness();
      const autoCache: boolean = await prefs.autoCache();
      if (this.destroyed || aid !== this.aid) { return; }
      this.options = options;
      this.activityBookKey = key;
      this.bookmarks = bookmarks;
      const m: string = this.options.mode;
      if (m === 'vertical' || m === 'pagedVertical' || m === 'horizontal' || m === 'rtl' || m === 'double') {
        this.mode = m;
      } else {
        this.mode = 'vertical';
      }
      this.buildSpreads(); // 偏好模式可能晚于章节列表就绪：补一次跨页序列重建
      this.preloadCount = this.clampPreload(this.options.preload);
      this.bgPaper = this.options.paper;
      this.applySystemBarDarkText(this.bgPaper).catch((e: Error): void => {
      });
      this.brightnessValue = brightness >= 0 && brightness <= 100 ? brightness : 100;
      this.autoCacheOn = autoCache;
    } catch (e) {
      this.toastMsg(`读取阅读偏好失败：${errorMessage(e as Error)}`);
    }
  }

  private async measureSafeAreas(): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(getAppContext());
      const top: window.AvoidArea = await win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const bottom: window.AvoidArea =
        await win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const t: number = this.getUIContext().px2vp(top.topRect.height);
      const b: number = this.getUIContext().px2vp(bottom.bottomRect.height);
      if (t >= 0) {
        this.topSafeVp = t;
      }
      if (b >= 0) {
        this.bottomSafeVp = b;
      }
    } catch (e) {
      // 量取失败保持默认（全屏沉浸下 HUD 仅短暂偏移）
    }
  }

  /** 米黄背景时切深色状态栏图标（EntryAbility 默认浅色主题深字）；退出阅读器恢复 */
  private async applySystemBarDarkText(darkText: boolean): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(getAppContext());
      await win.setWindowSystemBarProperties({ statusBarContentColor: darkText ? '#1E293B' : '#FFFFFF' });
    } catch (e) {
      // 系统栏配置失败不影响阅读
    }
  }

  /** 退出阅读器：状态栏文字恢复为当前应用主题应有形态（浅色主题→深字，深色主题→白字） */
  private restoreSystemBarToTheme(): void {
    const isDark: boolean = AppStorage.get<boolean>(IS_DARK_MODE_KEY) ?? false;
    this.applySystemBarDarkText(!isDark).catch((e: Error): void => {
    });
  }

  /** 已有目录可先阅读，刷新结果必须仍属于当前作品。 */
  private async loadAlbum(): Promise<void> {
    const token: number = ++this.albumToken;
    const aid: string = this.aid;
    let cachedAlbum: Album | null = null;
    try {
      cachedAlbum = await albumCacheStore.get(aid);
    } catch (e) {
      cachedAlbum = null;
    }
    if (token !== this.albumToken || aid !== this.aid || this.destroyed) { return; }
    if (cachedAlbum !== null) {
      this.applyAlbum(cachedAlbum);
      this.beginReading();
    }
    try {
      const fresh: Album = await jmApi.album(aid);
      if (token !== this.albumToken || aid !== this.aid || this.destroyed) { return; }
      this.applyAlbum(fresh);
      albumCacheStore.put(fresh).catch((e: Error): void => {
      });
      this.beginReading();
    } catch (e) {
      if (token !== this.albumToken || aid !== this.aid || this.destroyed) { return; }
      if (cachedAlbum === null) {
        if (!this.readingStarted) {
          this.loadState = 'error';
          this.errorMsg = errorMessage(e as Error);
          this.hudVisible = true;
        }
      }
    }
  }

  private applyAlbum(a: Album): void {
    this.currentAlbum = a;
    if (a.name !== '') {
      this.albumTitle = a.name;
    }
    const authors: string = a.author.join(' · ');
    if (authors !== '') {
      this.authorLine = authors;
    }
    if (a.episodes.length > 0) {
      if (this.readingStarted) {
        // 网络刷新后的目录以章 id 对齐当前阅读位置
        const curId: string = this.currentChapterId();
        const idx: number = curId !== '' ? this.indexOfChapterIn(a.episodes, curId) : -1;
        this.chapters = a.episodes;
        this.chapterSource.setList(a.episodes);
        if (idx >= 0) {
          this.chapterIndex = idx;
        }
      } else {
        this.chapters = a.episodes;
        this.chapterSource.setList(a.episodes);
      }
    }
  }

  /** 进入定位：路由参数优先，仅 aid 时读精确进度续读 */
  private beginReading(): void {
    if (this.readingStarted) {
      return;
    }
    if (this.chapters.length === 0) {
      this.loadState = 'error';
      this.errorMsg = '本作品暂无可阅读的章节';
      this.hudVisible = true;
      return;
    }
    this.readingStarted = true;
    if (this.routeChapterIndex >= 0 && this.routeChapterIndex < this.chapters.length) {
      this.resolveStart(this.routeChapterIndex, this.routePage >= 0 ? this.routePage : 0);
      return;
    }
    if (this.routeChapterId !== '') {
      const found: number = this.indexOfChapter(this.routeChapterId);
      this.resolveStart(found >= 0 ? found : 0, this.routePage >= 0 ? this.routePage : 0);
      return;
    }
    const aid: string = this.aid;
    const token: number = this.albumToken;
    readProgressStore.get(aid).then((p: ReadingProgress | null): void => {
      if (this.readingResolved || aid !== this.aid || token !== this.albumToken || this.destroyed) {
        return;
      }
      if (p === null) {
        this.resolveStart(0, 0);
        return;
      }
      const byId: number = p.chapterId !== '' ? this.indexOfChapter(p.chapterId) : -1;
      const idx: number = byId >= 0 ? byId : (p.chapterIndex >= 0 && p.chapterIndex < this.chapters.length
        ? p.chapterIndex : 0);
      const page: number = this.routePage >= 0 ? this.routePage : p.page;
      this.resolveStart(idx, page);
    }).catch((e: Error): void => {
      if (aid === this.aid && token === this.albumToken && !this.destroyed) {
        this.loadState = 'error'; this.errorMsg = `读取阅读进度失败：${errorMessage(e)}`; this.hudVisible = true;
      }
    });
  }

  private resolveStart(chapterIdx: number, page: number): void {
    if (this.readingResolved) {
      return;
    }
    this.readingResolved = true;
    this.loadChapter(chapterIdx, page).catch((e: Error): void => {
    });
  }

  // ───────────────────────── 章节加载─────────────────────────

  private async loadChapter(chapterIdx: number, targetPage: number, preserveAttempts: boolean = false): Promise<void> {
    const ch: Chapter | undefined = this.chapters[chapterIdx];
    if (ch === undefined) {
      this.loadState = 'error';
      this.errorMsg = '章节不存在';
      this.hudVisible = true;
      return;
    }
    // 先落盘当前话进度，再清空 pages。否则节流中的保存会看到空列表直接返回，目录切章/加载中返回会丢进度
    this.flushProgress();
    this.activitySince = 0;
    if (!preserveAttempts) { this.attemptedSources.clear(); }
    this.widePages.clear();
    this.chapterIndex = chapterIdx;
    this.loadState = 'loading';
    this.errorMsg = '';
    this.scrambleId = SCRAMBLE_DEFAULT;
    this.prefetched.clear();
    this.pages = [];
    this.resetZoom(false); // 切章复位缩放
    this.pagesSource.setList(this.pages);
    this.buildSpreads();
    const token: number = ++this.chapterToken;
    const initialTarget: number = targetPage;

    // 1) 秒开：章节图片列表缓存
    let cached: Array<string> | null = null;
    try {
      cached = await pagesCacheStore.get(ch.id);
    } catch (e) {
      cached = null;
    }
    if (token !== this.chapterToken) {
      return;
    }
    if (cached !== null && cached.length > 0) {
      this.pages = cached;
      this.pagesSource.setList(cached);
      this.buildSpreads();
      const t: number = this.clampPage(initialTarget, cached.length);
      this.currentPage = t;
      this.loadState = 'ready';
      this.scrollToPageDelayed(t);
      this.prefetchAhead(t);
    }

    // 2) 网络刷新：先撤 loading 再定位（防「布局等 loading、定位等布局」死锁，ReaderScreen.kt:177-182）
    try {
      const fresh: Array<string> = await jmApi.chapterImages(ch.id);
      if (token !== this.chapterToken) {
        return;
      }
      const hadCache: boolean = cached !== null && cached.length > 0;
      const changed: boolean = !hadCache || !this.samePages(fresh, cached as Array<string>);
      if (fresh.length > 0 && changed) {
        this.pages = fresh;
        this.pagesSource.setList(fresh);
        this.buildSpreads();
        const t: number = this.clampPage(initialTarget, fresh.length);
        this.currentPage = t;
        this.loadState = 'ready';
        pagesCacheStore.put(ch.id, fresh).catch((e: Error): void => {
        });
        this.prefetched.clear();
        this.scrollToPageDelayed(t);
        this.prefetchAhead(t);
      } else {
        this.loadState = 'ready';
      }
    } catch (e) {
      if (token !== this.chapterToken) {
        return;
      }
      if (cached === null || cached.length === 0) {
        this.currentPage = initialTarget;
        if (await this.tryFallback(e as Error)) { return; }
        if (token !== this.chapterToken || this.destroyed) { return; }
        this.loadState = 'error';
        if (this.errorMsg === '') { this.errorMsg = errorMessage(e as Error); }
        this.hudVisible = true;
        return;
      }
      this.loadState = 'ready'; // 失败保留缓存继续阅读
    }

    // 3) 乱序参数后台获取（默认 220980 与云端值算法等价）
    try {
      const sid: number = await jmApi.scrambleId(ch.id);
      if (token !== this.chapterToken) {
        return;
      }
      if (sid !== this.scrambleId) {
        this.scrambleId = sid;
        this.prefetched.clear();
        this.prefetchAhead(this.currentPage);
      }
    } catch (e) {
      // 保留默认值
    }

    // 4) 预加载下一章（目录 + 前 5 页）
    this.preloadNextChapter().catch((e: Error): void => {
    });
    this.saveProgressNow();
    library.activate(this.aid).catch((e: Error) => { this.toastMsg(`保存当前书源失败：${errorMessage(e)}`); });
    if (!this.inBackground && this.readerVisible) { this.activitySince = Date.now(); }
  }

  private retryLoad(): void {
    if (this.chapters.length > 0) {
      this.loadChapter(this.chapterIndex, 0).catch((e: Error): void => {
      });
    } else {
      this.readingStarted = false;
      this.readingResolved = false;
      this.loadAlbum().catch((e: Error): void => {
      });
    }
  }

  // ───────────────────────── 预加载─────────────────────────

  /** 恒预加载当前页后 N 页（N = 预加载档位；受 autoCache 开关控制，ReaderScreen.kt:120-134） */
  private prefetchAhead(fromIndex: number): void {
    if (!this.autoCacheOn) {
      return;
    }
    if (this.pages.length === 0) {
      return;
    }
    const photoId: string = this.currentChapterId();
    if (photoId === '') {
      return;
    }
    const last: number = Math.min(this.pages.length - 1, fromIndex + this.preloadCount);
    for (let i: number = fromIndex + 1; i <= last; i++) {
      const filename: string = this.pages[i];
      const key: string = `${photoId}/${filename}@${this.scrambleId}`;
      if (this.prefetched.has(key)) {
        continue;
      }
      this.prefetched.add(key);
      this.prefetchOne(photoId, filename, key);
    }
  }

  private async prefetchOne(photoId: string, filename: string, key: string): Promise<void> {
    try {
      const pm: image.PixelMap | null =
        await loadPagePixelMap(photoId, filename, this.scrambleId, this.targetWidthPx);
      if (pm !== null) {
        releasePagePixelMap(pm); // 借出即归还：位图留在 96MB 零拷贝 LRU 供热区秒开
      }
    } catch (e) {
      this.prefetched.delete(key);
    }
  }

  /** 下一章预载：目录（缓存优先）+ scrambleId + 前 5 页字节入缓存（ReaderScreen.kt:211-225） */
  private async preloadNextChapter(): Promise<void> {
    if (!this.autoCacheOn) {
      return;
    }
    const next: Chapter | undefined = this.chapters[this.chapterIndex + 1];
    if (next === undefined) {
      return;
    }
    try {
      let list: Array<string> | null = null;
      try {
        list = await pagesCacheStore.get(next.id);
      } catch (e) {
        list = null;
      }
      if (list === null || list.length === 0) {
        list = await jmApi.chapterImages(next.id);
        if (list.length > 0) {
          pagesCacheStore.put(next.id, list).catch((e: Error): void => {
          });
        }
      }
      if (list.length === 0) {
        return;
      }
      const sid: number = await jmApi.scrambleId(next.id);
      const count: number = Math.min(5, list.length);
      for (let i: number = 0; i < count; i++) {
        const pm: image.PixelMap | null =
          await loadPagePixelMap(next.id, list[i], sid, this.targetWidthPx);
        if (pm !== null) {
          releasePagePixelMap(pm);
        }
      }
    } catch (e) {
      // 下一章预载失败静默
    }
  }

  // ───────────────────────── 阅读进度─────────────────────────

  private buildProgress(): ReadingProgress {
    const progress: ReadingProgress = new ReadingProgress();
    progress.aid = this.aid;
    progress.chapterId = this.currentChapterId();
    progress.chapterIndex = this.chapterIndex;
    progress.page = this.currentPage;
    progress.totalPages = this.pages.length;
    progress.title = this.albumTitle;
    progress.author = this.authorLine;
    progress.coverUrl = jmApi.albumThumbUrl(this.aid);
    return progress;
  }

  private saveProgressNow(): void {
    if (this.aid === '' || this.pages.length === 0) {
      return;
    }
    const now: number = Date.now();
    const elapsed: number = this.activitySince > 0 ? Math.max(0, now - this.activitySince) : 0;
    if (this.activitySince > 0) { this.activitySince = now; }
    readingActivity.record(this.activityBookKey || this.aid, `${this.currentChapterId()}~${this.currentPage}`, elapsed)
      .catch((e: Error) => { this.toastMsg(`统计保存失败：${errorMessage(e)}`); });
    readProgressStore.save(this.buildProgress()).catch((e: Error): void => { this.toastMsg(`进度保存失败：${errorMessage(e)}`); });
    this.lastSavedAt = Date.now();
  }

  /** 立刻提交节流中的进度（切章、退出、销毁前调用，避免定时器落到已清空的 pages） */
  private flushProgress(): void {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    this.saveProgressNow();
  }

  private scheduleProgressSave(): void {
    const now: number = Date.now();
    if (now - this.lastSavedAt >= SAVE_THROTTLE_MS) {
      this.saveProgressNow();
      return;
    }
    if (this.saveTimer >= 0) {
      return;
    }
    const delay: number = SAVE_THROTTLE_MS - (now - this.lastSavedAt);
    this.saveTimer = setTimeout((): void => {
      this.saveTimer = -1;
      this.saveProgressNow();
    }, delay);
  }

  // ───────────────────────── 翻页 / 热区 / 模式─────────────────────────

  /** 点按三分：中央=HUD；两侧=翻页（条漫=滚动一屏）。方向按 uiux §四.3：点左=下一页、点右=上一页，日漫右翻镜像 */
  private handleCanvasClick(x: number, y: number): void {
    const w: number = this.canvasWidthVp;
    if (w <= 0) {
      this.toggleHud();
      return;
    }
    const col: number = Math.max(0, Math.min(2, Math.floor(x / (w / 3))));
    const row: number = Math.max(0, Math.min(2, Math.floor(y / (this.canvasHeightVp / 3))));
    const action: number = this.options.taps[row * 3 + col];
    if (action === 0) { this.toggleHud(); }
    else if (action === 1) { this.turnPage(this.mode === 'rtl'); }
    else if (action === 2) { this.turnPage(this.mode !== 'rtl'); }
    else { this.goChapter(action === 3 ? -1 : 1); }
  }

  private toggleHud(): void {
    this.hudVisible = !this.hudVisible;
    if (!this.hudVisible) {
      this.panel = 'none';
    }
  }

  // ───────────────────────── 双指缩放─────────────────────────

  /**
   * 缩放/平移边界：放大后内容超出画布的部分允许平移看到，偏移量被夹在
   * ±(画布尺寸 × (scale-1) / 2)（以缩放中心为画布中心的简化口径）；越界回弹。
   */
  private maxZoomOffsetX(): number {
    return Math.max(0, (this.canvasWidthVp * (this.zoomScale - 1)) / 2);
  }

  private maxZoomOffsetY(): number {
    return Math.max(0, (this.canvasHeightVp * (this.zoomScale - 1)) / 2);
  }

  /** 松手边界回弹：越界偏移动画夹回；scale<1 回弹到 1 */
  private bounceZoomBack(): void {
    const targetScale: number = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, this.zoomScale));
    const maxX: number = Math.max(0, (this.canvasWidthVp * (targetScale - 1)) / 2);
    const maxY: number = Math.max(0, (this.canvasHeightVp * (targetScale - 1)) / 2);
    const targetX: number = Math.max(-maxX, Math.min(maxX, this.zoomOffsetX));
    const targetY: number = Math.max(-maxY, Math.min(maxY, this.zoomOffsetY));
    if (targetScale === this.zoomScale && targetX === this.zoomOffsetX && targetY === this.zoomOffsetY) {
      return;
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.Friction }, (): void => {
      this.zoomScale = targetScale;
      this.zoomOffsetX = targetX;
      this.zoomOffsetY = targetY;
    });
  }

  /** HUD 顶栏「x.x · 重置」：复位缩放与平移（ReaderScreen.kt:246-259） */
  private resetZoom(animated: boolean): void {
    if (this.zoomScale === ZOOM_MIN && this.zoomOffsetX === 0 && this.zoomOffsetY === 0) {
      return;
    }
    if (animated) {
      this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
        this.zoomScale = ZOOM_MIN;
        this.zoomOffsetX = 0;
        this.zoomOffsetY = 0;
      });
    } else {
      this.zoomScale = ZOOM_MIN;
      this.zoomOffsetX = 0;
      this.zoomOffsetY = 0;
    }
  }

  private onPinchStart(event: GestureEvent): void {
    this.pinchStartScale = this.zoomScale;
  }

  private onPinchUpdate(event: GestureEvent): void {
    // 实时缩放硬夹 [1,5]（ReaderScreen.kt:104-118 transformable 语义）
    const raw: number = this.pinchStartScale * event.scale;
    this.zoomScale = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, raw));
  }

  private onTwoFingerPanStart(event: GestureEvent): void {
    this.panStartX = this.zoomOffsetX;
    this.panStartY = this.zoomOffsetY;
  }

  private onTwoFingerPanUpdate(event: GestureEvent): void {
    this.zoomOffsetX = this.panStartX + event.offsetX;
    this.zoomOffsetY = this.panStartY + event.offsetY;
  }

  private turnPage(forward: boolean): void {
    if (this.pages.length === 0) {
      return;
    }
    if (this.mode === 'vertical') {
      this.scrollScreen(forward);
      return;
    }
    if (this.mode === 'double') {
      const index: number = this.pageToSpreadIndex(this.currentPage) + (forward ? 1 : -1);
      if (index < 0 || index >= this.spreadsCache.length) { this.toastMsg('已到本章边界'); return; }
      this.jumpToPage(this.spreadIndexToPage(index)); return;
    }
    const target: number = this.currentPage + (forward ? 1 : -1);
    if (target < 0) {
      this.toastMsg('已经是第一页了');
      return;
    }
    if (target >= this.pages.length) {
      if (this.chapterIndex < this.chapters.length - 1) {
        this.toastMsg('本章完，可点「下一话」继续');
      } else {
        this.toastMsg('已经是最后一页了');
      }
      return;
    }
    this.jumpToPage(target);
  }

  /** 条漫模式两侧点按滚动一屏（0.85 屏，避免视觉跳跃） */
  private scrollScreen(forward: boolean): void {
    if (this.canvasHeightVp > 0) {
      const cur: OffsetResult = this.listScroller.currentOffset();
      const delta: number = this.canvasHeightVp * 0.85;
      const target: number = forward ? cur.yOffset + delta : Math.max(0, cur.yOffset - delta);
      this.listScroller.scrollTo({
        xOffset: 0,
        yOffset: target,
        animation: { duration: 220, curve: Curve.EaseOut }
      });
    } else {
      const idx: number = forward ? this.currentPage + 1 : this.currentPage - 1;
      if (idx >= 0 && idx < this.pages.length) {
        this.jumpToPage(idx);
      }
    }
  }

  private jumpToPage(page: number): void {
    const total: number = this.pages.length;
    if (total === 0) {
      return;
    }
    const p: number = this.clampPage(page, total);
    this.currentPage = p;
    if (this.mode === 'vertical') {
      this.listScroller.scrollToIndex(p, false);
    } else {
      this.swiperController.changeIndex(this.pageToSpreadIndex(p), false);
    }
    this.scheduleProgressSave();
  }

  /** 非阻塞定位：章节就绪后延迟滚动（等列表/翻页器完成布局）。过期章节的定时器不再跳页 */
  private scrollToPageDelayed(page: number): void {
    const token: number = this.chapterToken;
    setTimeout((): void => {
      if (this.destroyed || token !== this.chapterToken) {
        return;
      }
      this.jumpToPage(page);
    }, 120);
  }

  private switchMode(m: ReaderMode): void {
    if (this.mode === m) {
      this.panel = 'none';
      return;
    }
    const keepPage: number = this.currentPage;
    this.mode = m;
    this.panel = 'none';
    this.buildSpreads(); // 跨页序列随模式重建（rtl 倒排 / double 双页并排，评审 Step4）
    this.persistOptions();
    const token: number = this.chapterToken;
    setTimeout((): void => {
      if (this.destroyed || token !== this.chapterToken) {
        return;
      }
      if (m === 'vertical') {
        this.listScroller.scrollToIndex(keepPage, false);
      } else {
        this.swiperController.changeIndex(this.pageToSpreadIndex(keepPage), false);
      }
    }, 120);
  }

  private setPreload(n: number): void {
    this.preloadCount = n;
    this.persistOptions();
  }

  private toggleBackground(paper: boolean): void {
    if (this.bgPaper === paper) {
      return;
    }
    this.bgPaper = paper;
    // 评审 Step4：米黄背景偏好持久化（退出再进保持）
    this.persistOptions();
    this.applySystemBarDarkText(paper).catch((e: Error): void => {
    });
  }

  private goChapter(delta: number): void {
    const target: number = this.chapterIndex + delta;
    if (target < 0) {
      this.toastMsg('已经是第一话了');
      return;
    }
    if (target >= this.chapters.length) {
      this.toastMsg('已经是最后一话了');
      return;
    }
    this.saveProgressNow();
    this.loadChapter(target, 0).catch((e: Error): void => {
    });
  }

  private goBack(): void {
    this.flushProgress();
    this.pageStack.pop();
  }

  private toastMsg(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1600, bottom: '35%' });
    } catch (e) {
      // Toast 失败可忽略
    }
  }

  // ───────────────────────── 辅助 ─────────────────────────

  private currentChapterId(): string {
    const ch: Chapter | undefined = this.chapters[this.chapterIndex];
    return ch === undefined ? '' : ch.id;
  }

  private chapterTitle(): string {
    const ch: Chapter | undefined = this.chapters[this.chapterIndex];
    if (ch !== undefined && ch.title !== '') {
      return ch.title;
    }
    return `第 ${this.chapterIndex + 1} 話`;
  }

  private modeShortLabel(): string {
    if (this.mode === 'vertical') {
      return '条漫';
    }
    if (this.mode === 'horizontal') {
      return '翻页';
    }
    if (this.mode === 'pagedVertical') { return '纵翻'; }
    if (this.mode === 'rtl') {
      return '右翻';
    }
    return '双页';
  }

  // ───────────────────────── 跨页序列（评审 Step4：rtl 右起 / double 双页并排）─────────────────────────

  /**
   * 重建横向翻页跨页序列：horizontal=单页顺排；rtl=单页倒排（第 1 页在右，手指右滑=下一页，
   * 与三分热区镜像一致）；double=封面单独一屏 + 后续两两并排。
   */
  private buildSpreads(): void {
    const out: Array<Array<string>> = [];
    if (this.mode === 'rtl') {
      for (let i: number = this.pages.length - 1; i >= 0; i--) {
        out.push([this.pages[i]]);
      }
    } else if (this.mode === 'double') {
      out.push(...makeSpreads(this.pages, this.widePages, this.options.coverOffset));
    } else {
      for (const p of this.pages) {
        out.push([p]);
      }
    }
    this.spreadsCache = out;
    this.spreadSource.setList(out);
  }

  /** 页码 → 跨页序号（Swiper index / changeIndex 用） */
  private pageToSpreadIndex(page: number): number {
    const n: number = this.spreadsCache.length;
    if (n === 0) {
      return 0;
    }
    if (this.mode === 'rtl') {
      const p: number = this.clampPage(page, this.pages.length);
      return Math.max(0, Math.min(n - 1, this.pages.length - 1 - p));
    }
    if (this.mode === 'double') {
      return spreadForPage(this.spreadsCache, this.clampPage(page, this.pages.length));
    }
    return this.clampPage(page, n);
  }

  /** 跨页序号 → 页码。双页模式记该跨页最后一页，进度和滑条才对得上右侧正在看的页 */
  private spreadIndexToPage(index: number): number {
    const n: number = this.spreadsCache.length;
    if (n === 0) {
      return 0;
    }
    const i: number = Math.max(0, Math.min(n - 1, index));
    if (this.mode === 'rtl') {
      return Math.max(0, Math.min(this.pages.length - 1, this.pages.length - 1 - i));
    }
    if (this.mode === 'double') {
      return lastPageInSpread(this.spreadsCache, i);
    }
    const first: string | undefined = this.spreadsCache[i][0];
    if (first === undefined) {
      return 0;
    }
    const idx: number = this.pages.indexOf(first);
    return idx >= 0 ? idx : 0;
  }

  private indexOfChapter(id: string): number {
    return this.indexOfChapterIn(this.chapters, id);
  }

  private indexOfChapterIn(list: Array<Chapter>, id: string): number {
    for (let i: number = 0; i < list.length; i++) {
      if (list[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  private clampPage(page: number, total: number): number {
    if (total <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(page, total - 1));
  }

  private clampPreload(n: number): number {
    return Math.max(1, Math.min(8, Math.floor(n)));
  }

  private samePages(a: Array<string>, b: Array<string>): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i: number = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }

  // ───────────────────────── 画布─────────────────────────

  @Builder
  private VerticalList() {
    List({ scroller: this.listScroller }) {
      LazyForEach(this.pagesSource, (filename: string) => {
        ListItem() {
          ReaderImageItem({
            photoId: this.currentChapterId(),
            filename: filename,
            scrambleId: this.scrambleId,
            targetWidth: this.targetWidthPx,
            fitScreen: false,
            cropWhite: this.options.cropWhite,
            onFailure: (filename: string, error: Error): void => { this.pageFailed(filename, error); }
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
                  this.goChapter(-1);
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
                  this.goChapter(1);
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
        this.prefetchAhead(first);
        this.scheduleProgressSave();
      }
    })
    .onClick((event: ClickEvent) => {
      this.handleCanvasClick(event.x, event.y);
    })
  }

  /** 横向翻页（评审 Step4）：跨页序列渲染——horizontal 单页顺排 / rtl 倒排右起 / double 双页并排 */
  @Builder
  private HorizontalSwiper() {
    Swiper(this.swiperController) {
      LazyForEach(this.spreadSource, (spread: Array<string>) => {
        Row() {
          ForEach(spread, (filename: string) => {
            Column() {
              ReaderImageItem({
                photoId: this.currentChapterId(),
                filename: filename,
                scrambleId: this.scrambleId,
                targetWidth: this.targetWidthPx,
                fitScreen: true,
                cropWhite: this.options.cropWhite,
                onFailure: (filename: string, error: Error): void => { this.pageFailed(filename, error); },
                onMeasured: (filename: string, aspect: number): void => { this.measuredPage(filename, aspect); }
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
    .index(Math.max(0, this.pageToSpreadIndex(this.currentPage)))
    .loop(false)
    .vertical(this.mode === 'pagedVertical')
    .indicator(false)
    .duration(240)
    .cachedCount(Math.max(2, this.preloadCount))
    .width('100%')
    .height('100%')
    .onChange((index: number) => {
      const page: number = this.spreadIndexToPage(index);
      if (page !== this.currentPage) {
        this.currentPage = page;
      }
      this.prefetchAhead(page);
      this.scheduleProgressSave();
    })
    .onClick((event: ClickEvent) => {
      this.handleCanvasClick(event.x, event.y);
    })
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

  private isCurrentPageBookmarked(): boolean {
    const chId: string = this.currentChapterId();
    return this.bookmarks.some((b: ReadingProgress) => b.chapterId === chId && b.page === this.currentPage);
  }

  private tapActionLabel(action: number): string {
    const labels: Array<string> = ['呼出菜单', '上一页', '下一页', '上一话', '下一话'];
    return labels[action] ?? '呼出菜单';
  }

  private tapActionColor(action: number): ResourceColor {
    if (action === 0) {
      return PRIMARY;
    }
    if (action === 2 || action === 4) {
      return ACCENT;
    }
    return 'rgba(255,255,255,0.22)';
  }

  @Builder
  private ErrorView() {
    Column({ space: 14 }) {
      EmptyView({
        message: this.errorMsg !== '' ? this.errorMsg : '加载失败，请检查网络后重试',
        retryText: '重试当前章节',
        showRetry: true,
        onRetry: (): void => {
          this.retryLoad();
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

  // ───────────────────────── HUD─────────────────────────

  @Builder
  private TopHud() {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontColor([Color.White])
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor('rgba(255,255,255,0.12)')
      .border({ width: 0.5, color: 'rgba(255,255,255,0.18)' })
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .onClick(() => {
        this.goBack();
      })

      Column({ space: 2 }) {
        Text(this.chapterTitle())
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.pages.length > 0) {
          Text(`${this.albumTitle ? this.albumTitle + ' · ' : ''}P.${Math.min(this.currentPage + 1, this.pages.length)}/${this.pages.length}`)
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.68)')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 缩放重置入口
      if (this.pages.length > 0 && this.zoomScale > ZOOM_MIN) {
        Text(`${this.zoomScale.toFixed(1)}x 复位`)
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor(PRIMARY)
          .onClick(() => {
            this.resetZoom(true);
          })
      }

      // 书签纯图标按钮
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(this.isCurrentPageBookmarked() ? $r('sys.symbol.bookmark_fill') : $r('sys.symbol.bookmark'))
          .fontSize(17)
          .fontColor([this.isCurrentPageBookmarked() ? PRIMARY : Color.White])
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.isCurrentPageBookmarked() ? 'rgba(58,122,254,0.22)' : 'rgba(255,255,255,0.12)')
      .border({ width: 0.5, color: this.isCurrentPageBookmarked() ? PRIMARY : 'rgba(255,255,255,0.18)' })
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .onClick(() => {
        this.toggleBookmark();
      })

      if (this.pages.length > 0) {
        Text(this.modeShortLabel())
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .borderRadius(16)
          .backgroundColor(PRIMARY)
          .onClick(() => {
            this.panel = this.panel === 'mode' ? 'none' : 'mode';
          })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: this.topSafeVp + 8, bottom: 10 })
    .backgroundColor(MASK_DARK)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK }))
  }

  @Builder
  private ModePanel() {
    Column({ space: 6 }) {
      ModeOptionRow({
        label: '纵向条漫', sub: '上下连续瀑布流滚动', selected: this.mode === 'vertical',
        onPick: (): void => {
          this.switchMode('vertical');
        }
      })
      ModeOptionRow({
        label: '纵向翻页', sub: '上下整屏滑动逐页阅读', selected: this.mode === 'pagedVertical',
        onPick: (): void => { this.switchMode('pagedVertical'); }
      })
      ModeOptionRow({
        label: '左右翻页', sub: '从左向右单页整屏适配', selected: this.mode === 'horizontal',
        onPick: (): void => {
          this.switchMode('horizontal');
        }
      })
      ModeOptionRow({
        label: '日漫右翻', sub: '从右向左的自然手势翻页（进度条自动镜像）', selected: this.mode === 'rtl',
        onPick: (): void => {
          this.switchMode('rtl');
        }
      })
      ModeOptionRow({
        label: '双页拼合', sub: '封面单页 + 跨页自动识别并排', selected: this.mode === 'double',
        onPick: (): void => {
          this.switchMode('double');
        }
      })
    }
    .width('100%')
    .padding(12)
    .borderRadius(18)
    .backgroundColor(PANEL_BG)
    .border({ width: 0.5, color: 'rgba(255,255,255,0.12)' })
  }

  @Builder
  private DisplayPanel() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text('亮度')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F2F2F4')
          .width(38)
        Slider({ value: this.brightnessValue, min: 10, max: 100, step: 1, style: SliderStyle.OutSet })
          .selectedColor(PRIMARY)
          .trackColor('rgba(255,255,255,0.25)')
          .blockColor(Color.White)
          .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
          .layoutWeight(1)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.brightnessValue = value;
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              Prefs.getInstance()
                .then((p: Prefs): Promise<void> => p.setBrightness(value))
                .catch((e: Error): void => {
                });
            }
          })
        Text(`${Math.round(this.brightnessValue)}%`)
          .fontSize(12)
          .fontColor('rgba(255,255,255,0.75)')
          .width(36)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      Row({ space: 10 }) {
        Text('画布')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F2F2F4')
          .width(38)
        ChipOption({
          label: '深色纯黑', selected: !this.bgPaper,
          onTap: (): void => {
            this.toggleBackground(false);
          }
        })
        ChipOption({
          label: '纸质护眼', selected: this.bgPaper,
          onTap: (): void => {
            this.toggleBackground(true);
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius(18)
    .backgroundColor(PANEL_BG)
    .border({ width: 0.5, color: 'rgba(255,255,255,0.12)' })
  }

  @Builder
  private SettingsPanel() {
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Text('双页模式封面独占首页')
            .fontSize(13)
            .fontColor(Color.White)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.options.coverOffset })
            .selectedColor(PRIMARY)
            .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
            .onChange((value: boolean) => {
              this.options.coverOffset = value;
              this.buildSpreads();
              this.scrollToPageDelayed(this.currentPage);
              this.persistOptions();
            })
        }
        .width('100%')

        Row() {
          Text('智能裁切页面四周白边')
            .fontSize(13)
            .fontColor(Color.White)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.options.cropWhite })
            .selectedColor(PRIMARY)
            .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
            .onChange((value: boolean) => {
              this.options.cropWhite = value;
              this.persistOptions();
            })
        }
        .width('100%')

        Row() {
          Text('夜间暖色温护眼滤镜')
            .fontSize(13)
            .fontColor(Color.White)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.options.eyeComfort })
            .selectedColor(PRIMARY)
            .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
            .onChange((value: boolean) => {
              this.options.eyeComfort = value;
              this.persistOptions();
            })
        }
        .width('100%')

        Column({ space: 8 }) {
          Row() {
            Text('九宫格触控热区（点按格子切换动作）')
              .fontSize(12)
              .fontColor('rgba(255,255,255,0.78)')
              .layoutWeight(1)
            Text('恢复默认')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor(PRIMARY)
              .onClick(() => {
                this.options.taps = [1, 0, 2, 1, 0, 2, 1, 0, 2];
                this.persistOptions();
              })
          }
          .width('100%')

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8], (index: number) => {
              Column({ space: 2 }) {
                Text(this.tapActionLabel(this.options.taps[index]))
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
              }
              .width('31.5%')
              .height(38)
              .margin({ bottom: 6 })
              .justifyContent(FlexAlign.Center)
              .borderRadius(10)
              .backgroundColor(this.tapActionColor(this.options.taps[index]))
              .border({ width: 0.5, color: 'rgba(255,255,255,0.16)' })
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
              .onClick(() => {
                const taps: Array<number> = this.options.taps.slice();
                taps[index] = (taps[index] + 1) % 5;
                this.options.taps = taps;
                this.persistOptions();
              })
            }, (index: number) => `tap_${index}_${this.options.taps[index]}`)
          }
          .width('100%')
        }
        .width('100%')

        Column({ space: 8 }) {
          Text('后台预加载页数档位')
            .fontSize(12)
            .fontColor('rgba(255,255,255,0.78)')
            .width('100%')
          Row({ space: 8 }) {
            ChipOption({
              label: '省流 1页', selected: this.preloadCount === 1,
              onTap: (): void => {
                this.setPreload(1);
              }
            })
            ChipOption({
              label: '标准 3页', selected: this.preloadCount === 3,
              onTap: (): void => {
                this.setPreload(3);
              }
            })
            ChipOption({
              label: '进取 5页', selected: this.preloadCount === 5,
              onTap: (): void => {
                this.setPreload(5);
              }
            })
            ChipOption({
              label: '极速 8页', selected: this.preloadCount === 8,
              onTap: (): void => {
                this.setPreload(8);
              }
            })
          }
          .width('100%')
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .borderRadius(18)
      .backgroundColor(PANEL_BG)
      .border({ width: 0.5, color: 'rgba(255,255,255,0.12)' })
    }
    .constraintSize({ maxHeight: 390 })
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  private BottomHud() {
    Column({ space: 12 }) {
      if (this.panel === 'mode') {
        this.ModePanel()
      } else if (this.panel === 'display') {
        this.DisplayPanel()
      } else if (this.panel === 'settings') {
        this.SettingsPanel()
      }
      // 拖动进度条时显示目标页缩略图预览小窗
      if (this.sliderDragging && this.pages.length > 0) {
        Column({ space: 4 }) {
          PageThumbItem({
            photoId: this.currentChapterId(),
            filename: this.pages[this.clampPage(Math.round(this.sliderValue) - 1, this.pages.length)],
            scrambleId: this.scrambleId
          })
            .width(92)
            .height(128)
          Text(`P.${this.clampPage(Math.round(this.sliderValue) - 1, this.pages.length) + 1}`)
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .padding(6)
        .borderRadius(12)
        .backgroundColor(PANEL_BG)
        .border({ width: 0.5, color: 'rgba(255,255,255,0.16)' })
        .alignItems(HorizontalAlign.Center)
      }
      // 进度滑动条 + 上一话/下一话
      if (this.pages.length > 0) {
        Row({ space: 10 }) {
          Button('上一话', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.chapterIndex > 0 ? Color.White : 'rgba(255,255,255,0.35)')
            .backgroundColor('rgba(255,255,255,0.12)')
            .height(34)
            .onClick(() => {
              this.goChapter(-1);
            })

          Column({ space: 2 }) {
            Slider({
              value: this.sliderDragging ? this.sliderValue
                : Math.min(this.currentPage + 1, Math.max(this.pages.length, 1)),
              min: 1,
              max: Math.max(this.pages.length, 1),
              step: 1,
              style: SliderStyle.OutSet,
              reverse: this.mode === 'rtl'
            })
              .selectedColor(PRIMARY)
              .trackColor('rgba(255,255,255,0.22)')
              .blockColor(Color.White)
              .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
              .width('100%')
              .height(28)
              .onChange((value: number, mode: SliderChangeMode) => {
                if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                  this.sliderDragging = true;
                  this.sliderValue = value;
                } else {
                  this.sliderDragging = false;
                  if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                    this.jumpToPage(Math.round(value) - 1);
                  }
                }
              })
            Text(`${this.sliderDragging ? Math.round(this.sliderValue) : Math.min(this.currentPage + 1, this.pages.length)} / ${this.pages.length}${this.mode === 'rtl' ? ' · 右翻' : ''}`)
              .fontSize(11)
              .fontColor('rgba(255,255,255,0.72)')
              .textAlign(TextAlign.Center)
              .width('100%')
          }
          .layoutWeight(1)

          Button('下一话', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.chapterIndex < this.chapters.length - 1
              ? Color.White : 'rgba(255,255,255,0.35)')
            .backgroundColor('rgba(255,255,255,0.12)')
            .height(34)
            .onClick(() => {
              this.goChapter(1);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      // 核心功能入口
      Row({ space: 10 }) {
        HudButton({
          symbol: $r('sys.symbol.list_bullet'),
          label: '目录',
          onTap: (): void => {
            this.sheetVisible = true;
          }
        })
        HudButton({
          symbol: $r('sys.symbol.rectangle_on_rectangle'),
          label: this.modeShortLabel(),
          active: this.panel === 'mode',
          onTap: (): void => {
            this.panel = this.panel === 'mode' ? 'none' : 'mode';
          }
        })
        HudButton({
          symbol: $r('sys.symbol.sun_max'),
          label: '画面',
          active: this.panel === 'display',
          onTap: (): void => {
            this.panel = this.panel === 'display' ? 'none' : 'display';
          }
        })
        HudButton({
          symbol: $r('sys.symbol.gearshape'),
          label: '设置',
          active: this.panel === 'settings',
          onTap: (): void => {
            this.panel = this.panel === 'settings' ? 'none' : 'settings';
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: this.bottomSafeVp + 12 })
    .backgroundColor(MASK_DARK)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK }))
    .onClick(() => {
      // 阻断底栏点击穿透
    })
  }

  @Builder
  private HudLayer() {
    Column() {
      this.TopHud()
      Column()
        .width('100%')
        .layoutWeight(1)
        .onClick(() => {
          if (this.panel !== 'none') {
            this.panel = 'none';
          } else {
            this.hudVisible = false;
          }
        })
      this.BottomHud()
    }
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
  }

  /** HUD 隐藏时的微型常驻页码胶囊 */
  @Builder
  private PagePill() {
    Column() {
      Text(`${this.chapterTitle()} · ${Math.min(this.currentPage + 1, this.pages.length)}/${this.pages.length}`)
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
    Column() {
      if (this.bookmarks.length > 0) {
        Column({ space: 6 }) {
          Text('已存书签')
            .fontSize(12)
            .fontColor('rgba(255,255,255,0.55)')
            .padding({ left: 18 })
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.bookmarks, (bookmark: ReadingProgress) => {
                Text(`第 ${bookmark.chapterIndex + 1} 话 · P.${bookmark.page + 1}`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(14)
                  .backgroundColor('rgba(58,122,254,0.24)')
                  .border({ width: 0.5, color: PRIMARY })
                  .onClick(() => {
                    this.sheetVisible = false;
                    const index: number = this.chapters.findIndex((c: Chapter) => c.id === bookmark.chapterId);
                    if (index >= 0) {
                      this.loadChapter(index, bookmark.page);
                    }
                  })
              }, (bookmark: ReadingProgress) => `${bookmark.chapterId}_${bookmark.page}`)
            }
            .padding({ left: 18, right: 18 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 10 })
        .width('100%')
      }
      Row({ space: 8 }) {
        Text('章节目录')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2F2F4')
          .layoutWeight(1)
        Text(`共 ${this.chapters.length} 话`)
          .fontSize(12)
          .fontColor('rgba(255,255,255,0.55)')
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 14, bottom: 10 })
      List() {
        LazyForEach(this.chapterSource, (ch: Chapter, index?: number) => {
          ListItem() {
            Row({ space: 10 }) {
              Text(`${(index === undefined ? 0 : index) + 1}`)
                .fontSize(13)
                .fontColor('rgba(255,255,255,0.45)')
                .width(34)
              Text(ch.title !== '' ? ch.title : `第 ${(index === undefined ? 0 : index) + 1} 話`)
                .fontSize(14)
                .fontWeight(index === this.chapterIndex ? FontWeight.Bold : FontWeight.Regular)
                .fontColor(index === this.chapterIndex ? '#FFFFFF' : 'rgba(255,255,255,0.75)')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (index === this.chapterIndex) {
                Text('阅读中')
                  .fontSize(10)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(8)
                  .backgroundColor(PRIMARY)
              }
            }
            .width('100%')
            .padding({ left: 18, right: 18, top: 13, bottom: 13 })
            .onClick(() => {
              const idx: number = index === undefined ? 0 : index;
              this.sheetVisible = false;
              if (idx !== this.chapterIndex) {
                this.flushProgress();
                this.loadChapter(idx, 0).catch((e: Error): void => {
                });
              }
            })
          }
        }, (ch: Chapter) => `ch_${ch.id}`)
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: 'rgba(255,255,255,0.08)', startMargin: 18, endMargin: 18 })
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
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
                  this.onPinchStart(event);
                })
                .onActionUpdate((event: GestureEvent): void => {
                  this.onPinchUpdate(event);
                })
                .onActionEnd((): void => {
                  this.bounceZoomBack();
                }),
              PanGesture({ fingers: 2, distance: 1 })
                .onActionStart((event: GestureEvent): void => {
                  this.onTwoFingerPanStart(event);
                })
                .onActionUpdate((event: GestureEvent): void => {
                  this.onTwoFingerPanUpdate(event);
                })
                .onActionEnd((): void => {
                  this.bounceZoomBack();
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
        backgroundColor: '#141722',
        systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK }),
        onDisappear: (): void => {
          this.sheetVisible = false;
        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor(this.bgPaper ? PAPER_BG : READER_BG)
    .onReady((ctx: NavDestinationContext) => {
      if (this.paramReady) {
        return;
      }
      this.paramReady = true;
      const raw: Object | undefined = ctx.pathInfo.param as Object | undefined;
      if (raw !== undefined) {
        const rec: Record<string, Object> | null = asRecord(raw);
        if (rec !== null) {
          this.aid = asString(rec['aid']);
          // 契约参数 chapterId?: number，模型/Store 侧为 string —— asString 容忍数字统一转字符串
          this.routeChapterId = asString(rec['chapterId']);
          this.routeChapterIndex = asNumber(rec['chapterIndex'], -1);
          this.routePage = asNumber(rec['page'], -1);
        }
      }
      this.initAfterParams();
    })
    .onShown(() => {
      this.readerVisible = true;
      if (this.paramReady && this.readingResolved && this.loadState === 'loading') { this.retryLoad(); }
      if (this.loadState === 'ready' && !this.inBackground) { this.activitySince = Date.now(); }
      // 阅读器画布恒深色（米黄除外）：进入即白字/米黄深字（评审 Step2 状态栏联动）
      this.applySystemBarDarkText(this.bgPaper).catch((e: Error): void => {
      });
    })
    .onHidden(() => {
      this.flushProgress();
      this.activitySince = 0; this.readerVisible = false; this.chapterToken++;
    })
    .onWillDisappear(() => {
      this.flushProgress();
      this.restoreSystemBarToTheme();
    })
    .onBackPressed(() => {
      this.flushProgress();
      return false;
    })
  }
}
