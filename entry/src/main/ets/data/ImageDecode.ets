import { DecodeSemaphore, semFor, memoryKey, takeFromMemory, publishIntoMemory, releasePagePixelMap, isPixelMapValid } from './PageCachePool';
import { fileExists, ensureDir, parentDir, readFileBytes, writeFileBytes, rmTree } from '../util/FileUtil';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import { md5Hex } from './JmApi';
import { sourceApi } from './SourceApi';
import { sourceId, nativeId } from './Sources';
import { Prefs, getAppContext } from '../util/Prefs';
export { releasePagePixelMap, isPixelMapValid } from './PageCachePool';
const SCRAMBLE_268850: number = 268850;
const SCRAMBLE_421926: number = 421926;

/** 缩略图判定上限（targetWidth ≤ 720 视为缩略图，走缩略图磁盘缓存）（PageLoader.kt:50） */
const THUMB_MAX: number = 720;
/** 磁盘页缓存总量上限 512MB，超限删最旧至 ≤90%（PageLoader.kt:50,181-197） */
const DISK_CAP: number = 512 * 1024 * 1024;
const TRIM_INTERVAL_MS: number = 15000;

let lastTrimAt: number = 0;

// ─────────────── 解码并发信号量 + 内存 LRU ───────────────

/**
 * 计算分段数（0 表示无需重排）。对应 JmImageDecoder.segments（JmImageDecoder.kt:22-33）。
 */
const segmentsCache: Map<string, number> = new Map();

/** Review M-2：段数只由三元组决定，进程内缓存避免每页重复 md5 同步计算 */
export function computeSegments(scrambleId: number, photoId: string, filename: string): number {
  const cacheKey: string = `${scrambleId}/${photoId}/${filename}`;
  const hit: number | undefined = segmentsCache.get(cacheKey);
  if (hit !== undefined) {
    return hit;
  }
  const seg: number = computeSegmentsUncached(scrambleId, photoId, filename);
  if (segmentsCache.size > 2000) {
    segmentsCache.clear();
  }
  segmentsCache.set(cacheKey, seg);
  return seg;
}

function computeSegmentsUncached(scrambleId: number, photoId: string, filename: string): number {
  const t: string = photoId.trim();
  if (!/^[0-9]+$/.test(t)) {
    return 0; // 对应 toLongOrNull 失败 → 0
  }
  const pid: number = parseInt(t);
  if (pid < scrambleId) {
    return 0; // 老图无加密
  }
  if (pid < SCRAMBLE_268850) {
    return 10; // 固定 10 段（旧规则）
  }
  const x: number = pid < SCRAMBLE_421926 ? 10 : 8; // 新规则：哈希取模基数
  // ★ 官方算法参与 md5 的是不带扩展名的文件名
  const dot: number = filename.lastIndexOf('.');
  const nameNoSuffix: string = dot >= 0 ? filename.substring(0, dot) : filename;
  const h: string = md5Hex(`${pid}${nameNoSuffix}`);
  const n: number = h.charCodeAt(h.length - 1) % x;
  return n * 2 + 2;
}

/** PixelMap 支持逐带读写的像素格式白名单；其它格式保守原样返回 */
function mappableFormat(fmt: image.PixelMapFormat): image.PixelMapFormat | null {
  if (fmt === image.PixelMapFormat.RGBA_8888) {
    return image.PixelMapFormat.RGBA_8888;
  }
  if (fmt === image.PixelMapFormat.BGRA_8888) {
    return image.PixelMapFormat.BGRA_8888;
  }
  if (fmt === image.PixelMapFormat.RGB_565) {
    return image.PixelMapFormat.RGB_565;
  }
  return null;
}

/**
 * 还原乱序图片（垂直带级倒序重排，含余数处理）。
 * 对应 JmImageDecoder.decode（JmImageDecoder.kt:36-66）。
 * segments<=0 / 高度不足 / 不支持格式时原样返回（不 release 原图）。
 * 重排成功时原图已 release，调用方只需持有返回值。
 */
export async function descramble(src: image.PixelMap, segments: number): Promise<image.PixelMap> {
  if (segments <= 0) {
    return src;
  }
  const info: image.ImageInfo = src.getImageInfoSync();
  const w: number = info.size.width;
  const h: number = info.size.height;
  if (w <= 0 || h <= 0 || h < segments) {
    return src;
  }
  const fmt: image.PixelMapFormat | null = mappableFormat(info.pixelFormat);
  if (fmt === null) {
    return src;
  }
  const rowBytes: number = Math.floor(src.getPixelBytesNumber() / h);
  if (rowBytes <= 0) {
    return src;
  }
  const baseMove: number = Math.floor(h / segments);
  const over: number = h % segments;
  // 最大单带行数（第 0 段含余数），+1 行冗余
  const maxRows: number = baseMove + over + 1;
  const bandBuf: ArrayBuffer = new ArrayBuffer(rowBytes * maxRows);
  // 输出底图（透明初始化，随后被各带完整覆盖）
  const initBuf: ArrayBuffer = new ArrayBuffer(rowBytes * h);
  const opts: image.InitializationOptions = {
    size: { width: w, height: h },
    pixelFormat: fmt
  };
  const dst: image.PixelMap = await image.createPixelMap(initBuf, opts);
  for (let i: number = 0; i < segments; i++) {
    let move: number = baseMove;
    let ySrc: number = h - move * (i + 1) - over; // 源条带顶部（自底向上数）
    let yDst: number = move * i; // 目标条带顶部（自顶向下数）
    if (i === 0) {
      move += over; // 余数行并入第 0 段
    } else {
      yDst += over; // 其余段整体下移 over
    }
    if (move <= 0) {
      continue;
    }
    if (ySrc < 0) {
      ySrc = 0;
    }
    const srcRegion: image.Region = { x: 0, y: ySrc, size: { width: w, height: move } };
    // ★ stride 为每行【字节数】（官方 PositionArea 契约），必须 ≥ region 宽度字节数：
    //   RGBA_8888/BGRA_8888 需 4×w、RGB_565 需 2×w，传像素宽 w 会违反参数约束（抛错或花屏）
    const readArea: image.PositionArea = { pixels: bandBuf, offset: 0, stride: rowBytes, region: srcRegion };
    await src.readPixels(readArea);
    const dstRegion: image.Region = { x: 0, y: yDst, size: { width: w, height: move } };
    const writeArea: image.PositionArea = { pixels: bandBuf, offset: 0, stride: rowBytes, region: dstRegion };
    await dst.writePixels(writeArea);
  }
  await src.release();
  return dst;
}

/**
 * 网络字节 → 原尺寸解码 → 分块重排 → PixelMap（不做缩放）。
 * 下载导出与"只要原图"的场景使用。
 */
export async function descrambleFromBytes(buf: ArrayBuffer, photoId: string,
  filename: string, scrambleId: number): Promise<image.PixelMap | null> {
  const source: image.ImageSource = image.createImageSource(buf);
  let pm: image.PixelMap | null = null;
  try {
    pm = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
  } finally {
    // 解码抛错也要释放 ImageSource（Review M-3：原生内存泄漏）
    await source.release();
  }
  if (pm === null) {
    return null;
  }
  return sourceId(photoId) === 'jm' ? descramble(pm, computeSegments(scrambleId, nativeId(photoId), filename)) : pm;
}

/**
 * 整链路加载阅读页：网络/缓存字节 → 原尺寸解码 → 反混淆 → 等比缩放到 targetWidth。
 *  - 缓存键 `"{photoId}/{filename}@{scrambleId}@{targetWidth}"`：先查 96MB 内存 LRU（克隆交接，
 *    信号量外快路径 + 取得许可后二次确认）；命中直接返回；
 *  - 整个"缩略图磁盘缓存 → 取字节 → 解码 → 重排 → 缩放"全程持解码信号量
 *    （默认 4；用户设置 1..512 封顶 32，PageLoader.kt:31-48），并发与内存峰值受控；
 *  - targetWidth ∈ 1..720 视为缩略图：先查缩略图磁盘缓存 {filename}.t{w}-s{id}.jpg，命中直接返回；
 *  - 原图字节三级来源：页缓存 → 网络（换域名重试 3 次）；autoCache 开启时写页缓存并触发 trim；
 *  - 生成缩略图后以 JPEG q82 落盘，下次秒开。
 */
const THUMB_TIERS: number[] = [96, 160, 240, 320, 480, 640, 720];

/** 宽度档位化（Review M-4）：缩略图吸附固定档、大图吸附 120 倍数，降低内存/磁盘缓存键离散度提高命中率 */
function snapWidthTier(w: number): number {
  if (w <= 0) {
    return 0;
  }
  if (w > THUMB_MAX) {
    return Math.ceil(w / 120) * 120;
  }
  for (const t of THUMB_TIERS) {
    if (w <= t) {
      return t;
    }
  }
  return THUMB_MAX;
}

export async function loadPagePixelMap(photoId: string, filename: string,
  scrambleId: number, targetWidth: number): Promise<image.PixelMap | null> {
  targetWidth = snapWidthTier(targetWidth);
  const key: string = memoryKey(photoId, filename, scrambleId, targetWidth);
  // 内存缓存快路径（信号量外，PageLoader.kt:64）
  const fast: image.PixelMap | null = await takeFromMemory(key);
  if (fast !== null) {
    return fast;
  }
  const sem: DecodeSemaphore = await semFor();
  await sem.acquire();
  try {
    // 二次确认（PageLoader.kt:66）：等信号量期间其它加载可能已把同键结果放入内存缓存
    const again: image.PixelMap | null = await takeFromMemory(key);
    if (again !== null) {
      return again;
    }
    const isThumb: boolean = targetWidth >= 1 && targetWidth <= THUMB_MAX;
    if (isThumb) {
      const thumbPath: string | null = pageThumbPath(photoId, filename, targetWidth, scrambleId);
      if (thumbPath !== null && fileExists(thumbPath)) {
        const cached: image.PixelMap | null = await decodeFileAsync(thumbPath);
        if (cached !== null) {
          const borrowed: image.PixelMap | null = publishIntoMemory(key, cached);
          return borrowed !== null ? borrowed : cached;
        }
      }
    }
    const bytes: ArrayBuffer | null = await fetchPageBytes(photoId, filename);
    if (bytes === null) {
      return null;
    }
    let pm: image.PixelMap | null = await descrambleFromBytes(bytes, photoId, filename, scrambleId);
    if (pm === null) {
      return null;
    }
    const info: image.ImageInfo = pm.getImageInfoSync();
    const w: number = info.size.width;
    if (targetWidth >= 1 && targetWidth < w && w > 0) {
      const ratio: number = targetWidth / w;
      await pm.scale(ratio, ratio);
    }
    if (isThumb) {
      const prefs: Prefs = await Prefs.getInstance();
      if (await prefs.autoCache()) {
        try {
          const packed: ArrayBuffer = await packToJpeg(pm, 82);
          const thumbPath: string | null = pageThumbPath(photoId, filename, targetWidth, scrambleId);
          if (thumbPath !== null) {
            ensureDir(parentDir(thumbPath));
            writeFileBytes(thumbPath, packed);
          }
        } catch (e) {
          // 缩略图落盘失败可忽略
        }
      }
    }
    // 结果发布入内存 LRU 并借出（零拷贝共享；调用方用 releasePagePixelMap 归还）
    const published: image.PixelMap | null = publishIntoMemory(key, pm);
    return published !== null ? published : pm;
  } finally {
    sem.release();
  }
}

// ───────────────────────── 页缓存（PageLoader.kt:134-197 对应） ─────────────────────────

function pageCacheRoot(): string {
  return `${getAppContext().filesDir}/page_cache`;
}

/** 来源与页面地址共同决定缓存身份，避免不同书源同编号覆盖。 */
function pageCacheFile(photoId: string, filename: string): string | null {
  const id: string = md5Hex(photoId);
  const name: string = md5Hex(filename);
  return `${pageCacheRoot()}/${id}/${name}`;
}

/** 缩略图按原始页面、尺寸与反混淆参数分别缓存。 */
function pageThumbPath(photoId: string, filename: string, width: number, scrambleId: number): string | null {
  const id: string = md5Hex(photoId);
  const name: string = md5Hex(filename);
  return `${pageCacheRoot()}/${id}/${name}.t${width}-s${scrambleId}.jpg`;
}

/** 查"原始乱序字节"缓存（>1KB 才算命中），返回文件路径；下载队列复用（PageLoader.cachedRawFile） */
export function cachedRawFilePath(photoId: string, filename: string): string | null {
  const f: string | null = pageCacheFile(photoId, filename);
  if (f === null) {
    return null;
  }
  try {
    const stat: fs.Stat = fs.statSync(f);
    if (stat.size > 1024) {
      return f;
    }
  } catch (e) {
    // 不存在
  }
  return null;
}

/**
 * 原图字节来源：页缓存 → 网络（换域名重试 3 次）；成功且 autoCache 开启时写缓存并 trim。
 */
export async function fetchPageBytes(photoId: string, filename: string): Promise<ArrayBuffer | null> {
  const cacheFile: string | null = pageCacheFile(photoId, filename);
  if (cacheFile === null) {
    // photoId/filename 未过白名单（服务端可控）：整页按失败处理，不落盘（Review H-4）
    return null;
  }
  if (fileExists(cacheFile)) {
    try {
      return readFileBytes(cacheFile);
    } catch (e) {
      // 缓存损坏则走网络
    }
  }
  let lastError: Error = new Error('页面下载失败');
  for (let attempt: number = 0; attempt <= 2; attempt++) {
    try {
      const bytes: ArrayBuffer = await sourceApi.fetchPage(photoId, filename, attempt);
      if (bytes.byteLength > 0) {
        const prefs: Prefs = await Prefs.getInstance();
        if (await prefs.autoCache()) {
          try {
            ensureDir(parentDir(cacheFile));
            writeFileBytes(cacheFile, bytes);
            trimDiskCache();
          } catch (e) {
            // 写缓存失败不影响返回
          }
        }
        return bytes;
      }
    } catch (e) {
      lastError = e as Error;
      if (/登录|认证|401|403/.test(lastError.message)) { throw lastError; }
    }
  }
  throw lastError;
}

/** 白边裁剪使用独立位图，避免改变由多个页面共享的缓存。 */
export async function cropPageWhitespace(original: image.PixelMap): Promise<image.PixelMap> {
  const info: image.ImageInfo = original.getImageInfoSync();
  const width: number = info.size.width;
  const height: number = info.size.height;
  const buffer: ArrayBuffer = new ArrayBuffer(width * height * 4);
  await original.readPixelsToBuffer(buffer);
  const pixels: Uint8Array = new Uint8Array(buffer);
  let left: number = width; let right: number = -1; let top: number = height; let bottom: number = -1;
  for (let y: number = 0; y < height; y++) {
    for (let x: number = 0; x < width; x++) {
      const offset: number = (y * width + x) * 4;
      if (pixels[offset + 3] > 20 && (pixels[offset] < 245 || pixels[offset + 1] < 245 || pixels[offset + 2] < 245)) {
        left = Math.min(left, x); right = Math.max(right, x); top = Math.min(top, y); bottom = Math.max(bottom, y);
      }
    }
  }
  const copy: image.PixelMap = await image.createPixelMap(buffer, { size: info.size, pixelFormat: image.PixelMapFormat.RGBA_8888, editable: true });
  if (right >= left && bottom >= top) { await copy.crop({ x: left, y: top, size: { width: right - left + 1, height: bottom - top + 1 } }); }
  return copy;
}

/** 清空页缓存（设置页"缓存清理"用） */
export function clearPageCache(): void {
  rmTree(pageCacheRoot());
}

/** 页缓存目录当前占用字节数（诊断/设置页展示） */
export function pageCacheSize(): number {
  const files: Array<FileMeta> = [];
  walkFiles(pageCacheRoot(), files);
  let total: number = 0;
  for (const f of files) {
    total += f.size;
  }
  return total;
}

class FileMeta {
  path: string = '';
  size: number = 0;
  mtime: number = 0;
}

/** 512MB 上限，删最旧（mtime）直到 ≤90%；15s 节流（PageLoader.kt:181-197） */
function trimDiskCache(): void {
  const now: number = Date.now();
  if (now - lastTrimAt < TRIM_INTERVAL_MS) {
    return;
  }
  lastTrimAt = now;
  try {
    const files: Array<FileMeta> = [];
    walkFiles(pageCacheRoot(), files);
    let total: number = 0;
    for (const f of files) {
      total += f.size;
    }
    if (total <= DISK_CAP) {
      return;
    }
    files.sort((a: FileMeta, b: FileMeta) => a.mtime - b.mtime);
    for (const f of files) {
      if (total <= Math.floor(DISK_CAP * 9 / 10)) {
        break;
      }
      try {
        fs.unlinkSync(f.path);
        total -= f.size;
      } catch (e) {
        // 删除失败继续下一个
      }
    }
  } catch (e) {
    // trim 失败静默
  }
}

function walkFiles(root: string, out: Array<FileMeta>): void {
  let names: Array<string> = [];
  try {
    names = fs.listFileSync(root);
  } catch (e) {
    return;
  }
  for (const name of names) {
    const full: string = `${root}/${name}`;
    try {
      const stat: fs.Stat = fs.statSync(full);
      if (stat.isDirectory()) {
        walkFiles(full, out);
      } else {
        const meta: FileMeta = new FileMeta();
        meta.path = full;
        meta.size = stat.size;
        meta.mtime = stat.mtime;
        out.push(meta);
      }
    } catch (e) {
      // 单项失败跳过
    }
  }
}

/** 从文件解码 PixelMap（缩略图缓存命中路径）；失败返回 null */
async function decodeFileAsync(path: string): Promise<image.PixelMap | null> {
  try {
    const bytes: ArrayBuffer = readFileBytes(path);
    const source: image.ImageSource = image.createImageSource(bytes);
    try {
      return await source.createPixelMap();
    } finally {
      await source.release();
    }
  } catch (e) {
    return null;
  }
}

/** PixelMap → JPEG 字节（缩略图落盘 / CBZ 导出共用） */
export async function packToJpeg(pm: image.PixelMap, quality: number): Promise<ArrayBuffer> {
  return packImage(pm, 'image/jpeg', quality);
}

export async function packImage(pm: image.PixelMap, format: string, quality: number): Promise<ArrayBuffer> {
  const packer: image.ImagePacker = image.createImagePacker();
  try {
    const opt: image.PackingOption = { format: format, quality: quality };
    return await packer.packToData(pm, opt);
  } finally {
    await packer.release();
  }
}
