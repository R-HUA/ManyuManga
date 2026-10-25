import fs from '@ohos.file.fs';
import filePicker from '@ohos.file.picker';
import { DownloadTask } from '../../data/DownloadManager';

function fileNameOf(path: string): string {
  const parts: Array<string> = path.split('/');
  const name: string | undefined = parts.pop();
  return name === undefined ? 'download.cbz' : name;
}

function copyFileByChunk(srcFd: number, dstFd: number, total: number): number {
  fs.copyFileSync(srcFd, dstFd);
  return fs.statSync(dstFd).size;
}

export async function saveDownload(t: DownloadTask): Promise<boolean> {
    let src: fs.File | null = null;
    let dst: fs.File | null = null;
    try {
      const st: fs.Stat = fs.statSync(t.savedTo);
      const picker: filePicker.DocumentViewPicker = new filePicker.DocumentViewPicker();
      const opt: filePicker.DocumentSaveOptions = new filePicker.DocumentSaveOptions();
      opt.newFileNames = [fileNameOf(t.savedTo)];
      const uris: Array<string> = await picker.save(opt);
      if (uris.length === 0) {
        return false; // 用户取消
      }
      src = fs.openSync(t.savedTo, fs.OpenMode.READ_ONLY);
      dst = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      const copied: number = copyFileByChunk(src.fd, dst.fd, st.size);
      if (copied !== st.size) {
        throw new Error(`保存不完整（${copied}/${st.size}）`);
      }
      return true;

    } finally {
      if (src !== null) {
        try {
          fs.closeSync(src);
        } catch (e) {
          // 关闭失败忽略
        }
      }
      if (dst !== null) {
        try {
          fs.closeSync(dst);
        } catch (e) {
          // 关闭失败忽略
        }
      }
    }
}
