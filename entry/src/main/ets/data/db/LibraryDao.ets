import { relationalStore } from '@kit.ArkData';
import { Album } from '../../models/Models';
import { LibraryWork } from '../Library';
import { normalizedTitle } from '../Matching';
import { dbQuery, dbTransaction, txExecute, txQuery } from './AppDatabase';
import {
  AlbumTagRow, albumFromJson, albumToJson, appendPage, cellLong, cellString, readRows, sourcePrefix,
  syncAlbumRelations, txPosition, txUpsert, escapeLike
} from './RowCodec';

export function loadLibrary(): Promise<Array<LibraryWork>> { return loadLibraryPage(0, 0); }

export async function loadLibraryPage(offset: number, limit: number): Promise<Array<LibraryWork>> {
  const args: Array<relationalStore.ValueType> = [];
  const sql: string = appendPage('SELECT * FROM library_work ORDER BY position ASC, id ASC', args, limit, offset);
  return loadWorks(sql, args);
}

export async function loadLibraryWorkForAlbum(albumId: string): Promise<LibraryWork | null> {
  const items: Array<LibraryWork> = await loadWorks(
    'SELECT w.* FROM library_work w JOIN library_album a ON a.work_id = w.id WHERE a.album_id = ?', [albumId]);
  return items.length > 0 ? items[0] : null;
}

/**
 * 找出与 album 可能是同一作品的书架作品。
 * 之前用 json_extract 加三十多层嵌套 REPLACE 在 SQL 里归一化标题，替换表里含有 '?'、'？' 和制表、换行等控制字符，
 * RDB 绑定参数时会把字面量里的 '?' 误算成占位符，或因 JSON1 不可用而报 SQLITE_ERROR（Generic error），导致收藏失败。
 * 现在只读出 work_id 和 payload，在 TS 里用 normalizedTitle 做同样的归一化比较。
 */
export async function loadLibraryCandidates(album: Album): Promise<Array<LibraryWork>> {
  const target: string = normalizedTitle(album.name);
  const url: string = album.originalUrl;
  const ids: Array<string> = [];
  await readRows(await dbQuery('SELECT work_id, payload FROM library_album', []),
    (row: relationalStore.ResultSet): void => {
      const workId: string = cellString(row, 'work_id');
      if (ids.indexOf(workId) >= 0) { return; }
      const stored: Album = albumFromJson(cellString(row, 'payload'));
      if ((target !== '' && normalizedTitle(stored.name) === target) || (url !== '' && stored.originalUrl === url)) {
        ids.push(workId);
      }
    });
  if (ids.length === 0) { return []; }
  const marks: Array<string> = [];
  const args: Array<relationalStore.ValueType> = [];
  for (const id of ids) { marks.push('?'); args.push(id); }
  return loadWorks(`SELECT * FROM library_work WHERE id IN (${marks.join(', ')}) ORDER BY position ASC, id ASC`, args);
}

async function loadWorks(sql: string, args: Array<relationalStore.ValueType>): Promise<Array<LibraryWork>> {
  const works: Array<LibraryWork> = [];
  await readRows(await dbQuery(sql, args), (row: relationalStore.ResultSet): void => { works.push(workFrom(row)); });
  for (const work of works) {
    await readRows(await dbQuery(
      'SELECT payload FROM library_album WHERE work_id = ? ORDER BY position ASC, album_id ASC', [work.id]),
      (row: relationalStore.ResultSet): void => { work.albums.push(albumFromJson(cellString(row, 'payload'))); });
    work.categories = await loadNames('SELECT name FROM library_category WHERE work_id = ? ORDER BY name ASC',
      [work.id], 'name');
    work.chapterSnapshot = await loadNames(
      'SELECT chapter_id FROM library_snapshot WHERE work_id = ? ORDER BY position ASC, chapter_id ASC', [work.id], 'chapter_id');
  }
  return works;
}

function workFrom(row: relationalStore.ResultSet): LibraryWork {
  const work: LibraryWork = new LibraryWork();
  work.id = cellString(row, 'id');
  work.title = cellString(row, 'title');
  work.author = cellString(row, 'author');
  work.cover = cellString(row, 'cover');
  work.activeKey = cellString(row, 'active_key');
  work.read = cellLong(row, 'read') === 1;
  work.addedAt = cellLong(row, 'added_at');
  work.baselineSet = cellLong(row, 'baseline_set') === 1;
  work.newChapters = cellLong(row, 'new_chapters');
  return work;
}

async function loadNames(sql: string, args: Array<relationalStore.ValueType>, column: string): Promise<Array<string>> {
  const names: Array<string> = [];
  await readRows(await dbQuery(sql, args), (row: relationalStore.ResultSet): void => { names.push(cellString(row, column)); });
  return names;
}

class StoredAlbum {
  id: string = '';
  payload: string = '';
  position: number = 0;
}

/** 调用方只提交受影响作品；关联转移和删除位于同一事务。 */
export function changeLibraryWorks(items: Array<LibraryWork>, removed: Array<string> = []): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    const previous: Map<string, Array<StoredAlbum>> = new Map<string, Array<StoredAlbum>>();
    const orphanCandidates: Set<string> = new Set<string>();
    for (const id of removed) {
      const albums: Array<StoredAlbum> = await storedAlbums(tx, id);
      for (const album of albums) { orphanCandidates.add(album.id); }
      await txExecute(tx, 'DELETE FROM library_snapshot WHERE work_id = ?', [id]);
      await txExecute(tx, 'DELETE FROM library_category WHERE work_id = ?', [id]);
      await txExecute(tx, 'DELETE FROM library_album WHERE work_id = ?', [id]);
      await txExecute(tx, 'DELETE FROM library_work WHERE id = ?', [id]);
    }
    for (const work of items) {
      const albums: Array<StoredAlbum> = await storedAlbums(tx, work.id);
      previous.set(work.id, albums);
      for (const old of albums) {
        if (!work.albums.some((album: Album): boolean => album.id === old.id)) {
          await txExecute(tx, 'DELETE FROM library_album WHERE album_id = ? AND work_id = ?', [old.id, work.id]);
          orphanCandidates.add(old.id);
        }
      }
    }
    for (const work of items) {
      let position: number = 0;
      let existing: boolean = false;
      await readRows(await txQuery(tx, 'SELECT position FROM library_work WHERE id = ?', [work.id]),
        (row: relationalStore.ResultSet): void => { existing = true; position = cellLong(row, 'position'); });
      if (!existing) { position = await txPosition(tx, 'library_work', true); }
      await txUpsert(tx, 'library_work', ['id'],
        ['id', 'title', 'author', 'cover', 'active_key', 'read', 'added_at', 'baseline_set', 'new_chapters', 'position', 'updated_at'],
        [work.id, work.title, work.author, work.cover, work.activeKey, work.read ? 1 : 0, work.addedAt,
          work.baselineSet ? 1 : 0, work.newChapters, position, Date.now()]);
      const oldAlbums: Array<StoredAlbum> = previous.get(work.id) ?? [];
      for (let index: number = 0; index < work.albums.length; index++) {
        const album: Album = work.albums[index];
        const payload: string = albumToJson(album);
        const old: StoredAlbum | undefined = oldAlbums.find((item: StoredAlbum): boolean => item.id === album.id);
        if (old === undefined || old.payload !== payload || old.position !== index) {
          await txUpsert(tx, 'library_album', ['album_id'],
            ['album_id', 'work_id', 'source_id', 'position', 'payload', 'updated_at'],
            [album.id, work.id, sourcePrefix(album.id), index, payload, Date.now()]);
          await syncAlbumRelations(tx, album);
        }
      }
      await syncCategories(tx, work.id, work.categories);
      await syncSnapshot(tx, work.id, work.chapterSnapshot);
    }
    for (const albumId of orphanCandidates) {
      await txExecute(tx, 'DELETE FROM album_chapter WHERE album_id = ? AND NOT EXISTS ' +
        '(SELECT 1 FROM library_album WHERE album_id = ?) AND NOT EXISTS ' +
        '(SELECT 1 FROM local_book WHERE book_id = ?) AND NOT EXISTS ' +
        '(SELECT 1 FROM offline_book WHERE album_id = ?)', [albumId, albumId, albumId, albumId]);
      await txExecute(tx, 'DELETE FROM album_tag WHERE album_id = ? AND NOT EXISTS ' +
        '(SELECT 1 FROM library_album WHERE album_id = ?) AND NOT EXISTS ' +
        '(SELECT 1 FROM local_book WHERE book_id = ?) AND NOT EXISTS ' +
        '(SELECT 1 FROM offline_book WHERE album_id = ?)', [albumId, albumId, albumId, albumId]);
    }
  });
}

async function storedAlbums(tx: relationalStore.Transaction, workId: string): Promise<Array<StoredAlbum>> {
  const items: Array<StoredAlbum> = [];
  await readRows(await txQuery(tx, 'SELECT album_id, payload, position FROM library_album WHERE work_id = ?', [workId]),
    (row: relationalStore.ResultSet): void => {
      const item: StoredAlbum = new StoredAlbum();
      item.id = cellString(row, 'album_id');
      item.payload = cellString(row, 'payload');
      item.position = cellLong(row, 'position');
      items.push(item);
    });
  return items;
}

async function syncCategories(tx: relationalStore.Transaction, workId: string, names: Array<string>): Promise<void> {
  const old: Set<string> = new Set<string>();
  await readRows(await txQuery(tx, 'SELECT name FROM library_category WHERE work_id = ?', [workId]),
    (row: relationalStore.ResultSet): void => { old.add(cellString(row, 'name')); });
  for (const name of new Set<string>(names)) {
    if (!old.has(name)) {
      await txExecute(tx, 'INSERT INTO library_category (work_id, name, updated_at) VALUES (?, ?, ?)', [workId, name, Date.now()]);
    }
    old.delete(name);
  }
  for (const name of old) { await txExecute(tx, 'DELETE FROM library_category WHERE work_id = ? AND name = ?', [workId, name]); }
}

async function syncSnapshot(tx: relationalStore.Transaction, workId: string, chapters: Array<string>): Promise<void> {
  const old: Map<string, number> = new Map<string, number>();
  await readRows(await txQuery(tx, 'SELECT chapter_id, position FROM library_snapshot WHERE work_id = ?', [workId]),
    (row: relationalStore.ResultSet): void => { old.set(cellString(row, 'chapter_id'), cellLong(row, 'position')); });
  for (let index: number = 0; index < chapters.length; index++) {
    const id: string = chapters[index];
    if (old.get(id) !== index) {
      await txUpsert(tx, 'library_snapshot', ['work_id', 'chapter_id'], ['work_id', 'chapter_id', 'position'], [workId, id, index]);
    }
    old.delete(id);
  }
  for (const id of old.keys()) {
    await txExecute(tx, 'DELETE FROM library_snapshot WHERE work_id = ? AND chapter_id = ?', [workId, id]);
  }
}

export function categorizeLibraryWorks(ids: Array<string>, category: string): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    for (const id of ids) {
      const exists: Array<string> = [];
      await readRows(await txQuery(tx, 'SELECT id FROM library_work WHERE id = ?', [id]),
        (row: relationalStore.ResultSet): void => { exists.push(cellString(row, 'id')); });
      if (exists.length === 0) { continue; }
      await syncCategories(tx, id, category === '' ? [] : [category]);
      await txExecute(tx, 'UPDATE library_work SET updated_at = ? WHERE id = ?', [Date.now(), id]);
    }
  });
}

export function markLibraryWorksRead(ids: Array<string>, read: boolean): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    for (const id of ids) {
      await txExecute(tx, 'UPDATE library_work SET read = ?, updated_at = ? WHERE id = ?', [read ? 1 : 0, Date.now(), id]);
    }
  });
}

export function activateLibraryAlbum(key: string): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx, 'UPDATE library_work SET active_key = ?, new_chapters = ?, updated_at = ? WHERE id = ' +
      '(SELECT work_id FROM library_album WHERE album_id = ?)', [key, 0, Date.now(), key]);
  });
}

export async function searchAlbumTags(needle: string, onlySource: string, limit: number): Promise<Array<AlbumTagRow>> {
  const pattern: string = '%' + escapeLike(needle.toLowerCase()) + '%';
  const args: Array<relationalStore.ValueType> = [pattern, pattern];
  let sql: string = "SELECT MIN(album_id) AS album_id, namespace, value, MIN(label) AS label, MIN(position) AS position FROM album_tag " +
    "WHERE (LOWER(namespace || ':' || value) LIKE ? ESCAPE '\\' OR LOWER(label) LIKE ? ESCAPE '\\')";
  if (onlySource !== '') {
    sql += " AND album_id LIKE ? ESCAPE '\\'";
    args.push(escapeLike(onlySource) + '~%');
  }
  sql += " GROUP BY SUBSTR(album_id, 1, INSTR(album_id, '~') - 1), namespace, value" +
    ' ORDER BY album_id ASC, position ASC, namespace ASC, value ASC LIMIT ?';
  args.push(Math.max(1, Math.floor(limit)));
  const items: Array<AlbumTagRow> = [];
  await readRows(await dbQuery(sql, args), (row: relationalStore.ResultSet): void => {
    const tag: AlbumTagRow = new AlbumTagRow();
    tag.albumId = cellString(row, 'album_id');
    tag.namespace = cellString(row, 'namespace');
    tag.value = cellString(row, 'value');
    tag.label = cellString(row, 'label');
    tag.position = cellLong(row, 'position');
    items.push(tag);
  });
  return items;
}

