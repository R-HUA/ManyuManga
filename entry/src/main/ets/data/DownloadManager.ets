import { writeZipFile } from './CbzPacker';
import { fileExists, ensureDir, readFileBytes, writeFileBytes, rmTree } from '../util/FileUtil';
import { ZipEntry } from './CbzPacker';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import common from '@ohos.app.ability.common';
import { Prefs, PrefKeys, getAppContext } from '../util/Prefs';
import { sourceApi as jmApi } from './SourceApi';
import { offlineStore } from './OfflineStore';
import { cachedRawFilePath, descrambleFromBytes, packImage } from './ImageDecode';
import { Album, ChapterPage, asArray, asBool, asNumber, asRecord, asString, errorMessage } from '../models/Models';
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

/** 产物文件名 */
function safeFileName(title: string): string {
  const clean: string = title.replace(/[\\/:*?"<>|\n\r]/g, '_').trim().substring(0, 80);
  return `${clean || '漫画'}.cbz`;
}

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

  /** 启动恢复（幂等、并发安全）：RUNNING/QUEUED → FAILED "已中断（应用重启）" */
  init(): Promise<void> {
    if (this.initPromise === null) {
      this.initPromise = this.doInit();
    }
    return this.initPromise;
  }

  private async doInit(): Promise<void> {
    try {
      const prefs: Prefs = await Prefs.getInstance();
      const text: string = await prefs.getString(PrefKeys.DOWNLOAD_TASKS, '[]');
      const arr: Array<Object> | null = asArray(JSON.parse(text) as Object);
      if (arr !== null) {
        for (const it of arr) {
          const rec: Record<string, Object> | null = asRecord(it);
          if (rec === null) {
            continue;
          }
          const t: DownloadTask = new DownloadTask();
          t.id = asNumber(rec['id'], 0);
          t.albumId = asString(rec['albumId']);
          t.title = asString(rec['title']);
          t.state = this.parseState(asString(rec['state'], 'queued'));
          t.done = asNumber(rec['done'], 0);
          t.total = asNumber(rec['total'], 0);
          t.failedPages = asNumber(rec['failedPages'], 0);
          t.savedTo = asString(rec['savedTo']);
          t.cover = asString(rec['cover']);
          t.createdAt = asNumber(rec['createdAt'], 0);
          t.error = asString(rec['error']);
          t.exporting = asBool(rec['exporting'], false);
          t.exportDone = asNumber(rec['exportDone'], 0);
          t.exportTotal = asNumber(rec['exportTotal'], 0);
          if (t.state === 'running' || t.state === 'queued') {
            t.state = 'failed';
            t.error = '已中断（应用重启）';
          }
          this.tasks.push(t);
        }
      }
    } catch (e) {
      console.info(`[Download] 恢复任务失败: ${errorMessage(e as Error)}`);
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
  async enqueue(album: Album): Promise<void> {
    await this.init();
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
    try { await this.persistTasks(); }
    catch (e) { this.tasks = this.tasks.filter((task: DownloadTask) => task.id !== t.id); throw e as Error; }
    this.notify(t);
    this.startWorker();
  }

  /** 暂停：排队/进行中 → paused（鸿蒙版新增暂停态；恢复从头重下，不做断点续传） */
  async pause(id: number): Promise<void> {
    const t: DownloadTask | undefined = this.findTask(id);
    if (t !== undefined && (t.state === 'queued' || t.state === 'running')) {
      t.state = 'paused';
      this.notify(t);
      this.scheduleSave();
    }
  }

  /** 恢复：paused → queued */
  async resume(id: number): Promise<void> {
    const t: DownloadTask | undefined = this.findTask(id);
    if (t !== undefined && t.state === 'paused') {
      t.state = 'queued';
      t.done = 0;
      t.failedPages = 0;
      t.error = '';
      this.notify(t);
      this.scheduleSave();
      this.startWorker();
    }
  }

  /** 取消（原 cancel :136-141；进行中协作中止并清临时文件） */
  async cancel(id: number): Promise<void> {
    const t: DownloadTask | undefined = this.findTask(id);
    if (t !== undefined && t.state !== 'done' && t.state !== 'failed' && t.state !== 'canceled') {
      t.state = 'canceled';
      this.notify(t);
      this.scheduleSave();
    }
  }

  /** 删除任务：进行中/排队先置 canceled；deleteFile 同时删除产物（:148-158） */
  async removeTask(id: number, deleteFile: boolean): Promise<void> {
    const t: DownloadTask | undefined = this.findTask(id);
    if (t === undefined) {
      return;
    }
    if (t.state === 'running' || t.state === 'queued' || t.state === 'paused') {
      t.state = 'canceled';
    }
    if (this.activeTaskId !== id) { this.cleanupTempFiles(id); }
    if (deleteFile) {
      if (t.state === 'done' || t.savedTo !== '') { await offlineStore.remove(t.albumId); }
      if (t.savedTo !== '' && fileExists(t.savedTo)) { fs.unlinkSync(t.savedTo); }
    }
    this.tasks = this.tasks.filter((it: DownloadTask) => it.id !== id);
    this.scheduleSave();
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
    const prefs: Prefs = await Prefs.getInstance();
    const snapshots: Array<DownloadTask> = [];
    for (const t of this.tasks) {
      snapshots.push(cloneTask(t));
    }
    await prefs.putString(PrefKeys.DOWNLOAD_TASKS, JSON.stringify(snapshots));
  }

  /** 单飞 worker：循环取第一个 QUEUED（DownloadQueue.kt:202-212） */
  private startWorker(): void {
    if (this.workerActive) {
      return;
    }
    this.workerActive = true;
    const self: DownloadManager = this;
    const loop: Promise<void> = (async (): Promise<void> => {
      for (;;) {
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
    loop.catch((e: Error) => {
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
        if (e instanceof DownloadAbortError) {
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
  private async runTask(task: DownloadTask): Promise<void> {
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
    try {
      // 1) 本子信息（网络重试 3 次）
      const album: Album | null = await this.retryNet<Album>(3, (): Promise<Album> => jmApi.album(task.albumId));
      if (album === null) {
        throw new Error('获取本子信息失败');
      }

      // 2) 汇集全部页（含乱序参数）
      const pages: Array<ChapterPage> = [];
      for (const ep of album.episodes) {
        this.checkAbort(taskId);
        const images: Array<string> | null = await this.retryNet<Array<string>>(
          3, (): Promise<Array<string>> => jmApi.chapterImages(ep.id));
        if (images === null || images.length === 0) {
          const label: string = ep.title !== '' ? ep.title : ep.id;
          throw new Error(`章节图片获取失败：${label}`);
        }
        const sid: number = await jmApi.scrambleId(ep.id);
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
      for (let idx: number = 0; idx < pages.length; idx++) {
        const pageIdx: number = idx;
        const ref: ChapterPage = pages[pageIdx];
        const job: Promise<void> = (async (): Promise<void> => {
          await sem.acquire();
          try {
            this.checkAbort(taskId);
            const outFile: string = `${tmpDir}/${pad5(pageIdx)}.bin`;
            let ok: boolean = false;
            // ① 页缓存原始字节复用（>1KB 才算命中）
            try {
              const cached: string | null = cachedRawFilePath(ref.photoId, ref.filename);
              if (cached !== null) {
                fs.copyFileSync(cached, outFile);
                ok = fs.statSync(outFile).size > 1024;
              }
            } catch (e) {
              // 缓存复用失败走网络
            }
            // ② 网络：换域名重试 3 次
            if (!ok) {
              for (let attempt: number = 0; attempt <= 2; attempt++) {
                this.checkAbort(taskId);
                try {
                  const bytes: ArrayBuffer = await jmApi.fetchPage(ref.photoId, ref.filename, attempt);
                  this.checkAbort(taskId);
                  if (bytes.byteLength === 0) { throw new Error('页面内容为空'); }
                  writeFileBytes(outFile, bytes);
                  ok = true;
                  break;
                } catch (e) {
                  if (e instanceof DownloadAbortError) { throw e; }
                  if (attempt === 2 || /登录|认证|401|403/.test(errorMessage(e as Error))) {
                    pageErrors.push(e as Error); break;
                  }
                }
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
        return self.makeArchiveEntry(`${tmpDir}/${pad5(index)}.bin`, pages[index], index, imgQ).then(
          (entry: ZipEntry | null): Promise<ZipEntry | null> => {
            self.checkAbort(taskId);
            self.update(taskId, (t: DownloadTask) => {
              t.exportDone = Math.min(index + 1, total);
            });
            return Promise.resolve(entry);
          });
      });

      // 保存到应用 Download 目录（固定沙箱目录）
      const destDir: string = `${ctx.filesDir}/Download/${taskId}`;
      ensureDir(destDir);
      const dest: string = `${destDir}/${safeFileName(album.name)}`;
      await offlineStore.install(album, pages, pages.map((p: ChapterPage, index: number) => `${tmpDir}/${pad5(index)}.bin`), (): void => { this.checkAbort(taskId); });
      this.checkAbort(taskId);
      fs.copyFileSync(outTemp, dest);
      rmTree(tmpDir);
      try {
        fs.unlinkSync(outTemp);
      } catch (e) {
        // 临时文件清理失败可忽略
      }
      const doneFinal: number = Math.max(total - failCnt, 0);
      this.update(taskId, (t: DownloadTask) => {
        t.state = 'done';
        t.exporting = false;
        t.savedTo = dest;
        t.done = doneFinal;
      });
      await this.persistTasks();
    } catch (e) {
      const err: Error = e as Error;
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
        this.cleanupTempFiles(taskId);
      }
    } finally {
      this.activeTaskId = 0;
    }
  }

  /**
   * 单条 CBZ 条目：解码 + 反混淆 + 按源格式重编码（archiveEntry :508-576 的 visual/compact 档）。
   * 源 jpg/jpeg → JPEG q95/85；其它 → WebP q95/80。缺失或解码失败时停止导出，避免发布残缺文件。
   * 条目名带全局序号前缀 pad5(idx+1)_：JM 每章文件名都从 00001 重新编号，整本摊平导出到
   * 同一 ZIP 时必须消歧，否则跨章节重名导致部分阅读器丢页（Review H-1）。
   */
  private async makeArchiveEntry(binPath: string, ref: ChapterPage, idx: number,
    imgQ: string): Promise<ZipEntry | null> {
    const dot: number = ref.filename.lastIndexOf('.');
    const srcExt: string = dot >= 0 ? ref.filename.substring(dot + 1).toLowerCase() : '';
    const wantJpeg: boolean = srcExt === 'jpg' || srcExt === 'jpeg';
    let packed: ArrayBuffer | null = null;
    let ext: string = wantJpeg ? '.jpg' : '.webp';
    if (fileExists(binPath)) {
      try {
        const bytes: ArrayBuffer = readFileBytes(binPath);
        const pm: image.PixelMap | null = await descrambleFromBytes(bytes, ref.photoId, ref.filename, ref.scrambleId);
        if (pm !== null) {
          try {
            if (wantJpeg) {
              packed = await packImage(pm, 'image/jpeg', imgQ === 'compact' ? 85 : 95);
            } else {
              packed = await packImage(pm, 'image/webp', imgQ === 'compact' ? 80 : 95);
            }
          } finally {
            await pm.release();
          }
        }
      } catch (e) { throw new Error(`第 ${idx + 1} 页解码失败：${errorMessage(e as Error)}`); }
    }
    if (packed === null) {
      throw new Error(`第 ${idx + 1} 页文件缺失`);
    }
    return new ZipEntry(`${pad5(idx + 1)}${ext}`, packed);
  }
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
