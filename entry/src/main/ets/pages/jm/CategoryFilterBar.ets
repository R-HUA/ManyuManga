import { IMMERSIVE_REGULAR_MATERIAL, IMMERSIVE_SHEET_MATERIAL } from '../../common/ImmersiveMaterials';
import { IconCircleButton } from '../../common/Components';
import { PRIMARY, TEXT_MAIN, SUB_CARD } from '../../common/Theme';
import { CategoryItem } from '../../models/Models';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

export const CATEGORY_BAR_HEIGHT: number = 48;

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
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  selectAll: () => void = (): void => {};
  selectCategory: (cat: CategoryItem) => void = (): void => {};
  selectCustom: (term: string) => void = (): void => {};
  selectOrder: (code: string) => void = (): void => {};
  openAddDialog: () => void = (): void => {};
  confirmDeleteCustom: (term: string) => void = (): void => {};
  private readonly orders: Array<string> = ['mr', 'mv_t', 'mv_w', 'mv_m', 'mv'];
  private readonly orderLabels: Array<string> = ['最新', '日榜', '周榜', '月榜', '总榜'];

  private categoryOptions(): Array<SelectOption> {
    const options: Array<SelectOption> = [{ value: '全部分类' }];
    for (const cat of this.categories) { options.push({ value: cat.name }); }
    for (const term of this.customCats) { options.push({ value: term }); }
    return options;
  }

  private categoryIndex(): number {
    if (this.selectedCatId === '') { return 0; }
    const index: number = this.categories.findIndex((cat: CategoryItem): boolean => cat.id === this.selectedCatId);
    return index >= 0 ? index + 1 : this.categories.length + this.customCats.indexOf(this.selectedCatName) + 1;
  }

  private choose(index: number): void {
    if (index === 0) { this.selectAll(); }
    else if (index <= this.categories.length) { this.selectCategory(this.categories[index - 1]); }
    else { this.selectCustom(this.customCats[index - this.categories.length - 1]); }
  }

  @Builder
  private Filters() {
    Column({ space: 20 }) {
      Text('筛选').fontSize(20).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN).width('100%')
      Select(this.categoryOptions()).selected(this.categoryIndex()).value(this.selectedCatName || '全部分类')
        .systemMaterial(IMMERSIVE_REGULAR_MATERIAL).onSelect((index: number): void => this.choose(index))
      Select(this.orderLabels.map((label: string): SelectOption => { return { value: label }; }))
        .selected(this.orders.indexOf(this.order)).value(this.orderLabels[this.orders.indexOf(this.order)])
        .systemMaterial(IMMERSIVE_REGULAR_MATERIAL).onSelect((index: number): void => this.selectOrder(this.orders[index]))
      Row() {
        Text('自定义题材').fontSize(16).fontColor(TEXT_MAIN).layoutWeight(1)
        Button('添加', { buttonStyle: ButtonStyleMode.NORMAL }).fontColor(PRIMARY).backgroundColor(SUB_CARD)
          .onClick(() => { this.catDrawerVisible = false; this.openAddDialog(); })
      }.width('100%')
      List({ space: 8 }) {
        ForEach(this.customCats, (term: string) => {
          ListItem() {
            Row() {
              Button(term, { buttonStyle: ButtonStyleMode.NORMAL }).fontColor(TEXT_MAIN).backgroundColor(Color.Transparent).layoutWeight(1)
                .onClick(() => { this.selectCustom(term); })
              IconCircleButton({ glyph: $r('sys.symbol.trash'), onTap: (): void => { this.confirmDeleteCustom(term); } })
            }.width('100%')
          }
        }, (term: string) => term)
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 20, bottom: 20 + this.bottomInset }).alignItems(HorizontalAlign.Start)
  }

  build() {
    Row({ space: 8 }) {
      Select(this.categoryOptions()).selected(this.categoryIndex()).value(this.selectedCatName || '全部分类')
        .systemMaterial(IMMERSIVE_REGULAR_MATERIAL).layoutWeight(1)
        .onSelect((index: number): void => this.choose(index))
      Select(this.orderLabels.map((label: string): SelectOption => { return { value: label }; }))
        .selected(this.orders.indexOf(this.order)).value(this.orderLabels[this.orders.indexOf(this.order)])
        .systemMaterial(IMMERSIVE_REGULAR_MATERIAL).onSelect((index: number): void => this.selectOrder(this.orders[index]))
      IconCircleButton({ glyph: $r('sys.symbol.slider_horizontal_2'), onTap: (): void => { this.catDrawerVisible = true; } })
    }.width('100%').height(CATEGORY_BAR_HEIGHT).padding({ left: 16, right: 16 })
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
    .bindSheet($$this.catDrawerVisible, this.Filters(), { height: SheetSize.MEDIUM, dragBar: true, systemMaterial: IMMERSIVE_SHEET_MATERIAL })
  }
}
