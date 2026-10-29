/**
 * 偏好设置持久化封装（@ohos.data.preferences）
 */

import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';

/** 全部偏好 key 常量（集中定义，页面层只读引用） */
export class PrefKeys {
  // ── JmApi 自用（JmApi.kt:56-62）──
  static readonly API_DOMAINS: string = 'jm_domains';
  static readonly LAST_DOMAIN: string = 'jm_last_domain';
  static readonly IMAGE_HOST: string = 'jm_image_host';
  static readonly APP_VERSION: string = 'jm_app_version';
  static readonly HOST_ORDER: string = 'jm_host_order';
  static readonly HOST_ORDER_TS: string = 'jm_host_order_ts';
  // ── 通用偏好（AppPrefs.kt，O 级键已剔除）──
  static readonly AUTO_CACHE: string = 'auto_cache';
  static readonly HISTORY_ENABLED: string = 'history_enabled';
  static readonly PRIVACY_MODE: string = 'privacy_mode';
  static readonly ARCHIVE_IMG_QUALITY: string = 'archive_img_quality';
  // ── 鸿蒙版新增（conventions §4：主题模式、阅读器默认模式/预加载页数、亮度记忆、安全锁）──
  static readonly THEME_MODE: string = 'theme_mode';
  static readonly READER_MODE: string = 'reader_mode';
  static readonly READER_BG: string = 'reader_bg_paper';
  /** 点击左右两侧翻页（默认开）。 */
  static readonly READER_TAP_TURN: string = 'reader_tap_turn';
  static readonly PRELOAD_PAGES: string = 'preload_pages';
  static readonly BRIGHTNESS: string = 'reader_brightness';
  static readonly SECURITY_LOCK: string = 'security_lock';
  /** 系统窗口隐私保护；沿用既有偏好键。 */
  static readonly PREVIEW_PROTECTION: string = 'preview_protection';
  // ── 鸿蒙版新增（api-spec §3.3 [M] 第 2 条：图片解码并发，0=自动；对应 PageLoader.kt:31-44）──
  static readonly DECODE_CONCURRENCY: string = 'decode_concurrency';
  // ── 本地 Store 持久化（JSON 字符串，Stores.ets / DownloadManager.ets 使用）──
  static readonly FAV_ITEMS: string = 'store_fav_items';
  static readonly FAV_TAGS: string = 'store_fav_tags';
  static readonly HISTORY_ITEMS: string = 'store_history_items';
  static readonly READ_PROGRESS: string = 'store_read_progress';
  static readonly SEARCH_HISTORY: string = 'store_search_history';
  static readonly BLOCK_TAGS: string = 'store_block_tags';
  static readonly CUSTOM_CATS: string = 'store_custom_cats';
  static readonly DOWNLOAD_TASKS: string = 'store_download_tasks';
  static readonly ALBUM_CACHE: string = 'store_album_cache';
  static readonly PAGES_CACHE: string = 'store_pages_cache';
}

let appContext: common.Context | null = null;

/** 注入应用上下文（EntryAbility.onWindowStageCreate / 首页 aboutToAppear 时调用一次即可） */
export function setAppContext(context: common.Context): void {
  appContext = context;
}

/** 取应用上下文：仅认显式注入（EntryAbility 启动即调 jmApi.init/setAppContext）；未注入抛带说明的 Error（Review M-7：移除废弃全局 getContext 兜底） */
export function getAppContext(): common.Context {
  if (appContext !== null) {
    return appContext;
  }
  throw new Error('应用上下文未初始化：请在 EntryAbility 启动或页面 aboutToAppear 时调用 jmApi.init(context) 或 setAppContext(context)');
}

/**
 * 偏好设置单例封装。
 * 写入顺序落盘；失败恢复原值并交由调用方提示，避免界面显示未保存的结果。
 */
export class Prefs {
  private static instance: Prefs | null = null;
  private storeRef: preferences.Preferences | null = null;
  private pendingWrite: Promise<void> = Promise.resolve();

  private constructor() {
  }

  /** 获取单例（首次调用完成 preferences 文件加载） */
  static async getInstance(): Promise<Prefs> {
    if (Prefs.instance === null) {
      const p: Prefs = new Prefs();
      const context: common.Context = getAppContext();
      p.storeRef = preferences.getPreferencesSync(context, { name: 'manyu_prefs_v1' });
      Prefs.instance = p;
    }
    return Prefs.instance;
  }

  async getString(key: string, def: string): Promise<string> {
    const s: preferences.Preferences = await this.prefs();
    const v: preferences.ValueType = s.getSync(key, def);
    return typeof v === 'string' ? v : def;
  }

  async putString(key: string, value: string): Promise<void> {
    return this.write(key, value);
  }

  async getNumber(key: string, def: number): Promise<number> {
    const s: preferences.Preferences = await this.prefs();
    const v: preferences.ValueType = s.getSync(key, def);
    return typeof v === 'number' ? v : def;
  }

  async putNumber(key: string, value: number): Promise<void> {
    return this.write(key, value);
  }

  async getBool(key: string, def: boolean): Promise<boolean> {
    const s: preferences.Preferences = await this.prefs();
    const v: preferences.ValueType = s.getSync(key, def);
    return typeof v === 'boolean' ? v : def;
  }

  async putBool(key: string, value: boolean): Promise<void> {
    return this.write(key, value);
  }

  /** 顺序提交并等待落盘，调用者可以据失败结果保留原界面状态。 */
  private write(key: string, value: preferences.ValueType): Promise<void> {
    const next: Promise<void> = this.pendingWrite.then(async (): Promise<void> => {
      const s: preferences.Preferences = await this.prefs();
      const previous: preferences.ValueType = s.getSync(key, value);
      try {
        await s.put(key, value);
        await s.flush();
      } catch (e) {
        await s.put(key, previous);
        throw e as Error;
      }
    });
    this.pendingWrite = next.catch((): void => {});
    return next;
  }

  private async prefs(): Promise<preferences.Preferences> {
    const p: Prefs = await Prefs.getInstance();
    if (p.storeRef === null) {
      throw new Error('preferences 未初始化');
    }
    return p.storeRef;
  }

  async remove(key: string): Promise<void> {
    const removal: Promise<void> = this.pendingWrite.then(async (): Promise<void> => {
      const store: preferences.Preferences = await this.prefs();
      await store.delete(key);
      await store.flush();
    });
    this.pendingWrite = removal.catch((): void => {});
    return removal;
  }

  // ───────────────────────── 类型化便捷读写（页面层直接用） ─────────────────────────

  /** 自动缓存页图（默认开，AppPrefs auto_cache） */
  async autoCache(): Promise<boolean> {
    return this.getBool(PrefKeys.AUTO_CACHE, true);
  }

  async setAutoCache(v: boolean): Promise<void> {
    return this.putBool(PrefKeys.AUTO_CACHE, v);
  }

  /** 是否记录浏览历史（默认开，HistoryStore.record 前置判断） */
  async historyEnabled(): Promise<boolean> {
    return this.getBool(PrefKeys.HISTORY_ENABLED, true);
  }

  async setHistoryEnabled(v: boolean): Promise<void> {
    return this.putBool(PrefKeys.HISTORY_ENABLED, v);
  }

  /** 主题模式：system / light / dark（对应 ThemePrefs） */
  async themeMode(): Promise<string> {
    return this.getString(PrefKeys.THEME_MODE, 'system');
  }

  async setThemeMode(v: string): Promise<void> {
    return this.putString(PrefKeys.THEME_MODE, v);
  }

  /** 阅读器默认模式：vertical / horizontal / rtl / double（S 级：后两档渲染可后补） */
  async readerMode(): Promise<string> {
    return this.getString(PrefKeys.READER_MODE, 'vertical');
  }

  async setReaderMode(v: string): Promise<void> {
    return this.putString(PrefKeys.READER_MODE, v);
  }

  /** 阅读器背景纸色偏好（false=深邃黑 / true=米黄纸；评审 Step4 持久化） */
  async readerBgPaper(): Promise<boolean> {
    return this.getBool(PrefKeys.READER_BG, false);
  }

  /** 点击左右两侧翻页（默认开）；关闭后点按任意位置只呼出菜单。 */
  async readerTapTurn(): Promise<boolean> {
    return this.getBool(PrefKeys.READER_TAP_TURN, true);
  }

  async setReaderTapTurn(v: boolean): Promise<void> {
    return this.putBool(PrefKeys.READER_TAP_TURN, v);
  }

  /** 阅读器预加载页数（默认 3） */
  async preloadPages(): Promise<number> {
    return this.getNumber(PrefKeys.PRELOAD_PAGES, 3);
  }

  async setPreloadPages(v: number): Promise<void> {
    return this.putNumber(PrefKeys.PRELOAD_PAGES, v);
  }

  /** 图片解码并发（0=自动→默认 4；1..512 取设置值，ImageDecode 内部封顶 32；PageLoader.kt:31-44） */
  async decodeConcurrency(): Promise<number> {
    return this.getNumber(PrefKeys.DECODE_CONCURRENCY, 0);
  }

  /** 亮度记忆（0..100；-1 = 未设置，页面用系统亮度） */
  async brightness(): Promise<number> {
    return this.getNumber(PrefKeys.BRIGHTNESS, -1);
  }

  async setBrightness(v: number): Promise<void> {
    return this.putNumber(PrefKeys.BRIGHTNESS, v);
  }

  /** 安全锁开关（默认关；生物识别 S 级） */
  async securityLock(): Promise<boolean> {
    return this.getBool(PrefKeys.SECURITY_LOCK, false);
  }

  async setSecurityLock(v: boolean): Promise<void> {
    return this.putBool(PrefKeys.SECURITY_LOCK, v);
  }

  /** 系统隐私保护默认开启，与应用锁分开保存。 */
  async previewProtection(): Promise<boolean> {
    return this.getBool(PrefKeys.PREVIEW_PROTECTION, true);
  }

  async setPreviewProtection(v: boolean, windowName: string): Promise<void> {
    const previous: boolean = await this.previewProtection();
    const win: window.Window = window.findWindow(windowName);
    await win.setWindowPrivacyMode(v);
    try { await this.putBool(PrefKeys.PREVIEW_PROTECTION, v); }
    catch (e) {
      await win.setWindowPrivacyMode(previous);
      await this.putBool(PrefKeys.PREVIEW_PROTECTION, previous);
      throw e as Error;
    }
  }

  /** 压缩包图像质量：visual（默认）/ compact（CBZ 导出用） */
  async archiveImgQuality(): Promise<string> {
    return this.getString(PrefKeys.ARCHIVE_IMG_QUALITY, 'visual');
  }

  async setArchiveImgQuality(v: string): Promise<void> {
    return this.putString(PrefKeys.ARCHIVE_IMG_QUALITY, v);
  }

}
