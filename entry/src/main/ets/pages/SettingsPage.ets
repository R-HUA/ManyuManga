/**
 * 「我的」Tab：分组设置页
 *
 *
 */

import fs from '@ohos.file.fs';
import pasteboard from '@ohos.pasteboard';
import picker from '@ohos.file.picker';

import userIAM from '@ohos.userIAM.userAuth';
import bundleManager from '@ohos.bundle.bundleManager';
import window from '@ohos.window';
import common from '@ohos.app.ability.common';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';

import {
  PRIMARY,
  ACCENT,
  BG,
  CARD,
  TEXT_MAIN,
  TEXT_SUB,
  DIVIDER,
  TAB_INACTIVE,
  TAB_BAR_HEIGHT,
  CARD_R,
  CHIP_R,
  FONT_TITLE,
  FONT_BODY,
  FONT_CAPTION,
  SPACE_S,
  SPACE_M,
  SPACE_L,
  SPACE_XL
} from '../common/Theme';
import { TagChip, EmptyView } from '../common/Components';
import { ROUTE_DOWNLOADS } from '../common/Route';
import { DomainSpeed, FavItem, HistoryItem, errorMessage, asArray, asRecord, asString, asNumber } from '../models/Models';
import { jmApi, utf8Decode } from '../data/JmApi';
import { CURRENT_BREAKPOINT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';
import { blockTagsStore, favStore, historyStore, searchHistoryStore } from '../data/Stores';
import { downloadManager } from '../data/DownloadManager';
import { Prefs } from '../util/Prefs';

const PROJECT_REPO: string = 'https://github.com/jinmanji/jinmanji-app';
const PROJECT_LICENSE: string = 'GPLv3';
/** userAuth 认证成功结果码（对应 userIAM ResultCode.SUCCESS，数值常量避免枚举可用性差异） */
const AUTH_RESULT_SUCCESS: number = 12500000;
/** 预加载页数档位（原项目固定 5；SET-08 档位化） */
const PRELOAD_TIERS: Array<number> = [1, 3, 5, 8];
/** 骨架占位分组数 */
const SKELETON_GROUPS: Array<number> = [0, 1, 2];
/** 屏蔽标签长度上限（SET-07：SettingsScreen.kt:1089-1140，≤16 字符码点计数） */
const BLOCK_TAG_MAX_CP: number = 16;

/** 主题选项（SET-01 M 级三态：跟随系统/浅色/深色） */
class ThemeOption {
  value: string;
  label: string;

  constructor(value: string = '', label: string = '') {
    this.value = value;
    this.label = label;
  }
}

function buildThemeOptions(): Array<ThemeOption> {
  const list: Array<ThemeOption> = [];
  list.push(new ThemeOption('system', '跟随系统'));
  list.push(new ThemeOption('light', '浅色'));
  list.push(new ThemeOption('dark', '深色'));
  return list;
}

/**
 * 主题生效：ApplicationContext.setColorMode（API 11+ 稳定接口）。
 * dark→COLOR_MODE_DARK / light→COLOR_MODE_LIGHT / system→COLOR_MODE_NOT_SET（跟随系统）。
 * 与 pages/Index.ets 启动时应用同一口径（EntryAbility 为工程架构师所有权，入口页承担）。
 */
function applyThemeModeToApp(context: common.Context, mode: string): void {
  try {
    const appCtx: common.ApplicationContext = context.getApplicationContext();
    const cm: number = mode === 'dark'
      ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : mode === 'light'
        ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    appCtx.setColorMode(cm);
  } catch (e) {
    // 生效失败不影响偏好保存（下次启动由 Index 再应用）
  }
}

// ───────────────────────── 页面局部视图模型（class + 显式类型） ─────────────────────────

/** 镜像行视图状态：域名 + 最近一次测速结果 */
class MirrorRow {
  domain: string = '';
  ms: number = -1;
  ok: boolean = false;
  tested: boolean = false;
}

/** 阅读模式选项 */
class ModeOption {
  value: string;
  label: string;

  constructor(value: string = '', label: string = '') {
    this.value = value;
    this.label = label;
  }
}

/** 缓存统计累计器 */
class CacheStats {
  bytes: number = 0;
  files: number = 0;
}

/** 导出 JSON 结构（对齐 DataTransfer.buildExport 的收藏/历史两段） */
class ExportFavorites {
  items: Array<FavItem> = [];
  tags: Array<string> = [];
}

class ExportHistoryData {
  browse: Array<HistoryItem> = [];
  search: Array<string> = [];
}

class ExportRoot {
  app: string = 'jinmanji-harmony';
  schema: number = 1;
  exportedAt: number = 0;
  favorites: ExportFavorites = new ExportFavorites();
  history: ExportHistoryData = new ExportHistoryData();
}

/**
 * userAuth 认证结果回调（ArkTS 规则：接口实现用具名 class，参照 EntryAbility 的 ErrorObserver 写法）。
 * 成功/失败都按 S 级语义保留开关（仅提示不同）。
 */
class AuthResultHandler implements userIAM.IAuthCallback {
  private owner: SettingsPage;
  private instance: userIAM.UserAuthInstance | null = null;
  private settled: boolean = false;

  constructor(owner: SettingsPage) {
    this.owner = owner;
  }

  setInstance(instance: userIAM.UserAuthInstance): void {
    this.instance = instance;
  }

  onResult(result: userIAM.UserAuthResult): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    if (this.instance !== null) {
      try {
        this.instance.off('result');
      } catch (e) {
        // 取消订阅失败可忽略
      }
    }
    if (result.result === AUTH_RESULT_SUCCESS) {
      this.owner.onAuthResult('指纹验证通过，应用锁已开启');
    } else {
      this.owner.onAuthResult(`指纹验证未通过（码 ${result.result}），已仅保存开关状态`);
    }
  }
}

// ───────────────────────── 通用行组件 ─────────────────────────

/** 开关行：标题 + 副题 + Switch（开关态即时反馈由父页 @State 驱动） */
@Component
struct SwitchRow {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop isOn: boolean = false;
  onToggle: (v: boolean) => void = (v: boolean) => {
  };

  build() {
    Row() {
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(FONT_BODY)
          .fontColor(TEXT_MAIN)
          .maxLines(1)
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(FONT_CAPTION)
            .fontColor(TEXT_SUB)
            .maxLines(2)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(PRIMARY)
        .switchPointColor(Color.White)
        .onChange((v: boolean) => {
          this.onToggle(v);
        })
    }
    .width('100%')
    .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_M, bottom: SPACE_M })
    .alignItems(VerticalAlign.Center)
  }
}

/** 可点击行：标题 + 副题 + 右侧文案/箭头 */
@Component
struct ActionRow {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop trailing: string = '';
  onTap: () => void = () => {
  };

  build() {
    Row({ space: SPACE_M }) {
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(FONT_BODY)
          .fontColor(TEXT_MAIN)
          .maxLines(1)
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(FONT_CAPTION)
            .fontColor(TEXT_SUB)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.trailing !== '') {
        Text(this.trailing)
          .fontSize(FONT_CAPTION)
          .fontColor(TEXT_SUB)
          .maxLines(1)
      }
      Text('›')
        .fontSize(FONT_BODY)
        .fontColor(TAB_INACTIVE)
    }
    .width('100%')
    .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_M, bottom: SPACE_M })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onTap();
    })
  }
}

// ───────────────────────── 设置页 ─────────────────────────

@Component
export struct SettingsPage {
  @Prop sourceOnly: boolean = false;
  /** 全局路由栈（下载管理入口 P-02 用） */
  @Consume('navPathStack') pageStack: NavPathStack;

  // 加载/错误态（四态：骨架 / 错误重试；本页数据多为本地，无分页）
  @State loading: boolean = true;
  @State loadError: string = '';
  @State skelAlpha: number = 1.0;
  /** 顶部安全区避让（沉浸式全屏布局下需要自避让状态栏） */
  @State topInset: number = 38;

  // 图源与镜像
  @State mirrors: Array<MirrorRow> = [];
  @State currentDomain: string = '';
  @State testingAll: boolean = false;

  // 外观（SET-01 三态主题：system/light/dark，保存后立即生效 + Index 启动时应用）
  @State themeModeValue: string = 'system';

  // 阅读器默认
  @State readerModeValue: string = 'vertical';
  @State preloadPages: number = 3;

  // 通用（SET-06 历史开关 / P-02 下载入口 / SET-07 屏蔽标签管理）
  @State historyEnabled: boolean = true;
  @State downloadCount: number = 0;
  @State blockTags: Array<string> = [];
  @State blockSheet: boolean = false;
  @State blockInput: string = '';
  @State blockError: string = '';

  // 存储
  @State autoCache: boolean = true;
  @State cacheBytes: number = 0;
  @State cacheFiles: number = 0;
  @State cacheScanning: boolean = true;
  @State clearing: boolean = false;

  // 数据导出 / 导入
  @State exporting: boolean = false;
  @State exportPath: string = '';
  @State importing: boolean = false;
  // 一多：md/lg 无底部 Tab 栏（评审 Step4），底部避让按断点取值
  @StorageProp(CURRENT_BREAKPOINT_KEY) bp: string = 'sm';
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 16;

  // 安全锁
  @State securityLockOn: boolean = false;

  // 关于
  @State versionName: string = '';

  aboutToAppear(): void {
    this.loadAll();
    this.loadTopInset();
  }

  // ───────────────────────── 数据装载 ─────────────────────────

  private async loadAll(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    try {
      const prefs: Prefs = await Prefs.getInstance();
      this.themeModeValue = await prefs.themeMode();
      this.readerModeValue = await prefs.readerMode();
      this.preloadPages = await prefs.preloadPages();
      this.historyEnabled = await prefs.historyEnabled();
      this.autoCache = await prefs.autoCache();
      this.securityLockOn = await prefs.securityLock();
      this.blockTags = await blockTagsStore.getList();

      const domains: Array<string> = jmApi.getDomains();
      const rows: Array<MirrorRow> = [];
      for (const d of domains) {
        const row: MirrorRow = new MirrorRow();
        row.domain = d;
        rows.push(row);
      }
      this.mirrors = rows;
      // 当前使用域名 = 候选池首选（JmApi.rememberGoodDomain 保证所选域名置顶并持久化）
      this.currentDomain = domains.length > 0 ? domains[0] : '';
      this.loading = false;

      this.loadVersion();
      this.loadDownloadCount();
      await this.refreshCacheStats();
    } catch (e) {
      this.loading = false;
      this.loadError = errorMessage(e as Error);
    }
  }

  /** 读取状态栏高度做沉浸避让（失败回退常规值） */
  private async loadTopInset(): Promise<void> {
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      if (ctx !== undefined) {
        const win: window.Window = await window.getLastWindow(ctx);
        const avoid: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.topInset = this.getUIContext().px2vp(avoid.topRect.height);
      }
    } catch (e) {
      this.topInset = 38;
    }
  }

  /** 应用版本号（AppScope/app.json5 versionName；读取失败回退 '1.0.0'） */
  private async loadVersion(): Promise<void> {
    try {
      const info: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.versionName = info.versionName;
    } catch (e) {
      this.versionName = '1.0.0';
    }
  }

  /** 下载任务数（P-02：我的下载（N 个任务）入口；恢复持久化任务列表） */
  private async loadDownloadCount(): Promise<void> {
    try {
      await downloadManager.init();
      this.downloadCount = downloadManager.tasks.length;
    } catch (e) {
      this.downloadCount = 0;
    }
  }

  // ───────────────────────── 镜像切换与测速（SET-21/22） ─────────────────────────

  private async selectDomain(domain: string): Promise<void> {
    if (domain === '' || domain === this.currentDomain) {
      return;
    }
    try {
      await jmApi.setPreferredDomain(domain);
      this.currentDomain = domain;
      this.toast(`已切换镜像：${domain}`);
    } catch (e) {
      this.toast(`切换失败：${errorMessage(e as Error)}`);
    }
  }

  /**
   * 全量测速（契约：jmApi.testDomains 并发测全部候选域名并按延迟排序）。
   * autoPick=true 时一键优选最快（测速后自动切换到最快可用镜像）。
   */
  private async runSpeedTest(autoPick: boolean): Promise<void> {
    if (this.testingAll) {
      return;
    }
    this.testingAll = true;
    try {
      const results: Array<DomainSpeed> = await jmApi.testDomains();
      const next: Array<MirrorRow> = [];
      for (const row of this.mirrors) {
        const updated: MirrorRow = new MirrorRow();
        updated.domain = row.domain;
        for (const r of results) {
          if (r.domain === row.domain) {
            updated.ms = r.ms;
            updated.ok = r.ok;
            updated.tested = true;
            break;
          }
        }
        next.push(updated);
      }
      this.mirrors = next;

      let fastest: DomainSpeed | null = null;
      for (const r of results) {
        if (r.ok && (fastest === null || r.ms < fastest.ms)) {
          fastest = r;
        }
      }
      if (fastest === null) {
        this.toast('测速完成：所有镜像均不可用');
      } else if (autoPick) {
        await jmApi.setPreferredDomain(fastest.domain);
        this.currentDomain = fastest.domain;
        this.toast(`已优选最快镜像 ${fastest.domain}（${fastest.ms} ms）`);
      } else {
        this.toast(`测速完成，最快 ${fastest.ms} ms（${fastest.domain}）`);
      }
    } catch (e) {
      this.toast(`测速失败：${errorMessage(e as Error)}`);
    }
    this.testingAll = false;
  }

  private mirrorStatusText(row: MirrorRow): string {
    if (this.testingAll && !row.tested) {
      return '测速中…';
    }
    if (row.tested) {
      return row.ok ? `${row.ms} ms` : '连接失败';
    }
    return '未测速';
  }

  private mirrorStatusColor(row: MirrorRow): ResourceColor {
    if (row.tested && row.ok) {
      return ACCENT;
    }
    return TEXT_SUB;
  }

  // ───────────────────────── 外观 / 阅读器默认（SET-01/02/08） ─────────────────────────

  /**
   * SET-01 主题三态（跟随系统/浅色/深色）：保存偏好并立即经 ApplicationContext.setColorMode
   * 生效（API 11+）；Index 启动/回前台按同一口径应用。
   */
  private async setThemeMode(mode: string): Promise<void> {
    if (this.themeModeValue === mode) {
      return;
    }
    this.themeModeValue = mode;
    const themeCtx: common.Context = this.getUIContext().getHostContext() as common.Context;
    if (themeCtx !== undefined) {
      applyThemeModeToApp(themeCtx, mode);
    }
    try {
      const prefs: Prefs = await Prefs.getInstance();
      await prefs.setThemeMode(mode);
      this.toast(mode === 'dark' ? '已切换为深色模式'
        : mode === 'light' ? '已切换为浅色模式' : '深浅色将跟随系统');
    } catch (e) {
      this.toast(`保存失败：${errorMessage(e as Error)}`);
    }
  }

  private themeModeLabel(mode: string): string {
    if (mode === 'dark') {
      return '深色';
    }
    if (mode === 'light') {
      return '浅色';
    }
    return '跟随系统';
  }

  private readerModeLabel(mode: string): string {
    if (mode === 'horizontal') {
      return '左右翻页';
    }
    if (mode === 'rtl') {
      return '日漫右翻';
    }
    if (mode === 'double') {
      return '双页拼合';
    }
    return '条漫';
  }

  private readerModeOptions(): Array<ModeOption> {
    const list: Array<ModeOption> = [];
    list.push(new ModeOption('vertical', '条漫'));
    list.push(new ModeOption('horizontal', '左右翻页'));
    list.push(new ModeOption('rtl', '日漫右翻'));
    list.push(new ModeOption('double', '双页拼合'));
    return list;
  }

  private async setReaderMode(mode: string): Promise<void> {
    if (this.readerModeValue === mode) {
      return;
    }
    this.readerModeValue = mode;
    try {
      const prefs: Prefs = await Prefs.getInstance();
      await prefs.setReaderMode(mode);
      this.toast(`默认模式：${this.readerModeLabel(mode)}`);
    } catch (e) {
      this.toast(`保存失败：${errorMessage(e as Error)}`);
    }
  }

  private async setPreload(n: number): Promise<void> {
    if (this.preloadPages === n) {
      return;
    }
    this.preloadPages = n;
    try {
      const prefs: Prefs = await Prefs.getInstance();
      await prefs.setPreloadPages(n);
      this.toast(`预加载页数：${n} 页`);
    } catch (e) {
      this.toast(`保存失败：${errorMessage(e as Error)}`);
    }
  }

  // ───────────────────────── 通用开关（SET-06）与下载入口（P-02） ─────────────────────────

  private async setHistoryEnabled(v: boolean): Promise<void> {
    this.historyEnabled = v;
    try {
      const prefs: Prefs = await Prefs.getInstance();
      await prefs.setHistoryEnabled(v);
      this.toast(v ? '已恢复记录浏览历史' : '已停止记录浏览历史');
    } catch (e) {
      this.toast(`保存失败：${errorMessage(e as Error)}`);
    }
  }

  private async setAutoCache(v: boolean): Promise<void> {
    this.autoCache = v;
    try {
      const prefs: Prefs = await Prefs.getInstance();
      await prefs.setAutoCache(v);
      this.toast(v ? '已开启自动缓存' : '已关闭自动缓存');
    } catch (e) {
      this.toast(`保存失败：${errorMessage(e as Error)}`);
    }
  }

  private openDownloads(): void {
    this.pageStack.pushPathByName(ROUTE_DOWNLOADS, '');
  }

  // ───────────────────────── 屏蔽标签管理（SET-07：添加/列表预览/删除） ─────────────────────────

  /** 码点计数（≤16 字符校验，等价 Kotlin codePointCount） */
  private codePointCount(s: string): number {
    let n: number = 0;
    for (let i: number = 0; i < s.length; i++) {
      const c: number = s.charCodeAt(i);
      if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
        const c2: number = s.charCodeAt(i + 1);
        if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
          i++;
        }
      }
      n++;
    }
    return n;
  }

  private async refreshBlockTags(): Promise<void> {
    this.blockTags = await blockTagsStore.getList();
  }

  /** 添加：trim、非空、≤16 码点、查重（BlockTagsStore.add 内亦有 trim+去重，这里先做带提示的校验） */
  private async addBlockTag(): Promise<void> {
    const t: string = this.blockInput.trim();
    if (t === '') {
      this.blockError = '不能为空';
      return;
    }
    const cp: number = this.codePointCount(t);
    if (cp > BLOCK_TAG_MAX_CP) {
      this.blockError = `最多 ${BLOCK_TAG_MAX_CP} 个字符（当前 ${cp}）`;
      return;
    }
    if (this.blockTags.indexOf(t) >= 0) {
      this.blockError = '已存在';
      return;
    }
    await blockTagsStore.add(t);
    this.blockInput = '';
    this.blockError = '';
    await this.refreshBlockTags();
  }

  private async removeBlockTag(tag: string): Promise<void> {
    await blockTagsStore.remove(tag);
    await this.refreshBlockTags();
  }

  // ───────────────────────── 存储：缓存统计与清理（SET-09，StorageUtil 等价） ─────────────────────────

  /** 递归累计目录字节数与文件数（StorageUtil.dirStats 等价；fs 同步实现，目录规模有限） */
  private dirStats(dir: string, acc: CacheStats): void {
    let names: Array<string> = [];
    try {
      if (!fs.accessSync(dir)) {
        return;
      }
      names = fs.listFileSync(dir);
    } catch (e) {
      return;
    }
    for (const name of names) {
      const path: string = `${dir}/${name}`;
      try {
        const st: fs.Stat = fs.statSync(path);
        if (st.isDirectory()) {
          this.dirStats(path, acc);
        } else {
          acc.bytes += st.size;
          acc.files++;
        }
      } catch (e) {
        // 单项失败跳过
      }
    }
  }

  private async refreshCacheStats(): Promise<void> {
    this.cacheScanning = true;
    const stats: CacheStats = new CacheStats();
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      if (ctx === undefined) {
        throw new Error('页面宿主上下文不可用');
      }
      // 与数据层目录约定对齐：cacheDir（系统图片缓存 + 下载临时）+ filesDir/page_cache（阅读页缓存）
      this.dirStats(`${ctx.cacheDir}`, stats);
      this.dirStats(`${ctx.filesDir}/page_cache`, stats);
    } catch (e) {
      // 保留旧值
    }
    this.cacheBytes = stats.bytes;
    this.cacheFiles = stats.files;
    this.cacheScanning = false;
  }

  /** 递归删除文件或目录（本 SDK fs 无 rmSync，用 unlinkSync/rmdirSync 组合） */
  private rmTree(path: string): void {
    let isDir: boolean = false;
    try {
      const st: fs.Stat = fs.statSync(path);
      isDir = st.isDirectory();
    } catch (e) {
      return;
    }
    if (!isDir) {
      try {
        fs.unlinkSync(path);
      } catch (e) {
        // 单项失败跳过
      }
      return;
    }
    let names: Array<string> = [];
    try {
      names = fs.listFileSync(path);
    } catch (e) {
      return;
    }
    for (const name of names) {
      this.rmTree(`${path}/${name}`);
    }
    try {
      fs.rmdirSync(path);
    } catch (e) {
      // 目录非空等失败跳过
    }
  }

  /** 清理目录下全部子项（不删目录本身） */
  private rmChildren(dir: string): void {
    let names: Array<string> = [];
    try {
      if (!fs.accessSync(dir)) {
        return;
      }
      names = fs.listFileSync(dir);
    } catch (e) {
      return;
    }
    for (const name of names) {
      this.rmTree(`${dir}/${name}`);
    }
  }

  private confirmClearCache(): void {
    if (this.clearing) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '清除缓存',
      message: '将删除已缓存的图片、阅读页缓存与下载临时文件（不影响收藏、历史与已完成的下载），确定吗？',
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '清除',
        fontColor: PRIMARY,
        action: (): void => {
          this.doClearCache();
        }
      }
    });
  }

  private async doClearCache(): Promise<void> {
    this.clearing = true;
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      if (ctx === undefined) {
        throw new Error('页面宿主上下文不可用');
      }
      this.rmChildren(`${ctx.cacheDir}`);
      this.rmChildren(`${ctx.filesDir}/page_cache`);
      await this.refreshCacheStats();
      this.toast('缓存已清除');
    } catch (e) {
      this.toast(`清除失败：${errorMessage(e as Error)}`);
    }
    this.clearing = false;
  }

  private formatBytes(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    const kb: number = bytes / 1024.0;
    if (kb < 1024) {
      return `${kb.toFixed(1)} KB`;
    }
    const mb: number = kb / 1024.0;
    if (mb < 1024) {
      return `${mb.toFixed(1)} MB`;
    }
    return `${(mb / 1024.0).toFixed(2)} GB`;
  }

  // ───────────────────────── 数据导出（SET-19，DataTransfer.buildExport 等价） ─────────────────────────

  private fileStamp(ts: number): string {
    const d: Date = new Date(ts);
    const p2 = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    return `${d.getFullYear()}${p2(d.getMonth() + 1)}${p2(d.getDate())}` +
      `_${p2(d.getHours())}${p2(d.getMinutes())}${p2(d.getSeconds())}`;
  }

  private async exportData(): Promise<void> {
    if (this.exporting) {
      return;
    }
    this.exporting = true;
    try {
      const favItems: Array<FavItem> = await favStore.getList();
      const favTags: Array<string> = await favStore.getTags();
      const browse: Array<HistoryItem> = await historyStore.getList();
      const search: Array<string> = await searchHistoryStore.getList();

      const root: ExportRoot = new ExportRoot();
      root.exportedAt = Date.now();
      root.favorites.items = favItems;
      root.favorites.tags = favTags;
      root.history.browse = browse;
      root.history.search = search;
      const json: string = JSON.stringify(root);

      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      if (ctx === undefined) {
        throw new Error('页面宿主上下文不可用，导出失败');
      }
      // 评审 Step4：优先经系统文件选择器（DocumentViewPicker）保存到用户可见的公共目录；
      // 选择器取消或不可用时回退应用沙箱 Export 目录（原 SET-19 行为）
      let savedTo: string = '';
      try {
        const pickerInst: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
        const opt: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
        opt.newFileNames = [`jm_backup_${this.fileStamp(Date.now())}.json`];
        const uris: Array<string> = await pickerInst.save(opt);
        if (uris.length > 0) {
          const file: fs.File = fs.openSync(uris[0],
            fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
          fs.writeSync(file.fd, json);
          fs.closeSync(file);
          savedTo = uris[0];
        }
      } catch (e) {
        // 选择器异常走沙箱回退
      }
      if (savedTo === '') {
        const dir: string = `${ctx.filesDir}/Export`;
        if (!fs.accessSync(dir)) {
          fs.mkdirSync(dir, true);
        }
        savedTo = `${dir}/jm_backup_${this.fileStamp(Date.now())}.json`;
        const file: fs.File = fs.openSync(savedTo,
          fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, json);
        fs.closeSync(file);
      }

      this.exportPath = savedTo;
      this.toast(`已导出：收藏 ${favItems.length} 项 · 历史 ${browse.length} 条`);
    } catch (e) {
      this.toast(`导出失败：${errorMessage(e as Error)}`);
    }
    this.exporting = false;
  }

  // ───────────────────────── 数据导入（评审 Step4：备份 JSON 合并式恢复） ─────────────────────────

  private parseFavItems(section: Object | undefined): Array<FavItem> {
    const out: Array<FavItem> = [];
    const rec: Record<string, Object> | null = asRecord(section);
    if (rec === null) {
      return out;
    }
    const arr: Array<Object> | null = asArray(rec['items']);
    if (arr === null) {
      return out;
    }
    for (const it of arr) {
      const r: Record<string, Object> | null = asRecord(it);
      if (r === null) {
        continue;
      }
      out.push(new FavItem(asString(r['id']), asString(r['title']), asString(r['author']),
        asString(r['coverUrl']), asNumber(r['addedAt'], 0)));
    }
    return out;
  }

  private parseFavTags(section: Object | undefined): Array<string> {
    const out: Array<string> = [];
    const rec: Record<string, Object> | null = asRecord(section);
    if (rec === null) {
      return out;
    }
    const arr: Array<Object> | null = asArray(rec['tags']);
    if (arr === null) {
      return out;
    }
    for (const t of arr) {
      const s: string = asString(t);
      if (s !== '') {
        out.push(s);
      }
    }
    return out;
  }

  private parseBrowseHistory(section: Object | undefined): Array<HistoryItem> {
    const out: Array<HistoryItem> = [];
    const rec: Record<string, Object> | null = asRecord(section);
    if (rec === null) {
      return out;
    }
    const arr: Array<Object> | null = asArray(rec['browse']);
    if (arr === null) {
      return out;
    }
    for (const it of arr) {
      const r: Record<string, Object> | null = asRecord(it);
      if (r === null) {
        continue;
      }
      out.push(new HistoryItem(asString(r['id']), asString(r['title']), asString(r['author']),
        asString(r['coverUrl']), asNumber(r['viewedAt'], 0)));
    }
    return out;
  }

  private parseSearchHistory(section: Object | undefined): Array<string> {
    const out: Array<string> = [];
    const rec: Record<string, Object> | null = asRecord(section);
    if (rec === null) {
      return out;
    }
    const arr: Array<Object> | null = asArray(rec['search']);
    if (arr === null) {
      return out;
    }
    for (const t of arr) {
      const s: string = asString(t);
      if (s !== '') {
        out.push(s);
      }
    }
    return out;
  }

  /**
   * 导入备份（评审 Step4）：DocumentViewPicker 选 JSON → 四段合并导入
   * （收藏/收藏标签/浏览历史按 id 去重合并，搜索历史去重置顶）；Stores 导入接口
   * 内部递增 bookshelfDataVersion，书架页 @Watch 自动刷新。
   */
  private async importData(): Promise<void> {
    if (this.importing) {
      return;
    }
    this.importing = true;
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      if (ctx === undefined) {
        throw new Error('页面宿主上下文不可用，导入失败');
      }
      const pickerInst: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      const opt: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      opt.maxSelectNumber = 1;
      opt.fileSuffixFilters = ['.json'];
      const uris: Array<string> = await pickerInst.select(opt);
      if (uris.length === 0) {
        this.importing = false;
        return;
      }
      const file: fs.File = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
      const stat: fs.Stat = fs.statSync(file.fd);
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);

      const parsed: Object | null = JSON.parse(utf8Decode(new Uint8Array(buf))) as Object | null;
      const root: Record<string, Object> | null = asRecord(parsed);
      if (root === null) {
        throw new Error('备份文件格式无效');
      }
      const favItems: Array<FavItem> = this.parseFavItems(root['favorites']);
      const favTags: Array<string> = this.parseFavTags(root['favorites']);
      const browse: Array<HistoryItem> = this.parseBrowseHistory(root['history']);
      const search: Array<string> = this.parseSearchHistory(root['history']);

      const addedFav: number = await favStore.importItems(favItems);
      await favStore.importTags(favTags);
      const addedHist: number = await historyStore.importItems(browse);
      await searchHistoryStore.importAll(search);

      this.toast(`导入成功：新增收藏 ${addedFav} 项 · 新增历史 ${addedHist} 条`);
    } catch (e) {
      this.toast(`导入失败：${errorMessage(e as Error)}`);
    }
    this.importing = false;
  }

  // ───────────────────────── 安全锁（SET-24，S 级：失败回退为仅开关） ─────────────────────────

  private onSecurityLockToggle(v: boolean): void {
    if (!v) {
      this.applySecurityLock(false, '应用锁已关闭');
      return;
    }
    this.attemptFingerprint();
  }

  /** userAuth 指纹验证：成功开启应用锁；不可用/未通过时按 S 级降级为仅保存开关 */
  private attemptFingerprint(): void {
    // 前置可用性检查（未录入指纹/设备不支持/锁定中会抛错）
    try {
      userIAM.getAvailableStatus(userIAM.UserAuthType.FINGERPRINT, userIAM.AuthTrustLevel.ATL2);
    } catch (e) {
      this.applySecurityLock(true, `指纹不可用（${errorMessage(e as Error)}），已仅保存开关状态`);
      return;
    }
    try {
      const authParam: userIAM.AuthParam = {
        challenge: new Uint8Array([1, 2, 3, 4, 5, 6, 7]),
        authType: [userIAM.UserAuthType.FINGERPRINT],
        authTrustLevel: userIAM.AuthTrustLevel.ATL2
      };
      const widgetParam: userIAM.WidgetParam = { title: '验证指纹以开启应用锁' };
      const auth: userIAM.UserAuthInstance = userIAM.getUserAuthInstance(authParam, widgetParam);
      const handler: AuthResultHandler = new AuthResultHandler(this);
      handler.setInstance(auth);
      auth.on('result', handler);
      auth.start();
    } catch (e) {
      this.applySecurityLock(true, `指纹不可用（${errorMessage(e as Error)}），已仅保存开关状态`);
    }
  }

  /** 指纹验证结果回传（AuthResultHandler 调用；公开仅供本文件回调类访问） */
  onAuthResult(msg: string): void {
    this.applySecurityLock(true, msg);
  }

  private async applySecurityLock(on: boolean, msg: string): Promise<void> {
    this.securityLockOn = on;
    try {
      const prefs: Prefs = await Prefs.getInstance();
      await prefs.setSecurityLock(on);
      if (msg !== '') {
        this.toast(msg);
      }
    } catch (e) {
      this.toast(`保存失败：${errorMessage(e as Error)}`);
    }
  }

  // ───────────────────────── 剪贴板 / 轻提示 ─────────────────────────

  private copyToClipboard(text: string, tip: string): void {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      board.setData(data).then((): void => {
        this.toast(tip);
      }).catch((e: Error): void => {
        this.toast(`复制失败：${errorMessage(e)}`);
      });
    } catch (e) {
      this.toast(`复制失败：${errorMessage(e as Error)}`);
    }
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
    } catch (e) {
      // 提示失败静默
    }
  }

  // ───────────────────────── 视图 ─────────────────────────

  @Builder
  private GroupTitle(title: string) {
    Text(title)
      .fontSize(FONT_TITLE)
      .fontWeight(FontWeight.Bold)
      .fontColor(TEXT_MAIN)
      .maxLines(1)
      .width('100%')
      .padding({ top: SPACE_S, bottom: SPACE_S })
  }

  @Builder
  private CardDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(DIVIDER)
      .margin({ left: SPACE_L, right: SPACE_L })
  }

  /** 加载骨架（本地设置读取极快，仅兜底展示） */
  @Builder
  private SettingsSkeleton() {
    Column({ space: SPACE_M }) {
      ForEach(SKELETON_GROUPS, (g: number) => {
        Column({ space: SPACE_S }) {
          Column()
            .height(18)
            .width('30%')
            .borderRadius(4)
            .backgroundColor(DIVIDER)
            .opacity(this.skelAlpha)
          Column()
            .height(96)
            .width('100%')
            .borderRadius(CARD_R)
            .backgroundColor(DIVIDER)
            .opacity(this.skelAlpha)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (g: number) => `settings_skel_${g}`)
    }
    .width('100%')
    .padding({ top: SPACE_M })
    .onAppear(() => {
      this.getUIContext().animateTo({ duration: 800, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate }, () => {
        this.skelAlpha = 0.35;
      })
    })
  }

  /** 图源与镜像分组（自定义头：一键测速 / 优选最快） */
  @Builder
  private MirrorGroup() {
    Column() {
      Row() {
        Text('图源与镜像')
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)
          .maxLines(1)
        Text(this.testingAll ? '测速中…' : '一键测速')
          .fontSize(FONT_CAPTION)
          .fontColor(this.testingAll ? TAB_INACTIVE : PRIMARY)
          .padding({ left: SPACE_S, right: SPACE_S, top: SPACE_S, bottom: SPACE_S })
          .onClick(() => {
            this.runSpeedTest(false);
          })
        Text('优选最快')
          .fontSize(FONT_CAPTION)
          .fontColor(this.testingAll ? TAB_INACTIVE : ACCENT)
          .padding({ left: SPACE_S, right: SPACE_S, top: SPACE_S, bottom: SPACE_S })
          .onClick(() => {
            this.runSpeedTest(true);
          })
      }
      .width('100%')
      .padding({ top: SPACE_S, bottom: SPACE_S })

      Column() {
        if (this.mirrors.length === 0) {
          Text('暂无可用镜像域名')
            .fontSize(FONT_CAPTION)
            .fontColor(TEXT_SUB)
            .width('100%')
            .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_L, bottom: SPACE_L })
        }
        ForEach(this.mirrors, (row: MirrorRow, index: number) => {
          if (index > 0) {
            this.CardDivider()
          }
          Row({ space: SPACE_M }) {
            Row({ space: SPACE_M }) {
              Radio({ value: row.domain, group: 'mirror_group' })
                .checked(this.currentDomain === row.domain)
                .width(20)
                .height(20)
                .hitTestBehavior(HitTestMode.None)
              Column({ space: 2 }) {
                Text(row.domain)
                  .fontSize(FONT_BODY)
                  .fontColor(TEXT_MAIN)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.mirrorStatusText(row))
                  .fontSize(FONT_CAPTION)
                  .fontColor(this.mirrorStatusColor(row))
                  .maxLines(1)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .layoutWeight(1)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.selectDomain(row.domain);
            })

            if (this.currentDomain === row.domain) {
              Text('当前使用')
                .fontSize(FONT_CAPTION)
                .fontColor(Color.White)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(PRIMARY)
                .borderRadius(CHIP_R)
            }
            Button('测速')
              .fontSize(FONT_CAPTION)
              .fontColor(Color.White)
              .backgroundColor(ACCENT)
              .borderRadius(CHIP_R)
              .height(28)
              .padding({ left: 10, right: 10 })
              .enabled(!this.testingAll)
              .onClick(() => {
                this.runSpeedTest(false);
              })
          }
          .width('100%')
          .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_M, bottom: SPACE_M })
          .alignItems(VerticalAlign.Center)
        }, (row: MirrorRow) => row.domain)
      }
      .width('100%')
      .backgroundColor(CARD)
      .borderRadius(CARD_R)
      .clip(true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 外观分组：主题三态（SET-01 M：跟随系统/浅色/深色，立即生效） */
  @Builder
  private AppearanceGroup() {
    Column() {
      this.GroupTitle('外观')
      Column() {
        Column({ space: SPACE_S }) {
          Text('主题模式')
            .fontSize(FONT_BODY)
            .fontColor(TEXT_MAIN)
          Row({ space: SPACE_S }) {
            ForEach(buildThemeOptions(), (opt: ThemeOption) => {
              TagChip({
                label: opt.label,
                selected: this.themeModeValue === opt.value,
                onChipClick: (): void => {
                  this.setThemeMode(opt.value);
                }
              })
            }, (opt: ThemeOption) => `theme_${opt.value}`)
          }
          .width('100%')
          Text('当前：' + this.themeModeLabel(this.themeModeValue) + ' · 经系统 setColorMode 立即生效，启动时按本设置应用')
            .fontSize(FONT_CAPTION)
            .fontColor(TEXT_SUB)
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_M, bottom: SPACE_M })
      }
      .width('100%')
      .backgroundColor(CARD)
      .borderRadius(CARD_R)
      .clip(true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 阅读器默认分组：默认模式 + 预加载页数档位 */
  @Builder
  private ReaderGroup() {
    Column() {
      this.GroupTitle('阅读器默认')
      Column() {
        Column({ space: SPACE_S }) {
          Text('默认阅读模式')
            .fontSize(FONT_BODY)
            .fontColor(TEXT_MAIN)
          Row({ space: SPACE_S }) {
            ForEach(this.readerModeOptions(), (m: ModeOption) => {
              TagChip({
                label: m.label,
                selected: this.readerModeValue === m.value,
                onChipClick: (): void => {
                  this.setReaderMode(m.value);
                }
              })
            }, (m: ModeOption) => `mode_${m.value}`)
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_M, bottom: SPACE_M })

        this.CardDivider()

        Column({ space: SPACE_S }) {
          Text(`预加载页数（当前 ${this.preloadPages} 页）`)
            .fontSize(FONT_BODY)
            .fontColor(TEXT_MAIN)
          Row({ space: SPACE_S }) {
            ForEach(PRELOAD_TIERS, (n: number) => {
              TagChip({
                label: `${n} 页`,
                selected: this.preloadPages === n,
                onChipClick: (): void => {
                  this.setPreload(n);
                }
              })
            }, (n: number) => `preload_${n}`)
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_M, bottom: SPACE_M })
      }
      .width('100%')
      .backgroundColor(CARD)
      .borderRadius(CARD_R)
      .clip(true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 通用分组：记录浏览历史开关 + 屏蔽标签管理（SET-07）+ 我的下载入口 */
  @Builder
  private GeneralGroup() {
    Column() {
      this.GroupTitle('通用')
      Column() {
        SwitchRow({
          title: '记录浏览历史',
          subtitle: '关闭后不再记录浏览与阅读进度',
          isOn: this.historyEnabled,
          onToggle: (v: boolean): void => {
            this.setHistoryEnabled(v);
          }
        })
        this.CardDivider()
        ActionRow({
          title: '屏蔽标签',
          subtitle: '命中标题/作者/分类的作品将从各列表隐藏',
          trailing: `${this.blockTags.length} 个`,
          onTap: (): void => {
            this.blockError = '';
            this.blockInput = '';
            this.blockSheet = true;
          }
        })
        this.CardDivider()
        ActionRow({
          title: '我的下载',
          subtitle: '查看下载队列与已导出的 CBZ',
          trailing: `${this.downloadCount} 个任务`,
          onTap: (): void => {
            this.openDownloads();
          }
        })
      }
      .width('100%')
      .backgroundColor(CARD)
      .borderRadius(CARD_R)
      .clip(true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** SET-07 屏蔽标签管理弹层：添加（≤16 字符/查重）+ 列表预览 + 行内删除 */
  @Builder
  private BlockTagsSheet() {
    Column({ space: SPACE_M }) {
      Text('屏蔽标签')
        .fontSize(FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .width('100%')

      Row({ space: SPACE_S }) {
        TextInput({ text: this.blockInput, placeholder: '添加屏蔽关键词（≤16 字符）' })
          .layoutWeight(1)
          .height(38)
          .fontSize(FONT_BODY)
          .fontColor(TEXT_MAIN)
          .backgroundColor(BG)
          .borderRadius(CHIP_R)
          .padding({ left: SPACE_M, right: SPACE_M })
          .onChange((v: string) => {
            this.blockInput = v;
            this.blockError = '';
          })
          .onSubmit(() => {
            this.addBlockTag();
          })
        Text('添加')
          .fontSize(FONT_BODY)
          .fontColor(Color.White)
          .padding({ left: 14, right: 14, top: 9, bottom: 9 })
          .backgroundColor(PRIMARY)
          .borderRadius(CHIP_R)
          .onClick(() => {
            this.addBlockTag();
          })
      }
      .width('100%')

      if (this.blockError !== '') {
        Text(this.blockError)
          .fontSize(FONT_CAPTION)
          .fontColor(PRIMARY)
          .width('100%')
      }

      Scroll() {
        Column({ space: 0 }) {
          if (this.blockTags.length === 0) {
            Text('暂无屏蔽标签；添加后命中标题/作者/分类/子分类的作品将在各列表隐藏（下次刷新生效）')
              .fontSize(FONT_CAPTION)
              .fontColor(TEXT_SUB)
              .width('100%')
              .padding({ top: SPACE_M, bottom: SPACE_M })
          }
          ForEach(this.blockTags, (tag: string) => {
            Row({ space: SPACE_M }) {
              Text(tag)
                .fontSize(FONT_BODY)
                .fontColor(TEXT_MAIN)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text('✕')
                .fontSize(FONT_BODY)
                .fontColor(TEXT_SUB)
                .padding({ left: SPACE_S, right: SPACE_S })
                .onClick(() => {
                  this.removeBlockTag(tag);
                })
            }
            .width('100%')
            .padding({ top: 12, bottom: 12 })
          }, (tag: string) => 'block_' + tag)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Text('完成')
        .fontSize(FONT_BODY)
        .fontColor(Color.White)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 11, bottom: 11 })
        .backgroundColor(ACCENT)
        .borderRadius(CHIP_R)
        .margin({ bottom: SPACE_L })
        .onClick(() => {
          this.blockSheet = false;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CARD)
    .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_L })
  }

  /** 存储分组：缓存统计/刷新/清理 + 自动缓存开关 */
  @Builder
  private StorageGroup() {
    Column() {
      this.GroupTitle('存储')
      Column() {
        Row({ space: SPACE_M }) {
          Column({ space: 2 }) {
            Text('缓存占用')
              .fontSize(FONT_BODY)
              .fontColor(TEXT_MAIN)
            Text(this.cacheScanning ? '统计中…' : `${this.formatBytes(this.cacheBytes)} · ${this.cacheFiles} 个文件`)
              .fontSize(FONT_CAPTION)
              .fontColor(TEXT_SUB)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text('刷新')
            .fontSize(FONT_CAPTION)
            .fontColor(ACCENT)
            .padding({ left: SPACE_S, right: SPACE_S, top: SPACE_S, bottom: SPACE_S })
            .onClick(() => {
              this.refreshCacheStats();
            })
        }
        .width('100%')
        .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_M, bottom: SPACE_M })
        .alignItems(VerticalAlign.Center)

        this.CardDivider()

        SwitchRow({
          title: '自动缓存',
          subtitle: '阅读时自动缓存图片',
          isOn: this.autoCache,
          onToggle: (v: boolean): void => {
            this.setAutoCache(v);
          }
        })

        this.CardDivider()

        ActionRow({
          title: this.clearing ? '清除中…' : '清除缓存',
          subtitle: '清理图片、阅读页缓存与下载临时文件',
          onTap: (): void => {
            this.confirmClearCache();
          }
        })
      }
      .width('100%')
      .backgroundColor(CARD)
      .borderRadius(CARD_R)
      .clip(true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 数据分组：收藏与历史 JSON 导出（展示路径 + 复制路径） */
  @Builder
  private DataGroup() {
    Column() {
      this.GroupTitle('数据')
      Column() {
        ActionRow({
          title: this.exporting ? '导出中…' : '导出数据',
          subtitle: '收藏与浏览/搜索历史导出为 JSON 备份（系统选择器选保存位置）',
          trailing: this.exporting ? '' : '导出',
          onTap: (): void => {
            this.exportData();
          }
        })
        this.CardDivider()
        ActionRow({
          title: this.importing ? '导入中…' : '导入数据',
          subtitle: '从 JSON 备份合并收藏与历史（按 id 去重，不覆盖现有）',
          trailing: this.importing ? '' : '导入',
          onTap: (): void => {
            this.importData();
          }
        })
        if (this.exportPath !== '') {
          this.CardDivider()
          Column({ space: SPACE_S }) {
            Text('已导出到：')
              .fontSize(FONT_CAPTION)
              .fontColor(TEXT_SUB)
            Text(this.exportPath)
              .fontSize(FONT_CAPTION)
              .fontColor(TEXT_MAIN)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text('复制路径')
              .fontSize(FONT_CAPTION)
              .fontColor(ACCENT)
              .alignSelf(ItemAlign.Start)
              .padding({ top: SPACE_S })
              .onClick(() => {
                this.copyToClipboard(this.exportPath, '已复制导出路径');
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_M, bottom: SPACE_M })
        }
      }
      .width('100%')
      .backgroundColor(CARD)
      .borderRadius(CARD_R)
      .clip(true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 隐私分组：应用锁开关 + 指纹解锁（S 级） */
  @Builder
  private SecurityGroup() {
    Column() {
      this.GroupTitle('安全锁')
      Column() {
        SwitchRow({
          title: '应用锁',
          subtitle: '开启后使用指纹解锁进入应用',
          isOn: this.securityLockOn,
          onToggle: (v: boolean): void => {
            this.onSecurityLockToggle(v);
          }
        })
        this.CardDivider()
        Text('基于系统指纹验证（userAuth）。开启后应用启动与回到前台时（入口页 Index 拦截）会先要求指纹验证；若设备未录入指纹或验证组件不可用，将按简化方案仅保存开关状态。')
          .fontSize(FONT_CAPTION)
          .fontColor(TEXT_SUB)
          .width('100%')
          .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_M, bottom: SPACE_M })
      }
      .width('100%')
      .backgroundColor(CARD)
      .borderRadius(CARD_R)
      .clip(true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 关于分组：版本 / 开源致谢与声明 / 复制项目地址 */
  @Builder
  private AboutGroup() {
    Column() {
      this.GroupTitle('关于')
      Column() {
        Row({ space: SPACE_M }) {
          Column({ space: 2 }) {
            Text(`版本 ${this.versionName === '' ? '…' : this.versionName}`)
              .fontSize(FONT_CAPTION)
              .fontColor(TEXT_SUB)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_M, bottom: SPACE_M })

        this.CardDivider()

        Column({ space: SPACE_S }) {
          Text('声明：本项目仅供个人学习交流使用，请勿用于任何商业用途；所有内容数据均来自第三方公开接口，与本应用无关。')
            .fontSize(FONT_CAPTION)
            .fontColor(TEXT_SUB)
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_M, bottom: SPACE_M })

        this.CardDivider()
      }
      .width('100%')
      .backgroundColor(CARD)
      .borderRadius(CARD_R)
      .clip(true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      // 页标题（沉浸式布局下自避让状态栏）
      Row() {
        Text(this.sourceOnly ? '设置' : '我的')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
      }
      .width('100%')
      .height(48)
      .padding({ left: SPACE_L, right: SPACE_L })
      .margin({ top: this.topInset })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: SPACE_M }) {
          if (this.loading) {
            // 加载态：分组骨架
            this.SettingsSkeleton()
          } else if (this.loadError !== '') {
            // 错误态 + 重试
            EmptyView({
              message: `设置加载失败：${this.loadError}`,
              retryText: '重试',
              showRetry: true,
              onRetry: (): void => {
                this.loadAll();
              }
            })
          } else {
            this.MirrorGroup()
            ActionRow({ title: '屏蔽标签', trailing: `${this.blockTags.length} 个`, onTap: (): void => { this.blockSheet = true; } })
          }
        }
        .width('100%')
        .padding({
          left: SPACE_L,
          right: SPACE_L,
          top: SPACE_S,
          // md/lg 断点无底部 Tab 栏（评审 Step4），仅避让系统导航条
          bottom: (this.bp === 'sm' ? TAB_BAR_HEIGHT : 0) + this.bottomInset + SPACE_XL
        })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
    .bindSheet($$this.blockSheet, this.BlockTagsSheet(), {
      height: 480,
      dragBar: true,
      onDisappear: (): void => {
        this.blockSheet = false;
      }
    })
  }
}
