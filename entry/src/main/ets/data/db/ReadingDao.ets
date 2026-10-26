import { relationalStore } from '@kit.ArkData';
import { HistoryItem, ReadingProgress, asArray, asNumber } from '../../models/Models';
import { dbQuery, dbTransaction, txExecute, txQuery } from './AppDatabase';
import { appendPage, cellLong, cellString, readRows, sourcePrefix, txExists, txUpsert } from './RowCodec';

export class ReaderPrefRow {
  mode: string = 'vertical';
  coverOffset: number = 1;
  cropWhite: number = 0;
  eyeComfort: number = 0;
  preload: number = 3;
  paper: number = 0;
  taps: string = '';
}

export class ActivityRow {
  milliseconds: number = 0;
  pages: Array<string> = [];
  books: Array<string> = [];
}

export function loadHistory(): Promise<Array<HistoryItem>> { return loadHistoryPage(0, 0); }

export async function loadHistoryPage(offset: number, limit: number): Promise<Array<HistoryItem>> {
  const args: Array<relationalStore.ValueType> = [];
  const sql: string = appendPage('SELECT * FROM history ORDER BY viewed_at DESC, id ASC', args, limit, offset);
  const items: Array<HistoryItem> = [];
  await readRows(await dbQuery(sql, args), (row: relationalStore.ResultSet): void => {
    items.push(new HistoryItem(cellString(row, 'id'), cellString(row, 'title'), cellString(row, 'author'),
      cellString(row, 'cover_url'), cellLong(row, 'viewed_at')));
  });
  return items;
}

export function recordHistory(item: HistoryItem): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txUpsert(tx, 'history', ['id'],
      ['id', 'title', 'author', 'cover_url', 'source_id', 'viewed_at', 'position'],
      [item.id, item.title, item.author, item.coverUrl, sourcePrefix(item.id), item.viewedAt, -item.viewedAt]);
    await txExecute(tx, 'DELETE FROM history WHERE id IN ' +
      '(SELECT id FROM history ORDER BY viewed_at DESC, id ASC LIMIT -1 OFFSET ?)', [300]);
  });
}

export function removeHistory(ids: Array<string>): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    for (const id of ids) { await txExecute(tx, 'DELETE FROM history WHERE id = ?', [id]); }
  });
}

export function clearHistory(): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => { await txExecute(tx, 'DELETE FROM history', []); });
}

export function importHistory(items: Array<HistoryItem>): Promise<number> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<number> => {
    let added: number = 0;
    for (const item of items) {
      let previous: number = -1;
      await readRows(await txQuery(tx, 'SELECT viewed_at FROM history WHERE id = ?', [item.id]),
        (row: relationalStore.ResultSet): void => { previous = cellLong(row, 'viewed_at'); });
      if (previous >= item.viewedAt) { continue; }
      if (previous < 0) { added++; }
      await txUpsert(tx, 'history', ['id'],
        ['id', 'title', 'author', 'cover_url', 'source_id', 'viewed_at', 'position'],
        [item.id, item.title, item.author, item.coverUrl, sourcePrefix(item.id), item.viewedAt, -item.viewedAt]);
    }
    return added;
  });
}

export function loadProgress(): Promise<Array<ReadingProgress>> { return loadProgressPage(0, 0); }

export async function loadProgressPage(offset: number, limit: number): Promise<Array<ReadingProgress>> {
  const args: Array<relationalStore.ValueType> = [];
  const sql: string = appendPage('SELECT * FROM reading_progress ORDER BY at DESC, aid ASC', args, limit, offset);
  return readProgressRows(await dbQuery(sql, args));
}

export async function loadProgressFor(aid: string): Promise<ReadingProgress | null> {
  const items: Array<ReadingProgress> = await readProgressRows(
    await dbQuery('SELECT * FROM reading_progress WHERE aid = ?', [aid]));
  return items.length > 0 ? items[0] : null;
}

export function putProgress(item: ReadingProgress): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txUpsert(tx, 'reading_progress', ['aid'],
      ['aid', 'chapter_id', 'chapter_index', 'page', 'total_pages', 'at', 'title', 'author', 'cover_url', 'source_id'],
      [item.aid, item.chapterId, item.chapterIndex, item.page, item.totalPages, item.at, item.title, item.author,
        item.coverUrl, sourcePrefix(item.aid)]);
    await txExecute(tx, 'DELETE FROM reading_progress WHERE aid IN ' +
      '(SELECT aid FROM reading_progress ORDER BY at DESC, aid ASC LIMIT -1 OFFSET ?)', [200]);
  });
}

export function removeProgress(aid: string): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx, 'DELETE FROM reading_progress WHERE aid = ?', [aid]);
  });
}

export function clearProgress(): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx, 'DELETE FROM reading_progress', []);
  });
}

export async function loadBookmarks(aid: string): Promise<Array<ReadingProgress>> {
  return readProgressRows(await dbQuery(
    'SELECT * FROM bookmark WHERE aid = ? ORDER BY at ASC, chapter_id ASC, page ASC', [aid]));
}

export async function loadAllBookmarks(): Promise<Array<ReadingProgress>> {
  return readProgressRows(await dbQuery('SELECT * FROM bookmark ORDER BY at ASC, aid ASC, chapter_id ASC, page ASC', []));
}

export function toggleBookmark(item: ReadingProgress): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    const args: Array<relationalStore.ValueType> = [item.aid, item.chapterId, item.page];
    if (await txExists(tx, 'SELECT aid FROM bookmark WHERE aid = ? AND chapter_id = ? AND page = ?', args)) {
      await txExecute(tx, 'DELETE FROM bookmark WHERE aid = ? AND chapter_id = ? AND page = ?', args);
      return;
    }
    await txExecute(tx,
      'INSERT INTO bookmark (aid, chapter_id, page, chapter_index, total_pages, at, title, author, cover_url) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [item.aid, item.chapterId, item.page, item.chapterIndex, item.totalPages, item.at, item.title, item.author, item.coverUrl]);
  });
}

export async function loadReaderPref(workKey: string): Promise<ReaderPrefRow | null> {
  let found: ReaderPrefRow | null = null;
  await readRows(await dbQuery('SELECT * FROM reader_pref WHERE work_key = ?', [workKey]),
    (row: relationalStore.ResultSet): void => {
      const options: ReaderPrefRow = new ReaderPrefRow();
      options.mode = cellString(row, 'mode');
      options.coverOffset = cellLong(row, 'cover_offset');
      options.cropWhite = cellLong(row, 'crop_white');
      options.eyeComfort = cellLong(row, 'eye_comfort');
      options.preload = cellLong(row, 'preload');
      options.paper = cellLong(row, 'paper');
      options.taps = cellString(row, 'taps');
      found = options;
    });
  return found;
}

export function saveReaderPref(workKey: string, options: ReaderPrefRow): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txUpsert(tx, 'reader_pref', ['work_key'],
      ['work_key', 'mode', 'cover_offset', 'crop_white', 'eye_comfort', 'preload', 'paper', 'taps', 'updated_at'],
      [workKey, options.mode, options.coverOffset, options.cropWhite, options.eyeComfort, options.preload, options.paper,
        options.taps, Date.now()]);
  });
}

export async function loadStats(): Promise<ActivityRow> {
  const stats: ActivityRow = new ActivityRow();
  await readRows(await dbQuery('SELECT * FROM activity_stat WHERE id = ?', [1]), (row: relationalStore.ResultSet): void => {
    stats.milliseconds = cellLong(row, 'milliseconds');
  });
  await readRows(await dbQuery('SELECT page_key FROM activity_page ORDER BY recorded_at ASC, page_key ASC', []),
    (row: relationalStore.ResultSet): void => { stats.pages.push(cellString(row, 'page_key')); });
  await readRows(await dbQuery('SELECT book_key FROM activity_book ORDER BY recorded_at ASC, book_key ASC', []),
    (row: relationalStore.ResultSet): void => { stats.books.push(cellString(row, 'book_key')); });
  return stats;
}

export function recordActivity(book: string, page: string, elapsed: number): Promise<void> {
  const now: number = Date.now();
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx, 'INSERT INTO activity_stat (id, milliseconds, updated_at) VALUES (?, ?, ?) ' +
      'ON CONFLICT (id) DO UPDATE SET milliseconds = activity_stat.milliseconds + excluded.milliseconds, updated_at = excluded.updated_at',
      [1, elapsed, now]);
    await txExecute(tx, 'INSERT OR IGNORE INTO activity_page (page_key, recorded_at) VALUES (?, ?)', [page, now]);
    await txExecute(tx, 'INSERT OR IGNORE INTO activity_book (book_key, recorded_at) VALUES (?, ?)', [book, now]);
  });
}

async function readProgressRows(result: relationalStore.ResultSet): Promise<Array<ReadingProgress>> {
  const items: Array<ReadingProgress> = [];
  await readRows(result, (row: relationalStore.ResultSet): void => {
    items.push(new ReadingProgress(cellString(row, 'aid'), cellString(row, 'chapter_id'), cellLong(row, 'chapter_index'),
      cellLong(row, 'page'), cellLong(row, 'total_pages'), cellLong(row, 'at'), cellString(row, 'title'),
      cellString(row, 'author'), cellString(row, 'cover_url')));
  });
  return items;
}

export function copyProgress(item: ReadingProgress): ReadingProgress {
  return new ReadingProgress(item.aid, item.chapterId, item.chapterIndex, item.page, item.totalPages, item.at,
    item.title, item.author, item.coverUrl);
}

export function tapsFrom(text: string): Array<number> {
  const fallback: Array<number> = [1, 0, 2, 1, 0, 2, 3, 0, 4];
  let parsed: Object | null = null;
  try { parsed = JSON.parse(text) as Object; } catch (e) { return fallback; }
  const arr: Array<Object> | null = asArray(parsed);
  if (arr === null || arr.length !== fallback.length) { return fallback; }
  const taps: Array<number> = [];
  for (const item of arr) { taps.push(asNumber(item, 0)); }
  return taps;
}
