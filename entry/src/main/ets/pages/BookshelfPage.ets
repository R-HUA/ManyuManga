/**
 * 书架（收藏 / 历史 / 下载 三段 + 顶部续读横幅）
 *
 *
 */

import { ROUTE_ALBUM, ROUTE_READER, ROUTE_SEARCH, ROUTE_DOWNLOADS } from '../common/Route';
import {
  PRIMARY,
  ACCENT,
  BG,
  CARD,
  CARD_R,
  COVER_R,
  CHIP_R,
  TEXT_MAIN,
  TEXT_SUB,
  CHIP_BG,
  DIVIDER,
  MASK_DARK,
  TAB_INACTIVE,
  TAB_BAR_HEIGHT
} from '../common/Theme';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY, CURRENT_BREAKPOINT_KEY } from '../entryability/EntryAbility';
import { ComicCard, EmptyView, TagChip, SkeletonGrid } from '../common/Components';
import { Album, FavItem, HistoryItem, ReadingProgress, errorMessage } from '../models/Models';
import { favStore, historyStore, readProgressStore } from '../data/Stores';
import { sourceApi as jmApi } from '../data/SourceApi';
import { downloadManager, DownloadTask, DownloadState } from '../data/DownloadManager';
import { Prefs } from '../util/Prefs';

/* ===== 路由参数 ===== */

class AlbumRouteParam {
  aid: string = '';
}

class SearchRouteParam {
  query: string = '';
}

class DownloadsRouteParam {
}

class ReaderRouteParam {
  aid: string = '';
  /** -1 = 未指定（阅读器按默认定位） */
  chapterIndex: number = -1;
  page: number = -1;
}

/* ===== 收藏网格懒加载数据源 ===== */

class FavDataSource implements IDataSource {
  private items: Array<FavItem> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): FavItem {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener): boolean => l !== listener);
  }

  reload(items: Array<FavItem>): void {
    this.items = items;
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }
}

/* ===== 历史列表懒加载数据源 ===== */

class HistoryDataSource implements IDataSource {
  private items: Array<HistoryItem> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): HistoryItem {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener): boolean => l !== listener);
  }

  reload(items: Array<HistoryItem>): void {
    this.items = items;
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }
}

/* ===== 工具 ===== */

/** 手动添加 jm 编号识别（FavoritesScreen.kt:56 ADD_ID_PATTERN 等价） */
const ADD_ID_PATTERN: RegExp = /^\s*(?:[jJ][mM])?\s*(\d{1,10})\s*$/;

/** 下载段摘要最多展示的任务条数 */
const SUMMARY_MAX: number = 6;

function formatDateTime(ms: number): string {
  if (ms <= 0) {
    return '';
  }
  const d: Date = new Date(ms);
  const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function chapterLabel(index: number): string {
  return `第${index + 1}话`;
}

@Component
export struct BookshelfPage {
  @Consume('navPathStack') pageStack: NavPathStack;

  /* ===== 评审 Step2：全屏布局避让 + 断点（EntryAbility 写入 AppStorage） =====
   * sm 断点 MainShell 有悬浮底部 Tab 栏（TAB_BAR_HEIGHT），内容底部需叠加避让；
   * md/lg 由左侧 SideRail 承担导航，仅留系统导航条高度。 */
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 38;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 16;
  @StorageProp(CURRENT_BREAKPOINT_KEY) bp: string = 'sm';
  // 评审 Step3：收藏/历史/阅读进度每次写入 Stores 递增该版本戳（key 常量在数据层未导出，用字面量），
  // @Watch 安静重载——阅读返回后秒级同步续读横幅/页码，不弹骨架不清 UI
  @StorageProp('bookshelfDataVersion') @Watch('onBookshelfDataChanged') dataVer: number = 0;

  /* ===== 页面状态（四态：骨架/空/错误重试；本地数据无分页故无加载更多） ===== */
  @State loading: boolean = true;
  @State loadError: string = '';
  @State segIndex: number = 0;

  /* ===== 数据快照 ===== */
  @State favItems: Array<FavItem> = [];
  @State favTags: Array<string> = [];
  @State historyItems: Array<HistoryItem> = [];
  @State dlTasks: Array<DownloadTask> = [];
  @State latestProgress: ReadingProgress = new ReadingProgress();
  @State favSortMode: string = 'time_desc';
  @State historySortMode: string = 'time_desc';

  /* ===== 手动添加（B-06） ===== */
  @State addInput: string = '';
  @State adding: boolean = false;

  /* ===== 确认弹层状态：移除收藏 / 移除标签 / 清空历史 / 批量删除所选历史 ===== */
  @State pendingFavId: string = '';
  @State pendingFavTitle: string = '';
  @State pendingTag: string = '';
  @State showClearHistory: boolean = false;
  @State showDeleteHistory: boolean = false;

  /* ===== 历史段长按多选（B-10：长按进入多选 + 全选/取消全选 + 批量删除） ===== */
  @State selectMode: boolean = false;
  @State selectedIds: Array<string> = [];

  private initialized: boolean = false;
  private progressList: Array<ReadingProgress> = [];
  private favDS: FavDataSource = new FavDataSource();
  private historyDS: HistoryDataSource = new HistoryDataSource();
  private dlListener: (task: DownloadTask) => void = (): void => {
    this.onDownloadEvent();
  };

  aboutToAppear(): void {
    this.initData();
    downloadManager.onChange(this.dlListener);
  }

  aboutToDisappear(): void {
    downloadManager.offChange(this.dlListener);
  }

  /* ===== 数据加载 ===== */

  private async initData(): Promise<void> {
    await this.refresh(true);
  }

  private async refresh(showSkeleton: boolean): Promise<void> {
    if (showSkeleton && !this.initialized) {
      this.loading = true;
    }
    try {
      const prefs: Prefs = await Prefs.getInstance();
      const favMode: string = await prefs.favSort();
      const histMode: string = await prefs.historySort();
      const favs: Array<FavItem> = await favStore.getList();
      const tags: Array<string> = await favStore.getTags();
      const history: Array<HistoryItem> = await historyStore.getList();
      const progress: Array<ReadingProgress> = await readProgressStore.list(0);
      await downloadManager.init();
      this.favSortMode = favMode;
      this.historySortMode = histMode;
      this.progressList = progress;
      this.latestProgress = progress.length > 0 ? progress[0] : new ReadingProgress();
      this.favTags = tags;
      this.applyFavs(favs);
      this.applyHistory(history);
      this.dlTasks = downloadManager.tasks.slice();
      this.loadError = '';
      this.initialized = true;
    } catch (e) {
      this.loadError = errorMessage(e as Error);
    } finally {
      this.loading = false;
    }
  }

  private applyFavs(items: Array<FavItem>): void {
    this.favItems = items;
    this.favDS.reload(this.sortedFavs(items, this.favSortMode));
  }

  private applyHistory(items: Array<HistoryItem>): void {
    this.historyItems = items;
    this.historyDS.reload(this.sortedHistory(items, this.historySortMode));
  }

  private onDownloadEvent(): void {
    this.dlTasks = downloadManager.tasks.slice();
  }

  /** 评审 Step2（P1）：sm 断点底部内容避让高度 = Tab 栏高度 + 系统导航条；md/lg 仅导航条 */
  private tabAvoidBottom(): number {
    return this.bp === 'sm' ? TAB_BAR_HEIGHT + this.bottomInset : this.bottomInset;
  }

  /** 响应式网格列数（与 CategoryPage 一致：sm 3 / md 4 / lg 5），平板上避免卡片被拉得过大 */
  private gridColumns(): number {
    return this.bp === 'sm' ? 3 : (this.bp === 'md' ? 4 : 5);
  }

  /** Grid 列模板串（如 '1fr 1fr 1fr'），随断点联动 */
  private columnsTemplateStr(): string {
    const parts: Array<string> = [];
    for (let i: number = 0; i < this.gridColumns(); i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  /** 评审 Step3（P1）：收藏/历史/阅读进度版本戳变化（阅读返回等）→ 安静重读，不弹骨架不清滚动 */
  private onBookshelfDataChanged(): void {
    if (!this.initialized) {
      return; // 首载 initData 尚未完成，避免并发重读
    }
    this.refresh(false);
  }

  /* ===== 排序（B-05 / B-09 / B-13，偏好持久化） ===== */

  private compareTitle(a: string, b: string): number {
    if (a === b) {
      return 0;
    }
    return a > b ? 1 : -1;
  }

  private sortedFavs(items: Array<FavItem>, mode: string): Array<FavItem> {
    const arr: Array<FavItem> = items.slice();
    if (mode === 'time_asc') {
      arr.sort((a: FavItem, b: FavItem): number => a.addedAt - b.addedAt);
    } else if (mode === 'title_asc') {
      arr.sort((a: FavItem, b: FavItem): number => this.compareTitle(a.title, b.title));
    } else if (mode === 'title_desc') {
      arr.sort((a: FavItem, b: FavItem): number => -this.compareTitle(a.title, b.title));
    } else {
      arr.sort((a: FavItem, b: FavItem): number => b.addedAt - a.addedAt);
    }
    return arr;
  }

  private sortedHistory(items: Array<HistoryItem>, mode: string): Array<HistoryItem> {
    const arr: Array<HistoryItem> = items.slice();
    if (mode === 'time_asc') {
      arr.sort((a: HistoryItem, b: HistoryItem): number => a.viewedAt - b.viewedAt);
    } else if (mode === 'title_asc') {
      arr.sort((a: HistoryItem, b: HistoryItem): number => this.compareTitle(a.title, b.title));
    } else if (mode === 'title_desc') {
      arr.sort((a: HistoryItem, b: HistoryItem): number => -this.compareTitle(a.title, b.title));
    } else {
      arr.sort((a: HistoryItem, b: HistoryItem): number => b.viewedAt - a.viewedAt);
    }
    return arr;
  }

  private async applySort(kind: string, value: string): Promise<void> {
    try {
      const prefs: Prefs = await Prefs.getInstance();
      if (kind === 'fav') {
        this.favSortMode = value;
        await prefs.setFavSort(value);
        this.favDS.reload(this.sortedFavs(this.favItems, value));
      } else {
        this.historySortMode = value;
        await prefs.setHistorySort(value);
        this.historyDS.reload(this.sortedHistory(this.historyItems, value));
      }
    } catch (e) {
      this.showToast('排序保存失败');
    }
  }

  /* ===== 阅读进度（B-02 / B-04） ===== */

  private findProgress(aid: string): ReadingProgress | null {
    for (const p of this.progressList) {
      if (p.aid === aid) {
        return p;
      }
    }
    return null;
  }

  private progressLine(p: ReadingProgress): string {
    // p.page 为 0 基页码（ReaderPage.onScrollIndex 写入 currentPage），显示时 +1
    // 与 AlbumDetailPage（P.${p.page + 1}）、阅读器页码（currentPage + 1）口径一致
    const page: number = p.page + 1;
    let line: string = `读至 ${chapterLabel(p.chapterIndex)} P.${page}`;
    if (p.totalPages > 0) {
      line = `${line} / 共${p.totalPages}页`;
    }
    return line;
  }

  private favSubtitle(item: FavItem): string {
    const p: ReadingProgress | null = this.findProgress(item.id);
    if (p !== null && p.chapterIndex >= 0) {
      return this.progressLine(p);
    }
    return item.author;
  }

  private historyProgressText(item: HistoryItem): string {
    const p: ReadingProgress | null = this.findProgress(item.id);
    if (p !== null && p.chapterIndex >= 0) {
      return this.progressLine(p);
    }
    if (item.author !== '') {
      return item.author;
    }
    return '点击开始阅读';
  }

  /* ===== 导航 ===== */

  private openAlbum(aid: string): void {
    const p: AlbumRouteParam = new AlbumRouteParam();
    p.aid = aid;
    this.pageStack.pushPathByName(ROUTE_ALBUM, p);
  }

  private openSearch(query: string): void {
    const p: SearchRouteParam = new SearchRouteParam();
    p.query = query;
    this.pageStack.pushPathByName(ROUTE_SEARCH, p);
  }

  private openDownloads(): void {
    this.pageStack.pushPathByName(ROUTE_DOWNLOADS, new DownloadsRouteParam());
  }

  private openReader(aid: string, chapterIndex: number, page: number): void {
    const p: ReaderRouteParam = new ReaderRouteParam();
    p.aid = aid;
    if (chapterIndex >= 0) {
      p.chapterIndex = chapterIndex;
    }
    if (page > 0) {
      p.page = page;
    }
    this.pageStack.pushPathByName(ROUTE_READER, p);
  }

  /** 历史/横幅续读：有精确进度则携带 {chapterIndex, page}，否则仅 aid（阅读器默认定位） */
  private resumeReading(aid: string): void {
    const p: ReadingProgress | null = this.findProgress(aid);
    if (p !== null && p.chapterIndex >= 0) {
      this.openReader(p.aid, p.chapterIndex, p.page);
    } else {
      this.openReader(aid, -1, -1);
    }
  }

  private switchSeg(index: number): void {
    if (this.segIndex === index) {
      return;
    }
    if (this.selectMode) {
      this.exitSelect(); // 切段退出历史多选态
    }
    this.segIndex = index;
    this.refresh(false);
  }

  /* ===== 手动添加（B-06：jm 号 → 收藏本子；#开头/其它 → 收藏标签） ===== */

  private async submitAdd(): Promise<void> {
    const text: string = this.addInput.trim();
    if (text === '' || this.adding) {
      return;
    }
    const match: RegExpExecArray | null = ADD_ID_PATTERN.exec(text);
    if (match !== null && !text.startsWith('#')) {
      this.adding = true;
      try {
        const album: Album = await jmApi.album(match[1]);
        await favStore.add(album, jmApi.albumCoverUrl(album.id));
        this.addInput = '';
        this.showToast(`已添加本子 JM${album.id}`);
        await this.refresh(false);
      } catch (e) {
        this.showToast(`添加失败：${errorMessage(e as Error)}`);
      } finally {
        this.adding = false;
      }
    } else {
      const tag: string = text.replace(/^[#＃]/, '').trim();
      if (tag !== '') {
        await favStore.addTag(tag);
        this.addInput = '';
        this.showToast(`已添加标签：${tag}`);
        await this.refresh(false);
      }
    }
  }

  /* ===== 确认弹层（长按移除收藏/标签、清空历史、批量删除所选历史） ===== */

  private hasConfirm(): boolean {
    return this.pendingFavId !== '' || this.pendingTag !== '' || this.showClearHistory
      || this.showDeleteHistory;
  }

  private cancelConfirm(): void {
    this.pendingFavId = '';
    this.pendingFavTitle = '';
    this.pendingTag = '';
    this.showClearHistory = false;
    this.showDeleteHistory = false;
  }

  private confirmTitle(): string {
    if (this.pendingFavId !== '') {
      return '取消收藏';
    }
    if (this.pendingTag !== '') {
      return '移除标签';
    }
    if (this.showDeleteHistory) {
      return '删除所选历史';
    }
    return '清空历史记录';
  }

  private confirmMessage(): string {
    if (this.pendingFavId !== '') {
      return `将「${this.pendingFavTitle}」从本地收藏中移除？`;
    }
    if (this.pendingTag !== '') {
      return `将标签「${this.pendingTag}」从收藏中移除？`;
    }
    if (this.showDeleteHistory) {
      return `将删除选中的 ${this.selectedIds.length} 条浏览历史，确定吗？`;
    }
    return `将删除全部 ${this.historyItems.length} 条浏览历史，确定吗？`;
  }

  private async doConfirm(): Promise<void> {
    if (this.pendingFavId !== '') {
      const id: string = this.pendingFavId;
      this.cancelConfirm();
      await favStore.remove(id);
      this.showToast('已移除收藏');
      await this.refresh(false);
      return;
    }
    if (this.pendingTag !== '') {
      const tag: string = this.pendingTag;
      this.cancelConfirm();
      await favStore.removeTag(tag);
      this.showToast('已移除标签');
      await this.refresh(false);
      return;
    }
    if (this.showDeleteHistory) {
      const ids: Array<string> = this.selectedIds.slice();
      this.cancelConfirm();
      await historyStore.removeAll(ids);
      this.exitSelect();
      this.showToast(`已删除 ${ids.length} 条历史`);
      await this.refresh(false);
      return;
    }
    if (this.showClearHistory) {
      this.showClearHistory = false;
      await historyStore.clear();
      this.showToast('已清空历史');
      await this.refresh(false);
    }
  }

  /* ===== 历史段多选操作（B-10：长按进入多选 + 全选/取消全选 + 批量删除） ===== */

  private isHistorySelected(id: string): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private toggleHistorySelect(id: string): void {
    if (this.isHistorySelected(id)) {
      this.selectedIds = this.selectedIds.filter((i: string): boolean => i !== id);
    } else {
      this.selectedIds = this.selectedIds.concat([id]);
    }
  }

  private allHistorySelected(): boolean {
    return this.historyItems.length > 0 && this.selectedIds.length === this.historyItems.length;
  }

  private toggleHistorySelectAll(): void {
    if (this.allHistorySelected()) {
      this.selectedIds = [];
      return;
    }
    const ids: Array<string> = [];
    for (const h of this.historyItems) {
      ids.push(h.id);
    }
    this.selectedIds = ids;
  }

  private enterHistorySelect(id: string): void {
    this.selectMode = true;
    this.selectedIds = [id];
  }

  private exitSelect(): void {
    this.selectMode = false;
    this.selectedIds = [];
  }

  /* ===== 下载摘要辅助（B-12） ===== */

  private countByState(state: DownloadState): number {
    let n: number = 0;
    for (const t of this.dlTasks) {
      if (t.state === state) {
        n++;
      }
    }
    return n;
  }

  private progressValue(t: DownloadTask): number {
    if (t.exporting && t.exportTotal > 0) {
      return Math.min(100, t.exportDone / t.exportTotal * 100);
    }
    if (t.total > 0) {
      return Math.min(100, t.done / t.total * 100);
    }
    return 0;
  }

  private statusText(t: DownloadTask): string {
    if (t.state === 'queued') {
      return '排队中…';
    }
    if (t.state === 'running') {
      if (t.exporting) {
        return `导出中 ${t.exportDone}/${t.exportTotal}`;
      }
      return `下载中 ${t.done}/${t.total}`;
    }
    if (t.state === 'paused') {
      return `已暂停 ${t.done}/${t.total}`;
    }
    if (t.state === 'done') {
      return '已完成 · CBZ 已导出';
    }
    if (t.state === 'failed') {
      return `失败：${t.error === '' ? '未知错误' : t.error}`;
    }
    return '已取消';
  }

  private stateLabel(state: DownloadState): string {
    if (state === 'queued') {
      return '等待';
    }
    if (state === 'running') {
      return '下载中';
    }
    if (state === 'paused') {
      return '暂停';
    }
    if (state === 'done') {
      return '完成';
    }
    if (state === 'failed') {
      return '失败';
    }
    return '已取消';
  }

  private badgeTextColor(state: DownloadState): ResourceColor {
    if (state === 'running' || state === 'done' || state === 'failed') {
      return Color.White;
    }
    if (state === 'queued') {
      return TEXT_SUB;
    }
    return TEXT_MAIN;
  }

  private badgeBgColor(state: DownloadState): ResourceColor {
    if (state === 'running') {
      return ACCENT;
    }
    if (state === 'done') {
      return PRIMARY;
    }
    if (state === 'failed') {
      return MASK_DARK;
    }
    if (state === 'queued') {
      return CHIP_BG;
    }
    return DIVIDER;
  }

  private summaryTasks(): Array<DownloadTask> {
    return this.dlTasks.slice(0, Math.min(SUMMARY_MAX, this.dlTasks.length));
  }

  /* ===== 轻提示 ===== */

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000, bottom: '35%' });
    } catch (e) {
      // 提示失败可忽略
    }
  }

  /* ===== UI 构建 ===== */

  build() {
    Stack() {
      Column() {
        Row() {
          Text('书架')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_MAIN)
        }
        .width('100%')
        // 评审 Step2：标题行叠加状态栏避让高度（原有 top: 10 基础上加 topInset）
        .padding({ left: 16, right: 16, top: this.topInset + 10, bottom: 6 })

        if (this.latestProgress.aid !== '') {
          this.ResumeBanner()
        }

        this.SegmentBar()

        if (this.loading) {
          Column() {
            SkeletonGrid({ columns: this.gridColumns(), rows: 3 })
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 24 })
        } else if (this.loadError !== '') {
          Column() {
            EmptyView({
              message: `加载失败：${this.loadError}`,
              showRetry: true,
              onRetry: (): void => {
                this.refresh(true);
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          if (this.segIndex === 0) {
            this.FavoritesSegment()
          } else if (this.segIndex === 1) {
            this.HistorySegment()
          } else {
            this.DownloadsSegment()
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)

      if (this.hasConfirm()) {
        this.ConfirmOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 三段切换（B-01：SegmentButton 风格自绘胶囊，禁第三方依赖） */
  @Builder
  private SegmentBar() {
    Row({ space: 6 }) {
      this.SegButton(0, '收藏')
      this.SegButton(1, '历史')
      this.SegButton(2, '下载')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 10 })
  }

  @Builder
  private SegButton(index: number, label: string) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.segIndex === index ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.segIndex === index ? Color.White : TEXT_SUB)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 7, bottom: 7 })
      .backgroundColor(this.segIndex === index ? PRIMARY : CHIP_BG)
      .borderRadius(CHIP_R)
      .onClick(() => {
        this.switchSeg(index);
      })
  }

  /** 顶部一键续读横幅（B-02）：取最近一条精确阅读进度，点击直进阅读器携带进度 */
  @Builder
  private ResumeBanner() {
    Row({ space: 12 }) {
      Image(this.latestProgress.coverUrl)
        .width(44)
        .height(58)
        .borderRadius(COVER_R)
        .objectFit(ImageFit.Cover)
        .backgroundColor(CHIP_BG)
      Column({ space: 4 }) {
        Text(`继续阅读《${this.latestProgress.title}》`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_MAIN)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.progressLine(this.latestProgress))
          .fontSize(11)
          .fontColor(TEXT_SUB)
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('继续阅读')
        .fontSize(12)
        .fontColor(Color.White)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(ACCENT)
        .borderRadius(CHIP_R)
    }
    .width('100%')
    .padding(10)
    .backgroundColor(CARD)
    .borderRadius(CARD_R)
    .margin({ left: 16, right: 16, bottom: 4 })
    .onClick(() => {
      this.openReader(this.latestProgress.aid, this.latestProgress.chapterIndex, this.latestProgress.page);
    })
  }

  /** 收藏段（B-04/B-05/B-06/B-07/B-08） */
  @Builder
  private FavoritesSegment() {
    Column() {
      Row({ space: 8 }) {
        TextInput({ text: this.addInput, placeholder: 'jm350234 或 #标签' })
          .onChange((value: string) => {
            this.addInput = value;
          })
          .onSubmit(() => {
            this.submitAdd();
          })
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .backgroundColor(CARD)
          .borderRadius(CHIP_R)
          .padding({ left: 12, right: 12 })
        Text(this.adding ? '添加中…' : '添加')
          .fontSize(13)
          .fontColor(Color.White)
          .padding({ left: 14, right: 14, top: 9, bottom: 9 })
          .backgroundColor(this.adding ? TAB_INACTIVE : ACCENT)
          .borderRadius(CHIP_R)
          .onClick(() => {
            this.submitAdd();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 8 })

      if (this.favTags.length > 0) {
        Column({ space: 6 }) {
          Text('标签（点按搜索 · 长按移除）')
            .fontSize(11)
            .fontColor(TEXT_SUB)
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
            ForEach(this.favTags, (tag: string) => {
              Column() {
                TagChip({
                  label: tag,
                  selected: false,
                  onChipClick: (): void => {
                    this.openSearch(tag);
                  }
                })
              }
              .margin({ right: 8, bottom: 6 })
              .gesture(LongPressGesture().onAction(() => {
                this.pendingTag = tag;
              }))
            }, (tag: string) => tag)
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, bottom: 6 })
      }

      Row({ space: 6 }) {
        Text('本子（长按移除）')
          .fontSize(11)
          .fontColor(TEXT_SUB)
          .layoutWeight(1)
        this.SortChip('最新', 'time_desc', this.favSortMode, 'fav')
        this.SortChip('最早', 'time_asc', this.favSortMode, 'fav')
        this.SortChip('标题↑', 'title_asc', this.favSortMode, 'fav')
        this.SortChip('标题↓', 'title_desc', this.favSortMode, 'fav')
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      if (this.favItems.length === 0) {
        Column() {
          EmptyView({ message: '还没有收藏～ 在详情页点 ♥ 即可加入', showRetry: false })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          LazyForEach(this.favDS, (item: FavItem) => {
            GridItem() {
              this.FavCell(item)
            }
          }, (item: FavItem) => item.id)
        }
        .columnsTemplate(this.columnsTemplateStr())
        .columnsGap(12)
        .rowsGap(14)
        // 评审 Step2（P1）：sm 断点底部预留 Tab 栏 + 导航条，md/lg 仅导航条
        .padding({ left: 16, right: 16, bottom: this.tabAvoidBottom() })
        .cachedCount(6)
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private FavCell(item: FavItem) {
    Column() {
      ComicCard({
        coverUrl: item.coverUrl,
        aid: item.id, // 评审 Step3：补传 aid，封面加载失败时 ComicCard 按 id 轮换备用图床
        title: item.title,
        author: this.favSubtitle(item),
        badge: '',
        loading: false,
        onCardClick: (): void => {
          this.openAlbum(item.id);
        }
      })
    }
    .width('100%')
    .gesture(LongPressGesture().onAction(() => {
      this.pendingFavId = item.id;
      this.pendingFavTitle = item.title;
    }))
  }

  @Builder
  private SortChip(label: string, value: string, current: string, kind: string) {
    Text(label)
      .fontSize(11)
      .fontColor(current === value ? Color.White : TEXT_SUB)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor(current === value ? PRIMARY : CHIP_BG)
      .borderRadius(CHIP_R)
      .onClick(() => {
        this.applySort(kind, value);
      })
  }

  /** 历史段（B-09 排序+清空；B-10 长按多选 + 全选/取消全选 + 批量删除；点击续读） */
  @Builder
  private HistorySegment() {
    Column() {
      if (this.selectMode) {
        // B-10 多选态顶栏：已选 N 项 + 全选/取消全选 + 退出（同 DownloadsPage 交互）
        Row() {
          Text(`已选 ${this.selectedIds.length} 项`)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_MAIN)
            .layoutWeight(1)
          Text(this.allHistorySelected() ? '取消全选' : '全选')
            .fontSize(13)
            .fontColor(PRIMARY)
            .padding({ left: 8, right: 8 })
            .onClick(() => {
              this.toggleHistorySelectAll();
            })
          Text('退出')
            .fontSize(13)
            .fontColor(TEXT_SUB)
            .padding({ left: 8, right: 8 })
            .onClick(() => {
              this.exitSelect();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 6, bottom: 10 })
      } else {
        Row({ space: 6 }) {
          Text(`历史（${this.historyItems.length}）`)
            .fontSize(11)
            .fontColor(TEXT_SUB)
            .layoutWeight(1)
          this.SortChip('最新', 'time_desc', this.historySortMode, 'history')
          this.SortChip('最早', 'time_asc', this.historySortMode, 'history')
          this.SortChip('标题↑', 'title_asc', this.historySortMode, 'history')
          this.SortChip('标题↓', 'title_desc', this.historySortMode, 'history')
          Text('清空')
            .fontSize(11)
            .fontColor(PRIMARY)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .onClick(() => {
              this.showClearHistory = true;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
      }

      if (this.historyItems.length === 0) {
        Column() {
          EmptyView({ message: '还没有浏览历史（可在设置中关闭记录）', showRetry: false })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          LazyForEach(this.historyDS, (item: HistoryItem) => {
            ListItem() {
              this.HistoryRow(item)
            }
          }, (item: HistoryItem) => item.id)
        }
        .width('100%')
        .layoutWeight(1)
        .cachedCount(8)
        // 评审 Step2（P1）：非多选态列表底部预留 Tab 栏避让（多选态由底部操作条 margin 承担）
        .padding({ bottom: this.selectMode ? 0 : this.tabAvoidBottom() })

        if (this.selectMode) {
          // B-10 多选态底栏：删除所选 / 完成
          Row({ space: 10 }) {
            Text('删除所选')
              .fontSize(14)
              .fontColor(Color.White)
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .padding({ top: 10, bottom: 10 })
              .backgroundColor(PRIMARY)
              .borderRadius(CHIP_R)
              .onClick(() => {
                if (this.selectedIds.length > 0) {
                  this.showDeleteHistory = true;
                }
              })
            Text('完成')
              .fontSize(14)
              .fontColor(TEXT_MAIN)
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .padding({ top: 10, bottom: 10 })
              .backgroundColor(CHIP_BG)
              .borderRadius(CHIP_R)
              .onClick(() => {
                this.exitSelect();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          // 评审 Step2（P1）：多选底栏整体上移 Tab 栏避让高度，确保「删除所选 / 完成」完整露出
          .margin({ bottom: this.tabAvoidBottom() })
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private HistoryRow(item: HistoryItem) {
    Row({ space: 12 }) {
      if (this.selectMode) {
        Checkbox()
          .select(this.isHistorySelected(item.id))
          .selectedColor(PRIMARY)
          .onChange((_v: boolean) => {
            this.toggleHistorySelect(item.id);
          })
      }
      Image(item.coverUrl)
        .width(52)
        .height(70)
        .borderRadius(COVER_R)
        .objectFit(ImageFit.Cover)
        .backgroundColor(CHIP_BG)
      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_MAIN)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.historyProgressText(item))
          .fontSize(11)
          .fontColor(TEXT_SUB)
          .maxLines(1)
        if (item.viewedAt > 0) {
          Text(formatDateTime(item.viewedAt))
            .fontSize(10)
            .fontColor(TAB_INACTIVE)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(18)
        .fontColor(TAB_INACTIVE)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .onClick(() => {
      if (this.selectMode) {
        this.toggleHistorySelect(item.id);
      } else {
        this.resumeReading(item.id);
      }
    })
    .gesture(LongPressGesture().onAction(() => {
      if (!this.selectMode) {
        this.enterHistorySelect(item.id);
      }
    }))
  }

  /** 下载段（B-12）：任务摘要列表 + 进入下载管理入口 */
  @Builder
  private DownloadsSegment() {
    Column({ space: 10 }) {
      Row() {
        Text(`下载任务（${this.dlTasks.length}）`)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)
        Text('进入下载管理 ›')
          .fontSize(13)
          .fontColor(PRIMARY)
          .onClick(() => {
            this.openDownloads();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4 })

      Row({ space: 8 }) {
        this.CountChip(`下载中 ${this.countByState('running')}`)
        this.CountChip(`等待 ${this.countByState('queued')}`)
        this.CountChip(`已完成 ${this.countByState('done')}`)
        this.CountChip(`失败 ${this.countByState('failed')}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      if (this.dlTasks.length === 0) {
        Column() {
          EmptyView({ message: '还没有下载任务～ 去详情页点「下载」生成 CBZ 吧', showRetry: false })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column({ space: 8 }) {
          ForEach(this.summaryTasks(), (t: DownloadTask) => {
            this.DlSummaryRow(t)
          }, (t: DownloadTask) => `dl_${t.id}`)
          if (this.dlTasks.length > SUMMARY_MAX) {
            Text(`还有 ${this.dlTasks.length - SUMMARY_MAX} 个任务，进入下载管理查看`)
              .fontSize(11)
              .fontColor(TEXT_SUB)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .layoutWeight(1)
    // 评审 Step2（P1）：下载摘要段底部预留 Tab 栏避让，末行不被底栏遮挡
    .padding({ bottom: this.tabAvoidBottom() })
  }

  @Builder
  private CountChip(label: string) {
    Text(label)
      .fontSize(10)
      .fontColor(TEXT_SUB)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .backgroundColor(CHIP_BG)
      .borderRadius(CHIP_R)
  }

  @Builder
  private DlSummaryRow(t: DownloadTask) {
    Row({ space: 10 }) {
      if (t.cover !== '') {
        Image(t.cover)
          .width(36)
          .height(48)
          .borderRadius(COVER_R)
          .objectFit(ImageFit.Cover)
          .backgroundColor(CHIP_BG)
      }
      Column({ space: 4 }) {
        Text(t.title)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_MAIN)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (t.state === 'running' || t.state === 'queued' || t.state === 'paused') {
          Progress({ value: this.progressValue(t), total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(4)
            .color(PRIMARY)
            .backgroundColor(DIVIDER)
        }
        Text(this.statusText(t))
          .fontSize(10)
          .fontColor(TEXT_SUB)
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(this.stateLabel(t.state))
        .fontSize(10)
        .fontColor(this.badgeTextColor(t.state))
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .backgroundColor(this.badgeBgColor(t.state))
        .borderRadius(CHIP_R)
    }
    .width('100%')
    .padding(10)
    .backgroundColor(CARD)
    .borderRadius(CARD_R)
    .onClick(() => {
      this.openDownloads();
    })
  }

  /** 居中确认弹层（无依赖自绘：标题 + 说明 + 取消/确定） */
  @Builder
  private ConfirmOverlay() {
    Column() {
      Column({ space: 14 }) {
        Text(this.confirmTitle())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
        Text(this.confirmMessage())
          .fontSize(13)
          .fontColor(TEXT_SUB)
          .textAlign(TextAlign.Center)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Divider()
          .color(DIVIDER)
        Row() {
          Text('取消')
            .fontSize(15)
            .fontColor(TEXT_SUB)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 10, bottom: 10 })
            .onClick(() => {
              this.cancelConfirm();
            })
          Text('确定')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(PRIMARY)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 10, bottom: 10 })
            .onClick(() => {
              this.doConfirm();
            })
        }
        .width('100%')
      }
      .width('84%')
      .padding({ left: 20, right: 20, top: 20, bottom: 8 })
      .borderRadius(CARD_R)
      .backgroundColor(CARD)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(MASK_DARK)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
