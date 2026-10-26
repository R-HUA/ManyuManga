import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import { common, Want } from '@kit.AbilityKit';
import { cbzFileName, copyBytesAsync, makeArchiveEntry, writeZipFile, ZipEntry } from './CbzPacker';
import { ExportRow, loadCompletePages, loadExportPage, loadOfflineAlbum, OfflineBookRow, OfflinePageRow, saveExport } from './db/ContentDao';
import { ChapterPage } from '../models/Models';
import { fileExists, rmTree } from '../util/FileUtil';
import { getAppContext, Prefs } from '../util/Prefs';

export class ExportJob {
  albumId: string = '';
  title: string = '';
  taskId: number = 0;
  sourcePath: string = '';
  state: string = 'wait';
  message: string = '';
}

export class StagedCbz {
  path: string = '';
  temporary: boolean = false;
}

export async function pickExportFolder(): Promise<string> {
  const dialog: picker.DocumentViewPicker = new picker.DocumentViewPicker(getAppContext());
  const opt: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
  opt.selectMode = picker.DocumentSelectMode.FOLDER;
  opt.maxSelectNumber = 1;
  const uris: Array<string> = await dialog.select(opt);
  return uris.length === 0 ? '' : uris[0];
}

/** 系统授权目录的短探针也走异步文件接口。 */
export async function assertFolderWritable(folderUri: string): Promise<void> {
  const probe: string = `${folderUri}/manyu_write_${Date.now()}_${Math.floor(Math.random() * 1000000)}.tmp`;
  let file: fs.File | null = null;
  try {
    file = await fs.open(probe, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    if (await fs.write(file.fd, new ArrayBuffer(1)) !== 1) { throw new Error('所选目录无法写入'); }
  } finally {
    try {
      if (file !== null) { await fs.close(file); }
    } finally {
      if (file !== null) { await fs.unlink(probe); }
    }
  }
}

export function uniqueChildUri(folderUri: string, title: string): string {
  const filename: string = cbzFileName(title);
  const stem: string = filename.substring(0, filename.length - 4);
  let name: string = filename;
  let index: number = 1;
  while (fileExists(`${folderUri}/${name}`)) { name = `${stem} (${index++}).cbz`; }
  return `${folderUri}/${name}`;
}

export function copyFileAsync(src: string, dest: string, validate: () => void = (): void => {}): Promise<void> {
  return copyBytesAsync(src, dest, validate);
}

export async function stageCbz(albumId: string, sandboxCbz: string,
  validate: () => void = (): void => {}): Promise<StagedCbz> {
  validate();
  const staged: StagedCbz = new StagedCbz();
  if (sandboxCbz !== '' && fileExists(sandboxCbz) && (await fs.stat(sandboxCbz)).size > 0) {
    staged.path = sandboxCbz;
    return staged;
  }
  const book: OfflineBookRow | null = await loadOfflineAlbum(albumId);
  const rows: Array<OfflinePageRow> = await loadCompletePages(albumId);
  if (book === null || rows.length === 0) { throw new Error('没有可导出的离线页面'); }
  for (let index: number = 0; index < rows.length; index++) {
    const row: OfflinePageRow = rows[index];
    const path: string = `${getAppContext().filesDir}/${row.relativePath}`;
    if (row.albumId !== albumId || row.pageOrder !== index || row.complete !== 1 ||
      !row.relativePath.startsWith(`${book.directory}/`) || row.relativePath.includes('..') ||
      !fileExists(path) || row.fileSize <= 0 || (await fs.stat(path)).size !== row.fileSize) {
      throw new Error(`第 ${index + 1} 页离线文件缺失或损坏`);
    }
  }
  const prefs: Prefs = await Prefs.getInstance();
  const quality: string = await prefs.archiveImgQuality();
  const dest: string = `${getAppContext().cacheDir}/export_${Date.now()}_${Math.floor(Math.random() * 1000000)}.cbz`;
  await writeZipFile(dest, rows.length, (index: number): Promise<ZipEntry | null> => {
    const row: OfflinePageRow = rows[index];
    return makeArchiveEntry(`${getAppContext().filesDir}/${row.relativePath}`,
      new ChapterPage(row.chapterId, row.filename, row.scrambleId), index, quality, validate);
  }, validate);
  staged.path = dest;
  staged.temporary = true;
  return staged;
}

export function discardStaged(staged: StagedCbz): void {
  if (staged.temporary && staged.path !== '') { rmTree(staged.path); }
}

/** 单本与批量共用的导出完成边界：复制成功并成功记账后才返回。 */
export async function exportTo(job: ExportJob, destination: string,
  validate: () => void = (): void => {}): Promise<void> {
  const staged: StagedCbz = await stageCbz(job.albumId, job.sourcePath, validate);
  let copied: boolean = false;
  let recorded: boolean = false;
  try {
    await copyFileAsync(staged.path, destination, validate);
    copied = true;
    validate();
    await saveExport(job.albumId, job.taskId, destination);
    recorded = true;
  } finally {
    discardStaged(staged);
    if (copied && !recorded) { await fs.unlink(destination); }
  }
}

export async function saveExportJob(job: ExportJob, validate: () => void = (): void => {}): Promise<boolean> {
  const dialog: picker.DocumentViewPicker = new picker.DocumentViewPicker(getAppContext());
  const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
  options.newFileNames = [cbzFileName(job.title)];
  const uris: Array<string> = await dialog.save(options);
  if (uris.length === 0) { return false; }
  await exportTo(job, uris[0], validate);
  return true;
}

export async function recentExportFolder(): Promise<string> {
  const rows: Array<ExportRow> = await loadExportPage(0, 1);
  if (rows.length === 0) { return ''; }
  const location: string = rows[0].location;
  const slash: number = location.lastIndexOf('/');
  return slash > location.indexOf('://') + 2 ? location.substring(0, slash) : '';
}

export async function openExportFolder(folderUri: string): Promise<void> {
  const ability: common.UIAbilityContext = getAppContext() as common.UIAbilityContext;
  const want: Want = { action: 'ohos.want.action.viewData', uri: folderUri };
  await ability.startAbility(want);
}
