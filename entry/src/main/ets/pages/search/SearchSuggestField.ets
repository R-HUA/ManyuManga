import { BasicDataSource } from '../../common/DataSource';
import { CARD, SUB_CARD, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
import { sourceApi } from '../../data/SourceApi';
import { sourceStore, SourceEntry } from '../../data/Sources';
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
  onEdit: (text: string) => void = (_text: string): void => {};
  onSubmit: (text: string) => void = (_text: string): void => {};
  @State open: boolean = false;
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
    const items: Array<SearchSuggestion> = await suggestLocal(value, this.sourceId);
    if (ticket !== this.generation) {
      return;
    }
    this.source.reload(items);
    this.open = items.length > 0;
  }

  private async choose(item: SearchSuggestion): Promise<void> {
    const ticket: number = ++this.generation;
    this.clearTimer();
    let next: string = item.kind === 'tag' ? item.label : item.value;
    if (item.kind === 'tag' && item.sourceId !== '') {
      try {
        const source: SourceEntry = await sourceStore.get(item.sourceId);
        if (ticket !== this.generation) {
          return;
        }
        next = sourceApi.searchExpression(source, item.namespace, item.value);
      } catch (_e) {
        if (ticket !== this.generation) {
          return;
        }
      }
    }
    this.text = next;
    this.open = false;
    this.source.reload([]);
    this.onSubmit(next);
  }

  build() {
    Column({ space: 6 }) {
      Search({ value: this.text, placeholder: this.placeholder })
        .width('100%')
        .height(40)
        .backgroundColor(CARD)
        .onChange((value: string) => {
          this.text = value;
          this.onEdit(value);
          this.schedule(value);
        })
        .onSubmit((value: string) => {
          this.generation++;
          this.clearTimer();
          this.open = false;
          this.onSubmit(value);
        })
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
