import common from '@ohos.app.ability.common';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { jmApi } from './JmApi';
import { EhSettings } from './eh/EhSettings';
import { sourceStore, sourceId, sourceKey, SourceEntry, SourceKind } from './Sources';
import { suwayomiLibrary, LibrarySort, RemoteManga, RemoteMangaPage } from './SuwayomiLibrary';
import { Album, AlbumLite, SearchResult, CategoryItem, CommentsResult, DomainSpeed, errorMessage } from '../models/Models';
import { offlineStore } from './OfflineStore';
import { blockTagsStore } from './stores/FilterStores';
import { setAppContext } from '../util/Prefs';
import {
  capabilitiesFor,
  SourceSearchOptions,
  SourceRequestContext,
  SourceStrategy
} from './source/SourceContracts';
import { readUriBytes } from './source/LocalStrategy';
import { definitionFor } from './source/SourceRegistry';
import { RequestAbortGroup } from '../util/RequestAbort';

/** 配置按 sourceId 取到 SourceEntry 后，再用 kind 解析策略。 */
export function strategyFor(kind: SourceKind): SourceStrategy {
  return definitionFor(kind).strategy;
}

/** 阅读、目录和下载共享的图源入口。协议留在各策略里。 */
class SourceApi {
  private covers: Map<string, string> = new Map();

  /** 先写入上下文，再各自初始化图源。单个图源失败不挡住其余图源。 */
  async init(context?: common.Context): Promise<void> {
    if (context !== undefined) {
      setAppContext(context);
    }
    await sourceStore.list();
    const tasks: Array<Promise<void>> = [];
    tasks.push(jmApi.init(context).catch((e: Error): void => {
      hilog.error(0x0000, 'SourceApi', 'jm init: %{public}s', errorMessage(e));
    }));
    if (context !== undefined) {
      tasks.push(EhSettings.init(context).catch((e: Error): void => {
        hilog.error(0x0000, 'SourceApi', 'eh init: %{public}s', errorMessage(e));
      }));
    }
    await Promise.all(tasks);
  }

  async searchSource(source: SourceEntry, query: string, page: number = 1,
    options: SourceSearchOptions | null = null): Promise<SearchResult> {
    const entry: SourceEntry = await sourceStore.get(source.id);
    const start: number = Date.now();
    const context: SourceRequestContext = new SourceRequestContext(entry, '');
    context.searchOptions = options;
    const result: SearchResult = await strategyFor(entry.kind).search(context, query, page);
    result.list = await this.visibleAlbums(result.list);
    await sourceStore.get(source.id);
    source.latency = Date.now() - start;
    for (const item of result.list) {
      this.covers.set(item.id, item.coverUrl);
    }
    return result;
  }

  /** 主搜索只展示一个网关，扩展检索留在远程书库内部。 */
  async searchEntries(): Promise<Array<SourceEntry>> {
    const entries: Array<SourceEntry> = (await sourceStore.list()).filter((item: SourceEntry): boolean =>
      item.enabled && item.kind !== 'suwayomi');
    const gateway: SourceEntry | null = await sourceStore.gateway();
    if (gateway !== null) { gateway.name = 'Suwayomi'; entries.push(gateway); }
    return entries;
  }

  async remoteLibrary(source: SourceEntry, categoryId: number, query: string, sort: LibrarySort,
    after: string, signal: RequestAbortGroup): Promise<RemoteMangaPage> {
    const page: RemoteMangaPage = await suwayomiLibrary.library(source, categoryId, query, sort, after, signal);
    return this.prepareRemotePage(source, page, signal);
  }

  async remoteSearch(source: SourceEntry, remoteId: string, query: string, pageNumber: number,
    signal: RequestAbortGroup): Promise<RemoteMangaPage> {
    const page: RemoteMangaPage = await suwayomiLibrary.browseSource(source, remoteId, query, pageNumber, signal);
    return this.prepareRemotePage(source, page, signal);
  }

  private async prepareRemotePage(source: SourceEntry, page: RemoteMangaPage,
    signal: RequestAbortGroup): Promise<RemoteMangaPage> {
    signal.throwIfAborted();
    const identities: Array<SourceEntry> = await sourceStore.bindSuwayomiSources(source,
      page.items.map((item: RemoteManga): string => item.remoteSourceId));
    signal.throwIfAborted();
    const albums: Array<AlbumLite> = [];
    for (let index: number = 0; index < page.items.length; index++) {
      const item: RemoteManga = page.items[index];
      item.key = sourceKey(identities[index].id, `${item.id}`);
      let blocked: boolean = false;
      for (const tag of item.tags.length === 0 ? [''] : item.tags) {
        if (await blockTagsStore.isBlocked(item.title, item.author, tag, '', identities[index].id)) {
          blocked = true;
          break;
        }
      }
      if (blocked) { continue; }
      const album: AlbumLite = new AlbumLite(item.key, item.title, item.author, item.coverUrl);
      album.category = [item.unread > 0 ? `${item.unread}章未读` : '',
        item.downloaded > 0 ? '已下载' : ''].filter((label: string): boolean => label !== '').join(' / ');
      albums.push(album);
    }
    page.albums = albums;
    signal.throwIfAborted();
    page.items = page.items.filter((item: RemoteManga): boolean =>
      page.albums.some((album: AlbumLite): boolean => album.id === item.key));
    for (const album of page.albums) { this.covers.set(album.id, album.coverUrl); }
    return page;
  }

  /** 本地目录与扩展的热门入口独立于关键词搜索；远端请求格式保持原有约定。 */
  async browseSource(id: string, page: number = 1): Promise<SearchResult> {
    const source: SourceEntry = await sourceStore.get(id);
    if (source.kind !== 'local' && source.kind !== 'suwayomi') { throw new Error('该图源应使用专属浏览入口'); }
    return this.searchSource(source, '', page);
  }

  async album(key: string, refresh: boolean = false, signal: RequestAbortGroup | null = null): Promise<Album> {
    const offline: Album | null = refresh ? null : await offlineStore.album(key);
    if (offline !== null) {
      this.covers.set(key, offline.coverUrl);
      return offline;
    }
    const source: SourceEntry = await sourceStore.get(sourceId(key));
    const album: Album = await strategyFor(source.kind).album(new SourceRequestContext(source, key, signal));
    await sourceStore.get(source.id);
    this.covers.set(key, album.coverUrl);
    return album;
  }

  async chapterImages(key: string, signal: RequestAbortGroup | null = null): Promise<Array<string>> {
    const offline: Array<string> | null = await offlineStore.pages(key);
    if (offline !== null) {
      return offline;
    }
    const source: SourceEntry = await sourceStore.get(sourceId(key));
    const pages: Array<string> = await strategyFor(source.kind).chapterImages(new SourceRequestContext(source, key, signal));
    await sourceStore.get(source.id);
    if (pages.length === 0) {
      throw new Error('本章暂无可阅读的页面');
    }
    return pages;
  }

  async scrambleId(key: string, signal: RequestAbortGroup | null = null): Promise<number> {
    const offline: number | null = await offlineStore.scramble(key);
    if (offline !== null) {
      return offline;
    }
    const source: SourceEntry = await sourceStore.get(sourceId(key), false);
    if (!capabilitiesFor(source.kind).pageRestore) {
      return 0;
    }
    return strategyFor(source.kind).pageRestoreKey(new SourceRequestContext(source, key, signal));
  }

  imageUrl(key: string, filename: string, attempt: number = 0): string {
    const source: SourceEntry | null = sourceStore.peek(sourceId(key));
    return source === null ? filename : strategyFor(source.kind).imageUrl(new SourceRequestContext(source, key), filename, attempt);
  }

  async fetchPage(key: string, page: string, attempt: number = 0,
    signal: RequestAbortGroup | null = null): Promise<ArrayBuffer> {
    const offline: ArrayBuffer | null = await offlineStore.bytes(key, page);
    if (offline !== null) {
      return offline;
    }
    if (signal !== null) {
      signal.throwIfAborted();
    }
    const source: SourceEntry = await sourceStore.get(sourceId(key));
    const bytes: ArrayBuffer = await strategyFor(source.kind).fetchPage(
      new SourceRequestContext(source, key, signal), page, attempt);
    await sourceStore.get(source.id);
    return bytes;
  }

  /** 封面字节按作品主键选择策略，不从 URL 猜测 Suwayomi 实例。 */
  async fetchCover(key: string, url: string, signal: RequestAbortGroup | null = null): Promise<ArrayBuffer> {
    if (url.startsWith('file://')) {
      return readUriBytes(url);
    }
    if (key === '') {
      throw new Error('封面缺少图源标识');
    }
    if (signal !== null) {
      signal.throwIfAborted();
    }
    const source: SourceEntry = await sourceStore.get(sourceId(key), false);
    return strategyFor(source.kind).fetchCover(new SourceRequestContext(source, key, signal), url);
  }

  albumCoverUrl(key: string, attempt: number = 0): string {
    return this.coverUrl(key, attempt, false);
  }

  albumThumbUrl(key: string, attempt: number = 0): string {
    return this.coverUrl(key, attempt, true);
  }

  resolveDirectKey(source: SourceEntry, input: string): string {
    const entry: SourceEntry | null = sourceStore.peek(source.id);
    if (entry === null || !entry.enabled || !capabilitiesFor(entry.kind).idJump) {
      throw new Error('该书源当前不支持编号直达');
    }
    return strategyFor(entry.kind).resolveDirectKey(entry, input);
  }

  searchExpression(source: SourceEntry, namespace: string, value: string, field: string = 'tag'): string {
    const entry: SourceEntry | null = sourceStore.peek(source.id);
    if (entry === null) {
      throw new Error('书源尚未初始化或已移除');
    }
    return strategyFor(entry.kind).searchExpression(namespace, value, field);
  }

  private async visibleAlbums(list: Array<AlbumLite>): Promise<Array<AlbumLite>> {
    const kept: Array<AlbumLite> = [];
    for (const item of list) {
      if (item.id.indexOf('~') < 1) {
        kept.push(item);
        continue;
      }
      const blocked: boolean = await blockTagsStore.isBlocked(
        item.title, item.author, item.category, item.categorySub, sourceId(item.id));
      if (!blocked) {
        kept.push(item);
      }
    }
    return kept;
  }

  async latest(id: string, page: number = 1): Promise<Array<AlbumLite>> {
    const source: SourceEntry = await sourceStore.get(id);
    if (!capabilitiesFor(source.kind).latest) {
      throw new Error('该图源不支持最新列表');
    }
    return this.visibleAlbums(await strategyFor(source.kind).latest(new SourceRequestContext(source), page));
  }

  async random(id: string): Promise<Array<AlbumLite>> {
    const source: SourceEntry = await sourceStore.get(id);
    if (!capabilitiesFor(source.kind).random) {
      throw new Error('该图源不支持随机推荐');
    }
    return this.visibleAlbums(await strategyFor(source.kind).random(new SourceRequestContext(source)));
  }

  async ranking(id: string, category: string, order: string, page: number = 1): Promise<Array<AlbumLite>> {
    const source: SourceEntry = await sourceStore.get(id);
    if (!capabilitiesFor(source.kind).ranking) {
      throw new Error('该图源不支持通用榜单');
    }
    return this.visibleAlbums(await strategyFor(source.kind).ranking(new SourceRequestContext(source), category, order, page));
  }

  async categories(id: string): Promise<Array<CategoryItem>> {
    const source: SourceEntry = await sourceStore.get(id);
    if (!capabilitiesFor(source.kind).categories) {
      throw new Error('该图源不支持通用分类');
    }
    return strategyFor(source.kind).categories(new SourceRequestContext(source));
  }

  async comments(key: string, page: number = 1, signal: RequestAbortGroup | null = null): Promise<CommentsResult> {
    if (signal !== null) {
      signal.throwIfAborted();
    }
    const source: SourceEntry = await sourceStore.get(sourceId(key), false);
    if (!capabilitiesFor(source.kind).comments) {
      return new CommentsResult();
    }
    return strategyFor(source.kind).comments(new SourceRequestContext(source, key, signal), page);
  }

  async testDomains(id: string): Promise<Array<DomainSpeed>> {
    const source: SourceEntry = await sourceStore.get(id);
    if (!capabilitiesFor(source.kind).domainTest) {
      throw new Error('该图源不支持节点测速');
    }
    return strategyFor(source.kind).testDomains(new SourceRequestContext(source));
  }

  private coverUrl(key: string, attempt: number, thumb: boolean): string {
    const cached: string = this.covers.get(key) ?? '';
    const source: SourceEntry | null = sourceStore.peek(sourceId(key));
    if (source === null || !capabilitiesFor(source.kind).computedCover) {
      return cached;
    }
    return strategyFor(source.kind).coverUrl(new SourceRequestContext(source, key), cached, attempt, thumb);
  }
}

export const sourceApi: SourceApi = new SourceApi();
