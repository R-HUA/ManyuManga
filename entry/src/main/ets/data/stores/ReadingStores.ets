import { Prefs } from '../../util/Prefs';
import { Album, HistoryItem, ReadingProgress } from '../../models/Models';
import {
  loadHistory, loadHistoryPage, recordHistory, removeHistory, clearHistory, importHistory,
  loadProgress, loadProgressPage, loadProgressFor, putProgress, removeProgress, clearProgress, copyProgress
} from '../db/ReadingDao';
import { StoreQueue } from './StoreSupport';
import { assertDatabaseGeneration } from '../db/AppDatabase';

function bumpBookshelfVersion(): void {
  AppStorage.setOrCreate('bookshelfDataVersion', Date.now());
}

export class HistoryStore {
  private queue: StoreQueue = new StoreQueue();

  async getList(): Promise<Array<HistoryItem>> {
    await this.queue.wait();
    return loadHistory();
  }

  async getPage(offset: number, limit: number): Promise<Array<HistoryItem>> {
    await this.queue.wait();
    return loadHistoryPage(offset, limit);
  }

  invalidate(): void {}

  record(album: Album, coverUrl: string): Promise<void> {
    const item: HistoryItem = new HistoryItem(album.id, album.name, album.author.join(', '), coverUrl, Date.now());
    return this.queue.run(async (generation: number): Promise<void> => {
      const prefs: Prefs = await Prefs.getInstance();
      if (!await prefs.historyEnabled()) { return; }
      assertDatabaseGeneration(generation);
      await recordHistory(item);
      bumpBookshelfVersion();
    });
  }

  removeAll(ids: Array<string>): Promise<void> {
    const snapshot: Array<string> = ids.slice();
    return this.queue.run(async (): Promise<void> => {
      await removeHistory(snapshot);
      bumpBookshelfVersion();
    });
  }

  clear(): Promise<void> {
    return this.queue.run(async (): Promise<void> => {
      await clearHistory();
      bumpBookshelfVersion();
    });
  }

  importItems(items: Array<HistoryItem>): Promise<number> {
    const snapshot: Array<HistoryItem> = items.map((item: HistoryItem): HistoryItem =>
      new HistoryItem(item.id, item.title, item.author, item.coverUrl, item.viewedAt));
    return this.queue.run(async (): Promise<number> => {
      const added: number = await importHistory(snapshot);
      bumpBookshelfVersion();
      return added;
    });
  }
}

export class ReadProgressStore {
  private queue: StoreQueue = new StoreQueue();

  save(progress: ReadingProgress): Promise<void> {
    const snapshot: ReadingProgress = copyProgress(progress);
    snapshot.at = Date.now();
    return this.queue.run(async (): Promise<void> => {
      await putProgress(snapshot);
      bumpBookshelfVersion();
    });
  }

  async get(aid: string): Promise<ReadingProgress | null> {
    await this.queue.wait();
    return loadProgressFor(aid);
  }

  async list(limit: number = 0): Promise<Array<ReadingProgress>> {
    await this.queue.wait();
    return limit > 0 ? loadProgressPage(0, limit) : loadProgress();
  }

  async listPage(offset: number, limit: number): Promise<Array<ReadingProgress>> {
    await this.queue.wait();
    return loadProgressPage(offset, limit);
  }

  invalidate(): void {}

  remove(aid: string): Promise<void> {
    return this.queue.run(async (): Promise<void> => {
      await removeProgress(aid);
      bumpBookshelfVersion();
    });
  }

  clearAll(): Promise<void> {
    return this.queue.run(async (): Promise<void> => {
      await clearProgress();
      bumpBookshelfVersion();
    });
  }
}

export const historyStore: HistoryStore = new HistoryStore();
export const readProgressStore: ReadProgressStore = new ReadProgressStore();
