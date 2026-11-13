import { MetadataTerm } from '../../models/Models';
import { MangaRouteParams, ROUTE_SEARCH, SearchField, SearchScope, SearchSelection } from '../../common/Route';
import { CHIP_R, SUB_CARD, TEXT_MAIN } from '../../common/Theme';

/** capsule：中性底小胶囊（标签）；plain：普通文字色（详情页作者行），无背景、边框。 */
export type MetadataChipStyle = 'capsule' | 'plain';

@Component
export struct MetadataSearchChip {
  @Consume('navPathStack') stack: NavPathStack;
  @Prop term: MetadataTerm = new MetadataTerm();
  @Prop sourceId: string = '';
  @Prop sourceName: string = '';
  @Prop field: SearchField = 'tag';
  @Prop chipStyle: MetadataChipStyle = 'capsule';

  private search(scope: SearchScope): void {
    this.stack.pushPathByName(ROUTE_SEARCH, {
      scope: scope, sourceId: this.sourceId, query: this.term.value,
      selection: new SearchSelection(this.sourceId, this.field, this.term)
    } as MangaRouteParams);
  }

  @Builder
  private Actions() {
    Menu() {
      MenuItem({ content: `搜索「${this.sourceName}」` }).onClick(() => this.search('source'))
      MenuItem({ content: '搜索书架' }).onClick(() => this.search('library'))
      MenuItem({ content: '搜索全部' }).onClick(() => this.search('all'))
    }
  }

  build() {
    if (this.chipStyle === 'plain') {
      Text(this.term.label)
        .fontSize(14)
        .fontColor(TEXT_MAIN)
        .constraintSize({ minWidth: 40, minHeight: 40 })
        .accessibilityText(this.term.label)
        .onClick(() => this.search('source'))
        .bindContextMenu(this.Actions, ResponseType.LongPress)
    } else {
      this.Capsule()
    }
  }

  /** 标签：中性底、高 28、字号 12；热区向上下扩展到 40vp。 */
  @Builder
  private Capsule() {
    Text(this.term.label)
      .fontSize(12)
      .fontColor(TEXT_MAIN)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .height(28)
      .constraintSize({ maxWidth: '100%' })
      .padding({ left: 10, right: 10 })
      .margin({ right: 8, top: 6, bottom: 6 })
      .backgroundColor(SUB_CARD)
      .borderRadius(CHIP_R)
      .responseRegion({ x: 0, y: -6, width: '100%', height: 40 })
      .accessibilityText(this.term.label)
      .onClick(() => this.search('source'))
      .bindContextMenu(this.Actions, ResponseType.LongPress)
  }
}
