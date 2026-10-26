import { Album, FavItem, MetadataTerm } from '../../models/Models';
import {
  loadFavorites, loadFavoritePage, loadFavoriteTags, hasFavorite, addFavorite, removeFavorite,
  importFavorites, addFavoriteTags, removeFavoriteTag, searchFavoriteTags
} from '../db/CatalogDao';
import { StoreQueue } from './StoreSupport';
import { assertDatabaseGeneration } from '../db/AppDatabase';

function bumpBookshelfVersion(): void {
  AppStorage.setOrCreate('bookshelfDataVersion', Date.now());
}

export class FavStore {
  private queue: StoreQueue = new StoreQueue();

  async getList(): Promise<Array<FavItem>> {
    await this.queue.wait();
    return loadFavorites();
  }

  async getPage(offset: number, limit: number): Promise<Array<FavItem>> {
    await this.queue.wait();
    return loadFavoritePage(offset, limit);
  }

  invalidate(): void {}

  async contains(id: string): Promise<boolean> {
    await this.queue.wait();
    return hasFavorite(id);
  }

  add(album: Album, coverUrl: string): Promise<void> {
    const item: FavItem = new FavItem(album.id, album.name,
      album.author.map((term: MetadataTerm): string => term.label).join(', '), coverUrl, Date.now());
    return this.queue.run(async (): Promise<void> => {
      await addFavorite(item);
      bumpBookshelfVersion();
    });
  }

  remove(id: string): Promise<void> {
    return this.queue.run(async (): Promise<void> => {
      await removeFavorite(id);
      bumpBookshelfVersion();
    });
  }

  toggle(album: Album, coverUrl: string): Promise<boolean> {
    const item: FavItem = new FavItem(album.id, album.name,
      album.author.map((term: MetadataTerm): string => term.label).join(', '), coverUrl, Date.now());
    return this.queue.run(async (generation: number): Promise<boolean> => {
      const exists: boolean = await hasFavorite(item.id);
      assertDatabaseGeneration(generation);
      if (exists) {
        await removeFavorite(item.id);
        bumpBookshelfVersion();
        return false;
      }
      await addFavorite(item);
      bumpBookshelfVersion();
      return true;
    });
  }

  async getTags(): Promise<Array<string>> {
    await this.queue.wait();
    return loadFavoriteTags();
  }

  async searchTags(needle: string, limit: number): Promise<Array<string>> {
    await this.queue.wait();
    return searchFavoriteTags(needle, limit);
  }

  addTag(tag: string): Promise<void> { return this.importTags([tag]); }

  removeTag(tag: string): Promise<void> {
    return this.queue.run(async (): Promise<void> => {
      await removeFavoriteTag(tag);
      bumpBookshelfVersion();
    });
  }

  importItems(items: Array<FavItem>): Promise<number> {
    const snapshot: Array<FavItem> = items.map((item: FavItem): FavItem =>
      new FavItem(item.id, item.title, item.author, item.coverUrl, item.addedAt));
    return this.queue.run(async (): Promise<number> => {
      const added: number = await importFavorites(snapshot);
      if (added > 0) { bumpBookshelfVersion(); }
      return added;
    });
  }

  importTags(tags: Array<string>): Promise<void> {
    const snapshot: Array<string> = tags.slice();
    return this.queue.run(async (): Promise<void> => {
      await addFavoriteTags(snapshot);
      bumpBookshelfVersion();
    });
  }
}

export const favStore: FavStore = new FavStore();
