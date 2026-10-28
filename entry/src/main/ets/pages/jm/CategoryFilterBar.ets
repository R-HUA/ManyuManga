import { formatCount } from '../../common/ComicBadge';
import { IMMERSIVE_SHEET_MATERIAL, EMPTY_MATERIAL } from '../../common/ImmersiveMaterials';
import { LengthMetrics } from '@kit.ArkUI';
import {
  BAR_LIGHT,
  DIVIDER,
  SUB_CARD,
  CHIP_R,
  FONT_CAPTION,
  PRIMARY,
  SPACE_L,
  SPACE_S,
  TEXT_MAIN,
  TEXT_SUB
} from '../../common/Theme';
import { TagChip } from '../../common/Components';
import { ROUTE_SEARCH, MangaRouteParams } from '../../common/Route';
import { CategoryItem } from '../../models/Models';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

export const CATEGORY_BAR_HEIGHT: number = 48;

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
  @Prop selectedCatId: string = '';
  @Prop selectedCatName: string = '';
  @Prop categories: Array<CategoryItem> = [];
  @Prop customCats: Array<string> = [];
  @Prop catDrawerVisible: boolean = false;
  @Prop order: string = 'mr';
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
    Row({ space: 6 }) {
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
              selected: this.selectedCatId === `custom:${term}`,
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
      .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(20) })
      .layoutWeight(1)

      Divider()
        .vertical(true)
        .height(14)
        .strokeWidth(0.5)
        .color(DIVIDER)
        .margin({ left: 4, right: 2 })

      Select([
        { value: '最新上架' },
        { value: '日榜热门' },
        { value: '周榜热门' },
        { value: '月榜热门' },
        { value: '总榜殿堂' }
      ])
        .selected(this.orderIndex())
        .value(this.orderLabel())
        .controlSize(ControlSize.SMALL)
        .font({ size: 13, weight: FontWeight.Normal })
        .fontColor(TEXT_SUB)
        .selectedOptionFont({ size: 13, weight: FontWeight.Medium })
        .selectedOptionFontColor(PRIMARY)
        .optionFont({ size: 13, weight: FontWeight.Normal })
        .optionFontColor(TEXT_MAIN)
        .height(32)
        .backgroundColor(Color.Transparent)
        .borderWidth(0)
        .borderColor(Color.Transparent)
        .systemMaterial(EMPTY_MATERIAL)
        .onSelect((index: number) => {
          const codes: Array<string> = ['mr', 'mv_t', 'mv_w', 'mv_m', 'mv'];
          this.selectOrder(codes[index] ?? 'mr');
        })
    }
    .width('100%')
    .height(CATEGORY_BAR_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .padding({
      left: SPACE_L,
      right: SPACE_L,
      top: 4,
      bottom: 4
    })
    .backgroundColor(Color.Transparent)
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
