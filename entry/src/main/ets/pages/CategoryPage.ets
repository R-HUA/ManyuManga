import { CategoryFilterBar } from './jm/CategoryFilterBar';
import { BasicDataSource } from '../common/DataSource';
import { formatCount, langBadgeFor } from '../common/ComicBadge';
import { AlbumCard } from './jm/AlbumCard';
import { AddCatDialog } from './jm/AddCatDialog';
import { FONT_CAPTION, PRIMARY, SPACE_L, SPACE_M, SPACE_S, TAB_BAR_HEIGHT, TEXT_SUB } from '../common/Theme';
import { EmptyView, SkeletonGrid } from '../common/Components';
import { ROUTE_ALBUM } from '../common/Route';
import { AlbumLite, CategoryItem, errorMessage } from '../models/Models';
import { sourceApi as jmApi } from '../data/SourceApi';
import { blockTagsStore, customCatStore } from '../data/Stores';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY, CURRENT_BREAKPOINT_KEY } from '../entryability/EntryAbility';
export { formatCount, langBadgeFor } from '../common/ComicBadge';
export { AlbumCard } from './jm/AlbumCard';
/**
 * 分类页面
 */

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

// ───────────────────────── WaterFlow 数据源（LazyForEach + IDataSource） ─────────────────────────

/** 专辑列表数据源：供 WaterFlow LazyForEach 懒加载（） */
export class AlbumSource extends BasicDataSource<AlbumLite> {
  setItems(items: Array<AlbumLite>): void { this.setList(items); }
  count(): number { return this.totalCount(); }
}

// ───────────────────────── 瀑布流封面卡（3:4 封面 + 徽章 + 2 个高频标签胶囊） ─────────────────────────

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

  private openAddDialog(): void { this.addDialogCtrl.open(); }

  @Builder
  private FilterHeader() {
    CategoryFilterBar({
      selectedCatId: this.$selectedCatId,
      selectAll: (): void => this.selectAll(),
      categories: this.$categories,
      selectCategory: (cat: CategoryItem): void => this.selectCategory(cat),
      customCats: this.$customCats,
      catDrawerVisible: this.$catDrawerVisible,
      selectedCatName: this.$selectedCatName,
      selectOrder: (code: string): void => this.selectOrder(code),
      embeddedInShell: this.embeddedInShell,
      headerHeight: this.$headerHeight,
      openAddDialog: (): void => this.openAddDialog(),
      confirmDeleteCustom: (term: string): void => this.confirmDeleteCustom(term),
      order: this.$order
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

  }
}
