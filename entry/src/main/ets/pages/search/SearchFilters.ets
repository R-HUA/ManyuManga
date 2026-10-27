import { SourceKind } from '../../data/Sources';
import { SourceSearchOptions } from '../../data/source/SourceContracts';
import { EhSearchFilter } from '../../data/eh/EhSearchFilter';
import { EhFilterSheet } from '../eh/EhFilterSheet';
import { IMMERSIVE_REGULAR_MATERIAL, IMMERSIVE_SHEET_MATERIAL } from '../../common/ImmersiveMaterials';
import { PRIMARY, SUB_CARD } from '../../common/Theme';

@Component
export struct SearchFilters {
  @Prop kind: SourceKind = 'jm';
  @Prop options: SourceSearchOptions = new SourceSearchOptions();
  onApply: (options: SourceSearchOptions) => void = (_options: SourceSearchOptions): void => {};
  @State private sheet: boolean = false;
  private readonly orders: Array<string> = ['mr', 'mv', 'mp', 'tf'];
  private readonly orderLabels: Array<string> = ['最新', '最多观看', '最多图片', '最多喜欢'];
  private readonly times: Array<string> = ['a', 't', 'w', 'm'];
  private readonly timeLabels: Array<string> = ['全部时间', '今天', '本周', '本月'];

  @Builder
  private FilterSheet() {
    EhFilterSheet({ filter: this.options.eh, apply: (filter: EhSearchFilter): void => {
      const next: SourceSearchOptions = this.options.copy();
      next.eh.copyFrom(filter);
      this.onApply(next);
    }, close: (): void => { this.sheet = false; } })
  }

  build() {
    Row({ space: 8 }) {
      if (this.kind === 'jm') {
        Select(this.orderLabels.map((value: string): SelectOption => { return { value: value }; }))
          .selected(this.orders.indexOf(this.options.jm.order)).value(this.orderLabels[this.orders.indexOf(this.options.jm.order)])
          .systemMaterial(IMMERSIVE_REGULAR_MATERIAL)
          .onSelect((index: number): void => {
            const next: SourceSearchOptions = this.options.copy();
            next.jm.order = this.orders[index];
            this.onApply(next);
          })
        Select(this.timeLabels.map((value: string): SelectOption => { return { value: value }; }))
          .selected(this.times.indexOf(this.options.jm.time)).value(this.timeLabels[this.times.indexOf(this.options.jm.time)])
          .systemMaterial(IMMERSIVE_REGULAR_MATERIAL)
          .onSelect((index: number): void => {
            const next: SourceSearchOptions = this.options.copy();
            next.jm.time = this.times[index];
            this.onApply(next);
          })
      } else if (this.kind === 'eh') {
        Button(this.options.eh.hasActiveFilter() ? '筛选已启用' : '筛选', { buttonStyle: ButtonStyleMode.NORMAL })
          .fontColor(PRIMARY).backgroundColor(SUB_CARD).onClick((): void => { this.sheet = true; })
      }
    }.width('100%').height(48).padding({ left: 16, right: 16 })
    .bindSheet($$this.sheet, this.FilterSheet(), { height: SheetSize.LARGE, dragBar: true, systemMaterial: IMMERSIVE_SHEET_MATERIAL })
  }
}
