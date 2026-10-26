import { relationalStore } from '@kit.ArkData';
import { Album, ChapterPage } from '../../models/Models';
import { dbQuery, dbTransaction, txExecute } from './AppDatabase';
import { albumFromJson, albumToJson, appendPage, cellLong, cellString, readRows, sourcePrefix } from './RowCodec';

export class TaskRow {
  id: number = 0;
  albumId: string = '';
  title: string = '';
  state: string = 'queued';
  done: number = 0;
  total: number = 0;
  failedPages: number = 0;
  savedTo: string = '';
  cover: string = '';
  createdAt: number = 0;
  error: string = '';
  exporting: number = 0;
  exportDone: number = 0;
  exportTotal: number = 0;
}

export class OfflinePageRow {
  albumId: string = '';
  chapterId: string = '';
  pageOrder: number = 0;
  relativePath: string = '';
  fileSize: number = 0;
  complete: number = 0;
  scrambleId: number = 0;
  filename: string = '';
}

export class DownloadPageRow extends OfflinePageRow {
  taskId: number = 0;
}

export class OfflineBookRow {
  album: Album = new Album();
  directory: string = '';
  pages: Array<OfflinePageRow> = [];
}

export class LocalBookRow {
  bookId: string = '';
  album: Album = new Album();
  filesJson: string = '';
}

export class ExportRow {
  id: number = 0;
  albumId: string = '';
  taskId: number = 0;
  location: string = '';
  createdAt: number = 0;
}

export async function loadTasks(): Promise<Array<TaskRow>> {
  const items: Array<TaskRow> = [];
  const result: relationalStore.ResultSet = await dbQuery(
    'SELECT * FROM download_task ORDER BY created_at ASC', []);
  await readRows(result, (row: relationalStore.ResultSet): void => {
    items.push(taskFrom(row));
  });
  return items;
}

export async function loadTaskPage(offset: number, limit: number): Promise<Array<TaskRow>> {
  const args: Array<relationalStore.ValueType> = [];
  const sql: string = appendPage('SELECT * FROM download_task ORDER BY created_at DESC', args, limit, offset);
  const items: Array<TaskRow> = [];
  const result: relationalStore.ResultSet = await dbQuery(sql, args);
  await readRows(result, (row: relationalStore.ResultSet): void => {
    items.push(taskFrom(row));
  });
  return items;
}

export function saveTasks(items: Array<TaskRow>): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    for (const item of items) {
      await writeTask(tx, item);
    }
  });
}

async function writeTask(tx: relationalStore.Transaction, item: TaskRow): Promise<void> {
  await txExecute(tx,
    'INSERT OR REPLACE INTO download_task (id, album_id, title, state, done, total, failed_pages, saved_to, cover, created_at, error, exporting, export_done, export_total, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [item.id, item.albumId, item.title, item.state, item.done, item.total, item.failedPages, item.savedTo,
      item.cover, item.createdAt, item.error, item.exporting, item.exportDone, item.exportTotal, Date.now()]);
}

export function deleteTask(id: number): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx, 'DELETE FROM download_page WHERE task_id = ?', [id]);
    await txExecute(tx, 'DELETE FROM download_task WHERE id = ?', [id]);
  });
}

/** 页面、书目、任务完成状态与续传记录在一次事务中切换。 */
export function publishOffline(album: Album, directory: string, pages: Array<OfflinePageRow>,
  task: TaskRow, validate: () => void): Promise<void> {
  const now: number = Date.now();
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx, 'DELETE FROM offline_book WHERE album_id = ?', [album.id]);
    await txExecute(tx, 'DELETE FROM offline_page WHERE album_id = ?', [album.id]);
    await txExecute(tx,
      'INSERT INTO offline_book (album_id, source_id, directory, payload, updated_at) VALUES (?, ?, ?, ?, ?)',
      [album.id, sourcePrefix(album.id), directory, albumToJson(album), now]);
    for (const page of pages) {
      await txExecute(tx,
        'INSERT INTO offline_page (album_id, chapter_id, page_order, relative_path, file_size, complete, scramble_id, filename) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [album.id, page.chapterId, page.pageOrder, page.relativePath, page.fileSize, 1, page.scrambleId, page.filename]);
    }
    await writeTask(tx, task);
    await txExecute(tx, 'DELETE FROM download_page WHERE task_id = ?', [task.id]);
    validate();
  });
}

export function deleteOffline(albumId: string): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx, 'DELETE FROM offline_page WHERE album_id = ?', [albumId]);
    await txExecute(tx, 'DELETE FROM offline_book WHERE album_id = ?', [albumId]);
  });
}

export async function loadOfflineAlbum(albumId: string): Promise<OfflineBookRow | null> {
  const result: relationalStore.ResultSet = await dbQuery(
    'SELECT * FROM offline_book WHERE album_id = ?', [albumId]);
  let found: OfflineBookRow | null = null;
  await readRows(result, (row: relationalStore.ResultSet): void => {
    const book: OfflineBookRow = new OfflineBookRow();
    book.album = albumFromJson(cellString(row, 'payload'));
    book.directory = cellString(row, 'directory');
    found = book;
  });
  return found;
}

export async function loadOfflineAlbumIds(): Promise<Array<string>> {
  const ids: Array<string> = [];
  const result: relationalStore.ResultSet = await dbQuery(
    'SELECT * FROM offline_book ORDER BY updated_at DESC', []);
  await readRows(result, (row: relationalStore.ResultSet): void => {
    ids.push(cellString(row, 'album_id'));
  });
  return ids;
}

export async function loadCompletePages(albumId: string): Promise<Array<OfflinePageRow>> {
  const items: Array<OfflinePageRow> = [];
  const result: relationalStore.ResultSet = await dbQuery(
    'SELECT * FROM offline_page WHERE album_id = ? AND complete = ? ORDER BY page_order ASC', [albumId, 1]);
  await readRows(result, (row: relationalStore.ResultSet): void => {
    items.push(pageFrom(row));
  });
  return items;
}

export async function loadDownloadPages(taskId: number, albumId: string): Promise<Array<DownloadPageRow>> {
  const items: Array<DownloadPageRow> = [];
  const result: relationalStore.ResultSet = await dbQuery(
    'SELECT * FROM download_page WHERE task_id = ? AND album_id = ? AND complete = ? ORDER BY page_order ASC',
    [taskId, albumId, 1]);
  await readRows(result, (row: relationalStore.ResultSet): void => {
    const page: DownloadPageRow = new DownloadPageRow();
    fillPage(page, row);
    page.taskId = cellLong(row, 'task_id');
    items.push(page);
  });
  return items;
}

export function saveDownloadPage(page: DownloadPageRow): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx,
      'INSERT OR REPLACE INTO download_page (task_id, album_id, chapter_id, page_order, relative_path, file_size, complete, scramble_id, filename) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [page.taskId, page.albumId, page.chapterId, page.pageOrder, page.relativePath, page.fileSize, 1,
        page.scrambleId, page.filename]);
  });
}

export async function loadOfflinePages(chapterId: string): Promise<Array<OfflinePageRow>> {
  const items: Array<OfflinePageRow> = [];
  const result: relationalStore.ResultSet = await dbQuery(
    'SELECT * FROM offline_page WHERE chapter_id = ? AND complete = ? ORDER BY page_order ASC', [chapterId, 1]);
  await readRows(result, (row: relationalStore.ResultSet): void => {
    items.push(pageFrom(row));
  });
  return items;
}

export async function loadLocalBooks(): Promise<Array<LocalBookRow>> {
  const items: Array<LocalBookRow> = [];
  const result: relationalStore.ResultSet = await dbQuery(
    'SELECT * FROM local_book ORDER BY updated_at ASC', []);
  await readRows(result, (row: relationalStore.ResultSet): void => {
    const book: LocalBookRow = new LocalBookRow();
    book.bookId = cellString(row, 'book_id');
    book.album = albumFromJson(cellString(row, 'payload'));
    book.filesJson = cellString(row, 'files_json');
    items.push(book);
  });
  return items;
}

export function saveLocalBooks(items: Array<LocalBookRow>): Promise<void> {
  const now: number = Date.now();
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx, 'DELETE FROM local_book', []);
    for (const item of items) {
      await txExecute(tx,
        'INSERT INTO local_book (book_id, payload, files_json, updated_at) VALUES (?, ?, ?, ?)',
        [item.bookId, albumToJson(item.album), item.filesJson, now]);
    }
  });
}

export function saveExport(albumId: string, taskId: number, location: string): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx,
      'INSERT INTO export_record (album_id, task_id, location, created_at) VALUES (?, ?, ?, ?)',
      [albumId, taskId, location, Date.now()]);
  });
}

export async function loadExportPage(offset: number, limit: number): Promise<Array<ExportRow>> {
  const args: Array<relationalStore.ValueType> = [];
  const sql: string = appendPage('SELECT * FROM export_record ORDER BY created_at DESC', args, limit, offset);
  const items: Array<ExportRow> = [];
  const result: relationalStore.ResultSet = await dbQuery(sql, args);
  await readRows(result, (row: relationalStore.ResultSet): void => {
    const item: ExportRow = new ExportRow();
    item.id = cellLong(row, 'id');
    item.albumId = cellString(row, 'album_id');
    item.taskId = cellLong(row, 'task_id');
    item.location = cellString(row, 'location');
    item.createdAt = cellLong(row, 'created_at');
    items.push(item);
  });
  return items;
}

function taskFrom(row: relationalStore.ResultSet): TaskRow {
  const task: TaskRow = new TaskRow();
  task.id = cellLong(row, 'id');
  task.albumId = cellString(row, 'album_id');
  task.title = cellString(row, 'title');
  task.state = cellString(row, 'state');
  task.done = cellLong(row, 'done');
  task.total = cellLong(row, 'total');
  task.failedPages = cellLong(row, 'failed_pages');
  task.savedTo = cellString(row, 'saved_to');
  task.cover = cellString(row, 'cover');
  task.createdAt = cellLong(row, 'created_at');
  task.error = cellString(row, 'error');
  task.exporting = cellLong(row, 'exporting');
  task.exportDone = cellLong(row, 'export_done');
  task.exportTotal = cellLong(row, 'export_total');
  return task;
}

function pageFrom(row: relationalStore.ResultSet): OfflinePageRow {
  const page: OfflinePageRow = new OfflinePageRow();
  fillPage(page, row);
  return page;
}

function fillPage(page: OfflinePageRow, row: relationalStore.ResultSet): void {
  page.albumId = cellString(row, 'album_id');
  page.chapterId = cellString(row, 'chapter_id');
  page.pageOrder = cellLong(row, 'page_order');
  page.relativePath = cellString(row, 'relative_path');
  page.fileSize = cellLong(row, 'file_size');
  page.complete = cellLong(row, 'complete');
  page.scrambleId = cellLong(row, 'scramble_id');
  page.filename = cellString(row, 'filename');
}

export function pageRow(page: ChapterPage, order: number, relativePath: string, fileSize: number): OfflinePageRow {
  const row: OfflinePageRow = new OfflinePageRow();
  row.albumId = '';
  row.chapterId = page.photoId;
  row.pageOrder = order;
  row.relativePath = relativePath;
  row.fileSize = fileSize;
  row.complete = 1;
  row.scrambleId = page.scrambleId;
  row.filename = page.filename;
  return row;
}
