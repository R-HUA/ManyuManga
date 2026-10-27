import { BasicDataSource } from '../../common/DataSource';
import { IMMERSIVE_CONTROL_MATERIAL, IMMERSIVE_REGULAR_MATERIAL } from '../../common/ImmersiveMaterials';
import { TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
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
    }, 200);
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
          Button(item.label, { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL })
            .fontSize(14)
            .fontColor(item.kind === 'history' ? TEXT_SUB : TEXT_MAIN)
            .backgroundColor(Color.Transparent)
            .width('100%')
            .height(44)
            .onClick(() => this.choose(item))
        }
      }, (item: SearchSuggestion) => `${item.kind}_${item.sourceId}_${item.namespace}_${item.value}`)
    }
    .width(this.contentWidth)
    .constraintSize({ maxHeight: 264 })
    .padding(8)
    .scrollBar(BarState.Off)
  }

  build() {
      Search({ value: this.text, placeholder: this.placeholder })
        .width('100%')
        .height(48)
        .fontColor($r('sys.color.font_primary'))
        .backgroundColor(Color.Transparent)
        .systemMaterial(IMMERSIVE_CONTROL_MATERIAL)
        .searchButton('搜索', { autoDisable: true })
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
