import { Album, MetadataTerm } from '../models/Models';
import { highConfidence } from './Matching';
import {
  loadLibrary, loadLibraryPage, loadLibraryWorkForAlbum, loadLibraryCandidates, changeLibraryWorks,
  categorizeLibraryWorks, markLibraryWorksRead, activateLibraryAlbum
} from './db/LibraryDao';
import { albumFromJson, albumToJson } from './db/RowCodec';
import { assertDatabaseGeneration } from './db/AppDatabase';
import { notifyBookshelfChanged, StoreQueue } from './stores/StoreSupport';

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

function newWork(album: Album): LibraryWork {
  const work: LibraryWork = new LibraryWork();
  work.id = `w${Date.now()}_${album.id}`;
  work.title = album.name;
  work.author = album.author.map((term: MetadataTerm): string => term.label).join(' · ');
  work.cover = album.coverUrl;
  work.activeKey = album.id;
  work.albums = [album];
  work.addedAt = Date.now();
  work.chapterSnapshot = album.episodes.map((chapter) => chapter.id);
  work.baselineSet = true;
  return work;
}

class Library {
  private queue: StoreQueue = new StoreQueue();

  async list(): Promise<Array<LibraryWork>> {
    await this.queue.wait();
    return loadLibrary();
  }

  async listPage(offset: number, limit: number): Promise<Array<LibraryWork>> {
    await this.queue.wait();
    return loadLibraryPage(offset, limit);
  }

  async workFor(key: string): Promise<LibraryWork | null> {
    await this.queue.wait();
    return loadLibraryWorkForAlbum(key);
  }

  add(album: Album): Promise<void> {
    const snapshot: Album = albumFromJson(albumToJson(album));
    return this.queue.run(async (generation: number): Promise<void> => {
      if (await loadLibraryWorkForAlbum(snapshot.id) !== null) { return; }
      const candidates: Array<LibraryWork> = await loadLibraryCandidates(snapshot);
      const matching: Array<LibraryWork> = candidates.filter((work: LibraryWork): boolean =>
        work.albums.some((item: Album): boolean => highConfidence(item, snapshot)));
      assertDatabaseGeneration(generation);
      if (matching.length === 1) {
        matching[0].albums.push(snapshot);
        await changeLibraryWorks([matching[0]]);
      } else { await changeLibraryWorks([newWork(snapshot)]); }
      notifyBookshelfChanged();
    });
  }

  remove(ids: Array<string>): Promise<void> {
    const snapshot: Array<string> = ids.slice();
    return this.queue.run(async (): Promise<void> => {
      await changeLibraryWorks([], snapshot);
      notifyBookshelfChanged();
    });
  }

  categorize(ids: Array<string>, category: string): Promise<void> {
    const snapshot: Array<string> = ids.slice();
    const name: string = category.trim();
    return this.queue.run(async (): Promise<void> => {
      await categorizeLibraryWorks(snapshot, name);
      notifyBookshelfChanged();
    });
  }

  markRead(ids: Array<string>, read: boolean): Promise<void> {
    const snapshot: Array<string> = ids.slice();
    return this.queue.run(async (): Promise<void> => {
      await markLibraryWorksRead(snapshot, read);
      notifyBookshelfChanged();
    });
  }

  associate(key: string, album: Album): Promise<void> {
    const snapshot: Album = albumFromJson(albumToJson(album));
    return this.queue.run(async (generation: number): Promise<void> => {
      const target: LibraryWork | null = await loadLibraryWorkForAlbum(key);
      if (target === null) { throw new Error('请先加入书架再关联书源'); }
      const previous: LibraryWork | null = await loadLibraryWorkForAlbum(snapshot.id);
      const changed: Array<LibraryWork> = [];
      const removed: Array<string> = [];
      if (previous !== null && previous.id !== target.id) {
        previous.albums = previous.albums.filter((item: Album): boolean => item.id !== snapshot.id);
        if (previous.albums.length === 0) { removed.push(previous.id); }
        else {
          if (previous.activeKey === snapshot.id) { previous.activeKey = previous.albums[0].id; }
          changed.push(previous);
        }
      }
      target.albums = target.albums.filter((item: Album): boolean => item.id !== snapshot.id);
      target.albums.push(snapshot);
      changed.push(target);
      assertDatabaseGeneration(generation);
      await changeLibraryWorks(changed, removed);
      notifyBookshelfChanged();
    });
  }

  detach(key: string): Promise<void> {
    return this.queue.run(async (generation: number): Promise<void> => {
      const work: LibraryWork | null = await loadLibraryWorkForAlbum(key);
      if (work === null || work.albums.length < 2) { throw new Error('当前作品只有一个书源'); }
      const album: Album | undefined = work.albums.find((item: Album): boolean => item.id === key);
      if (album === undefined) { throw new Error('书源不存在'); }
      work.albums = work.albums.filter((item: Album): boolean => item.id !== key);
      if (work.activeKey === key) { work.activeKey = work.albums[0].id; }
      assertDatabaseGeneration(generation);
      await changeLibraryWorks([work, newWork(album)]);
      notifyBookshelfChanged();
    });
  }

  activate(key: string): Promise<void> {
    return this.queue.run(async (): Promise<void> => {
      await activateLibraryAlbum(key);
      notifyBookshelfChanged();
    });
  }

  updateSnapshot(album: Album): Promise<number> {
    const snapshot: Album = albumFromJson(albumToJson(album));
    return this.queue.run(async (generation: number): Promise<number> => {
      const work: LibraryWork | null = await loadLibraryWorkForAlbum(snapshot.id);
      if (work === null || work.activeKey !== snapshot.id) { return 0; }
      const seen: Set<string> = new Set<string>(work.chapterSnapshot);
      const count: number = work.baselineSet ?
        snapshot.episodes.filter((chapter) => !seen.has(chapter.id)).length : 0;
      work.chapterSnapshot = snapshot.episodes.map((chapter) => chapter.id);
      work.baselineSet = true;
      work.newChapters += count;
      const index: number = work.albums.findIndex((item: Album): boolean => item.id === snapshot.id);
      work.albums[index] = snapshot;
      assertDatabaseGeneration(generation);
      await changeLibraryWorks([work]);
      notifyBookshelfChanged();
      return count;
    });
  }
}

export const library: Library = new Library();
