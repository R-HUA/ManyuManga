import { ehSource } from '../EhSource';
import { EhTagTranslator } from '../eh/EhNative';
import { Album, AlbumLite, CategoryItem, CommentsResult, DomainSpeed, SearchResult } from '../../models/Models';
import { SourceEntry, SourceKind } from '../Sources';
import { SourceRequestContext, SourceStrategy } from './SourceContracts';

export class EhStrategy implements SourceStrategy {
  kind: SourceKind = 'eh';

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

  search(_ctx: SourceRequestContext, query: string, page: number): Promise<SearchResult> {
    return ehSource.searchSource(query, page);
  }

  album(ctx: SourceRequestContext): Promise<Album> {
    return ehSource.album(ctx.key, ctx.signal === null ? undefined : ctx.signal.control());
  }

  chapterImages(ctx: SourceRequestContext): Promise<Array<string>> {
    return ehSource.chapterImages(ctx.key, ctx.signal === null ? undefined : ctx.signal.control());
  }

  fetchPage(ctx: SourceRequestContext, page: string, attempt: number): Promise<ArrayBuffer> {
    return ehSource.fetchPage(ctx.key, page, attempt, ctx.signal === null ? undefined : ctx.signal.control());
  }

  async fetchCover(ctx: SourceRequestContext, url: string): Promise<ArrayBuffer> {
    const bytes: ArrayBuffer | null = await ehSource.fetchImageBytes(url,
      ctx.signal === null ? undefined : ctx.signal.control());
    if (bytes === null) {
      throw new Error('封面地址不属于当前图源');
    }
    return bytes;
  }

  coverUrl(_ctx: SourceRequestContext, cached: string, _attempt: number, _thumb: boolean): string {
    return cached;
  }

  comments(ctx: SourceRequestContext, page: number): Promise<CommentsResult> {
    return ehSource.comments(ctx.key, page, ctx.signal === null ? undefined : ctx.signal.control());
  }

  pageRestoreKey(_ctx: SourceRequestContext): Promise<number> {
    return Promise.resolve(0);
  }

  searchExpression(namespace: string, value: string): string {
    const name: string = value.trim();
    const ns: string = namespace.trim();
    if (ns === '') {
      return name;
    }
    const prefix: string | undefined = EhTagTranslator.namespaceToPrefix(ns);
    if (prefix !== undefined) {
      return `${prefix}${name}`;
    }
    return `${ns}:${name}`;
  }

  resolveDirectKey(_source: SourceEntry, input: string): string {
    return ehSource.keyFromInput(input);
  }
}

export const ehStrategy: EhStrategy = new EhStrategy();
