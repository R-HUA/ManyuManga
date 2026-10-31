import { MetadataTerm } from '../../models/Models';
import { MangaRouteParams, ROUTE_SEARCH, SearchField, SearchScope, SearchSelection } from '../../common/Route';
import { CARD, PRIMARY, PRIMARY_SOFT, TEXT_MAIN, DIVIDER } from '../../common/Theme';

/** capsule：带底色胶囊（标签）；plain：纯文字（详情页作者行），无背景、边框。 */
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
        .fontSize(13)
        .fontColor(PRIMARY)
        .accessibilityText(this.term.label)
        .onClick(() => this.search('source'))
        .bindContextMenu(this.Actions, ResponseType.LongPress)
    } else {
      this.Capsule()
    }
  }

  @Builder
  private Capsule() {
    Button({ type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL }) {
      Text(this.term.label).fontSize(12).fontColor(this.field === 'author' ? PRIMARY : TEXT_MAIN)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .height(32)
      .width('auto')
      .constraintSize({ maxWidth: '100%' })
      .padding({ left: 12, right: 12 })
      .margin({ right: 8, bottom: 8 })
      .backgroundColor(this.field === 'author' ? PRIMARY_SOFT : CARD)
      .borderRadius(14)
      .border({ width: 0.5, color: DIVIDER })
      .onClick(() => this.search('source'))
      .bindContextMenu(this.Actions, ResponseType.LongPress)
  }
}
