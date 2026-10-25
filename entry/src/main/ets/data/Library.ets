import { Album } from '../models/Models';
import { Prefs } from '../util/Prefs';
import { highConfidence } from './Matching';

/** 作品身份与来源身份分开，关联书源不会覆盖各来源的阅读记录。 */
export class LibraryWork {
  id: string = '';
  title: string = '';
  author: string = '';
  cover: string = '';
  activeKey: string = '';
  albums: Array<Album> = [];
  categories: Array<string> = [];
  read: boolean = false;
  addedAt: number = 0;
  chapterSnapshot: Array<string> = [];
  baselineSet: boolean = false;
  newChapters: number = 0;
}
class Library {
  private items: Array<LibraryWork> = [];
  private loading: Promise<void> | null = null;
  private queue: Promise<void> = Promise.resolve();
  private async load(): Promise<void> {
    this.items = JSON.parse(await (await Prefs.getInstance()).getString('library_v1', '[]')) as Array<LibraryWork>;
  }
  async list(): Promise<Array<LibraryWork>> {
    if (this.loading === null) { this.loading = this.load(); }
    await this.loading;
    return JSON.parse(JSON.stringify(this.items)) as Array<LibraryWork>;
  }
  async workFor(key: string): Promise<LibraryWork | null> {
    return (await this.list()).find((w: LibraryWork) => w.albums.some((a: Album) => a.id === key)) ?? null;
  }
  private async change(action: (items: Array<LibraryWork>) => void): Promise<void> {
    const next: Promise<void> = this.queue.then(async (): Promise<void> => {
      const items: Array<LibraryWork> = await this.list();
      action(items);
      await (await Prefs.getInstance()).putString('library_v1', JSON.stringify(items));
      this.items = items;
      AppStorage.setOrCreate('bookshelfDataVersion', Date.now());
    });
    this.queue = next.catch((): void => {});
    return next;
  }
  async add(album: Album): Promise<void> {
    await this.change((items: Array<LibraryWork>): void => {
      if (items.some((w: LibraryWork) => w.albums.some((a: Album) => a.id === album.id))) { return; }
      const matching: Array<LibraryWork> = items.filter((w: LibraryWork) => w.albums.some((a: Album) => highConfidence(a, album)));
      if (matching.length === 1) { matching[0].albums.push(album); return; }
      const work: LibraryWork = new LibraryWork();
      work.id = `w${Date.now()}_${album.id}`;
      work.title = album.name;
      work.author = album.author.join(' · ');
      work.cover = album.coverUrl;
      work.activeKey = album.id;
      work.albums = [album];
      work.addedAt = Date.now();
      work.chapterSnapshot = album.episodes.map((c) => c.id);
      work.baselineSet = true;
      items.unshift(work);
    });
  }
  async remove(ids: Array<string>): Promise<void> {
    await this.change((items: Array<LibraryWork>): void => {
      for (let i: number = items.length - 1; i >= 0; i--) { if (ids.includes(items[i].id)) { items.splice(i, 1); } }
    });
  }
  async categorize(ids: Array<string>, category: string): Promise<void> {
    await this.change((items: Array<LibraryWork>): void => {
      for (const work of items) {
        if (ids.includes(work.id)) { work.categories = category.trim() === '' ? [] : [category.trim()]; }
      }
    });
  }
  async markRead(ids: Array<string>, read: boolean): Promise<void> {
    await this.change((items: Array<LibraryWork>): void => { for (const w of items) { if (ids.includes(w.id)) { w.read = read; } } });
  }
  async associate(key: string, album: Album): Promise<void> {
    await this.change((items: Array<LibraryWork>): void => {
      const target: LibraryWork | undefined = items.find((w: LibraryWork) => w.albums.some((a: Album) => a.id === key));
      if (target === undefined) { throw new Error('请先加入书架再关联书源'); }
      for (const w of items) { w.albums = w.albums.filter((a: Album) => a.id !== album.id); }
      target.albums.push(album);
      for (let i: number = items.length - 1; i >= 0; i--) { if (items[i].albums.length === 0) { items.splice(i, 1); } }
    });
  }
  async detach(key: string): Promise<void> {
    const work: LibraryWork | null = await this.workFor(key);
    if (work === null || work.albums.length < 2) { throw new Error('当前作品只有一个书源'); }
    const album: Album = work.albums.find((a: Album) => a.id === key)!;
    await this.change((items: Array<LibraryWork>): void => {
      const current: LibraryWork = items.find((w: LibraryWork) => w.id === work.id)!;
      current.albums = current.albums.filter((a: Album) => a.id !== key);
      if (current.activeKey === key) { current.activeKey = current.albums[0].id; }
      const detached: LibraryWork = new LibraryWork();
      detached.id = `w${Date.now()}_${album.id}`; detached.title = album.name; detached.author = album.author.join(' · ');
      detached.cover = album.coverUrl; detached.activeKey = album.id; detached.albums = [album]; detached.addedAt = Date.now();
      detached.chapterSnapshot = album.episodes.map((c) => c.id); detached.baselineSet = true;
      items.unshift(detached);
    });
  }
  async activate(key: string): Promise<void> {
    await this.change((items: Array<LibraryWork>): void => {
      const work: LibraryWork | undefined = items.find((w: LibraryWork) => w.albums.some((a: Album) => a.id === key));
      if (work !== undefined) { work.activeKey = key; work.newChapters = 0; }
    });
  }
  async updateSnapshot(album: Album): Promise<number> {
    let count: number = 0;
    await this.change((items: Array<LibraryWork>): void => {
      const work: LibraryWork | undefined = items.find((w: LibraryWork) => w.activeKey === album.id);
      if (work === undefined) { return; }
      count = work.baselineSet ? album.episodes.filter((c) => !work.chapterSnapshot.includes(c.id)).length : 0;
      work.chapterSnapshot = album.episodes.map((c) => c.id);
      work.baselineSet = true;
      work.newChapters += count;
      const index: number = work.albums.findIndex((a: Album) => a.id === album.id);
      work.albums[index] = album;
    });
    return count;
  }
}
export const library: Library = new Library();
