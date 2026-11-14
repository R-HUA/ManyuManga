import { Album, Chapter, ReadingProgress } from '../../models/Models';
import { ChapterDownloadInfo } from '../../data/DownloadTypes';

export { ChapterDownloadInfo };

/**
 * 章节列表行的展示模型：已读、当前在读与下载状态都在这里一次算好。
 * 行对象按章节 id 复用，状态变化只改属性（@Observed），LazyForEach 的键不随状态变化，避免每下载一页就重建一行。
 */
@Observed
export class ChapterRow {
  chapter: Chapter = new Chapter();
  index: number = 0;
  read: boolean = false;
  current: boolean = false;
  download: ChapterDownloadInfo = new ChapterDownloadInfo();
  /** 多选模式：selecting 表示处于多选，selected 表示本行已勾选。 */
  selecting: boolean = false;
  selected: boolean = false;
  /** 在当前可见列表里是否为首行 / 末行，用于分组圆角。 */
  first: boolean = false;
  last: boolean = false;

  /** 键只含业务身份。多选模式切换会改变行的滑动操作，所以单独作为前缀。 */
  key(): string {
    return `${this.selecting ? 'select' : 'read'}|${this.chapter.id}`;
  }

  /** 把新算出的状态写进已显示的行，只在值变化时赋值。 */
  assign(next: ChapterRow): void {
    if (this.chapter !== next.chapter) { this.chapter = next.chapter; }
    if (this.index !== next.index) { this.index = next.index; }
    if (this.read !== next.read) { this.read = next.read; }
    if (this.current !== next.current) { this.current = next.current; }
    if (this.selecting !== next.selecting) { this.selecting = next.selecting; }
    if (this.selected !== next.selected) { this.selected = next.selected; }
    if (this.first !== next.first) { this.first = next.first; }
    if (this.last !== next.last) { this.last = next.last; }
    const a: ChapterDownloadInfo = this.download;
    const b: ChapterDownloadInfo = next.download;
    if (a.state !== b.state || a.done !== b.done || a.total !== b.total) {
      this.download = new ChapterDownloadInfo(b.state, b.done, b.total);
    }
  }
}

export function chapterLabel(chapter: Chapter): string {
  return chapter.title || `第 ${chapter.sort} 章`;
}

/** 当前在读章节是否已经读完（停在最后一页）。 */
function finished(progress: ReadingProgress): boolean {
  return progress.totalPages > 0 && progress.page >= progress.totalPages - 1;
}

export function buildChapterRows(album: Album | null, progress: ReadingProgress | null, filter: string,
  unreadOnly: boolean, ascending: boolean, downloads: Map<string, ChapterDownloadInfo>): Array<ChapterRow> {
  if (album === null) {
    return [];
  }
  const readIndex: number = progress === null ? -1 : progress.chapterIndex;
  const rows: Array<ChapterRow> = [];
  for (let i = 0; i < album.episodes.length; i++) {
    const chapter: Chapter = album.episodes[i];
    const current: boolean = progress !== null && progress.chapterId === chapter.id;
    const read: boolean = i < readIndex || (current && progress !== null && finished(progress));
    if (unreadOnly && read) {
      continue;
    }
    if (filter !== '' && !chapter.title.includes(filter)) {
      continue;
    }
    const row: ChapterRow = new ChapterRow();
    row.chapter = chapter;
    row.index = i;
    row.read = read;
    row.current = current;
    const info: ChapterDownloadInfo | undefined = downloads.get(chapter.id);
    row.download = info === undefined ? new ChapterDownloadInfo() : info;
    rows.push(row);
  }
  return ascending ? rows : rows.reverse();
}

/** 章节 LazyForEach 数据源：整体替换数据后通知重载。 */
export class ChapterDataSource implements IDataSource {
  private rows: Array<ChapterRow> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): ChapterRow {
    return this.rows[index];
  }

  all(): Array<ChapterRow> {
    return this.rows;
  }

  /** 按键复用已显示的行对象：键不变的行只更新属性，增删或换序时才通知重载。 */
  setRows(rows: Array<ChapterRow>): void {
    const previous: Map<string, ChapterRow> = new Map<string, ChapterRow>();
    for (const row of this.rows) {
      previous.set(row.key(), row);
    }
    let structural: boolean = rows.length !== this.rows.length;
    const next: Array<ChapterRow> = [];
    for (let i = 0; i < rows.length; i++) {
      const fresh: ChapterRow = rows[i];
      fresh.first = i === 0;
      fresh.last = i === rows.length - 1;
      const kept: ChapterRow | undefined = previous.get(fresh.key());
      if (kept === undefined) {
        next.push(fresh);
        structural = true;
        continue;
      }
      if (!structural && this.rows[i] !== kept) {
        structural = true;
      }
      kept.assign(fresh);
      next.push(kept);
    }
    this.rows = next;
    if (!structural) {
      return;
    }
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
}

/** 下载范围：missing 全部未下载 / unread 未读 / next 接下来 N 章 */
export function pickDownloadChapters(album: Album | null, progress: ReadingProgress | null, mode: string, count: number,
  downloads: Map<string, ChapterDownloadInfo>): Array<string> {
  if (album === null) {
    return [];
  }
  const rows: Array<ChapterRow> = buildChapterRows(album, progress, '', false, true, downloads);
  const start: number = progress === null ? 0 : Math.max(0, progress.chapterIndex);
  const ids: Array<string> = [];
  for (const row of rows) {
    const known: boolean = row.download.state !== 'none' && row.download.state !== 'failed';
    if (known) {
      continue;
    }
    if (mode === 'unread' && row.read) {
      continue;
    }
    if (mode === 'next' && (row.index < start || ids.length >= count)) {
      continue;
    }
    ids.push(row.chapter.id);
  }
  return ids;
}

function progressAt(album: Album, base: ReadingProgress | null, index: number, page: number,
  total: number): ReadingProgress {
  const chapter: Chapter = album.episodes[index];
  return new ReadingProgress(album.id, chapter.id, index, page, total, Date.now(),
    base !== null ? base.title : album.name, base !== null ? base.author : '',
    base !== null ? base.coverUrl : album.coverUrl);
}

/**
 * 批量标记已读/未读。进度是“读到哪一章”的水位线：
 * 标记已读把水位推进到所选最后一章之后，标记未读退回到所选第一章；不会反向移动。
 * 返回 null 表示清除进度（全部未读），返回原对象表示无需改动。
 */
export function markedProgress(album: Album, progress: ReadingProgress | null, ids: Array<string>,
  read: boolean): ReadingProgress | null {
  const wanted: Set<string> = new Set<string>(ids);
  let first: number = -1;
  let last: number = -1;
  for (let i = 0; i < album.episodes.length; i++) {
    if (wanted.has(album.episodes[i].id)) {
      if (first < 0) {
        first = i;
      }
      last = i;
    }
  }
  if (first < 0) {
    return progress;
  }
  const rows: Array<ChapterRow> = buildChapterRows(album, progress, '', false, true, new Map<string, ChapterDownloadInfo>());
  if (read) {
    if (rows[last].read) {
      return progress;
    }
    return last + 1 < album.episodes.length ? progressAt(album, progress, last + 1, 0, 0) :
      progressAt(album, progress, last, 0, 1);
  }
  if (!rows[first].read && (progress === null || progress.chapterIndex <= first)) {
    return progress;
  }
  return first === 0 ? null : progressAt(album, progress, first, 0, 0);
}
