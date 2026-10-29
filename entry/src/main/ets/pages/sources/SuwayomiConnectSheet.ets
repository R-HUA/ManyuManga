import { SUB_CARD, PRIMARY, DANGER, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

@Component
export struct SuwayomiConnectSheet {
  @Prop instance: string = '';
  @Link name: string;
  @Link endpoint: string;
  @Link authIndex: number;
  @Link user: string;
  @Link password: string;
  @Link error: string;
  @Link busy: boolean;
  connect: () => Promise<void> = async (): Promise<void> => {};
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Column({ space: 8 }) {
          Text('服务别名')
            .fontSize(12)
            .fontColor(TEXT_SUB)
          TextInput({ text: this.name, placeholder: '例如：家庭 NAS 书源库' })
            .height(44)
            .borderRadius(14)
            .backgroundColor(SUB_CARD)
            .fontColor(TEXT_MAIN)
            .placeholderColor(TEXT_SUB)
            .onChange((s: string) => {
              this.name = s;
            })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Column({ space: 8 }) {
          Text('服务端地址')
            .fontSize(12)
            .fontColor(TEXT_SUB)
          TextInput({ text: this.endpoint, placeholder: '如 http://192.168.1.10:4567' })
            .height(44)
            .borderRadius(14)
            .backgroundColor(SUB_CARD)
            .fontColor(TEXT_MAIN)
            .placeholderColor(TEXT_SUB)
            .onChange((s: string) => {
              this.endpoint = s;
            })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Column({ space: 8 }) {
          Text('鉴权方式')
            .fontSize(12)
            .fontColor(TEXT_SUB)
          Row({ space: 8 }) {
            this.AuthModePill('免密直连', 0)
            this.AuthModePill('基础认证', 1)
            this.AuthModePill('会话登录', 2)
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        if (this.authIndex > 0) {
          TextInput({ text: this.user, placeholder: '认证用户名' })
            .height(44)
            .borderRadius(14)
            .backgroundColor(SUB_CARD)
            .fontColor(TEXT_MAIN)
            .placeholderColor(TEXT_SUB)
            .onChange((s: string) => {
              this.user = s;
            })
          TextInput({ text: this.password, placeholder: '认证密码' })
            .height(44)
            .borderRadius(14)
            .backgroundColor(SUB_CARD)
            .fontColor(TEXT_MAIN)
            .placeholderColor(TEXT_SUB)
            .type(InputType.Password)
            .onChange((s: string) => {
              this.password = s;
            })
        }

        if (this.error !== '') {
          Text(this.error)
            .fontSize(12)
            .fontColor(DANGER)
            .width('100%')
        }

        Button(this.busy ? '正在连接…' : '连接书库', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.EMPHASIZED })
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .width('100%')
          .height(46)
          .borderRadius(23)
          .backgroundColor(PRIMARY)
          .opacity(this.busy ? 0.6 : 1.0)
          .enabled(!this.busy)
          .onClick(() => {
            if (!this.busy) {
              this.connect();
            }
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16, bottom: 28 + this.bottomInset })
    }
    .width('100%')
    .align(Alignment.TopStart)
  }

  @Builder
  private AuthModePill(label: string, index: number) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.authIndex === index ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.authIndex === index ? Color.White : TEXT_MAIN)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 9, bottom: 9 })
      .borderRadius(16)
      .backgroundColor(this.authIndex === index ? PRIMARY : SUB_CARD)
      .onClick(() => {
        this.authIndex = index;
      })
  }
}
