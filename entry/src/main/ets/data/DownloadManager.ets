import { copyBytesAsync, makeArchiveEntry, writeBytesAsync, writeZipFile } from './CbzPacker';
import { fileExists, ensureDir, rmTree } from '../util/FileUtil';
import { ZipEntry } from './CbzPacker';
import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import { Prefs, getAppContext } from '../util/Prefs';
import { deleteTask, DownloadPageRow, loadTasks, saveTasks, TaskRow } from './db/ContentDao';
import { isRequestCancelled, RequestAbortGroup } from '../util/RequestAbort';
import { sourceApi as jmApi } from './SourceApi';
import { offlineStore } from './OfflineStore';
import { cachedRawFilePath } from './ImageDecode';
import { Album, ChapterPage, errorMessage } from '../models/Models';
export { ZipEntry } from './CbzPacker';
/** 任务状态机 */
export type DownloadState = 'queued' | 'running' | 'paused' | 'done' | 'failed' | 'canceled';

/** 下载任务 */
export class DownloadTask {
  id: number = 0;
  albumId: string = '';
  title: string = '';
  state: DownloadState = 'queued';
  done: number = 0;
  total: number = 0;
  failedPages: number = 0;
  savedTo: string = '';
  cover: string = '';
  createdAt: number = 0;
  error: string = '';
  exporting: boolean = false;
  exportDone: number = 0;
  exportTotal: number = 0;
}

/** 任务字段快照（浅拷贝，回调与持久化用；不用展开/解构） */
function cloneTask(t: DownloadTask): DownloadTask {
  const c: DownloadTask = new DownloadTask();
  c.id = t.id;
  c.albumId = t.albumId;
  c.title = t.title;
  c.state = t.state;
  c.done = t.done;
  c.total = t.total;
  c.failedPages = t.failedPages;
  c.savedTo = t.savedTo;
  c.cover = t.cover;
  c.createdAt = t.createdAt;
  c.error = t.error;
  c.exporting = t.exporting;
  c.exportDone = t.exportDone;
  c.exportTotal = t.exportTotal;
  return c;
}

/** 协作式中断信号（取消/暂停） */
class DownloadAbortError extends Error {
  readonly kind: string; // 'canceled' | 'paused'
  constructor(kind: string) {
    super(kind);
    this.kind = kind;
  }
}

/** 轻量异步信号量（页下载并发控制） */
class Semaphore {
  private permits: number;
  private waiters: Array<(value: void) => void> = [];

  constructor(permits: number) {
    this.permits = permits;
  }

  async acquire(): Promise<void> {
    if (this.permits > 0) {
      this.permits--;
      return;
    }
    await new Promise<void>((resolve: (value: void) => void) => {
      this.waiters.push(resolve);
    });
  }

  release(): void {
    this.permits++;
    if (this.waiters.length > 0) {
      const w: ((value: void) => void) | undefined = this.waiters.shift();
      if (w !== undefined) {
        this.permits--;
        w();
      }
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: (value: void) => void) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

// ───────────────────────── CRC32（自实现，无第三方依赖） ─────────────────────────

// ───────────────────────── 下载管理器 ─────────────────────────

/** 页下载并发 */
const PAGE_CONCURRENCY: number = 3;

export class DownloadManager {
  /** 任务列表 */
  tasks: Array<DownloadTask> = [];

  private listeners: Array<(task: DownloadTask) => void> = [];
  private workerActive: boolean = false;
  private activeTaskId: number = 0;
  private saveTimer: number = -1;
  private initPromise: Promise<void> | null = null;
  private taskSignals: Map<number, RequestAbortGroup> = new Map();
  private workerPromise: Promise<void> = Promise.resolve();
  private saveGate: Promise<void> = Promise.resolve();
  private suspensionGate: Promise<void> = Promise.resolve();
  private suspensionCount: number = 0;
  private committingTaskId: number = 0;
  private dirtyTasks: Set<number> = new Set();
  private taskWrites: Set<Promise<void>> = new Set();
  private activeRun: Promise<void> = Promise.resolve();

  /** 备份恢复屏障：暂停并等待所有在途写入，work 期间拒绝新任务及任务操作。 */
  async withSuspendedWrites<T>(work: () => Promise<T>): Promise<T> {
    this.suspensionCount++;
    const previous: Promise<void> = this.suspensionGate;
    let release: () => void = (): void => {};
    this.suspensionGate = new Promise<void>((resolve: () => void): void => { release = resolve; });
    try {
      await previous;
      await this.init();
      for (const task of this.tasks) {
        if (task.id !== this.committingTaskId && (task.state === 'queued' || task.state === 'running')) {
          task.state = 'paused';
          this.abortSignal(task.id);
          this.dirtyTasks.add(task.id);
          this.notify(task);
        }
      }
      await this.workerPromise;
      await this.activeRun;
      await Promise.all(Array.from(this.taskWrites));
      this.clearSaveTimer();
      await this.persistTasks();
      return await work();
    } finally {
      this.suspensionCount--;
      release();
    }
  }

  private assertWritable(): void {
    if (this.suspensionCount > 0) { throw new Error('正在恢复数据，请稍后操作下载任务'); }
  }

  private async mutate(work: () => Promise<void>): Promise<void> {
    this.assertWritable();
    const next: Promise<void> = work();
    const waiting: Promise<void> = next.catch((): void => {});
    this.taskWrites.add(waiting);
    waiting.then((): void => { this.taskWrites.delete(waiting); });
    return next;
  }

  private clearSaveTimer(): void {
    if (this.saveTimer >= 0) { clearTimeout(this.saveTimer); this.saveTimer = -1; }
  }

  private async waitCommit(id: number): Promise<void> {
    if (this.committingTaskId === id) { await this.activeRun; }
  }

  private openSignal(id: number): RequestAbortGroup {
    const previous: RequestAbortGroup | undefined = this.taskSignals.get(id);
    if (previous !== undefined) {
      previous.abortAll();
    }
    const next: RequestAbortGroup = new RequestAbortGroup();
    this.taskSignals.set(id, next);
    return next;
  }

  private abortSignal(id: number): void {
    const current: RequestAbortGroup | undefined = this.taskSignals.get(id);
    if (current !== undefined) {
      current.abortAll();
    }
  }

  async reloadTasks(): Promise<void> {
    this.clearSaveTimer();
    await this.saveGate;
    this.tasks = [];
    this.dirtyTasks.clear();
    this.initPromise = null;
    await this.init();
    offlineStore.notifyChanged();
    if (this.tasks.length === 0) { this.notify(new DownloadTask()); }
    else { for (const task of this.tasks) { this.notify(task); } }
  }

  /** 启动恢复：排队和进行中改为暂停，等待用户继续。不自动开下。 */
  init(): Promise<void> {
    if (this.initPromise === null) {
      this.initPromise = this.doInit().catch((e: Error): void => {
        this.initPromise = null;
        throw e;
      });
    }
    return this.initPromise;
  }

  private async doInit(): Promise<void> {
      const rows: Array<TaskRow> = await loadTasks();
      this.tasks = [];
      let interrupted: boolean = false;
      for (const rec of rows) {
        const t: DownloadTask = new DownloadTask();
        t.id = rec.id;
        t.albumId = rec.albumId;
        t.title = rec.title;
        t.state = this.parseState(rec.state);
        t.done = rec.done;
        t.total = rec.total;
        t.failedPages = rec.failedPages;
        t.savedTo = rec.savedTo;
        t.cover = rec.cover;
        t.createdAt = rec.createdAt;
        t.error = rec.error;
        t.exporting = rec.exporting === 1;
        t.exportDone = rec.exportDone;
        t.exportTotal = rec.exportTotal;
        if (t.state === 'running' || t.state === 'queued') {
          t.state = 'paused';
          t.error = '';
          interrupted = true;
          this.dirtyTasks.add(t.id);
        }
        t.exporting = false;
        this.tasks.push(t);
      }
      if (interrupted) {
        await this.persistTasks();
      }
  }

  private parseState(s: string): DownloadState {
    if (s === 'running' || s === 'paused' || s === 'done' || s === 'failed' || s === 'canceled') {
      return s;
    }
    return 'queued';
  }

  /** 进度/状态回调（页面订阅；回调收到的是任务快照） */
  onChange(listener: (task: DownloadTask) => void): void {
    this.listeners.push(listener);
  }

  offChange(listener: (task: DownloadTask) => void): void {
    this.listeners = this.listeners.filter((l: (task: DownloadTask) => void) => l !== listener);
  }

  /** 入队 */
  enqueue(album: Album): Promise<void> { return this.mutate(() => this.enqueueNow(album)); }
  private async enqueueNow(album: Album): Promise<void> {
    this.assertWritable();
    await this.init();
    this.assertWritable();
    if (this.tasks.some((t: DownloadTask) => t.albumId === album.id && t.state !== 'canceled')) {
      throw new Error('该漫画已有下载任务，请前往下载管理查看或重试');
    }
    const t: DownloadTask = new DownloadTask();
    t.id = nextTaskId();
    t.albumId = album.id;
    t.title = album.name;
    t.cover = jmApi.albumCoverUrl(album.id);
    t.createdAt = Date.now();
    this.tasks.push(t);
    this.dirtyTasks.add(t.id);
    try { await this.persistTasks(); }
    catch (e) { this.tasks = this.tasks.filter((task: DownloadTask) => task.id !== t.id); throw e as Error; }
    this.notify(t);
    this.startWorker();
  }

  /** 暂停：排队/进行中 → paused。已完成页保留，恢复时跳过。 */
  pause(id: number): Promise<void> { return this.mutate(() => this.pauseNow(id)); }
  private async pauseNow(id: number): Promise<void> {
    this.assertWritable();
    await this.waitCommit(id);
    const t: DownloadTask | undefined = this.findTask(id);
    if (t !== undefined && (t.state === 'queued' || t.state === 'running')) {
      t.state = 'paused';
      this.abortSignal(id);
      this.dirtyTasks.add(id);
      this.notify(t);
      this.scheduleSave();
    }
  }

  /** 恢复：paused → queued */
  resume(id: number): Promise<void> { return this.mutate(() => this.resumeNow(id)); }
  private async resumeNow(id: number): Promise<void> {
    this.assertWritable();
    if (this.activeTaskId === id) { await this.activeRun; }
    this.assertWritable();
    const t: DownloadTask | undefined = this.findTask(id);
    if (t !== undefined && t.state === 'paused') {
      t.state = 'queued';
      t.failedPages = 0;
      t.error = '';
      this.dirtyTasks.add(id);
      this.notify(t);
      this.scheduleSave();
      this.startWorker();
    }
  }

  /** 取消（原 cancel :136-141；进行中协作中止并清临时文件） */
  cancel(id: number): Promise<void> { return this.mutate(() => this.cancelNow(id)); }
  private async cancelNow(id: number): Promise<void> {
    this.assertWritable();
    await this.waitCommit(id);
    const t: DownloadTask | undefined = this.findTask(id);
    if (t !== undefined && t.state !== 'done' && t.state !== 'failed' && t.state !== 'canceled') {
      t.state = 'canceled';
      this.abortSignal(id);
      this.dirtyTasks.add(id);
      this.notify(t);
      this.scheduleSave();
    }
  }

  /** 删除任务记录。deleteFile 只删除已打包的 CBZ，不删除离线内容索引。 */
  removeTask(id: number, deleteFile: boolean): Promise<void> {
    return this.mutate(() => this.removeTaskNow(id, deleteFile));
  }
  private async removeTaskNow(id: number, deleteFile: boolean): Promise<void> {
    this.assertWritable();
    await this.waitCommit(id);
    const t: DownloadTask | undefined = this.findTask(id);
    if (t === undefined) {
      return;
    }
    if (t.state === 'running' || t.state === 'queued' || t.state === 'paused') {
      t.state = 'canceled';
    }
    this.abortSignal(id);
    if (this.activeTaskId === id) { await this.activeRun; }
    this.cleanupTempFiles(id);
    // 成品属于离线内容；删除任务不会删除书目或用户导出的文件。
    if (deleteFile && t.savedTo !== '' && fileExists(t.savedTo)) { await fs.unlink(t.savedTo); }
    this.tasks = this.tasks.filter((it: DownloadTask) => it.id !== id);
    this.dirtyTasks.delete(id);
    await this.saveGate;
    await deleteTask(id);
    rmTree(`${getAppContext().filesDir}/resume/${id}`);
    this.notify(t);
  }

  /** 失败重试保留本任务已校验的续传页。 */
  retry(id: number): Promise<void> { return this.mutate(() => this.retryNow(id)); }
  private async retryNow(id: number): Promise<void> {
    this.assertWritable();
    if (this.activeTaskId === id) { await this.activeRun; }
    this.assertWritable();
    const task: DownloadTask | undefined = this.findTask(id);
    if (task === undefined || (task.state !== 'failed' && task.state !== 'canceled')) { return; }
    task.state = 'queued';
    task.error = '';
    task.failedPages = 0;
    this.dirtyTasks.add(id);
    await this.persistTasks();
    this.notify(task);
    this.startWorker();
  }

  private findTask(id: number): DownloadTask | undefined {
    for (const t of this.tasks) {
      if (t.id === id) {
        return t;
      }
    }
    return undefined;
  }

  private notify(t: DownloadTask): void {
    const snapshot: DownloadTask = cloneTask(t);
    for (const l of this.listeners) {
      try {
        l(snapshot);
      } catch (e) {
        // 监听器异常不影响队列
      }
    }
  }

  /** 600ms 去抖持久化（DownloadQueue.kt:192-200） */
  private scheduleSave(): void {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout(() => {
      this.saveTimer = -1;
      this.persistTasks().catch((e: Error) => {
        AppStorage.setOrCreate('crashErrorMessage', `下载任务保存失败：${errorMessage(e)}`);
      });
    }, 600);
  }

  private async persistTasks(): Promise<void> {
    const rows: Array<TaskRow> = [];
    for (const t of this.tasks) {
      if (!this.dirtyTasks.has(t.id)) { continue; }
      rows.push(taskRow(t));
    }
    this.dirtyTasks.clear();
    const next: Promise<void> = this.saveGate.then(() => saveTasks(rows));
    this.saveGate = next.catch((): void => {});
    try { await next; }
    catch (e) {
      for (const row of rows) {
        if (this.findTask(row.id) !== undefined) { this.dirtyTasks.add(row.id); }
      }
      throw e as Error;
    }
  }

  /** 单飞 worker：循环取第一个 QUEUED（DownloadQueue.kt:202-212） */
  private startWorker(): void {
    if (this.workerActive || this.suspensionCount > 0) {
      return;
    }
    this.workerActive = true;
    const self: DownloadManager = this;
    const loop: Promise<void> = (async (): Promise<void> => {
      for (;;) {
        if (self.suspensionCount > 0) { break; }
        let next: DownloadTask | undefined = undefined;
        for (const t of self.tasks) {
          if (t.state === 'queued') {
            next = t;
            break;
          }
        }
        if (next === undefined) {
          break;
        }
        await self.runTask(next);
      }
      self.workerActive = false;
    })();
    this.workerPromise = loop.catch((e: Error) => {
      self.workerActive = false;
      AppStorage.setOrCreate('crashErrorMessage', `下载未能完成：${errorMessage(e)}`);
    });
  }

  /** 任务被删除或取消 = 终止（DownloadQueue.kt:215-218）；暂停 = 协作中止 */
  private checkAbort(id: number): void {
    const t: DownloadTask | undefined = this.findTask(id);
    if (t === undefined) {
      throw new DownloadAbortError('canceled');
    }
    if (t.state === 'canceled') {
      throw new DownloadAbortError('canceled');
    }
    if (t.state === 'paused') {
      throw new DownloadAbortError('paused');
    }
  }

  private update(id: number, mutate: (t: DownloadTask) => void): void {
    const t: DownloadTask | undefined = this.findTask(id);
    if (t === undefined) {
      return;
    }
    mutate(t);
    this.dirtyTasks.add(id);
    this.notify(t);
    this.scheduleSave();
  }

  private cleanupTempFiles(id: number): void {
    const ctx: common.Context = getAppContext();
    rmTree(`${ctx.cacheDir}/dl_${id}`);
    try {
      fs.unlinkSync(`${ctx.cacheDir}/cbz_${id}.cbz`);
    } catch (e) {
      // 不存在可忽略
    }
  }

  /** 网络级重试：times 次、500ms×(i+1) 退避（DownloadQueue.kt:415-429） */
  private async retryNet<T>(times: number, fn: () => Promise<T>): Promise<T | null> {
    let failure: Error = new Error('请求失败');
    for (let i: number = 0; i < times; i++) {
      try {
        return await fn();
      } catch (e) {
        if (e instanceof DownloadAbortError || isRequestCancelled(e as Error)) {
          throw e;
        }
        failure = e as Error;
        if (/登录|认证|401|403/.test(failure.message)) { throw failure; }
        if (i + 1 < times) { await sleep(500 * (i + 1)); }
      }
    }
    throw failure;
  }

  /** 执行任务（runTask :253-413） */
  private runTask(task: DownloadTask): Promise<void> {
    const next: Promise<void> = this.runTaskNow(task);
    this.activeRun = next;
    return next;
  }
  private async runTaskNow(task: DownloadTask): Promise<void> {
    const taskId: number = task.id;
    // 选中后、改成 running 之前若已暂停/取消/删除，不能把状态盖回去
    const live: DownloadTask | undefined = this.findTask(taskId);
    if (live === undefined || live.state !== 'queued') {
      return;
    }
    this.update(taskId, (t: DownloadTask) => {
      if (t.state !== 'queued') {
        return;
      }
      t.state = 'running';
      t.exporting = false;
      t.error = '';
    });
    const started: DownloadTask | undefined = this.findTask(taskId);
    if (started === undefined || started.state !== 'running') {
      return;
    }
    this.activeTaskId = taskId;
    const signal: RequestAbortGroup = this.openSignal(taskId);
    try {
      // 1) 本子信息（网络重试 3 次）
      const album: Album | null = await this.retryNet<Album>(3, (): Promise<Album> => jmApi.album(task.albumId, false, signal));
      if (album === null) {
        throw new Error('获取本子信息失败');
      }

      // 2) 汇集全部页（含乱序参数）
      const pages: Array<ChapterPage> = [];
      for (const ep of album.episodes) {
        this.checkAbort(taskId);
        const images: Array<string> | null = await this.retryNet<Array<string>>(
          3, (): Promise<Array<string>> => jmApi.chapterImages(ep.id, signal));
        if (images === null || images.length === 0) {
          const label: string = ep.title !== '' ? ep.title : ep.id;
          throw new Error(`章节图片获取失败：${label}`);
        }
        const sid: number = await this.retryNet<number>(3, (): Promise<number> => jmApi.scrambleId(ep.id, signal)) ?? 0;
        for (const fn of images) {
          pages.push(new ChapterPage(ep.id, fn, sid));
        }
        const totalNow: number = pages.length;
        this.update(taskId, (t: DownloadTask) => {
          t.total = totalNow;
        });
      }
      if (pages.length === 0) {
        throw new Error('没有可下载的图片');
      }

      // 3) 并发下载原图到临时目录（存乱序原始字节；缓存优先 > 网络换域名 3 次）
      const ctx: common.Context = getAppContext();
      const tmpDir: string = `${ctx.cacheDir}/dl_${taskId}`;
      ensureDir(tmpDir);
      const sem: Semaphore = new Semaphore(PAGE_CONCURRENCY);
      let doneCnt: number = 0;
      let failCnt: number = 0;
      const pageErrors: Array<Error> = [];
      const workers: Array<Promise<void>> = [];
      const finished: Array<DownloadPageRow> = await offlineStore.completedPages(taskId, task.albumId);
      for (let idx: number = 0; idx < pages.length; idx++) {
        const pageIdx: number = idx;
        const ref: ChapterPage = pages[pageIdx];
        const job: Promise<void> = (async (): Promise<void> => {
          await sem.acquire();
          try {
            this.checkAbort(taskId);
            const outFile: string = `${tmpDir}/${pad5(pageIdx)}.bin`;
            let ok: boolean = false;
            let reused: boolean = false;
            let kept: DownloadPageRow | undefined = undefined;
            for (const row of finished) {
              if (row.pageOrder === pageIdx && row.chapterId === ref.photoId && row.filename === ref.filename &&
                row.scrambleId === ref.scrambleId) {
                kept = row;
              }
            }
            if (kept !== undefined) {
              try {
                await copyBytesAsync(`${ctx.filesDir}/${kept.relativePath}`, outFile, (): void => this.checkAbort(taskId));
                reused = (await fs.stat(outFile)).size === kept.fileSize && kept.fileSize > 0;
                ok = reused;
              } catch (e) {
                this.checkAbort(taskId);
                reused = false;
                ok = false;
              }
            }
            // ① 页缓存原始字节复用（>1KB 才算命中）
            if (!ok) {
              try {
                const cached: string | null = cachedRawFilePath(ref.photoId, ref.filename);
                if (cached !== null) {
                  await copyBytesAsync(cached, outFile, (): void => this.checkAbort(taskId));
                  ok = (await fs.stat(outFile)).size > 1024;
                }
              } catch (e) {
                this.checkAbort(taskId);
                // 缓存复用失败走网络
              }
            }
            // ② 网络：换域名重试 3 次
            if (!ok) {
              for (let attempt: number = 0; attempt <= 2; attempt++) {
                this.checkAbort(taskId);
                try {
                  const bytes: ArrayBuffer = await jmApi.fetchPage(ref.photoId, ref.filename, attempt, signal);
                  this.checkAbort(taskId);
                  if (bytes.byteLength === 0) { throw new Error('页面内容为空'); }
                  await writeBytesAsync(outFile, bytes, (): void => this.checkAbort(taskId));
                  ok = true;
                  break;
                } catch (e) {
                  if (e instanceof DownloadAbortError) { throw e; }
                  if (isRequestCancelled(e as Error)) {
                    this.checkAbort(taskId);
                    throw new DownloadAbortError('canceled');
                  }
                  if (attempt === 2 || /登录|认证|401|403/.test(errorMessage(e as Error))) {
                    pageErrors.push(e as Error); break;
                  }
                }
              }
            }
            if (ok && !reused) {
              try {
                await offlineStore.rememberPage(taskId, task.albumId, ref, pageIdx, outFile,
                  (): void => this.checkAbort(taskId));
              } catch (e) {
                if (e instanceof DownloadAbortError || isRequestCancelled(e as Error)) {
                  throw e;
                }
                ok = false;
                pageErrors.push(e as Error);
              }
            }
            if (ok) {
              doneCnt++;
            } else {
              failCnt++;
            }
            const doneNow: number = doneCnt;
            const failNow: number = failCnt;
            this.update(taskId, (t: DownloadTask) => {
              t.done = doneNow;
              t.failedPages = failNow;
            });
          } finally {
            sem.release();
          }
        })();
        workers.push(job);
      }
      // 暂停或删除后等所有页请求收尾，避免清理临时目录时仍有请求写入。
      const failures: Array<Error> = [];
      await Promise.all(workers.map((job: Promise<void>): Promise<void> => job.catch((e: Error): void => { failures.push(e); })));
      if (failures.length > 0) { throw failures[0]; }
      this.checkAbort(taskId);
      if (failCnt > 0) { throw new Error(`${failCnt} 页下载失败：${pageErrors[0].message}`); }

      // 4) 导出 CBZ（反混淆后按源格式重编码；逐页回调进度）
      const total: number = pages.length;
      this.update(taskId, (t: DownloadTask) => {
        t.exporting = true;
        t.exportDone = 0;
        t.exportTotal = total;
      });
      const prefs: Prefs = await Prefs.getInstance();
      const imgQ: string = await prefs.archiveImgQuality();
      const outTemp: string = `${ctx.cacheDir}/cbz_${taskId}.cbz`;
      const self: DownloadManager = this;
      await writeZipFile(outTemp, total, (index: number): Promise<ZipEntry | null> => {
        return makeArchiveEntry(`${tmpDir}/${pad5(index)}.bin`, pages[index], index, imgQ,
          (): void => self.checkAbort(taskId)).then(
          (entry: ZipEntry | null): Promise<ZipEntry | null> => {
            self.checkAbort(taskId);
            self.update(taskId, (t: DownloadTask) => {
              t.exportDone = Math.min(index + 1, total);
            });
            return Promise.resolve(entry);
          });
      }, (): void => this.checkAbort(taskId));

      const finalRow: TaskRow = taskRow(task);
      const dest: string = await offlineStore.install(album, pages,
        pages.map((p: ChapterPage, index: number): string => `${tmpDir}/${pad5(index)}.bin`), outTemp, finalRow,
        (): void => this.checkAbort(taskId), async (): Promise<void> => {
          this.checkAbort(taskId);
          this.committingTaskId = taskId;
          this.clearSaveTimer();
          await this.persistTasks();
        });
      rmTree(tmpDir);
      try {
        fs.unlinkSync(outTemp);
      } catch (e) {
        // 临时文件清理失败可忽略
      }
      task.state = 'done';
      task.exporting = false;
      task.savedTo = dest;
      task.done = total;
      task.failedPages = 0;
      this.dirtyTasks.delete(taskId);
      this.notify(task);
    } catch (e) {
      let err: Error = e as Error;
      if (isRequestCancelled(err)) {
        try {
          this.checkAbort(taskId);
        } catch (abort) {
          err = abort as Error;
        }
      }
      if (err instanceof DownloadAbortError) {
        if (err.kind === 'paused') {
          this.update(taskId, (t: DownloadTask) => {
            t.state = 'paused';
            t.exporting = false;
          });
        } else {
          this.update(taskId, (t: DownloadTask) => {
            t.state = 'canceled';
            t.exporting = false;
          });
          this.cleanupTempFiles(taskId);
        }
      } else {
        this.update(taskId, (t: DownloadTask) => {
          t.state = 'failed';
          t.exporting = false;
          t.error = errorMessage(err);
        });
        // 失败保留独立续传目录，重试复用同一任务。
        this.cleanupTempFiles(taskId);
      }
    } finally {
      this.committingTaskId = 0;
      this.abortSignal(taskId);
      this.taskSignals.delete(taskId);
      this.clearSaveTimer();
      try { await this.persistTasks(); }
      finally { this.activeTaskId = 0; }
    }
  }
}

function taskRow(task: DownloadTask): TaskRow {
  const row: TaskRow = new TaskRow();
  row.id = task.id;
  row.albumId = task.albumId;
  row.title = task.title;
  row.state = task.state;
  row.done = task.done;
  row.total = task.total;
  row.failedPages = task.failedPages;
  row.savedTo = task.savedTo;
  row.cover = task.cover;
  row.createdAt = task.createdAt;
  row.error = task.error;
  row.exporting = task.exporting ? 1 : 0;
  row.exportDone = task.exportDone;
  row.exportTotal = task.exportTotal;
  return row;
}

let taskIdSeq: number = 0;

/** 任务 id：时间戳 ×1000 + 进程序列，避免同毫秒批量入队撞 id（Review M-5） */
function nextTaskId(): number {
  taskIdSeq += 1;
  return Date.now() * 1000 + (taskIdSeq % 1000);
}

function pad5(n: number): string {
  let s: string = `${n}`;
  while (s.length < 5) {
    s = `0${s}`;
  }
  return s;
}

export const downloadManager: DownloadManager = new DownloadManager();
