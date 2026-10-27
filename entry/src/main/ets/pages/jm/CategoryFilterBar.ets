/**
 * entry/src/main/ets/pages/jm/CategoryFilterBar.ets
 * 修复截图 3 (202131) 与半模态右上角碰撞：
 * 1. 移除浑浊深灰底条，统一使用 BAR_LIGHT 毛玻璃与 0.5vp 底部分割线
 * 2. 将 [分类胶囊轨] + [排序紧凑胶囊 Select (30vp)] + [全部分类圆钮 (32vp)] 视觉高度与材质拉齐
 * 3. 全部分类半模态显式开启 showClose: false 并内建关闭圆钮，杜绝与「添加自定义」按钮重叠
 */
import { formatCount } from '../../common/ComicBadge';
import { IMMERSIVE_REGULAR_MATERIAL, IMMERSIVE_SHEET_MATERIAL } from '../../common/ImmersiveMaterials';
import {
  BAR_LIGHT,
  SUB_CARD,
  CHIP_R,
  DIVIDER,
  FONT_CAPTION,
  PRIMARY,
  PRIMARY_SOFT,
  SPACE_L,
  SPACE_S,
  TEXT_MAIN,
  TEXT_SUB
} from '../../common/Theme';
import { IconCircleButton, TagChip } from '../../common/Components';
import { ROUTE_SEARCH, MangaRouteParams } from '../../common/Route';
import { CategoryItem } from '../../models/Models';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

export const CATEGORY_BAR_HEIGHT: number = 86;

export class ChipOption {
  code: string;
  label: string;

  constructor(code: string, label: string) {
    this.code = code;
    this.label = label;
  }
}

const ORDER_OPTIONS: Array<ChipOption> = [
  new ChipOption('mr', '最新上架'),
  new ChipOption('mv_t', '日榜热门'),
  new ChipOption('mv_w', '周榜热门'),
  new ChipOption('mv_m', '月榜热门'),
  new ChipOption('mv', '总榜殿堂')
];

@Component
export struct CategoryFilterBar {
  @Prop sourceIdValue: string = '';
  @Link selectedCatId: string;
  @Link selectedCatName: string;
  @Link categories: Array<CategoryItem>;
  @Link customCats: Array<string>;
  @Link catDrawerVisible: boolean;
  @Link headerHeight: number;
  @Link order: string;
  @Prop embeddedInShell: boolean = false;
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 38;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 16;
  @Consume('navPathStack') navPathStack: NavPathStack;

  selectAll: () => void = (): void => {};
  selectCategory: (cat: CategoryItem) => void = (_cat: CategoryItem): void => {};
  selectCustom: (term: string) => void = (_term: string): void => {};
  selectOrder: (code: string) => void = (_code: string): void => {};
  openAddDialog: () => void = (): void => {};
  confirmDeleteCustom: (term: string) => void = (_term: string): void => {};

  build() {
    Column({ space: 8 }) {
      // 第 1 行：单行横滑分类胶囊轨 + 右侧统一封装的 32vp IconCircleButton
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
                  if (this.selectCustom) {
                    this.selectCustom(term);
                  } else {
                    const param: MangaRouteParams = { query: term };
                    this.navPathStack.pushPathByName(ROUTE_SEARCH, param);
                  }
                }
              })
            }, (term: string) => 'ccat_' + term)
          }
          .padding({ right: 4 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)

        IconCircleButton({
          glyph: $r('sys.symbol.square_grid_2x2'),
          btnSize: 32,
          iconSize: 16,
          active: this.selectedCatId !== '',
          onTap: (): void => {
            this.catDrawerVisible = true;
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 第 2 行：左侧当前题材面包屑 + 右侧 30vp 紧凑排序胶囊 Select
      Row({ space: 8 }) {
        Row({ space: 6 }) {
          Circle({ width: 6, height: 6 })
            .fill(PRIMARY)
          Text(this.selectedCatId === '' ? '全部题材' : this.selectedCatName)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_MAIN)
          Text('· 点击右侧切换排序')
            .fontSize(11)
            .fontColor(TEXT_SUB)
        }
        .alignItems(VerticalAlign.Center)
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
          .font({ size: 12, weight: FontWeight.Bold })
          .fontColor(PRIMARY)
          .selectedOptionFont({ size: 14, weight: FontWeight.Bold })
          .selectedOptionFontColor(PRIMARY)
          .optionFont({ size: 14 })
          .height(30)
          .padding({ left: 10, right: 6 })
          .backgroundColor(PRIMARY_SOFT)
          .borderRadius(15)
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
    .border({ width: { bottom: 0.5 }, color: DIVIDER })
    .bindSheet($$this.catDrawerVisible, this.CategoryDrawer(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: false,
      systemMaterial: IMMERSIVE_SHEET_MATERIAL
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const h: number = Number(newArea.height);
      if (!Number.isNaN(h) && h > 0) {
        this.headerHeight = h;
      }
    })
  }

  @Builder
  private CategoryDrawer() {
    Column({ space: 14 }) {
      // 自绘顶栏：标题 + 添加自定义胶囊 + 关闭圆钮（showClose: false 杜绝重叠）
      Row({ space: 10 }) {
        Text('全部分类与题材')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)

        Text('+ 自定义标签')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY)
          .height(28)
          .padding({ left: 12, right: 12 })
          .borderRadius(14)
          .backgroundColor(PRIMARY_SOFT)
          .onClick(() => {
            this.catDrawerVisible = false;
            this.openAddDialog();
          })

        IconCircleButton({
          glyph: $r('sys.symbol.xmark'),
          btnSize: 32,
          iconSize: 16,
          onTap: (): void => {
            this.catDrawerVisible = false;
          }
        })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12 })
      .alignItems(VerticalAlign.Center)

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
                Text(`#${term}`)
                  .fontSize(FONT_CAPTION)
                  .fontColor(TEXT_MAIN)
                  .maxLines(1)
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(11)
                  .fontColor([TEXT_SUB])
                  .onClick(() => {
                    this.confirmDeleteCustom(term);
                  })
              }
              .padding({ left: 10, right: 8, top: 6, bottom: 6 })
              .backgroundColor(SUB_CARD)
              .borderRadius(CHIP_R)
              .margin({ right: SPACE_S, bottom: SPACE_S })
              .onClick(() => {
                this.catDrawerVisible = false;
                if (this.selectCustom) {
                  this.selectCustom(term);
                } else {
                  const param: MangaRouteParams = { query: term };
                  this.navPathStack.pushPathByName(ROUTE_SEARCH, param);
                }
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

  private orderIndex(): number {
    const codes: Array<string> = ['mr', 'mv_t', 'mv_w', 'mv_m', 'mv'];
    const idx: number = codes.indexOf(this.order);
    return idx >= 0 ? idx : 0;
  }

  private orderLabel(): string {
    for (const opt of ORDER_OPTIONS) {
      if (opt.code === this.order) {
        return opt.label;
      }
    }
    return '最新上架';
  }

  private chipLabel(cat: CategoryItem): string {
    if (cat.total !== '' && cat.total !== '0') {
      return `${cat.name} ${formatCount(cat.total)}`;
    }
    return cat.name;
  }
}
