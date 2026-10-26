import { BasicDataSource } from '../../common/DataSource';
import { CARD, SUB_CARD, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
import { SearchSelection } from '../../common/Route';
import { MetadataTerm, errorMessage } from '../../models/Models';
import { SearchSuggestion, suggestLocal } from '../../data/SearchSuggest';

class SuggestSource extends BasicDataSource<SearchSuggestion> {
  reload(items: Array<SearchSuggestion>): void {
    this.setList(items);
  }
}

@Component
export struct SearchSuggestField {
  @Link text: string;
  @Prop sourceId: string = '';
  @Prop placeholder: string = '';
  @Prop selection: SearchSelection | null = null;
  onEdit: (text: string) => void = (_text: string): void => {};
  onSubmit: (text: string, selection: SearchSelection | null) => void =
    (_text: string, _selection: SearchSelection | null): void => {};
  @State open: boolean = false;
  @State error: string = '';
  private source: SuggestSource = new SuggestSource();
  private generation: number = 0;
  private timer: number = -1;

  aboutToDisappear(): void {
    this.generation++;
    this.clearTimer();
  }

  private clearTimer(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private schedule(value: string): void {
    this.clearTimer();
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
      this.open = false;
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

  build() {
    Column({ space: 6 }) {
      Search({ value: this.text, placeholder: this.placeholder })
        .width('100%')
        .height(40)
        .backgroundColor(CARD)
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
      if (this.error !== '') {
        Text(this.error).fontSize(12).fontColor(TEXT_SUB)
      }
      if (this.open) {
        List({ space: 6 }) {
          LazyForEach(this.source, (item: SearchSuggestion) => {
            ListItem() {
              Button(item.label, {
                type: ButtonType.Normal,
                buttonStyle: ButtonStyleMode.NORMAL
              })
                .fontSize(13)
                .fontColor(item.kind === 'history' ? TEXT_SUB : TEXT_MAIN)
                .backgroundColor(SUB_CARD)
                .width('100%')
                .height(36)
                .borderRadius(12)
                .onClick(() => {
                  this.choose(item);
                })
            }
          }, (item: SearchSuggestion) => `${item.kind}_${item.sourceId}_${item.label}`)
        }
        .width('100%')
        .constraintSize({ maxHeight: 220 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
