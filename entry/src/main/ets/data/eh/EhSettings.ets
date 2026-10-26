/**
 * E-Hentai 图源站点设置：表站/里站切换、登录 Cookie 导入、标签汉化词库引导。
 * Cookie 属于登录凭据，走系统资产服务（见 Sources.ets saveSourceSecret）。
 */
import common from '@ohos.app.ability.common';
import webview from '@ohos.web.webview';
import util from '@ohos.util';
import { relationalStore } from '@kit.ArkData';
import { dbQuery, dbTransaction, txExecute } from '../db/AppDatabase';
import { cellString, readRows } from '../db/RowCodec';
import { saveSourceSecret, readSourceSecret, clearSourceSecret } from '../Sources';
import { NativeEhClient, EhTagTranslator, GallerySite } from './EhNative';

export class EhSettings {
  private static siteMode: string = GallerySite.E;
  private static cookieHeader: string = '';
  private static tagDatabaseLoaded: boolean = false;

  /**
   * 启动链只做快路径：恢复站点模式与登录 Cookie（幂等，可安全重复调用）。
   * 1.3MB 词库解码与全量解析延迟到首帧之后再做，避免卡启动。
   */
  static async init(context: common.Context): Promise<void> {
    const rows: relationalStore.ResultSet = await dbQuery(
      'SELECT value FROM source_setting WHERE source_id = ? AND key = ?', ['eh', 'site']);
    let savedSite: string = GallerySite.E;
    await readRows(rows, (row: relationalStore.ResultSet): void => {
      savedSite = cellString(row, 'value');
    });
    EhSettings.applyRestoredSite(savedSite);
    try {
      EhSettings.cookieHeader = await readSourceSecret('eh');
      NativeEhClient.configureCookieHeader(EhSettings.cookieHeader);
    } catch (e) {
      EhSettings.cookieHeader = '';
    }
    setTimeout((): void => {
      EhSettings.loadTagDatabase(context);
    }, 1200);
  }

  private static loadTagDatabase(context: common.Context): void {
    if (EhSettings.tagDatabaseLoaded) {
      return;
    }
    EhSettings.tagDatabaseLoaded = true;
    try {
      EhTagTranslator.configureCacheDir(context.filesDir);
      // 词库正文为 ASCII（仅文件头 2 字节二进制标记，UTF-8 解码后仍被行解析忽略），
      // 原生 TextDecoder 解码，避免逐字节拼接的启动期长任务
      const raw: Uint8Array = context.resourceManager.getRawFileContentSync('tag-translations-zh-rCN');
      EhTagTranslator.configureBundledRaw(util.TextDecoder.create('utf-8').decodeToString(raw));
    } catch (e) {
      // 词库缺失时 EhTagTranslator 使用内置兜底翻译
    }
    EhTagTranslator.update().catch((): void => {});
  }

  /** 用户选择的站点（'e' 表站 / 'ex' 里站）。 */
  static site(): string {
    return EhSettings.siteMode;
  }

  /** 里站必须带账号 Cookie（Sad Panda 防线），缺账号或缺可用 igneous 时自动回退表站。 */
  static effectiveSite(): string {
    if (EhSettings.siteMode === GallerySite.EX && !EhSettings.canUseEx()) {
      return GallerySite.E;
    }
    return EhSettings.siteMode;
  }

  /** 选了里站但因未登录/缺 igneous 回退表站（设置页提示用）。 */
  static exDowngraded(): boolean {
    return EhSettings.siteMode === GallerySite.EX && EhSettings.effectiveSite() !== EhSettings.siteMode;
  }

  static async setSite(mode: string): Promise<void> {
    const selected: string = mode === GallerySite.EX ? GallerySite.EX : GallerySite.E;
    await dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
      await txExecute(tx,
        'INSERT INTO source_setting (source_id, key, value) VALUES (?, ?, ?) ON CONFLICT(source_id, key) DO UPDATE SET value = excluded.value',
        ['eh', 'site', selected]);
    });
    EhSettings.applyRestoredSite(selected);
  }

  /** 恢复事务提交后同步内存，不产生额外持久化操作。 */
  static applyRestoredSite(mode: string): void {
    EhSettings.siteMode = mode === GallerySite.EX ? GallerySite.EX : GallerySite.E;
  }

  /** 已导入的 Cookie 头（k1=v1; k2=v2 形式，可能为空）。 */
  static cookie(): string {
    return EhSettings.cookieHeader;
  }

  /** 账号判定：手动导入的 Cookie 或 WebView 登录落盘的 Cookie 任一含 ipb_member_id 即视为有账号。 */
  static hasLogin(): boolean {
    if (/ipb_member_id=\d+/.test(EhSettings.cookieHeader)) {
      return true;
    }
    try {
      const webCookie: string = webview.WebCookieManager.fetchCookieSync('https://e-hentai.org/', false);
      return /ipb_member_id=\d+/.test(webCookie);
    } catch (e) {
      return false;
    }
  }

  /** igneous 与官方客户端同规则：空 / mystery / deleted / null / 0 视为不可用。 */
  private static usableIgneous(value: string): boolean {
    const normalized: string = value.trim().toLowerCase();
    return normalized.length > 0 && normalized !== 'mystery' && normalized !== 'deleted' &&
      normalized !== 'delete' && normalized !== 'null' && normalized !== 'undefined' &&
      normalized !== 'none' && normalized !== '0';
  }

  /** 里站解锁条件：账号（ipb_member_id）+ 可用 igneous（手动导入或 WebView 里站域均可）。 */
  static canUseEx(): boolean {
    if (!EhSettings.hasLogin()) {
      return false;
    }
    const manual: RegExpMatchArray | null = EhSettings.cookieHeader.match(/igneous=([^;\s]+)/i);
    if (manual !== null && EhSettings.usableIgneous(manual[1] ?? '')) {
      return true;
    }
    try {
      const webCookie: string = webview.WebCookieManager.fetchCookieSync('https://exhentai.org/', false);
      const fromWeb: RegExpMatchArray | null = webCookie.match(/igneous=([^;\s]+)/i);
      return fromWeb !== null && EhSettings.usableIgneous(fromWeb[1] ?? '');
    } catch (e) {
      return false;
    }
  }

  /** 完整退出：清手动 Cookie，并清掉 WebView 登录态。 */
  static async logout(): Promise<void> {
    await EhSettings.saveCookie('');
  }

  /** 应用内 WebView 只用于 EH 登录，清空时不能只删资产库而留下网页 Cookie。 */
  private static clearWebCookies(): void {
    try {
      webview.WebCookieManager.clearAllCookiesSync();
      webview.WebCookieManager.saveCookieSync();
    } catch (e) {
      // 清理失败不影响手动 Cookie 已清除的结果
    }
  }

  /** 手动导入 / 清空 Cookie；空字符串同时清 WebView，避免界面仍显示已登录。 */
  static async saveCookie(header: string): Promise<void> {
    const clean: string = header.trim();
    EhSettings.cookieHeader = clean;
    NativeEhClient.configureCookieHeader(clean);
    if (clean === '') {
      await clearSourceSecret('eh');
      EhSettings.clearWebCookies();
      return;
    }
    await saveSourceSecret('eh', clean);
  }

  /** 标签翻译词库状态（设置页展示用）。 */
  static tagTranslationLabel(): string {
    return EhTagTranslator.statusLabel();
  }
}
