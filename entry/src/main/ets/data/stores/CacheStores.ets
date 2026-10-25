import { Prefs, PrefKeys } from '../../util/Prefs';
import { Album, AlbumLite, Chapter, asArray, asRecord, asString } from '../../models/Models';
import { parseJsonArray } from './StoreSupport';
const ALBUM_CACHE_LIMIT: number = 100;
export class HomeCacheData {
  random: Array<AlbumLite> = [];
  ranking: Array<AlbumLite> = [];
  latest: Array<AlbumLite> = [];
}

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
