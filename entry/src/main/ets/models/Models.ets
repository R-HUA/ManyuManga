/**
 * models/Models.ets — 数据模型与 JSON 解析辅助
 *
 * 移植依据：
 *  - jinmanji-app/app/src/main/java/com/mobai/jm/data/Models.kt（Comic/JmCategory/JmAlbum/Episode/JmComment）
 *  - jinmanji-app/app/src/main/java/com/mobai/jm/data/FavStore.kt:16-23（FavItem）
 *  - jinmanji-app/app/src/main/java/com/mobai/jm/data/HistoryStore.kt:17-24（HistoryItem）
 *  - docs/api-spec.md §7、docs/conventions.md §4（模型命名：Album/AlbumLite/Chapter/ChapterPage/CommentItem/SearchOptions/RankingType）
 *
 * 硬规则：全部 class + 显式类型 + 构造器默认值；禁止对象字面量直接构造 class。
 */

/** 榜单排序（categories/filter 的 o 参数）：最新/总榜/月榜/周榜/日榜 */
export type RankingType = 'mr' | 'mv' | 'mv_m' | 'mv_w' | 'mv_t';

/** 搜索排序（/search 的 o 参数）：最新/最多观看/最多图片/最多爱心 */
export type SearchOrderType = 'mr' | 'mv' | 'mp' | 'tf';

/** 搜索时间范围（/search 的 t 参数）：全部/今日/本周/本月 */
export type SearchTimeType = 'a' | 't' | 'w' | 'm';

/** 阅读器模式（S 级：双页/右翻渲染可后补，枚举与切换保留） */
export type ReaderMode = 'vertical' | 'pagedVertical' | 'horizontal' | 'rtl' | 'double';

/** 列表条目（对应 Kotlin Comic，Models.kt:5-13） */
export class AlbumLite {
  id: string;
  title: string;
  author: string;
  coverUrl: string;
  category: string;
  categorySub: string;

  constructor(id: string = '', title: string = '', author: string = '',
    coverUrl: string = '', category: string = '', categorySub: string = '') {
    this.id = id;
    this.title = title;
    this.author = author;
    this.coverUrl = coverUrl;
    this.category = category;
    this.categorySub = categorySub;
  }
}

/** 分类条目（对应 Kotlin JmCategory，Models.kt:15-20） */
export class CategoryItem {
  id: string;
  name: string;
  slug: string;
  total: string;

  constructor(id: string = '', name: string = '', slug: string = '', total: string = '') {
    this.id = id;
    this.name = name;
    this.slug = slug;
    this.total = total;
  }
}

/** 章节（对应 Kotlin Episode，Models.kt:34-40） */
export class Chapter {
  number: string = '';
  id: string;
  title: string;
  sort: string;

  constructor(id: string = '', title: string = '', sort: string = '') {
    this.id = id;
    this.title = title;
    this.sort = sort;
  }
}

/** 本子详情（对应 Kotlin JmAlbum，Models.kt:22-32；可持久化到本地缓存） */
export class Album {
  coverUrl: string = '';
  description: string = '';
  language: string = '';
  originalUrl: string = '';
  id: string;
  name: string;
  author: Array<string>;
  tags: Array<string>;
  likes: string;
  views: string;
  episodes: Array<Chapter>;

  constructor(id: string = '', name: string = '') {
    this.id = id;
    this.name = name;
    this.author = [];
    this.tags = [];
    this.likes = '';
    this.views = '';
    this.episodes = [];
  }
}

/** 下载用页引用（对应 DownloadQueue.kt:249 的 PageRef） */
export class ChapterPage {
  photoId: string;
  filename: string;
  scrambleId: number;

  constructor(photoId: string = '', filename: string = '', scrambleId: number = 0) {
    this.photoId = photoId;
    this.filename = filename;
    this.scrambleId = scrambleId;
  }
}

/** 评论（对应 Kotlin JmComment，Models.kt:43-52；content 已由数据层完成 HTML 清洗） */
export class CommentItem {
  id: string;
  nickname: string;
  content: string;
  likes: string;
  spoiler: boolean;
  time: string;
  parentId: string;

  constructor(id: string = '', nickname: string = '', content: string = '',
    likes: string = '', spoiler: boolean = false, time: string = '', parentId: string = '') {
    this.id = id;
    this.nickname = nickname;
    this.content = content;
    this.likes = likes;
    this.spoiler = spoiler;
    this.time = time;
    this.parentId = parentId;
  }
}

/** 评论分页结果（Kotlin 用 Pair<Int, List<JmComment>>，ArkTS 无元组，改用结果类） */
export class CommentsResult {
  total: number;
  list: Array<CommentItem>;

  constructor(total: number = 0, list: Array<CommentItem> = []) {
    this.total = total;
    this.list = list;
  }
}

/** 搜索结果（Kotlin 用 Pair，同上改结果类） */
export class SearchResult {
  total: number;
  list: Array<AlbumLite>;
  /** 部分书源只提供下一页标记，不提供结果总数。 */
  hasNext: boolean | null = null;

  constructor(total: number = 0, list: Array<AlbumLite> = []) {
    this.total = total;
    this.list = list;
  }
}

/** 搜索参数（JmApi.kt:686-693 的参数集合） */
export class SearchOptions {
  query: string;
  page: number;
  order: string;
  time: string;
  year: string;
  month: string;

  constructor(query: string = '', page: number = 1, order: string = 'mr',
    time: string = 'a', year: string = '', month: string = '') {
    this.query = query;
    this.page = page;
    this.order = order;
    this.time = time;
    this.year = year;
    this.month = month;
  }
}

/** 收藏条目（FavStore.kt:16-23） */
export class FavItem {
  id: string;
  title: string;
  author: string;
  coverUrl: string;
  addedAt: number;

  constructor(id: string = '', title: string = '', author: string = '',
    coverUrl: string = '', addedAt: number = 0) {
    this.id = id;
    this.title = title;
    this.author = author;
    this.coverUrl = coverUrl;
    this.addedAt = addedAt;
  }
}

/** 本子级浏览历史条目（HistoryStore.kt:17-24） */
export class HistoryItem {
  id: string;
  title: string;
  author: string;
  coverUrl: string;
  viewedAt: number;

  constructor(id: string = '', title: string = '', author: string = '',
    coverUrl: string = '', viewedAt: number = 0) {
    this.id = id;
    this.title = title;
    this.author = author;
    this.coverUrl = coverUrl;
    this.viewedAt = viewedAt;
  }
}

/**
 * 精确阅读进度（conventions §4 / feature-spec B-03：鸿蒙版新增，原项目无）。
 * 基本字段严格为 { aid, chapterId, chapterIndex, page, totalPages, at }；
 * title/author/coverUrl 为展示冗余（书架续读横幅 B-02 直接可渲染，不必再查详情缓存）。
 */
export class ReadingProgress {
  aid: string;
  chapterId: string;
  chapterIndex: number;
  page: number;
  totalPages: number;
  at: number;
  title: string;
  author: string;
  coverUrl: string;

  constructor(aid: string = '', chapterId: string = '', chapterIndex: number = 0,
    page: number = 0, totalPages: number = 0, at: number = 0,
    title: string = '', author: string = '', coverUrl: string = '') {
    this.aid = aid;
    this.chapterId = chapterId;
    this.chapterIndex = chapterIndex;
    this.page = page;
    this.totalPages = totalPages;
    this.at = at;
    this.title = title;
    this.author = author;
    this.coverUrl = coverUrl;
  }
}

/** 镜像域名测速结果（SET-22） */
export class DomainSpeed {
  domain: string;
  ms: number;
  ok: boolean;

  constructor(domain: string = '', ms: number = 0, ok: boolean = false) {
    this.domain = domain;
    this.ms = ms;
    this.ok = ok;
  }
}

// ───────────────────────── JSON 解析辅助（ArkTS 安全访问） ─────────────────────────

/** 把 JSON.parse 的结果安全转为 Record；非对象返回 null */
export function asRecord(v: Object | null | undefined): Record<string, Object> | null {
  if (v === null || v === undefined) {
    return null;
  }
  if (typeof v === 'object' && !(v instanceof Array)) {
    return v as Record<string, Object>;
  }
  return null;
}

/** 把 JSON.parse 的结果安全转为数组；非数组返回 null */
export function asArray(v: Object | null | undefined): Array<Object> | null {
  if (v === null || v === undefined) {
    return null;
  }
  if (v instanceof Array) {
    return v as Array<Object>;
  }
  return null;
}

/** 取字符串（对应 kotlinx contentOrNull；数字容忍转字符串） */
export function asString(v: Object | null | undefined, def: string = ''): string {
  if (v === null || v === undefined) {
    return def;
  }
  if (typeof v === 'string') {
    return v;
  }
  if (typeof v === 'number' || typeof v === 'boolean') {
    return `${v}`;
  }
  return def;
}

/** 取数值（Kotlin 数值容错解析；可能含小数，需要整数处自行 Math.floor） */
export function asNumber(v: Object | null | undefined, def: number = 0): number {
  if (typeof v === 'number') {
    return v;
  }
  if (typeof v === 'string' && v !== '') {
    const n: number = Number(v);
    if (!Number.isNaN(n)) {
      return n;
    }
  }
  return def;
}

/** 取布尔（容忍 "1" 字符串，对应 spoiler 的 bool|"1" 两态） */
export function asBool(v: Object | null | undefined, def: boolean = false): boolean {
  if (typeof v === 'boolean') {
    return v;
  }
  if (typeof v === 'string') {
    return v === '1' || v === 'true';
  }
  return def;
}

/** 统一取错误消息 */
export function errorMessage(e: Error): string {
  if (e !== null && e !== undefined && typeof e.message === 'string' && e.message !== '') {
    return e.message;
  }
  return '未知错误';
}
