import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import { ChapterPage, errorMessage } from '../models/Models';
import { rmTree } from '../util/FileUtil';
import { descrambleFromBytes, packImage } from './ImageDecode';

const IO_CHUNK: number = 256 * 1024;

/** 不指定 offset，使用 SDK 文件指针语义；短写后仅重写尚未写出的字节。 */
export async function writeAll(fd: number, data: ArrayBuffer, validate: () => void = (): void => {}): Promise<void> {
  let offset: number = 0;
  while (offset < data.byteLength) {
    validate();
    const chunk: ArrayBuffer = data.slice(offset, Math.min(offset + IO_CHUNK, data.byteLength));
    const count: number = await fs.write(fd, chunk);
    if (count <= 0 || count > chunk.byteLength) { throw new Error('文件写入不完整'); }
    offset += count;
  }
}

export async function readBytesAsync(path: string, validate: () => void = (): void => {}): Promise<ArrayBuffer> {
  validate();
  const file: fs.File = await fs.open(path, fs.OpenMode.READ_ONLY);
  try {
    const size: number = (await fs.stat(file.fd)).size;
    if (size <= 0) { throw new Error('页面文件为空'); }
    const data: Uint8Array = new Uint8Array(size);
    let offset: number = 0;
    while (offset < size) {
      validate();
      const chunk: ArrayBuffer = new ArrayBuffer(Math.min(IO_CHUNK, size - offset));
      const count: number = await fs.read(file.fd, chunk);
      if (count <= 0 || count > chunk.byteLength) { throw new Error('文件读取不完整'); }
      data.set(new Uint8Array(chunk, 0, count), offset);
      offset += count;
    }
    validate();
    return data.buffer;
  } finally {
    await fs.close(file);
  }
}

export async function writeBytesAsync(path: string, data: ArrayBuffer,
  validate: () => void = (): void => {}): Promise<void> {
  validate();
  const file: fs.File = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  let closed: boolean = false;
  let success: boolean = false;
  try {
    await writeAll(file.fd, data, validate);
    validate();
    await fs.close(file);
    closed = true;
    success = true;
  } finally {
    if (!closed) {
      try { await fs.close(file); } catch (e) { console.warn('[Download] 关闭写入文件失败'); }
    }
    if (!success) { rmTree(path); }
  }
}

/** 有界内存异步复制，任何失败都删除本次创建的半成品。 */
export async function copyBytesAsync(src: string, dest: string,
  validate: () => void = (): void => {}): Promise<void> {
  validate();
  let input: fs.File | null = null;
  let output: fs.File | null = null;
  let success: boolean = false;
  try {
    input = await fs.open(src, fs.OpenMode.READ_ONLY);
    const size: number = (await fs.stat(input.fd)).size;
    if (size <= 0) { throw new Error('源文件为空'); }
    validate();
    output = await fs.open(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    let copied: number = 0;
    while (copied < size) {
      validate();
      const buffer: ArrayBuffer = new ArrayBuffer(Math.min(IO_CHUNK, size - copied));
      const read: number = await fs.read(input.fd, buffer);
      if (read <= 0 || read > buffer.byteLength) { throw new Error('源文件读取不完整'); }
      await writeAll(output.fd, buffer.slice(0, read), validate);
      copied += read;
    }
    if ((await fs.stat(output.fd)).size !== size || (await fs.stat(input.fd)).size !== size) {
      throw new Error('复制文件大小校验失败');
    }
    validate();
    await fs.close(input);
    input = null;
    await fs.close(output);
    output = null;
    success = true;
  } finally {
    if (input !== null) { try { await fs.close(input); } catch (e) { console.warn('[Download] 关闭源文件失败'); } }
    if (output !== null) { try { await fs.close(output); } catch (e) { console.warn('[Download] 关闭目标文件失败'); } }
    if (!success && output !== null) { rmTree(dest); }
  }
}

/** 主下载和离线回退导出共用反混淆、编码及安全序号命名。 */
export async function makeArchiveEntry(path: string, page: ChapterPage, index: number, quality: string,
  validate: () => void = (): void => {}): Promise<ZipEntry> {
  const jpeg: boolean = /\.jpe?g$/i.test(page.filename);
  let pixelMap: image.PixelMap | null = null;
  try {
    const bytes: ArrayBuffer = await readBytesAsync(path, validate);
    pixelMap = await descrambleFromBytes(bytes, page.photoId, page.filename, page.scrambleId);
    if (pixelMap === null) { throw new Error('图片无法解码'); }
    validate();
    const encoded: ArrayBuffer = await packImage(pixelMap, jpeg ? 'image/jpeg' : 'image/webp',
      quality === 'compact' ? (jpeg ? 85 : 80) : 95);
    if (encoded.byteLength === 0) { throw new Error('图片编码为空'); }
    validate();
    return new ZipEntry(`${`${index + 1}`.padStart(5, '0')}${jpeg ? '.jpg' : '.webp'}`, encoded);
  } catch (e) {
    validate();
    throw new Error(`第 ${index + 1} 页导出失败：${errorMessage(e as Error)}`);
  } finally {
    if (pixelMap !== null) { await pixelMap.release(); }
  }
}

export function cbzFileName(title: string): string {
  const clean: string = title.replace(/[\\/:*?"<>|\x00-\x1f]/g, '_').trim().substring(0, 80);
  return `${clean || '漫画'}.cbz`;
}

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
export async function writeZipFile(path: string, entryCount: number,
  provider: (index: number) => Promise<ZipEntry | null>, validate: () => void = (): void => {}): Promise<void> {
  if (!Number.isInteger(entryCount) || entryCount < 1 || entryCount > 65535) { throw new Error('漫画包页数超出支持范围'); }
  validate();
  const file: fs.File = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  const fd: number = file.fd;
  let failed: boolean = true;
  let closed: boolean = false;
  try {
    let offset: number = 0;
    const centrals: Array<CentralEntry> = [];
    const names: Set<string> = new Set();
    for (let i: number = 0; i < entryCount; i++) {
      validate();
      const entry: ZipEntry | null = await provider(i);
      if (entry === null) {
        throw new Error(`第 ${i + 1} 页缺失`);
      }
      if (entry.name === '' || /[\\/:\x00-\x1f\x7f]/.test(entry.name) || entry.name === '.' || entry.name === '..' ||
        entry.name.endsWith('.') || entry.name.trim() !== entry.name || /%2e|%2f|%5c/i.test(entry.name) ||
        names.has(entry.name.toLowerCase())) { throw new Error('漫画包包含危险或重复的文件名'); }
      names.add(entry.name.toLowerCase());
      const dataBytes: Uint8Array = new Uint8Array(entry.data);
      const nameBytes: Uint8Array = utf8Bytes(entry.name);
      const crc: number = crc32(dataBytes);
      const size: number = entry.data.byteLength;
      if (nameBytes.length > 65535 || size === 0 || offset + 30 + nameBytes.length + size > 0xFFFFFFFF) {
        throw new Error('漫画包条目为空或超出支持范围');
      }

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
      await writeAll(fd, local, validate);
      await writeAll(fd, nameBytes.buffer, validate);
      await writeAll(fd, entry.data, validate);
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
    if (offset + cdBuf.byteLength + 22 > 0xFFFFFFFF) { throw new Error('漫画包超出支持范围'); }
    await writeAll(fd, cdBuf, validate);
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
    await writeAll(fd, eocd, validate);
    validate();
    if ((await fs.stat(fd)).size !== offset + cdSize + eocd.byteLength) { throw new Error('漫画包写入不完整'); }
    await fs.close(file);
    closed = true;
    failed = false;
  } finally {
    if (!closed) {
      try { await fs.close(file); } catch (e2) { console.warn('[Download] 关闭漫画包失败'); }
    }
    if (failed) {
      // Review M-8：中途失败删除半成品，避免残留同名文件破坏下次导出
      rmTree(path);
    }
  }
}
