import { SPACE_M, SPACE_S, SPACE_L, FONT_CAPTION, TEXT_SUB, PRIMARY, CARD, CARD_R } from '../../common/Theme';
@Builder
export function SectionErrorRow(message: string, onRetry: () => void) {
  Row({ space: SPACE_M }) {
    Text(message)
      .fontSize(FONT_CAPTION)
      .fontColor(TEXT_SUB)
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .layoutWeight(1)
    Text('重试')
      .fontSize(FONT_CAPTION)
      .fontColor(PRIMARY)
      .padding({ left: SPACE_M, right: SPACE_M, top: SPACE_S, bottom: SPACE_S })
      .onClick(() => {
        onRetry();
      })
  }
  .width('100%')
  .padding({ left: SPACE_L, right: SPACE_M, top: SPACE_S, bottom: SPACE_S })
  .backgroundColor(CARD)
  .borderRadius(CARD_R)
  .margin({ left: SPACE_L, right: SPACE_L })
}
