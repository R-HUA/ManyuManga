import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HDS_TITLE_STYLE } from '../../common/ImmersiveMaterials';
import { BG } from '../../common/Theme';
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
    HdsNavDestination() {
      Column() {
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
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)
    }
    .titleBar({ content: { title: { mainTitle: this.sourceId === '' ? '全局屏蔽规则' : '本源屏蔽规则' } }, style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(BG)
    .onReady((context: NavDestinationContext) => {
      const params: Record<string, Object> | null = asRecord(context.pathInfo.param as Object);
      this.sourceId = params === null ? '' : asString(params['sourceId']);
    })
  }
}
