import { SUB_CARD, PRIMARY, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

@Component
export struct LibraryCategorySheet {
  @Link categoryName: string;
  @Link categories: Array<string>;
  @Link categorySheet: boolean;
  action: (kind: string) => Promise<void> = async (kind: string): Promise<void> => {};
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;

  build() {
    Column({ space: 18 }) {
      Text('设置作品分类')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .width('100%')

      TextInput({ text: this.categoryName, placeholder: '输入新分类名称（留空则移出分类）' })
        .height(44)
        .borderRadius(14)
        .backgroundColor(SUB_CARD)
        .fontColor(TEXT_MAIN)
        .placeholderColor(TEXT_SUB)
        .onChange((text: string) => {
          this.categoryName = text;
        })

      if (this.categories.length > 0) {
        Column({ space: 8 }) {
          Text('已有分类')
            .fontSize(12)
            .fontColor(TEXT_SUB)
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.categories, (cat: string) => {
              Text(cat)
                .fontSize(13)
                .fontColor(this.categoryName === cat ? Color.White : TEXT_MAIN)
                .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                .margin({ right: 8, bottom: 8 })
                .borderRadius(16)
                .backgroundColor(this.categoryName === cat ? PRIMARY : SUB_CARD)
                .onClick(() => {
                  this.categoryName = cat;
                })
            }, (cat: string) => cat)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }

      Row({ space: 12 }) {
        Text('取消')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_MAIN)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(44)
          .borderRadius(22)
          .backgroundColor(SUB_CARD)
          .onClick(() => {
            this.categorySheet = false;
          })
        Text('保存应用')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(44)
          .borderRadius(22)
          .backgroundColor(PRIMARY)
          .onClick(() => {
            this.action('category');
          })
      }
      .width('100%')
    }
    .padding({ left: 24, right: 24, top: 16, bottom: 28 + this.bottomInset })
    .width('100%')
  }
}
