/**
 * 搜索
 *
 *
 */
import pasteboard from '@ohos.pasteboard';
import { ACCENT, BG, CARD, CHIP_BG, CHIP_R, FONT_BODY, FONT_CAPTION, FONT_TITLE, PRIMARY,
  SPACE_L, SPACE_M, SPACE_S, SPACE_XS, SPACE_XL, TEXT_MAIN, TEXT_SUB } from '../common/Theme';
import { EmptyView, SectionTitle, SkeletonGrid, TagChip } from '../common/Components';
import { ROUTE_ALBUM } from '../common/Route';
import { TOP_RECT_HEIGHT_KEY, CURRENT_BREAKPOINT_KEY } from '../entryability/EntryAbility';
import { AlbumLite, asArray, asString, CategoryItem, SearchResult, errorMessage } from '../models/Models';
import { sourceApi as jmApi } from '../data/SourceApi';
import { searchHistoryStore } from '../data/Stores';
import { Prefs } from '../util/Prefs';
import { AlbumCard, AlbumSource, ChipOption, formatCount } from './CategoryPage';

/* ===== 路由参数 ===== */

class AlbumRouteParam {
  aid: string = '';
}

/** 车牌号/纯数字识别 */
const ID_RE: RegExp = /^(?:jm)?\s*(\d{1,10})$/i;

function matchAlbumId(raw: string): string {
  const q: string = raw.trim();
  const m: RegExpMatchArray | null = q.match(ID_RE);
  if (m !== null && m.length >= 2) {
    return m[1];
  }
  return '';
}

/** 搜索排序 */
const SEARCH_ORDER_OPTIONS: Array<ChipOption> = [
  new ChipOption('mr', '最新'),
  new ChipOption('mv', '最多观看'),
  new ChipOption('mp', '最多图片'),
  new ChipOption('tf', '最多爱心')
];

/** 时间范围 */
const TIME_OPTIONS: Array<ChipOption> = [
  new ChipOption('a', '全部时间'),
  new ChipOption('t', '今日'),
  new ChipOption('w', '本周'),
  new ChipOption('m', '本月')
];

function buildYearOptions(): Array<string> {
  const list: Array<string> = ['不限'];
  for (let y: number = 2026; y >= 2006; y--) {
    list.push(y.toString());
  }
  return list;
}

function buildMonthOptions(): Array<string> {
  const list: Array<string> = ['全年'];
  for (let m: number = 1; m <= 12; m++) {
    list.push(m.toString());
  }
  return list;
}

/* ===== 客户端筛选（S-09 语言多选+全彩 / S-10 自定义筛选词 / S-11 连扫补足） ===== */

/**
 * 自定义筛选词持久化 key（契约口径：feature-spec §6.3 允许页面用 Prefs.ets 自管 JSON；
 * PrefKeys 集中常量归数据层工程师所有，此处只定义页面级 key 字符串）。
 */
const SEARCH_FILTER_WORDS_KEY: string = 'search_filter_words';
/** 连扫补足单次上限（S-11：SearchStore.kt:185-219 单次上限 8 页） */
const SCAN_PAGE_LIMIT: number = 8;
/** 自定义筛选词长度上限（S-10：SearchScreen.kt:420-449，≤16 字符码点计数） */
const WORD_MAX_CP: number = 16;

/** 自定义筛选词（文本 + 勾选启用态；持久化为 JSON 数组） */
class FilterWord {
  text: string = '';
  enabled: boolean = true;
}

/** 语言筛选项（code=zh/ja/en/ko/none 未识别；SearchScreen.kt:410-418） */
const LANG_FILTER_OPTIONS: Array<ChipOption> = [
  new ChipOption('zh', '中字'),
  new ChipOption('ja', '日漫'),
  new ChipOption('en', '英文'),
  new ChipOption('ko', '韩漫'),
  new ChipOption('none', '未识别')
];

/* ── 语言/全彩启发式（E-12 简化口径：标题/作者/分类关键词 + 字符脚本统计）── */
const KW_ZH: Array<string> = ['中文', '漢化', '汉化', '中字', '中国', 'chinese', '翻譯', '翻译'];
const KW_JA: Array<string> = ['日本語', '日語', '日文', 'japanese', '生肉', '日版'];
const KW_KO: Array<string> = ['한국', '한글', '韓文', '韩文', 'korean'];
const KW_EN: Array<string> = ['english', '英文', '英譯', '英译', 'translated'];
const KW_FC: Array<string> = ['全彩', 'フルカラー', 'fullcolor', 'full color', '彩漫', '彩色'];

function containsWord(hay: string, words: Array<string>): boolean {
  for (const w of words) {
    if (hay.indexOf(w) >= 0) {
      return true;
    }
  }
  return false;
}

/** 语言归类：zh/ja/en/ko，均未命中返回 'none'（未识别） */
function detectLang(item: AlbumLite): string {
  const hay: string = `${item.title} ${item.author} ${item.category} ${item.categorySub}`.toLowerCase();
  if (containsWord(hay, KW_ZH)) {
    return 'zh';
  }
  if (containsWord(hay, KW_JA)) {
    return 'ja';
  }
  if (containsWord(hay, KW_KO)) {
    return 'ko';
  }
  if (containsWord(hay, KW_EN)) {
    return 'en';
  }
  // 字符脚本回退（LangDetect.kt:63-73：谚文→韩 / 假名→日 / 汉字→中 / 拉丁≥4→英）
  let hangul: number = 0;
  let kana: number = 0;
  let han: number = 0;
  let latin: number = 0;
  const text: string = `${item.title}${item.author}`;
  for (let i: number = 0; i < text.length; i++) {
    const c: number = text.charCodeAt(i);
    if ((c >= 0xAC00 && c <= 0xD7AF) || (c >= 0x3130 && c <= 0x318F)) {
      hangul++;
    } else if ((c >= 0x3040 && c <= 0x30FF) || (c >= 0x31F0 && c <= 0x31FF)) {
      kana++;
    } else if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF)) {
      han++;
    } else if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) {
      latin++;
    }
  }
  if (hangul > 0) {
    return 'ko';
  }
  if (kana > 0) {
    return 'ja';
  }
  if (han > 0) {
    return 'zh';
  }
  if (latin >= 4) {
    return 'en';
  }
  return 'none';
}

/** 全彩判定（E-12 简化口径：关键词命中） */
function isFullColorItem(item: AlbumLite): boolean {
  const hay: string = `${item.title} ${item.author} ${item.category} ${item.categorySub}`.toLowerCase();
  return containsWord(hay, KW_FC);
}

/** 码点计数（≤16 字符校验，等价 Kotlin codePointCount） */
function codePointCount(s: string): number {
  let n: number = 0;
  for (let i: number = 0; i < s.length; i++) {
    const c: number = s.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
      const c2: number = s.charCodeAt(i + 1);
      if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
        i++;
      }
    }
    n++;
  }
  return n;
}

/** 热门搜索词缓存（S-16 替代口径：/categories 分类名，无趋势 API 不伪造数据） */
let cachedHotWords: Array<string> | null = null;

/** 筛选抽屉里的单选项行 */
@Component
struct OptionRow {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  onTap: () => void = () => {};

  build() {
    Row() {
      Text(this.label)
        .fontSize(FONT_BODY)
        .fontColor(this.selected ? PRIMARY : TEXT_MAIN)
        .layoutWeight(1)
      if (this.selected) {
        Text('✓')
          .fontSize(FONT_BODY)
          .fontColor(PRIMARY)
      }
    }
    .width('100%')
    .padding({ top: 11, bottom: 11 })
    .onClick(() => {
      this.onTap();
    })
  }
}

@Component
export struct SearchPage {
  @Consume('navPathStack') navPathStack: NavPathStack;

  // 评审 Step2：顶部状态栏避让高度（EntryAbility 全屏布局写入 AppStorage，顶栏 padding 引用）
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 38;
  // 一多断点：结果网格列数随窗口宽度联动（sm 3 / md 4 / lg 5）
  @StorageProp(CURRENT_BREAKPOINT_KEY) bp: string = 'sm';

  // 搜索输入与结果
  @State keyword: string = '';
  @State searched: boolean = false;
  @State loading: boolean = false;
  @State errorMsg: string = '';
  @State total: number = 0;
  @State page: number = 1;
  @State resultCount: number = 0;

  // 历史与热搜
  @State history: Array<string> = [];
  @State hotWords: Array<string> = [];
  // S-12 长按多选（评审 Step2，对齐原版交互）：多选态与已勾选的历史词
  @State historySelectMode: boolean = false;
  @State selectedHistory: Array<string> = [];
  // S-15 剪贴板识别升级（评审 Step2）：识别到的 JM 编号，建议区顶部展示直达横幅
  @State clipboardAid: string = '';

  // 筛选（S-06/S-07/S-08 服务端参数；S-09/S-10 客户端筛选）
  @State filterSheet: boolean = false;
  @State order: string = 'mr';
  @State timeRange: string = 'a';
  @State yearSel: string = '';
  @State monthSel: string = '';
  @State pickYearIdx: number = 0;
  @State pickMonthIdx: number = 0;

  // 客户端筛选（S-09 语言多选 + 全彩；S-10 自定义筛选词）
  @State filterLangs: Array<string> = [];
  @State fullColorOnly: boolean = false;
  @State filterWords: Array<FilterWord> = [];
  @State wordInput: string = '';
  @State wordError: string = '';
  // S-11 连扫补足状态（已扫 API 页数 / 筛后累计条数）
  @State scanPages: number = 0;
  @State filteredTotal: number = 0;

  private source: AlbumSource = new AlbumSource();
  private scroller: Scroller = new Scroller();
  @State pageSize: number = 45; // 首页条数动态校准（影响页码展示，需 @State）
  private requestSeq: number = 0;
  private yearOptions: Array<string> = buildYearOptions();
  private monthOptions: Array<string> = buildMonthOptions();
  // S-11 连扫累计器（非渲染成员）：筛选后累计结果 / 已扫到的 API 页 / 是否已扫尽
  private accItems: Array<AlbumLite> = [];
  private scannedTo: number = 0;
  private scanExhausted: boolean = false;
  /** 连扫去重已见 id 集（新搜索/筛选变更时重置）：重复 id 会导致 LazyForEach key 冲突、渲染错乱 */
  private accSeenIds: Set<string> = new Set<string>();

  /** 批内去重（普通搜索整页替换用） */
  private dedupById(list: Array<AlbumLite>): Array<AlbumLite> {
    const seen: Set<string> = new Set<string>();
    const out: Array<AlbumLite> = [];
    for (const it of list) {
      if (it.id !== '') {
        if (seen.has(it.id)) {
          continue;
        }
        seen.add(it.id);
      }
      out.push(it);
    }
    return out;
  }

  /** 响应式网格列数（与 CategoryPage 一致：sm 3 / md 4 / lg 5） */
  private gridColumns(): number {
    return this.bp === 'sm' ? 3 : (this.bp === 'md' ? 4 : 5);
  }

  /** WaterFlow 列模板串（如 '1fr 1fr 1fr'），随断点联动 */
  private columnsTemplateStr(): string {
    const parts: Array<string> = [];
    for (let i: number = 0; i < this.gridColumns(); i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  aboutToAppear(): void {
    this.loadHistory().catch((e: Error) => {
      console.info(`[SearchPage] 历史读取失败: ${errorMessage(e)}`);
    });
    this.loadHotWords();
    this.loadFilterWords().catch((e: Error) => {
      console.info(`[SearchPage] 自定义筛选词读取失败: ${errorMessage(e)}`);
    });
  }

  // ── 生命周期与参数 ──

  private handleReady(ctx: NavDestinationContext): void {
    // 本 SDK 的 NavPathInfo.param 为 unknown（ArkTS 禁止显式 unknown 注解），在使用处直接窄化转型
    const rec: Record<string, Object> | undefined = ctx.pathInfo.param as Record<string, Object> | undefined;
    let query: string = '';
    if (rec !== undefined && rec !== null) {
      query = asString(rec['query']);
    }
    if (query !== '') {
      // S-03 外部搜索请求（详情标签/作者、书架标签 chips 带入）：预填并自动执行
      this.keyword = query;
      this.submit(query);
    }
  }

  /** S-15（Review H-3 改版）：仅由安全组件 PasteButton 授权后调用——读到 JM 编号则预填输入框（不自动搜索） */
  private async pasteFromClipboard(): Promise<void> {
    try {
      const data: pasteboard.PasteData = await pasteboard.getSystemPasteboard().getData();
      // 本 SDK 的 PasteData 无 getPrimary()；用 getPrimaryText() 取纯文本（非文本记录会抛错，走 catch）
      const text: string = data.getPrimaryText().trim();
      const aid: string = matchAlbumId(text);
      if (text !== '' && aid !== '') {
        this.keyword = text;
        this.clipboardAid = aid; // 评审 Step2：记录识别结果，建议区顶部展示直达横幅
      } else {
        this.clipboardAid = ''; // 非编号内容：清掉旧横幅避免误导
      }
    } catch (e) {
      console.info(`[SearchPage] 剪贴板读取失败: ${errorMessage(e as Error)}`);
    }
  }

  // ── 数据 ──

  private async loadHistory(): Promise<void> {
    this.history = await searchHistoryStore.getList();
  }

  private async loadHotWords(): Promise<void> {
    if (cachedHotWords !== null) {
      this.hotWords = cachedHotWords;
      return;
    }
    try {
      const cats: Array<CategoryItem> = await jmApi.categories();
      const words: Array<string> = [];
      for (const c of cats) {
        if (c.name !== '') {
          words.push(c.name);
        }
      }
      cachedHotWords = words;
      this.hotWords = words;
    } catch (e) {
      console.info(`[SearchPage] 热门词加载失败: ${errorMessage(e as Error)}`);
    }
  }

  // ── 客户端筛选（S-09/S-10）：词表持久化 + 匹配口径 ──

  /** 读取持久化的自定义筛选词（Prefs 自管 JSON；坏数据静默回退空表） */
  private async loadFilterWords(): Promise<void> {
    const prefs: Prefs = await Prefs.getInstance();
    const text: string = await prefs.getString(SEARCH_FILTER_WORDS_KEY, '[]');
    const out: Array<FilterWord> = [];
    try {
      const parsed: Object | null = JSON.parse(text) as Object | null;
      const arr: Array<Object> | null = asArray(parsed);
      if (arr !== null) {
        for (const it of arr) {
          const rec: Record<string, Object> | null = it as Record<string, Object>;
          const t: string = asString(rec['text']);
          if (t !== '') {
            const w: FilterWord = new FilterWord();
            w.text = t;
            const en: Object = rec['enabled'];
            w.enabled = typeof en === 'boolean' ? en : true;
            out.push(w);
          }
        }
      }
    } catch (e) {
      // 坏数据回退空表
    }
    this.filterWords = out;
  }

  private async persistFilterWords(): Promise<void> {
    const prefs: Prefs = await Prefs.getInstance();
    await prefs.putString(SEARCH_FILTER_WORDS_KEY, JSON.stringify(this.filterWords));
  }

  /** S-10 添加：trim、非空、≤16 码点、查重（SearchScreen.kt:420-449） */
  private async addFilterWord(): Promise<void> {
    const t: string = this.wordInput.trim();
    if (t === '') {
      this.wordError = '不能为空';
      return;
    }
    const cp: number = codePointCount(t);
    if (cp > WORD_MAX_CP) {
      this.wordError = `最多 ${WORD_MAX_CP} 个字符（当前 ${cp}）`;
      return;
    }
    for (const w of this.filterWords) {
      if (w.text === t) {
        this.wordError = '已存在';
        return;
      }
    }
    const w: FilterWord = new FilterWord();
    w.text = t;
    w.enabled = true;
    this.filterWords = this.filterWords.concat([w]);
    this.wordInput = '';
    this.wordError = '';
    await this.persistFilterWords().catch((e: Error) => {
      console.info(`[SearchPage] 筛选词保存失败: ${errorMessage(e)}`);
    });
    this.retriggerIfSearched();
  }

  private async removeFilterWord(text: string): Promise<void> {
    this.filterWords = this.filterWords.filter((w: FilterWord): boolean => w.text !== text);
    await this.persistFilterWords().catch((e: Error) => {
      console.info(`[SearchPage] 筛选词删除保存失败: ${errorMessage(e)}`);
    });
    this.retriggerIfSearched();
  }

  private async toggleFilterWord(text: string): Promise<void> {
    const next: Array<FilterWord> = [];
    for (const w of this.filterWords) {
      const c: FilterWord = new FilterWord();
      c.text = w.text;
      c.enabled = w.text === text ? !w.enabled : w.enabled;
      next.push(c);
    }
    this.filterWords = next;
    await this.persistFilterWords().catch((e: Error) => {
      console.info(`[SearchPage] 筛选词勾选保存失败: ${errorMessage(e)}`);
    });
    this.retriggerIfSearched();
  }

  /** S-09 语言勾选（多选，再点取消） */
  private async toggleLang(code: string): Promise<void> {
    if (this.filterLangs.indexOf(code) >= 0) {
      this.filterLangs = this.filterLangs.filter((c: string): boolean => c !== code);
    } else {
      this.filterLangs = this.filterLangs.concat([code]);
    }
    this.retriggerIfSearched();
  }

  private async toggleFullColor(): Promise<void> {
    this.fullColorOnly = !this.fullColorOnly;
    this.retriggerIfSearched();
  }

  /** 客户端筛选是否激活（S-11：激活时走连扫补足 + 虚拟分页） */
  private clientFilterActive(): boolean {
    if (this.filterLangs.length > 0 || this.fullColorOnly) {
      return true;
    }
    for (const w of this.filterWords) {
      if (w.enabled) {
        return true;
      }
    }
    return false;
  }

  /**
   * 客户端匹配口径（SearchStore.kt:337-373：语言=或、自定义词=或、两组与）。
   * 未勾选语言=不限语言；未启用任何词=不限词。
   */
  private matchesClientFilter(item: AlbumLite): boolean {
    if (this.filterLangs.length > 0) {
      if (this.filterLangs.indexOf(detectLang(item)) < 0) {
        return false;
      }
    }
    if (this.fullColorOnly && !isFullColorItem(item)) {
      return false;
    }
    let hasEnabled: boolean = false;
    for (const w of this.filterWords) {
      if (!w.enabled) {
        continue;
      }
      hasEnabled = true;
      const hay: string =
        `${item.title} ${item.author} ${item.category} ${item.categorySub}`.toLowerCase();
      if (hay.indexOf(w.text.toLowerCase()) >= 0) {
        return true; // 词组内命中任一即可（或）
      }
    }
    if (hasEnabled) {
      return false; // 有启用词但未命中
    }
    return true;
  }

  // ── 搜索流程 ──

  private submitCurrent(): void {
    this.submit(this.keyword);
  }

  private submit(raw: string): void {
    const q: string = raw.trim();
    if (q === '' || this.loading) {
      return; // S-01 空输入不触发
    }
    const aid: string = matchAlbumId(q);
    if (aid !== '') {
      // S-02 JM 编号直达：纯编号 / jm 前缀编号不进关键词搜索（SearchScreen.kt:104-114）
      const p: AlbumRouteParam = new AlbumRouteParam();
      p.aid = aid;
      this.navPathStack.pushPathByName(ROUTE_ALBUM, p);
      return;
    }
    this.keyword = q;
    searchHistoryStore.record(q).then((): void => {
      this.loadHistory();
    }).catch((e: Error) => {
      console.info(`[SearchPage] 历史写入失败: ${errorMessage(e)}`);
    });
    this.doSearch(q, 1);
  }

  private async doSearch(q: string, target: number): Promise<void> {
    if (this.clientFilterActive()) {
      await this.doFilteredSearch(q, target);
      return;
    }
    const seq: number = ++this.requestSeq;
    this.loading = true;
    this.errorMsg = '';
    try {
      const r: SearchResult =
        await jmApi.search(q, target, this.order, this.timeRange, this.yearSel, this.monthSel);
      if (seq !== this.requestSeq) {
        return;
      }
      this.total = r.total;
      if (r.list.length === 0 && target > 1) {
        // 翻页空结果：保留旧结果，仅提示（S-05/S-14）
        this.errorMsg = '没有更多了';
        return;
      }
      const fresh: Array<AlbumLite> = this.dedupById(r.list);
      this.source.setItems(fresh);
      this.resultCount = fresh.length;
      this.page = target;
      this.searched = true;
      if (target === 1 && r.list.length > 0) {
        this.pageSize = Math.max(r.list.length, 1); // 用首页条数估算每页大小（SearchStore.kt:183）
      }
      if (target === 1) {
        try {
          this.scroller.scrollToIndex(0);
        } catch (e) {
          console.info(`[SearchPage] 滚动复位跳过: ${errorMessage(e as Error)}`);
        }
      }
    } catch (e) {
      if (seq !== this.requestSeq) {
        return;
      }
      this.errorMsg = errorMessage(e as Error);
    } finally {
      if (seq === this.requestSeq) {
        this.loading = false;
      }
    }
  }

  /**
   * S-11 筛选补足自动扫描（SearchStore.kt:185-219 简化版）：
   * 客户端筛选激活时按 API 页连续扫描累积筛选结果，直到装满目标虚拟页
   * （target × pageSize 条）或单次扫满 8 页 / 已扫尽；虚拟页 = 累积结果的切片。
   */
  private async doFilteredSearch(q: string, target: number): Promise<void> {
    const seq: number = ++this.requestSeq;
    this.loading = true;
    this.errorMsg = '';
    if (target <= 1) {
      // 新搜索/筛选变更：重置累积器
      this.accItems = [];
      this.accSeenIds = new Set<string>();
      this.scannedTo = 0;
      this.scanExhausted = false;
    }
    try {
      const need: number = target * this.pageSize;
      let scannedThisCall: number = 0;
      while (this.accItems.length < need && !this.scanExhausted && scannedThisCall < SCAN_PAGE_LIMIT) {
        const apiPage: number = this.scannedTo + 1;
        const r: SearchResult =
          await jmApi.search(q, apiPage, this.order, this.timeRange, this.yearSel, this.monthSel);
        if (seq !== this.requestSeq) {
          return;
        }
        this.scannedTo = apiPage;
        scannedThisCall++;
        this.scanPages = apiPage;
        if (apiPage === 1 && r.list.length > 0) {
          this.pageSize = Math.max(r.list.length, 1);
        }
        if (r.list.length === 0) {
          this.scanExhausted = true;
          break;
        }
        const kept: Array<AlbumLite> = [];
        for (const it of r.list) {
          if (!this.matchesClientFilter(it)) {
            continue;
          }
          if (it.id !== '') {
            if (this.accSeenIds.has(it.id)) {
              continue;
            }
            this.accSeenIds.add(it.id);
          }
          kept.push(it);
        }
        this.accItems = this.accItems.concat(kept);
        this.filteredTotal = this.accItems.length;
      }
      const from: number = (target - 1) * this.pageSize;
      const slice: Array<AlbumLite> = this.accItems.slice(from, from + this.pageSize);
      if (slice.length === 0 && target > 1) {
        this.errorMsg = '没有更多了';
        return;
      }
      this.source.setItems(slice);
      this.resultCount = slice.length;
      this.page = target;
      this.searched = true;
      this.total = this.scanExhausted ? this.accItems.length : this.total;
      try {
        this.scroller.scrollToIndex(0);
      } catch (e) {
        console.info(`[SearchPage] 滚动复位跳过: ${errorMessage(e as Error)}`);
      }
    } catch (e) {
      if (seq !== this.requestSeq) {
        return;
      }
      this.errorMsg = errorMessage(e as Error);
    } finally {
      if (seq === this.requestSeq) {
        this.loading = false;
      }
    }
  }

  private pageCount(): number {
    if (this.clientFilterActive()) {
      // 虚拟分页：筛后累计条数切页；未扫尽时至少保留下一页可试探
      const byFiltered: number = Math.max(1, Math.ceil(this.filteredTotal / this.pageSize));
      return this.scanExhausted ? byFiltered : Math.max(byFiltered, this.page + 1);
    }
    if (this.total <= 0) {
      return 1;
    }
    return Math.max(1, Math.ceil(this.total / this.pageSize));
  }

  private hasNextPage(): boolean {
    return this.page < this.pageCount();
  }

  private goPage(target: number): void {
    if (this.loading || target < 1 || target > this.pageCount()) {
      return;
    }
    if (target === this.page) {
      return;
    }
    this.doSearch(this.keyword.trim(), target);
  }

  private retrySearch(): void {
    const q: string = this.keyword.trim();
    if (q !== '') {
      this.doSearch(q, 1);
    }
  }

  // ── 历史操作（S-12：点击即搜 / 单条删除 / 清空确认） ──

  private removeOneHistory(h: string): void {
    searchHistoryStore.removeAll([h]).then((): void => {
      this.loadHistory();
    }).catch((e: Error) => {
      console.info(`[SearchPage] 历史删除失败: ${errorMessage(e)}`);
    });
  }

  // ── S-12 历史长按多选（评审 Step2，对齐原版：长按进入多选，点击切换勾选，底栏批量删除） ──

  private isHistoryPicked(h: string): boolean {
    return this.selectedHistory.indexOf(h) >= 0;
  }

  private toggleHistoryPicked(h: string): void {
    if (this.isHistoryPicked(h)) {
      this.selectedHistory = this.selectedHistory.filter((s: string): boolean => s !== h);
    } else {
      this.selectedHistory = this.selectedHistory.concat([h]);
    }
  }

  private enterHistorySelect(h: string): void {
    this.historySelectMode = true;
    this.selectedHistory = [h];
  }

  private exitHistorySelect(): void {
    this.historySelectMode = false;
    this.selectedHistory = [];
  }

  /** 批量删除所选历史（searchHistoryStore.removeAll(queries)，Stores.ets:490） */
  private removeSelectedHistory(): void {
    if (this.selectedHistory.length === 0) {
      return;
    }
    const picks: Array<string> = this.selectedHistory.slice();
    searchHistoryStore.removeAll(picks).then((): void => {
      this.exitHistorySelect(); // 评审 Step2：删完退出多选并刷新列表
      this.loadHistory();
    }).catch((e: Error) => {
      console.info(`[SearchPage] 历史批量删除失败: ${errorMessage(e)}`);
    });
  }

  private confirmClearHistory(): void {
    this.getUIContext().showAlertDialog({
      message: `将删除全部 ${this.history.length} 条搜索历史，确定吗？`,
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '清空',
        fontColor: PRIMARY,
        action: (): void => {
          searchHistoryStore.clear().then((): void => {
            this.loadHistory();
          }).catch((e: Error) => {
            console.info(`[SearchPage] 历史清空失败: ${errorMessage(e)}`);
          });
        }
      }
    });
  }

  // ── 筛选操作（S-06/S-07/S-08：条件变更后从第 1 页重跑，SearchStore.restartIfSearched） ──

  private retriggerIfSearched(): void {
    if (this.searched && this.keyword.trim() !== '') {
      this.doSearch(this.keyword.trim(), 1);
    }
  }

  private applyOrder(code: string): void {
    if (this.order === code) {
      return;
    }
    this.order = code;
    this.retriggerIfSearched();
  }

  private applyTime(code: string): void {
    if (this.timeRange === code && this.yearSel === '') {
      return;
    }
    this.timeRange = code;
    if (code !== 'a') {
      // 预设时间与指定年月互斥（SearchStore.kt:263-281）
      this.yearSel = '';
      this.monthSel = '';
      this.pickYearIdx = 0;
      this.pickMonthIdx = 0;
    }
    this.retriggerIfSearched();
  }

  private applyDate(): void {
    const year: string = this.pickYearIdx === 0 ? '' : this.yearOptions[this.pickYearIdx];
    const month: string = this.pickMonthIdx === 0 ? '' : this.monthOptions[this.pickMonthIdx];
    this.yearSel = year;
    this.monthSel = year === '' ? '' : month;
    if (this.yearSel !== '') {
      this.timeRange = 'a'; // 年月与时间预设互斥
    }
    this.retriggerIfSearched();
  }

  private clearDate(): void {
    this.pickYearIdx = 0;
    this.pickMonthIdx = 0;
    this.yearSel = '';
    this.monthSel = '';
    this.retriggerIfSearched();
  }

  private activeFilterCount(): number {
    let n: number = 0;
    if (this.order !== 'mr') {
      n++;
    }
    if (this.timeRange !== 'a') {
      n++;
    }
    if (this.yearSel !== '') {
      n++;
    }
    if (this.clientFilterActive()) {
      n++;
    }
    return n;
  }

  private filterSummary(): string {
    // S-11：客户端筛选激活时显示「已扫 N 页 · 筛后 M 条」（SearchScreen.kt:173-185）
    if (this.clientFilterActive() && this.searched) {
      let s: string = `已扫 ${this.scanPages} 页 · 筛后 ${this.filteredTotal} 条`;
      if (this.scanExhausted) {
        s += '（已扫完）';
      }
      return s;
    }
    let s: string = `共 ${formatCount(this.total.toString())} 条`;
    for (const opt of SEARCH_ORDER_OPTIONS) {
      if (opt.code === this.order && this.order !== 'mr') {
        s += ` · ${opt.label}`;
      }
    }
    for (const opt of TIME_OPTIONS) {
      if (opt.code === this.timeRange && this.timeRange !== 'a') {
        s += ` · ${opt.label}`;
      }
    }
    if (this.yearSel !== '') {
      s += ` · ${this.yearSel}-${this.monthSel === '' ? '全年' : this.monthSel}`;
    }
    return s;
  }

  private openAlbum(item: AlbumLite): void {
    const p: AlbumRouteParam = new AlbumRouteParam();
    p.aid = item.id;
    this.navPathStack.pushPathByName(ROUTE_ALBUM, p);
  }

  // ── UI ──

  @Builder
  private SearchBar() {
    Row({ space: SPACE_S }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(26)
        .fontColor([TEXT_MAIN])
        .onClick(() => {
          this.navPathStack.pop();
        })
      Row({ space: SPACE_S }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(16)
          .fontColor([TEXT_SUB])
        TextInput({ text: this.keyword, placeholder: '搜索漫画名、作者或 JM 编号' })
          .layoutWeight(1)
          .height(38)
          .padding({ left: 0, right: 0, top: 0, bottom: 0 })
          .backgroundColor(Color.Transparent)
          .fontSize(FONT_BODY)
          .fontColor(TEXT_MAIN)
          .placeholderColor(TEXT_SUB)
          .enterKeyType(EnterKeyType.Search)
          .onChange((v: string) => {
            this.keyword = v;
          })
          .onSubmit(() => {
            this.submitCurrent();
          })
      }
      .layoutWeight(1)
      .padding({ left: SPACE_M, right: SPACE_M })
      .height(40)
      .borderRadius(CHIP_R)
      .backgroundColor(CARD)

      Text('搜索')
        .fontSize(FONT_BODY)
        .fontColor(PRIMARY)
        .padding({ left: 4, right: 4, top: 8, bottom: 8 })
        .onClick(() => {
          this.submitCurrent();
        })
    }
    .width('100%')
    // 评审 Step2：顶部状态栏避让（全屏布局下自绘顶栏需叠加 topInset）
    .padding({ left: SPACE_L, right: SPACE_L, top: this.topInset + SPACE_S, bottom: SPACE_S })
    .alignItems(VerticalAlign.Center)
  }

  /** S-02：输入为纯数字 / JM 前缀编号时出现的直达按钮 */
  @Builder
  private DirectButton() {
    Row() {
      Text(`直达本子 JM${matchAlbumId(this.keyword)}`)
        .fontSize(FONT_BODY)
        .fontColor(Color.White)
        .padding({ left: SPACE_XL, right: SPACE_XL, top: 9, bottom: 9 })
        .backgroundColor(ACCENT)
        .borderRadius(CHIP_R)
        .onClick(() => {
          const aid: string = matchAlbumId(this.keyword);
          if (aid !== '') {
            const p: AlbumRouteParam = new AlbumRouteParam();
            p.aid = aid;
            this.navPathStack.pushPathByName(ROUTE_ALBUM, p);
          }
        })
    }
    .width('100%')
    .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_XS, bottom: SPACE_XS })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private StatusRow() {
    Column({ space: 4 }) {
      Row({ space: SPACE_S }) {
        Text(this.activeFilterCount() > 0 ? `筛选 · ${this.activeFilterCount()}` : '筛选')
          .fontSize(FONT_CAPTION)
          .fontColor(this.activeFilterCount() > 0 ? Color.White : PRIMARY)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(this.activeFilterCount() > 0 ? PRIMARY : CHIP_BG)
          .borderRadius(CHIP_R)
          .onClick(() => {
            this.filterSheet = true;
          })
        Text(this.filterSummary())
          .fontSize(FONT_CAPTION)
          .fontColor(TEXT_SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.loading) {
          LoadingProgress()
            .width(14)
            .height(14)
            .color(PRIMARY)
        }
      }
      .width('100%')

      // S-14：有旧结果时的错误/提示横幅（点此重试），旧结果不消失
      if (this.errorMsg !== '' && this.resultCount > 0) {
        Text(`⚠ ${this.errorMsg} · 点此重试`)
          .fontSize(FONT_CAPTION)
          .fontColor(PRIMARY)
          .width('100%')
          .onClick(() => {
            this.retrySearch();
          })
      }
    }
    .width('100%')
    .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_XS, bottom: SPACE_XS })
  }

  /** S-15（Review H-3 改版）：安全组件粘贴按钮——用户点击即获一次性剪贴板读取授权，无需申请 READ_PASTEBOARD */
  @Builder
  private PasteRow() {
    Row({ space: SPACE_M }) {
      PasteButton()
        .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
          if (result === PasteButtonOnClickResult.SUCCESS) {
            this.pasteFromClipboard();
          }
        })
      // 评审 Step2：粘贴按钮旁说明文字，说明可粘贴编号或关键词
      Text('粘贴编号或关键词')
        .fontSize(FONT_CAPTION)
        .fontColor(TEXT_SUB)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Start)
  }

  /** S-15 剪贴板识别升级（评审 Step2）：识别到 JM 编号后的显眼直达横幅，点击按 S-02 逻辑跳详情 */
  @Builder
  private ClipboardBanner() {
    Row({ space: SPACE_M }) {
      Text('📋')
        .fontSize(18)
      Column({ space: 2 }) {
        Text(`检测到剪贴板编号 JM${this.clipboardAid}`)
          .fontSize(FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('点击直达')
          .fontSize(FONT_CAPTION)
          .fontColor(Color.White)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(18)
        .fontColor(Color.White)
    }
    .width('100%')
    .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_M, bottom: SPACE_M })
    .backgroundColor(PRIMARY)
    .borderRadius(CHIP_R)
    .margin({ left: SPACE_L, right: SPACE_L })
    .onClick(() => {
      const aid: string = this.clipboardAid;
      if (aid !== '') {
        const p: AlbumRouteParam = new AlbumRouteParam();
        p.aid = aid;
        this.navPathStack.pushPathByName(ROUTE_ALBUM, p);
      }
    })
  }

  /** S-12 多选态底栏（评审 Step2）：删除所选(N) / 完成，沿用页面现有按钮风格 */
  @Builder
  private HistorySelectBar() {
    Row({ space: SPACE_S }) {
      Text(`删除所选(${this.selectedHistory.length})`)
        .fontSize(FONT_BODY)
        .fontColor(this.selectedHistory.length > 0 ? Color.White : TEXT_SUB)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .padding({ top: 10, bottom: 10 })
        .backgroundColor(this.selectedHistory.length > 0 ? PRIMARY : CHIP_BG)
        .borderRadius(CHIP_R)
        .onClick(() => {
          this.removeSelectedHistory();
        })
      Text('完成')
        .fontSize(FONT_BODY)
        .fontColor(TEXT_MAIN)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .padding({ top: 10, bottom: 10 })
        .backgroundColor(CHIP_BG)
        .borderRadius(CHIP_R)
        .onClick(() => {
          this.exitHistorySelect();
        })
    }
    .width('100%')
    .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_S, bottom: SPACE_S })
    .backgroundColor(CARD)
  }

  /** 输入为空且未搜索：粘贴直达 + 历史 + 热门搜索（S-12 / S-16 替代口径） */
  @Builder
  private SuggestBody() {
    Scroll() {
      Column({ space: SPACE_L }) {
        this.PasteRow()

        if (this.history.length > 0) {
          Column({ space: SPACE_S }) {
            SectionTitle({
              title: '搜索历史',
              // 评审 Step2：多选态隐藏「清空」，避免与批量删除混淆
              actionText: this.historySelectMode ? '' : '清空',
              onAction: (): void => {
                this.confirmClearHistory();
              }
            })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.history, (h: string) => {
                Row({ space: 6 }) {
                  if (this.historySelectMode && this.isHistoryPicked(h)) {
                    // 评审 Step2：多选态勾选标记
                    Text('✓')
                      .fontSize(FONT_CAPTION)
                      .fontColor(PRIMARY)
                  }
                  Text(h)
                    .fontSize(FONT_CAPTION)
                    .fontColor(this.historySelectMode && this.isHistoryPicked(h) ? PRIMARY : TEXT_MAIN)
                    .maxLines(1)
                    .constraintSize({ maxWidth: 200 })
                  if (!this.historySelectMode) {
                    Text('✕')
                      .fontSize(FONT_CAPTION)
                      .fontColor(TEXT_SUB)
                      .onClick(() => {
                        this.removeOneHistory(h);
                      })
                  }
                }
                .padding({ left: 10, right: 8, top: 5, bottom: 5 })
                // 评审 Step2：选中态品牌粉描边/背景
                .backgroundColor(this.historySelectMode && this.isHistoryPicked(h) ? CARD : CHIP_BG)
                .borderRadius(CHIP_R)
                .border({
                  width: 1,
                  color: this.historySelectMode && this.isHistoryPicked(h) ? PRIMARY : Color.Transparent
                })
                .margin({ right: SPACE_S, bottom: SPACE_S })
                .onClick(() => {
                  if (this.historySelectMode) {
                    this.toggleHistoryPicked(h); // 多选态点击切换勾选
                  } else {
                    this.submit(h); // 点击历史即搜
                  }
                })
                .gesture(LongPressGesture().onAction(() => {
                  if (!this.historySelectMode) {
                    this.enterHistorySelect(h); // 长按进入多选（S-12 原版交互）
                  }
                }))
              }, (h: string) => 'hist_' + h)
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        if (this.hotWords.length > 0) {
          Column({ space: SPACE_S }) {
            SectionTitle({ title: '热门搜索' })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.hotWords, (w: string, idx: number) => {
                TagChip({
                  label: idx < 3 ? `${idx + 1} ${w}` : w,
                  selected: false,
                  onChipClick: (): void => {
                    this.keyword = w;
                    this.submit(w);
                  }
                })
                  .margin({ right: SPACE_S, bottom: SPACE_S })
              }, (w: string, idx: number) => 'hot_' + idx.toString() + '_' + w)
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        if (this.history.length === 0 && this.hotWords.length === 0) {
          EmptyView({
            message: '输入 jm350234 可直达本子\n搜索词会自动记录',
            showRetry: false
          })
        }
      }
      .width('100%')
      .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_M, bottom: SPACE_XL })
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .layoutWeight(1) // 评审 Step2：与多选底栏同列时占满剩余高度（原 height('100%') 会顶出容器）
  }

  @Builder
  private ResultBody() {
    if (this.loading && this.resultCount === 0) {
      Column() {
        SkeletonGrid({ columns: this.gridColumns(), rows: 3 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_M })
    } else if (this.errorMsg !== '' && this.resultCount === 0) {
      Column() {
        EmptyView({
          message: this.errorMsg,
          retryText: '重试',
          showRetry: true,
          onRetry: (): void => {
            this.retrySearch();
          }
        })
      }
      .width('100%')
      .height('100%')
    } else if (this.searched && this.resultCount === 0) {
      Column() {
        EmptyView({
          message: this.clientFilterActive()
            ? '没有符合筛选的结果，试试放宽筛选条件'
            : '没有找到相关作品，换个关键词试试吧',
          retryText: '重新搜索',
          showRetry: true,
          onRetry: (): void => {
            this.retrySearch();
          }
        })
      }
      .width('100%')
      .height('100%')
    } else {
      WaterFlow({ scroller: this.scroller }) {
        LazyForEach(this.source, (item: AlbumLite) => {
          FlowItem() {
            AlbumCard({
              item: item,
              onCardClick: (): void => {
                this.openAlbum(item);
              }
            })
          }
        }, (item: AlbumLite) => item.id)
      }
      .columnsTemplate(this.columnsTemplateStr())
      .columnsGap(SPACE_M)
      .rowsGap(14)
      .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_M, bottom: SPACE_S })
      .cachedCount(4)
      .width('100%')
      .height('100%')
    }
  }

  /** S-05 分页（PageBar 简化口径：上一页 / 页码 / 下一页） */
  @Builder
  private PageBarRow() {
    Row() {
      Text('上一页')
        .fontSize(FONT_BODY)
        .fontColor(this.page > 1 ? PRIMARY : TEXT_SUB)
        .opacity(this.page > 1 ? 1 : 0.4)
        .padding({ left: SPACE_L, right: SPACE_L, top: 8, bottom: 8 })
        .onClick(() => {
          this.goPage(this.page - 1);
        })
      Text(`第 ${this.page} / ${this.pageCount()} 页`)
        .fontSize(FONT_CAPTION)
        .fontColor(TEXT_SUB)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Text('下一页')
        .fontSize(FONT_BODY)
        .fontColor(this.hasNextPage() ? PRIMARY : TEXT_SUB)
        .opacity(this.hasNextPage() ? 1 : 0.4)
        .padding({ left: SPACE_L, right: SPACE_L, top: 8, bottom: 8 })
        .onClick(() => {
          this.goPage(this.page + 1);
        })
    }
    .width('100%')
    .height(46)
    .alignItems(VerticalAlign.Center)
  }

  /** 筛选抽屉（S-06 排序 / S-07 时间 / S-08 指定年月） */
  @Builder
  private FilterSheet() {
    Column({ space: SPACE_M }) {
      Text('筛选')
        .fontSize(FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)

      Scroll() {
        Column({ space: 2 }) {
          Text('排序')
            .fontSize(FONT_CAPTION)
            .fontColor(PRIMARY)
            .width('100%')
          ForEach(SEARCH_ORDER_OPTIONS, (opt: ChipOption) => {
            OptionRow({
              label: opt.label,
              selected: this.order === opt.code,
              onTap: (): void => {
                this.applyOrder(opt.code);
              }
            })
          }, (opt: ChipOption) => 'so_' + opt.code)

          Text('时间')
            .fontSize(FONT_CAPTION)
            .fontColor(PRIMARY)
            .width('100%')
            .margin({ top: SPACE_M })
          ForEach(TIME_OPTIONS, (opt: ChipOption) => {
            OptionRow({
              label: opt.label,
              selected: this.timeRange === opt.code && this.yearSel === '',
              onTap: (): void => {
                this.applyTime(opt.code);
              }
            })
          }, (opt: ChipOption) => 'st_' + opt.code)

          Text('指定年月（上架时间）')
            .fontSize(FONT_CAPTION)
            .fontColor(PRIMARY)
            .width('100%')
            .margin({ top: SPACE_M })
          Row({ space: SPACE_M }) {
            TextPicker({ range: this.yearOptions, selected: this.pickYearIdx })
              .layoutWeight(1)
              .height(110)
              .onChange((_value: string | string[], index: number | number[]) => {
                const idx: number = Number(index);
                if (!Number.isNaN(idx)) {
                  this.pickYearIdx = idx;
                  if (idx === 0) {
                    this.pickMonthIdx = 0;
                  }
                }
              })
            TextPicker({ range: this.monthOptions, selected: this.pickMonthIdx })
              .layoutWeight(1)
              .height(110)
              .enabled(this.pickYearIdx > 0)
              .onChange((_value: string | string[], index: number | number[]) => {
                const idx: number = Number(index);
                if (!Number.isNaN(idx)) {
                  this.pickMonthIdx = idx;
                }
              })
          }
          .width('100%')

          Text(`当前：${this.yearSel === '' ? '不限' : this.yearSel}-${this.monthSel === '' ? '全年' : this.monthSel}（将与排序等条件同时生效）`)
            .fontSize(11)
            .fontColor(TEXT_SUB)
            .width('100%')

          Row({ space: SPACE_M }) {
            Text('清除年月')
              .fontSize(FONT_BODY)
              .fontColor(TEXT_SUB)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 9, bottom: 9 })
              .backgroundColor(CHIP_BG)
              .borderRadius(CHIP_R)
              .onClick(() => {
                this.clearDate();
              })
            Text('应用年月')
              .fontSize(FONT_BODY)
              .fontColor(Color.White)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 9, bottom: 9 })
              .backgroundColor(PRIMARY)
              .borderRadius(CHIP_R)
              .onClick(() => {
                this.applyDate();
              })
          }
          .width('100%')

          // ── S-09 语言多选 + 全彩开关（客户端过滤）──
          Text('语言（客户端筛选，可多选）')
            .fontSize(FONT_CAPTION)
            .fontColor(PRIMARY)
            .width('100%')
            .margin({ top: SPACE_M })
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(LANG_FILTER_OPTIONS, (opt: ChipOption) => {
              TagChip({
                label: opt.label,
                selected: this.filterLangs.indexOf(opt.code) >= 0,
                onChipClick: (): void => {
                  this.toggleLang(opt.code);
                }
              })
                .margin({ right: SPACE_S, bottom: SPACE_S })
            }, (opt: ChipOption) => 'lang_' + opt.code)
            TagChip({
              label: '仅全彩',
              selected: this.fullColorOnly,
              onChipClick: (): void => {
                this.toggleFullColor();
              }
            })
              .margin({ right: SPACE_S, bottom: SPACE_S })
          }
          .width('100%')
          Text('语言/全彩按标题·作者·分类关键词启发式判定；筛选后自动连扫补足结果（每次最多 8 页）')
            .fontSize(11)
            .fontColor(TEXT_SUB)
            .width('100%')

          // ── S-10 自定义筛选词（添加 ≤16 字符/查重/勾选/删除/持久化）──
          Text('自定义筛选词')
            .fontSize(FONT_CAPTION)
            .fontColor(PRIMARY)
            .width('100%')
            .margin({ top: SPACE_M })
          Row({ space: SPACE_S }) {
            TextInput({ text: this.wordInput, placeholder: '添加筛选词（≤16 字符）' })
              .layoutWeight(1)
              .height(38)
              .fontSize(FONT_BODY)
              .fontColor(TEXT_MAIN)
              .backgroundColor(CHIP_BG)
              .borderRadius(CHIP_R)
              .padding({ left: SPACE_M, right: SPACE_M })
              .onChange((v: string) => {
                this.wordInput = v;
                this.wordError = '';
              })
              .onSubmit(() => {
                this.addFilterWord();
              })
            Text('添加')
              .fontSize(FONT_BODY)
              .fontColor(Color.White)
              .padding({ left: 14, right: 14, top: 9, bottom: 9 })
              .backgroundColor(PRIMARY)
              .borderRadius(CHIP_R)
              .onClick(() => {
                this.addFilterWord();
              })
          }
          .width('100%')
          if (this.wordError !== '') {
            Text(this.wordError)
              .fontSize(11)
              .fontColor(PRIMARY)
              .width('100%')
          }
          ForEach(this.filterWords, (w: FilterWord) => {
            Row({ space: SPACE_S }) {
              Checkbox()
                .select(w.enabled)
                .selectedColor(PRIMARY)
                .onChange((_v: boolean) => {
                  this.toggleFilterWord(w.text);
                })
              Text(w.text)
                .fontSize(FONT_BODY)
                .fontColor(w.enabled ? TEXT_MAIN : TEXT_SUB)
                .maxLines(1)
                .layoutWeight(1)
              Text('✕')
                .fontSize(FONT_BODY)
                .fontColor(TEXT_SUB)
                .padding({ left: SPACE_S, right: SPACE_S })
                .onClick(() => {
                  this.removeFilterWord(w.text);
                })
            }
            .width('100%')
            .padding({ top: 6, bottom: 6 })
          }, (w: FilterWord) => 'fw_' + w.text)
          if (this.filterWords.length === 0) {
            Text('暂无自定义筛选词；勾选的词命中标题/作者/分类即保留（多个词任一命中即可）')
              .fontSize(11)
              .fontColor(TEXT_SUB)
              .width('100%')
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Text('完成')
        .fontSize(FONT_BODY)
        .fontColor(Color.White)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 11, bottom: 11 })
        .backgroundColor(ACCENT)
        .borderRadius(CHIP_R)
        .margin({ bottom: SPACE_L })
        .onClick(() => {
          this.filterSheet = false;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CARD)
    .padding({ left: SPACE_L, right: SPACE_L, top: SPACE_L })
  }

  build() {
    NavDestination() {
      Column() {
        this.SearchBar()
        if (matchAlbumId(this.keyword) !== '') {
          this.DirectButton()
        }
        if (this.searched) {
          this.StatusRow()
        }
        if (this.searched || this.loading) {
          this.ResultBody()
        } else {
          // 评审 Step2：建议区 = 剪贴板直达横幅（固定顶部）+ 建议 Scroll + 多选底栏（固定底部）
          Column() {
            if (this.clipboardAid !== '') {
              this.ClipboardBanner()
            }
            this.SuggestBody()
            if (this.historySelectMode) {
              this.HistorySelectBar()
            }
          }
          .width('100%')
          .layoutWeight(1)
        }
        if (this.searched && this.resultCount > 0) {
          this.PageBarRow()
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(BG)
    .bindSheet($$this.filterSheet, this.FilterSheet(), {
      height: 560,
      dragBar: true,
      onDisappear: (): void => {
        this.filterSheet = false;
      }
    })
    .onReady((ctx: NavDestinationContext) => {
      this.handleReady(ctx);
    })
  }
}
