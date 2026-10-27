import { IMMERSIVE_REGULAR_MATERIAL } from '../../common/ImmersiveMaterials';
import { PRIMARY, SUB_CARD, TEXT_MAIN } from '../../common/Theme';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

@Component
export struct LibraryFilterSheet {
  @Link readFilter: number;
  @Link downloadFilter: number;
  @Link sort: number;
  @Link error: string;
  @Link sheet: boolean;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;

  build() {
    Column({ space: 20 }) {
      Text('筛选').fontSize(20).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN).width('100%')
      Row() {
        Text('排序').fontColor(TEXT_MAIN).layoutWeight(1)
        Select([{ value: '最近加入' }, { value: '作品名称' }, { value: '最近阅读' }])
          .selected(this.sort).value(['最近加入', '作品名称', '最近阅读'][this.sort])
          .systemMaterial(IMMERSIVE_REGULAR_MATERIAL).onSelect((index: number): void => { this.sort = index; })
      }.width('100%')
      Row() {
        Text('阅读状态').fontColor(TEXT_MAIN).layoutWeight(1)
        Select([{ value: '全部' }, { value: '已读完' }, { value: '未读完' }])
          .selected(this.readFilter).value(['全部', '已读完', '未读完'][this.readFilter])
          .systemMaterial(IMMERSIVE_REGULAR_MATERIAL).onSelect((index: number): void => { this.readFilter = index; })
      }.width('100%')
      Row() {
        Text('离线状态').fontColor(TEXT_MAIN).layoutWeight(1)
        Select([{ value: '全部' }, { value: '已离线' }, { value: '未离线' }])
          .selected(this.downloadFilter).value(['全部', '已离线', '未离线'][this.downloadFilter])
          .systemMaterial(IMMERSIVE_REGULAR_MATERIAL).onSelect((index: number): void => { this.downloadFilter = index; })
      }.width('100%')
      Row({ space: 12 }) {
        Button('重置', { buttonStyle: ButtonStyleMode.NORMAL }).fontColor(PRIMARY).backgroundColor(SUB_CARD).layoutWeight(1)
          .onClick(() => { this.sort = 0; this.readFilter = 0; this.downloadFilter = 0; })
        Button('完成', { buttonStyle: ButtonStyleMode.NORMAL }).fontColor(Color.White).backgroundColor(PRIMARY).layoutWeight(1)
          .onClick(() => { this.sheet = false; })
      }.width('100%')
    }.width('100%').padding({ left: 24, right: 24, top: 20, bottom: 24 + this.bottomInset })
  }
}
