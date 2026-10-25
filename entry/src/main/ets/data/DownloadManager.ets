/**
 * data/DownloadManager.ets — 下载队列单例 + 状态机 + CBZ 导出（手写最小 ZIP 写入器）
 *
 *
 */

import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import common from '@ohos.app.ability.common';
import { Prefs, PrefKeys, getAppContext } from '../util/Prefs';
import { sourceApi as jmApi } from './SourceApi';
import { offlineStore } from './OfflineStore';
import { cachedRawFilePath, descrambleFromBytes, packImage } from './ImageDecode';
import { Album, ChapterPage, asArray, asBool, asNumber, asRecord, asString, errorMessage } from '../models/Models';

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

let crcTable: Array<number> | null = null;

function crc32Table(): Array<number> {
  if (crcTable !== null) {
    return crcTable;
  }
  const table: Array<number> = [];
  for (let n: number = 0; n < 256; n++) {
    let c: number = n;
    for (let k: number = 0; k < 8; k++) {
      if (c & 1) {
        c = 0xEDB88320 ^ (c >>> 1);
      } else {
        c = c >>> 1;
      }
    }
    table.push(c);
  }
  crcTable = table;
  return table;
}

function crc32(data: Uint8Array): number {
  const table: Array<number> = crc32Table();
  let crc: number = 0xFFFFFFFF;
  for (let i: number = 0; i < data.length; i++) {
    crc = (crc >>> 8) ^ table[(crc ^ data[i]) & 0xFF];
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

// ───────────────────────── 最小 ZIP 写入器（STORE 不压缩） ─────────────────────────

/** 单个压缩条目（名称 + 字节） */
export class ZipEntry {
  name: string = '';
  data: ArrayBuffer = new ArrayBuffer(0);

  constructor(name: string, data: ArrayBuffer) {
    this.name = name;
    this.data = data;
  }
}

class CentralEntry {
  nameBytes: Uint8Array = new Uint8Array(0);
  crc: number = 0;
  size: number = 0;
  offset: number = 0;
}

/** 固定 DOS 时间戳 */
const DOS_TIME: number = 0;
const DOS_DATE: number = ((2024 - 1980) << 9) | (1 << 5) | 1;

/** 字符串 → UTF-8 字节（返回精确长度的独立 buffer，可直接整块写入文件） */
function utf8Bytes(s: string): Uint8Array {
  const tmp: Uint8Array = new Uint8Array(s.length * 4);
  let n: number = 0;
  for (let i: number = 0; i < s.length; i++) {
    const c: number = s.charCodeAt(i);
    if (c < 0x80) {
      tmp[n++] = c;
    } else if (c < 0x800) {
      tmp[n++] = 0xC0 | (c >> 6);
      tmp[n++] = 0x80 | (c & 0x3F);
    } else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
      const c2: number = s.charCodeAt(i + 1);
      if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
        const cp: number = 0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00);
        tmp[n++] = 0xF0 | (cp >> 18);
        tmp[n++] = 0x80 | ((cp >> 12) & 0x3F);
        tmp[n++] = 0x80 | ((cp >> 6) & 0x3F);
        tmp[n++] = 0x80 | (cp & 0x3F);
        i++;
      } else {
        tmp[n++] = 0xE0 | (c >> 12);
        tmp[n++] = 0x80 | ((c >> 6) & 0x3F);
        tmp[n++] = 0x80 | (c & 0x3F);
      }
    } else {
      tmp[n++] = 0xE0 | (c >> 12);
      tmp[n++] = 0x80 | ((c >> 6) & 0x3F);
      tmp[n++] = 0x80 | (c & 0x3F);
    }
  }
  return tmp.slice(0, n);
}

/**
 * 顺序写入 STORE 型 ZIP（local header + 数据 → central directory → EOCD）。
 * 条目经 provider 逐个产出（内存恒定，不整包驻留）。
 */
async function writeZipFile(path: string, entryCount: number,
  provider: (index: number) => Promise<ZipEntry | null>): Promise<void> {
  // 本 SDK 的 openSync 返回 File（writeSync 仍收 fd number）
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  const fd: number = file.fd;
  let failed: boolean = false;
  try {
    let offset: number = 0;
    const centrals: Array<CentralEntry> = [];
    for (let i: number = 0; i < entryCount; i++) {
      const entry: ZipEntry | null = await provider(i);
      if (entry === null) {
        continue;
      }
      const dataBytes: Uint8Array = new Uint8Array(entry.data);
      const nameBytes: Uint8Array = utf8Bytes(entry.name);
      const crc: number = crc32(dataBytes);
      const size: number = entry.data.byteLength;

      const local: ArrayBuffer = new ArrayBuffer(30);
      const lv: DataView = new DataView(local);
      lv.setUint32(0, 0x04034b50, true); // local file header signature
      lv.setUint16(4, 20, true); // version needed
      lv.setUint16(6, 0x0800, true); // flags: UTF-8 名称
      lv.setUint16(8, 0, true); // method: STORE
      lv.setUint16(10, DOS_TIME, true);
      lv.setUint16(12, DOS_DATE, true);
      lv.setUint32(14, crc, true);
      lv.setUint32(18, size, true); // compressed
      lv.setUint32(22, size, true); // uncompressed
      lv.setUint16(26, nameBytes.length, true);
      lv.setUint16(28, 0, true); // extra len
      fs.writeSync(fd, local);
      fs.writeSync(fd, nameBytes.buffer);
      fs.writeSync(fd, entry.data);
      offset += 30 + nameBytes.length + size;

      const ce: CentralEntry = new CentralEntry();
      ce.nameBytes = nameBytes;
      ce.crc = crc;
      ce.size = size;
      ce.offset = offset - 30 - nameBytes.length - size;
      centrals.push(ce);
    }

    // central directory
    let nameTotal: number = 0;
    for (const ce of centrals) {
      nameTotal += ce.nameBytes.length;
    }
    const cdBuf: ArrayBuffer = new ArrayBuffer(centrals.length * 46 + nameTotal);
    const cd: DataView = new DataView(cdBuf);
    let pos: number = 0;
    for (const ce of centrals) {
      cd.setUint32(pos, 0x02014b50, true);
      cd.setUint16(pos + 4, 20, true); // version made by
      cd.setUint16(pos + 6, 20, true); // version needed
      cd.setUint16(pos + 8, 0x0800, true); // flags
      cd.setUint16(pos + 10, 0, true); // method STORE
      cd.setUint16(pos + 12, DOS_TIME, true);
      cd.setUint16(pos + 14, DOS_DATE, true);
      cd.setUint32(pos + 16, ce.crc, true);
      cd.setUint32(pos + 20, ce.size, true);
      cd.setUint32(pos + 24, ce.size, true);
      cd.setUint16(pos + 28, ce.nameBytes.length, true);
      cd.setUint16(pos + 30, 0, true); // extra
      cd.setUint16(pos + 32, 0, true); // comment
      cd.setUint16(pos + 34, 0, true); // disk start
      cd.setUint16(pos + 36, 0, true); // internal attrs
      cd.setUint32(pos + 38, 0, true); // external attrs
      cd.setUint32(pos + 42, ce.offset, true);
      pos += 46;
      for (let i: number = 0; i < ce.nameBytes.length; i++) {
        cd.setUint8(pos, ce.nameBytes[i]);
        pos++;
      }
    }
    fs.writeSync(fd, cdBuf);
    const cdSize: number = cdBuf.byteLength;

    // EOCD
    const eocd: ArrayBuffer = new ArrayBuffer(22);
    const ev: DataView = new DataView(eocd);
    ev.setUint32(0, 0x06054b50, true);
    ev.setUint16(4, 0, true);
    ev.setUint16(6, 0, true);
    ev.setUint16(8, centrals.length, true);
    ev.setUint16(10, centrals.length, true);
    ev.setUint32(12, cdSize, true);
    ev.setUint32(16, offset, true);
    ev.setUint16(20, 0, true);
    fs.writeSync(fd, eocd);
  } catch (e) {
    failed = true;
    throw e as Error;
  } finally {
    try {
      fs.closeSync(fd);
    } catch (e2) {
      // 关闭失败可忽略
    }
    if (failed) {
      // Review M-8：中途失败删除半成品，避免残留同名文件破坏下次导出
      try {
        fs.unlinkSync(path);
      } catch (e3) {
        // 清理失败可忽略
      }
    }
  }
}

// ───────────────────────── 文件辅助 ─────────────────────────

function fileExists(path: string): boolean {
  try {
    fs.statSync(path);
    return true;
  } catch (e) {
    return false;
  }
}

function ensureDir(path: string): void {
  if (path === '' || fileExists(path)) {
    return;
  }
  ensureDir(path.substring(0, path.lastIndexOf('/')));
  try {
    fs.mkdirSync(path);
  } catch (e) {
    // 竞态可忽略
  }
}

function rmTree(path: string): void {
  if (!fileExists(path)) {
    return;
  }
  try {
    const stat: fs.Stat = fs.statSync(path);
    if (stat.isDirectory()) {
      const names: Array<string> = fs.listFileSync(path);
      for (const name of names) {
        rmTree(`${path}/${name}`);
      }
      fs.rmdirSync(path);
    } else {
      fs.unlinkSync(path);
    }
  } catch (e) {
    // 清理失败静默
  }
}

function readFileBytes(path: string): ArrayBuffer {
  const stat: fs.Stat = fs.statSync(path);
  const buf: ArrayBuffer = new ArrayBuffer(stat.size);
  // 本 SDK 的 openSync 返回 File（readSync/writeSync 仍收 fd number）
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
  const fd: number = file.fd;
  try {
    fs.readSync(fd, buf);
  } finally {
    fs.closeSync(file);
  }
  return buf;
}

function writeFileBytes(path: string, data: ArrayBuffer): void {
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  const fd: number = file.fd;
  try {
    fs.writeSync(fd, data);
  } finally {
    fs.closeSync(file);
  }
}

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

      // 5) 保存到应用 Download 目录（DL-07 简化：固定沙箱目录）
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
