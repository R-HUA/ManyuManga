/**
 * 路由名常量
 * MainShell 预注册以下全部路由；页面用 @Consume('navPathStack') 获取栈后
 * pushPathByName(name, param) 跳转，NavDestination.onReady 中 ctx.pathInfo.param 取参。
 */
export const ROUTE_SEARCH: string = 'search';
export const ROUTE_ALBUM: string = 'albumDetail';
export const ROUTE_READER: string = 'reader';
export const ROUTE_DOWNLOADS: string = 'downloads';
export const ROUTE_PREVIEW: string = 'chapterPreview';
export const ROUTE_JM_SETTINGS: string = 'jmSettings';
export const ROUTE_JM_BROWSE: string = 'jmBrowse';
export const ROUTE_EH_BROWSE: string = 'ehBrowse';
export const ROUTE_BLOCK_RULES: string = 'blockRules';

/** 导航参数在来源边界之外始终使用完整来源标识。 */
export interface MangaRouteParams {
  aid?: string;
  chapterId?: string;
  chapterIndex?: number;
  page?: number;
  sourceId?: string;
  matchAid?: string;
  query?: string;
  match?: boolean;
}

/** MainShell 写入、Index.onBackPress 读取：NavDestination 在栈上时 > 0，Tab 首页为 0 */
export const NAV_STACK_DEPTH_KEY: string = 'navStackDepth';
