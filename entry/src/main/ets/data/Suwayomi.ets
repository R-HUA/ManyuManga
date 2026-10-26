import http from '@ohos.net.http';
import util from '@ohos.util';
import { SourceEntry, SourceAuth, SourceInstance, sourceKey, sourceStore, readSourceSecret, saveSourceSecret } from './Sources';
import { Album, AlbumLite, Chapter, MetadataTerm, SearchResult, asRecord, asArray, asString, asNumber } from '../models/Models';
import { utf8Encode } from './JmApi';
import { isRequestCancelled, RequestAbortGroup, RequestCancelled } from '../util/RequestAbort';
import { assertDatabaseGeneration, databaseGeneration } from './db/AppDatabase';

function record(value: Object | undefined): Record<string, Object> {
  const result: Record<string, Object> | null = asRecord(value);
  if (result === null) {
    throw new Error('服务端返回的数据格式不正确');
  }
  return result;
}
function array(value: Object | undefined): Array<Object> {
  const result: Array<Object> | null = asArray(value);
  if (result === null) {
    throw new Error('服务端缺少列表数据');
  }
  return result;
}
function absolute(source: SourceEntry, path: string): string {
  if (/^https?:\/\//.test(path)) {
    return path;
  }
  return path === '' ? '' : `${source.endpoint}${path.startsWith('/') ? '' : '/'}${path}`;
}
interface LoginInput { username: string; password: string; }
interface BrowseInput { source: string; type: string; page: number; query: string; }
interface DetailInput { id: number; fetchManga: boolean; fetchChapters: boolean; }
interface PagesInput { chapterId: number; }
function variables(input: Object): Record<string, Object> {
  const result: Record<string, Object> = {};
  result['input'] = input;
  return result;
}

/** 使用稳定服务端的内容接口，所有本机阅读状态仍由本机保存。 */
export class SuwayomiClient {
  async headers(source: SourceEntry): Promise<Record<string, string>> {
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (source.auth !== 'none') {
      headers['Authorization'] = await readSourceSecret(source.instanceId);
    }
    return headers;
  }
  async query(source: SourceEntry, query: string, variables: Record<string, Object>,
    authorization?: string, signal: RequestAbortGroup | null = null): Promise<Record<string, Object>> {
    if (signal !== null) {
      signal.throwIfAborted();
    }
    const request: http.HttpRequest = http.createHttp();
    if (signal !== null) {
      signal.track(request);
    }
    try {
      const headers: Record<string, string> = authorization === undefined ? await this.headers(source) : { 'Content-Type': 'application/json', 'Authorization': authorization };
      const response: http.HttpResponse = await request.request(`${source.endpoint}/api/graphql`, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify({ query: query, variables: variables }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 6000,
        readTimeout: 20000,
        usingCache: false
      });
      if (signal !== null && signal.aborted()) {
        throw new RequestCancelled();
      }
      if (response.responseCode === 401 || response.responseCode === 403) {
        throw new Error('书源登录失效，请在书源设置中重新登录');
      }
      if (response.responseCode !== 200) {
        throw new Error(`书源请求失败（${response.responseCode}）`);
      }
      const body: Record<string, Object> = record(JSON.parse(response.result as string) as Object);
      const errors: Array<Object> | null = asArray(body['errors']);
      if (errors !== null && errors.length > 0) {
        throw new Error(asString(record(errors[0])['message'], '书源请求失败'));
      }
      return record(body['data']);
    } catch (e) {
      if (signal !== null && (signal.aborted() || isRequestCancelled(e as Error))) {
        throw new RequestCancelled();
      }
      throw e as Error;
    } finally {
      if (signal !== null) {
        signal.untrack(request);
      }
      request.destroy();
    }
  }
  async connect(endpoint: string, name: string, auth: SourceAuth, user: string, password: string,
    _instance: string = '', replace: boolean = false): Promise<Array<SourceEntry>> {
    const expected: number = databaseGeneration();
    const base: string = endpoint.trim().replace(/\/+$/, '');
    if (!/^https?:\/\/[^\s/]+/.test(base)) {
      throw new Error('请输入完整的服务地址');
    }
    const current: SourceInstance | null = await sourceStore.connection();
    if (current !== null && current.endpoint !== base && !replace) {
      throw new Error('更换服务地址前请确认替换连接');
    }
    const instance: string = current !== null && current.endpoint === base ? current.id : `s${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
    const server: SourceEntry = new SourceEntry(instance, name, 'suwayomi');
    server.endpoint = base;
    let authorization: string = '';
    if (auth !== 'none' && current !== null && current.endpoint === base && current.auth === auth && user === '' && password === '') {
      authorization = await readSourceSecret(instance);
    } else if (auth === 'basic') {
      const token: string = new util.Base64Helper().encodeToStringSync(utf8Encode(`${user}:${password}`));
      authorization = `Basic ${token}`;
    } else if (auth === 'login') {
      const data: Record<string, Object> = await this.query(server,
        'mutation Login($input: LoginInput!) { login(input: $input) { accessToken refreshToken } }',
        variables({ username: user, password: password } as LoginInput));
      const token: string = asString(record(data['login'])['accessToken']);
      if (token === '') {
        throw new Error('服务端未返回登录凭据');
      }
      authorization = `Bearer ${token}`;
    }
    const data: Record<string, Object> = await this.query(server,
      'query { sources { nodes { id name lang displayName } } }', {}, authorization);
    assertDatabaseGeneration(expected);
    if (auth !== 'none') { await saveSourceSecret(instance, authorization); }
    const seen: Set<string> = new Set();
    const entries: Array<SourceEntry> = array(record(data['sources'])['nodes']).map((value: Object): SourceEntry => {
      const node: Record<string, Object> = record(value);
      const id: string = asString(node['id']);
      if (id === '' || seen.has(id)) {
        throw new Error('服务端扩展标识为空或重复');
      }
      seen.add(id);
      const entry: SourceEntry = new SourceEntry(`${instance}_${id}`,
        `${name} · ${asString(node['displayName'], asString(node['name']))}`, 'suwayomi');
      entry.instanceId = instance;
      entry.endpoint = base;
      entry.remoteId = id;
      entry.language = asString(node['lang']);
      entry.auth = auth;
      return entry;
    });
    const connection: SourceInstance = new SourceInstance();
    connection.id = instance;
    connection.endpoint = base;
    connection.auth = auth;
    connection.name = name;
    assertDatabaseGeneration(expected);
    await sourceStore.syncSuwayomi(connection, entries, replace);
    return entries;
  }
  async search(source: SourceEntry, query: string, page: number): Promise<SearchResult> {
    const data: Record<string, Object> = await this.query(source,
      'mutation Browse($input: FetchSourceMangaInput!) { fetchSourceManga(input: $input) { mangas { id title thumbnailUrl } hasNextPage } }',
      variables({ source: source.remoteId, type: query === '' ? 'POPULAR' : 'SEARCH', page: page, query: query } as BrowseInput));
    const payload: Record<string, Object> = record(data['fetchSourceManga']);
    const list: Array<AlbumLite> = array(payload['mangas']).map((value: Object): AlbumLite => {
      const node: Record<string, Object> = record(value);
      return new AlbumLite(sourceKey(source.id, asString(node['id'])), asString(node['title']), '',
        absolute(source, asString(node['thumbnailUrl'])));
    });
    const result: SearchResult = new SearchResult(0, list);
    result.hasNext = payload['hasNextPage'] === true;
    return result;
  }
  async album(source: SourceEntry, id: string, signal: RequestAbortGroup | null = null): Promise<Album> {
    const data: Record<string, Object> = await this.query(source,
      'mutation Details($input: FetchMangaAndChaptersInput!) { fetchMangaAndChapters(input: $input) { manga { id title author artist genre description thumbnailUrl url } chapters { id name chapterNumber sourceOrder } } }',
      variables({ id: Number(id), fetchManga: true, fetchChapters: true } as DetailInput), undefined, signal);
    const payload: Record<string, Object> = record(data['fetchMangaAndChapters']);
    const node: Record<string, Object> = record(payload['manga']);
    const album: Album = new Album(sourceKey(source.id, id), asString(node['title']));
    album.author = [asString(node['author']), asString(node['artist'])].filter((s: string) => s !== '')
      .map((value: string): MetadataTerm => new MetadataTerm(value));
    album.tags = (asArray(node['genre']) ?? []).map((value: Object): MetadataTerm => new MetadataTerm(asString(value)));
    album.description = asString(node['description']);
    album.coverUrl = absolute(source, asString(node['thumbnailUrl']));
    album.language = source.language;
    album.originalUrl = asString(node['url']);
    album.episodes = array(payload['chapters']).map((value: Object): Chapter => {
      const chapter: Record<string, Object> = record(value);
      const result: Chapter = new Chapter(sourceKey(source.id, asString(chapter['id'])), asString(chapter['name']),
        `${asNumber(chapter['sourceOrder'])}`);
      result.number = asString(chapter['chapterNumber']);
      return result;
    }).sort((a: Chapter, b: Chapter) => Number(a.number) - Number(b.number) || Number(b.sort) - Number(a.sort));
    return album;
  }
  async pages(source: SourceEntry, chapter: string, signal: RequestAbortGroup | null = null): Promise<Array<string>> {
    const data: Record<string, Object> = await this.query(source,
      'mutation Pages($input: FetchChapterPagesInput!) { fetchChapterPages(input: $input) { pages } }',
      variables({ chapterId: Number(chapter) } as PagesInput), undefined, signal);
    const pages: Array<string> = array(record(data['fetchChapterPages'])['pages']).map((v: Object) => absolute(source, asString(v)));
    if (pages.length === 0) {
      throw new Error('本章暂无可阅读的页面');
    }
    return pages;
  }
}
export const suwayomi: SuwayomiClient = new SuwayomiClient();
