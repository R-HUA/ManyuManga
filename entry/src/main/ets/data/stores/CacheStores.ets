import { Prefs, PrefKeys } from '../../util/Prefs';
import { Album, AlbumLite, asArray, asRecord, asString } from '../../models/Models';
import { parseJsonArray, StoreQueue } from './StoreSupport';
import { albumFromJson, albumToJson } from '../db/RowCodec';
import { assertDatabaseGeneration } from '../db/AppDatabase';
const ALBUM_CACHE_LIMIT: number = 100;
export class HomeCacheData {
  random: Array<AlbumLite> = [];
  ranking: Array<AlbumLite> = [];
  latest: Array<AlbumLite> = [];
}

export class AlbumCacheStore {
  private queue: StoreQueue = new StoreQueue();
  private loaded: boolean = false;
  private loading: Promise<void> | null = null;
  private items: Array<Album> = [];

  private ensureLoaded(): Promise<void> {
    if (this.loading === null) {
      this.loading = this.doLoad().catch((error: Error): void => {
        this.loading = null;
        throw error;
      });
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

  private parseAlbum(item: Object): Album | null {
    try {
      return albumFromJson(JSON.stringify(item));
    } catch (error) {
      // 详情缓存损坏时按未命中处理，后续由网络重新获取。
      return null;
    }
  }

  async list(): Promise<Array<Album>> {
    await this.queue.wait();
    await this.ensureLoaded();
    return this.items.map((album: Album): Album => albumFromJson(albumToJson(album)));
  }

  async get(albumId: string): Promise<Album | null> {
    await this.queue.wait();
    await this.ensureLoaded();
    for (const it of this.items) {
      if (it.id === albumId) {
        return albumFromJson(albumToJson(it));
      }
    }
    return null;
  }

  put(album: Album): Promise<void> {
    const snapshot: Album = albumFromJson(albumToJson(album));
    return this.queue.run(async (generation: number): Promise<void> => {
      await this.ensureLoaded();
      const items: Array<Album> = [snapshot].concat(this.items.filter((item: Album): boolean => item.id !== snapshot.id))
        .slice(0, ALBUM_CACHE_LIMIT);
      const prefs: Prefs = await Prefs.getInstance();
      assertDatabaseGeneration(generation);
      await prefs.putString(PrefKeys.ALBUM_CACHE, JSON.stringify(items));
      this.items = items;
    });
  }
}

export class PagesCacheStore {
  private queue: StoreQueue = new StoreQueue();
  private loaded: boolean = false;
  private loading: Promise<void> | null = null;
  private items: Array<ListEntry> = [];

  private ensureLoaded(): Promise<void> {
    if (this.loading === null) {
      this.loading = this.doLoad().catch((error: Error): void => {
        this.loading = null;
        throw error;
      });
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
    await this.queue.wait();
    await this.ensureLoaded();
    for (const it of this.items) {
      if (it.key === photoId) {
        return it.list.slice();
      }
    }
    return null;
  }

  put(photoId: string, list: Array<string>): Promise<void> {
    const entry: ListEntry = new ListEntry();
    entry.key = photoId;
    entry.list = list.slice();
    return this.queue.run(async (generation: number): Promise<void> => {
      await this.ensureLoaded();
      const items: Array<ListEntry> = [entry].concat(this.items.filter((item: ListEntry): boolean => item.key !== photoId))
        .slice(0, 200);
      const prefs: Prefs = await Prefs.getInstance();
      assertDatabaseGeneration(generation);
      await prefs.putString(PrefKeys.PAGES_CACHE, JSON.stringify(items));
      this.items = items;
    });
  }
}

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

class ListEntry {
  key: string = '';
  list: Array<string> = [];
}

export const albumCacheStore: AlbumCacheStore = new AlbumCacheStore();
export const pagesCacheStore: PagesCacheStore = new PagesCacheStore();
export const homeCacheStore: HomeCacheStore = new HomeCacheStore();
