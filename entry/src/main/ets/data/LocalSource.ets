import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import zlib from '@ohos.zlib';
import { Album, AlbumLite, Chapter, MetadataTerm, SearchResult, asArray, asRecord, asString } from '../models/Models';
import { albumMatchesText } from './SearchQuery';
import { getAppContext } from '../util/Prefs';
import { sourceKey } from './Sources';
import { loadLocalBooks, LocalBookRow } from './db/ContentDao';
import { assertDatabaseGeneration, databaseGeneration, dbTransaction } from './db/AppDatabase';
import { albumToJson, syncAlbumRelations, txUpsert } from './db/RowCodec';
import { StoreQueue } from './stores/StoreSupport';
import { relationalStore } from '@kit.ArkData';

class LocalBook {
  album: Album = new Album();
  files: Record<string, Array<string>> = {};
}
function filesFromJson(text: string): Record<string, Array<string>> {
  const out: Record<string, Array<string>> = {};
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(text) as Object;
  } catch (e) {
    throw new Error('本地漫画文件清单已损坏，请重新导入');
  }
  const rec: Record<string, Object> | null = asRecord(parsed);
  if (rec === null) {
    throw new Error('本地漫画文件清单格式无效，请重新导入');
  }
  const keys: Array<string> = Object.keys(rec);
  for (const key of keys) {
    const arr: Array<Object> | null = asArray(rec[key]);
    if (arr === null) { throw new Error('本地漫画章节文件清单格式无效'); }
    const paths: Array<string> = [];
    for (const item of arr) {
      const path: string = asString(item);
      if (path === '') { throw new Error('本地漫画图片路径无效'); }
      paths.push(path);
    }
    out[key] = paths;
  }
  return out;
}
function natural(a: string, b: string): number {
  const aa: Array<string> = a.toLowerCase().match(/\d+|\D+/g) ?? [];
  const bb: Array<string> = b.toLowerCase().match(/\d+|\D+/g) ?? [];
  for (let i: number = 0; i < Math.min(aa.length, bb.length); i++) {
    if (aa[i] === bb[i]) { continue; }
    if (/^\d+$/.test(aa[i]) && /^\d+$/.test(bb[i])) { return Number(aa[i]) - Number(bb[i]); }
    return aa[i] < bb[i] ? -1 : 1;
  }
  return aa.length - bb.length;
}

/** 导入完成才发布书目，应用始终读取沙箱副本。 */
class LocalSource {
  private queue: StoreQueue = new StoreQueue();
  private books: Array<LocalBook> = [];
  private loading: Promise<void> | null = null;
  private async load(): Promise<void> {
    const generation: number = databaseGeneration();
    const rows: Array<LocalBookRow> = await loadLocalBooks();
    assertDatabaseGeneration(generation);
    const books: Array<LocalBook> = [];
    for (const row of rows) {
      const book: LocalBook = new LocalBook();
      book.album = row.album;
      book.files = filesFromJson(row.filesJson);
      books.push(book);
    }
    this.books = books;
  }
  private async ready(): Promise<void> {
    if (this.loading === null) {
      this.loading = this.load().catch((error: Error): void => {
        this.loading = null;
        throw error;
      });
    }
    await this.loading;
  }
  invalidate(): void {
    this.loading = null;
    this.books = [];
  }
  async search(query: string): Promise<SearchResult> {
    await this.ready();
    const list: Array<AlbumLite> = this.books.filter((b: LocalBook) => albumMatchesText(b.album, query))
      .map((b: LocalBook) => new AlbumLite(b.album.id, b.album.name,
        b.album.author.map((term: MetadataTerm): string => term.label).join(' · '), b.album.coverUrl));
    return new SearchResult(list.length, list);
  }
  async album(id: string): Promise<Album> {
    await this.ready();
    const book: LocalBook | undefined = this.books.find((b: LocalBook) => b.album.id === sourceKey('local', id));
    if (book === undefined) { throw new Error('本地漫画文件不存在，请重新导入'); }
    return book.album;
  }
  async pages(chapterId: string): Promise<Array<string>> {
    await this.ready();
    for (const book of this.books) {
      if (book.files[chapterId] !== undefined) { return book.files[chapterId].slice(); }
    }
    throw new Error('本地章节文件不存在');
  }
  async importFiles(title: string): Promise<Album | null> {
    const generation: number = databaseGeneration();
    const dialog: picker.DocumentViewPicker = new picker.DocumentViewPicker(getAppContext());
    const uris: Array<string> = await dialog.select({
      maxSelectNumber: 500,
      fileSuffixFilters: ['漫画文件|.cbz,.zip,.jpg,.jpeg,.png,.webp,.gif']
    });
    if (uris.length === 0) { return null; }
    const archives: Array<string> = uris.filter((u: string) => /\.(cbz|zip)$/i.test(decodeURIComponent(u)));
    if (archives.length > 0 && uris.length !== 1) { throw new Error('请一次导入一个漫画压缩包，或选择同一本漫画的图片'); }
    const id: string = `${Date.now()}`;
    const root: string = `${getAppContext().filesDir}/local/${id}`;
    fs.mkdirSync(root, true);
    try {
      const names: Array<string> = [];
      uris.sort((a: string, b: string) => natural(decodeURIComponent(a), decodeURIComponent(b)));
      for (let i: number = 0; i < uris.length; i++) {
        const input: fs.File = fs.openSync(uris[i], fs.OpenMode.READ_ONLY);
        const name: string = decodeURIComponent(uris[i].substring(uris[i].lastIndexOf('/') + 1));
        try { fs.copyFileSync(input.fd, `${root}/${archives.length > 0 ? 'import.zip' : `${i.toString().padStart(5, '0')}_${name}`}`); }
        finally { fs.closeSync(input); }
        names.push(name);
      }
      if (archives.length > 0) {
        await zlib.decompressFile(`${root}/import.zip`, root);
        fs.unlinkSync(`${root}/import.zip`);
      }
      const files: Array<string> = fs.listFileSync(root, { recursion: true }).filter((p: string) => /\.(jpe?g|png|webp|gif)$/i.test(p)).sort(natural);
      if (files.length === 0) { throw new Error('所选文件中没有可阅读的图片'); }
      const book: LocalBook = new LocalBook();
      book.album = new Album(sourceKey('local', id), title.trim() || names[0].replace(/\.[^.]+$/, ''));
      book.album.coverUrl = `file://${root}/${files[0]}`;
      const folders: Array<string> = [];
      for (const path of files) {
        const cut: number = path.lastIndexOf('/');
        const folder: string = cut < 0 ? '' : path.substring(0, cut);
        if (!folders.includes(folder)) { folders.push(folder); }
        const chapter: string = sourceKey('local', `${id}/${folder}`);
        if (book.files[chapter] === undefined) { book.files[chapter] = []; }
        book.files[chapter].push(`file://${root}/${path}`);
      }
      book.album.episodes = folders.map((folder: string, index: number) =>
        new Chapter(sourceKey('local', `${id}/${folder}`), folder || '正文', `${index + 1}`));
      const metadata: string | undefined = fs.listFileSync(root, { recursion: true }).find((p: string) => /(^|\/)ComicInfo\.xml$/i.test(p));
      if (metadata !== undefined) {
        const xml: string = fs.readTextSync(`${root}/${metadata}`);
        const name: RegExpMatchArray | null = xml.match(/<Title>([^<]+)<\/Title>/i);
        const author: RegExpMatchArray | null = xml.match(/<Writer>([^<]+)<\/Writer>/i);
        if (title.trim() === '' && name !== null) { book.album.name = name[1]; }
        if (author !== null) { book.album.author = [new MetadataTerm(author[1])]; }
      }
      assertDatabaseGeneration(generation);
      await this.queue.run(async (): Promise<void> => {
        assertDatabaseGeneration(generation);
        await dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
          await txUpsert(tx, 'local_book', ['book_id'], ['book_id', 'payload', 'files_json', 'updated_at'],
            [book.album.id, albumToJson(book.album), JSON.stringify(book.files), Date.now()]);
          await syncAlbumRelations(tx, book.album);
        });
        this.invalidate();
      });
      return book.album;
    } catch (e) {
      fs.rmdirSync(root);
      throw e as Error;
    }
  }
}
export const localSource: LocalSource = new LocalSource();
