import { jmApi } from '../JmApi';
import { Album, Chapter, AlbumLite, CategoryItem, CommentsResult, DomainSpeed, SearchOptions, SearchResult } from '../../models/Models';
import { SourceEntry, SourceKind, sourceKey, nativeId } from '../Sources';
import { SourceRequestContext, SourceStrategy } from './SourceContracts';

export class JmStrategy implements SourceStrategy {
  kind: SourceKind = 'jm';

  async latest(ctx: SourceRequestContext, page: number): Promise<Array<AlbumLite>> {
    return this.qualifyAlbums(await jmApi.latest(page), ctx.source.id);
  }

  async random(ctx: SourceRequestContext): Promise<Array<AlbumLite>> {
    return this.qualifyAlbums(await jmApi.random(), ctx.source.id);
  }

  async ranking(ctx: SourceRequestContext, category: string, order: string, page: number): Promise<Array<AlbumLite>> {
    return this.qualifyAlbums(await jmApi.ranking(category, order, page), ctx.source.id);
  }

  categories(_ctx: SourceRequestContext): Promise<Array<CategoryItem>> {
    return jmApi.categories();
  }

  testDomains(_ctx: SourceRequestContext): Promise<Array<DomainSpeed>> {
    return jmApi.testDomains();
  }

  imageUrl(ctx: SourceRequestContext, page: string, attempt: number): string {
    return jmApi.imageUrl(nativeId(ctx.key), page, attempt);
  }

  async search(ctx: SourceRequestContext, query: string, page: number): Promise<SearchResult> {
    if (query === '' && ctx.searchOptions === null) {
      return new SearchResult(0, this.qualifyAlbums(await jmApi.latest(page), ctx.source.id));
    }
    // 关键词为空但带筛选条件（来自“应用筛选”）时，按筛选条件做空关键词检索。
    const filter: SearchOptions = ctx.searchOptions === null ? new SearchOptions() : ctx.searchOptions.jm;
    const raw: SearchResult = await jmApi.search(query, page, filter.order, filter.time, filter.year, filter.month);
    return new SearchResult(raw.total, this.qualifyAlbums(raw.list, ctx.source.id));
  }

  qualifyAlbums(list: Array<AlbumLite>, id: string = 'jm'): Array<AlbumLite> {
    return list.map((item: AlbumLite): AlbumLite => new AlbumLite(sourceKey(id, item.id),
      item.title, item.author, item.coverUrl, item.category, item.categorySub));
  }

  async album(ctx: SourceRequestContext): Promise<Album> {
    const id: string = nativeId(ctx.key);
    const album: Album = await jmApi.album(id, ctx.signal);
    album.id = ctx.key;
    album.episodes = album.episodes.map((c: Chapter): Chapter =>
      new Chapter(sourceKey(ctx.source.id, c.id), c.title, c.sort));
    album.coverUrl = jmApi.albumCoverUrl(id);
    return album;
  }

  chapterImages(ctx: SourceRequestContext): Promise<Array<string>> {
    return jmApi.chapterImages(nativeId(ctx.key), ctx.signal);
  }

  fetchPage(ctx: SourceRequestContext, page: string, attempt: number): Promise<ArrayBuffer> {
    if (ctx.signal !== null) {
      ctx.signal.throwIfAborted();
    }
    return jmApi.fetchBytes(jmApi.imageUrl(nativeId(ctx.key), page, attempt), ctx.signal);
  }

  fetchCover(ctx: SourceRequestContext, url: string): Promise<ArrayBuffer> {
    if (ctx.signal !== null) {
      ctx.signal.throwIfAborted();
    }
    return jmApi.fetchBytes(url, ctx.signal);
  }

  coverUrl(ctx: SourceRequestContext, _cached: string, attempt: number, thumb: boolean): string {
    const id: string = nativeId(ctx.key);
    return thumb ? jmApi.albumThumbUrl(id, attempt) : jmApi.albumCoverUrl(id, attempt);
  }

  comments(ctx: SourceRequestContext, page: number): Promise<CommentsResult> {
    return jmApi.comments(nativeId(ctx.key), page, ctx.signal);
  }

  pageRestoreKey(ctx: SourceRequestContext): Promise<number> {
    return jmApi.scrambleId(nativeId(ctx.key), ctx.signal);
  }

  searchExpression(_namespace: string, value: string, _field: string = 'tag'): string {
    return value.trim();
  }

  resolveDirectKey(source: SourceEntry, input: string): string {
    const clean: string = input.trim().replace(/^[jJ][mM]/, '');
    if (!/^\d+$/.test(clean)) {
      throw new Error('请输入有效的纯数字漫画编号');
    }
    return sourceKey(source.id, clean);
  }

}

export const jmStrategy: JmStrategy = new JmStrategy();
