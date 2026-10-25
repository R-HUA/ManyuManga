import uiMaterial from '@ohos.arkui.uiMaterial';
import { errorMessage } from '../../models/Models';
import { SUB_CARD, PRIMARY, PRIMARY_SOFT, TEXT_MAIN, TEXT_SUB, DIVIDER } from '../../common/Theme';
import { Prefs } from '../../util/Prefs';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

@Component
export struct LibraryFilterSheet {
  @Link readFilter: number;
  @Link downloadFilter: number;
  @Link sort: number;
  @Link columns: number;
  @Link error: string;
  @Link sheet: boolean;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;

  build() {
    Column({ space: 20 }) {
      Row() {
        Text('筛选与视图控制')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)
        if (this.readFilter !== 0 || this.downloadFilter !== 0 || this.sort !== 0) {
          Text('重置')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(PRIMARY)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor(PRIMARY_SOFT)
            .onClick(() => {
              this.readFilter = 0;
              this.downloadFilter = 0;
              this.sort = 0;
            })
        }
      }
      .width('100%')

      Column({ space: 10 }) {
        Text('排序方式')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SUB)
        Row({ space: 10 }) {
          this.SheetOptionPill('最近加入', this.sort === 0, () => { this.sort = 0; })
          this.SheetOptionPill('作品名称', this.sort === 1, () => { this.sort = 1; })
          this.SheetOptionPill('最近阅读', this.sort === 2, () => { this.sort = 2; })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Column({ space: 10 }) {
        Text('阅读状态')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SUB)
        Row({ space: 10 }) {
          this.SheetOptionPill('全部状态', this.readFilter === 0, () => { this.readFilter = 0; })
          this.SheetOptionPill('已读完', this.readFilter === 1, () => { this.readFilter = 1; })
          this.SheetOptionPill('未读完', this.readFilter === 2, () => { this.readFilter = 2; })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Column({ space: 10 }) {
        Text('离线状态')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SUB)
        Row({ space: 10 }) {
          this.SheetOptionPill('全部漫画', this.downloadFilter === 0, () => { this.downloadFilter = 0; })
          this.SheetOptionPill('已离线下载', this.downloadFilter === 1, () => { this.downloadFilter = 1; })
          this.SheetOptionPill('未离线', this.downloadFilter === 2, () => { this.downloadFilter = 2; })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Column({ space: 8 }) {
        Row() {
          Text('书架网格密度')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT_SUB)
            .layoutWeight(1)
          Text(`每行 ${this.columns} 部`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(PRIMARY)
        }
        .width('100%')

        Slider({ value: this.columns, min: 2, max: 6, step: 1, style: SliderStyle.OutSet })
          .selectedColor(PRIMARY)
          .trackColor(DIVIDER)
          .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
          .onChange((value: number) => {
            const cols: number = Math.round(value);
            this.columns = cols;
            (async (): Promise<void> => {
              await (await Prefs.getInstance()).putNumber('library_columns', cols);
            })().catch((e: Error) => {
              this.error = errorMessage(e);
            });
          })
      }
      .width('100%')

      Text('完成')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(44)
        .borderRadius(22)
        .backgroundColor(PRIMARY)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
        .onClick(() => {
          this.sheet = false;
        })
    }
    .padding({ left: 24, right: 24, top: 16, bottom: 28 + this.bottomInset })
    .width('100%')
  }

  @Builder
  private SheetOptionPill(label: string, active: boolean, onTap: () => void) {
    Text(label)
      .fontSize(13)
      .fontWeight(active ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(active ? Color.White : TEXT_MAIN)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .borderRadius(16)
      .backgroundColor(active ? PRIMARY : SUB_CARD)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
      .onClick(() => {
        onTap();
      })
  }
}
