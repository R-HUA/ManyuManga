/**
 * 设置读写的共享逻辑：“我的”页摘要与各设置子页共用，页面只负责状态与交互。
 */
import common from '@ohos.app.ability.common';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import { Prefs } from '../util/Prefs';
import { exportBackup, importBackup } from './Backup';
import { cleanLegacyData } from './LegacyCleanup';
import { AuthOutcome, authenticate } from '../util/AppLock';

/** 设置子页写入后递增，“我的”页据此刷新摘要。 */
export const SETTINGS_VERSION_KEY: string = 'settingsVersion';

export const THEME_MODES: Array<string> = ['system', 'light', 'dark'];
export const THEME_LABELS: Array<string> = ['跟随系统', '浅色', '深色'];
export const READER_MODES: Array<string> = ['vertical', 'pagedVertical', 'horizontal', 'rtl', 'double'];
export const READER_MODE_LABELS: Array<string> = ['纵向条漫', '纵向翻页', '左翻单页', '日漫右翻', '双页拼合'];
export const PRELOAD_COUNTS: Array<number> = [1, 3, 5, 8];
export const PRELOAD_LABELS: Array<string> = ['省流 (1 页)', '标准 (3 页)', '进取 (5 页)', '极速 (8 页)'];

export class SettingsSnapshot {
  theme: number = 0;
  reader: number = 0;
  preload: number = 3;
  archiveQuality: number = 0;
  autoCache: boolean = true;
  history: boolean = true;
  securityLock: boolean = false;
  previewOn: boolean = true;
}

export function bumpSettingsVersion(): void {
  AppStorage.setOrCreate(SETTINGS_VERSION_KEY, Date.now());
}

export function preloadIndex(count: number): number {
  const index: number = PRELOAD_COUNTS.indexOf(count);
  return index >= 0 ? index : 1;
}

export async function loadSettings(): Promise<SettingsSnapshot> {
  const prefs: Prefs = await Prefs.getInstance();
  const snapshot: SettingsSnapshot = new SettingsSnapshot();
  snapshot.theme = Math.max(0, THEME_MODES.indexOf(await prefs.themeMode()));
  snapshot.reader = Math.max(0, READER_MODES.indexOf(await prefs.readerMode()));
  snapshot.preload = await prefs.preloadPages();
  snapshot.archiveQuality = await prefs.archiveImgQuality() === 'compact' ? 1 : 0;
  snapshot.autoCache = await prefs.autoCache();
  snapshot.history = await prefs.historyEnabled();
  snapshot.securityLock = await prefs.securityLock();
  snapshot.previewOn = await prefs.previewProtection();
  return snapshot;
}

export function readerSummary(snapshot: SettingsSnapshot): string {
  return `${READER_MODE_LABELS[snapshot.reader] ?? ''} · 预加载 ${snapshot.preload} 页`;
}

export function themeSummary(snapshot: SettingsSnapshot): string {
  return THEME_LABELS[snapshot.theme] ?? '';
}

export function privacySummary(snapshot: SettingsSnapshot): string {
  return snapshot.securityLock ? '应用锁已开启' : (snapshot.previewOn ? '隐私保护已开启' : '');
}

export async function saveTheme(index: number, context: common.Context): Promise<void> {
  await (await Prefs.getInstance()).setThemeMode(THEME_MODES[index] ?? 'system');
  context.getApplicationContext().setColorMode(
    index === 2 ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : index === 1 ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
  );
  bumpSettingsVersion();
}

export async function saveReaderMode(index: number): Promise<void> {
  await (await Prefs.getInstance()).setReaderMode(READER_MODES[index] ?? READER_MODES[0]);
  bumpSettingsVersion();
}

export async function savePreload(count: number): Promise<void> {
  await (await Prefs.getInstance()).setPreloadPages(count);
  bumpSettingsVersion();
}

export async function saveArchiveQuality(index: number): Promise<void> {
  await (await Prefs.getInstance()).setArchiveImgQuality(index === 1 ? 'compact' : 'visual');
  bumpSettingsVersion();
}

export async function saveAutoCache(on: boolean): Promise<void> {
  await (await Prefs.getInstance()).setAutoCache(on);
  bumpSettingsVersion();
}

export async function saveHistory(on: boolean): Promise<void> {
  await (await Prefs.getInstance()).setHistoryEnabled(on);
  bumpSettingsVersion();
}

export async function savePreview(on: boolean, windowName: string): Promise<void> {
  await (await Prefs.getInstance()).setPreviewProtection(on, windowName);
  bumpSettingsVersion();
}

/** 生物识别确认后写入应用锁；验证失败返回提示文案，成功返回空串。 */
export async function confirmSecurityLock(enable: boolean): Promise<string> {
  const outcome: AuthOutcome = await authenticate(enable ? '验证身份以开启应用锁' : '验证身份以关闭应用锁');
  if (!outcome.ok) {
    return outcome.message === '' ? '验证未通过，应用锁未更改' : outcome.message;
  }
  await (await Prefs.getInstance()).setSecurityLock(enable);
  bumpSettingsVersion();
  return '';
}

/** 返回 true 表示用户完成了文件选择并成功执行。 */
export async function runBackup(isRestore: boolean): Promise<boolean> {
  const ok: boolean = isRestore ? await importBackup() : await exportBackup();
  if (ok && isRestore) {
    bumpSettingsVersion();
  }
  return ok;
}

export async function cleanLegacy(): Promise<void> {
  await cleanLegacyData();
}
