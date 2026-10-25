import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { Prefs, PrefKeys, getAppContext } from '../util/Prefs';
import { utf8Decode } from './JmApi';
import { sourceStore } from './Sources';
import { library } from './Library';
import { ActivityStats } from './ReadingActivity';
import { asRecord } from '../models/Models';

class BackupDocument {
  format: string = 'manyu';
  version: number = 1;
  createdAt: number = Date.now();
  values: Record<string, string> = {};
}
const KEYS: Array<string> = ['library_v1', 'sources_v1', PrefKeys.READ_PROGRESS, PrefKeys.HISTORY_ITEMS,
  'reader_options_v1', 'bookmarks_v1', 'activity_v1', PrefKeys.API_DOMAINS, PrefKeys.LAST_DOMAIN, PrefKeys.IMAGE_HOST];

/** 备份只接受漫屿自身格式，文件与系统凭据由各自的生命周期管理。 */
export async function exportBackup(): Promise<boolean> {
  const document: BackupDocument = new BackupDocument();
  const prefs: Prefs = await Prefs.getInstance();
  for (const key of KEYS) {
    const fallback: string = key === 'reader_options_v1' ? '{}' : key === 'activity_v1' ? JSON.stringify(new ActivityStats())
      : ['library_v1', 'sources_v1', PrefKeys.READ_PROGRESS, PrefKeys.HISTORY_ITEMS, 'bookmarks_v1'].includes(key) ? '[]' : '';
    document.values[key] = await prefs.getString(key, fallback);
  }
  document.values['sources_v1'] = JSON.stringify(await sourceStore.list());
  document.values['library_v1'] = JSON.stringify(await library.list());
  const dialog: picker.DocumentViewPicker = new picker.DocumentViewPicker(getAppContext());
  const uris: Array<string> = await dialog.save({ newFileNames: [`漫屿备份_${new Date().toISOString().substring(0, 10)}.json`] });
  if (uris.length === 0) { return false; }
  const file: fs.File = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try { fs.writeSync(file.fd, JSON.stringify(document)); }
  finally { fs.closeSync(file); }
  return true;
}
export async function importBackup(): Promise<boolean> {
  const dialog: picker.DocumentViewPicker = new picker.DocumentViewPicker(getAppContext());
  const uris: Array<string> = await dialog.select({ maxSelectNumber: 1, fileSuffixFilters: ['备份文件|.json'] });
  if (uris.length === 0) { return false; }
  const file: fs.File = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
  let text: string;
  try {
    const data: ArrayBuffer = new ArrayBuffer(fs.statSync(file.fd).size);
    if (fs.readSync(file.fd, data) !== data.byteLength) { throw new Error('备份文件读取不完整'); }
    text = utf8Decode(new Uint8Array(data));
  } finally { fs.closeSync(file); }
  const document: Record<string, Object> | null = asRecord(JSON.parse(text) as Object);
  const content: Record<string, Object> | null = document === null ? null : asRecord(document['values']);
  if (document === null || document['format'] !== 'manyu' || document['version'] !== 1 || content === null) { throw new Error('请选择有效的漫屿备份文件'); }
  const values: Record<string, string> = {};
  for (const key of KEYS) {
    const raw: Object | undefined = content[key];
    if (typeof raw !== 'string') { throw new Error('备份数据不完整'); }
    const value: string = raw;
    if (value !== '' && ['library_v1', 'sources_v1', PrefKeys.READ_PROGRESS, PrefKeys.HISTORY_ITEMS].includes(key)) {
      if (!(JSON.parse(value) instanceof Array)) { throw new Error('备份列表格式无效'); }
    }
    values[key] = value;
  }
  await (await Prefs.getInstance()).putStrings(values);
  return true;
}
