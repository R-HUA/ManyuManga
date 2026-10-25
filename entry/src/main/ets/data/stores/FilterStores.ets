import { Prefs, PrefKeys } from '../../util/Prefs';
import { asString } from '../../models/Models';
import { parseJsonArray } from './StoreSupport';
const SEARCH_HISTORY_LIMIT: number = 50;
const BLOCK_TAGS_VERSION_KEY: string = 'blockTagsVersion';
function bumpBlockTagsVersion(): void {
  AppStorage.setOrCreate(BLOCK_TAGS_VERSION_KEY, Date.now());
}
function codePointCount(s: string): number {
  let n: number = 0;
  for (let i: number = 0; i < s.length; i++) {
    const c: number = s.charCodeAt(i);
    // 高代理不单独计数（与低代理组成一个码点）
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
      const c2: number = s.charCodeAt(i + 1);
      if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
        i++;
      }
    }
    n++;
  }
  return n;
}
export class SearchHistoryStore {
  private items: Array<string> = [];
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
    const arr: Array<Object> = parseJsonArray(await prefs.getString(PrefKeys.SEARCH_HISTORY, '[]'));
    for (const it of arr) {
      const v: string = asString(it);
      if (v !== '') {
        this.items.push(v);
      }
    }
    this.loaded = true;
  }

  /** 搜索历史（最近在前） */
  async getList(): Promise<Array<string>> {
    await this.ensureLoaded();
    return this.items.slice();
  }

  /** 记录：trim、去重置顶、上限 50（SearchHistoryStore.kt:34-41） */
  async record(query: string): Promise<void> {
    await this.ensureLoaded();
    const q: string = query.trim();
    if (q === '') {
      return;
    }
    this.items = this.items.filter((it: string) => it !== q);
    this.items.unshift(q);
    while (this.items.length > SEARCH_HISTORY_LIMIT) {
      this.items.pop();
    }
    await this.persist();
  }

  async removeAll(queries: Array<string>): Promise<void> {
    await this.ensureLoaded();
    this.items = this.items.filter((it: string) => queries.indexOf(it) < 0);
    await this.persist();
  }

  async clear(): Promise<void> {
    await this.ensureLoaded();
    this.items = [];
    await this.persist();
  }

  /** 导入合并（去重，后写的在前）（SearchHistoryStore.kt:54-65） */
  async importAll(newQueries: Array<string>): Promise<void> {
    await this.ensureLoaded();
    let changed: boolean = false;
    for (let i: number = newQueries.length - 1; i >= 0; i--) {
      const v: string = newQueries[i].trim();
      if (v !== '' && this.items.indexOf(v) < 0) {
        this.items.unshift(v);
        changed = true;
      }
    }
    while (this.items.length > SEARCH_HISTORY_LIMIT) {
      this.items.pop();
    }
    if (changed) {
      await this.persist();
    }
  }

  private async persist(): Promise<void> {
    const prefs: Prefs = await Prefs.getInstance();
    await prefs.putString(PrefKeys.SEARCH_HISTORY, JSON.stringify(this.items));
  }
}

export class BlockTagsStore {
  private items: Array<string> = [];
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
    const arr: Array<Object> = parseJsonArray(await prefs.getString(PrefKeys.BLOCK_TAGS, '[]'));
    for (const it of arr) {
      const v: string = asString(it).trim();
      if (v !== '' && this.items.indexOf(v) < 0) {
        this.items.push(v);
      }
    }
    this.loaded = true;
  }

  async getList(): Promise<Array<string>> {
    await this.ensureLoaded();
    return this.items.slice();
  }

  /** 添加：trim + 去重（BlockTagsStore.kt:46-58 等价） */
  async add(tag: string): Promise<void> {
    await this.ensureLoaded();
    const t: string = tag.trim();
    if (t === '' || this.items.indexOf(t) >= 0) {
      return;
    }
    this.items.push(t);
    await this.persist();
    bumpBlockTagsVersion();
  }

  async remove(tag: string): Promise<void> {
    await this.ensureLoaded();
    this.items = this.items.filter((t: string) => t !== tag);
    await this.persist();
    bumpBlockTagsVersion();
  }

  async clear(): Promise<void> {
    await this.ensureLoaded();
    this.items = [];
    await this.persist();
    bumpBlockTagsVersion();
  }

  /**
   * 命中判定：拼接 title + author + category + categorySub 小写后包含任一屏蔽词
   * （BlockTagsStore.kt:59-74；原实现还会比对 TagStore 真实 tags，词云已裁剪故不移植）
   */
  async isBlocked(title: string, author: string, category: string, categorySub: string): Promise<boolean> {
    await this.ensureLoaded();
    if (this.items.length === 0) {
      return false;
    }
    const joined: string = `${title}${author}${category}${categorySub}`.toLowerCase();
    for (const t of this.items) {
      if (joined.indexOf(t.toLowerCase()) >= 0) {
        return true;
      }
    }
    return false;
  }

  private async persist(): Promise<void> {
    const prefs: Prefs = await Prefs.getInstance();
    await prefs.putString(PrefKeys.BLOCK_TAGS, JSON.stringify(this.items));
  }
}

export class CustomCatStore {
  private items: Array<string> = [];
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
    const arr: Array<Object> = parseJsonArray(await prefs.getString(PrefKeys.CUSTOM_CATS, '[]'));
    for (const it of arr) {
      const v: string = asString(it);
      if (v !== '') {
        this.items.push(v);
      }
    }
    this.loaded = true;
  }

  async getList(): Promise<Array<string>> {
    await this.ensureLoaded();
    return this.items.slice();
  }

  /** 添加（≤16 个 Unicode 码点，查重）；返回错误信息或 '' 表示成功（Stores.kt:188-198） */
  async add(raw: string): Promise<string> {
    await this.ensureLoaded();
    const t: string = raw.trim();
    if (t === '') {
      return '不能为空';
    }
    const cp: number = codePointCount(t);
    if (cp > 16) {
      return `最多 16 个字符（当前 ${cp}）`;
    }
    if (this.items.indexOf(t) >= 0) {
      return '已存在';
    }
    this.items.push(t);
    await this.persist();
    return '';
  }

  async remove(t: string): Promise<void> {
    await this.ensureLoaded();
    this.items = this.items.filter((it: string) => it !== t);
    await this.persist();
  }

  private async persist(): Promise<void> {
    const prefs: Prefs = await Prefs.getInstance();
    await prefs.putString(PrefKeys.CUSTOM_CATS, JSON.stringify(this.items));
  }
}

export const searchHistoryStore: SearchHistoryStore = new SearchHistoryStore();
export const blockTagsStore: BlockTagsStore = new BlockTagsStore();
export const customCatStore: CustomCatStore = new CustomCatStore();
