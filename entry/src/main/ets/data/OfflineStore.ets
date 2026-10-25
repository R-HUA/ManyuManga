import fs from '@ohos.file.fs';
import { Album, ChapterPage } from '../models/Models';
import { Prefs, getAppContext } from '../util/Prefs';
import { md5Hex } from './JmApi';

class OfflineBook {
  album: Album = new Album();
  pages: Array<ChapterPage> = [];
  directory: string = '';
}
/** 完整书目才发布离线清单，缺页任务不会成为可离线阅读的版本。 */
class OfflineStore {
  private queue: Promise<void> = Promise.resolve();
  private async list(): Promise<Array<OfflineBook>> {
    return JSON.parse(await (await Prefs.getInstance()).getString('offline_v1', '[]')) as Array<OfflineBook>;
  }
  async album(key: string): Promise<Album | null> {
    return (await this.list()).find((b: OfflineBook) => b.album.id === key)?.album ?? null;
  }
  async pages(key: string): Promise<Array<string> | null> {
    const book: OfflineBook | undefined = (await this.list()).find((b: OfflineBook) => b.pages.some((p: ChapterPage) => p.photoId === key));
    return book === undefined ? null : book.pages.filter((p: ChapterPage) => p.photoId === key).map((p: ChapterPage) => p.filename);
  }
  async scramble(key: string): Promise<number | null> {
    for (const book of await this.list()) {
      const page: ChapterPage | undefined = book.pages.find((p: ChapterPage) => p.photoId === key);
      if (page !== undefined) { return page.scrambleId; }
    }
    return null;
  }
  async bytes(key: string, filename: string): Promise<ArrayBuffer | null> {
    for (const book of await this.list()) {
      const index: number = book.pages.findIndex((p: ChapterPage) => p.photoId === key && p.filename === filename);
      if (index < 0) { continue; }
      const file: fs.File = fs.openSync(`${book.directory}/${index}.bin`, fs.OpenMode.READ_ONLY);
      try {
        const bytes: ArrayBuffer = new ArrayBuffer(fs.statSync(file.fd).size);
        if (fs.readSync(file.fd, bytes) !== bytes.byteLength) { throw new Error('离线页面读取不完整'); }
        return bytes;
      } finally { fs.closeSync(file); }
    }
    return null;
  }
  install(album: Album, pages: Array<ChapterPage>, files: Array<string>, validate: () => void = (): void => {}): Promise<void> {
    const next: Promise<void> = this.queue.then(() => this.installFiles(album, pages, files, validate));
    this.queue = next.catch((): void => {});
    return next;
  }
  private async installFiles(album: Album, pages: Array<ChapterPage>, files: Array<string>, validate: () => void): Promise<void> {
    const book: OfflineBook = new OfflineBook();
    book.album = album;
    book.pages = pages;
    book.directory = `${getAppContext().filesDir}/offline/${md5Hex(album.id)}_${Date.now()}`;
    fs.mkdirSync(book.directory, true);
    const previous: Array<OfflineBook> = await this.list();
    let published: boolean = false;
    try {
      validate();
      for (let i: number = 0; i < files.length; i++) { fs.copyFileSync(files[i], `${book.directory}/${i}.bin`); }
      const next: Array<OfflineBook> = previous.filter((b: OfflineBook) => b.album.id !== album.id).concat([book]);
      validate();
      await (await Prefs.getInstance()).putString('offline_v1', JSON.stringify(next));
      published = true;
      validate();
    } catch (e) {
      if (published) { await (await Prefs.getInstance()).putString('offline_v1', JSON.stringify(previous)); }
      fs.rmdirSync(book.directory); throw e as Error;
    }
    for (const old of previous.filter((b: OfflineBook) => b.album.id === album.id)) { fs.rmdirSync(old.directory); }
  }
  remove(key: string): Promise<void> {
    const next: Promise<void> = this.queue.then(async (): Promise<void> => {
      const books: Array<OfflineBook> = await this.list();
      await (await Prefs.getInstance()).putString('offline_v1', JSON.stringify(books.filter((b: OfflineBook) => b.album.id !== key)));
      for (const book of books.filter((b: OfflineBook) => b.album.id === key)) { fs.rmdirSync(book.directory); }
    });
    this.queue = next.catch((): void => {});
    return next;
  }
}
export const offlineStore: OfflineStore = new OfflineStore();
