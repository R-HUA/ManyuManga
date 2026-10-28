import { TagChip } from '../../common/Components';
import { TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

interface LibraryFilterOption {
  label: string;
  active: boolean;
  onTap: () => void;
}

@Component
export struct LibraryFilterSheet {
  @Link category: string;
  @Link categories: Array<string>;
  @Link readFilter: number;
  @Link downloadFilter: number;
  @Link sort: number;
  @Link error: string;
  @Link sheet: boolean;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;

  @Builder
  private OptionPill($$: LibraryFilterOption) {
    TagChip({
      label: $$.label,
      selected: $$.active,
      onChipClick: (): void => {
        $$.onTap();
      }
    })
      .margin({ right: 8, bottom: 8 })
  }

  build() {
    Column({ space: 18 }) {
      Text('筛选与排序')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .width('100%')

      if (this.categories.length > 0) {
        Column({ space: 8 }) {
          Text('分类').fontSize(12).fontColor(TEXT_SUB)
          Flex({ wrap: FlexWrap.Wrap }) {
            this.OptionPill({ label: '全部分类', active: this.category === '', onTap: (): void => { this.category = ''; } })
            ForEach(this.categories, (name: string) => {
              this.OptionPill({ label: name, active: this.category === name, onTap: (): void => { this.category = name; } })
            }, (name: string): string => `cat_${name}`)
          }.width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
      }

      Column({ space: 8 }) {
        Text('排序方式').fontSize(12).fontColor(TEXT_SUB)
        Flex({ wrap: FlexWrap.Wrap }) {
          this.OptionPill({ label: '最近加入', active: this.sort === 0, onTap: (): void => { this.sort = 0; } })
          this.OptionPill({ label: '作品名称', active: this.sort === 1, onTap: (): void => { this.sort = 1; } })
          this.OptionPill({ label: '最近阅读', active: this.sort === 2, onTap: (): void => { this.sort = 2; } })
        }.width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)

      Column({ space: 8 }) {
        Text('阅读状态').fontSize(12).fontColor(TEXT_SUB)
        Flex({ wrap: FlexWrap.Wrap }) {
          this.OptionPill({ label: '全部状态', active: this.readFilter === 0, onTap: (): void => { this.readFilter = 0; } })
          this.OptionPill({ label: '已读完', active: this.readFilter === 1, onTap: (): void => { this.readFilter = 1; } })
          this.OptionPill({ label: '未读完', active: this.readFilter === 2, onTap: (): void => { this.readFilter = 2; } })
        }.width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)

      Column({ space: 8 }) {
        Text('离线状态').fontSize(12).fontColor(TEXT_SUB)
        Flex({ wrap: FlexWrap.Wrap }) {
          this.OptionPill({ label: '全部漫画', active: this.downloadFilter === 0, onTap: (): void => { this.downloadFilter = 0; } })
          this.OptionPill({ label: '已离线下载', active: this.downloadFilter === 1, onTap: (): void => { this.downloadFilter = 1; } })
          this.OptionPill({ label: '未离线', active: this.downloadFilter === 2, onTap: (): void => { this.downloadFilter = 2; } })
        }.width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)

      Row({ space: 12 }) {
        Button('重置', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
          .layoutWeight(1)
          .height(40)
          .onClick(() => {
            this.category = '';
            this.sort = 0;
            this.readFilter = 0;
            this.downloadFilter = 0;
          })
        Button('完成', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.EMPHASIZED })
          .layoutWeight(1)
          .height(40)
          .onClick(() => {
            this.sheet = false;
          })
      }.width('100%')
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 18, bottom: 24 + this.bottomInset })
  }
}
