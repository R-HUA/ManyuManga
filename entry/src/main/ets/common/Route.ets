/**
 * 路由名常量
 * MainShell 预注册以下全部路由；页面用 @Consume('navPathStack') 获取栈后
 * pushPathByName(name, param) 跳转，NavDestination.onReady 中 ctx.pathInfo.param 取参。
 */
import { MetadataTerm, asRecord, asString, metadataTermFromObject } from '../models/Models';

export type SearchScope = 'source' | 'library' | 'all';
export type SearchField = 'author' | 'tag';

/** 来源身份与原词一起传递，避免译名进入图源协议。 */
export class SearchSelection {
  sourceId: string;
  field: SearchField;
  term: MetadataTerm;
  constructor(sourceId: string, field: SearchField, term: MetadataTerm) {
    this.sourceId = sourceId;
    this.field = field;
    this.term = term;
  }
}

export function searchSelectionFromObject(value: Object | undefined): SearchSelection | null {
  if (value === undefined) { return null; }
  const row: Record<string, Object> | null = asRecord(value);
  if (row === null || typeof row['sourceId'] !== 'string' ||
    (row['field'] !== 'author' && row['field'] !== 'tag')) {
    throw new Error('搜索条件格式无效');
  }
  return new SearchSelection(asString(row['sourceId']), asString(row['field']) as SearchField,
    metadataTermFromObject(row['term']));
}

export const ROUTE_SEARCH: string = 'search';
export const ROUTE_ALBUM: string = 'albumDetail';
export const ROUTE_READER: string = 'reader';
export const ROUTE_DOWNLOADS: string = 'downloads';
export const ROUTE_PREVIEW: string = 'chapterPreview';
export const ROUTE_JM_SETTINGS: string = 'jmSettings';
export const ROUTE_JM_BROWSE: string = 'jmBrowse';
export const ROUTE_EH_BROWSE: string = 'ehBrowse';
export const ROUTE_BLOCK_RULES: string = 'blockRules';
export const ROUTE_STATS: string = 'readingStats';
export const ROUTE_SOURCE_BROWSE: string = 'sourceBrowse';
export const ROUTE_SUWAYOMI_LIBRARY: string = 'suwayomiLibrary';
export const ROUTE_SOURCE_SETTINGS: string = 'sourceSettings';
export const ROUTE_SUWAYOMI_CONNECT: string = 'suwayomiConnect';
export const ROUTE_EH_SITE: string = 'ehSite';
export const ROUTE_READER_SETTINGS: string = 'readerSettings';
export const ROUTE_APPEARANCE: string = 'appearanceSettings';
export const ROUTE_PRIVACY: string = 'privacySettings';
export const ROUTE_STORAGE: string = 'storageSettings';

/** 导航参数在来源边界之外始终使用完整来源标识。 */
export interface MangaRouteParams {
  aid?: string;
  chapterId?: string;
  chapterIndex?: number;
  page?: number;
  sourceId?: string;
  matchAid?: string;
  query?: string;
  scope?: SearchScope;
  selection?: SearchSelection;
  match?: boolean;
  /** 仅从书架进入时为 true，决定详情页是否提供多源换源入口。 */
  fromLibrary?: boolean;
  browseMode?: string;
  order?: string;
}

/** MainShell 写入、Index.onBackPress 读取：NavDestination 在栈上时 > 0，Tab 首页为 0 */
export const NAV_STACK_DEPTH_KEY: string = 'navStackDepth';
