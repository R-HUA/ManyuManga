import { Album, Chapter, ReadingProgress } from '../../models/Models';

/** 单章下载状态：none 未下载 / queued 排队 / running 下载中 / done 已完成 / failed 失败 */
export class ChapterDownloadInfo {
  state: string = 'none';
  done: number = 0;
  total: number = 0;

  constructor(state: string = 'none', done: number = 0, total: number = 0) {
    this.state = state;
    this.done = done;
    this.total = total;
  }
}

/** 章节列表行的展示模型：已读、当前在读与下载状态都在这里一次算好，LazyForEach 只负责渲染。 */
export class ChapterRow {
  chapter: Chapter = new Chapter();
  index: number = 0;
  read: boolean = false;
  current: boolean = false;
  progressText: string = '';
  download: ChapterDownloadInfo = new ChapterDownloadInfo();

  key(): string {
    return `${this.chapter.id}_${this.read}_${this.current}_${this.progressText}_${this.download.state}_${this.download.done}`;
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
    row.progressText = current && progress !== null && progress.totalPages > 0 ?
      `${progress.page + 1}/${progress.totalPages}` : '';
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

  setRows(rows: Array<ChapterRow>): void {
    this.rows = rows;
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
