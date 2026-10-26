import { ActivityRow, loadStats, recordActivity } from './db/ReadingDao';
import { StoreQueue } from './stores/StoreSupport';

export class ActivityStats {
  milliseconds: number = 0;
  pages: Array<string> = [];
  books: Array<string> = [];
}
class ReadingActivity {
  private queue: StoreQueue = new StoreQueue();
  async stats(): Promise<ActivityStats> {
    await this.queue.wait();
    const row: ActivityRow = await loadStats();
    const stats: ActivityStats = new ActivityStats();
    stats.milliseconds = row.milliseconds;
    stats.pages = row.pages;
    stats.books = row.books;
    return stats;
  }
  record(book: string, page: string, elapsed: number): Promise<void> {
    return this.queue.run(async (): Promise<void> => {
      await recordActivity(book, page, elapsed);
      AppStorage.setOrCreate('activityVersion', Date.now());
    });
  }
}
export const readingActivity: ReadingActivity = new ReadingActivity();
