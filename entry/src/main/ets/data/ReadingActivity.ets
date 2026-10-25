import { Prefs } from '../util/Prefs';

export class ActivityStats {
  milliseconds: number = 0;
  pages: Array<string> = [];
  books: Array<string> = [];
}
class ReadingActivity {
  private queue: Promise<void> = Promise.resolve();
  async stats(): Promise<ActivityStats> {
    return JSON.parse(await (await Prefs.getInstance()).getString('activity_v1', JSON.stringify(new ActivityStats()))) as ActivityStats;
  }
  record(book: string, page: string, elapsed: number): Promise<void> {
    const next: Promise<void> = this.queue.then(async (): Promise<void> => {
      const stats: ActivityStats = await this.stats();
      stats.milliseconds += elapsed;
      if (!stats.pages.includes(page)) { stats.pages.push(page); }
      if (!stats.books.includes(book)) { stats.books.push(book); }
      await (await Prefs.getInstance()).putString('activity_v1', JSON.stringify(stats));
      AppStorage.setOrCreate('activityVersion', Date.now());
    });
    this.queue = next.catch((): void => {});
    return next;
  }
}
export const readingActivity: ReadingActivity = new ReadingActivity();
