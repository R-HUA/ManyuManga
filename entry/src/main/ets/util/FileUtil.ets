import fs from '@ohos.file.fs';

export function fileExists(path: string): boolean {
  try {
    fs.statSync(path);
    return true;
  } catch (e) {
    return false;
  }
}

export function ensureDir(path: string): void {
  if (path === '' || fileExists(path)) {
    return;
  }
  ensureDir(parentDir(path));
  try {
    fs.mkdirSync(path);
  } catch (e) {
    // 已存在等竞态可忽略
  }
}

export function parentDir(path: string): string {
  const idx: number = path.lastIndexOf('/');
  if (idx <= 0) {
    return '';
  }
  return path.substring(0, idx);
}

export function readFileBytes(path: string): ArrayBuffer {
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

export function writeFileBytes(path: string, data: ArrayBuffer): void {
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  const fd: number = file.fd;
  try {
    fs.writeSync(fd, data);
  } finally {
    fs.closeSync(file);
  }
}

export function rmTree(path: string): void {
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
    // 清理失败静默（对应原 runCatching）
  }
}
