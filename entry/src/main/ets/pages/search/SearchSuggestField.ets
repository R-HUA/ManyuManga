import { BasicDataSource } from '../../common/DataSource';
import { IMMERSIVE_REGULAR_MATERIAL } from '../../common/ImmersiveMaterials';
import { CARD, PRIMARY, PRIMARY_SOFT, TEXT_MAIN, TEXT_SUB, DIVIDER } from '../../common/Theme';
import { SearchSelection } from '../../common/Route';
import { MetadataTerm, errorMessage } from '../../models/Models';
import { SearchSuggestion, suggestLocal } from '../../data/SearchSuggest';

class SuggestSource extends BasicDataSource<SearchSuggestion> {
  reload(items: Array<SearchSuggestion>): void {
    this.setList(items);
  }
}

interface SuggestPopupState { isVisible: boolean; }

@Component
export struct SearchSuggestField {
  @Link text: string;
  @Prop @Watch('reset') sourceId: string = '';
  @Prop placeholder: string = '';
  /** 带右侧筛选入口时隐藏“搜索”按钮，回车仍可提交。 */
  @Prop showSearchButton: boolean = true;
  @Prop selection: SearchSelection | null = null;
  onEdit: (text: string) => void = (_text: string): void => {};
  onSubmit: (text: string, selection: SearchSelection | null) => void =
    (_text: string, _selection: SearchSelection | null): void => {};
  @State open: boolean = false;
  @State error: string = '';
  @State contentWidth: number = 280;
  private source: SuggestSource = new SuggestSource();
  private generation: number = 0;
  private timer: number = -1;

  aboutToDisappear(): void {
    this.reset();
  }

  private reset(): void {
    this.generation++;
    this.clearTimer();
    this.open = false;
    this.error = '';
    this.source.reload([]);
  }

  private clearTimer(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private schedule(value: string): void {
    this.reset();
    if (value.trim() === '') { return; }
    const ticket: number = ++this.generation;
    this.timer = setTimeout((): void => {
      this.timer = -1;
      this.load(value, ticket);
    }, 180);
  }

  private async load(value: string, ticket: number): Promise<void> {
    try {
      const items: Array<SearchSuggestion> = await suggestLocal(value, this.sourceId);
      if (ticket !== this.generation) { return; }
      this.source.reload(items);
      this.open = items.length > 0;
      this.error = '';
    } catch (e) {
      if (ticket !== this.generation) { return; }
      this.open = true;
      this.error = errorMessage(e as Error);
    }
  }

  private choose(item: SearchSuggestion): void {
    this.generation++;
    this.clearTimer();
    const next: string = item.value;
    const selection: SearchSelection | null = item.kind === 'tag' ?
      new SearchSelection(item.sourceId, 'tag', new MetadataTerm(item.value, item.label, item.namespace)) : null;
    this.text = next;
    this.open = false;
    this.source.reload([]);
    this.onSubmit(next, selection);
  }

  @Builder
  private Suggestions() {
    List({ space: 4 }) {
      if (this.error !== '') {
        ListItem() { Text(this.error).fontSize(12).fontColor(TEXT_SUB).padding(12) }
      }
      LazyForEach(this.source, (item: SearchSuggestion) => {
        ListItem() {
          Row({ space: 8 }) {
            SymbolGlyph(item.kind === 'history' ? $r('sys.symbol.clock') : $r('sys.symbol.label'))
              .fontSize(14)
              .fontColor([item.kind === 'history' ? TEXT_SUB : PRIMARY])
            Text(item.label)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(TEXT_MAIN)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (item.namespace !== '') {
              Text(item.namespace)
                .fontSize(10)
                .fontColor(PRIMARY)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(6)
                .backgroundColor(PRIMARY_SOFT)
            }
          }
          .width('100%')
          .height(38)
          .padding({ left: 12, right: 12 })
          .borderRadius(10)
          .backgroundColor(CARD)
          .onClick(() => this.choose(item))
        }
      }, (item: SearchSuggestion) => `${item.kind}_${item.sourceId}_${item.namespace}_${item.value}`)
    }
    .width(this.contentWidth)
    .constraintSize({ maxHeight: 260 })
    .padding(6)
    .scrollBar(BarState.Off)
  }

  build() {
    Search({ value: this.text, placeholder: this.placeholder })
      .width('100%')
      .height(40)
      .fontColor($r('sys.color.font_primary'))
      .backgroundColor(CARD)
      .border({ width: 0.5, color: DIVIDER })
      .searchButton(this.showSearchButton ? '搜索' : '', { autoDisable: true })
      .cancelButton({ style: CancelButtonStyle.INPUT })
      .onChange((value: string) => {
        this.text = value;
        this.selection = null;
        this.onEdit(value);
        this.schedule(value);
      })
      .onSubmit((value: string) => {
        this.generation++;
        this.clearTimer();
        this.open = false;
        this.onSubmit(value, this.selection);
      })
      .onAreaChange((_old: Area, area: Area) => { this.contentWidth = Number(area.width); })
      .bindPopup(this.open, {
        builder: this.Suggestions(), placement: Placement.Bottom, enableArrow: false,
        systemMaterial: IMMERSIVE_REGULAR_MATERIAL,
        onStateChange: (event: SuggestPopupState): void => { if (!event.isVisible) { this.open = false; } }
      })
  }
}
