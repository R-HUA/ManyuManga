/**
 * E-Hentai / ExHentai 图源适配器：把 HarmonyOS-EhViewer 的协议引擎（data/eh/EhNative.ets）
 * 无缝映射进漫语 SourceAdapter 契约。
 *
 * 三大模型差异的桥接（详见接入方案文档）：
 *  1. 复合主键 gid+token —— 全局 aid 编码为 sourceKey('eh', '${gid}_${token}')；
 *  2. 画廊无章节 —— 映射为单章 Album（"全一册 · 共 N 页"），页列表用虚拟文件名 00001.eh..N；
 *  3. 两阶段图片解析 —— 详情页缩略图提供每页 /s/{pageToken} 地址，单页请求才得到带时效签名的
 *     图片直链；attempt>0 时附带 nl 参数强制服务端切换 H@H 节点重试。
 */
import { Album, AlbumLite, Chapter, CommentItem, CommentsResult, SearchResult } from '../models/Models';
import { sourceKey } from './Sources';
import { EhSettings } from './eh/EhSettings';
import {
  NativeEhClient,
  NativeGallerySummary,
  NativeGalleryDetail,
  NativeGalleryListResult,
  NativeGalleryComment,
  NativeGalleryPreviewPage,
  NativeRequestControl,
  EhTagTranslator,
  EhUrl,
  GallerySite
} from './eh/EhNative';

/** 5 位页码文件名前缀（与 DownloadManager.pad5 同构）。 */
function ehPad5(n: number): string {
  let s: string = `${n}`;
  while (s.length < 5) {
    s = `0${s}`;
  }
  return s;
}

/** EhNative 抛出的英文协议错误 → 界面可读中文；未命中则原样返回。 */
function ehFriendlyError(e: Error): Error {
  const raw: string = e.message ?? '';
  if (/^HTTP \d+$/.test(raw)) {
    return new Error(`服务器返回 ${raw}，可能需要登录或稍后再试`);
  }
  const table: Array<Array<string>> = [
    ['Empty response. Sign in first', '响应为空：请先登录或导入 Cookie（里站必须登录）'],
    ['Gallery list was not found', '未找到画廊列表：请登录或导入有效 Cookie'],
    ['No gallery entries were parsed', '本页没有解析到画廊条目'],
    ['Account home is not a gallery list', '当前入口不是画廊列表页'],
    ['Reader image parse failed', '阅读页图片解析失败，请重试'],
    ['Binary request failed', '图片下载失败，请重试'],
    ['Text request failed', '网络请求失败，请重试'],
    ['Form request failed', '请求提交失败，请重试'],
    ['No translation rows parsed', '标签翻译库解析失败']
  ];
  for (const pair of table) {
    if (raw.indexOf(pair[0]) >= 0) {
      return new Error(pair[1]);
    }
  }
  return e;
}

/** 画廊列表游标结果：EH 列表分页是 next 游标而非页码。 */
export class EhListPage {
  items: Array<AlbumLite> = [];
  nextUrl: string = '';
  prevUrl: string = '';
  firstUrl: string = '';
  totalLabel: string = '';

  constructor(items: Array<AlbumLite>, nextUrl: string, prevUrl: string, firstUrl: string, totalLabel: string) {
    this.items = items;
    this.nextUrl = nextUrl;
    this.prevUrl = prevUrl;
    this.firstUrl = firstUrl;
    this.totalLabel = totalLabel;
  }
}

interface EhIdentity {
  gid: number;
  token: string;
}

export class EhSource {
  /** `${site}:${gid_token}` -> 画廊详情（album/chapterImages/comments 共享，站点独立缓存）。 */
  private detailCache: Map<string, NativeGalleryDetail> = new Map();
  /** `${site}:${gid_token}` -> 页码(1-based) -> 单页查看器地址 /s/{token}/{gid}-{n}。 */
  private readerUrls: Map<string, Map<number, string>> = new Map();
  /** gid_token_page -> 上次响应的 nl 键（H@H 换源重试用，与站点无关）。 */
  private skipHathKeys: Map<string, string> = new Map();
  /** `${site}:${gid_token}` -> 缩略图分页容量（首次抓到后即可跳页定位）。 */
  private previewPerPage: Map<string, number> = new Map();
  /** `${site}:${gid_token}` -> 已抓取过的缩略图分页下标。 */
  private previewLoaded: Map<string, Set<number>> = new Map();
  /** 搜索游标链：key = `q:${site}:${query}`，value[i] = 第 i+1 页的请求 URL。 */
  private searchCursors: Map<string, Array<string>> = new Map();

  /** 站点进入缓存键：切换表/里站后自动取新键，避免复用旧站点的空壳与游标。 */
  private scope(site: string, id: EhIdentity): string {
    return `${site}:${id.gid}_${id.token}`;
  }

  // ─────────────── 标识解析 ───────────────

  /** 'gid_token' / 'gid/token' / 'eh~gid_token' / 画廊 URL → { gid, token }。 */
  public parseIdentity(rawKey: string): EhIdentity {
    let clean: string = rawKey.trim();
    const cut: number = clean.indexOf('~');
    if (cut > 0) {
      clean = decodeURIComponent(clean.substring(cut + 1));
    }
    const urlMatch: RegExpMatchArray | null = clean.match(/(?:e-hentai\.org|exhentai\.org)\/g\/(\d+)\/([0-9a-f]{10})/i);
    if (urlMatch !== null) {
      return { gid: Number(urlMatch[1]), token: urlMatch[2] };
    }
    let core: string = clean.replace(/[\/\s]+$/, '');
    const slashParts: Array<string> = core.split('/');
    if (slashParts.length >= 2) {
      core = `${slashParts[slashParts.length - 2]}_${slashParts[slashParts.length - 1]}`;
    }
    const pair: Array<string> = core.split('_');
    const gid: number = Number(pair[0] ?? '');
    const token: string = pair[1] ?? '';
    if (!Number.isInteger(gid) || gid <= 0 || !/^[0-9a-f]{10}$/i.test(token)) {
      throw new Error('无效的 E-Hentai 画廊标识，应为 gid/token、gid_token 或画廊链接');
    }
    return { gid, token };
  }

  public fullKey(id: EhIdentity): string {
    return sourceKey('eh', `${id.gid}_${id.token}`);
  }

  /** SourcesPage 直达输入（车号 / 链接）→ 漫语完整 aid。 */
  public keyFromInput(input: string): string {
    return this.fullKey(this.parseIdentity(input));
  }

  // ─────────────── 列表 / 搜索（游标分页） ───────────────

  /** 拉取任意 EH 列表 URL（首页/热门/关注/收藏/搜索）。control 用于页面离开时销毁在途请求。 */
  public async list(requestUrl: string, control?: NativeRequestControl): Promise<EhListPage> {
    const site: string = EhSettings.effectiveSite();
    let res: NativeGalleryListResult;
    try {
      res = await NativeEhClient.fetchGalleryList(site, requestUrl, control);
    } catch (e) {
      throw ehFriendlyError(e as Error);
    }
    return new EhListPage(res.items.map((it: NativeGallerySummary): AlbumLite => this.toAlbumLite(it)),
      res.nextUrl, res.prevUrl, res.firstUrl, res.resultCount);
  }

  /** 各浏览入口的首页 URL（里站未登录时 effectiveSite 已回退表站）。 */
  public homeUrl(): string {
    return EhUrl.galleryFront(EhSettings.effectiveSite());
  }
  public popularUrl(): string {
    return EhUrl.popular(EhSettings.effectiveSite());
  }
  public watchedUrl(): string {
    return EhUrl.watched(EhSettings.effectiveSite());
  }
  public favoritesUrl(): string {
    return EhUrl.favorites(EhSettings.effectiveSite());
  }

  public searchUrl(query: string): string {
    return EhUrl.search(EhSettings.effectiveSite(), query);
  }

  // ─────────────── 封面 / 缩略图（补齐 Referer 与登录 Cookie） ───────────────

  /** 判断是否 EH 图片域：官方三域（可带 Cookie）或缩略图 CDN ehgt.org（仅需 Referer）。 */
  public isEhImageUrl(url: string): boolean {
    if (NativeEhClient.isOfficialEhHost(url)) {
      return true;
    }
    const match: RegExpMatchArray | null = url.match(/^https?:\/\/([^\/?#:]+)/i);
    const host: string = match !== null ? match[1].toLowerCase() : '';
    return host === 'ehgt.org' || host.endsWith('.ehgt.org');
  }

  /**
   * 抓取 EH 域图片字节（缩略图/封面）。官方域自动带登录 Cookie（域隔离在 NativeEhClient
   * 内部保证），ehgt CDN 仅补 Referer；非 EH 域返回 null 交回调用方。
   */
  public async fetchImageBytes(url: string): Promise<ArrayBuffer | null> {
    if (!this.isEhImageUrl(url)) {
      return null;
    }
    const site: string = EhSettings.effectiveSite();
    try {
      return await NativeEhClient.downloadBinary(site, url, EhUrl.host(site));
    } catch (e) {
      throw ehFriendlyError(e as Error);
    }
  }

  /**
   * SourceAdapter.searchSource 的页码适配：每个 (站点, 查询词) 维护一条游标链。
   * 请求越过链尾时沿 nextUrl 顺序补齐（丢弃中间结果），链断或超上限时退回链尾页。
   */
  public async searchSource(query: string, page: number): Promise<SearchResult> {
    const site: string = EhSettings.effectiveSite();
    const cacheKey: string = `q:${site}:${query}`;
    let cursors: Array<string> | undefined = this.searchCursors.get(cacheKey);
    if (cursors === undefined) {
      cursors = [this.searchUrl(query)];
      this.searchCursors.set(cacheKey, cursors);
      if (this.searchCursors.size > 12) {
        for (const oldest of this.searchCursors.keys()) {
          this.searchCursors.delete(oldest);
          break;
        }
      }
    }
    let hops: number = 0;
    while (page > cursors.length && hops < 12) {
      const walk: EhListPage = await this.list(cursors[cursors.length - 1]);
      if (walk.nextUrl === '') {
        break;
      }
      cursors.push(walk.nextUrl);
      hops++;
    }
    const target: number = Math.min(Math.max(1, page), cursors.length);
    const result: EhListPage = await this.list(cursors[target - 1]);
    if (result.nextUrl !== '' && cursors.length === target) {
      cursors.push(result.nextUrl);
    }
    const out: SearchResult = new SearchResult(0, result.items);
    out.hasNext = result.nextUrl !== '';
    return out;
  }

  // ─────────────── 详情 / 章节 / 评论 ───────────────

  private summaryFor(id: EhIdentity, site: string): NativeGallerySummary {
    return {
      gid: id.gid,
      token: id.token,
      title: '',
      titleJpn: '',
      thumb: '',
      categoryLabel: '',
      posted: '',
      uploader: '',
      rating: -1,
      pages: 0,
      simpleTags: [],
      simpleLanguage: '',
      detailUrl: EhUrl.galleryDetail(site, id.gid, id.token)
    };
  }

  public async detail(rawKey: string): Promise<NativeGalleryDetail> {
    const id: EhIdentity = this.parseIdentity(rawKey);
    const site: string = EhSettings.effectiveSite();
    const cacheKey: string = this.scope(site, id);
    const cached: NativeGalleryDetail | undefined = this.detailCache.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }
    let detail: NativeGalleryDetail;
    try {
      detail = await NativeEhClient.fetchGalleryDetail(site, this.summaryFor(id, site));
      // 里站无权限（Sad Panda 空响应）时按表站重试一次
      if ((detail.gid === 0 || detail.pages === 0) && site === GallerySite.EX) {
        detail = await NativeEhClient.fetchGalleryDetail(GallerySite.E, this.summaryFor(id, GallerySite.E));
      }
    } catch (e) {
      throw ehFriendlyError(e as Error);
    }
    if (detail.gid === 0 || detail.pages === 0) {
      // 空壳（未登录/无权限/解析失败）绝不进缓存：补完 Cookie、切换站点或网络恢复后可直接重试
      throw new Error('画廊详情解析失败：可能需要登录、Cookie 失效或稍后再试');
    }
    this.detailCache.set(cacheKey, detail);
    if (this.detailCache.size > 60) {
      for (const oldest of this.detailCache.keys()) {
        this.detailCache.delete(oldest);
        break;
      }
    }
    return detail;
  }

  public toAlbumLite(item: NativeGallerySummary): AlbumLite {
    const sub: string = item.rating > 0 ? `★${item.rating.toFixed(1)} · ${item.pages}P` : `${item.pages}P`;
    const id: EhIdentity = { gid: item.gid, token: item.token };
    return new AlbumLite(this.fullKey(id), item.titleJpn !== '' ? item.titleJpn : item.title,
      item.uploader !== '' ? item.uploader : 'E-Hentai', item.thumb, item.categoryLabel, sub);
  }

  public async album(rawKey: string): Promise<Album> {
    const id: EhIdentity = this.parseIdentity(rawKey);
    const detail: NativeGalleryDetail = await this.detail(rawKey);
    const key: string = this.fullKey(id);
    const album: Album = new Album(key, detail.titleJpn !== '' ? detail.titleJpn : detail.title);
    album.coverUrl = detail.cover;
    const ratingLabel: string = detail.rating > 0 ? `★${detail.rating.toFixed(2)}` : '暂无评分';
    album.description = `${detail.categoryLabel} · 上传者 ${detail.uploader === '' ? '未知' : detail.uploader}` +
      ` · ${detail.posted} · ${ratingLabel} · ${detail.fileSize}`;
    album.language = detail.language;
    album.likes = detail.ratingCount > 0 ? `${detail.ratingCount}` : '';
    album.views = `${detail.pages} 页`;
    album.originalUrl = detail.detailUrl;

    const authors: Array<string> = [];
    const tags: Array<string> = [];
    for (const group of detail.tagGroups) {
      const nsLabel: string = EhTagTranslator.translateNamespace(group.name);
      for (const tag of group.tags) {
        const translated: string = `${nsLabel}:${EhTagTranslator.translateTag(group.name, tag)}`;
        if (group.name === 'artist' || group.name === 'group') {
          authors.push(translated);
        }
        tags.push(translated);
      }
    }
    album.author = authors.length > 0 ? authors : (detail.uploader !== '' ? [detail.uploader] : []);
    album.tags = tags;
    album.episodes = [new Chapter(key, `全一册 · 共 ${detail.pages} 页 (${detail.categoryLabel})`, '1')];
    return album;
  }

  /** 虚拟页名 00001.eh..N：阅读器/下载器先拿到总页数与稳定缓存键，真实直链两阶段解析。 */
  public async chapterImages(rawKey: string): Promise<Array<string>> {
    const detail: NativeGalleryDetail = await this.detail(rawKey);
    const pages: Array<string> = [];
    for (let i: number = 1; i <= detail.pages; i++) {
      pages.push(`${ehPad5(i)}.eh`);
    }
    if (pages.length === 0) {
      throw new Error('画廊没有可阅读的页面');
    }
    return pages;
  }

  public async comments(rawKey: string, page: number = 1): Promise<CommentsResult> {
    // 评论接口一次返回当前可见的全部楼层，没有第二页。页码大于 1 时给空页，避免调用方拼接出重复。
    if (page > 1) {
      return new CommentsResult(0, []);
    }
    const id: EhIdentity = this.parseIdentity(rawKey);
    const detail: NativeGalleryDetail = await this.detail(rawKey);
    const site: string = EhSettings.effectiveSite();
    let loaded: NativeGalleryDetail;
    try {
      loaded = await NativeEhClient.fetchGalleryDetailComments(site, detail);
    } catch (e) {
      throw ehFriendlyError(e as Error);
    }
    const list: Array<CommentItem> = loaded.comments.map((c: NativeGalleryComment, idx: number): CommentItem =>
      new CommentItem(`${c.id}`, c.user, c.body, `${c.score}`, false, c.posted, ''));
    if (loaded.comments.length > 0 && loaded.pages > 0) {
      this.detailCache.set(this.scope(site, id), loaded);
    }
    return new CommentsResult(list.length, list);
  }

  // ─────────────── 两阶段单页解析（阅读 / 下载共用） ───────────────

  /**
   * 解析某页的单页查看器地址（/s/{token}/{gid}-{n}）。
   * 缩略图每页容量（20/40 视站点设置）未知：先按假设跳页抓取，实测容量后重定位，
   * 仍失配则顺序向后推进；全部页码已知仍缺目标即页号异常。
   */
  private async readerUrl(id: EhIdentity, pageIndex: number): Promise<string> {
    const site: string = EhSettings.effectiveSite();
    const cacheKey: string = this.scope(site, id);
    let urls: Map<number, string> | undefined = this.readerUrls.get(cacheKey);
    if (urls === undefined) {
      urls = new Map();
      this.readerUrls.set(cacheKey, urls);
    }
    const hit: string | undefined = urls.get(pageIndex);
    if (hit !== undefined) {
      return hit;
    }
    const detail: NativeGalleryDetail = await this.detail(`${id.gid}_${id.token}`);
    if (pageIndex > detail.pages || detail.pages === 0) {
      throw new Error(`页码越界：第 ${pageIndex} 页（画廊共 ${detail.pages} 页）`);
    }
    let loaded: Set<number> | undefined = this.previewLoaded.get(cacheKey);
    if (loaded === undefined) {
      loaded = new Set<number>();
      this.previewLoaded.set(cacheKey, loaded);
    }
    const perKnown: number | undefined = this.previewPerPage.get(cacheKey);
    let per: number = perKnown !== undefined && perKnown > 0 ? perKnown : 40;
    let index: number = Math.floor((pageIndex - 1) / per);
    for (let step: number = 0; step < 12; step++) {
      if (index < 0 || (detail.previewPageCount > 0 && loaded.size > 0 && index >= detail.previewPageCount)) {
        break;
      }
      if (!loaded.has(index)) {
        const page: NativeGalleryPreviewPage = await NativeEhClient.fetchGalleryPreviewPage(site, detail.detailUrl, index);
        loaded.add(index);
        if (page.items.length > 0) {
          this.previewPerPage.set(cacheKey, page.items.length);
          per = page.items.length;
        }
        for (const item of page.items) {
          const pageNumber: number = item.position + 1;
          if (urls.get(pageNumber) === undefined) {
            urls.set(pageNumber, item.pageUrl);
          }
        }
      }
      const found: string | undefined = urls.get(pageIndex);
      if (found !== undefined) {
        return found;
      }
      if (urls.size >= detail.pages) {
        break;
      }
      const wanted: number = Math.floor((pageIndex - 1) / per);
      index = wanted > index ? wanted : index + 1;
    }
    throw new Error(`第 ${pageIndex} 页的单页地址解析失败，请重试`);
  }

  /**
   * 虚拟页名 → 真实图片字节。attempt>0 时附带 nl 键让服务端换一个 H@H 节点重新签发直链。
   */
  public async fetchPage(rawKey: string, filename: string, attempt: number): Promise<ArrayBuffer> {
    const id: EhIdentity = this.parseIdentity(rawKey);
    const pageIndex: number = parseInt(filename.replace(/\.eh$/i, ''), 10);
    if (!Number.isInteger(pageIndex) || pageIndex < 1) {
      throw new Error(`无效的 E-Hentai 页文件名：${filename}`);
    }
    const site: string = EhSettings.effectiveSite();
    const pageUrl: string = await this.readerUrl(id, pageIndex);
    const nlKey: string = `${id.gid}_${id.token}_${pageIndex}`;
    const skipHathKey: string = attempt > 0 ? (this.skipHathKeys.get(nlKey) ?? '') : '';
    try {
      const page = await NativeEhClient.fetchReaderPage(site, pageUrl, skipHathKey);
      if (page.skipHathKey !== undefined && page.skipHathKey !== '') {
        this.skipHathKeys.set(nlKey, page.skipHathKey);
      }
      return await NativeEhClient.downloadBinary(site, page.imageUrl, page.pageUrl);
    } catch (e) {
      throw ehFriendlyError(e as Error);
    }
  }
}

export const ehSource: EhSource = new EhSource();
