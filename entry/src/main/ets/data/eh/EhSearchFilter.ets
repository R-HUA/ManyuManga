/**
 * E-Hentai 高级搜索筛选：10 大分类掩码、搜索模式（普通/标签/上传者/关注）、
 * advsearch 十项开关、最低评分与页数区间。URL 语义与 HarmonyOS-EhViewer 对齐：
 *  f_cats 传「未选分类」的补码掩码；f_sr/f_srdd 评分下限；f_sp/f_spf/f_spt 页数区间；
 *  标签模式把关键词规范成 `f:"tag"$` 形式的精确标签；上传者模式走 /uploader/{name}。
 */
import { EhUrl } from './EhNative';
import { ehTagQuery } from './EhQuery';
import { EhSettings } from './EhSettings';
import { Prefs } from '../../util/Prefs';
import { asRecord, asNumber, asBool, asString } from '../../models/Models';

const PREF_KEY: string = 'eh_search_filter_v1';

export const EH_CATEGORY_ALL: number = 0x3ff;

export class EhCategoryOption {
  label: string;
  bit: number;
  color: string;

  constructor(label: string, bit: number, color: string) {
    this.label = label;
    this.bit = bit;
    this.color = color;
  }
}

/** EH 官方分类位序与色标（对齐 AppConstants.SEARCH_CATEGORY_OPTIONS）。 */
export const EH_CATEGORY_OPTIONS: Array<EhCategoryOption> = [
  new EhCategoryOption('同人志', 0x2, '#F44336'),
  new EhCategoryOption('漫画', 0x4, '#FF9800'),
  new EhCategoryOption('画师 CG', 0x8, '#FBC02D'),
  new EhCategoryOption('游戏 CG', 0x10, '#4CAF50'),
  new EhCategoryOption('西方', 0x200, '#8BC34A'),
  new EhCategoryOption('非 H', 0x100, '#2196F3'),
  new EhCategoryOption('图集', 0x20, '#3F51B5'),
  new EhCategoryOption('Cosplay', 0x40, '#9C27B0'),
  new EhCategoryOption('亚洲成人', 0x80, '#E91E63'),
  new EhCategoryOption('其他', 0x1, '#607D8B')
];

export type EhSearchMode = 'normal' | 'tag' | 'uploader' | 'watched';

export class EhSearchFilter {
  /** 已选分类掩码（含）；URL 上以补码形式传给 f_cats。 */
  categoryMask: number = EH_CATEGORY_ALL;
  mode: EhSearchMode = 'normal';
  /** advsearch=1 总开关与其下十项（对应 f_sname/f_stags/... ）。 */
  advanced: boolean = false;
  inName: boolean = true;
  inTags: boolean = true;
  inDescription: boolean = false;
  inTorrents: boolean = false;
  inLowPowerTags: boolean = false;
  showExpunged: boolean = false;
  showDownvoted: boolean = false;
  inFileName: boolean = false;
  inUploader: boolean = false;
  inTorrentFile: boolean = false;
  /** 最低评分（0 = 不限，2..5 对应 f_srdd）。 */
  minRating: number = 0;
  /** 页数区间（空串 = 不限）。 */
  pageFrom: string = '';
  pageTo: string = '';

  public copyFrom(other: EhSearchFilter): void {
    this.categoryMask = other.categoryMask;
    this.mode = other.mode;
    this.advanced = other.advanced;
    this.inName = other.inName;
    this.inTags = other.inTags;
    this.inDescription = other.inDescription;
    this.inTorrents = other.inTorrents;
    this.inLowPowerTags = other.inLowPowerTags;
    this.showExpunged = other.showExpunged;
    this.showDownvoted = other.showDownvoted;
    this.inFileName = other.inFileName;
    this.inUploader = other.inUploader;
    this.inTorrentFile = other.inTorrentFile;
    this.minRating = other.minRating;
    this.pageFrom = other.pageFrom;
    this.pageTo = other.pageTo;
  }

  /** 任一筛选项偏离默认值（顶栏红点提示用）。 */
  public hasActiveFilter(): boolean {
    return this.categoryMask !== EH_CATEGORY_ALL || this.mode !== 'normal' || this.advanced ||
      this.minRating > 0 || this.pageFrom !== '' || this.pageTo !== '';
  }

  /** 分类是否勾选。 */
  public categoryOn(bit: number): boolean {
    return (this.categoryMask & bit) === bit;
  }

  public toggleCategory(bit: number): void {
    this.categoryMask = this.categoryOn(bit)
      ? (this.categoryMask & ~bit) & EH_CATEGORY_ALL
      : (this.categoryMask | bit) & EH_CATEGORY_ALL;
  }

  private static numeric(value: string): string {
    const trimmed: string = value.trim();
    if (trimmed === '') {
      return '';
    }
    const n: number = Number(trimmed);
    if (!Number.isFinite(n) || n < 0) {
      return '';
    }
    return `${Math.floor(n)}`;
  }


  /**
   * 构建搜索/列表 URL：mode 决定基址（关注=watched，上传者=/uploader/，其余=站点根），
   * 分类掩码作用于全部模式；高级开关、评分、页数仅在 advanced 开启时附加。
   */
  public buildUrl(query: string): string {
    const site: string = EhSettings.effectiveSite();
    const trimmed: string = query.trim();
    if (this.mode === 'uploader' && trimmed !== '') {
      return `${EhUrl.host(site)}uploader/${encodeURIComponent(trimmed)}`;
    }
    const base: string = this.mode === 'watched' ? EhUrl.watched(site) : EhUrl.host(site);
    const params: Array<string> = [];
    if (this.categoryMask !== EH_CATEGORY_ALL) {
      params.push(`f_cats=${(~this.categoryMask) & EH_CATEGORY_ALL}`);
    }
    const keyword: string = this.mode === 'tag' ? ehTagQuery(trimmed) : trimmed;
    if (keyword !== '') {
      params.push(`f_search=${encodeURIComponent(keyword)}`);
    }
    if (this.advanced) {
      params.push('advsearch=1');
      if (this.inName) { params.push('f_sname=on'); }
      if (this.inTags) { params.push('f_stags=on'); }
      if (this.inDescription) { params.push('f_sdesc=on'); }
      if (this.inTorrents) { params.push('f_storr=on'); }
      if (this.inLowPowerTags) { params.push('f_sto=on'); }
      if (this.showExpunged) { params.push('f_sdt1=on'); }
      if (this.showDownvoted) { params.push('f_sdt2=on'); }
      if (this.inFileName) { params.push('f_sfl=on'); }
      if (this.inUploader) { params.push('f_sfu=on'); }
      if (this.inTorrentFile) { params.push('f_sft=on'); }
      const rating: string = EhSearchFilter.numeric(`${this.minRating}`);
      if (this.minRating >= 2) {
        params.push('f_sr=on');
        params.push(`f_srdd=${rating}`);
      }
      const from: string = EhSearchFilter.numeric(this.pageFrom);
      const to: string = EhSearchFilter.numeric(this.pageTo);
      if (from !== '' || to !== '') {
        params.push('f_sp=on');
        params.push(`f_spf=${from}`);
        params.push(`f_spt=${to}`);
      }
    }
    if (params.length === 0) {
      return base;
    }
    return base.indexOf('?') >= 0 ? `${base}&${params.join('&')}` : `${base}?${params.join('&')}`;
  }

  /** 仅应用分类掩码的列表 URL（首页/关注/收藏页签，对齐 EhViewer 分类快捷过滤）。 */
  public buildListUrl(base: string): string {
    if (this.categoryMask === EH_CATEGORY_ALL) {
      return base;
    }
    const param: string = `f_cats=${(~this.categoryMask) & EH_CATEGORY_ALL}`;
    return base.indexOf('?') >= 0 ? `${base}&${param}` : `${base}?${param}`;
  }

  public static async load(): Promise<EhSearchFilter> {
    const filter: EhSearchFilter = new EhSearchFilter();
    try {
      const prefs: Prefs = await Prefs.getInstance();
      const raw: Record<string, Object> | null = asRecord(JSON.parse(await prefs.getString(PREF_KEY, '')));
      if (raw !== null) {
        filter.categoryMask = asNumber(raw['categoryMask'], EH_CATEGORY_ALL) & EH_CATEGORY_ALL;
        const mode: string = asString(raw['mode'], 'normal');
        filter.mode = mode === 'tag' || mode === 'uploader' || mode === 'watched' ? mode : 'normal';
        filter.advanced = asBool(raw['advanced'], false);
        filter.inName = asBool(raw['inName'], true);
        filter.inTags = asBool(raw['inTags'], true);
        filter.inDescription = asBool(raw['inDescription'], false);
        filter.inTorrents = asBool(raw['inTorrents'], false);
        filter.inLowPowerTags = asBool(raw['inLowPowerTags'], false);
        filter.showExpunged = asBool(raw['showExpunged'], false);
        filter.showDownvoted = asBool(raw['showDownvoted'], false);
        filter.inFileName = asBool(raw['inFileName'], false);
        filter.inUploader = asBool(raw['inUploader'], false);
        filter.inTorrentFile = asBool(raw['inTorrentFile'], false);
        filter.minRating = asNumber(raw['minRating'], 0);
        filter.pageFrom = asString(raw['pageFrom'], '');
        filter.pageTo = asString(raw['pageTo'], '');
      }
    } catch (e) {
      // 解析失败回默认
    }
    return filter;
  }

  public async save(): Promise<void> {
    const prefs: Prefs = await Prefs.getInstance();
    await prefs.putString(PREF_KEY, JSON.stringify(this));
  }
}
