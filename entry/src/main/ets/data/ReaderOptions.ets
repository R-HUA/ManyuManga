import { Prefs } from '../util/Prefs';
import { ReaderMode, ReadingProgress } from '../models/Models';
import { library } from './Library';
import { loadBookmarks, loadReaderPref, ReaderPrefRow, saveReaderPref, tapsFrom, toggleBookmark, copyProgress } from './db/ReadingDao';
import { StoreQueue } from './stores/StoreSupport';
import { assertDatabaseGeneration } from './db/AppDatabase';

export class ReaderOptions {
  mode: ReaderMode = 'vertical';
  coverOffset: boolean = true;
  cropWhite: boolean = false;
  eyeComfort: boolean = false;
  preload: number = 3;
  paper: boolean = false;
  taps: Array<number> = [1, 0, 2, 1, 0, 2, 3, 0, 4];
}
class ReaderPreferences {
  private queue: StoreQueue = new StoreQueue();
  async key(aid: string): Promise<string> { return (await library.workFor(aid))?.id ?? aid; }
  async load(aid: string): Promise<ReaderOptions> {
    await this.queue.wait();
    const row: ReaderPrefRow | null = await loadReaderPref(await this.key(aid));
    if (row !== null) {
      return optionsFrom(row);
    }
    const prefs: Prefs = await Prefs.getInstance();
    const options: ReaderOptions = new ReaderOptions();
    options.mode = await prefs.readerMode() as ReaderMode;
    options.preload = await prefs.preloadPages();
    options.paper = await prefs.readerBgPaper();
    return options;
  }
  save(aid: string, options: ReaderOptions): Promise<void> {
    const snapshot: ReaderOptions = copyOptions(options);
    return this.queue.run(async (generation: number): Promise<void> => {
      const row: ReaderPrefRow = new ReaderPrefRow();
      row.mode = snapshot.mode;
      row.coverOffset = snapshot.coverOffset ? 1 : 0;
      row.cropWhite = snapshot.cropWhite ? 1 : 0;
      row.eyeComfort = snapshot.eyeComfort ? 1 : 0;
      row.preload = snapshot.preload;
      row.paper = snapshot.paper ? 1 : 0;
      row.taps = JSON.stringify(snapshot.taps);
      const key: string = await this.key(aid);
      assertDatabaseGeneration(generation);
      await saveReaderPref(key, row);
    });
  }
  async bookmarks(aid: string): Promise<Array<ReadingProgress>> {
    await this.queue.wait();
    return loadBookmarks(aid);
  }
  toggleBookmark(progress: ReadingProgress): Promise<void> {
    const snapshot: ReadingProgress = copyProgress(progress);
    return this.queue.run(async (): Promise<void> => {
      await toggleBookmark(snapshot);
    });
  }
}

function copyOptions(options: ReaderOptions): ReaderOptions {
  const next: ReaderOptions = new ReaderOptions();
  next.mode = options.mode;
  next.coverOffset = options.coverOffset;
  next.cropWhite = options.cropWhite;
  next.eyeComfort = options.eyeComfort;
  next.preload = options.preload;
  next.paper = options.paper;
  next.taps = options.taps.slice();
  return next;
}

function optionsFrom(row: ReaderPrefRow): ReaderOptions {
  const options: ReaderOptions = new ReaderOptions();
  options.mode = row.mode as ReaderMode;
  options.coverOffset = row.coverOffset === 1;
  options.cropWhite = row.cropWhite === 1;
  options.eyeComfort = row.eyeComfort === 1;
  options.preload = row.preload;
  options.paper = row.paper === 1;
  options.taps = tapsFrom(row.taps);
  return options;
}

export const readerPreferences: ReaderPreferences = new ReaderPreferences();
