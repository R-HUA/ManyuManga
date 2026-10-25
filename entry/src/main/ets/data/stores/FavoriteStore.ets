import { Prefs, PrefKeys } from '../../util/Prefs';
import { Album, FavItem, asNumber, asRecord, asString } from '../../models/Models';
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
export class FavStore {
  private items: Array<FavItem> = [];
  private tags: Array<string> = [];
  private loaded: boolean = false;
  private loading: Promise<void> | null = null;

  /** 并发安全：共享同一次加载 Promise（避免并发首调重复读入） */
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
    const favArr: Array<Object> = parseJsonArray(await prefs.getString(PrefKeys.FAV_ITEMS, '[]'));
    for (const it of favArr) {
      const rec: Record<string, Object> | null = asRecord(it);
      if (rec === null) {
        continue;
      }
      const f: FavItem = new FavItem();
      f.id = asString(rec['id']);
      f.title = asString(rec['title']);
      f.author = asString(rec['author']);
      f.coverUrl = asString(rec['coverUrl']);
      f.addedAt = asNumber(rec['addedAt'], 0);
      this.items.push(f);
    }
    const tagArr: Array<Object> = parseJsonArray(await prefs.getString(PrefKeys.FAV_TAGS, '[]'));
    for (const t of tagArr) {
      const v: string = asString(t);
      if (v !== '') {
        this.tags.push(v);
      }
    }
    this.loaded = true;
  }

  /** 收藏列表（新的在前） */
  async getList(): Promise<Array<FavItem>> {
    await this.ensureLoaded();
    return this.items.slice();
  }

  async contains(id: string): Promise<boolean> {
    await this.ensureLoaded();
    for (const it of this.items) {
      if (it.id === id) {
        return true;
      }
    }
    return false;
  }

  /** 新增收藏：按 id 去重，插到列表头 */
  async add(album: Album, coverUrl: string): Promise<void> {
    await this.ensureLoaded();
    if (await this.contains(album.id)) {
      return;
    }
    const f: FavItem = new FavItem();
    f.id = album.id;
    f.title = album.name;
    f.author = album.author.join(', ');
    f.coverUrl = coverUrl;
    f.addedAt = Date.now();
    this.items.unshift(f);
    await this.persist();
    bumpBookshelfVersion();
  }

  async remove(id: string): Promise<void> {
    await this.ensureLoaded();
    this.items = this.items.filter((it: FavItem) => it.id !== id);
    await this.persist();
    bumpBookshelfVersion();
  }

  /** 切换收藏态；返回切换后是否已收藏 */
  async toggle(album: Album, coverUrl: string): Promise<boolean> {
    if (await this.contains(album.id)) {
      await this.remove(album.id);
      return false;
    }
    await this.add(album, coverUrl);
    return true;
  }

  /** 收藏的标签列表 */
  async getTags(): Promise<Array<string>> {
    await this.ensureLoaded();
    return this.tags.slice();
  }

  /** 添加标签：trim + 去重 */
  async addTag(tag: string): Promise<void> {
    await this.ensureLoaded();
    const t: string = tag.trim();
    if (t === '' || this.tags.indexOf(t) >= 0) {
      return;
    }
    this.tags.push(t);
    await this.persistTags();
    bumpBookshelfVersion();
  }

  async removeTag(tag: string): Promise<void> {
    await this.ensureLoaded();
    this.tags = this.tags.filter((t: string) => t !== tag);
    await this.persistTags();
    bumpBookshelfVersion();
  }

  /** 导入合并收藏：按 id 去重，返回新增数量 */
  async importItems(newItems: Array<FavItem>): Promise<number> {
    await this.ensureLoaded();
    let added: number = 0;
    for (const item of newItems) {
      let exists: boolean = false;
      for (const it of this.items) {
        if (it.id === item.id) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        this.items.push(item);
        added++;
      }
    }
    if (added > 0) {
      await this.persist();
      bumpBookshelfVersion();
    }
    return added;
  }

  async importTags(newTags: Array<string>): Promise<void> {
    await this.ensureLoaded();
    let changed: boolean = false;
    for (const raw of newTags) {
      const t: string = raw.trim();
      if (t !== '' && this.tags.indexOf(t) < 0) {
        this.tags.push(t);
        changed = true;
      }
    }
    if (changed) {
      await this.persistTags();
      bumpBookshelfVersion();
    }
  }

  private async persist(): Promise<void> {
    const prefs: Prefs = await Prefs.getInstance();
    await prefs.putString(PrefKeys.FAV_ITEMS, JSON.stringify(this.items));
  }

  private async persistTags(): Promise<void> {
    const prefs: Prefs = await Prefs.getInstance();
    await prefs.putString(PrefKeys.FAV_TAGS, JSON.stringify(this.tags));
  }
}

export const favStore: FavStore = new FavStore();
