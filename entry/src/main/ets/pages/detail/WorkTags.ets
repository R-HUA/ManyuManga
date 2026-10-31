import { LengthMetrics } from '@kit.ArkUI';
import { MetadataSearchChip } from '../search/MetadataSearchChip';
import { IconCircleButton } from '../../common/Components';
import { MetadataTerm } from '../../models/Models';
import { TEXT_SUB } from '../../common/Theme';

/**
 * 详情页标签：默认单行横向滚动（两端渐隐），内容超出可视宽度时右侧固定展开按钮；
 * 展开后换行显示全部标签，末尾为收起按钮。作品切换时恢复折叠。
 */
@Component
export struct WorkTags {
  @Prop @Watch('reset') aid: string = '';
  @Prop terms: Array<MetadataTerm> = [];
  @Prop sourceId: string = '';
  @Prop sourceName: string = '';
  @State private expanded: boolean = false;
  @State private contentWidth: number = 0;
  @State private viewportWidth: number = 0;

  private reset(): void { this.expanded = false; }

  private overflowing(): boolean { return this.contentWidth > this.viewportWidth + 0.5; }

  @Builder
  private Chips() {
    ForEach(this.terms, (term: MetadataTerm) => {
      MetadataSearchChip({ term: term, sourceId: this.sourceId, sourceName: this.sourceName })
    }, (term: MetadataTerm) => JSON.stringify([term.namespace, term.value]))
  }

  build() {
    if (this.expanded) {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        this.Chips()
        IconCircleButton({
          glyph: $r('sys.symbol.chevron_up'), btnSize: 40, iconSize: 18, iconColor: TEXT_SUB,
          onTap: (): void => { this.expanded = false; }
        })
          .margin({ bottom: 8 })
          .accessibilityText('收起标签')
      }
      .width('100%')
    } else {
      Row() {
        Scroll() {
          Row() {
            this.Chips()
          }
          .alignItems(VerticalAlign.Top)
          .onAreaChange((_old: Area, area: Area): void => { this.contentWidth = Number(area.width); })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .align(Alignment.Start)
        .layoutWeight(1)
        .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(24) })
        .onAreaChange((_old: Area, area: Area): void => { this.viewportWidth = Number(area.width); })

        if (this.overflowing()) {
          IconCircleButton({
            glyph: $r('sys.symbol.chevron_down'), btnSize: 40, iconSize: 18, iconColor: TEXT_SUB,
            onTap: (): void => { this.expanded = true; }
          })
            .margin({ bottom: 8 })
            .accessibilityText('展开全部标签')
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }
}
