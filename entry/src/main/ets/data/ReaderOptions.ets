import { Prefs } from '../util/Prefs';
import { ReaderMode, ReadingProgress } from '../models/Models';
import { library } from './Library';

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
  private queue: Promise<void> = Promise.resolve();
  async key(aid: string): Promise<string> { return (await library.workFor(aid))?.id ?? aid; }
  async load(aid: string): Promise<ReaderOptions> {
    const prefs: Prefs = await Prefs.getInstance();
    const all: Record<string, ReaderOptions> = JSON.parse(await prefs.getString('reader_options_v1', '{}')) as Record<string, ReaderOptions>;
    const key: string = await this.key(aid);
    if (all[key] !== undefined) { return all[key]; }
    const options: ReaderOptions = new ReaderOptions();
    options.mode = await prefs.readerMode() as ReaderMode;
    options.preload = await prefs.preloadPages();
    options.paper = await prefs.readerBgPaper();
    return options;
  }
  save(aid: string, options: ReaderOptions): Promise<void> {
    const snapshot: ReaderOptions = JSON.parse(JSON.stringify(options)) as ReaderOptions;
    const next: Promise<void> = this.queue.then(async (): Promise<void> => {
      const prefs: Prefs = await Prefs.getInstance();
      const all: Record<string, ReaderOptions> = JSON.parse(await prefs.getString('reader_options_v1', '{}')) as Record<string, ReaderOptions>;
      all[await this.key(aid)] = snapshot;
      await prefs.putString('reader_options_v1', JSON.stringify(all));
    });
    this.queue = next.catch((): void => {});
    return next;
  }
  async bookmarks(aid: string): Promise<Array<ReadingProgress>> {
    const all: Array<ReadingProgress> = JSON.parse(await (await Prefs.getInstance()).getString('bookmarks_v1', '[]')) as Array<ReadingProgress>;
    return all.filter((p: ReadingProgress) => p.aid === aid);
  }
  toggleBookmark(progress: ReadingProgress): Promise<void> {
    const next: Promise<void> = this.queue.then(async (): Promise<void> => {
      const prefs: Prefs = await Prefs.getInstance();
      const all: Array<ReadingProgress> = JSON.parse(await prefs.getString('bookmarks_v1', '[]')) as Array<ReadingProgress>;
      const exists: boolean = all.some((p: ReadingProgress) => p.aid === progress.aid && p.chapterId === progress.chapterId && p.page === progress.page);
      const result: Array<ReadingProgress> = all.filter((p: ReadingProgress) => !(p.aid === progress.aid && p.chapterId === progress.chapterId && p.page === progress.page));
      if (!exists) { result.push(progress); }
      await prefs.putString('bookmarks_v1', JSON.stringify(result));
    });
    this.queue = next.catch((): void => {});
    return next;
  }
}
export const readerPreferences: ReaderPreferences = new ReaderPreferences();
