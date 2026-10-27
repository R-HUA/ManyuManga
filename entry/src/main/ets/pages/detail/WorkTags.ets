import { MetadataSearchChip } from '../search/MetadataSearchChip';
import { MetadataTerm } from '../../models/Models';
import { PRIMARY, SUB_CARD } from '../../common/Theme';

@Component
export struct WorkTags {
  @Prop @Watch('reset') aid: string = '';
  @Prop terms: Array<MetadataTerm> = [];
  @Prop sourceId: string = '';
  @Prop sourceName: string = '';
  @State private expanded: boolean = false;
  @State private contentHeight: number = 80;

  private reset(): void { this.expanded = false; this.contentHeight = 80; }

  build() {
    Column({ space: 8 }) {
      Scroll() {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.terms, (term: MetadataTerm) => {
            MetadataSearchChip({ term: term, sourceId: this.sourceId, sourceName: this.sourceName })
          }, (term: MetadataTerm) => JSON.stringify([term.namespace, term.value]))
        }.width('100%').height('auto')
        .onAreaChange((_old: Area, area: Area): void => { this.contentHeight = Number(area.height); })
      }.width('100%').height(this.expanded ? this.contentHeight : Math.min(80, this.contentHeight)).clip(true)
      .scrollable(ScrollDirection.None).scrollBar(BarState.Off).align(Alignment.TopStart)
      if (this.contentHeight > 80) {
        Button(this.expanded ? '收起' : '展开', { buttonStyle: ButtonStyleMode.NORMAL })
          .fontColor(PRIMARY).backgroundColor(SUB_CARD).height(32).onClick(() => { this.expanded = !this.expanded; })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
