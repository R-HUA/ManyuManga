import fs from '@ohos.file.fs';
import { Album, ChapterPage } from '../models/Models';
import { getAppContext } from '../util/Prefs';
import { ensureDir, fileExists, rmTree } from '../util/FileUtil';
import { md5Hex } from './JmApi';
import { cbzFileName, copyBytesAsync, readBytesAsync } from './CbzPacker';
import {
  deleteOffline, DownloadPageRow, loadCompletePages, loadDownloadPages, loadOfflineAlbum,
  loadOfflineAlbumIds, loadOfflinePages, OfflineBookRow, OfflinePageRow, pageRow, publishOffline,
  saveDownloadPage, TaskRow
} from './db/ContentDao';

/** 续传页独立存放；只有完整页面和 CBZ 都校验通过后才发布正式索引。 */
class OfflineStore {
  private queue: Promise<void> = Promise.resolve();
  private listeners: Array<() => void> = [];
  private sequence: number = 0;

  onChange(listener: () => void): void {
    if (!this.listeners.includes(listener)) { this.listeners.push(listener); }
  }
  offChange(listener: () => void): void {
    this.listeners = this.listeners.filter((item: () => void): boolean => item !== listener);
  }
  notifyChanged(): void {
    for (const listener of this.listeners) {
      try { listener(); } catch (e) { console.warn('[Offline] 刷新离线书目失败'); }
    }
  }
  async album(key: string): Promise<Album | null> {
    const book: OfflineBookRow | null = await loadOfflineAlbum(key);
    return book === null ? null : book.album;
  }
  async albumIds(): Promise<Array<string>> { return loadOfflineAlbumIds(); }
  async pages(key: string): Promise<Array<string> | null> {
    const rows: Array<OfflinePageRow> = await this.readyPages(key);
    return rows.length === 0 ? null : rows.map((row: OfflinePageRow): string => row.filename);
  }
  async scramble(key: string): Promise<number | null> {
    const rows: Array<OfflinePageRow> = await this.readyPages(key);
    return rows.length === 0 ? null : rows[0].scrambleId;
  }
  async bytes(key: string, filename: string): Promise<ArrayBuffer | null> {
    const rows: Array<OfflinePageRow> = await this.readyPages(key);
    for (const row of rows) {
      if (row.filename !== filename) { continue; }
      const path: string = `${getAppContext().filesDir}/${row.relativePath}`;
      if (!await this.validFile(path, row.fileSize)) { return null; }
      return readBytesAsync(path);
    }
    return null;
  }

  async completedPages(taskId: number, albumId: string): Promise<Array<DownloadPageRow>> {
    const rows: Array<DownloadPageRow> = await loadDownloadPages(taskId, albumId);
    const kept: Array<DownloadPageRow> = [];
    for (const row of rows) {
      if (row.taskId !== taskId || row.albumId !== albumId || row.complete !== 1 ||
        !row.relativePath.startsWith(`resume/${taskId}/`) || row.relativePath.includes('..')) { continue; }
      if (await this.validFile(`${getAppContext().filesDir}/${row.relativePath}`, row.fileSize)) { kept.push(row); }
    }
    return kept;
  }

  /** 已发布离线书的页面，追加章节重跑任务时直接复用，不重复下载。 */
  async installedPages(albumId: string): Promise<Array<DownloadPageRow>> {
    const rows: Array<OfflinePageRow> = await loadCompletePages(albumId);
    const kept: Array<DownloadPageRow> = [];
    for (const row of rows) {
      if (row.albumId !== albumId || row.relativePath.includes('..') || !row.relativePath.startsWith('content/')) { continue; }
      if (!await this.validFile(`${getAppContext().filesDir}/${row.relativePath}`, row.fileSize)) { continue; }
      const page: DownloadPageRow = new DownloadPageRow();
      page.albumId = row.albumId;
      page.chapterId = row.chapterId;
      page.pageOrder = row.pageOrder;
      page.relativePath = row.relativePath;
      page.fileSize = row.fileSize;
      page.complete = row.complete;
      page.scrambleId = row.scrambleId;
      page.filename = row.filename;
      kept.push(page);
    }
    return kept;
  }

  async rememberPage(taskId: number, albumId: string, page: ChapterPage, order: number, srcPath: string,
    validate: () => void = (): void => {}): Promise<void> {
    validate();
    const size: number = (await fs.stat(srcPath)).size;
    if (size <= 0) { throw new Error('续传页面校验失败'); }
    const folder: string = `resume/${taskId}`;
    ensureDir(`${getAppContext().filesDir}/${folder}`);
    const relative: string = `${folder}/${order}_${Date.now()}_${this.sequence++}.bin`;
    const dest: string = `${getAppContext().filesDir}/${relative}`;
    let recorded: boolean = false;
    try {
      await copyBytesAsync(srcPath, dest, validate);
      if (!await this.validFile(dest, size)) { throw new Error('续传页面校验失败'); }
      validate();
      const row: DownloadPageRow = new DownloadPageRow();
      row.taskId = taskId;
      row.albumId = albumId;
      row.chapterId = page.photoId;
      row.pageOrder = order;
      row.relativePath = relative;
      row.fileSize = size;
      row.complete = 1;
      row.scrambleId = page.scrambleId;
      row.filename = page.filename;
      await saveDownloadPage(row);
      recorded = true;
    } finally {
      if (!recorded) { rmTree(dest); }
    }
  }

  install(album: Album, pages: Array<ChapterPage>, files: Array<string>, cbzPath: string, task: TaskRow,
    validate: () => void = (): void => {}, beforePublish: () => Promise<void> = async (): Promise<void> => {}): Promise<string> {
    const next: Promise<string> = this.queue.then(() => this.installFiles(album, pages, files, cbzPath, task, validate, beforePublish));
    this.queue = next.then((): void => {}).catch((): void => {});
    return next;
  }

  private async installFiles(album: Album, pages: Array<ChapterPage>, files: Array<string>, cbzPath: string,
    task: TaskRow, validate: () => void, beforePublish: () => Promise<void>): Promise<string> {
    if (pages.length === 0 || pages.length !== files.length || task.albumId !== album.id) {
      throw new Error('离线页面列表不完整');
    }
    const previous: OfflineBookRow | null = await loadOfflineAlbum(album.id);
    const folder: string = `content/${md5Hex(album.id)}_${task.id}_${Date.now()}_${this.sequence++}`;
    const root: string = `${getAppContext().filesDir}/${folder}`;
    const destination: string = `${root}/${cbzFileName(album.name)}`;
    ensureDir(root);
    let committed: boolean = false;
    try {
      const rows: Array<OfflinePageRow> = [];
      for (let index: number = 0; index < files.length; index++) {
        validate();
        const relative: string = `${folder}/${index}.bin`;
        const size: number = (await fs.stat(files[index])).size;
        await copyBytesAsync(files[index], `${getAppContext().filesDir}/${relative}`, validate);
        if (!await this.validFile(`${getAppContext().filesDir}/${relative}`, size)) { throw new Error('离线页面校验失败'); }
        const row: OfflinePageRow = pageRow(pages[index], index, relative, size);
        row.albumId = album.id;
        rows.push(row);
      }
      await copyBytesAsync(cbzPath, destination, validate);
      validate();
      await beforePublish();
      validate();
      task.savedTo = destination;
      task.state = 'done';
      task.done = pages.length;
      task.total = pages.length;
      task.failedPages = 0;
      task.exporting = 0;
      task.exportDone = pages.length;
      task.exportTotal = pages.length;
      task.error = '';
      await publishOffline(album, folder, rows, task, validate);
      committed = true;
    } finally {
      if (!committed) { rmTree(root); }
    }
    // 提交成功即完成，不再用中断信号撤回已发布的新版本。
    if (previous !== null && previous.directory !== '' && previous.directory !== folder) {
      rmTree(`${getAppContext().filesDir}/${previous.directory}`);
    }
    rmTree(`${getAppContext().filesDir}/resume/${task.id}`);
    this.notifyChanged();
    return destination;
  }

  remove(key: string): Promise<void> {
    const next: Promise<void> = this.queue.then(async (): Promise<void> => {
      const book: OfflineBookRow | null = await loadOfflineAlbum(key);
      await deleteOffline(key);
      if (book !== null && book.directory !== '') { rmTree(`${getAppContext().filesDir}/${book.directory}`); }
      this.notifyChanged();
    });
    this.queue = next.catch((): void => {});
    return next;
  }

  private async validFile(path: string, size: number): Promise<boolean> {
    return size > 0 && fileExists(path) && (await fs.stat(path)).size === size;
  }
  private async readyPages(chapterId: string): Promise<Array<OfflinePageRow>> {
    const rows: Array<OfflinePageRow> = await loadOfflinePages(chapterId);
    const ready: Array<OfflinePageRow> = [];
    for (const row of rows) {
      if (row.complete !== 1) { continue; }
      const book: OfflineBookRow | null = await loadOfflineAlbum(row.albumId);
      if (book !== null && row.relativePath.startsWith(`${book.directory}/`) && !row.relativePath.includes('..')) {
        ready.push(row);
      }
    }
    return ready;
  }
}
export const offlineStore: OfflineStore = new OfflineStore();
