import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { relationalStore } from '@kit.ArkData';
import { getAppContext } from '../util/Prefs';
import { utf8Decode, utf8Encode } from './JmApi';
import { sourceStore } from './Sources';
import { EhSettings } from './eh/EhSettings';
import { library } from './Library';
import { historyStore, readProgressStore } from './stores/ReadingStores';
import { favStore } from './stores/FavoriteStore';
import { searchHistoryStore, blockTagsStore, customCatStore } from './stores/FilterStores';
import { localSource } from './LocalSource';
import { downloadManager } from './DownloadManager';
import { asArray, asNumber, asRecord, asString } from '../models/Models';
import { dbTransaction, withDatabaseMaintenance, txExecute, txQuery } from './db/AppDatabase';
import { albumFromJson, cellLong, cellString, readRows } from './db/RowCodec';
import { TABLE_DELETE_ORDER } from './db/Schema';
import { isRegisteredSourceKind } from './source/SourceRegistry';

export const BACKUP_MAGIC: string = 'manyu-backup';
export const BACKUP_VERSION: number = 3;

class FieldSpec {
  name: string = '';
  numeric: boolean = false;
  constructor(name: string, numeric: boolean) {
    this.name = name;
    this.numeric = numeric;
  }
}

function textFields(names: Array<string>): Array<FieldSpec> {
  return names.map((name: string): FieldSpec => new FieldSpec(name, false));
}
function num(name: string): FieldSpec {
  return new FieldSpec(name, true);
}

const FIELDS: Record<string, Array<FieldSpec>> = {
  'library_work': textFields(['id', 'title', 'author', 'cover', 'active_key']).concat([
    num('read'), num('added_at'), num('baseline_set'), num('new_chapters'), num('position'), num('updated_at')]),
  'library_album': textFields(['album_id', 'work_id', 'source_id', 'payload']).concat([num('position'), num('updated_at')]),
  'library_category': textFields(['work_id', 'name']).concat([num('updated_at')]),
  'library_snapshot': textFields(['work_id', 'chapter_id']).concat([num('position')]),
  'album_chapter': textFields(['album_id', 'chapter_id', 'title', 'sort']).concat([num('position')]),
  'album_tag': textFields(['album_id', 'namespace', 'value']).concat([num('position')]),
  'source_instance': textFields(['id', 'endpoint', 'auth', 'name']),
  'source_entry': textFields(['id', 'instance_id', 'name', 'kind', 'endpoint', 'remote_id', 'language', 'auth']).concat([
    num('enabled'), num('latency'), num('position')]),
  'source_setting': textFields(['source_id', 'key', 'value']),
  'favorite': textFields(['id', 'title', 'author', 'cover_url', 'source_id']).concat([num('added_at'), num('position')]),
  'favorite_tag': textFields(['tag']).concat([num('position'), num('updated_at')]),
  'history': textFields(['id', 'title', 'author', 'cover_url', 'source_id']).concat([num('viewed_at'), num('position')]),
  'reading_progress': textFields(['aid', 'chapter_id', 'title', 'author', 'cover_url', 'source_id']).concat([
    num('chapter_index'), num('page'), num('total_pages'), num('at')]),
  'bookmark': textFields(['aid', 'chapter_id', 'title', 'author', 'cover_url']).concat([
    num('page'), num('chapter_index'), num('total_pages'), num('at')]),
  'reader_pref': textFields(['work_key', 'mode', 'taps']).concat([
    num('cover_offset'), num('crop_white'), num('eye_comfort'), num('preload'), num('paper'), num('updated_at')]),
  'activity_stat': [num('id'), num('milliseconds'), num('updated_at')],
  'activity_page': textFields(['page_key']).concat([num('recorded_at')]),
  'activity_book': textFields(['book_key']).concat([num('recorded_at')]),
  'search_history': textFields(['query']).concat([num('recorded_at'), num('position')]),
  'block_rule': [num('id'), new FieldSpec('kind', false), new FieldSpec('value', false), num('enabled'),
    new FieldSpec('source_id', false), num('updated_at')],
  'custom_category': textFields(['name']).concat([num('position'), num('updated_at')]),
  'download_task': [num('id'), new FieldSpec('album_id', false), new FieldSpec('title', false), new FieldSpec('state', false),
    num('done'), num('total'), num('failed_pages'), new FieldSpec('saved_to', false), new FieldSpec('cover', false),
    num('created_at'), new FieldSpec('error', false), num('exporting'), num('export_done'), num('export_total'), num('updated_at')],
  'offline_book': textFields(['album_id', 'source_id', 'directory', 'payload']).concat([num('updated_at')]),
  'offline_page': textFields(['album_id', 'chapter_id', 'relative_path', 'filename']).concat([
    num('page_order'), num('file_size'), num('complete'), num('scramble_id')]),
  'download_page': textFields(['album_id', 'chapter_id', 'relative_path', 'filename']).concat([
    num('task_id'), num('page_order'), num('file_size'), num('complete'), num('scramble_id')]),
  'export_record': [num('id'), new FieldSpec('album_id', false), num('task_id'), new FieldSpec('location', false), num('created_at')],
  'local_book': textFields(['book_id', 'payload', 'files_json']).concat([num('updated_at')])
};

class BackupDocument {
  magic: string = BACKUP_MAGIC;
  version: number = BACKUP_VERSION;
  createdAt: number = 0;
  tables: Record<string, Array<Record<string, Object>>> = {};
}

/** 备份业务库和非敏感书源配置。不含凭据和漫画文件。不读取旧版 JSON 备份。 */
export async function exportBackup(): Promise<boolean> {
  const document: BackupDocument = new BackupDocument();
  document.createdAt = Date.now();
  await sourceStore.list();
  await dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    for (const table of TABLE_DELETE_ORDER) {
      document.tables[table] = await dumpTable(tx, table);
    }
  });
  const dialog: picker.DocumentViewPicker = new picker.DocumentViewPicker(getAppContext());
  const uris: Array<string> = await dialog.save({ newFileNames: [`漫屿备份_${new Date().toISOString().substring(0, 10)}.json`] });
  if (uris.length === 0) {
    return false;
  }
  const file: fs.File = await fs.open(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    const bytes: Uint8Array = utf8Encode(JSON.stringify(document));
    let offset: number = 0;
    while (offset < bytes.byteLength) {
      const count: number = await fs.write(file.fd, bytes.buffer.slice(offset));
      if (count <= 0) {
        throw new Error('备份文件写入不完整');
      }
      offset += count;
    }
  } finally {
    await fs.close(file);
  }
  return true;
}

export async function importBackup(): Promise<boolean> {
  const dialog: picker.DocumentViewPicker = new picker.DocumentViewPicker(getAppContext());
  const uris: Array<string> = await dialog.select({ maxSelectNumber: 1, fileSuffixFilters: ['备份文件|.json'] });
  if (uris.length === 0) {
    return false;
  }
  const document: BackupDocument = parseBackup(await readBackupText(uris[0]));
  await downloadManager.withSuspendedWrites(async (): Promise<void> => {
    await withDatabaseMaintenance(async (tx: relationalStore.Transaction): Promise<void> => {
      for (const table of TABLE_DELETE_ORDER) {
        await txExecute(tx, `DELETE FROM ${table}`, []);
      }
      for (let index: number = TABLE_DELETE_ORDER.length - 1; index >= 0; index--) {
        const table: string = TABLE_DELETE_ORDER[index];
        const rows: Array<Record<string, Object>> = document.tables[table];
        const spec: Array<FieldSpec> = FIELDS[table];
        for (const row of rows) {
          const names: Array<string> = [];
          const marks: Array<string> = [];
          const args: Array<relationalStore.ValueType> = [];
          for (const field of spec) {
            names.push(field.name);
            marks.push('?');
            const value: Object = row[field.name];
            args.push(field.numeric ? asNumber(value, 0) : asString(value));
          }
          await txExecute(tx, `INSERT INTO ${table} (${names.join(', ')}) VALUES (${marks.join(', ')})`, args);
        }
      }
    }, (): void => invalidateRestoredData(document));
    await sourceStore.list();
    await downloadManager.reloadTasks();
  });
  return true;
}

function invalidateRestoredData(document: BackupDocument): void {
  library.invalidate();
  historyStore.invalidate();
  readProgressStore.invalidate();
  favStore.invalidate();
  searchHistoryStore.invalidate();
  blockTagsStore.invalidate();
  customCatStore.invalidate();
  localSource.invalidate();
  sourceStore.invalidate();
  let site: string = 'e';
  for (const row of document.tables['source_setting']) {
    if (asString(row['source_id']) === 'eh' && asString(row['key']) === 'site') {
      site = asString(row['value']);
    }
  }
  EhSettings.applyRestoredSite(site);
  AppStorage.setOrCreate('libraryVersion', Date.now());
  AppStorage.setOrCreate('sourceVersion', Date.now());
}

async function dumpTable(tx: relationalStore.Transaction, table: string): Promise<Array<Record<string, Object>>> {
  const spec: Array<FieldSpec> = FIELDS[table];
  const rows: Array<Record<string, Object>> = [];
  const result: relationalStore.ResultSet = await txQuery(tx, `SELECT * FROM ${table}`, []);
  await readRows(result, (row: relationalStore.ResultSet): void => {
    const record: Record<string, Object> = {};
    for (const field of spec) {
      record[field.name] = field.numeric ? cellLong(row, field.name) : cellString(row, field.name);
    }
    rows.push(record);
  });
  return rows;
}

async function readBackupText(uri: string): Promise<string> {
  const file: fs.File = await fs.open(uri, fs.OpenMode.READ_ONLY);
  try {
    const size: number = (await fs.stat(file.fd)).size;
    const data: Uint8Array = new Uint8Array(size);
    let offset: number = 0;
    while (offset < size) {
      const chunk: ArrayBuffer = new ArrayBuffer(Math.min(262144, size - offset));
      const count: number = await fs.read(file.fd, chunk);
      if (count <= 0) {
        throw new Error('备份文件读取不完整');
      }
      data.set(new Uint8Array(chunk, 0, count), offset);
      offset += count;
    }
    return utf8Decode(data);
  } finally {
    await fs.close(file);
  }
}

function parseBackup(text: string): BackupDocument {
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(text) as Object;
  } catch (e) {
    throw new Error('请选择有效的漫屿备份文件');
  }
  const root: Record<string, Object> | null = asRecord(parsed);
  if (root === null || asString(root['magic']) !== BACKUP_MAGIC || asNumber(root['version'], -1) !== BACKUP_VERSION) {
    throw new Error('请选择有效的漫屿备份文件');
  }
  const tables: Record<string, Object> | null = asRecord(root['tables']);
  if (tables === null) {
    throw new Error('备份数据不完整');
  }
  const document: BackupDocument = new BackupDocument();
  document.createdAt = asNumber(root['createdAt'], 0);
  for (const table of TABLE_DELETE_ORDER) {
    const rows: Array<Object> | null = asArray(tables[table]);
    if (rows === null || FIELDS[table] === undefined) {
      throw new Error('备份数据不完整');
    }
    const parsedRows: Array<Record<string, Object>> = [];
    for (const item of rows) {
      parsedRows.push(rowFrom(item, FIELDS[table]));
    }
    document.tables[table] = parsedRows;
  }
  const tableNames: Array<string> = Object.keys(tables);
  for (const name of tableNames) {
    if (TABLE_DELETE_ORDER.indexOf(name) < 0) {
      throw new Error('请选择有效的漫屿备份文件');
    }
  }
  validateSources(document);
  validateContentPaths(document);
  for (const table of ['library_album', 'offline_book', 'local_book']) {
    for (const row of document.tables[table]) {
      const expected: string = asString(row[table === 'local_book' ? 'book_id' : 'album_id']);
      if (albumFromJson(asString(row['payload'])).id !== expected || expected.indexOf('~') < 1) {
        throw new Error('备份中的作品信息无效');
      }
    }
  }
  return document;
}

function rowFrom(item: Object, spec: Array<FieldSpec>): Record<string, Object> {
  const rec: Record<string, Object> | null = asRecord(item);
  if (rec === null) {
    throw new Error('备份数据不完整');
  }
  const keys: Array<string> = Object.keys(rec);
  if (keys.length !== spec.length) {
    throw new Error('备份数据不完整');
  }
  const row: Record<string, Object> = {};
  for (const field of spec) {
    if (keys.indexOf(field.name) < 0) {
      throw new Error('备份数据不完整');
    }
    const value: Object = rec[field.name];
    if (field.numeric) {
      if (typeof value !== 'number' || !Number.isFinite(value)) {
        throw new Error('备份数据不完整');
      }
      row[field.name] = value;
    } else if (typeof value !== 'string') {
      throw new Error('备份数据不完整');
    } else {
      row[field.name] = value;
    }
  }
  return row;
}

function validateSources(document: BackupDocument): void {
  const instances: Array<Record<string, Object>> = document.tables['source_instance'];
  if (instances.length > 1) {
    throw new Error('备份中包含多个 Suwayomi 服务，请选择当前版本的备份');
  }
  for (const row of document.tables['source_entry']) {
    const id: string = asString(row['id']);
    const kind: string = asString(row['kind']);
    const auth: string = asString(row['auth']);
    if (id === '' || id.indexOf('~') >= 0 || !isRegisteredSourceKind(kind) ||
      (auth !== 'none' && auth !== 'basic' && auth !== 'login')) {
      throw new Error('备份中的书源配置无效');
    }
    if (kind === 'suwayomi' && asNumber(row['enabled']) === 1 &&
      !instances.some((item: Record<string, Object>): boolean =>
        asString(item['id']) === asString(row['instance_id']))) {
      throw new Error('备份中的 Suwayomi 服务配置不完整');
    }
  }
  for (const row of document.tables['source_setting']) {
    if (asString(row['source_id']) === 'eh' && asString(row['key']) === 'site' &&
      asString(row['value']) !== 'e' && asString(row['value']) !== 'ex') {
      throw new Error('备份中的站点设置无效');
    }
  }
}

/** 文件索引来自外部备份，只允许指向应用管理的相对路径。 */
function validateContentPaths(document: BackupDocument): void {
  for (const table of ['offline_page', 'download_page']) {
    for (const row of document.tables[table]) {
      assertPrivateRelative(asString(row['relative_path']));
    }
  }
  for (const row of document.tables['offline_book']) {
    const directory: string = asString(row['directory']);
    assertPrivateRelative(directory);
    if (!directory.startsWith('content/')) {
      throw new Error('备份中的离线目录无效');
    }
  }
}

function assertPrivateRelative(path: string): void {
  const parts: Array<string> = path.split('/');
  if (path === '' || path.indexOf('\\') >= 0 || path.indexOf(':') >= 0 ||
    parts.some((part: string): boolean => part === '' || part === '.' || part === '..') ||
    ['content', 'page_cache', 'resume'].indexOf(parts[0]) < 0) {
    throw new Error('备份中的文件路径无效');
  }
}
