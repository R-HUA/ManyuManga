import { IconCircleButton } from '../../common/Components';
import { BG, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
import { asRecord, asString } from '../../models/Models';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';
import { BlockRuleEditor } from './BlockRuleEditor';

@Component
export struct BlockRulesPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 0;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  @State sourceId: string = '';

  build() {
    NavDestination() {
      Column() {
        Row({ space: 10 }) {
          IconCircleButton({
            glyph: $r('sys.symbol.chevron_left'),
            onTap: (): void => {
              this.stack.pop();
            }
          })
          Column({ space: 2 }) {
            Text(this.sourceId === '' ? '全局屏蔽规则' : '本源屏蔽规则')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_MAIN)
            if (this.sourceId !== '') {
              Text(this.sourceId)
                .fontSize(12)
                .fontColor(TEXT_SUB)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topInset + 8, bottom: 8 })
        Scroll() {
          Column() {
            BlockRuleEditor({ sourceId: this.sourceId })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 24 + this.bottomInset })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)
    }
    .hideTitleBar(true)
    .backgroundColor(BG)
    .onReady((context: NavDestinationContext) => {
      const params: Record<string, Object> | null = asRecord(context.pathInfo.param as Object);
      this.sourceId = params === null ? '' : asString(params['sourceId']);
    })
  }
}
