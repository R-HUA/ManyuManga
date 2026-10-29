import { UIContext } from '@kit.ArkUI';
import { BasicDataSource } from '../../common/DataSource';
import display from '@ohos.display';
import image from '@ohos.multimedia.image';
import { window } from '@kit.ArkUI';
import { Album, Chapter, MetadataTerm, ReadingProgress, ReaderMode, errorMessage } from '../../models/Models';
import { sourceApi as jmApi } from '../../data/SourceApi';
import { library } from '../../data/Library';
import { readerPreferences, ReaderOptions, ReaderSheetKind } from '../../data/ReaderOptions';
import { readingActivity } from '../../data/ReadingActivity';
import { fallbackSource, SourceSwitchResult } from '../../data/SourceSwitch';
import { clampPage, makeSpreads, spreadForPage, lastPageInSpread } from '../../data/ReaderLayout';
import { loadPagePixelMap, releasePagePixelMap } from '../../data/ImageDecode';
import { isRequestCancelled, RequestAbortGroup } from '../../util/RequestAbort';
import { albumCacheStore, pagesCacheStore, readProgressStore, historyStore } from '../../data/Stores';
import { Prefs, getAppContext } from '../../util/Prefs';
import { IS_DARK_MODE_KEY } from '../../entryability/EntryAbility';
import { ROUTE_PREVIEW, MangaRouteParams } from '../../common/Route';
import { ReaderPanelKind } from './ReaderHud';

/** 默认乱序参数 */
const SCRAMBLE_DEFAULT: number = 220980;
/** 进度节流间隔 ms */
const SAVE_THROTTLE_MS: number = 2000;
/** 缩放范围 */
const ZOOM_MIN: number = 1;
const ZOOM_MAX: number = 5;

/** 页面持有响应式状态，控制器仅通过此契约更新阅读会话。 */
interface ReaderHost {
  pageStack: NavPathStack;
  inBackground: boolean;
  options: ReaderOptions;
  bookmarks: Array<ReadingProgress>;
  aid: string;
  albumTitle: string;
  authorLine: string;
  chapters: Array<Chapter>;
  chapterIndex: number;
  pages: Array<string>;
  scrambleId: number;
  loadState: 'loading' | 'ready' | 'error';
  errorMsg: string;
  currentPage: number;
  mode: ReaderMode;
  hudVisible: boolean;
  panel: ReaderPanelKind;
  sheetKind: ReaderSheetKind;
  sheetVisible: boolean;
  zoneEditorVisible: boolean;
  brightnessValue: number;
  bgPaper: boolean;
  preloadCount: number;
  sliderValue: number;
  sliderDragging: boolean;
  canvasWidthVp: number;
  canvasHeightVp: number;
  topSafeVp: number;
  bottomSafeVp: number;
  zoomScale: number;
  zoomOffsetX: number;
  zoomOffsetY: number;
  getUIContext(): UIContext;
}

export class ReaderController {
  private host: ReaderHost;
  constructor(host: ReaderHost) { this.host = host; }
  private currentAlbum: Album | null = null;
  private attemptedSources: Set<string> = new Set();
  private widePages: Set<string> = new Set();
  private switchingSource: boolean = false;
  activitySince: number = 0;
  private visiblePages: Set<string> = new Set();
  private displayedProgress: ReadingProgress | null = null;
  private activityPage: string = '';
  private visible: boolean = true;

  get readerVisible(): boolean { return this.visible; }

  set readerVisible(value: boolean) {
    const wasVisible: boolean = this.visible;
    this.visible = value;
    if (!value) {
      this.flushProgress();
      this.activitySince = 0;
      this.visiblePages.clear();
      this.albumToken++;
      if (!this.readingResolved) { this.readingStarted = false; }
      this.albumSignal.abortAll();
      this.pageSignal.abortAll();
      this.preloadSignal.abortAll();
      this.prefetched.clear();
    } else if (!wasVisible && !this.destroyed) {
      if (this.pageSignal.aborted()) { this.pageSignal = new RequestAbortGroup(); }
      if (this.preloadSignal.aborted()) { this.preloadSignal = new RequestAbortGroup(); }
      if (this.paramReady && !this.readingResolved) {
        this.loadAlbum().catch((_e: Error): void => {});
      }
    }
  }
  private activityBookKey: string = '';
  routeChapterId: string = '';
  routeChapterIndex: number = -1;
  routePage: number = -1;
  paramReady: boolean = false;
  private pinchStartScale: number = 1;
  private panStartX: number = 0;
  private panStartY: number = 0;
  targetWidthPx: number = 1080;
  pagesSource: BasicDataSource<string> = new BasicDataSource<string>();
  spreadSource: BasicDataSource<Array<string>> = new BasicDataSource<Array<string>>();
  private spreadsCache: Array<Array<string>> = [];
  chapterSource: BasicDataSource<Chapter> = new BasicDataSource<Chapter>();
  listScroller: Scroller = new Scroller();
  swiperController: SwiperController = new SwiperController();
  private prefetched: Set<string> = new Set<string>();
  chapterToken: number = 0;
  private pageSignal: RequestAbortGroup = new RequestAbortGroup();
  private albumSignal: RequestAbortGroup = new RequestAbortGroup();
  private preloadSignal: RequestAbortGroup = new RequestAbortGroup();
  private albumToken: number = 0;
  private lastSavedAt: number = 0;
  private saveTimer: number = -1;
  private hudTimer: number = -1;
  private hudTouching: boolean = false;
  private readingStarted: boolean = false;
  readingResolved: boolean = false;
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
    this.clearHudTimer();
    this.flushProgress();
    this.activitySince = 0;
    this.chapterToken++;
    this.albumToken++;
    this.destroyed = true;
    this.pageSignal.abortAll();
    this.albumSignal.abortAll();
    this.preloadSignal.abortAll();
  }

  backgroundChanged(): void {
    if (this.host.inBackground) { this.flushProgress(); this.activitySince = 0; }
    else if (this.readerVisible && this.visiblePages.size > 0) { this.activitySince = Date.now(); }
  }

  async persistOptions(): Promise<void> {
    this.host.options.mode = this.host.mode; this.host.options.preload = this.host.preloadCount; this.host.options.paper = this.host.bgPaper;
    try { await readerPreferences.save(this.host.aid, this.host.options); }
    catch (e) { this.toastMsg(`保存阅读偏好失败：${errorMessage(e as Error)}`); }
  }

  async toggleBookmark(): Promise<void> {
    try { await readerPreferences.toggleBookmark(this.buildProgress()); this.host.bookmarks = await readerPreferences.bookmarks(this.host.aid); }
    catch (e) { this.toastMsg(errorMessage(e as Error)); }
  }

  measuredPage(filename: string, aspect: number): void {
    if (aspect > 1.2 && !this.widePages.has(filename)) {
      this.widePages.add(filename); this.buildSpreads(); this.scrollToPageDelayed(this.host.currentPage);
    }
  }

  pageFailed(filename: string, error: Error): void {
    if (isRequestCancelled(error)) {
      return;
    }
    if (this.host.pages[this.host.currentPage] === filename && !this.host.sliderDragging) { this.tryFallback(error, false); }
  }

  private async tryFallback(error: Error, fatalIfNoSource: boolean = true): Promise<boolean> {
    if (isRequestCancelled(error) || this.switchingSource || this.destroyed || !this.readerVisible || this.currentAlbum === null) { return false; }
    if (/登录|认证|401|403/.test(error.message)) {
      if (fatalIfNoSource) {
        this.host.errorMsg = error.message;
        this.host.hudVisible = true;
      }
      return false;
    }
    const chapter: Chapter | undefined = this.host.chapters[this.host.chapterIndex];
    if (chapter === undefined) { return false; }
    const token: number = this.chapterToken;
    this.switchingSource = true;
    this.attemptedSources.add(this.host.aid);
    try {
      const result: SourceSwitchResult = await fallbackSource(this.currentAlbum, chapter, this.host.currentPage,
        this.host.pages.length || (await readProgressStore.get(this.host.aid))?.totalPages || 0,
        this.attemptedSources, (): boolean => token === this.chapterToken && !this.destroyed && this.readerVisible);
      if (token !== this.chapterToken || this.destroyed) { return false; }
      this.flushProgress();
      this.activitySince = 0;
      this.visiblePages.clear();
      this.displayedProgress = null;
      await library.activate(result.album.id);
      if (token !== this.chapterToken || this.destroyed || !this.readerVisible) { return false; }
      this.albumToken++;
      this.albumSignal.abortAll();
      this.host.pages = []; this.host.aid = result.album.id; this.applyAlbum(result.album);
      await this.loadPrefs();
      if (token !== this.chapterToken || this.destroyed || !this.readerVisible) { return false; }
      await this.loadChapter(result.album.episodes.findIndex((c: Chapter) => c.id === result.chapter.id), result.page, true);
      this.toastMsg(result.proportional ? '已切换书源，已按阅读比例定位' : '已切换到可用书源');
      return true;
    } catch (e) {
      if (isRequestCancelled(e as Error)) { return false; }
      if (token === this.chapterToken && fatalIfNoSource) {
        this.host.errorMsg = `${error.message}；${errorMessage(e as Error)}`;
        this.host.loadState = 'error';
        this.host.hudVisible = true;
      }
      return false;
    } finally { this.switchingSource = false; }
  }

  initAfterParams(): void {
    this.measureSafeAreas().catch((_e: Error): void => {
    });
    this.loadPrefs().catch((_e: Error): void => {
    });
    this.loadAlbum().catch((_e: Error): void => {
    });
  }

  private async loadPrefs(): Promise<void> {
    try {
      const aid: string = this.host.aid;
      const prefs: Prefs = await Prefs.getInstance();
      const options: ReaderOptions = await readerPreferences.load(aid);
      const key: string = await readerPreferences.key(aid);
      const bookmarks: Array<ReadingProgress> = await readerPreferences.bookmarks(aid);
      const brightness: number = await prefs.brightness();
      const autoCache: boolean = await prefs.autoCache();
      if (this.destroyed || aid !== this.host.aid) { return; }
      this.host.options = options;
      this.activityBookKey = key;
      this.host.bookmarks = bookmarks;
      const m: string = this.host.options.mode;
      if (m === 'vertical' || m === 'pagedVertical' || m === 'horizontal' || m === 'rtl' || m === 'double') {
        this.host.mode = m;
      } else {
        this.host.mode = 'vertical';
      }
      this.buildSpreads();
      this.host.preloadCount = this.clampPreload(this.host.options.preload);
      this.host.bgPaper = this.host.options.paper;
      this.applySystemBarDarkText(this.host.bgPaper).catch((_e: Error): void => {
      });
      this.host.brightnessValue = brightness >= 0 && brightness <= 100 ? brightness : 100;
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
      const t: number = this.host.getUIContext().px2vp(top.topRect.height);
      const b: number = this.host.getUIContext().px2vp(bottom.bottomRect.height);
      if (t >= 0) {
        this.host.topSafeVp = t;
      }
      if (b >= 0) {
        this.host.bottomSafeVp = b;
      }
    } catch (e) {
      // 量取失败保持默认
    }
  }

  async applySystemBarDarkText(darkText: boolean): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(getAppContext());
      await win.setWindowSystemBarProperties({ statusBarContentColor: darkText ? '#1E293B' : '#FFFFFF' });
    } catch (e) {
      // 系统栏配置失败不影响阅读
    }
  }

  restoreSystemBarToTheme(): void {
    const isDark: boolean = AppStorage.get<boolean>(IS_DARK_MODE_KEY) ?? false;
    this.applySystemBarDarkText(!isDark).catch((_e: Error): void => {
    });
  }

  private async loadAlbum(): Promise<void> {
    if (this.destroyed) { return; }
    this.albumSignal.abortAll();
    const signal: RequestAbortGroup = new RequestAbortGroup();
    this.albumSignal = signal;
    const token: number = ++this.albumToken;
    const aid: string = this.host.aid;
    let cachedAlbum: Album | null = null;
    try {
      cachedAlbum = await albumCacheStore.get(aid);
    } catch (e) {
      cachedAlbum = null;
    }
    if (token !== this.albumToken || aid !== this.host.aid || this.destroyed || signal.aborted()) { return; }
    if (cachedAlbum !== null) {
      this.applyAlbum(cachedAlbum);
      this.beginReading();
    }
    try {
      const fresh: Album = await jmApi.album(aid, false, signal);
      if (token !== this.albumToken || aid !== this.host.aid || this.destroyed || signal.aborted()) { return; }
      this.applyAlbum(fresh);
      albumCacheStore.put(fresh).catch((_e: Error): void => {
      });
      this.beginReading();
    } catch (e) {
      if (isRequestCancelled(e as Error) || signal.aborted() ||
        token !== this.albumToken || aid !== this.host.aid || this.destroyed) { return; }
      if (cachedAlbum === null) {
        if (!this.readingStarted) {
          this.host.loadState = 'error';
          this.host.errorMsg = errorMessage(e as Error);
          this.host.hudVisible = true;
        }
      }
    }
  }

  private applyAlbum(a: Album): void {
    this.currentAlbum = a;
    if (a.name !== '') {
      this.host.albumTitle = a.name;
    }
    const authors: string = a.author.map((term: MetadataTerm): string => term.label).join(' ');
    if (authors !== '') {
      this.host.authorLine = authors;
    }
    if (a.episodes.length > 0) {
      if (this.readingStarted) {
        const curId: string = this.currentChapterId();
        const idx: number = curId !== '' ? this.indexOfChapterIn(a.episodes, curId) : -1;
        this.host.chapters = a.episodes;
        this.chapterSource.setList(a.episodes);
        if (idx >= 0) {
          this.host.chapterIndex = idx;
        }
      } else {
        this.host.chapters = a.episodes;
        this.chapterSource.setList(a.episodes);
      }
    }
  }

  private beginReading(): void {
    if (this.readingStarted) {
      return;
    }
    if (this.host.chapters.length === 0) {
      this.host.loadState = 'error';
      this.host.errorMsg = '本作品暂无可阅读的章节';
      this.host.hudVisible = true;
      return;
    }
    this.readingStarted = true;
    if (this.routeChapterIndex >= 0 && this.routeChapterIndex < this.host.chapters.length) {
      this.resolveStart(this.routeChapterIndex, this.routePage >= 0 ? this.routePage : 0);
      return;
    }
    if (this.routeChapterId !== '') {
      const found: number = this.indexOfChapter(this.routeChapterId);
      this.resolveStart(found >= 0 ? found : 0, this.routePage >= 0 ? this.routePage : 0);
      return;
    }
    const aid: string = this.host.aid;
    const token: number = this.albumToken;
    readProgressStore.get(aid).then((p: ReadingProgress | null): void => {
      if (this.readingResolved || aid !== this.host.aid || token !== this.albumToken || this.destroyed) {
        return;
      }
      if (p === null) {
        this.resolveStart(0, 0);
        return;
      }
      const byId: number = p.chapterId !== '' ? this.indexOfChapter(p.chapterId) : -1;
      const idx: number = byId >= 0 ? byId : (p.chapterIndex >= 0 && p.chapterIndex < this.host.chapters.length
        ? p.chapterIndex : 0);
      const page: number = this.routePage >= 0 ? this.routePage : p.page;
      this.resolveStart(idx, page);
    }).catch((e: Error): void => {
      if (aid === this.host.aid && token === this.albumToken && !this.destroyed) {
        this.host.loadState = 'error'; this.host.errorMsg = `读取阅读进度失败：${errorMessage(e)}`; this.host.hudVisible = true;
      }
    });
  }

  private resolveStart(chapterIdx: number, page: number): void {
    if (this.readingResolved) {
      return;
    }
    this.readingResolved = true;
    this.loadChapter(chapterIdx, page).catch((_e: Error): void => {
    });
  }

  async loadChapter(chapterIdx: number, targetPage: number, preserveAttempts: boolean = false): Promise<void> {
    if (this.destroyed) { return; }
    const ch: Chapter | undefined = this.host.chapters[chapterIdx];
    if (ch === undefined) {
      this.host.loadState = 'error';
      this.host.errorMsg = '章节不存在';
      this.host.hudVisible = true;
      return;
    }
    this.flushProgress();
    this.activitySince = 0;
    this.visiblePages.clear();
    this.displayedProgress = null;
    if (!preserveAttempts) { this.attemptedSources.clear(); }
    this.widePages.clear();
    this.host.chapterIndex = chapterIdx;
    this.host.loadState = 'loading';
    this.host.errorMsg = '';
    this.host.scrambleId = SCRAMBLE_DEFAULT;
    this.prefetched.clear();
    this.host.pages = [];
    this.resetZoom(false);
    this.pagesSource.setList(this.host.pages);
    this.buildSpreads();
    const token: number = ++this.chapterToken;
    this.pageSignal.abortAll();
    this.preloadSignal.abortAll();
    const signal: RequestAbortGroup = new RequestAbortGroup();
    const preloadSignal: RequestAbortGroup = new RequestAbortGroup();
    this.pageSignal = signal;
    this.preloadSignal = preloadSignal;
    const initialTarget: number = targetPage;

    let cached: Array<string> | null = null;
    try {
      cached = await pagesCacheStore.get(ch.id);
    } catch (e) {
      cached = null;
    }
    if (!this.chapterCurrent(token, signal)) {
      return;
    }
    if (cached !== null && cached.length > 0) {
      this.host.pages = cached;
      this.pagesSource.setList(cached);
      this.buildSpreads();
      const t: number = clampPage(initialTarget, cached.length);
      this.host.currentPage = t;
      this.host.loadState = 'ready';
      this.scrollToPageDelayed(t);
      this.prefetchAhead(t);
    }

    try {
      const fresh: Array<string> = await jmApi.chapterImages(ch.id, signal);
      if (!this.chapterCurrent(token, signal)) {
        return;
      }
      const hadCache: boolean = cached !== null && cached.length > 0;
      const changed: boolean = !hadCache || !this.samePages(fresh, cached as Array<string>);
      if (fresh.length > 0 && changed) {
        this.host.pages = fresh;
        this.pagesSource.setList(fresh);
        this.buildSpreads();
        const t: number = clampPage(initialTarget, fresh.length);
        this.host.currentPage = t;
        this.host.loadState = 'ready';
        pagesCacheStore.put(ch.id, fresh).catch((_e: Error): void => {
        });
        this.prefetched.clear();
        this.scrollToPageDelayed(t);
        this.prefetchAhead(t);
      } else {
        this.host.loadState = 'ready';
      }
    } catch (e) {
      if (isRequestCancelled(e as Error) || !this.chapterCurrent(token, signal)) {
        return;
      }
      if (cached === null || cached.length === 0) {
        this.host.currentPage = initialTarget;
        if (await this.tryFallback(e as Error)) { return; }
        if (!this.chapterCurrent(token, signal)) { return; }
        this.host.loadState = 'error';
        if (this.host.errorMsg === '') { this.host.errorMsg = errorMessage(e as Error); }
        this.host.hudVisible = true;
        return;
      }
      this.host.loadState = 'ready';
    }

    try {
      const sid: number = await jmApi.scrambleId(ch.id, signal);
      if (!this.chapterCurrent(token, signal)) {
        return;
      }
      if (sid !== this.host.scrambleId) {
        this.host.scrambleId = sid;
        this.prefetched.clear();
        this.prefetchAhead(this.host.currentPage);
      }
    } catch (e) {
      if (isRequestCancelled(e as Error) || !this.chapterCurrent(token, signal)) { return; }
    }
    if (!this.chapterCurrent(token, signal)) { return; }

    this.preloadNextChapter(token, preloadSignal).catch((_e: Error): void => {
    });
    library.activate(this.host.aid).catch((e: Error) => { this.toastMsg(`保存当前书源失败：${errorMessage(e)}`); });
  }

  retryLoad(): void {
    if (this.host.chapters.length > 0) {
      this.loadChapter(this.host.chapterIndex, 0).catch((_e: Error): void => {
      });
    } else {
      this.readingStarted = false;
      this.readingResolved = false;
      this.loadAlbum().catch((_e: Error): void => {
      });
    }
  }

  prefetchAhead(fromIndex: number): void {
    if (!this.autoCacheOn || this.destroyed || !this.readerVisible || this.pageSignal.aborted()) {
      return;
    }
    if (this.host.pages.length === 0) {
      return;
    }
    const photoId: string = this.currentChapterId();
    if (photoId === '') {
      return;
    }
    const last: number = Math.min(this.host.pages.length - 1, fromIndex + this.host.preloadCount);
    for (let i: number = fromIndex + 1; i <= last; i++) {
      const filename: string = this.host.pages[i];
      const key: string = `${photoId}/${filename}@${this.host.scrambleId}`;
      if (this.prefetched.has(key)) {
        continue;
      }
      this.prefetched.add(key);
      this.prefetchOne(photoId, filename, key, this.host.scrambleId, this.chapterToken, this.pageSignal);
    }
  }

  private chapterCurrent(token: number, signal: RequestAbortGroup): boolean {
    return token === this.chapterToken && !signal.aborted() && !this.destroyed;
  }

  private async prefetchOne(photoId: string, filename: string, key: string, scrambleId: number,
    token: number, signal: RequestAbortGroup): Promise<void> {
    if (!this.chapterCurrent(token, signal)) { return; }
    try {
      const pm: image.PixelMap | null =
        await loadPagePixelMap(photoId, filename, scrambleId, this.targetWidthPx, signal);
      if (pm !== null) {
        releasePagePixelMap(pm);
      }
    } catch (e) {
      if (this.chapterCurrent(token, signal)) { this.prefetched.delete(key); }
    }
  }

  private async preloadNextChapter(token: number, signal: RequestAbortGroup): Promise<void> {
    if (!this.autoCacheOn || !this.chapterCurrent(token, signal)) {
      return;
    }
    const next: Chapter | undefined = this.host.chapters[this.host.chapterIndex + 1];
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
      if (!this.chapterCurrent(token, signal)) { return; }
      if (list === null || list.length === 0) {
        list = await jmApi.chapterImages(next.id, signal);
        if (!this.chapterCurrent(token, signal)) { return; }
        if (list.length > 0) {
          pagesCacheStore.put(next.id, list).catch((_e: Error): void => {
          });
        }
      }
      if (list.length === 0) {
        return;
      }
      const sid: number = await jmApi.scrambleId(next.id, signal);
      if (!this.chapterCurrent(token, signal)) { return; }
      const count: number = Math.min(5, list.length);
      for (let i: number = 0; i < count; i++) {
        if (!this.chapterCurrent(token, signal)) { return; }
        const pm: image.PixelMap | null =
          await loadPagePixelMap(next.id, list[i], sid, this.targetWidthPx, signal);
        if (pm !== null) {
          releasePagePixelMap(pm);
        }
      }
    } catch (e) {
      // 下一章预载失败静默
    }
  }

  private buildProgress(): ReadingProgress {
    const progress: ReadingProgress = new ReadingProgress();
    progress.aid = this.host.aid;
    progress.chapterId = this.currentChapterId();
    progress.chapterIndex = this.host.chapterIndex;
    progress.page = this.host.currentPage;
    progress.totalPages = this.host.pages.length;
    progress.title = this.host.albumTitle;
    progress.author = this.host.authorLine;
    progress.coverUrl = (this.currentAlbum !== null && this.currentAlbum.coverUrl !== '')
      ? this.currentAlbum.coverUrl
      : jmApi.albumThumbUrl(this.host.aid);
    return progress;
  }

  private saveProgressNow(): void {
    if (this.displayedProgress === null) {
      return;
    }
    const now: number = Date.now();
    const elapsed: number = this.activitySince > 0 ? Math.max(0, now - this.activitySince) : 0;
    if (this.activitySince > 0) { this.activitySince = now; }
    if (elapsed > 0) {
      readingActivity.record(this.activityBookKey || this.displayedProgress.aid, this.activityPage, elapsed)
        .catch((e: Error) => { this.toastMsg(`统计保存失败：${errorMessage(e)}`); });
    }
    if (elapsed > 0) { this.lastSavedAt = now; }
  }

  pageDisplayed(chapter: string, filename: string, visible: boolean): void {
    if (chapter !== this.currentChapterId()) { return; }
    const page: number = this.host.pages.indexOf(filename);
    if (page < 0) { return; }
    if (!visible) {
      this.visiblePages.delete(filename);
      if (this.visiblePages.size === 0) { this.flushProgress(); this.activitySince = 0; }
      return;
    }
    if (this.destroyed || !this.readerVisible || this.host.inBackground || this.host.loadState !== 'ready' || this.visiblePages.has(filename)) { return; }
    this.flushProgress();
    this.visiblePages.add(filename);
    const progress: ReadingProgress = this.buildProgress();
    progress.page = page;
    this.displayedProgress = progress;
    this.activityPage = `${chapter}~${page}`;
    this.activitySince = Date.now();
    readingActivity.record(this.activityBookKey || this.host.aid, this.activityPage, 0)
      .catch((e: Error): void => { this.toastMsg(`统计保存失败：${errorMessage(e)}`); });
    const album: Album | null = this.currentAlbum;
    readProgressStore.save(progress).catch((e: Error): void => { this.toastMsg(`进度保存失败：${errorMessage(e)}`); });
    if (album !== null) {
      historyStore.record(album, album.coverUrl).catch((e: Error): void => { this.toastMsg(`阅读历史保存失败：${errorMessage(e)}`); });
    }
  }

  flushProgress(): void {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    this.saveProgressNow();
  }

  scheduleProgressSave(): void {
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

  handleCanvasClick(x: number, y: number): void {
    if (this.host.zoneEditorVisible) {
      return;
    }
    const w: number = this.host.canvasWidthVp;
    if (w <= 0 || this.host.canvasHeightVp <= 0) {
      this.toggleHud();
      return;
    }
    const col: number = Math.max(0, Math.min(2, Math.floor(x / (w / 3))));
    const row: number = Math.max(0, Math.min(2, Math.floor(y / (this.host.canvasHeightVp / 3))));
    const action: number = this.host.options.taps[row * 3 + col];
    if (action === 0) { this.toggleHud(); }
    else if (action === 1) { this.turnPage(this.host.mode === 'rtl'); }
    else if (action === 2) { this.turnPage(this.host.mode !== 'rtl'); }
    else { this.goChapter(action === 3 ? -1 : 1); }
  }

  /** 目录入口拉起半模态抽屉；画面与设置改为切换底栏上方的同材质浮卡。 */
  openSheet(kind: ReaderSheetKind): void {
    this.host.sheetKind = kind;
    if (kind === 'index') {
      this.host.panel = 'none';
      this.host.hudVisible = false;
      this.host.sheetVisible = true;
    } else {
      this.host.sheetVisible = false;
      this.host.panel = kind;
    }
  }

  /** 热区校准是三级全屏交互：先收起浮卡或抽屉，再压上蒙层。 */
  openZoneEditor(): void {
    this.host.sheetVisible = false;
    this.host.panel = 'none';
    const token: number = this.chapterToken;
    setTimeout((): void => {
      if (this.destroyed || token !== this.chapterToken) {
        return;
      }
      this.host.hudVisible = false;
      this.host.zoneEditorVisible = true;
    }, 260);
  }

  private toggleHud(): void {
    this.host.hudVisible = !this.host.hudVisible;
    this.host.panel = this.host.hudVisible ? 'progress' : 'none';
    this.syncHudTimer();
  }

  onHudTouch(down: boolean): void {
    this.hudTouching = down;
    this.syncHudTimer();
  }

  syncHudTimer(): void {
    this.clearHudTimer();
    const idlePanel: boolean = this.host.panel === 'none' || this.host.panel === 'progress';
    if (!this.host.hudVisible || this.hudTouching || !idlePanel ||
      this.host.sliderDragging || this.host.sheetVisible) {
      return;
    }
    this.hudTimer = setTimeout((): void => {
      this.hudTimer = -1;
      const stillIdlePanel: boolean = this.host.panel === 'none' || this.host.panel === 'progress';
      if (stillIdlePanel && !this.host.sliderDragging && !this.host.sheetVisible && !this.hudTouching) {
        this.host.panel = 'none';
        this.host.hudVisible = false;
      }
    }, 3500);
  }

  private clearHudTimer(): void {
    if (this.hudTimer >= 0) {
      clearTimeout(this.hudTimer);
      this.hudTimer = -1;
    }
  }

  onDoubleTap(x: number, y: number): void {
    if (this.host.zoomScale > 1.05) {
      this.resetZoom(true);
      return;
    }
    const width: number = this.host.canvasWidthVp;
    const height: number = this.host.canvasHeightVp;
    const scale: number = 2;
    let offsetX: number = (width / 2 - x) * (scale - 1);
    let offsetY: number = (height / 2 - y) * (scale - 1);
    const maxX: number = Math.max(0, (width * (scale - 1)) / 2);
    const maxY: number = Math.max(0, (height * (scale - 1)) / 2);
    offsetX = Math.max(-maxX, Math.min(maxX, offsetX));
    offsetY = Math.max(-maxY, Math.min(maxY, offsetY));
    this.host.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, (): void => {
      this.host.zoomScale = scale;
      this.host.zoomOffsetX = offsetX;
      this.host.zoomOffsetY = offsetY;
    });
  }

  bounceZoomBack(): void {
    const targetScale: number = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, this.host.zoomScale));
    const maxX: number = Math.max(0, (this.host.canvasWidthVp * (targetScale - 1)) / 2);
    const maxY: number = Math.max(0, (this.host.canvasHeightVp * (targetScale - 1)) / 2);
    const targetX: number = Math.max(-maxX, Math.min(maxX, this.host.zoomOffsetX));
    const targetY: number = Math.max(-maxY, Math.min(maxY, this.host.zoomOffsetY));
    if (targetScale === this.host.zoomScale && targetX === this.host.zoomOffsetX && targetY === this.host.zoomOffsetY) {
      return;
    }
    this.host.getUIContext().animateTo({ duration: 200, curve: Curve.Friction }, (): void => {
      this.host.zoomScale = targetScale;
      this.host.zoomOffsetX = targetX;
      this.host.zoomOffsetY = targetY;
    });
  }

  resetZoom(animated: boolean): void {
    if (this.host.zoomScale === ZOOM_MIN && this.host.zoomOffsetX === 0 && this.host.zoomOffsetY === 0) {
      return;
    }
    if (animated) {
      this.host.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
        this.host.zoomScale = ZOOM_MIN;
        this.host.zoomOffsetX = 0;
        this.host.zoomOffsetY = 0;
      });
    } else {
      this.host.zoomScale = ZOOM_MIN;
      this.host.zoomOffsetX = 0;
      this.host.zoomOffsetY = 0;
    }
  }

  onPinchStart(_event: GestureEvent): void {
    this.pinchStartScale = this.host.zoomScale;
  }

  onPinchUpdate(event: GestureEvent): void {
    const raw: number = this.pinchStartScale * event.scale;
    this.host.zoomScale = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, raw));
  }

  onTwoFingerPanStart(_event: GestureEvent): void {
    this.panStartX = this.host.zoomOffsetX;
    this.panStartY = this.host.zoomOffsetY;
  }

  onTwoFingerPanUpdate(event: GestureEvent): void {
    this.host.zoomOffsetX = this.panStartX + event.offsetX;
    this.host.zoomOffsetY = this.panStartY + event.offsetY;
  }

  private turnPage(forward: boolean): void {
    if (this.host.pages.length === 0) {
      return;
    }
    if (this.host.mode === 'vertical') {
      this.scrollScreen(forward);
      return;
    }
    if (this.host.mode === 'double') {
      const index: number = this.pageToSpreadIndex(this.host.currentPage) + (forward ? 1 : -1);
      if (index < 0 || index >= this.spreadsCache.length) { this.toastMsg('已到本章边界'); return; }
      this.jumpToPage(this.spreadIndexToPage(index)); return;
    }
    const target: number = this.host.currentPage + (forward ? 1 : -1);
    if (target < 0) {
      this.toastMsg('已经是第一页了');
      return;
    }
    if (target >= this.host.pages.length) {
      if (this.host.chapterIndex < this.host.chapters.length - 1) {
        this.toastMsg('本章完，可点「下一话」继续');
      } else {
        this.toastMsg('已经是最后一页了');
      }
      return;
    }
    this.jumpToPage(target);
  }

  private scrollScreen(forward: boolean): void {
    if (this.host.canvasHeightVp > 0) {
      const cur: OffsetResult = this.listScroller.currentOffset();
      const delta: number = this.host.canvasHeightVp * 0.85;
      const target: number = forward ? cur.yOffset + delta : Math.max(0, cur.yOffset - delta);
      this.listScroller.scrollTo({
        xOffset: 0,
        yOffset: target,
        animation: { duration: 220, curve: Curve.EaseOut }
      });
    } else {
      const idx: number = forward ? this.host.currentPage + 1 : this.host.currentPage - 1;
      if (idx >= 0 && idx < this.host.pages.length) {
        this.jumpToPage(idx);
      }
    }
  }

  jumpToPage(page: number): void {
    const total: number = this.host.pages.length;
    if (total === 0) {
      return;
    }
    const p: number = clampPage(page, total);
    this.host.currentPage = p;
    if (this.host.mode === 'vertical') {
      this.listScroller.scrollToIndex(p, false);
    } else {
      this.swiperController.changeIndex(this.pageToSpreadIndex(p), false);
    }
    this.scheduleProgressSave();
  }

  scrollToPageDelayed(page: number): void {
    const token: number = this.chapterToken;
    setTimeout((): void => {
      if (this.destroyed || token !== this.chapterToken) {
        return;
      }
      this.jumpToPage(page);
    }, 120);
  }

  switchMode(m: ReaderMode): void {
    if (this.host.mode === m) {
      this.host.panel = 'none';
      return;
    }
    const keepPage: number = this.host.currentPage;
    this.host.mode = m;
    this.host.panel = 'none';
    this.buildSpreads();
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

  setPreload(n: number): void {
    this.host.preloadCount = n;
    this.persistOptions();
  }

  toggleBackground(paper: boolean): void {
    if (this.host.bgPaper === paper) {
      return;
    }
    this.host.bgPaper = paper;
    this.persistOptions();
    this.applySystemBarDarkText(paper).catch((_e: Error): void => {
    });
  }

  goChapter(delta: number): void {
    const target: number = this.host.chapterIndex + delta;
    if (target < 0) {
      this.toastMsg('已经是第一话了');
      return;
    }
    if (target >= this.host.chapters.length) {
      this.toastMsg('已经是最后一话了');
      return;
    }
    this.saveProgressNow();
    this.loadChapter(target, 0).catch((_e: Error): void => {
    });
  }

  goBack(): void {
    this.flushProgress();
    this.host.pageStack.pop();
  }

  openPreview(): void {
    const chId: string = this.currentChapterId();
    if (chId === '') {
      return;
    }
    this.flushProgress();
    this.host.hudVisible = false;
    const params: MangaRouteParams = {
      aid: this.host.aid,
      chapterId: chId,
      query: this.chapterTitle()
    };
    this.host.pageStack.pushPathByName(ROUTE_PREVIEW, params);
  }

  private toastMsg(msg: string): void {
    try {
      this.host.getUIContext().getPromptAction().showToast({ message: msg, duration: 1600, bottom: '35%' });
    } catch (e) {
      // Toast 失败可忽略
    }
  }

  buildSpreads(): void {
    const out: Array<Array<string>> = [];
    if (this.host.mode === 'rtl') {
      for (let i: number = this.host.pages.length - 1; i >= 0; i--) {
        out.push([this.host.pages[i]]);
      }
    } else if (this.host.mode === 'double') {
      out.push(...makeSpreads(this.host.pages, this.widePages, this.host.options.coverOffset));
    } else {
      for (const p of this.host.pages) {
        out.push([p]);
      }
    }
    this.spreadsCache = out;
    this.spreadSource.setList(out);
  }

  pageToSpreadIndex(page: number): number {
    const n: number = this.spreadsCache.length;
    if (n === 0) {
      return 0;
    }
    if (this.host.mode === 'rtl') {
      const p: number = clampPage(page, this.host.pages.length);
      return Math.max(0, Math.min(n - 1, this.host.pages.length - 1 - p));
    }
    if (this.host.mode === 'double') {
      return spreadForPage(this.spreadsCache, clampPage(page, this.host.pages.length));
    }
    return clampPage(page, n);
  }

  spreadIndexToPage(index: number): number {
    const n: number = this.spreadsCache.length;
    if (n === 0) {
      return 0;
    }
    const i: number = Math.max(0, Math.min(n - 1, index));
    if (this.host.mode === 'rtl') {
      return Math.max(0, Math.min(this.host.pages.length - 1, this.host.pages.length - 1 - i));
    }
    if (this.host.mode === 'double') {
      return lastPageInSpread(this.spreadsCache, i);
    }
    const first: string | undefined = this.spreadsCache[i][0];
    if (first === undefined) {
      return 0;
    }
    const idx: number = this.host.pages.indexOf(first);
    return idx >= 0 ? idx : 0;
  }

  chapterTitle(): string {
    const ch: Chapter | undefined = this.host.chapters[this.host.chapterIndex];
    if (ch !== undefined && ch.title !== '') {
      return ch.title;
    }
    return `第 ${this.host.chapterIndex + 1} 話`;
  }

  currentChapterId(): string {
    const ch: Chapter | undefined = this.host.chapters[this.host.chapterIndex];
    return ch === undefined ? '' : ch.id;
  }

  private indexOfChapter(id: string): number {
    return this.indexOfChapterIn(this.host.chapters, id);
  }

  private indexOfChapterIn(list: Array<Chapter>, id: string): number {
    for (let i: number = 0; i < list.length; i++) {
      if (list[i].id === id) {
        return i;
      }
    }
    return -1;
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
}
