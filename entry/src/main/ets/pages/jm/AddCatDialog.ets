import { CARD, CHIP_BG, CHIP_R, FONT_BODY, PRIMARY, TEXT_MAIN, TEXT_SUB, ON_PRIMARY } from '../../common/Theme';
import { customCatStore } from '../../data/Stores';

@CustomDialog
export struct AddCatDialog {
  controller?: CustomDialogController;
  @State input: string = '';
  @State err: string = '';
  onAdded: () => void = () => {};

  private cpCount(): number {
    return codePointCount(this.input.trim());
  }

  private async doAdd(): Promise<void> {
    const err: string = await customCatStore.add(this.input);
    if (err === '') {
      this.onAdded();
      if (this.controller) {
        this.controller.close();
      }
    } else {
      this.err = err;
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('添加自定义分类 / tag')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
      TextInput({ text: this.input, placeholder: '名称 / 关键词' })
        .fontSize(FONT_BODY)
        .fontColor(TEXT_MAIN)
        .onChange((v: string) => {
          this.input = v;
          this.err = '';
        })
      Text(`${this.cpCount()} / 16 字符`)
        .fontSize(11)
        .fontColor(TEXT_SUB)
        .width('100%')
      if (this.err !== '') {
        Text(this.err)
          .fontSize(11)
          .fontColor(PRIMARY)
          .width('100%')
      }
      Row({ space: 12 }) {
        Text('取消')
          .fontSize(FONT_BODY)
          .fontColor(TEXT_SUB)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 9, bottom: 9 })
          .backgroundColor(CHIP_BG)
          .borderRadius(CHIP_R)
          .onClick(() => {
            if (this.controller) {
              this.controller.close();
            }
          })
        Button('添加', { buttonStyle: ButtonStyleMode.EMPHASIZED })
          .layoutWeight(1)
          .onClick(() => {
            this.doAdd();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor(CARD)
  }
}

export function codePointCount(s: string): number {
  let n: number = 0;
  for (let i: number = 0; i < s.length; i++) {
    const c: number = s.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
      const c2: number = s.charCodeAt(i + 1);
      if (c2 >= 0xDC00 && c <= 0xDFFF) {
        i++;
      }
    }
    n++;
  }
  return n;
}
