import { Prefs, PrefKeys, getAppContext } from '../util/Prefs';
import { rmTree } from '../util/FileUtil';
import { relationalStore } from '@kit.ArkData';

/** 这些键曾经整包保存业务 JSON。新版本不再读取它们。 */
const LEGACY_PREF_KEYS: Array<string> = [
  'library_v1',
  'offline_v1',
  'reader_options_v1',
  'bookmarks_v1',
  'activity_v1',
  'local_books_v1',
  'sources_v1',
  'eh_seeded_v1',
  'eh_site_mode',
  'store_home_cache',
  PrefKeys.FAV_ITEMS,
  PrefKeys.FAV_TAGS,
  PrefKeys.HISTORY_ITEMS,
  PrefKeys.READ_PROGRESS,
  PrefKeys.SEARCH_HISTORY,
  PrefKeys.BLOCK_TAGS,
  PrefKeys.CUSTOM_CATS,
  PrefKeys.DOWNLOAD_TASKS
];

/**
 * 只删除已确认的应用沙箱旧数据。
 * 不删除 filesDir/Download、filesDir/local、filesDir/content、filesDir/page_cache，
 * 也不碰系统公共 Download 目录。
 */
export async function cleanLegacyData(): Promise<void> {
  const prefs: Prefs = await Prefs.getInstance();
  for (const key of LEGACY_PREF_KEYS) {
    await prefs.remove(key);
  }
  await relationalStore.deleteRdbStore(getAppContext(), {
    name: 'manyu_business.db', securityLevel: relationalStore.SecurityLevel.S2
  });
  rmTree(`${getAppContext().filesDir}/offline`);
}
