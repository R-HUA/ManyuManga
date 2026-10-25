import image from '@ohos.multimedia.image';
import { Prefs, PrefKeys } from '../util/Prefs';
/** 内存 LRU 上限 96MB，按 getPixelBytesNumber 计（PageLoader.kt:46-48） */
const MEMORY_CAP: number = 96 * 1024 * 1024;
/** 解码并发默认 4（PageLoader.kt:34） */
const SEM_DEFAULT: number = 4;
/** 用户设置 1..512 时取设置值但封顶 32（PageLoader.kt:38） */
const SEM_USER_MIN: number = 1;
const SEM_USER_MAX: number = 512;
const SEM_CEIL: number = 32;

/** 异步计数信号量（对应 kotlinx.coroutines.sync.Semaphore + withPermit） */
export class DecodeSemaphore {
  private permits: number = 0;
  private waiters: Array<() => void> = [];

  constructor(permits: number) {
    this.permits = permits;
  }

  acquire(): Promise<void> {
    if (this.permits > 0) {
      this.permits--;
      return Promise.resolve();
    }
    return new Promise<void>((resolve: (value: void) => void) => {
      this.waiters.push(resolve);
    });
  }

  release(): void {
    const next: (() => void) | undefined = this.waiters.shift();
    if (next !== undefined) {
      next(); // 许可直接移交给等待者，总量不变
      return;
    }
    this.permits++;
  }
}

let semMax: number = SEM_DEFAULT;
let decodeSem: DecodeSemaphore = new DecodeSemaphore(SEM_DEFAULT);

/**
 * 取当前信号量：读用户并发设置（0=自动→4；1..512 封顶 32），设置变化时换新信号量
 * 偏好读取失败保持现值。
 */
export async function semFor(): Promise<DecodeSemaphore> {
  try {
    const prefs: Prefs = await Prefs.getInstance();
    const raw: number = await prefs.getNumber(PrefKeys.DECODE_CONCURRENCY, 0);
    let want: number = SEM_DEFAULT;
    if (raw >= SEM_USER_MIN && raw <= SEM_USER_MAX) {
      want = raw > SEM_CEIL ? SEM_CEIL : raw;
    }
    if (want !== semMax) {
      semMax = want;
      decodeSem = new DecodeSemaphore(want);
    }
  } catch (e) {
    // 偏好未初始化（上下文未注入）等场景沿用默认信号量
  }
  return decodeSem;
}

/**
 * PixelMap 内存 LRU：键 `"{photoId}/{filename}@{scrambleId}@{targetWidth}"`
 * 容量按像素字节数计、96MB 上限、淘汰最旧。
 *
 * ★ 所有权约定（引用计数）：旧版命中/写入各克隆一份整图（主线程数 MB memcpy，翻页掉帧），
 *   现改为缓存与调用方共享同一实例——外借时 borrows+1，调用方必须经 releasePagePixelMap(pm)
 *   归还（borrows-1）；条目被 LRU 淘汰时若仍有外借则挂起，待最后一笔归还后才真正 release
 *   底层位图。命中与写入均为零拷贝。
 */
class RefEntry {
  readonly pm: image.PixelMap;
  readonly bytes: number;
  borrows: number = 0; // 外借中的调用方数
  inCache: boolean = true; // 仍在 LRU 表内（false = 已淘汰，等外借全部归还后释放）
  disposed: boolean = false;

  constructor(pm: image.PixelMap, bytes: number) {
    this.pm = pm;
    this.bytes = bytes;
  }
}

/** 外借登记：pm 实例 → 所属条目（releasePagePixelMap 反查归还） */
const leased: Map<image.PixelMap, RefEntry> = new Map<image.PixelMap, RefEntry>();

function borrowEntry(e: RefEntry): void {
  e.borrows++;
  leased.set(e.pm, e);
}

function releaseEntryPm(e: RefEntry): void {
  if (e.disposed) {
    return;
  }
  e.disposed = true;
  leased.delete(e.pm);
  e.pm.release().catch((_err: Error): void => {
  });
}

/**
 * 判断 PixelMap 是否仍然有效（防止已被释放的实例继续读取导致 info.size 报错）
 */
export function isPixelMapValid(pm: image.PixelMap | null | undefined): boolean {
  if (pm === null || pm === undefined) {
    return false;
  }
  try {
    const info: image.ImageInfo | undefined = pm.getImageInfoSync();
    return info !== undefined && info !== null && info.size !== undefined && info.size.width > 0 && info.size.height > 0;
  } catch (_e) {
    return false;
  }
}

/**
 * 归还借出的页位图
 * 仅在已不在缓存且无其他外借引用时释放底层资源
 */
export function releasePagePixelMap(pm: image.PixelMap): void {
  const e: RefEntry | undefined = leased.get(pm);
  if (e === undefined) {
    pm.release().catch((_err: Error): void => {
    });
    return;
  }
  e.borrows = Math.max(0, e.borrows - 1);
  if (e.borrows <= 0 && !e.inCache) {
    releaseEntryPm(e);
  }
}

class PixelMapLru {
  private entries: Map<string, RefEntry> = new Map<string, RefEntry>();
  private total: number = 0;
  private cap: number = 0;

  constructor(capBytes: number) {
    this.cap = capBytes;
  }

  /** 借出：命中刷新 LRU 顺序并登记外借；未命中返回 null */
  acquire(key: string): RefEntry | null {
    const e: RefEntry | undefined = this.entries.get(key);
    if (e === undefined) {
      return null;
    }
    this.entries.delete(key);
    this.entries.set(key, e);
    return e;
  }

  /** 驱逐指定条目 */
  evict(key: string): void {
    const e: RefEntry | undefined = this.entries.get(key);
    if (e !== undefined) {
      this.entries.delete(key);
      this.total -= e.bytes;
      e.inCache = false;
      if (e.borrows <= 0) {
        releaseEntryPm(e);
      }
    }
  }

  /**
   * 发布新解码结果：入表并外借给发布方。
   */
  publish(key: string, pm: image.PixelMap, byteCount: number): RefEntry | null {
    if (byteCount <= 0 || byteCount > MEMORY_CAP) {
      return null;
    }
    const existing: RefEntry | undefined = this.entries.get(key);
    if (existing !== undefined) {
      pm.release().catch((err: Error): void => {
      });
      borrowEntry(existing);
      return existing;
    }
    const e: RefEntry = new RefEntry(pm, byteCount);
    this.entries.set(key, e);
    this.total += byteCount;
    this.trim();
    borrowEntry(e);
    return e;
  }

  /** 超限时自最旧起淘汰 */
  private trim(): void {
    if (this.total <= this.cap) {
      return;
    }
    const keys: Array<string> = [];
    this.entries.forEach((_e: RefEntry, k: string) => {
      keys.push(k);
    });
    for (const k of keys) {
      if (this.total <= this.cap) {
        break;
      }
      const e: RefEntry | undefined = this.entries.get(k);
      this.entries.delete(k);
      if (e === undefined) {
        continue;
      }
      this.total -= e.bytes;
      e.inCache = false;
      if (e.borrows <= 0) {
        releaseEntryPm(e);
      }
    }
  }
}

const memCache: PixelMapLru = new PixelMapLru(MEMORY_CAP);

/** 内存缓存键 */
export function memoryKey(photoId: string, filename: string, scrambleId: number, targetWidth: number): string {
  return `${photoId}/${filename}@${scrambleId}@${targetWidth}`;
}

/** 命中内存缓存：登记外借后零拷贝返回；未命中返回 null */
export async function takeFromMemory(key: string): Promise<image.PixelMap | null> {
  const e: RefEntry | null = memCache.acquire(key);
  if (e === null) {
    return null;
  }
  if (!isPixelMapValid(e.pm)) {
    memCache.evict(key);
    return null;
  }
  borrowEntry(e);
  return e.pm;
}

/** 解码结果发布入内存缓存并借出（同键竞态时释放后来者、借出既有条目）；超预算不入表返回 null */
export function publishIntoMemory(key: string, pm: image.PixelMap): image.PixelMap | null {
  let bytes: number = 0;
  try {
    bytes = pm.getPixelBytesNumber();
  } catch (e) {
    return null;
  }
  if (bytes <= 0 || bytes > MEMORY_CAP) {
    return null; // 单项超总预算不入缓存
  }
  const e: RefEntry | null = memCache.publish(key, pm, bytes);
  return e === null ? null : e.pm;
}
