import { Album, AlbumLite, CategoryItem, CommentsResult, DomainSpeed, SearchResult } from '../../models/Models';
import { SourceEntry, SourceKind, sourceStore } from '../Sources';
import { RequestAbortGroup } from '../../util/RequestAbort';
import { definitionFor } from './SourceRegistry';

/**
 * 一次图源调用的身份。
 * 作品 / 章节 / 封面都带复合主键；协议、Cookie 和还原参数留在各策略内部。
 */
export class SourceRequestContext {
  source: SourceEntry;
  /** sourceKey(sourceId, nativeId)。列表搜索可为空。 */
  key: string;
  /** 非空时，该次图源请求归入这一组；组作废后不得复用。 */
  signal: RequestAbortGroup | null = null;

  constructor(source: SourceEntry, key: string = '', signal: RequestAbortGroup | null = null) {
    this.source = source;
    this.key = key;
    this.signal = signal;
  }
}

/** 共享页面只问能力，不问图源种类。 */
export class SourceCapabilities {
  kind: SourceKind | null = null;
  latest: boolean = false;
  random: boolean = false;
  ranking: boolean = false;
  categories: boolean = false;
  domainTest: boolean = false;
  comments: boolean = false;
  idJump: boolean = false;
  idJumpNumeric: boolean = false;
  searchPaging: boolean = true;
  /** 封面字节必须带图源身份（登录 Cookie 或服务端鉴权），不能直接用 Image 拉 URL。 */
  signedCover: boolean = false;
  /** 阅读页解码后需要图源内部还原。 */
  pageRestore: boolean = false;
  /** 封面地址由策略按作品号计算，而不是只信列表缓存。 */
  computedCover: boolean = false;
  importPackage: boolean = false;
}

/** 图源策略：搜索、详情、章节页、页字节、封面、评论。 */
export interface SourceStrategy {
  kind: SourceKind;
  search(ctx: SourceRequestContext, query: string, page: number): Promise<SearchResult>;
  latest(ctx: SourceRequestContext, page: number): Promise<Array<AlbumLite>>;
  random(ctx: SourceRequestContext): Promise<Array<AlbumLite>>;
  ranking(ctx: SourceRequestContext, category: string, order: string, page: number): Promise<Array<AlbumLite>>;
  categories(ctx: SourceRequestContext): Promise<Array<CategoryItem>>;
  testDomains(ctx: SourceRequestContext): Promise<Array<DomainSpeed>>;
  imageUrl(ctx: SourceRequestContext, page: string, attempt: number): string;
  album(ctx: SourceRequestContext): Promise<Album>;
  chapterImages(ctx: SourceRequestContext): Promise<Array<string>>;
  fetchPage(ctx: SourceRequestContext, page: string, attempt: number): Promise<ArrayBuffer>;
  fetchCover(ctx: SourceRequestContext, url: string): Promise<ArrayBuffer>;
  coverUrl(ctx: SourceRequestContext, cached: string, attempt: number, thumb: boolean): string;
  comments(ctx: SourceRequestContext, page: number): Promise<CommentsResult>;
  pageRestoreKey(ctx: SourceRequestContext): Promise<number>;
  resolveDirectKey(source: SourceEntry, input: string): string;
  /** 把已缓存标签变成该图源自己的搜索串。空命名空间允许。 */
  searchExpression(namespace: string, value: string, field: string): string;
}

export function emptyComments(): CommentsResult {
  return new CommentsResult();
}

export function capabilitiesFor(kind: SourceKind): SourceCapabilities {
  return definitionFor(kind).capabilities;
}

/**
 * 同步能力只读取已初始化配置；缺失身份返回无能力。
 */
export function capabilitiesForSourceId(id: string): SourceCapabilities {
  const entry: SourceEntry | null = sourceStore.peek(id);
  return entry === null ? new SourceCapabilities() : capabilitiesFor(entry.kind);
}
