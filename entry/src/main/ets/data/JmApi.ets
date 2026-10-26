import { JmDomainPool } from './JmDomainPool';
import common from '@ohos.app.ability.common';
import { RequestAbortGroup } from '../util/RequestAbort';
import { Album, AlbumLite, CategoryItem, Chapter, CommentItem, CommentsResult, DomainSpeed, SearchOptions, SearchResult, asArray, asBool, asNumber, asRecord, asString } from '../models/Models';
export { utf8Encode, utf8Decode, md5Hex, javaStringHashCode } from '../util/JmCrypto';
export class JmApi {
  private domainPool: JmDomainPool = new JmDomainPool();

  /**
   * 进程启动时调用一次（幂等）：读缓存域名/图片域名/版本号，再后台刷新
   * （域名分发服务器 → /setting → 图片域名测速），绝不阻塞首屏（JmApi.kt:193-218）。
   */
  init(context?: common.Context): Promise<void> {
    return this.domainPool.init(context);
  }

                /**
   * 加密信封 GET（JmApi.kt:320-368）：
   * ts → token=md5(ts+SECRET) → 解析 {code,data} → AES 解密 data → 明文 JSON（对象或数组）。
   * 域名重试：前 3 个健康域名；总预算 18s；剩余 <800ms 放弃；单次尝试封顶剩余预算。
   */
  private apiGet(pathAndQuery: string, signal: RequestAbortGroup | null = null): Promise<Object> {
    return this.domainPool.apiGet(pathAndQuery, signal);
  }

  // ───────────────────────── 解析（JmApi.kt:380-407） ─────────────────────────

  private parseComic(o: Record<string, Object>): AlbumLite {
    const id: string = asString(o['id']);
    const title: string = asString(o['name']);
    const author: string = asString(o['author']);
    const img: string = asString(o['image']);
    let coverUrl: string = '';
    if (img === '') {
      coverUrl = `https://${this.domainPool.hostForSeed(`album/${id}`, 0)}/media/albums/${id}_3x4.jpg`;
    } else if (img.indexOf('http') === 0) {
      coverUrl = img;
    } else {
      coverUrl = `https://${this.domainPool.hostForSeed(img, 0)}${img}`;
    }
    const cat: Record<string, Object> | null = asRecord(o['category']);
    const catSub: Record<string, Object> | null = asRecord(o['category_sub']);
    return new AlbumLite(id, title, author, coverUrl,
      cat === null ? '' : asString(cat['title']),
      catSub === null ? '' : asString(catSub['title']));
  }

  private parseComicArray(v: Object | null): Array<AlbumLite> {
    const out: Array<AlbumLite> = [];
    const arr: Array<Object> | null = asArray(v);
    if (arr !== null) {
      for (const item of arr) {
        const rec: Record<string, Object> | null = asRecord(item);
        if (rec !== null) {
          out.push(this.parseComic(rec));
        }
      }
    }
    return out;
  }

  /** 评论 HTML 清洗（JmApi.kt:500-507） */
  private cleanCommentHtml(raw: string): string {
    let t: string = raw.replace(/<br\s*\/?>/gi, '\n');
    t = t.replace(/<[^>]+>/g, '');
    t = t.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"').replace(/&#39;/g, '\'').replace(/&nbsp;/g, ' ');
    return t.trim();
  }

  // ───────────────────────── 业务接口 ─────────────────────────

  /** 随机推荐（每批 30 条，服务端按周期轮换；调用方本地洗牌展示）（JmApi.kt:408-410） */
  async random(): Promise<Array<AlbumLite>> {
    const element: Object = await this.apiGet(`/random_recommend?time=${Date.now()}`);
    return this.parseComicArray(element);
  }

  /** 最新上架（每页 80 条）（JmApi.kt:413-415） */
  async latest(page: number = 1): Promise<Array<AlbumLite>> {
    const element: Object = await this.apiGet(`/latest?page=${page}`);
    return this.parseComicArray(element);
  }

  /** 分类/榜单：order = mr(最新)/mv(总榜)/mv_m(月)/mv_w(周)/mv_t(日)（JmApi.kt:417-427） */
  async ranking(category: string, order: string, page: number = 1): Promise<Array<AlbumLite>> {
    const c: string = encodeURIComponent(category === '' ? '0' : category);
    const o: string = encodeURIComponent(order);
    const root: Record<string, Object> | null = asRecord(await this.apiGet(`/categories/filter?page=${page}&c=${c}&o=${o}`));
    return this.parseComicArray(root === null ? null : root['content']);
  }

  /** 分类列表（JmApi.kt:430-443） */
  async categories(): Promise<Array<CategoryItem>> {
    const root: Record<string, Object> | null = asRecord(await this.apiGet('/categories'));
    const out: Array<CategoryItem> = [];
    if (root === null) {
      return out;
    }
    const arr: Array<Object> | null = asArray(root['categories']);
    if (arr === null) {
      return out;
    }
    for (const item of arr) {
      const rec: Record<string, Object> | null = asRecord(item);
      if (rec === null) {
        continue;
      }
      out.push(new CategoryItem(
        asString(rec['id']),
        asString(rec['name']),
        asString(rec['slug']),
        asString(rec['total_albums'])
      ));
    }
    return out;
  }

  /** 本子详情（含章节目录；series 按 sort 升序，空则回退单章节）（JmApi.kt:446-471） */
  async album(albumId: string, signal: RequestAbortGroup | null = null): Promise<Album> {
    const o: Record<string, Object> | null = asRecord(await this.apiGet(`/album?id=${albumId}`, signal));
    if (o === null) {
      throw new Error('响应格式错误');
    }
    let episodes: Array<Chapter> = [];
    const series: Array<Object> | null = asArray(o['series']);
    if (series !== null) {
      for (const item of series) {
        const rec: Record<string, Object> | null = asRecord(item);
        if (rec === null) {
          continue;
        }
        episodes.push(new Chapter(
          asString(rec['id']),
          asString(rec['name']),
          asString(rec['sort'])
        ));
      }
    }
    episodes = episodes.slice().sort((a: Chapter, b: Chapter) => {
      const sa: number = this.sortInt(a.sort);
      const sb: number = this.sortInt(b.sort);
      return sa - sb;
    });
    const name: string = asString(o['name']);
    if (episodes.length === 0) {
      episodes.push(new Chapter(albumId, name, '1'));
    }
    const result: Album = new Album(albumId, name);
    result.likes = asString(o['likes']);
    result.views = asString(o['total_views']);
    const authors: Array<Object> | null = asArray(o['author']);
    if (authors !== null) {
      for (const a of authors) {
        const v: string = asString(a);
        if (v !== '') {
          result.author.push(v);
        }
      }
    }
    const tags: Array<Object> | null = asArray(o['tags']);
    if (tags !== null) {
      for (const t of tags) {
        const v: string = asString(t);
        if (v !== '') {
          result.tags.push(v);
        }
      }
    }
    result.episodes = episodes;
    return result;
  }

  private sortInt(s: string): number {
    const n: number = Number(s);
    if (s !== '' && !Number.isNaN(n)) {
      return Math.floor(n);
    }
    return 2147483647;
  }

  /** 章节图片文件名列表（JmApi.kt:474-477） */
  async chapterImages(photoId: string, signal: RequestAbortGroup | null = null): Promise<Array<string>> {
    const o: Record<string, Object> | null = asRecord(await this.apiGet(`/chapter?id=${photoId}`, signal));
    const out: Array<string> = [];
    if (o === null) {
      return out;
    }
    const arr: Array<Object> | null = asArray(o['images']);
    if (arr !== null) {
      for (const item of arr) {
        const v: string = asString(item);
        if (v !== '') {
          out.push(v);
        }
      }
    }
    return out;
  }

  /** 本子评论区（page 从 1 起，每页约 10 条）（JmApi.kt:480-498） */
  async comments(albumId: string, page: number = 1,
    signal: RequestAbortGroup | null = null): Promise<CommentsResult> {
    const o: Record<string, Object> | null = asRecord(await this.apiGet(
      `/forum?mode=manhua&aid=${albumId}&page=${page}&lang=CN`, signal));
    const result: CommentsResult = new CommentsResult();
    if (o === null) {
      return result;
    }
    result.total = asNumber(o['total'], 0);
    const arr: Array<Object> | null = asArray(o['list']);
    if (arr !== null) {
      for (const item of arr) {
        const c: Record<string, Object> | null = asRecord(item);
        if (c === null) {
          continue;
        }
        let nickname: string = asString(c['nickname']);
        if (nickname === '') {
          nickname = asString(c['username']);
        }
        let time: string = asString(c['addtime']);
        if (time === '') {
          time = asString(c['update_at']);
        }
        result.list.push(new CommentItem(
          asString(c['CID']),
          nickname,
          this.cleanCommentHtml(asString(c['content'])),
          asString(c['likes']),
          asBool(c['spoiler'], false) || asString(c['spoiler']) === '1',
          time,
          asString(c['parent_CID'])
        ));
      }
    }
    const pageSize: number = 10;
    const loaded: number = (page - 1) * pageSize + result.list.length;
    result.hasNext = result.list.length > 0 &&
      (result.total > loaded || (result.total <= 0 && result.list.length >= pageSize));
    return result;
  }

  /**
   * 章节图片乱序解密参数（JmApi.kt:509-542）：
   * 特殊密钥 18comicAPPContent；返回 HTML 明文用正则提取 scramble_id；
   * 失败回退常量 220980；结果按 photoId 进程内缓存。
   */
  scrambleId(photoId: string, signal: RequestAbortGroup | null = null): Promise<number> {
    return this.domainPool.scrambleId(photoId, signal);
  }

    /** 轮换到下一个图片域名（图床失败重试用）（JmApi.kt:564-570） */
  nextImageHost(current: string): string | null {
    return this.domainPool.nextImageHost(current);
  }

  /** 记录图片域名失败：从健康池移除并触发下一轮探测（JmApi.kt:573-578） */
  reportImgHostFailure(host: string): void {
    return this.domainPool.reportImgHostFailure(host);
  }

  /** 后台轻量探测：按 HEAD 延迟维护健康池（30 分钟节流）（JmApi.kt:581-604） */
  refreshImageHostsAsync(): void {
    return this.domainPool.refreshImageHostsAsync();
  }

      /** 章节图片完整地址（retry 递增可轮换图片域名）（JmApi.kt:613-615） */
  imageUrl(photoId: string, filename: string, retry: number = 0): string {
    return this.domainPool.imageUrl(photoId, filename, retry);
  }

  /** 本子封面大图（JmApi.kt:617-619） */
  albumCoverUrl(albumId: string, retry: number = 0): string {
    return this.domainPool.albumCoverUrl(albumId, retry);
  }

  /** 本子封面小图 3:4（列表/预览用，体积约 1/10）（JmApi.kt:621-623） */
  albumThumbUrl(albumId: string, retry: number = 0): string {
    return this.domainPool.albumThumbUrl(albumId, retry);
  }

  /** 下载原始图片字节（整本下载用；失败由调用方换域名重试）（JmApi.kt:634-637） */
  fetchBytes(url: string, signal: RequestAbortGroup | null = null): Promise<ArrayBuffer> {
    return this.domainPool.fetchBytes(url, signal);
  }

      /**
   * 关键词搜索（JmApi.kt:686-708）。
   * order: mr 最新 / mv 最多观看 / mp 最多图片 / tf 最多爱心；
   * time: a 全部 / t 今日 / w 本周 / m 本月；year/month 指定上架年月（仅有年时只带 y）。
   */
  async search(query: string, page: number = 1, order: string = 'mr',
    time: string = 'a', year: string = '', month: string = ''): Promise<SearchResult> {
    return this.searchByOptions(new SearchOptions(query, page, order, time, year, month));
  }

  async searchByOptions(options: SearchOptions): Promise<SearchResult> {
    const q: string = encodeURIComponent(options.query);
    const o: string = encodeURIComponent(options.order);
    const t: string = encodeURIComponent(options.time);
    let datePart: string = '';
    if (options.year !== '') {
      if (options.month === '') {
        datePart = `&y=${encodeURIComponent(options.year)}`;
      } else {
        datePart = `&y=${encodeURIComponent(options.year)}&m=${encodeURIComponent(options.month)}`;
      }
    }
    const root: Record<string, Object> | null = asRecord(await this.apiGet(
      `/search?search_query=${q}&page=${options.page}&o=${o}&t=${t}${datePart}`));
    const result: SearchResult = new SearchResult();
    if (root === null) {
      return result;
    }
    result.total = asNumber(root['total'], 0);
    result.list = this.parseComicArray(root['content']);
    return result;
  }

  // ───────────────────────── 镜像切换 ─────────────────────────

  /** 当前域名候选池（健康排序后），设置页展示/选择用 */
  getDomains(): Array<string> {
    return this.domainPool.getDomains();
  }

  /** 手动切换镜像：置顶并持久化（等效 rememberGoodDomain 的域名偏好语义） */
  setPreferredDomain(domain: string): Promise<void> {
    return this.domainPool.setPreferredDomain(domain);
  }

  /** 当前图片 CDN 域名（诊断展示） */
  getImageHost(): string {
    return this.domainPool.getImageHost();
  }

  /** 接口版本号（诊断展示） */
  getAppVersion(): string {
    return this.domainPool.getAppVersion();
  }

  /** 一键测速：对全部候选域名请求 /setting（带 token 头）计时，按延迟升序返回 */
  testDomains(): Promise<Array<DomainSpeed>> {
    return this.domainPool.testDomains();
  }

  /** 调试信息（设置页展示，对应 JmApi.debugInfo） */
  debugInfo(): string {
    return this.domainPool.debugInfo();
  }
}

export const jmApi: JmApi = new JmApi();
