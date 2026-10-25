import { Prefs, PrefKeys } from '../../util/Prefs';
import { Album, HistoryItem, ReadingProgress, asNumber, asRecord, asString } from '../../models/Models';
import { parseJsonArray } from './StoreSupport';
const HISTORY_LIMIT: number = 300;
const SEARCH_HISTORY_LIMIT: number = 50;
const READ_PROGRESS_LIMIT: number = 200;

/* ===== 跨页刷新版本戳 =====
 * 收藏/历史/阅读进度每次写入递增 bookshelfDataVersion：BookshelfPage 经
 * @StorageProp + @Watch 自动重读（阅读返回秒级同步续读横幅/页码）。
 * 屏蔽词写入递增 blockTagsVersion：发现/分类页 @Watch 对已渲染列表重新过滤。 */
const BOOKSHELF_DATA_VERSION_KEY: string = 'bookshelfDataVersion';
function bumpBookshelfVersion(): void {
  AppStorage.setOrCreate(BOOKSHELF_DATA_VERSION_KEY, Date.now());
}
export class HistoryStore {
  private items: Array<HistoryItem> = [];
  private loaded: boolean = false;
  private loading: Promise<void> | null = null;

  private ensureLoaded(): Promise<void> {
    if (this.loading === null) {
      this.loading = this.doLoad();
    }
    return this.loading;
  }

  private async doLoad(): Promise<void> {
    if (this.loaded) {
      return;
    }
    const prefs: Prefs = await Prefs.getInstance();
    const arr: Array<Object> = parseJsonArray(await prefs.getString(PrefKeys.HISTORY_ITEMS, '[]'));
    for (const it of arr) {
      const rec: Record<string, Object> | null = asRecord(it);
      if (rec === null) {
        continue;
      }
      const h: HistoryItem = new HistoryItem();
      h.id = asString(rec['id']);
      h.title = asString(rec['title']);
      h.author = asString(rec['author']);
      h.coverUrl = asString(rec['coverUrl']);
      h.viewedAt = asNumber(rec['viewedAt'], 0);
      this.items.push(h);
    }
    this.loaded = true;
  }

  /** 历史列表（最近在前） */
  async getList(): Promise<Array<HistoryItem>> {
    await this.ensureLoaded();
    return this.items.slice();
  }

  /**
   * 记录浏览（详情页加载后调用）：historyEnabled 关闭不记录；同 id 先删后插头；上限 300
   */
  async record(album: Album, coverUrl: string): Promise<void> {
    await this.ensureLoaded();
    const prefs: Prefs = await Prefs.getInstance();
    if (!await prefs.historyEnabled()) {
      return;
    }
    const h: HistoryItem = new HistoryItem();
    h.id = album.id;
    h.title = album.name;
    h.author = album.author.join(', ');
    h.coverUrl = coverUrl;
    h.viewedAt = Date.now();
    this.items = this.items.filter((it: HistoryItem) => it.id !== album.id);
    this.items.unshift(h);
    while (this.items.length > HISTORY_LIMIT) {
      this.items.pop();
    }
    await this.persist();
    bumpBookshelfVersion();
  }

  async removeAll(ids: Array<string>): Promise<void> {
    await this.ensureLoaded();
    this.items = this.items.filter((it: HistoryItem) => ids.indexOf(it.id) < 0);
    await this.persist();
    bumpBookshelfVersion();
  }

  async clear(): Promise<void> {
    await this.ensureLoaded();
    this.items = [];
    await this.persist();
    bumpBookshelfVersion();
  }

  /** 导入合并（同 id 保留较新 viewedAt；有新增或更新则落盘并按 viewedAt 降序重排），返回新增数量（HistoryStore.kt:74-92） */
  async importItems(newItems: Array<HistoryItem>): Promise<number> {
    await this.ensureLoaded();
    let added: number = 0;
    let changed: boolean = false;
    for (const item of newItems) {
      let idx: number = -1;
      for (let i: number = 0; i < this.items.length; i++) {
        if (this.items[i].id === item.id) {
          idx = i;
          break;
        }
      }
      if (idx < 0) {
        this.items.push(item);
        added++;
      } else if (item.viewedAt > this.items[idx].viewedAt) {
        this.items[idx] = item;
        changed = true;
      }
    }
    if (added > 0 || changed) {
      this.items = this.items.slice().sort((a: HistoryItem, b: HistoryItem) => b.viewedAt - a.viewedAt);
      await this.persist();
      bumpBookshelfVersion();
    }
    return added;
  }

  private async persist(): Promise<void> {
    const prefs: Prefs = await Prefs.getInstance();
    await prefs.putString(PrefKeys.HISTORY_ITEMS, JSON.stringify(this.items));
  }
}

export class ReadProgressStore {
  private pendingSave: Promise<void> = Promise.resolve();
  private items: Array<ReadingProgress> = [];
  private loaded: boolean = false;
  private loading: Promise<void> | null = null;

  private ensureLoaded(): Promise<void> {
    if (this.loading === null) {
      this.loading = this.doLoad();
    }
    return this.loading;
  }

  private async doLoad(): Promise<void> {
    if (this.loaded) {
      return;
    }
    const prefs: Prefs = await Prefs.getInstance();
    const arr: Array<Object> = parseJsonArray(await prefs.getString(PrefKeys.READ_PROGRESS, '[]'));
    for (const it of arr) {
      const rec: Record<string, Object> | null = asRecord(it);
      if (rec === null) {
        continue;
      }
      const p: ReadingProgress = new ReadingProgress();
      p.aid = asString(rec['aid']);
      p.chapterId = asString(rec['chapterId']);
      p.chapterIndex = asNumber(rec['chapterIndex'], 0);
      p.page = asNumber(rec['page'], 0);
      p.totalPages = asNumber(rec['totalPages'], 0);
      p.at = asNumber(rec['at'], 0);
      p.title = asString(rec['title']);
      p.author = asString(rec['author']);
      p.coverUrl = asString(rec['coverUrl']);
      this.items.push(p);
    }
    this.loaded = true;
  }

  /** 保存进度：单 aid 单条，替换后置于头部（at 更新）；上限 200 */
  async save(progress: ReadingProgress): Promise<void> {
    const snapshot: ReadingProgress = JSON.parse(JSON.stringify(progress)) as ReadingProgress;
    snapshot.at = Date.now();
    const next: Promise<void> = this.pendingSave.then(async (): Promise<void> => {
      await this.ensureLoaded();
      const items: Array<ReadingProgress> = [snapshot].concat(this.items.filter((it: ReadingProgress) => it.aid !== snapshot.aid)).slice(0, READ_PROGRESS_LIMIT);
      const prefs: Prefs = await Prefs.getInstance();
      await prefs.putString(PrefKeys.READ_PROGRESS, JSON.stringify(items));
      this.items = items;
      bumpBookshelfVersion();
    });
    this.pendingSave = next.catch((): void => {});
    return next;
  }

  /** 取某本子的阅读进度；无则 null（书架续读横幅 / 详情页续读 CTA / 阅读器进入定位） */
  async get(aid: string): Promise<ReadingProgress | null> {
    await this.ensureLoaded();
    for (const it of this.items) {
      if (it.aid === aid) {
        return it;
      }
    }
    return null;
  }

  /** 最近阅读进度列表（at 倒序），可带 limit（0 = 全部） */
  async list(limit: number = 0): Promise<Array<ReadingProgress>> {
    await this.ensureLoaded();
    const sorted: Array<ReadingProgress> = this.items.slice().sort(
      (a: ReadingProgress, b: ReadingProgress) => b.at - a.at);
    return limit > 0 ? sorted.slice(0, limit) : sorted;
  }

  async remove(aid: string): Promise<void> {
    await this.ensureLoaded();
    this.items = this.items.filter((it: ReadingProgress) => it.aid !== aid);
    const prefs: Prefs = await Prefs.getInstance();
    await prefs.putString(PrefKeys.READ_PROGRESS, JSON.stringify(this.items));
    bumpBookshelfVersion();
  }

  async clearAll(): Promise<void> {
    await this.ensureLoaded();
    this.items = [];
    const prefs: Prefs = await Prefs.getInstance();
    await prefs.putString(PrefKeys.READ_PROGRESS, JSON.stringify(this.items));
    bumpBookshelfVersion();
  }
}

export const historyStore: HistoryStore = new HistoryStore();
export const readProgressStore: ReadProgressStore = new ReadProgressStore();
