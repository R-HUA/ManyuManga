/**
 *
 * 规范来源：
 *  - uiux-design.md 第四.2 节（折叠视差头部 / 元数据 / 主次 CTA / 章节列表 / 预览抽屉化）与布局示意；
 *
 */

import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import pasteboard from '@ohos.pasteboard';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import { ROUTE_SEARCH, ROUTE_READER } from '../common/Route';
import {
  PRIMARY,
  ACCENT,
  BG,
  CARD,
  TEXT_MAIN,
  TEXT_SUB,
  CHIP_BG,
  DIVIDER,
  COVER_R,
  CARD_R,
  CHIP_R,
  COVER_ASPECT_RATIO,
  MASK_DARK
} from '../common/Theme';
import { EmptyView, SectionTitle } from '../common/Components';
import {
  Album,
  Chapter,
  CommentItem,
  CommentsResult,
  ReadingProgress,
  asRecord,
  asString,
  errorMessage
} from '../models/Models';
import { sourceApi as jmApi } from '../data/SourceApi';
import {
  favStore,
  historyStore,
  readProgressStore,
  albumCacheStore,
  pagesCacheStore
} from '../data/Stores';
import { downloadManager, DownloadTask } from '../data/DownloadManager';
import { loadPagePixelMap, releasePagePixelMap } from '../data/ImageDecode';
import { Prefs } from '../util/Prefs';
import { IS_DARK_MODE_KEY } from '../entryability/EntryAbility';

// ───────────────────────── 常量 ─────────────────────────

/** 视差头部模糊背景高度（uiux 范式 340） */
const HEADER_BG_H: number = 340;
/** 顶栏渐显起始滚动偏移与过渡区间（D-01：上滑超阈值后渐显书名） */
const TOOLBAR_FADE_START: number = 110;
const TOOLBAR_FADE_RANGE: number = 120;
/** 胶片条预览页数（uiux：前 8 页精简胶片条） */
const PREVIEW_STRIP_COUNT: number = 8;
/** 缩略图解码目标宽度（原 PageLoader targetWidth=360） */
const THUMB_WIDTH: number = 360;
/** 官方链接域名（D-03） */
const OFFICIAL_LINK_BASE: string = 'https://18comic.vip/photo/';

// 顶栏图标/底色随渐显插值的两端（一次性 rgba，conventions §5 允许内联）
const T_ICON_A: string = 'rgba(255,255,255,1)';
const T_ICON_B: string = 'rgba(30,41,59,1)';
const T_CHIP_A: string = 'rgba(0,0,0,0.22)';
const T_CHIP_B: string = 'rgba(255,255,255,0.85)';
const T_BG_A: string = 'rgba(247,248,250,0)';
const T_BG_B: string = 'rgba(247,248,250,0.97)';

// ───────────────────────── 路由参数 ─────────────────────────

class SearchRouteParam {
  query: string = '';
}

class ReaderRouteParam {
  aid: string = '';
  chapterId: number = -1;
  chapterIndex: number = 0;
  page: number = 0;
}

// ───────────────────────── 预览页条目 ─────────────────────────

class PreviewPageItem {
  filename: string = '';
  index: number = 0;
}

/** 章节数据源 */
class ChaptersDataSource implements IDataSource {
  private items: Array<Chapter> = [];
  private listeners: Array<DataChangeListener> = [];

  setItems(items: Array<Chapter>): void {
    this.items = items;
    this.notifyReload();
  }

  /** 外部状态（阅读进度）变化后强制重建行（已读置灰 / 上次读到胶囊） */
  reload(): void {
    this.notifyReload();
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): Chapter {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener);
  }

  private notifyReload(): void {
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }
}

/** 全量预览缩略图数据源（bindSheet 内 Grid + LazyForEach） */
class PreviewDataSource implements IDataSource {
  private items: Array<PreviewPageItem> = [];
  private listeners: Array<DataChangeListener> = [];

  setItems(items: Array<PreviewPageItem>): void {
    this.items = items;
    this.notifyReload();
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): PreviewPageItem {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener);
  }

  private notifyReload(): void {
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }
}

// ───────────────────────── 通用辅助函数 ─────────────────────────

/** 数字本地化：10591 → 1.1万（conventions §8） */
function formatCount(raw: string): string {
  if (raw === '') {
    return '0';
  }
  const n: number = Number(raw);
  if (Number.isNaN(n) || n < 0) {
    return raw;
  }
  if (n >= 10000) {
    const w: number = Math.round(n / 1000) / 10;
    let s: string = `${w}`;
    if (s.endsWith('.0')) {
      s = s.substring(0, s.length - 2);
    }
    return `${s}万`;
  }
  return `${n}`;
}

/** 评论时间格式化 yyyy-MM-dd HH:mm（CommentsScreen.kt:212-217；异常回退原串前 16 位） */
function formatCommentTime(raw: string): string {
  if (raw === '') {
    return '';
  }
  const sec: number = Number(raw);
  if (Number.isNaN(sec) || sec <= 0) {
    return raw.length > 16 ? raw.substring(0, 16) : raw;
  }
  const d: Date = new Date(sec * 1000);
  const p2 = (n: number): string => {
    return n < 10 ? `0${n}` : `${n}`;
  };
  return `${d.getFullYear()}-${p2(d.getMonth() + 1)}-${p2(d.getDate())} ${p2(d.getHours())}:${p2(d.getMinutes())}`;
}

function parseRgba(s: string): Array<number> | null {
  const inner: string = s.replace('rgba(', '').replace(')', '').trim();
  const parts: Array<string> = inner.split(',');
  if (parts.length !== 4) {
    return null;
  }
  const out: Array<number> = [];
  for (let i: number = 0; i < 4; i++) {
    const n: number = Number(parts[i].trim());
    if (Number.isNaN(n)) {
      return null;
    }
    out.push(n);
  }
  return out;
}

/** 两端 rgba 插值（顶栏随滚动渐显的颜色过渡） */
function mixRgba(from: string, to: string, ratio: number): string {
  const a: Array<number> | null = parseRgba(from);
  const b: Array<number> | null = parseRgba(to);
  if (a === null || b === null) {
    return ratio < 0.5 ? from : to;
  }
  const t: number = Math.min(1, Math.max(0, ratio));
  const r: number = Math.round(a[0] + (b[0] - a[0]) * t);
  const g: number = Math.round(a[1] + (b[1] - a[1]) * t);
  const bl: number = Math.round(a[2] + (b[2] - a[2]) * t);
  const alpha: number = Math.round((a[3] + (b[3] - a[3]) * t) * 1000) / 1000;
  return `rgba(${r},${g},${bl},${alpha})`;
}

// ───────────────────────── 下载确认弹窗（D-16 简化版） ─────────────────────────

@CustomDialog
struct DownloadConfirmDialog {
  // @CustomDialog 标准模式：controller 由框架注入，无需（也不可）零参构造
  controller?: CustomDialogController;
  @State remember: boolean = false;
  onCancel: () => void = () => {};
  onConfirm: (remember: boolean) => void = () => {};

  build() {
    Column({ space: 14 }) {
      Text('下载设置')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
      Text('格式：CBZ（ZIP 无损存档）')
        .fontSize(13)
        .fontColor(TEXT_MAIN)
      Text('图像：解密后原格式（先反混淆再打包）')
        .fontSize(13)
        .fontColor(TEXT_SUB)
      Row({ space: 8 }) {
        Checkbox()
          .width(20)
          .height(20)
          .select(this.remember)
          .selectedColor(PRIMARY)
          .onChange((value: boolean) => {
            this.remember = value;
          })
        Text('以后不再弹出')
          .fontSize(13)
          .fontColor(TEXT_MAIN)
      }
      .width('100%')
      .margin({ top: 4 })

      Row({ space: 12 }) {
        Button('取消')
          .fontSize(14)
          .fontColor(TEXT_SUB)
          .backgroundColor(CHIP_BG)
          .borderRadius(CARD_R)
          .layoutWeight(1)
          .onClick(() => {
            this.onCancel();
          })
        Button('开始下载')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(ACCENT)
          .borderRadius(CARD_R)
          .layoutWeight(1)
          .onClick(() => {
            this.onConfirm(this.remember);
          })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .padding(22)
    .backgroundColor(CARD)
    .borderRadius(CARD_R)
  }
}

// ───────────────────────── 预览缩略图组件（D-12 解码链路承接 ImageDecode） ─────────────────────────

/**
 * 单页缩略图：loadPagePixelMap（网络/缓存字节 → 原尺寸反混淆 → 缩放到 360），
 * 三态：加载骨架 / 失败点按重试 / 成功；点按进阅读器定位该页。
 */
@Component
struct PageThumb {
  @Prop photoId: string = '';
  @Prop filename: string = '';
  @Prop scrambleId: number = 220980;
  @Prop targetWidth: number = THUMB_WIDTH;
  @Prop label: string = '';
  onTap: () => void = () => {};
  @State pm: image.PixelMap | null = null;
  @State failed: boolean = false;
  @State pulse: number = 1;

  aboutToAppear(): void {
    this.fetch();
  }

  aboutToDisappear(): void {
    const pm: image.PixelMap | null = this.pm;
    if (pm !== null) {
      releasePagePixelMap(pm);
    }
  }

  private fetch(): void {
    this.failed = false;
    if (this.pm !== null) {
      releasePagePixelMap(this.pm);
      this.pm = null;
    }
    const photoId: string = this.photoId;
    const filename: string = this.filename;
    const sid: number = this.scrambleId;
    const width: number = this.targetWidth;
    loadPagePixelMap(photoId, filename, sid, width).then((result: image.PixelMap | null) => {
      if (result === null) {
        this.failed = true;
      } else {
        this.pm = result;
      }
    }).catch((e: Error) => {
      this.failed = true;
      console.info(`[AlbumDetail] 缩略图加载失败 ${filename}: ${errorMessage(e)}`);
    });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.pm !== null) {
        Image(this.pm)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
      } else if (this.failed) {
        Column({ space: 2 }) {
          Text('加载失败')
            .fontSize(10)
            .fontColor(TEXT_SUB)
          Text('点按重试')
            .fontSize(10)
            .fontColor(PRIMARY)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(BG)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(DIVIDER)
          .opacity(this.pulse)
          .onAppear(() => {
            this.getUIContext().animateTo({ duration: 800, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate }, () => {
              this.pulse = 0.45;
            });
          })
      }
      if (this.label !== '') {
        Text(this.label)
          .fontSize(9)
          .fontColor(Color.White)
          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          .backgroundColor('rgba(0,0,0,0.45)')
          .borderRadius(6)
          .margin(4)
      }
    }
    .width('100%')
    .aspectRatio(0.7)
    .borderRadius(8)
    .clip(true)
    .onClick(() => {
      if (this.failed) {
        this.fetch();
        return;
      }
      this.onTap();
    })
  }
}

// ───────────────────────── 页面 ─────────────────────────

@Component
export struct AlbumDetailPage {
  @Consume('navPathStack') pageStack: NavPathStack;

  // 基础状态
  @State aid: string = '';
  @State album: Album | null = null;
  @State loadState: string = 'loading'; // 'loading' | 'error' | 'ready'
  @State errorMsg: string = '';

    // 元数据与本地状态
  @State isFav: boolean = false;
  @State favTags: Array<string> = [];
  @State displayedTags: Array<string> = [];
  @State progress: ReadingProgress | null = null;
  @State chaptersDescending: boolean = false;

  // 预览（D-11/D-12）
  @State previewPages: Array<string> = [];
  @State previewSid: number = 220980;
  @State previewLoading: boolean = false;
  @State previewError: string = '';
  @State previewSheetOpen: boolean = false;

  // 评论（CM-01~CM-06）
  @State commentsSheetOpen: boolean = false;
  @State comments: Array<CommentItem> = [];
  @State commentsTotal: number = 0;
  @State commentsPage: number = 0;
  @State commentsLoading: boolean = false;
  @State commentsError: string = '';
  @State commentsFetched: boolean = false;
  @State commentsSort: string = 'new'; // 'hot' | 'new'（本地排序，接口无参数）
  @State revealedIds: Array<string> = [];
  @State commentTotalBadge: number = -1;
  @State commentDraft: string = '';

  // 视差与动效
  @State toolbarAlpha: number = 0;
  /** 状态栏当前是否白字（滚动联动，评审 Step3）；进入详情页头部为深色图域 */
  private barLightText: boolean = true;
  @State topInset: number = 0;
  @State favScale: number = 1;
  @State skelAlpha: number = 1;
  @State coverViewerOpen: boolean = false;

  // 下载（D-17/D-18）
  @State dlTask: DownloadTask | null = null;

  // 非响应式成员
  private scroller: Scroller = new Scroller();
  private chaptersDs: ChaptersDataSource = new ChaptersDataSource();
  private previewDs: PreviewDataSource = new PreviewDataSource();
  private chapAscIndex: Map<string, number> = new Map<string, number>();
  private previewPhotoId: string = '';
  private historyRecorded: boolean = false;
  /** 已应用过附属状态拉取的本子 id（缓存与网络双写去重） */
  private appliedAid: string = '';
  private downloadDlg: CustomDialogController = new CustomDialogController({
    builder: DownloadConfirmDialog({
      onCancel: (): void => {
        this.downloadDlg.close();
      },
      onConfirm: (remember: boolean): void => {
        this.downloadDlg.close();
        this.doEnqueue(remember);
      }
    }),
    autoCancel: true,
    customStyle: true
  });
  private dlListener: (task: DownloadTask) => void = (task: DownloadTask): void => {
    this.onDlTask(task);
  };

  // ───────────────────────── 生命周期 ─────────────────────────

  aboutToAppear(): void {
    this.measureTopInset();
    downloadManager.onChange(this.dlListener);
    downloadManager.init().then((): void => {
      this.refreshDlState();
    }).catch((e: Error): void => {
      console.info(`[AlbumDetail] 下载队列恢复失败: ${errorMessage(e)}`);
    });
  }

  aboutToDisappear(): void {
    downloadManager.offChange(this.dlListener);
  }

  // ───────────────────────── 路由与加载 ─────────────────────────

  private measureTopInset(): void {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    if (ctx === undefined) {
      this.topInset = 38;
      return;
    }
    window.getLastWindow(ctx).then((win: window.Window): void => {
      const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const h: number = this.getUIContext().px2vp(area.topRect.height);
      this.topInset = h > 0 ? h : 38;
    }).catch((): void => {
      this.topInset = 38;
    });
  }

  private async loadAll(): Promise<void> {
    const aid: string = this.aid;
    // D-14 缓存秒开：AlbumCache 优先展示
    try {
      if (this.album === null) {
        const cached: Album | null = await albumCacheStore.get(aid);
        if (cached !== null) {
          this.applyAlbum(cached);
        }
      }
    } catch (e) {
      console.info(`[AlbumDetail] 缓存读取失败: ${errorMessage(e as Error)}`);
    }
    // 网络刷新替换；失败保留缓存（无缓存才进错误态）
    try {
      const fresh: Album = await jmApi.album(aid);
      this.applyAlbum(fresh);
      albumCacheStore.put(fresh).catch((): void => {});
    } catch (e) {
      if (this.album === null) {
        this.errorMsg = errorMessage(e as Error);
        this.loadState = 'error';
      } else {
        console.info(`[AlbumDetail] 刷新失败（已保留缓存）: ${errorMessage(e as Error)}`);
      }
    }
    // D-15 浏览历史（加载成功后写入，受 SET-06 开关控制在 Store 内部）
    if (this.album !== null && !this.historyRecorded) {
      this.historyRecorded = true;
      const viewed: Album = this.album;
      historyStore.record(viewed, jmApi.albumThumbUrl(aid)).catch((): void => {});
    }
  }

  private reload(): void {
    this.loadState = 'loading';
    this.errorMsg = '';
    this.loadAll();
  }

  private applyAlbum(album: Album): void {
    const firstApply: boolean = album.id !== this.appliedAid;
    this.appliedAid = album.id;
    this.album = album;
    this.loadState = 'ready';
    this.errorMsg = '';
    // 章节升序索引（JmApi.album 已按 sort 升序）
    this.chapAscIndex.clear();
    for (let i: number = 0; i < album.episodes.length; i++) {
      this.chapAscIndex.set(album.episodes[i].id, i);
    }
    this.rebuildChapters();
    this.syncTags();
    // 附属状态只在同一本子首次应用时拉取（缓存秒开→网络刷新不重复请求）
    if (firstApply) {
      this.refreshFavState();
      this.refreshProgress();
      this.loadPreview();
      this.prefetchCommentBadge();
    }
    this.refreshDlState();
  }

  private async refreshFavState(): Promise<void> {
    if (this.aid === '') {
      return;
    }
    try {
      this.isFav = await favStore.contains(this.aid);
      this.favTags = await favStore.getTags();
      this.syncTags();
    } catch (e) {
      console.info(`[AlbumDetail] 收藏状态读取失败: ${errorMessage(e as Error)}`);
    }
  }

  private async refreshProgress(): Promise<void> {
    if (this.aid === '') {
      return;
    }
    try {
      const p: ReadingProgress | null = await readProgressStore.get(this.aid);
      this.progress = p;
      this.chaptersDs.reload(); // 已读置灰 / 上次读到胶囊依赖该状态
    } catch (e) {
      console.info(`[AlbumDetail] 阅读进度读取失败: ${errorMessage(e as Error)}`);
    }
  }

  private syncTags(): void {
    const a: Album | null = this.album;
    if (a === null) {
      this.displayedTags = [];
      return;
    }
    this.displayedTags = a.tags.slice(0, 14); // 原实现最多展示 14 个标签
  }

  // ───────────────────────── 预览（D-11/D-12） ─────────────────────────

  private async loadPreview(): Promise<void> {
    const a: Album | null = this.album;
    if (a === null || a.episodes.length === 0) {
      return;
    }
    const aid: string = this.aid;
    const first: Chapter = a.episodes[0];
    this.previewLoading = true;
    this.previewError = '';
    try {
      let pages: Array<string> | null = await pagesCacheStore.get(first.id);
      if (aid !== this.aid) {
        return;
      }
      if (pages === null || pages.length === 0) {
        pages = await jmApi.chapterImages(first.id);
        if (aid !== this.aid) {
          return;
        }
        if (pages.length > 0) {
          pagesCacheStore.put(first.id, pages).catch((): void => {});
        }
      }
      let sid: number = 220980;
      try {
        sid = await jmApi.scrambleId(first.id);
      } catch (e) {
        console.info(`[AlbumDetail] scrambleId 获取失败，回退默认: ${errorMessage(e as Error)}`);
      }
      if (aid !== this.aid) {
        return;
      }
      this.previewSid = sid;
      this.previewPhotoId = first.id;
      this.previewPages = pages;
      const items: Array<PreviewPageItem> = [];
      for (let i: number = 0; i < pages.length; i++) {
        const it: PreviewPageItem = new PreviewPageItem();
        it.filename = pages[i];
        it.index = i;
        items.push(it);
      }
      this.previewDs.setItems(items);
    } catch (e) {
      if (aid === this.aid) {
        this.previewError = errorMessage(e as Error);
      }
    } finally {
      if (aid === this.aid) {
        this.previewLoading = false;
      }
    }
  }

  // ───────────────────────── 评论（CM-01~CM-06） ─────────────────────────

  private prefetchCommentBadge(): void {
    const aid: string = this.aid;
    jmApi.comments(aid, 1).then((r: CommentsResult): void => {
      this.commentTotalBadge = r.total;
      if (!this.commentsFetched && !this.commentsLoading) {
        this.comments = r.list;
        this.commentsTotal = r.total;
        this.commentsPage = 1;
        this.commentsFetched = true;
      }
    }).catch((e: Error): void => {
      console.info(`[AlbumDetail] 评论预取失败: ${errorMessage(e)}`);
    });
  }

  private ensureComments(): void {
    if (this.commentsFetched || this.commentsLoading) {
      return;
    }
    this.loadComments(1);
  }

  private async loadComments(page: number): Promise<void> {
    if (this.aid === '') {
      return;
    }
    this.commentsLoading = true;
    this.commentsError = '';
    try {
      const r: CommentsResult = await jmApi.comments(this.aid, page);
      this.comments = r.list;
      this.commentsTotal = r.total;
      this.commentsPage = page;
      this.commentsFetched = true;
      this.commentTotalBadge = r.total;
    } catch (e) {
      this.commentsError = errorMessage(e as Error);
    } finally {
      this.commentsLoading = false;
    }
  }

  private commentsPageCount(): number {
    if (this.commentsTotal <= 0) {
      return 1;
    }
    return Math.ceil(this.commentsTotal / 10);
  }

  /** 热门/最新分段（接口无排序参数：热门=本地按点赞降序，最新=接口时序） */
  private displayedComments(): Array<CommentItem> {
    if (this.commentsSort !== 'hot') {
      return this.comments;
    }
    return this.comments.slice().sort((a: CommentItem, b: CommentItem): number => {
      const la: number = Number(a.likes);
      const lb: number = Number(b.likes);
      const na: number = Number.isNaN(la) ? 0 : la;
      const nb: number = Number.isNaN(lb) ? 0 : lb;
      return nb - na;
    });
  }

  private revealComment(id: string): void {
    if (this.revealedIds.indexOf(id) >= 0) {
      return;
    }
    this.revealedIds = this.revealedIds.concat([id]);
  }

  // ───────────────────────── 下载（D-16/D-17/D-18） ─────────────────────────

  private onDlTask(task: DownloadTask): void {
    if (task.albumId === this.aid) {
      this.dlTask = task;
    }
  }

  private refreshDlState(): void {
    const tasks: Array<DownloadTask> = downloadManager.tasks;
    for (const t of tasks) {
      if (t.albumId === this.aid) {
        this.dlTask = t;
        return;
      }
    }
    this.dlTask = null;
  }

  private dlBusy(): boolean {
    const t: DownloadTask | null = this.dlTask;
    return t !== null && (t.state === 'queued' || t.state === 'running');
  }

  private dlStatusText(): string {
    const t: DownloadTask | null = this.dlTask;
    if (t === null) {
      return '';
    }
    if (t.state === 'queued') {
      return '排队中…（下载队列会逐个处理）';
    }
    if (t.state === 'running') {
      if (t.exporting) {
        return `导出中 ${t.exportDone}/${t.exportTotal}`;
      }
      return `下载中 ${t.done}/${t.total}（失败 ${t.failedPages} 页）`;
    }
    if (t.state === 'done') {
      return `已保存：${t.savedTo}`;
    }
    if (t.state === 'failed') {
      return `下载失败：${t.error}`;
    }
    if (t.state === 'paused') {
      return '已暂停';
    }
    return '已取消';
  }

  private async startDownloadFlow(): Promise<void> {
    if (this.album === null) {
      return;
    }
    if (this.dlBusy()) {
      this.toast('已在下载队列中');
      return;
    }
    try {
      const p: Prefs = await Prefs.getInstance();
      if (await p.downloadRemember()) {
        await this.doEnqueue(false);
      } else {
        this.downloadDlg.open();
      }
    } catch (e) {
      await this.doEnqueue(false);
    }
  }

  private async doEnqueue(remember: boolean): Promise<void> {
    const a: Album | null = this.album;
    if (a === null) {
      return;
    }
    if (remember) {
      try {
        const p: Prefs = await Prefs.getInstance();
        await p.setDownloadRemember(true);
      } catch (e) {
        console.info(`[AlbumDetail] 记忆下载弹窗失败: ${errorMessage(e as Error)}`);
      }
    }
    try {
      await downloadManager.enqueue(a);
      this.refreshDlState();
      let n: number = 0;
      for (const t of downloadManager.tasks) {
        if (t.state === 'queued' || t.state === 'running') {
          n++;
        }
      }
      this.toast(`已加入下载队列（当前 ${n} 个）`);
    } catch (e) {
      this.toast(`加入下载队列失败：${errorMessage(e as Error)}`);
    }
  }

  // ───────────────────────── 收藏 / 标签 ─────────────────────────

  private async toggleFav(): Promise<void> {
    const a: Album | null = this.album;
    if (a === null) {
      return;
    }
    try {
      const added: boolean = await favStore.toggle(a, jmApi.albumCoverUrl(a.id));
      this.isFav = added;
      this.popHeart();
      this.toast(added ? '已加入收藏' : '已取消收藏');
    } catch (e) {
      this.toast('收藏操作失败，请重试');
    }
  }

  /** 收藏爱心微动效（uiux：带爱心微动效） */
  private popHeart(): void {
    this.getUIContext().animateTo({ duration: 130, curve: Curve.EaseOut }, (): void => {
      this.favScale = 1.35;
    });
    setTimeout((): void => {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, (): void => {
        this.favScale = 1.0;
      });
    }, 150);
  }

  private async toggleFavTag(tag: string): Promise<void> {
    try {
      const tags: Array<string> = await favStore.getTags();
      if (tags.indexOf(tag) >= 0) {
        await favStore.removeTag(tag);
        this.toast('已取消收藏标签');
      } else {
        await favStore.addTag(tag);
        this.toast(`已收藏标签：${tag}`);
      }
      this.favTags = await favStore.getTags();
    } catch (e) {
      this.toast('标签收藏操作失败');
    }
  }

  // ───────────────────────── 章节列表 ─────────────────────────

  private rebuildChapters(): void {
    const a: Album | null = this.album;
    if (a === null) {
      this.chaptersDs.setItems([]);
      return;
    }
    let displayed: Array<Chapter> = a.episodes.slice();
    if (this.chaptersDescending) {
      displayed = displayed.reverse();
    }
    this.chaptersDs.setItems(displayed);
  }

  private toggleChapterOrder(): void {
    this.chaptersDescending = !this.chaptersDescending;
    this.rebuildChapters();
  }

  private ascIndexOf(id: string): number {
    const v: number | undefined = this.chapAscIndex.get(id);
    return v === undefined ? 0 : v;
  }

  private chapterCount(): number {
    const a: Album | null = this.album;
    return a === null ? 0 : a.episodes.length;
  }

  private chapterDisplayName(ch: Chapter): string {
    if (ch.title !== '') {
      return ch.title;
    }
    return `第 ${this.ascIndexOf(ch.id) + 1} 話`;
  }

  private isChapterRead(id: string): boolean {
    const p: ReadingProgress | null = this.progress;
    return p !== null && this.ascIndexOf(id) < p.chapterIndex;
  }

  private isLastReadChapter(id: string): boolean {
    const p: ReadingProgress | null = this.progress;
    return p !== null && this.ascIndexOf(id) === p.chapterIndex;
  }

  private lastReadPageLabel(): string {
    const p: ReadingProgress | null = this.progress;
    return `上次读到 P.${(p === null ? 0 : p.page) + 1}`;
  }

  // ───────────────────────── 跳转 ─────────────────────────

  private pushSearch(query: string): void {
    const param: SearchRouteParam = new SearchRouteParam();
    param.query = query;
    this.pageStack.pushPathByName(ROUTE_SEARCH, param);
  }

  private toNumericId(id: string): number {
    const n: number = Number(id);
    return Number.isNaN(n) ? -1 : Math.floor(n);
  }

  private pushReader(chapterIndex: number, page: number): void {
    const a: Album | null = this.album;
    if (a === null || chapterIndex < 0 || chapterIndex >= a.episodes.length) {
      return;
    }
    const ch: Chapter = a.episodes[chapterIndex];
    const param: ReaderRouteParam = new ReaderRouteParam();
    param.aid = a.id;
    param.chapterId = this.toNumericId(ch.id);
    param.chapterIndex = chapterIndex;
    param.page = page;
    this.pageStack.pushPathByName(ROUTE_READER, param);
  }

  /** 主 CTA：无进度从第 1 话开始；有进度续读（B-03 精确进度驱动） */
  private onMainCta(): void {
    const p: ReadingProgress | null = this.progress;
    if (p !== null) {
      this.pushReader(p.chapterIndex, p.page);
    } else {
      this.pushReader(0, 0);
    }
  }

  // ───────────────────────── 工具 ─────────────────────────

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800, bottom: 180 });
  }

  private copyText(text: string, label: string): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.toast(`已复制${label}`);
    }).catch((): void => {
      this.toast('复制失败，请重试');
    });
  }

  private officialLink(): string {
    return `${OFFICIAL_LINK_BASE}${this.aid}`;
  }

  private albumTitle(): string {
    const a: Album | null = this.album;
    return a === null ? '' : a.name;
  }

  private headerCoverUrl(): string {
    return this.aid === '' ? '' : jmApi.albumCoverUrl(this.aid);
  }

  private authorLine(a: Album): string {
    return a.author.join(', ');
  }

  private onAuthorClick(a: Album): void {
    if (a.author.length > 0 && a.author[0] !== '') {
      this.pushSearch(a.author[0]);
    }
  }

  private hitAny(hay: string, keys: Array<string>): boolean {
    for (const k of keys) {
      if (hay.indexOf(k) >= 0) {
        return true;
      }
    }
    return false;
  }

  /** 语言徽章 + 全彩判定（D-04：真实 tags 命中优先，标题启发式回退，TagStore.remember 等价简化） */
  private langBadge(a: Album): string {
    const hay: string = `${a.name} ${a.tags.join(' ')}`.toLowerCase();
    let badge: string = '';
    if (this.hitAny(hay, ['中文', '漢化', '汉化', '中字', '中國翻譯', '中文翻译', 'chinese'])) {
      badge = '中字';
    } else if (this.hitAny(hay, ['日本語', '日語', '日文', 'japanese', '生肉', 'raw'])) {
      badge = '日漫';
    } else if (this.hitAny(hay, ['한국', '한글', 'korean', '韩文', '韓文'])) {
      badge = '韩漫';
    } else if (this.hitAny(hay, ['english', '英文', '英譯', '英译'])) {
      badge = '英语';
    }
    if (this.hitAny(hay, ['全彩', '全彩漢化', '全彩汉化'])) {
      badge = badge === '' ? '全彩' : `${badge}·全彩`;
    }
    return badge;
  }

  private ctaLabel(): string {
    const p: ReadingProgress | null = this.progress;
    if (p !== null) {
      return `▶ 续读 · 第${p.chapterIndex + 1}话 P.${p.page + 1}`;
    }
    return '▶ 开始阅读 · 第 1 话';
  }

  private updateToolbarAlpha(): void {
    const y: number = this.scroller.currentOffset().yOffset;
    const alpha: number = Math.min(1, Math.max(0, (y - TOOLBAR_FADE_START) / TOOLBAR_FADE_RANGE));
    if (alpha !== this.toolbarAlpha) {
      this.toolbarAlpha = alpha;
      // 评审 Step3：滚动联动状态栏文字色——头部深色图域白字，上滑浅色栏后切深字
      const wantLight: boolean = alpha < 0.55;
      if (wantLight !== this.barLightText) {
        this.barLightText = wantLight;
        this.applyStatusBarTextLight(wantLight);
      }
    }
  }

  /** 状态栏文字：true=白字（深色头图）/false=深字（浅色吸顶栏或浅色主题） */
  private applyStatusBarTextLight(light: boolean): void {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    if (ctx === undefined) {
      return;
    }
    window.getLastWindow(ctx).then((win: window.Window): void => {
      win.setWindowSystemBarProperties({
        statusBarContentColor: light ? '#FFFFFF' : '#1E293B'
      }).catch((): void => {
      });
    }).catch((): void => {
    });
  }

  /** 离开详情页：状态栏文字恢复为当前应用主题应有形态 */
  private restoreStatusBarToTheme(): void {
    const isDark: boolean = AppStorage.get<boolean>(IS_DARK_MODE_KEY) ?? false;
    this.barLightText = !isDark ? false : true;
    this.applyStatusBarTextLight(isDark);
  }

  private toolbarBgColor(): string {
    return mixRgba(T_BG_A, T_BG_B, this.toolbarAlpha);
  }

  private toolbarIconColor(): string {
    return mixRgba(T_ICON_A, T_ICON_B, this.toolbarAlpha);
  }

  private toolbarChipColor(): string {
    return mixRgba(T_CHIP_A, T_CHIP_B, this.toolbarAlpha);
  }

  private truncate(s: string, max: number): string {
    if (s.length <= max) {
      return s;
    }
    return s.substring(0, max);
  }

  private startPulse(): void {
    this.getUIContext().animateTo({ duration: 800, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate }, (): void => {
      this.skelAlpha = 0.45;
    });
  }

  // ───────────────────────── Builders ─────────────────────────

  /** D-01 折叠视差头部背景：封面 blur(60) + 暗渐变遮罩（固定层，内容滚动形成折叠视差） */
  @Builder
  HeaderBackdrop() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(15,17,23,0.55)')
      Column() {
        Image(this.headerCoverUrl())
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(60)
          .opacity(0.5)
          .backgroundColor(DIVIDER)
      }
      .width('100%')
      .height('100%')

      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            ['rgba(15,17,23,0.45)', 0.0],
            ['rgba(15,17,23,0.38)', 0.45],
            ['rgba(247,248,250,1.0)', 1.0]
          ]
        })
    }
    .width('100%')
    .height(HEADER_BG_H + this.topInset)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }

  /** D-01 顶部栏：初始透明（仅返回/复制链接），上滑渐显毛玻璃 + 单行书名 */
  @Builder
  ToolbarLayer() {
    Column() {
      Row({ space: 6 }) {
        Text('←')
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.toolbarIconColor())
          .width(34)
          .height(34)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.toolbarChipColor())
          .borderRadius(17)
          .onClick(() => {
            this.pageStack.pop();
          })
        Text(this.albumTitle())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.toolbarIconColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .opacity(this.toolbarAlpha)
        Text('复制链接')
          .fontSize(11)
          .fontColor(this.toolbarIconColor())
          .height(30)
          .padding({ left: 10, right: 10 })
          .textAlign(TextAlign.Center)
          .backgroundColor(this.toolbarChipColor())
          .borderRadius(15)
          .onClick(() => {
            this.copyText(this.officialLink(), '链接');
          })
      }
      .width('100%')
      .height(50)
    }
    .width('100%')
    .padding({ top: this.topInset })
    .backgroundColor(this.toolbarBgColor())
    .backgroundBlurStyle(BlurStyle.Thin)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }

  /** D-02/D-04/D-05 元数据区：封面（点击放大）/两行书名/作者可点/编号胶囊/统计/标签流 */
  @Builder
  private MetaHeader(a: Album) {
    Column({ space: 12 }) {
      Row({ space: 14 }) {
        Stack({ alignContent: Alignment.TopEnd }) {
          Image(jmApi.albumCoverUrl(a.id))
            .width(118)
            .aspectRatio(COVER_ASPECT_RATIO)
            .objectFit(ImageFit.Cover)
            .borderRadius(COVER_R)
            .backgroundColor(DIVIDER)
            .border({ width: 0.5, color: 'rgba(255,255,255,0.2)' })
            .onClick(() => {
              this.coverViewerOpen = true;
            })
            .bindContentCover(this.coverViewerOpen, this.CoverViewerBuilder(), {
              modalTransition: ModalTransition.DEFAULT,
              onDisappear: (): void => {
                this.coverViewerOpen = false;
              }
            })
          if (this.langBadge(a) !== '') {
            Text(this.langBadge(a))
              .fontSize(10)
              .fontColor(Color.White)
              .maxLines(1)
              .constraintSize({ maxWidth: '80%' })
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .backgroundColor('rgba(20,20,20,0.35)')
              .backgroundBlurStyle(BlurStyle.Thin)
              .borderRadius(9)
              .margin(6)
          }
        }
        .width(118)

        Column({ space: 8 }) {
          Text(a.name)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .gesture(LongPressGesture().onAction(() => {
              this.copyText(a.name, '标题');
            }))
          if (this.authorLine(a) !== '') {
            Row({ space: 2 }) {
              Text(`作者：${this.authorLine(a)}`)
                .fontSize(13)
                .fontColor(Color.White)
                .opacity(0.88)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
                .onClick(() => {
                  this.onAuthorClick(a);
                })
                .gesture(LongPressGesture().onAction(() => {
                  this.copyText(this.authorLine(a), '作者');
                }))
              Text('›')
                .fontSize(13)
                .fontColor(Color.White)
                .opacity(0.88)
            }
            .width('100%')
          }
          Row({ space: 10 }) {
            Text(`JM${a.id}`)
              .fontSize(12)
              .fontColor(Color.White)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor('rgba(255,255,255,0.22)')
              .borderRadius(CHIP_R)
              .onClick(() => {
                this.copyText(a.id, `编号 JM${a.id}`);
              })
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.heart'))
                .fontSize(13)
                .fontColor([PRIMARY])
              Text(formatCount(a.likes))
                .fontSize(12)
                .fontColor(Color.White)
                .opacity(0.9)
            }
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.eye'))
                .fontSize(13)
                .fontColor([Color.White])
              Text(formatCount(a.views))
                .fontSize(12)
                .fontColor(Color.White)
                .opacity(0.9)
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (this.displayedTags.length > 0) {
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          ForEach(this.displayedTags, (tag: string) => {
            this.MetaTagChip(tag)
          }, (tag: string) => `tag_${tag}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topInset + 62 })
  }

  /** D-05/D-06 标签胶囊：点击搜索、长按收藏/取消（已收藏 PRIMARY 高亮） */
  @Builder
  private MetaTagChip(tag: string) {
    Text(tag)
      .fontSize(11)
      .fontColor(Color.White)
      .maxLines(1)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(this.favTags.indexOf(tag) >= 0 ? PRIMARY : 'rgba(255,255,255,0.18)')
      .borderRadius(CHIP_R)
      .margin({ right: 8, bottom: 6 })
      .onClick(() => {
        this.pushSearch(tag);
      })
      .gesture(LongPressGesture().onAction(() => {
        this.toggleFavTag(tag);
      }))
  }

  /** D-07/D-08/D-18 主次 CTA：通栏主按钮（ACCENT 蓝）+ 收藏/下载/评论三个毛玻璃圆钮 + 下载状态行 */
  @Builder
  private CtaBlock(a: Album) {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Button(this.ctaLabel())
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(ACCENT)
          .borderRadius(CARD_R)
          .height(48)
          .layoutWeight(1)
          .onClick(() => {
            this.onMainCta();
          })

        Column() {
          Text('♥')
            .fontSize(20)
            .fontColor(this.isFav ? PRIMARY : TEXT_SUB)
            .scale({ x: this.favScale, y: this.favScale })
        }
        .width(48)
        .height(48)
        .borderRadius(24)
        .backgroundColor(CHIP_BG)
        .backgroundBlurStyle(BlurStyle.Thin)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.toggleFav();
        })

        Column() {
          Text('⬇')
            .fontSize(17)
            .fontColor(TEXT_MAIN)
        }
        .width(48)
        .height(48)
        .borderRadius(24)
        .backgroundColor(CHIP_BG)
        .backgroundBlurStyle(BlurStyle.Thin)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .opacity(this.dlBusy() ? 0.55 : 1)
        .onClick(() => {
          this.startDownloadFlow();
        })

        Stack({ alignContent: Alignment.TopEnd }) {
          Column() {
            Text('💬')
              .fontSize(17)
              .fontColor(TEXT_MAIN)
          }
          .width(48)
          .height(48)
          .borderRadius(24)
          .backgroundColor(CHIP_BG)
          .backgroundBlurStyle(BlurStyle.Thin)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          if (this.commentTotalBadge > 0) {
            Text(formatCount(`${this.commentTotalBadge}`))
              .fontSize(9)
              .fontColor(Color.White)
              .backgroundColor(PRIMARY)
              .borderRadius(8)
              .constraintSize({ minWidth: 16 })
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .offset({ x: 3, y: -3 })
          }
        }
        .width(48)
        .height(48)
        .onClick(() => {
          this.commentsSheetOpen = true;
          this.ensureComments();
        })
      }
      .width('100%')

      if (this.dlTask !== null && this.dlStatusText() !== '') {
        Text(this.dlStatusText())
          .fontSize(11)
          .fontColor(TEXT_SUB)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .margin({ top: 16 })
    .bindSheet(this.commentsSheetOpen, this.CommentSheetContent(), {
      height: '75%',
      showClose: true,
      onDisappear: (): void => {
        this.commentsSheetOpen = false;
      }
    })
  }

  /** D-09/D-10 章节列表头：章节数 + 正倒序切换 */
  @Builder
  ChapterHeaderBlock() {
    Row() {
      Text(`章节 (${this.chapterCount()})`)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .layoutWeight(1)
      Row({ space: 4 }) {
        Text('⇅')
          .fontSize(12)
          .fontColor(TEXT_SUB)
        Text(this.chaptersDescending ? '倒序' : '正序')
          .fontSize(12)
          .fontColor(TEXT_SUB)
      }
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(CHIP_BG)
      .borderRadius(CHIP_R)
      .onClick(() => {
        this.toggleChapterOrder();
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 6 })
  }

  /** D-09 章节行：序号 + 标题（已读置灰）+ 上次读到胶囊；点击进阅读器、长按复制章节名 */
  @Builder
  private ChapterRow(ch: Chapter) {
    Row({ space: 10 }) {
      Text(`${this.ascIndexOf(ch.id) + 1}`)
        .fontSize(12)
        .fontColor(TEXT_SUB)
        .width(24)
        .textAlign(TextAlign.Center)
      Text(this.chapterDisplayName(ch))
        .fontSize(14)
        .fontColor(this.isChapterRead(ch.id) ? TEXT_SUB : TEXT_MAIN)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.isLastReadChapter(ch.id)) {
        Text(this.lastReadPageLabel())
          .fontSize(10)
          .fontColor(ACCENT)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor('rgba(59,91,219,0.12)')
          .borderRadius(CHIP_R)
      }
    }
    .width('100%')
    .height(50)
    .padding({ left: 16, right: 12 })
    .border({ width: { bottom: 0.5 }, color: DIVIDER })
    .onClick(() => {
      this.pushReader(this.ascIndexOf(ch.id), 0);
    })
    .gesture(LongPressGesture().onAction(() => {
      this.copyText(this.chapterDisplayName(ch), '章节名');
    }))
  }

  /** D-11/D-12/D-13 预览区：单行横向胶片条（前 8 页）+ 查看全部（bindSheet 半模态全量网格） */
  @Builder
  PreviewSection() {
    if (this.previewLoading) {
      Column({ space: 10 }) {
        SectionTitle({ title: '内容预览 · 第 1 話' })
        Row({ space: 8 }) {
          ForEach([0, 1, 2, 3, 4, 5], (i: number) => {
            Column()
              .width(96)
              .aspectRatio(0.7)
              .borderRadius(8)
              .backgroundColor(DIVIDER)
              .opacity(this.skelAlpha)
          }, (i: number) => `pv_skel_${i}`)
        }
        .width('100%')
        .onAppear(() => {
          this.startPulse();
        })
      }
      .width('100%')
      .margin({ top: 14 })
    } else if (this.previewError !== '') {
      Column({ space: 10 }) {
        SectionTitle({ title: '内容预览 · 第 1 話' })
        Row({ space: 8 }) {
          Text(this.previewError)
            .fontSize(12)
            .fontColor(TEXT_SUB)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Button('重试')
            .fontSize(12)
            .fontColor(PRIMARY)
            .backgroundColor(CHIP_BG)
            .borderRadius(CHIP_R)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .onClick(() => {
              this.loadPreview();
            })
        }
        .width('100%')
      }
      .width('100%')
      .margin({ top: 14 })
    } else if (this.previewPages.length > 0) {
      Column({ space: 10 }) {
        SectionTitle({
          title: `内容预览 · 第 1 話`,
          actionText: `查看全部 ${this.previewPages.length} 页 ›`,
          onAction: (): void => {
            this.previewSheetOpen = true;
          }
        })
        List({ space: 8 }) {
          ForEach(this.previewPages.slice(0, PREVIEW_STRIP_COUNT), (fn: string, idx: number) => {
            ListItem() {
              PageThumb({
                photoId: this.previewPhotoId,
                filename: fn,
                scrambleId: this.previewSid,
                targetWidth: THUMB_WIDTH,
                label: `${idx + 1}`,
                onTap: (): void => {
                  this.pushReader(0, idx);
                }
              })
            }
          }, (fn: string, idx: number) => `film_${idx}_${fn}`)
        }
        .listDirection(Axis.Horizontal)
        .width('100%')
        .height(150)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .margin({ top: 14 })
      .bindSheet(this.previewSheetOpen, this.PreviewSheetContent(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        showClose: true,
        onDisappear: (): void => {
          this.previewSheetOpen = false;
        }
      })
    }
  }

  /** 全量预览半模态：LazyForEach + Grid 缩略网格，点任意页进阅读器 */
  @Builder
  PreviewSheetContent() {
    Column({ space: 12 }) {
      Text(`全部预览 · 共 ${this.previewPages.length} 页`)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .width('100%')
      Grid() {
        LazyForEach(this.previewDs, (item: PreviewPageItem) => {
          GridItem() {
            PageThumb({
              photoId: this.previewPhotoId,
              filename: item.filename,
              scrambleId: this.previewSid,
              targetWidth: THUMB_WIDTH,
              label: `${item.index + 1}`,
              onTap: (): void => {
                this.pushReader(0, item.index);
              }
            })
          }
        }, (item: PreviewPageItem) => `pv_${item.index}_${item.filename}`)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(8)
      .rowsGap(8)
      .cachedCount(3)
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 18, bottom: 16 })
  }

  /** CM-01 评论半模态（75% 高）：热门/最新分段 + 分页 + 剧透遮罩 + 只读发布入口 */
  @Builder
  CommentSheetContent() {
    Column({ space: 10 }) {
      Column({ space: 8 }) {
        Text(`评论 · ${this.truncate(this.albumTitle(), 16)}`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 8 }) {
          Text('热门')
            .fontSize(12)
            .fontColor(this.commentsSort === 'hot' ? Color.White : TEXT_SUB)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .backgroundColor(this.commentsSort === 'hot' ? PRIMARY : CHIP_BG)
            .borderRadius(CHIP_R)
            .onClick(() => {
              this.commentsSort = 'hot';
            })
          Text('最新')
            .fontSize(12)
            .fontColor(this.commentsSort === 'new' ? Color.White : TEXT_SUB)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .backgroundColor(this.commentsSort === 'new' ? PRIMARY : CHIP_BG)
            .borderRadius(CHIP_R)
            .onClick(() => {
              this.commentsSort = 'new';
            })
          if (this.commentsTotal > 0) {
            Text(`共 ${formatCount(`${this.commentsTotal}`)} 条`)
              .fontSize(11)
              .fontColor(TEXT_SUB)
              .margin({ left: 4 })
          }
        }
        .width('100%')
      }
      .width('100%')

      if (this.commentsLoading && this.comments.length === 0) {
        Column({ space: 10 }) {
          ForEach([0, 1, 2], (i: number) => {
            Column({ space: 8 }) {
              Column()
                .height(12)
                .width('42%')
                .borderRadius(4)
                .backgroundColor(CHIP_BG)
                .opacity(this.skelAlpha)
              Column()
                .height(28)
                .width('100%')
                .borderRadius(4)
                .backgroundColor(CHIP_BG)
                .opacity(this.skelAlpha)
            }
            .width('100%')
            .onAppear(() => {
              this.startPulse();
            })
          }, (i: number) => `cm_skel_${i}`)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.commentsError !== '' && this.comments.length === 0) {
        Column() {
          EmptyView({
            message: `评论加载失败：${this.commentsError}`,
            onRetry: (): void => {
              this.loadComments(1);
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.comments.length === 0) {
        Column() {
          EmptyView({ message: '还没有评论', showRetry: false })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 10 }) {
          ForEach(this.displayedComments(), (c: CommentItem) => {
            ListItem() {
              this.CommentCardView(c)
            }
          }, (c: CommentItem) => `cmt_${c.id}`)
          ListItem() {
            this.CommentPager()
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }

      Row({ space: 8 }) {
        TextInput({ text: this.commentDraft, placeholder: '说点什么…（评论仅支持浏览）' })
          .fontSize(13)
          .height(38)
          .layoutWeight(1)
          .backgroundColor(CHIP_BG)
          .borderRadius(CHIP_R)
          .onChange((value: string) => {
            this.commentDraft = value;
          })
        Button('发布')
          .fontSize(13)
          .height(38)
          .fontColor(Color.White)
          .backgroundColor(PRIMARY)
          .borderRadius(CHIP_R)
          .padding({ left: 16, right: 16 })
          .onClick(() => {
            this.toast('评论接口为只读，暂不支持发布');
          })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 18, bottom: 12 })
  }

  /** CM-02/CM-03 评论卡片：昵称/回复标记/时间/♥点赞数 + 剧透遮罩 */
  @Builder
  private CommentCardView(c: CommentItem) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(c.nickname === '' ? '匿名' : c.nickname)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_MAIN)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (c.parentId !== '' && c.parentId !== '0') {
          Text('回复')
            .fontSize(10)
            .fontColor(PRIMARY)
        }
        Text(formatCommentTime(c.time))
          .fontSize(10)
          .fontColor(TEXT_SUB)
        Text(`♥ ${c.likes === '' ? '0' : c.likes}`)
          .fontSize(10)
          .fontColor(TEXT_SUB)
      }
      .width('100%')

      if (c.spoiler && this.revealedIds.indexOf(c.id) < 0) {
        Text('包含剧透，点按查看')
          .fontSize(12)
          .fontColor(TEXT_SUB)
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ top: 14, bottom: 14 })
          .backgroundColor(CHIP_BG)
          .borderRadius(8)
          .onClick(() => {
            this.revealComment(c.id);
          })
      } else {
        Text(c.content === '' ? '（空）' : c.content)
          .fontSize(13)
          .fontColor(TEXT_MAIN)
          .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(BG)
    .borderRadius(CARD_R)
  }

  /** CM-04 评论分页条（每页约 10 条） */
  @Builder
  CommentPager() {
    Row({ space: 12 }) {
      Button('上一页')
        .fontSize(12)
        .fontColor(this.commentsPage > 1 ? PRIMARY : TEXT_SUB)
        .backgroundColor(CHIP_BG)
        .borderRadius(CHIP_R)
        .height(30)
        .padding({ left: 14, right: 14 })
        .enabled(this.commentsPage > 1)
        .onClick(() => {
          if (this.commentsPage > 1) {
            this.loadComments(this.commentsPage - 1);
          }
        })
      Row({ space: 6 }) {
        Text(`${this.commentsPage} / ${this.commentsPageCount()}`)
          .fontSize(12)
          .fontColor(TEXT_SUB)
        if (this.commentsLoading) {
          LoadingProgress()
            .width(14)
            .height(14)
            .color(PRIMARY)
        }
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      Button('下一页')
        .fontSize(12)
        .fontColor(this.commentsPage < this.commentsPageCount() ? PRIMARY : TEXT_SUB)
        .backgroundColor(CHIP_BG)
        .borderRadius(CHIP_R)
        .height(30)
        .padding({ left: 14, right: 14 })
        .enabled(this.commentsPage < this.commentsPageCount())
        .onClick(() => {
          if (this.commentsPage < this.commentsPageCount()) {
            this.loadComments(this.commentsPage + 1);
          }
        })
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  /** 封面全屏查看（bindContentCover）；底部提供「保存高清封面」经系统选择器存到公共目录（评审 Step3） */
  @Builder
  CoverViewerBuilder() {
    Column({ space: 18 }) {
      Image(this.headerCoverUrl())
        .objectFit(ImageFit.Contain)
        .width('94%')
        .layoutWeight(1)
        .borderRadius(COVER_R)
      Text('保存高清封面')
        .fontSize(14)
        .fontColor(Color.White)
        .padding({ left: 26, right: 26, top: 10, bottom: 10 })
        .borderRadius(18)
        .backgroundColor('rgba(255,255,255,0.16)')
        .backgroundBlurStyle(BlurStyle.Thin)
        .margin({ bottom: 34 })
        .onClick(() => {
          this.saveCoverToPublic();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(MASK_DARK)
    .onClick(() => {
      this.coverViewerOpen = false;
    })
  }

  /** 封面原图字节 → DocumentViewPicker 保存（评审 Step3：D 补齐封面保存） */
  private async saveCoverToPublic(): Promise<void> {
    try {
      const url: string = this.headerCoverUrl();
      if (url === '') {
        throw new Error('封面尚未就绪');
      }
      const bytes: ArrayBuffer = await jmApi.fetchBytes(url);
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      if (ctx === undefined) {
        throw new Error('页面宿主上下文不可用');
      }
      const pickerInst: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      const opt: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      opt.newFileNames = [`jm_cover_${this.aid}.jpg`];
      const uris: Array<string> = await pickerInst.save(opt);
      if (uris.length === 0) {
        return;
      }
      const file: fs.File = fs.openSync(uris[0],
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, bytes);
      fs.closeSync(file);
      this.toast('封面已保存');
    } catch (e) {
      this.toast(`保存失败：${errorMessage(e as Error)}`);
    }
  }

  /** 首载骨架（D-20：加载态） */
  @Builder
  LoadingBody() {
    Column({ space: 16 }) {
      Row({ space: 14 }) {
        Column()
          .width(118)
          .aspectRatio(COVER_ASPECT_RATIO)
          .borderRadius(COVER_R)
          .backgroundColor('rgba(255,255,255,0.16)')
          .opacity(this.skelAlpha)
        Column({ space: 10 }) {
          Column()
            .height(18)
            .width('82%')
            .borderRadius(4)
            .backgroundColor('rgba(255,255,255,0.16)')
            .opacity(this.skelAlpha)
          Column()
            .height(13)
            .width('58%')
            .borderRadius(4)
            .backgroundColor('rgba(255,255,255,0.16)')
            .opacity(this.skelAlpha)
          Column()
            .height(22)
            .width('40%')
            .borderRadius(CHIP_R)
            .backgroundColor('rgba(255,255,255,0.16)')
            .opacity(this.skelAlpha)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Row({ space: 12 }) {
        Column()
          .width(48)
          .height(48)
          .borderRadius(24)
          .backgroundColor('rgba(255,255,255,0.16)')
          .opacity(this.skelAlpha)
        Column()
          .height(48)
          .borderRadius(CARD_R)
          .backgroundColor('rgba(255,255,255,0.16)')
          .opacity(this.skelAlpha)
          .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topInset + 62 })
    .onAppear(() => {
      this.startPulse();
    })
  }

  /** 错误态 + 重试（D-20 / D-14：无缓存失败才报错） */
  @Builder
  ErrorBody() {
    Column() {
      EmptyView({
        message: this.errorMsg === '' ? '加载失败，请检查网络后重试' : `加载失败：${this.errorMsg}`,
        onRetry: (): void => {
          this.reload();
        }
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: this.topInset })
  }

  // ───────────────────────── 页面构建 ─────────────────────────

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        this.HeaderBackdrop()

        if (this.loadState === 'ready' && this.album !== null) {
          List({ scroller: this.scroller }) {
            ListItem() {
              this.MetaHeader(this.album as Album)
            }
            ListItem() {
              this.CtaBlock(this.album as Album)
            }
            if (this.chapterCount() > 0) {
              ListItem() {
                this.ChapterHeaderBlock()
              }
            }
            LazyForEach(this.chaptersDs, (ch: Chapter) => {
              ListItem() {
                this.ChapterRow(ch)
              }
            }, (ch: Chapter) => `chap_${ch.id}`)
            if (this.previewLoading || this.previewError !== '' || this.previewPages.length > 0) {
              ListItem() {
                this.PreviewSection()
              }
            }
            ListItem() {
              Column().height(40)
            }
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .cachedCount(4)
          .onDidScroll((offset: number, state: ScrollState) => {
            this.updateToolbarAlpha();
          })
        } else if (this.loadState === 'loading') {
          this.LoadingBody()
        } else {
          this.ErrorBody()
        }

        this.ToolbarLayer()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      const raw: Object | undefined = ctx.pathInfo.param as Object | undefined;
      if (raw === undefined || raw === null) {
        return;
      }
      const rec: Record<string, Object> | null = asRecord(raw);
      if (rec === null) {
        return;
      }
      const aid: string = asString(rec['aid'], '');
      if (aid === '' || aid === this.aid) {
        return;
      }
      this.aid = aid;
      this.loadState = 'loading';
      this.errorMsg = '';
      this.loadAll();
    })
    .onShown(() => {
      // 从阅读器返回时静默刷新续读进度/收藏/下载状态
      if (this.aid === '' || this.album === null) {
        return;
      }
      this.refreshFavState();
      this.refreshProgress();
      this.refreshDlState();
    })
    .onWillDisappear(() => {
      // 评审 Step3：离开详情页把状态栏文字交还给当前应用主题
      this.restoreStatusBarToTheme();
    })
  }
}
