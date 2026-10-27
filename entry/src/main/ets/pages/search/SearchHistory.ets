import { searchHistoryStore } from '../../data/stores/FilterStores';
import { errorMessage } from '../../models/Models';
import { IconCircleButton } from '../../common/Components';
import { SUB_CARD, TEXT_MAIN, TEXT_SUB, DANGER } from '../../common/Theme';

@Component
export struct SearchHistory {
  onSubmit: (text: string) => void = (_text: string): void => {};
  @State private items: Array<string> = [];
  @State private expanded: boolean = false;
  @State private contentHeight: number = 36;
  @State private error: string = '';

  aboutToAppear(): void { this.load(); }

  private async load(): Promise<void> {
    try { this.items = await searchHistoryStore.getList(); }
    catch (e) { this.error = errorMessage(e as Error); }
  }

  private confirmClear(): void {
    this.getUIContext().showAlertDialog({
      title: '清空搜索历史', message: '确定清空全部搜索历史？',
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: { value: '清空', action: (): void => { this.clear(); } }
    });
  }

  private async clear(): Promise<void> {
    try {
      await searchHistoryStore.clear();
      this.items = [];
      this.expanded = false;
      this.error = '';
    } catch (e) { this.error = errorMessage(e as Error); }
  }

  build() {
    Column({ space: 20 }) {
      if (this.items.length > 0) {
        Row() {
          Text('搜索历史').fontSize(22).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN).layoutWeight(1)
          IconCircleButton({ glyph: $r('sys.symbol.trash'), onTap: (): void => this.confirmClear() })
        }.width('100%')
        Row({ space: 12 }) {
          Scroll() {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.items, (item: string) => {
                Button(item, { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
                  .fontSize(15).fontColor(TEXT_MAIN).backgroundColor(SUB_CARD).height(36)
                  .padding({ left: 14, right: 14 }).margin({ right: 8, bottom: 8 })
                  .constraintSize({ maxWidth: '100%' }).onClick(() => this.onSubmit(item))
              }, (item: string) => item)
            }.width('100%').height('auto')
            .onAreaChange((_old: Area, area: Area): void => { this.contentHeight = Number(area.height); })
          }.layoutWeight(1).height(this.expanded ? this.contentHeight : 36).clip(true)
          .scrollable(ScrollDirection.None).scrollBar(BarState.Off).align(Alignment.TopStart)
          if (this.contentHeight > 44) {
            IconCircleButton({ glyph: this.expanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'),
              onTap: (): void => { this.expanded = !this.expanded; } })
          }
        }.alignItems(VerticalAlign.Top).width('100%')
      }
      if (this.error !== '') { Text(this.error).fontSize(13).fontColor(DANGER).width('100%') }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 28 })
  }
}
