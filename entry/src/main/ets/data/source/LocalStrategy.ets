import fs from '@ohos.file.fs';
import { localSource } from '../LocalSource';
import { Album, AlbumLite, CategoryItem, CommentsResult, DomainSpeed, SearchResult } from '../../models/Models';
import { SourceEntry, SourceKind, nativeId } from '../Sources';
import { emptyComments, SourceRequestContext, SourceStrategy } from './SourceContracts';

/** file:// 与沙箱路径都走 fs。FileUtil 只接受去掉 scheme 的路径，这里保持原 URI 打开方式。 */
export async function readUriBytes(url: string): Promise<ArrayBuffer> {
  const file: fs.File = fs.openSync(url, fs.OpenMode.READ_ONLY);
  try {
    const buffer: ArrayBuffer = new ArrayBuffer(fs.statSync(file.fd).size);
    if (fs.readSync(file.fd, buffer) !== buffer.byteLength) {
      throw new Error('本地漫画页面读取不完整');
    }
    return buffer;
  } finally {
    fs.closeSync(file);
  }
}

export class LocalStrategy implements SourceStrategy {
  kind: SourceKind = 'local';

  latest(_ctx: SourceRequestContext, _page: number): Promise<Array<AlbumLite>> {
    return Promise.reject(new Error('该图源不支持最新列表'));
  }

  random(_ctx: SourceRequestContext): Promise<Array<AlbumLite>> {
    return Promise.reject(new Error('该图源不支持随机推荐'));
  }

  ranking(_ctx: SourceRequestContext, _category: string, _order: string, _page: number): Promise<Array<AlbumLite>> {
    return Promise.reject(new Error('该图源不支持通用榜单'));
  }

  categories(_ctx: SourceRequestContext): Promise<Array<CategoryItem>> {
    return Promise.reject(new Error('该图源不支持通用分类'));
  }

  testDomains(_ctx: SourceRequestContext): Promise<Array<DomainSpeed>> {
    return Promise.reject(new Error('该图源不支持节点测速'));
  }

  imageUrl(_ctx: SourceRequestContext, page: string, _attempt: number): string {
    return page;
  }

  search(_ctx: SourceRequestContext, query: string, _page: number): Promise<SearchResult> {
    return localSource.search(query);
  }

  album(ctx: SourceRequestContext): Promise<Album> {
    return localSource.album(nativeId(ctx.key));
  }

  chapterImages(ctx: SourceRequestContext): Promise<Array<string>> {
    return localSource.pages(ctx.key);
  }

  fetchPage(_ctx: SourceRequestContext, page: string, _attempt: number): Promise<ArrayBuffer> {
    return readUriBytes(page);
  }

  fetchCover(_ctx: SourceRequestContext, url: string): Promise<ArrayBuffer> {
    return readUriBytes(url);
  }

  coverUrl(_ctx: SourceRequestContext, cached: string, _attempt: number, _thumb: boolean): string {
    return cached;
  }

  comments(_ctx: SourceRequestContext, _page: number): Promise<CommentsResult> {
    return Promise.resolve(emptyComments());
  }

  pageRestoreKey(_ctx: SourceRequestContext): Promise<number> {
    return Promise.resolve(0);
  }

  searchExpression(namespace: string, value: string): string {
    const name: string = value.trim();
    return namespace.trim() === '' ? name : `${namespace.trim()}:${name}`;
  }

  resolveDirectKey(_source: SourceEntry, _input: string): string {
    throw new Error('本地漫画不支持编号直达');
  }
}

export const localStrategy: LocalStrategy = new LocalStrategy();
