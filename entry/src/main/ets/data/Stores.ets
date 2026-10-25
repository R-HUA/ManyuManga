/**
 * 本地数据 Store（收藏 / 本子级浏览历史 / 精确阅读进度 / 搜索历史 / 屏蔽词 / 自定义分类）
 *
 *
 */

import { Prefs, PrefKeys } from '../util/Prefs';
import {
  Album,
  AlbumLite,
  Chapter,
  FavItem,
  HistoryItem,
  ReadingProgress,
  asArray,
  asNumber,
  asRecord,
  asString
} from '../models/Models';

/** 数组条目上限常量 */
const HISTORY_LIMIT: number = 300;
const SEARCH_HISTORY_LIMIT: number = 50;
const READ_PROGRESS_LIMIT: number = 200;

/* ===== 跨页刷新版本戳 =====
 * 收藏/历史/阅读进度每次写入递增 bookshelfDataVersion：BookshelfPage 经
 * @StorageProp + @Watch 自动重读（阅读返回秒级同步续读横幅/页码）。
 * 屏蔽词写入递增 blockTagsVersion：发现/分类页 @Watch 对已渲染列表重新过滤。 */
const BOOKSHELF_DATA_VERSION_KEY: string = 'bookshelfDataVersion';
const BLOCK_TAGS_VERSION_KEY: string = 'blockTagsVersion';

function bumpBookshelfVersion(): void {
  AppStorage.setOrCreate(BOOKSHELF_DATA_VERSION_KEY, Date.now());
}

function bumpBlockTagsVersion(): void {
  AppStorage.setOrCreate(BLOCK_TAGS_VERSION_KEY, Date.now());
}

function parseJsonArray(text: string): Array<Object> {
  if (text === '') {
    return [];
  }
  try {
    const parsed: Object | null = JSON.parse(text) as Object | null;
    const arr: Array<Object> | null = asArray(parsed);
    return arr === null ? [] : arr;
  } catch (e) {
    return [];
  }
}

// ───────────────────────── 收藏（FavStore 等价） ─────────────────────────

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

// ───────────────────────── 浏览历史（HistoryStore 等价） ─────────────────────────

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

// ───────────────────────── 精确阅读进度 ─────────────────────────

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

// ───────────────────────── 搜索历史（SearchHistoryStore 等价） ─────────────────────────

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

// ───────────────────────── 屏蔽词（BlockTagsStore 等价，S 级） ─────────────────────────

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

// ───────────────────────── 自定义分类（CustomCatStore 等价，S 级） ─────────────────────────

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

// ───────────────────────── 详情/章节/首页缓存（AlbumCache/PagesCache/HomeCache 等价） ─────────────────────────
// 语义（api-spec §4）：先读缓存秒开，网络成功后覆写，失败保留旧值。持久化为单 JSON（preferences 版）。

/** 首页缓存数据（HomeCache 等价） */
export class HomeCacheData {
  random: Array<AlbumLite> = [];
  ranking: Array<AlbumLite> = [];
  latest: Array<AlbumLite> = [];
}

const ALBUM_CACHE_LIMIT: number = 100;

/** 本子详情缓存（AlbumCache 等价；容量上限 100，超出按插入序淘汰——preferences 版简化） */
export class AlbumCacheStore {
  private loaded: boolean = false;
  private loading: Promise<void> | null = null;
  private items: Array<Album> = [];

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
    const arr: Array<Object> = parseJsonArray(await prefs.getString(PrefKeys.ALBUM_CACHE, '[]'));
    for (const it of arr) {
      const album: Album | null = this.parseAlbum(it);
      if (album !== null) {
        this.items.push(album);
      }
    }
    this.loaded = true;
  }

  private parseAlbum(it: Object): Album | null {
    const rec: Record<string, Object> | null = asRecord(it);
    if (rec === null) {
      return null;
    }
    const a: Album = new Album(asString(rec['id']), asString(rec['name']));
    a.coverUrl = asString(rec['coverUrl']);
    a.description = asString(rec['description']);
    a.language = asString(rec['language']);
    a.originalUrl = asString(rec['originalUrl']);
    a.likes = asString(rec['likes']);
    a.views = asString(rec['views']);
    const authors: Array<Object> | null = asArray(rec['author']);
    if (authors !== null) {
      for (const x of authors) {
        const v: string = asString(x);
        if (v !== '') {
          a.author.push(v);
        }
      }
    }
    const tags: Array<Object> | null = asArray(rec['tags']);
    if (tags !== null) {
      for (const x of tags) {
        const v: string = asString(x);
        if (v !== '') {
          a.tags.push(v);
        }
      }
    }
    const eps: Array<Object> | null = asArray(rec['episodes']);
    if (eps !== null) {
      for (const x of eps) {
        const e: Record<string, Object> | null = asRecord(x);
        if (e !== null) {
          const chapter: Chapter = new Chapter(asString(e['id']), asString(e['title']), asString(e['sort']));
          chapter.number = asString(e['number']);
          a.episodes.push(chapter);
        }
      }
    }
    return a;
  }

  async get(albumId: string): Promise<Album | null> {
    await this.ensureLoaded();
    for (const it of this.items) {
      if (it.id === albumId) {
        return it;
      }
    }
    return null;
  }

  async put(album: Album): Promise<void> {
    await this.ensureLoaded();
    this.items = this.items.filter((it: Album) => it.id !== album.id);
    this.items.unshift(album);
    while (this.items.length > ALBUM_CACHE_LIMIT) {
      this.items.pop();
    }
    const prefs: Prefs = await Prefs.getInstance();
    await prefs.putString(PrefKeys.ALBUM_CACHE, JSON.stringify(this.items));
  }
}

/** 章节图片文件名列表缓存（PagesCache 等价） */
export class PagesCacheStore {
  private loaded: boolean = false;
  private loading: Promise<void> | null = null;
  private items: Array<ListEntry> = [];

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
    const arr: Array<Object> = parseJsonArray(await prefs.getString(PrefKeys.PAGES_CACHE, '[]'));
    for (const it of arr) {
      const rec: Record<string, Object> | null = asRecord(it);
      if (rec === null) {
        continue;
      }
      const entry: ListEntry = new ListEntry();
      entry.key = asString(rec['key']);
      const list: Array<Object> | null = asArray(rec['list']);
      if (list !== null) {
        for (const x of list) {
          const v: string = asString(x);
          if (v !== '') {
            entry.list.push(v);
          }
        }
      }
      if (entry.key !== '') {
        this.items.push(entry);
      }
    }
    this.loaded = true;
  }

  async get(photoId: string): Promise<Array<string> | null> {
    await this.ensureLoaded();
    for (const it of this.items) {
      if (it.key === photoId) {
        return it.list.slice();
      }
    }
    return null;
  }

  async put(photoId: string, list: Array<string>): Promise<void> {
    await this.ensureLoaded();
    const entry: ListEntry = new ListEntry();
    entry.key = photoId;
    entry.list = list.slice();
    this.items = this.items.filter((it: ListEntry) => it.key !== photoId);
    this.items.unshift(entry);
    while (this.items.length > 200) {
      this.items.pop();
    }
    const prefs: Prefs = await Prefs.getInstance();
    await prefs.putString(PrefKeys.PAGES_CACHE, JSON.stringify(this.items));
  }
}

class ListEntry {
  key: string = '';
  list: Array<string> = [];
}

/** 首页缓存（HomeCache 等价：random/ranking/latest 三段） */
export class HomeCacheStore {
  async load(): Promise<HomeCacheData | null> {
    const prefs: Prefs = await Prefs.getInstance();
    const text: string = await prefs.getString(PrefKeys.HOME_CACHE, '');
    if (text === '') {
      return null;
    }
    const rec: Record<string, Object> | null = asRecord(JSON.parse(text) as Object);
    if (rec === null) {
      return null;
    }
    const data: HomeCacheData = new HomeCacheData();
    data.random = this.parseLiteArray(rec['random']);
    data.ranking = this.parseLiteArray(rec['ranking']);
    data.latest = this.parseLiteArray(rec['latest']);
    return data;
  }

  private parseLiteArray(v: Object | null): Array<AlbumLite> {
    const out: Array<AlbumLite> = [];
    const arr: Array<Object> | null = asArray(v);
    if (arr === null) {
      return out;
    }
    for (const it of arr) {
      const rec: Record<string, Object> | null = asRecord(it);
      if (rec === null) {
        continue;
      }
      out.push(new AlbumLite(
        asString(rec['id']),
        asString(rec['title']),
        asString(rec['author']),
        asString(rec['coverUrl']),
        asString(rec['category']),
        asString(rec['categorySub'])
      ));
    }
    return out;
  }

  async save(random: Array<AlbumLite>, ranking: Array<AlbumLite>, latest: Array<AlbumLite>): Promise<void> {
    const prefs: Prefs = await Prefs.getInstance();
    await prefs.putString(PrefKeys.HOME_CACHE,
      JSON.stringify(new HomeCacheSnapshot(random, ranking, latest)));
  }
}

class HomeCacheSnapshot {
  random: Array<AlbumLite>;
  ranking: Array<AlbumLite>;
  latest: Array<AlbumLite>;

  constructor(random: Array<AlbumLite>, ranking: Array<AlbumLite>, latest: Array<AlbumLite>) {
    this.random = random;
    this.ranking = ranking;
    this.latest = latest;
  }
}

// ───────────────────────── 单例导出 ─────────────────────────

export const favStore: FavStore = new FavStore();
export const historyStore: HistoryStore = new HistoryStore();
export const readProgressStore: ReadProgressStore = new ReadProgressStore();
export const searchHistoryStore: SearchHistoryStore = new SearchHistoryStore();
export const blockTagsStore: BlockTagsStore = new BlockTagsStore();
export const customCatStore: CustomCatStore = new CustomCatStore();
export const albumCacheStore: AlbumCacheStore = new AlbumCacheStore();
export const pagesCacheStore: PagesCacheStore = new PagesCacheStore();
export const homeCacheStore: HomeCacheStore = new HomeCacheStore();
