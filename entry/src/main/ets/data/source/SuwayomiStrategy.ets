import { suwayomi } from '../Suwayomi';
import { httpUtil } from '../../util/Http';
import { Album, AlbumLite, CategoryItem, CommentsResult, DomainSpeed, SearchResult } from '../../models/Models';
import { SourceEntry, SourceKind, nativeId } from '../Sources';
import { emptyComments, SourceRequestContext, SourceStrategy } from './SourceContracts';

/**
 * 页和封面都使用调用方给出的 SourceEntry，不从图片 URL 反推实例。
 */
export class SuwayomiStrategy implements SourceStrategy {
  kind: SourceKind = 'suwayomi';

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

  search(ctx: SourceRequestContext, query: string, page: number): Promise<SearchResult> {
    return suwayomi.search(ctx.source, query, page);
  }

  album(ctx: SourceRequestContext): Promise<Album> {
    return suwayomi.album(ctx.source, nativeId(ctx.key), ctx.signal);
  }

  chapterImages(ctx: SourceRequestContext): Promise<Array<string>> {
    return suwayomi.pages(ctx.source, nativeId(ctx.key), ctx.signal);
  }

  async fetchPage(ctx: SourceRequestContext, page: string, _attempt: number): Promise<ArrayBuffer> {
    if (ctx.signal !== null) {
      ctx.signal.throwIfAborted();
    }
    return httpUtil.getBytes(page, await suwayomi.headers(ctx.source), 5000, 12000, 15000, ctx.signal);
  }

  fetchCover(ctx: SourceRequestContext, url: string): Promise<ArrayBuffer> {
    return this.fetchPage(ctx, url, 0);
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
    throw new Error('该图源不支持编号直达');
  }
}

export const suwayomiStrategy: SuwayomiStrategy = new SuwayomiStrategy();
