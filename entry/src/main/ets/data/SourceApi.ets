import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import { jmApi } from './JmApi';
import { suwayomi } from './Suwayomi';
import { localSource } from './LocalSource';
import { sourceStore, sourceId, nativeId, sourceKey, SourceEntry } from './Sources';
import { Album, AlbumLite, SearchResult, Chapter, CategoryItem, CommentsResult, DomainSpeed } from '../models/Models';
import { httpUtil } from '../util/Http';
import { offlineStore } from './OfflineStore';

/** 阅读、目录和下载共享同一来源契约。 */
export interface SourceAdapter {
  searchSource(source: SourceEntry, query: string, page: number): Promise<SearchResult>;
  album(key: string): Promise<Album>;
  chapterImages(key: string): Promise<Array<string>>;
  fetchPage(key: string, page: string, attempt: number): Promise<ArrayBuffer>;
}
class SourceApi implements SourceAdapter {
  private covers: Map<string, string> = new Map();
  async init(context?: common.Context): Promise<void> { await jmApi.init(context); }
  private qualify(list: Array<AlbumLite>): Array<AlbumLite> {
    return list.map((item: AlbumLite): AlbumLite => new AlbumLite(sourceKey('jm', item.id),
      item.title, item.author, item.coverUrl, item.category, item.categorySub));
  }
  async searchSource(source: SourceEntry, query: string, page: number = 1): Promise<SearchResult> {
    await sourceStore.get(source.id);
    const start: number = Date.now();
    let result: SearchResult;
    if (source.kind === 'jm') {
      if (query === '') { result = new SearchResult(0, this.qualify(await jmApi.latest(page))); }
      else {
        const raw: SearchResult = await jmApi.search(query, page);
        result = new SearchResult(raw.total, this.qualify(raw.list));
      }
    } else if (source.kind === 'local') { result = await localSource.search(query); }
    else { result = await suwayomi.search(source, query, page); }
    await sourceStore.get(source.id);
    source.latency = Date.now() - start;
    for (const item of result.list) { this.covers.set(item.id, item.coverUrl); }
    return result;
  }
  async album(key: string, refresh: boolean = false): Promise<Album> {
    const offline: Album | null = refresh ? null : await offlineStore.album(key);
    if (offline !== null) { this.covers.set(key, offline.coverUrl); return offline; }
    const source: SourceEntry = await sourceStore.get(sourceId(key));
    let album: Album;
    if (source.kind === 'jm') {
      album = await jmApi.album(nativeId(key));
      album.id = key;
      album.episodes = album.episodes.map((c: Chapter) => new Chapter(sourceKey(source.id, c.id), c.title, c.sort));
      album.coverUrl = jmApi.albumCoverUrl(nativeId(key));
    } else if (source.kind === 'local') { album = await localSource.album(nativeId(key)); }
    else { album = await suwayomi.album(source, nativeId(key)); }
    await sourceStore.get(source.id);
    this.covers.set(key, album.coverUrl);
    return album;
  }
  async chapterImages(key: string): Promise<Array<string>> {
    const offline: Array<string> | null = await offlineStore.pages(key);
    if (offline !== null) { return offline; }
    const source: SourceEntry = await sourceStore.get(sourceId(key));
    let pages: Array<string>;
    if (source.kind === 'jm') { pages = await jmApi.chapterImages(nativeId(key)); }
    else if (source.kind === 'local') { pages = await localSource.pages(key); }
    else { pages = await suwayomi.pages(source, nativeId(key)); }
    await sourceStore.get(source.id);
    if (pages.length === 0) { throw new Error('本章暂无可阅读的页面'); }
    return pages;
  }
  async scrambleId(key: string): Promise<number> {
    const offline: number | null = await offlineStore.scramble(key);
    if (offline !== null) { return offline; }
    return sourceId(key) === 'jm' ? jmApi.scrambleId(nativeId(key)) : 0;
  }
  imageUrl(key: string, filename: string, attempt: number = 0): string {
    return sourceId(key) === 'jm' ? jmApi.imageUrl(nativeId(key), filename, attempt) : filename;
  }
  async fetchPage(key: string, page: string, attempt: number = 0): Promise<ArrayBuffer> {
    const offline: ArrayBuffer | null = await offlineStore.bytes(key, page);
    if (offline !== null) { return offline; }
    const source: SourceEntry = await sourceStore.get(sourceId(key));
    const bytes: ArrayBuffer = source.kind === 'jm' ? await jmApi.fetchBytes(this.imageUrl(key, page, attempt))
      : await this.fetchBytes(page);
    await sourceStore.get(source.id);
    return bytes;
  }
  async fetchBytes(url: string): Promise<ArrayBuffer> {
    if (url.startsWith('file://')) {
      const file: fs.File = fs.openSync(url, fs.OpenMode.READ_ONLY);
      try {
        const buffer: ArrayBuffer = new ArrayBuffer(fs.statSync(file.fd).size);
        if (fs.readSync(file.fd, buffer) !== buffer.byteLength) { throw new Error('本地漫画页面读取不完整'); }
        return buffer;
      } finally { fs.closeSync(file); }
    }
    const source: SourceEntry | undefined = (await sourceStore.list()).find((s: SourceEntry) =>
      s.kind === 'suwayomi' && url.startsWith(`${s.endpoint}/`));
    return source === undefined ? jmApi.fetchBytes(url) : httpUtil.getBytes(url, await suwayomi.headers(source));
  }
  albumCoverUrl(key: string, attempt: number = 0): string {
    return sourceId(key) === 'jm' ? jmApi.albumCoverUrl(nativeId(key), attempt) : this.covers.get(key) ?? '';
  }
  albumThumbUrl(key: string, attempt: number = 0): string { return this.albumCoverUrl(key, attempt); }
  async latest(page: number = 1): Promise<Array<AlbumLite>> { return this.qualify(await jmApi.latest(page)); }
  async random(): Promise<Array<AlbumLite>> { return this.qualify(await jmApi.random()); }
  async ranking(category: string, order: string, page: number = 1): Promise<Array<AlbumLite>> {
    return this.qualify(await jmApi.ranking(category, order, page));
  }
  async categories(): Promise<Array<CategoryItem>> { return jmApi.categories(); }
  async comments(key: string, page: number = 1): Promise<CommentsResult> {
    return sourceId(key) === 'jm' ? jmApi.comments(nativeId(key), page) : new CommentsResult();
  }
  async search(query: string, page: number = 1, order: string = 'mr', time: string = 'a', year: string = '', month: string = ''): Promise<SearchResult> {
    const raw: SearchResult = await jmApi.search(query, page, order, time, year, month);
    return new SearchResult(raw.total, this.qualify(raw.list));
  }
  async testDomains(): Promise<Array<DomainSpeed>> { return jmApi.testDomains(); }
}
export const sourceApi: SourceApi = new SourceApi();
