import { PRIMARY, PRIMARY_SOFT, SUB_CARD, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

interface LibraryFilterOption {
  label: string;
  active: boolean;
  onTap: () => void;
}

@Component
export struct LibraryFilterSheet {
  @Link readFilter: number;
  @Link downloadFilter: number;
  @Link sort: number;
  @Link error: string;
  @Link sheet: boolean;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;

  @Builder
  private OptionPill($$: LibraryFilterOption) {
    Button($$.label, { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
      .fontSize(13).fontWeight($$.active ? FontWeight.Bold : FontWeight.Medium)
      .fontColor($$.active ? PRIMARY : TEXT_MAIN)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 }).margin({ right: 8, bottom: 8 })
      .backgroundColor($$.active ? PRIMARY_SOFT : SUB_CARD)
      .onClick(() => { $$.onTap(); })
  }

  build() {
    Column({ space: 20 }) {
      Text('筛选').fontSize(20).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN).width('100%')
      Column({ space: 10 }) {
        Text('排序方式').fontSize(13).fontColor(TEXT_SUB)
        Flex({ wrap: FlexWrap.Wrap }) {
          this.OptionPill({ label: '最近加入', active: this.sort === 0, onTap: (): void => { this.sort = 0; } })
          this.OptionPill({ label: '作品名称', active: this.sort === 1, onTap: (): void => { this.sort = 1; } })
          this.OptionPill({ label: '最近阅读', active: this.sort === 2, onTap: (): void => { this.sort = 2; } })
        }.width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)
      Column({ space: 10 }) {
        Text('阅读状态').fontSize(13).fontColor(TEXT_SUB)
        Flex({ wrap: FlexWrap.Wrap }) {
          this.OptionPill({ label: '全部状态', active: this.readFilter === 0, onTap: (): void => { this.readFilter = 0; } })
          this.OptionPill({ label: '已读完', active: this.readFilter === 1, onTap: (): void => { this.readFilter = 1; } })
          this.OptionPill({ label: '未读完', active: this.readFilter === 2, onTap: (): void => { this.readFilter = 2; } })
        }.width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)
      Column({ space: 10 }) {
        Text('离线状态').fontSize(13).fontColor(TEXT_SUB)
        Flex({ wrap: FlexWrap.Wrap }) {
          this.OptionPill({ label: '全部漫画', active: this.downloadFilter === 0, onTap: (): void => { this.downloadFilter = 0; } })
          this.OptionPill({ label: '已离线下载', active: this.downloadFilter === 1, onTap: (): void => { this.downloadFilter = 1; } })
          this.OptionPill({ label: '未离线', active: this.downloadFilter === 2, onTap: (): void => { this.downloadFilter = 2; } })
        }.width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)
      Row({ space: 12 }) {
        Button('重置', { buttonStyle: ButtonStyleMode.NORMAL }).fontColor(PRIMARY).backgroundColor(SUB_CARD).layoutWeight(1)
          .onClick(() => { this.sort = 0; this.readFilter = 0; this.downloadFilter = 0; })
        Button('完成', { buttonStyle: ButtonStyleMode.NORMAL }).fontColor(Color.White).backgroundColor(PRIMARY).layoutWeight(1)
          .onClick(() => { this.sheet = false; })
      }.width('100%')
    }.width('100%').padding({ left: 24, right: 24, top: 20, bottom: 24 + this.bottomInset })
  }
}
