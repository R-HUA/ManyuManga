/**
 * entry/src/main/ets/data/SuwayomiLibrary.ets
 * Suwayomi 远程书架数据层。字段名按 Suwayomi-Server master（6b481e8, 2026-10-21）核实：
 * 所有 Long 在 JSON 中是字符串标量；`inLibrary/unreadCount/downloadCount` 已迁到 `user { … }`；
 * 排序使用 `order: [{ by, byType }]`（`orderBy/orderByType` 已废弃）。
 */
import { SourceEntry } from './Sources';
import { suwayomi } from './Suwayomi';
import { asArray, asNumber, asRecord, asString } from '../models/Models';
import { RequestAbortGroup } from '../util/RequestAbort';

export class RemoteCategory {
  id: number = 0;
  name: string = '';
  order: number = 0;
  isDefault: boolean = false;
}

export class RemoteManga {
  id: number = 0;
  title: string = '';
  coverUrl: string = '';
  unread: number = 0;
  downloaded: number = 0;
  inLibrary: boolean = false;
  /** 完整图源身份，跨页时按 sourceKey 组装。 */
  remoteSourceId: string = '';
  url: string = '';
}

export class RemoteChapter {
  id: number = 0;
  name: string = '';
  mangaId: number = 0;
  mangaTitle: string = '';
  chapterNumber: string = '';
  pageCount: number = 0;
  lastPageRead: number = 0;
  read: boolean = false;
  downloaded: boolean = false;
}

export class RemoteSource {
  id: string = '';
  displayName: string = '';
  language: string = '';
  supportsLatest: boolean = false;
}

export class ServerInfo {
  name: string = '';
  version: string = '';
  revision: string = '';
  /** 服务版本过旧时服务端会置位，用来提示升级而不是静默失败。 */
  deprecated: boolean = false;
  reachable: boolean = false;
}

/** 书架排序键，直接对应服务端 MangaOrderBy 枚举。 */
export type LibrarySort = 'recent' | 'title' | 'added';

export const LIBRARY_SORT_LABELS: Array<string> = ['最近阅读', '标题', '最近加入'];

function vars(input: Object): Record<string, Object> {
  const result: Record<string, Object> = {};
  result['input'] = input;
  return result;
}

function sortToEnum(sort: LibrarySort): string {
  if (sort === 'title') {
    return 'TITLE';
  }
  return sort === 'added' ? 'IN_LIBRARY_AT' : 'LAST_FETCHED_AT';
}

class LibraryApi {
  /** 服务端标签：`mangas` 的连接节点。 */
  async categories(source: SourceEntry, signal: RequestAbortGroup | null = null): Promise<Array<RemoteCategory>> {
    const data: Record<string, Object> = await suwayomi.query(source,
      'query { categories { nodes { id name order default } } }', {}, undefined, signal);
    return asArray(record(data['categories'])['nodes'])!.map((value: Object): RemoteCategory => {
      const node: Record<string, Object> = record(value);
      const item: RemoteCategory = new RemoteCategory();
      item.id = asNumber(node['id']);
      item.name = asString(node['name']);
      item.order = asNumber(node['order']);
      item.isDefault = node['default'] === true;
      return item;
    }).sort((a: RemoteCategory, b: RemoteCategory): number => a.order - b.order);
  }

  async library(source: SourceEntry, categoryId: number, keyword: string, sort: LibrarySort,
    after: string, signal: RequestAbortGroup | null = null): Promise<Array<RemoteManga>> {
    const filter: Record<string, Object> = {};
    const inLibrary: Record<string, Object> = {};
    inLibrary['equalTo'] = true;
    filter['inLibrary'] = inLibrary;
    if (categoryId > 0) {
      const cat: Record<string, Object> = {};
      cat['equalTo'] = categoryId;
      filter['categoryId'] = cat;
    }
    if (keyword !== '') {
      const title: Record<string, Object> = {};
      title['contains'] = keyword;
      filter['title'] = title;
    }
    const orderEntry: Record<string, Object> = {};
    orderEntry['by'] = sortToEnum(sort);
    orderEntry['byType'] = sort === 'title' ? 'ASC' : 'DESC';
    const orders: Array<Record<string, Object>> = [orderEntry];
    const variables: Record<string, Object> = {};
    variables['filter'] = filter;
    variables['order'] = orders;
    variables['first'] = 60;
    if (after !== '') {
      variables['after'] = after;
    }
    const data: Record<string, Object> = await suwayomi.query(source,
      'query Library($filter: MangaFilter, $order: [MangaOrder!], $first: Int, $after: Cursor) {' +
      ' mangas(filter: $filter, order: $order, first: $first, after: $after) {' +
      ' nodes { id sourceId url title thumbnailUrl user { inLibrary unreadCount downloadCount } }' +
      ' pageInfo { hasNextPage endCursor } totalCount } }', variables, undefined, signal);
    const page: Record<string, Object> = record(data['mangas']);
    const nodes: Array<Object> | null = asArray(page['nodes']);
    if (nodes === null) {
      throw new Error('服务端缺少远程书架数据');
    }
    return nodes.map((value: Object): RemoteManga => {
      const node: Record<string, Object> = record(value);
      const user: Record<string, Object> = asRecord(node['user']) ?? {};
      const item: RemoteManga = new RemoteManga();
      item.id = asNumber(node['id']);
      item.title = asString(node['title']);
      item.url = asString(node['url']);
      item.remoteSourceId = asString(node['sourceId']);
      item.coverUrl = absolute(source, asString(node['thumbnailUrl']));
      item.unread = asNumber(user['unreadCount']);
      item.downloaded = asNumber(user['downloadCount']);
      item.inLibrary = user['inLibrary'] === true;
      return item;
    });
  }

  /** 加入/移出远程书架：服务端没有专用 add/remove 接口，靠 patch.inLibrary。 */
  async setInLibrary(source: SourceEntry, mangaId: number, inLibrary: boolean): Promise<void> {
    const patch: Record<string, Object> = {};
    patch['inLibrary'] = inLibrary;
    const input: Record<string, Object> = {};
    input['id'] = mangaId;
    input['patch'] = patch;
    await suwayomi.query(source,
      'mutation Lib($input: UpdateMangaInput!) { updateManga(input: $input) { manga { id } } }', vars(input));
  }

  /** 分类是增量语义（加入/移出/清空），不是绝对集合。 */
  async assignCategories(source: SourceEntry, mangaId: number, addTo: Array<number>,
    removeFrom: Array<number>): Promise<void> {
    const patch: Record<string, Object> = {};
    if (addTo.length > 0) {
      patch['addToCategories'] = addTo;
    }
    if (removeFrom.length > 0) {
      patch['removeFromCategories'] = removeFrom;
    }
    const input: Record<string, Object> = {};
    input['id'] = mangaId;
    input['patch'] = patch;
    await suwayomi.query(source,
      'mutation Cat($input: UpdateMangaCategoriesInput!) { updateMangaCategories(input: $input) { manga { id } } }',
      vars(input));
  }

  /** 下载入队：payload 是 DownloadStatus{state, queue}，queue 项含 chapterId/state/progress。 */
  async enqueueDownload(source: SourceEntry, chapterIds: Array<number>): Promise<void> {
    const input: Record<string, Object> = {};
    input['ids'] = chapterIds;
    await suwayomi.query(source,
      'mutation Dl($input: EnqueueChapterDownloadsInput!) { enqueueChapterDownloads(input: $input) {' +
      ' downloadStatus { state queue { chapterId state progress } } } }', vars(input));
  }

  /** 最近更新流：服务端没有 downloads 查询，这里用新抓取章节作为 feed。 */
  async recentChapters(source: SourceEntry, limit: number,
    signal: RequestAbortGroup | null = null): Promise<Array<RemoteChapter>> {
    const orderEntry: Record<string, Object> = {};
    orderEntry['by'] = 'FETCHED_AT';
    orderEntry['byType'] = 'DESC';
    const variables: Record<string, Object> = {};
    variables['order'] = [orderEntry];
    variables['first'] = limit;
    const data: Record<string, Object> = await suwayomi.query(source,
      'query Recent($order: [ChapterOrder!], $first: Int) { chapters(order: $order, first: $first) {' +
      ' nodes { id name mangaId chapterNumber pageCount' +
      ' user { isRead isDownloaded lastPageRead } manga { id title } } } }', variables, undefined, signal);
    const nodes: Array<Object> | null = asArray(record(data['chapters'])['nodes']);
    if (nodes === null) {
      return [];
    }
    return nodes.map((value: Object): RemoteChapter => {
      const node: Record<string, Object> = record(value);
      const user: Record<string, Object> = asRecord(node['user']) ?? {};
      const manga: Record<string, Object> = asRecord(node['manga']) ?? {};
      const item: RemoteChapter = new RemoteChapter();
      item.id = asNumber(node['id']);
      item.name = asString(node['name']);
      item.mangaId = asNumber(node['mangaId']);
      item.mangaTitle = asString(manga['title']);
      item.chapterNumber = asString(node['chapterNumber']);
      item.pageCount = asNumber(node['pageCount']);
      item.lastPageRead = asNumber(user['lastPageRead']);
      item.read = user['isRead'] === true;
      item.downloaded = user['isDownloaded'] === true;
      return item;
    });
  }

  /** 服务端已安装的图源，用于书架内的跨源聚合检索。 */
  async serverSources(source: SourceEntry, signal: RequestAbortGroup | null = null): Promise<Array<RemoteSource>> {
    const data: Record<string, Object> = await suwayomi.query(source,
      'query { sources { nodes { id displayName lang supportsLatest } } }', {}, undefined, signal);
    const nodes: Array<Object> | null = asArray(record(data['sources'])['nodes']);
    if (nodes === null) {
      return [];
    }
    return nodes.map((value: Object): RemoteSource => {
      const node: Record<string, Object> = record(value);
      const item: RemoteSource = new RemoteSource();
      item.id = asString(node['id']);
      item.displayName = asString(node['displayName'], asString(node['name']));
      item.language = asString(node['lang']);
      item.supportsLatest = node['supportsLatest'] === true;
      return item;
    });
  }

  /** 聚合检索结果转成本机身份键，避免服务端编号跨实例串台。 */
  async browseSource(source: SourceEntry, remoteSourceId: string, keyword: string,
    page: number): Promise<Array<RemoteManga>> {
    const input: Record<string, Object> = {};
    input['source'] = remoteSourceId;
    input['type'] = keyword === '' ? 'POPULAR' : 'SEARCH';
    input['page'] = page;
    input['query'] = keyword;
    const data: Record<string, Object> = await suwayomi.query(source,
      'mutation Browse($input: FetchSourceMangaInput!) { fetchSourceManga(input: $input) {' +
      ' mangas { id title thumbnailUrl user { inLibrary } } hasNextPage } }', vars(input));
    const nodes: Array<Object> | null = asArray(record(data['fetchSourceManga'])['mangas']);
    if (nodes === null) {
      return [];
    }
    return nodes.map((value: Object): RemoteManga => {
      const node: Record<string, Object> = record(value);
      const user: Record<string, Object> = asRecord(node['user']) ?? {};
      const item: RemoteManga = new RemoteManga();
      item.id = asNumber(node['id']);
      item.title = asString(node['title']);
      item.coverUrl = absolute(source, asString(node['thumbnailUrl']));
      item.remoteSourceId = remoteSourceId;
      item.inLibrary = user['inLibrary'] === true;
      return item;
    });
  }

  /** aboutServer 不需要鉴权，最适合做连通性与端口探测。 */
  async probe(endpoint: string, lanEndpoint: string, headers: string): Promise<ServerInfo> {
    const info: ServerInfo = new ServerInfo();
    const probe: SourceEntry = new SourceEntry('probe', 'Suwayomi', 'suwayomi');
    probe.endpoint = endpoint;
    probe.lanEndpoint = lanEndpoint;
    probe.customHeaders = headers;
    probe.auth = 'none';
    try {
      const data: Record<string, Object> = await suwayomi.query(probe,
        'query { aboutServer { name version revision deprecated } }', {});
      const node: Record<string, Object> = record(data['aboutServer']);
      info.name = asString(node['name'], 'Suwayomi');
      info.version = asString(node['version']);
      info.revision = asString(node['revision']);
      info.deprecated = node['deprecated'] === true;
      info.reachable = true;
    } catch (e) {
      info.reachable = false;
    }
    return info;
  }

  /** 服务端管理后台入口：客户端不做扩展仓库安装器。 */
  webUiUrl(source: SourceEntry): string {
    return `${source.endpoint}/`;
  }
}

function record(value: Object | undefined): Record<string, Object> {
  const result: Record<string, Object> | null = asRecord(value);
  if (result === null) {
    throw new Error('服务端返回的数据格式不正确');
  }
  return result;
}

function absolute(source: SourceEntry, path: string): string {
  if (/^https?:\/\//.test(path)) {
    return path;
  }
  if (path === '') {
    return '';
  }
  return `${source.endpoint}${path.startsWith('/') ? '' : '/'}${path}`;
}

export const suwayomiLibrary: LibraryApi = new LibraryApi();
