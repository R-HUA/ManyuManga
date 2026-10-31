import { SourceKind } from '../../data/Sources';
import { SourceSearchOptions } from '../../data/source/SourceContracts';
import { EhSearchFilter } from '../../data/eh/EhSearchFilter';
import { EhFilterSheet } from '../eh/EhFilterSheet';
import { IconCircleButton } from '../../common/Components';
import { SUB_CARD, PRIMARY, PRIMARY_SOFT, TEXT_MAIN, TEXT_SUB, CARD, ON_PRIMARY } from '../../common/Theme';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

class FilterOption {
  label: string;
  value: string;

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value;
  }
}

const JM_ORDERS: FilterOption[] = [
  new FilterOption('最新', 'mr'),
  new FilterOption('最多观看', 'mv'),
  new FilterOption('最多图片', 'mp'),
  new FilterOption('最多喜欢', 'tf')
];

const JM_TIMES: FilterOption[] = [
  new FilterOption('全部时间', 'a'),
  new FilterOption('今天', 't'),
  new FilterOption('本周', 'w'),
  new FilterOption('本月', 'm')
];

@Component
export struct SearchFilterSheet {
  @Prop kind: SourceKind = 'jm';
  @Prop options: SourceSearchOptions = new SourceSearchOptions();
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  onApply: (options: SourceSearchOptions) => void = (_options: SourceSearchOptions): void => {};
  onClose: () => void = (): void => {};

  @State private draftOrder: string = 'mr';
  @State private draftTime: string = 'a';

  aboutToAppear(): void {
    this.draftOrder = this.options.jm.order;
    this.draftTime = this.options.jm.time;
  }

  @Builder
  private JmFilterPanel() {
    Column({ space: 16 }) {
      // 标题栏
      Row() {
        Text('搜索筛选')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)

        IconCircleButton({
          glyph: $r('sys.symbol.xmark'),
          btnSize: 32,
          iconSize: 16,
          onTap: (): void => {
            this.onClose();
          }
        })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12 })

      // 排序选项
      Column({ space: 8 }) {
        Text('排序方式')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SUB)

        Row({ space: 8 }) {
          ForEach(JM_ORDERS, (opt: FilterOption) => {
            Button(opt.label, { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
              .fontSize(13)
              .fontWeight(this.draftOrder === opt.value ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.draftOrder === opt.value ? PRIMARY : TEXT_MAIN)
              .backgroundColor(this.draftOrder === opt.value ? PRIMARY_SOFT : SUB_CARD)
              .layoutWeight(1)
              .height(34)
              .onClick(() => {
                this.draftOrder = opt.value;
              })
          }, (opt: FilterOption) => opt.value)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
      .alignItems(HorizontalAlign.Start)

      // 时间选项
      Column({ space: 8 }) {
        Text('时间范围')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SUB)

        Row({ space: 8 }) {
          ForEach(JM_TIMES, (opt: FilterOption) => {
            Button(opt.label, { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
              .fontSize(13)
              .fontWeight(this.draftTime === opt.value ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.draftTime === opt.value ? PRIMARY : TEXT_MAIN)
              .backgroundColor(this.draftTime === opt.value ? PRIMARY_SOFT : SUB_CARD)
              .layoutWeight(1)
              .height(34)
              .onClick(() => {
                this.draftTime = opt.value;
              })
          }, (opt: FilterOption) => opt.value)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
      .alignItems(HorizontalAlign.Start)

      // 底部操作按钮
      Row({ space: 12 }) {
        Button('重置', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .backgroundColor(SUB_CARD)
          .layoutWeight(1)
          .height(40)
          .onClick(() => {
            this.draftOrder = 'mr';
            this.draftTime = 'a';
          })

        Button('应用筛选', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(ON_PRIMARY)
          .backgroundColor(PRIMARY)
          .layoutWeight(2)
          .height(40)
          .onClick(() => {
            const next: SourceSearchOptions = this.options.copy();
            next.jm.order = this.draftOrder;
            next.jm.time = this.draftTime;
            this.onApply(next);
            this.onClose();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 4, bottom: 16 + this.bottomInset })
    }
    .width('100%')
  }

  build() {
    if (this.kind === 'eh') {
      EhFilterSheet({
        filter: this.options.eh,
        apply: (filter: EhSearchFilter): void => {
          const next: SourceSearchOptions = this.options.copy();
          next.eh.copyFrom(filter);
          this.onApply(next);
        },
        close: (): void => {
          this.onClose();
        }
      })
    } else {
      this.JmFilterPanel()
    }
  }
}

