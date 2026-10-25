/**
 * 分类页面
 */
import { uiMaterial } from '@kit.ArkUI';
import { BAR_LIGHT, CARD, CHIP_BG, CHIP_R, COVER_ASPECT_RATIO, COVER_R, FONT_BADGE, FONT_BODY,
  FONT_CAPTION, FONT_TITLE, PRIMARY, SPACE_L, SPACE_M, SPACE_S, TAB_BAR_HEIGHT, TEXT_MAIN, TEXT_SUB } from '../common/Theme';
import { EmptyView, SkeletonGrid, TagChip } from '../common/Components';
import { ROUTE_ALBUM, ROUTE_SEARCH } from '../common/Route';
import { AlbumLite, CategoryItem, errorMessage } from '../models/Models';
import { sourceApi as jmApi } from '../data/SourceApi';
import { blockTagsStore, customCatStore } from '../data/Stores';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY, CURRENT_BREAKPOINT_KEY } from '../entryability/EntryAbility';

/* ===== 路由参数（ 契约表；ArkTS 严格模式禁对象字面量传参，用具名 class） ===== */

class AlbumRouteParam {
  aid: string = '';
}

class SearchRouteParam {
  query: string = '';
}

// ───────────────────────── 页间共享的小工具（SearchPage 复用） ─────────────────────────

/** 筛选选项 */
export class ChipOption {
  code: string;
  label: string;

  constructor(code: string, label: string) {
    this.code = code;
    this.label = label;
  }
}

/** 排序选项 */
const ORDER_OPTIONS: Array<ChipOption> = [
  new ChipOption('mv_t', '日榜'),
  new ChipOption('mv_w', '周榜'),
  new ChipOption('mv_m', '月榜'),
  new ChipOption('mv', '总榜'),
  new ChipOption('mr', '最新')
];

/** 数字本地化：10591 → 1.1万（；小于 1 万原样返回） */
export function formatCount(raw: string): string {
  if (raw === '') {
    return raw;
  }
  const n: number = Number(raw);
  if (Number.isNaN(n)) {
    return raw;
  }
  if (n >= 10000) {
    const w: number = Math.round(n / 1000) / 10;
    return `${w}万`;
  }
  return raw;
}

const ZH_WORDS: Array<string> = ['中文', '漢化', '汉化', '中字', '中国', 'chinese', '翻譯', '翻译'];
const JA_WORDS: Array<string> = ['日本語', '日語', '日文', 'japanese', '生肉', '日版'];
const KO_WORDS: Array<string> = ['한국', '한글', '韓文', '韩文', 'korean'];
const FC_WORDS: Array<string> = ['全彩', 'フルカラー', 'fullcolor', 'full color', '彩漫', '彩色'];

function containsAny(hay: string, words: Array<string>): boolean {
  for (const w of words) {
    if (hay.indexOf(w) >= 0) {
      return true;
    }
  }
  return false;
}

/**
 * 语言/全彩徽章启发式。
 */
export function langBadgeFor(item: AlbumLite): string {
  const hay: string = `${item.title} ${item.author} ${item.category} ${item.categorySub}`.toLowerCase();
  if (containsAny(hay, ZH_WORDS)) {
    return '中字';
  }
  if (containsAny(hay, JA_WORDS)) {
    return '日漫';
  }
  if (containsAny(hay, KO_WORDS)) {
    return '韩漫';
  }
  let hangul: number = 0;
  let kana: number = 0;
  let han: number = 0;
  for (let i: number = 0; i < item.title.length; i++) {
    const c: number = item.title.charCodeAt(i);
    if ((c >= 0xAC00 && c <= 0xD7AF) || (c >= 0x3130 && c <= 0x318F)) {
      hangul++;
    } else if ((c >= 0x3040 && c <= 0x30FF) || (c >= 0x31F0 && c <= 0x31FF)) {
      kana++;
    } else if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF)) {
      han++;
    }
  }
  if (hangul > 0) {
    return '韩漫';
  }
  if (kana > 0) {
    return '日漫';
  }
  if (containsAny(hay, FC_WORDS)) {
    return '全彩';
  }
  if (han > 0) {
    return '中字';
  }
  return '';
}

/** 码点计数（≤16 字符校验用，等价 Kotlin codePointCount） */
function codePointCount(s: string): number {
  let n: number = 0;
  for (let i: number = 0; i < s.length; i++) {
    const c: number = s.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
      const c2: number = s.charCodeAt(i + 1);
      if (c2 >= 0xDC00 && c <= 0xDFFF) {
        i++;
      }
    }
    n++;
  }
  return n;
}

// ───────────────────────── WaterFlow 数据源（LazyForEach + IDataSource） ─────────────────────────

/** 专辑列表数据源：供 WaterFlow LazyForEach 懒加载（） */
export class AlbumSource implements IDataSource {
  private items: Array<AlbumLite> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): AlbumLite {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener);
  }

  /** 整体替换（筛选/排序变更、搜索翻页） */
  setItems(list: Array<AlbumLite>): void {
    this.items = list.slice();
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }

  /** 追加一页（分类上拉加载更多） */
  appendItems(list: Array<AlbumLite>): void {
    if (list.length === 0) {
      return;
    }
    const at: number = this.items.length;
    this.items = this.items.concat(list);
    for (const l of this.listeners) {
      for (let i: number = at; i < this.items.length; i++) {
        l.onDataAdd(i);
      }
    }
  }

  count(): number {
    return this.items.length;
  }
}

// ───────────────────────── 瀑布流封面卡（3:4 封面 + 徽章 + 2 个高频标签胶囊） ─────────────────────────

/**
 * 卡片底部 2 个标签胶囊取真实列表字段 category / category_sub（数据源 JmApi.parseComic，
 * 不依赖已裁剪的标签级 enrich）；两者皆空时降级为作者行。
 */
@Component
export struct AlbumCard {
  @Prop item: AlbumLite = new AlbumLite();
  onCardClick: () => void = () => {};
  /** 封面图床轮换序号（评审 Step3：失败换备用图床，最多 3 次） */
  @State coverRetry: number = 0;

  /** retry>0 走 jmApi.albumThumbUrl(id, retry) 轮换域名；否则原 url（空 url 降级小图直链） */
  private coverSrc(): string {
    if (this.coverRetry > 0 && this.item.id !== '') {
      return jmApi.albumThumbUrl(this.item.id, this.coverRetry);
    }
    return this.item.coverUrl === '' ? jmApi.albumThumbUrl(this.item.id) : this.item.coverUrl;
  }

  private badge(): string {
    return langBadgeFor(this.item);
  }

  @Builder
  private Capsule(label: string) {
    Text(label)
      .fontSize(FONT_BADGE)
      .fontColor(TEXT_SUB)
      .maxLines(1)
      .padding({ left: 7, right: 7, top: 2, bottom: 2 })
      .backgroundColor(CHIP_BG)
      .borderRadius(CHIP_R)
  }

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(this.coverSrc())
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .backgroundColor(CHIP_BG)
          .onError(() => {
            if (this.coverRetry < 3 && this.item.id !== '') {
              this.coverRetry += 1;
            }
          })
        if (this.badge() !== '') {
          Text(this.badge())
            .fontSize(FONT_BADGE)
            .fontColor(Color.White)
            .maxLines(1)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor('rgba(14,17,26,0.78)')
            .borderRadius(9)
            .margin(6)
        }
      }
      .width('100%')
      .aspectRatio(COVER_ASPECT_RATIO)
      .borderRadius(COVER_R)
      .clip(true)
      .border({ width: 0.5, color: 'rgba(255,255,255,0.15)' })

      Text(this.item.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_MAIN)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (this.item.category !== '' || this.item.categorySub !== '') {
        Row({ space: 4 }) {
          if (this.item.category !== '') {
            this.Capsule(this.item.category)
          }
          if (this.item.categorySub !== '') {
            this.Capsule(this.item.categorySub)
          }
        }
        .width('100%')
      } else if (this.item.author !== '') {
        Text(this.item.author)
          .fontSize(11)
          .fontColor(TEXT_SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onCardClick();
    })
  }
}

// ───────────────────────── 自定义分类添加弹窗 ─────────────────────────

@CustomDialog
struct AddCatDialog {
  controller?: CustomDialogController;
  @State input: string = '';
  @State err: string = '';
  onAdded: () => void = () => {};

  private cpCount(): number {
    return codePointCount(this.input.trim());
  }

  private async doAdd(): Promise<void> {
    const err: string = await customCatStore.add(this.input);
    if (err === '') {
      this.onAdded();
      if (this.controller) {
        this.controller.close();
      }
    } else {
      this.err = err;
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('添加自定义分类 / tag')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
      TextInput({ text: this.input, placeholder: '名称 / 关键词' })
        .fontSize(FONT_BODY)
        .fontColor(TEXT_MAIN)
        .onChange((v: string) => {
          this.input = v;
          this.err = '';
        })
      Text(`${this.cpCount()} / 16 字符`)
        .fontSize(11)
        .fontColor(TEXT_SUB)
        .width('100%')
      if (this.err !== '') {
        Text(this.err)
          .fontSize(11)
          .fontColor(PRIMARY)
          .width('100%')
      }
      Row({ space: 12 }) {
        Text('取消')
          .fontSize(FONT_BODY)
          .fontColor(TEXT_SUB)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 9, bottom: 9 })
          .backgroundColor(CHIP_BG)
          .borderRadius(CHIP_R)
          .onClick(() => {
            if (this.controller) {
              this.controller.close();
            }
          })
        Text('添加')
          .fontSize(FONT_BODY)
          .fontColor(Color.White)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 9, bottom: 9 })
          .backgroundColor(PRIMARY)
          .borderRadius(CHIP_R)
          .onClick(() => {
            this.doAdd();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor(CARD)
  }
}

// ───────────────────────── 分类页 ─────────────────────────

/** 分类列表进程内缓存（契约缺口：Stores.ets 无分类持久化缓存，切 Tab/返回仍保留选中与列表） */
let cachedCategories: Array<CategoryItem> | null = null;

@Component
export struct CategoryPage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @Prop embeddedInShell: boolean = false;

  /* ── 安全区/断点契约（评审 Step2/Step4：EntryAbility 写入 AppStorage，页面 @StorageProp 消费）── */
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 38;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 16;
  @StorageProp(CURRENT_BREAKPOINT_KEY) bp: string = 'sm';
  /* ── 屏蔽词实时联动（评审 Step3）── */
  @StorageProp('blockTagsVersion') @Watch('onBlockTagsChanged') blockVer: number = 0;

  // 筛选状态
  @State selectedCatId: string = '';
  @State selectedCatName: string = '';
  @State selectedCatSlug: string = '';
  @State order: string = 'mr';
  @State expanded: boolean = true;
  @State catDrawerVisible: boolean = false;

  private orderIndex(): number {
    const codes: Array<string> = ['mr', 'mv_t', 'mv_w', 'mv_m', 'mv'];
    const idx: number = codes.indexOf(this.order);
    return idx >= 0 ? idx : 0;
  }

  // 分类列表
  @State categories: Array<CategoryItem> = [];
  @State customCats: Array<string> = [];
  @State catsLoading: boolean = true;
  @State catsError: string = '';

  // 列表四态
  @State firstLoading: boolean = true;
  @State firstError: string = '';
  @State emptyResult: boolean = false;
  @State loadingMore: boolean = false;
  @State moreError: boolean = false;
  @State finished: boolean = false;
  @State loadedCount: number = 0;
  @State headerHeight: number = 150;

  private source: AlbumSource = new AlbumSource();
  private scroller: Scroller = new Scroller();
  private page: number = 1;
  private requestSeq: number = 0;
  /** 未经屏蔽过滤的合并原始列表（评审 Step3：屏蔽词变更时重复过滤整体替换） */
  private rawItems: Array<AlbumLite> = [];
  /** 跨页去重已见 id 集（reload 时重置）：榜单接口翻页可能重复返回同一本子 */
  private pageSeenIds: Set<string> = new Set<string>();
  /** 连续整页都是已见 id 的次数；满 2 次才结束，避免一页重复就把后面的新书丢掉 */
  private dupPageStreak: number = 0;

  private addDialogCtrl: CustomDialogController = new CustomDialogController({
    builder: AddCatDialog({
      onAdded: (): void => {
        this.refreshCustomCats().catch((e: Error) => {
          console.info(`[CategoryPage] 自定义分类刷新失败: ${errorMessage(e)}`);
        });
      }
    })
  });

  aboutToAppear(): void {
    // 评审 Step2：首帧头部高度估算补上状态栏避让（onAreaChange 随后校准为实际值，缓解首帧重叠）
    this.headerHeight = (this.embeddedInShell ? 0 : this.topInset) + 150;
    jmApi.init().catch((e: Error) => {
      console.info(`[CategoryPage] jmApi.init: ${errorMessage(e)}`);
    });
    this.loadCategories();
    this.refreshCustomCats().catch((e: Error) => {
      console.info(`[CategoryPage] 自定义分类读取失败: ${errorMessage(e)}`);
    });
    this.reload();
  }

  // ── 数据 ──

  private async loadCategories(): Promise<void> {
    if (cachedCategories !== null) {
      this.categories = cachedCategories;
      this.catsLoading = false;
      return;
    }
    this.catsLoading = true;
    this.catsError = '';
    try {
      const list: Array<CategoryItem> = await jmApi.categories();
      cachedCategories = list;
      this.categories = list;
    } catch (e) {
      this.catsError = errorMessage(e as Error);
    } finally {
      this.catsLoading = false;
    }
  }

  private async refreshCustomCats(): Promise<void> {
    this.customCats = await customCatStore.getList();
  }

  private currentSlug(): string {
    if (this.selectedCatId === '') {
      return '0';
    }
    return this.selectedCatSlug === '' ? '0' : this.selectedCatSlug;
  }

  /** 屏蔽词过滤（字段匹配口径，简化） */
  private async filterBlocked(list: Array<AlbumLite>): Promise<Array<AlbumLite>> {
    const out: Array<AlbumLite> = [];
    for (const it of list) {
      const blocked: boolean =
        await blockTagsStore.isBlocked(it.title, it.author, it.category, it.categorySub);
      if (!blocked) {
        out.push(it);
      }
    }
    return out;
  }

  /** 评审 Step3：屏蔽词变更（Stores 递增 blockTagsVersion）→ 以原始合并列表重新过滤整体替换 */
  private onBlockTagsChanged(): void {
    this.refilterBlocked().catch((e: Error) => {
      console.info(`[CategoryPage] 屏蔽词重过滤失败: ${errorMessage(e)}`);
    });
  }

  private async refilterBlocked(): Promise<void> {
    if (this.rawItems.length === 0) {
      return;
    }
    const visible: Array<AlbumLite> = await this.filterBlocked(this.rawItems);
    this.source.setItems(visible);
    this.loadedCount = this.source.count();
    this.emptyResult = this.source.count() === 0;
  }

  private async reload(): Promise<void> {
    this.page = 1;
    this.finished = false;
    this.moreError = false;
    this.emptyResult = false;
    this.firstError = '';
    this.firstLoading = true;
    this.loadedCount = 0;
    this.rawItems = [];
    this.pageSeenIds = new Set<string>();
    this.dupPageStreak = 0;
    this.source.setItems([]);
    await this.fetchPage(1);
  }

  private async loadMore(): Promise<void> {
    if (this.firstLoading || this.loadingMore || this.finished || this.moreError) {
      return;
    }
    this.loadingMore = true;
    this.moreError = false;
    await this.fetchPage(this.page + 1);
  }

  private retryMore(): void {
    this.moreError = false;
    this.loadMore();
  }

  /**
   * 翻页去重：重复 id 会导致 LazyForEach key 冲突。
   * 只读 pageSeenIds，成功写入列表后才 rememberIds，过滤失败或请求作废不会把这页标成已见。
   */
  private dedupById(list: Array<AlbumLite>): Array<AlbumLite> {
    const local: Set<string> = new Set<string>();
    const out: Array<AlbumLite> = [];
    for (const it of list) {
      if (it.id !== '') {
        if (this.pageSeenIds.has(it.id) || local.has(it.id)) {
          continue;
        }
        local.add(it.id);
      }
      out.push(it);
    }
    return out;
  }

  private rememberIds(list: Array<AlbumLite>): void {
    for (const it of list) {
      if (it.id !== '') {
        this.pageSeenIds.add(it.id);
      }
    }
  }

  private async fetchPage(target: number): Promise<void> {
    const seq: number = ++this.requestSeq;
    const slug: string = this.currentSlug();
    try {
      const raw: Array<AlbumLite> = await jmApi.ranking(slug, this.order, target);
      if (seq !== this.requestSeq) {
        return;
      }
      const fresh: Array<AlbumLite> = this.dedupById(raw);
      const visible: Array<AlbumLite> = await this.filterBlocked(fresh);
      if (seq !== this.requestSeq) {
        return;
      }
      if (target === 1) {
        this.rememberIds(fresh);
        this.rawItems = fresh.slice();
        this.source.setItems(visible);
        this.emptyResult = fresh.length === 0;
        this.dupPageStreak = 0;
      } else if (raw.length === 0) {
        this.finished = true; // 接口返回空页：没有更多了（CategoryScreen.kt:276-278）
      } else if (fresh.length === 0) {
        // 整页都是已见 id：先翻过这一页再要下一页。连续两页如此才结束，避免重复页把后面的新书截掉
        this.dupPageStreak++;
        if (this.dupPageStreak >= 2) {
          this.finished = true;
        }
      } else {
        this.dupPageStreak = 0;
        this.rememberIds(fresh);
        this.rawItems = this.rawItems.concat(fresh);
        this.source.appendItems(visible);
      }
      if (fresh.length > 0 || (target > 1 && raw.length > 0 && !this.finished)) {
        this.page = target;
      }
      this.loadedCount = this.source.count();
    } catch (e) {
      if (seq !== this.requestSeq) {
        return;
      }
      const msg: string = errorMessage(e as Error);
      if (target === 1 && this.source.count() === 0) {
        this.firstError = msg;
      } else {
        this.moreError = true;
      }
    } finally {
      if (seq === this.requestSeq) {
        this.firstLoading = false;
        this.loadingMore = false;
      }
    }
  }

  // ── 筛选联动 ──

  private selectAll(): void {
    if (this.selectedCatId === '') {
      return;
    }
    this.selectedCatId = '';
    this.selectedCatName = '';
    this.selectedCatSlug = '';
    this.applyOrderDefaultAndReload();
  }

  private selectCategory(cat: CategoryItem): void {
    if (this.selectedCatId === cat.id) {
      return;
    }
    this.selectedCatId = cat.id;
    this.selectedCatName = cat.name;
    this.selectedCatSlug = cat.slug;
    this.applyOrderDefaultAndReload();
  }

  /** 联动：无 slug 分类（含全部）默认最新 mr，有 slug 默认总榜 mv（CategoryScreen.kt:240-242） */
  private applyOrderDefaultAndReload(): void {
    this.order = (this.selectedCatId === '' || this.selectedCatSlug === '') ? 'mr' : 'mv';
    this.reload();
  }

  private selectOrder(code: string): void {
    if (this.order === code) {
      return;
    }
    this.order = code;
    this.reload();
  }

  /** 当前排序的中文名（收起面板时的摘要胶囊用） */
  private orderLabel(): string {
    for (const opt of ORDER_OPTIONS) {
      if (opt.code === this.order) {
        return opt.label;
      }
    }
    return this.order;
  }

  /** 响应式网格列数（评审 Step4：sm 3 / md 4 / lg 5） */
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

  private chipLabel(cat: CategoryItem): string {
    if (cat.total !== '' && cat.total !== '0') {
      return `${cat.name} ${formatCount(cat.total)}`;
    }
    return cat.name;
  }

  private openAlbum(item: AlbumLite): void {
    const p: AlbumRouteParam = new AlbumRouteParam();
    p.aid = item.id;
    this.navPathStack.pushPathByName(ROUTE_ALBUM, p);
  }

  private confirmDeleteCustom(term: string): void {
    this.getUIContext().showAlertDialog({
      message: `删除自定义分类「${term}」？`,
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: PRIMARY,
        action: (): void => {
          customCatStore.remove(term).then((): void => {
            this.refreshCustomCats();
          }).catch((e: Error) => {
            console.info(`[CategoryPage] 自定义分类删除失败: ${errorMessage(e)}`);
          });
        }
      }
    });
  }

  // ── UI ──

  @Builder
  private CategoryDrawer() {
    Column({ space: 14 }) {
      Row() {
        Text('全部分类与题材')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)

        Button('添加自定义', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY)
          .backgroundColor(CHIP_BG)
          .height(30)
          .onClick(() => {
            this.catDrawerVisible = false;
            this.addDialogCtrl.open();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16 })

      Scroll() {
        Column({ space: 12 }) {
          Flex({ wrap: FlexWrap.Wrap }) {
            TagChip({
              label: '全部题材',
              selected: this.selectedCatId === '',
              onChipClick: (): void => {
                this.catDrawerVisible = false;
                this.selectAll();
              }
            })
              .margin({ right: SPACE_S, bottom: SPACE_S })

            ForEach(this.categories, (cat: CategoryItem) => {
              TagChip({
                label: this.chipLabel(cat),
                selected: this.selectedCatId === cat.id,
                onChipClick: (): void => {
                  this.catDrawerVisible = false;
                  this.selectCategory(cat);
                }
              })
                .margin({ right: SPACE_S, bottom: SPACE_S })
            }, (cat: CategoryItem) => 'drawer_cat_' + cat.id)

            ForEach(this.customCats, (term: string) => {
              Row({ space: 6 }) {
                Text(term)
                  .fontSize(FONT_CAPTION)
                  .fontColor(TEXT_SUB)
                  .maxLines(1)
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(11)
                  .fontColor([TEXT_SUB])
                  .onClick(() => {
                    this.confirmDeleteCustom(term);
                  })
              }
              .padding({ left: 10, right: 8, top: 5, bottom: 5 })
              .backgroundColor(CHIP_BG)
              .borderRadius(CHIP_R)
              .margin({ right: SPACE_S, bottom: SPACE_S })
              .onClick(() => {
                this.catDrawerVisible = false;
                const param: SearchRouteParam = new SearchRouteParam();
                param.query = term;
                this.navPathStack.pushPathByName(ROUTE_SEARCH, param);
              })
            }, (term: string) => 'drawer_ccat_' + term)
          }
          .width('100%')
        }
        .padding({ left: 20, right: 20, bottom: 28 + this.bottomInset })
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private FilterHeader() {
    Column({ space: 8 }) {
      // 第 1 行：单行横滑分类轨 + 右侧「全部分类」抽屉按钮
      Row({ space: 8 }) {
        Scroll() {
          Row({ space: 8 }) {
            TagChip({
              label: '全部',
              selected: this.selectedCatId === '',
              onChipClick: (): void => {
                this.selectAll();
              }
            })
            ForEach(this.categories, (cat: CategoryItem) => {
              TagChip({
                label: cat.name,
                selected: this.selectedCatId === cat.id,
                onChipClick: (): void => {
                  this.selectCategory(cat);
                }
              })
            }, (cat: CategoryItem) => 'cat_' + cat.id)
            ForEach(this.customCats, (term: string) => {
              TagChip({
                label: `#${term}`,
                selected: false,
                onChipClick: (): void => {
                  const param: SearchRouteParam = new SearchRouteParam();
                  param.query = term;
                  this.navPathStack.pushPathByName(ROUTE_SEARCH, param);
                }
              })
            }, (term: string) => 'ccat_' + term)
          }
          .padding({ right: 4 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)

        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(18)
            .fontColor([TEXT_MAIN])
        }
        .width(34)
        .height(34)
        .backgroundColor(CHIP_BG)
        .onClick(() => {
          this.catDrawerVisible = true;
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 第 2 行：左侧当前分类说明 + 右侧 Select 排序
      Row() {
        Text(`当前：${this.selectedCatId === '' ? '全部题材' : this.selectedCatName}`)
          .fontSize(12)
          .fontColor(TEXT_SUB)
          .layoutWeight(1)

        Select([
          { value: '最新上架' },
          { value: '日榜热门' },
          { value: '周榜热门' },
          { value: '月榜热门' },
          { value: '总榜殿堂' }
        ])
          .selected(this.orderIndex())
          .value(this.orderLabel())
          .font({ size: 13, weight: FontWeight.Medium })
          .fontColor(TEXT_MAIN)
          .selectedOptionFont({ size: 14, weight: FontWeight.Bold })
          .optionFont({ size: 14 })
          .height(32)
          .backgroundColor(CHIP_BG)
          .borderRadius(16)
          .menuSystemMaterial(new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR
          }))
          .onSelect((index: number) => {
            const codes: Array<string> = ['mr', 'mv_t', 'mv_w', 'mv_m', 'mv'];
            this.selectOrder(codes[index] ?? 'mr');
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({
      left: SPACE_L,
      right: SPACE_L,
      top: (this.embeddedInShell ? 0 : this.topInset) + 8,
      bottom: 8
    })
    .backgroundColor(BAR_LIGHT)
    .backgroundBlurStyle(BlurStyle.Regular)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const h: number = Number(newArea.height);
      if (!Number.isNaN(h) && h > 0) {
        this.headerHeight = h;
      }
    })
  }

  @Builder
  private Content() {
    if (this.firstLoading) {
      Column() {
        SkeletonGrid({ columns: this.gridColumns(), rows: 3 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: SPACE_L, right: SPACE_L, top: this.headerHeight + SPACE_S })
    } else if (this.firstError !== '') {
      Column() {
        EmptyView({
          message: this.firstError,
          retryText: '重试',
          showRetry: true,
          onRetry: (): void => {
            this.reload();
          }
        })
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.headerHeight })
    } else if (this.emptyResult) {
      Column() {
        EmptyView({
          message: '这个分类下暂时没有作品',
          showRetry: false
        })
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.headerHeight })
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
      .padding({ left: SPACE_L, right: SPACE_L, top: this.headerHeight + SPACE_S, bottom: SPACE_S })
      .cachedCount(4)
      .width('100%')
      .height('100%')
      .onReachEnd(() => {
        this.loadMore();
      })
    }
  }

  @Builder
  private Footer() {
    Row({ space: SPACE_S }) {
      if (this.loadingMore) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(PRIMARY)
        Text('加载中…')
          .fontSize(FONT_CAPTION)
          .fontColor(TEXT_SUB)
      } else if (this.moreError) {
        Text('加载失败 · 点此重试')
          .fontSize(FONT_CAPTION)
          .fontColor(PRIMARY)
          .onClick(() => {
            this.retryMore();
          })
      } else if (this.finished) {
        Text('— 没有更多了 —')
          .fontSize(FONT_CAPTION)
          .fontColor(TEXT_SUB)
      } else {
        Text(`已加载 ${this.loadedCount} 本 · 上拉加载更多`)
          .fontSize(FONT_CAPTION)
          .fontColor(TEXT_SUB)
      }
    }
    .width('100%')
    .height(40)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Top }) {
        this.Content()
        this.FilterHeader()
      }
      .layoutWeight(1)
      .width('100%')

      if (this.loadedCount > 0) {
        this.Footer()
      }
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: this.bp === 'sm' ? TAB_BAR_HEIGHT + this.bottomInset + SPACE_S : this.bottomInset + SPACE_S })
    .bindSheet($$this.catDrawerVisible, this.CategoryDrawer(), {
      height: '70%',
      dragBar: true,
      backgroundColor: CARD,
      systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK })
    })
  }
}
