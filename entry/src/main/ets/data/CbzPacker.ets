import fs from '@ohos.file.fs';
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
