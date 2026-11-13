import { CARD, FONT_BODY, PRIMARY, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
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
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_MAIN)
      TextInput({ text: this.input, placeholder: '名称 / 关键词' })
        .fontSize(FONT_BODY)
        .fontColor(TEXT_MAIN)
        .onChange((v: string) => {
          this.input = v;
          this.err = '';
        })
      Text(`${this.cpCount()} / 16 字符`)
        .fontSize(12)
        .fontColor(TEXT_SUB)
        .width('100%')
      if (this.err !== '') {
        Text(this.err)
          .fontSize(12)
          .fontColor(PRIMARY)
          .width('100%')
      }
      Row({ space: 12 }) {
        Button('取消', { buttonStyle: ButtonStyleMode.NORMAL })
          .layoutWeight(1)
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
