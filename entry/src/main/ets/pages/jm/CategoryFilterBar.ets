import { formatCount } from '../../common/ComicBadge';
import { IMMERSIVE_REGULAR_MATERIAL, IMMERSIVE_SHEET_MATERIAL } from '../../common/ImmersiveMaterials';
import { CARD, CHIP_BG, CHIP_R, DIVIDER, FONT_CAPTION, PRIMARY, PRIMARY_SOFT, SPACE_L, SPACE_S, SUB_CARD, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
import { TagChip } from '../../common/Components';
import { ROUTE_SEARCH } from '../../common/Route';
import { CategoryItem } from '../../models/Models';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

export const CATEGORY_BAR_HEIGHT: number = 48;

class SearchRouteParam { query: string = ''; sourceId: string = ''; }
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

@Component
export struct CategoryFilterBar {
  @Prop sourceIdValue: string = '';
  @Link selectedCatId: string;
  selectAll: () => void = (): void => {};
  @Link categories: Array<CategoryItem>;
  selectCategory: (cat: CategoryItem) => void = (_cat: CategoryItem): void => {};
  @Link customCats: Array<string>;
  @Consume('navPathStack') navPathStack: NavPathStack;
  @Link catDrawerVisible: boolean;
  @Link selectedCatName: string;
  selectOrder: (code: string) => void = (_code: string): void => {};
  @Prop embeddedInShell: boolean = false;
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 38;
  @Link headerHeight: number;
  openAddDialog: () => void = (): void => {};
  confirmDeleteCustom: (term: string) => void = (_term: string): void => {};
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 16;
  @Link order: string;

  private orderIndex(): number {
    const codes: Array<string> = ['mr', 'mv_t', 'mv_w', 'mv_m', 'mv'];
    const idx: number = codes.indexOf(this.order);
    return idx >= 0 ? idx : 0;
  }

  private orderShortLabel(): string {
    const map: Record<string, string> = {
      'mr': '最新',
      'mv_t': '日榜',
      'mv_w': '周榜',
      'mv_m': '月榜',
      'mv': '总榜'
    };
    return map[this.order] ?? '最新';
  }

  private chipLabel(cat: CategoryItem): string {
    if (cat.total !== '' && cat.total !== '0') {
      return `${cat.name} ${formatCount(cat.total)}`;
    }
    return cat.name;
  }

  build() {
    Row({ space: 8 }) {
      // 1. 左侧：紧凑排序选择器
      Select([
        { value: '最新上架' },
        { value: '日榜热门' },
        { value: '周榜热门' },
        { value: '月榜热门' },
        { value: '总榜殿堂' }
      ])
        .selected(this.orderIndex())
        .value(this.orderShortLabel())
        .font({ size: 12, weight: FontWeight.Bold })
        .fontColor(PRIMARY)
        .selectedOptionFont({ size: 14, weight: FontWeight.Bold })
        .optionFont({ size: 14 })
        .height(30)
        .backgroundColor(PRIMARY_SOFT)
        .borderRadius(15)
        .menuSystemMaterial(IMMERSIVE_REGULAR_MATERIAL)
        .onSelect((index: number) => {
          const codes: Array<string> = ['mr', 'mv_t', 'mv_w', 'mv_m', 'mv'];
          this.selectOrder(codes[index] ?? 'mr');
        })

      Divider()
        .vertical(true)
        .height(16)
        .color(DIVIDER)

      // 2. 中间：单行横滑分类胶囊轨
      Scroll() {
        Row({ space: 6 }) {
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
        }
        .justifyContent(FlexAlign.Start)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .layoutWeight(1)

      // 3. 右侧：展开全部分类抽屉按钮
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        SymbolGlyph($r('sys.symbol.square_grid_2x2'))
          .fontSize(16)
          .fontColor([TEXT_MAIN])
      }
      .width(30)
      .height(30)
      .backgroundColor(SUB_CARD)
      .onClick(() => {
        this.catDrawerVisible = true;
      })
    }
    .width('100%')
    .height(CATEGORY_BAR_HEIGHT + (this.embeddedInShell ? 0 : this.topInset))
    .padding({
      left: SPACE_L,
      right: SPACE_L,
      top: this.embeddedInShell ? 0 : this.topInset
    })
    .alignItems(VerticalAlign.Center)
    .systemMaterial(IMMERSIVE_REGULAR_MATERIAL)
    .border({ width: { bottom: 0.5 }, color: DIVIDER })
    .bindSheet($$this.catDrawerVisible, this.CategoryDrawer(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
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
            this.openAddDialog();
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
                param.sourceId = this.sourceIdValue;
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
}
