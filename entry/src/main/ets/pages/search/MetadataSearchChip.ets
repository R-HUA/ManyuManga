import { MetadataTerm } from '../../models/Models';
import { MangaRouteParams, ROUTE_SEARCH, SearchField, SearchScope, SearchSelection } from '../../common/Route';
import { CARD, PRIMARY, PRIMARY_SOFT, TEXT_MAIN, DIVIDER } from '../../common/Theme';

@Component
export struct MetadataSearchChip {
  @Consume('navPathStack') stack: NavPathStack;
  @Prop term: MetadataTerm = new MetadataTerm();
  @Prop sourceId: string = '';
  @Prop sourceName: string = '';
  @Prop field: SearchField = 'tag';

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
    Button(this.term.label, { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL })
      .fontSize(12)
      .fontColor(this.field === 'author' ? PRIMARY : TEXT_MAIN)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .margin({ right: 8, bottom: 8 })
      .backgroundColor(this.field === 'author' ? PRIMARY_SOFT : CARD)
      .borderRadius(14)
      .border({ width: 0.5, color: DIVIDER })
      .onClick(() => this.search('source'))
      .bindContextMenu(this.Actions, ResponseType.LongPress)
  }
}
