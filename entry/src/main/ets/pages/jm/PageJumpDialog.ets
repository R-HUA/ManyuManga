import { PRIMARY, CARD, TEXT_MAIN, TEXT_SUB, CHIP_BG, CHIP_R, FONT_BODY } from '../../common/Theme';

@CustomDialog
export struct PageJumpDialog {
  controller?: CustomDialogController;
  @State input: string = '';
  /** 打开时读取当前页码（页面侧闭包） */
  current: () => number = () => 1;
  onConfirm: (page: number) => void = () => {};

  /** 解析输入页码；非法返回 0 交由页面 Toast */
  private confirm(): void {
    const n: number = Number(this.input.trim());
    const page: number = Number.isNaN(n) ? 0 : Math.floor(n);
    if (page < 1) {
      this.onConfirm(0);
      return;
    }
    this.onConfirm(page);
    if (this.controller) {
      this.controller.close();
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('跳转到指定页')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
      Text(`当前第 ${this.current()} 页`)
        .fontSize(11)
        .fontColor(TEXT_SUB)
        .width('100%')
      TextInput({ text: this.input, placeholder: '输入页码，如 12' })
        .type(InputType.Number)
        .fontSize(FONT_BODY)
        .fontColor(TEXT_MAIN)
        .onChange((v: string) => {
          this.input = v;
        })
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
        Text('确定')
          .fontSize(FONT_BODY)
          .fontColor(Color.White)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 9, bottom: 9 })
          .backgroundColor(PRIMARY)
          .borderRadius(CHIP_R)
          .onClick(() => {
            this.confirm();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor(CARD)
  }
}
