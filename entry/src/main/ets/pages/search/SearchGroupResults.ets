import { ComicGrid } from '../../common/ComicGrid';
import { AlbumLite } from '../../models/Models';
import { SourceEntry } from '../../data/Sources';
import { SourceSearchOptions } from '../../data/source/SourceContracts';
import { DANGER, PRIMARY, SUB_CARD, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';

/** 异步结果逐字段更新，列表项必须观察同一个分组实例。 */
@Observed
export class SearchGroup {
  source: SourceEntry = new SourceEntry();
  items: Array<AlbumLite> = [];
  page: number = 0;
  remoteCursor: string = '';
  more: boolean = false;
  loading: boolean = true;
  error: string = '';
  query: string = '';
  options: SourceSearchOptions = new SourceSearchOptions();
}

@Component
export struct SearchGroupResults {
  @ObjectLink group: SearchGroup;
  @Prop summary: boolean = false;
  onOpen: (item: AlbumLite) => void = (_item: AlbumLite): void => {};
  onViewAll: () => void = (): void => {};
  onRetry: () => void = (): void => {};

  build() {
    Column({ space: 12 }) {
      Row() {
        Text(this.group.source.name).fontSize(18).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN).layoutWeight(1)
        if (this.group.loading) { LoadingProgress().width(22).height(22) }
        if (this.summary && this.group.items.length > 0) {
          Button('查看全部', { buttonStyle: ButtonStyleMode.NORMAL }).fontColor(PRIMARY).backgroundColor(SUB_CARD)
            .onClick(this.onViewAll)
        }
      }.width('100%')
      if (this.group.error !== '') {
        Text(this.group.error).fontColor(DANGER).fontSize(13).width('100%')
        Button('重试', { buttonStyle: ButtonStyleMode.NORMAL }).onClick(this.onRetry)
      } else if (!this.group.loading && this.group.items.length === 0) {
        Text('没有搜索结果').fontColor(TEXT_SUB).fontSize(13).width('100%')
      }
      ComicGrid({ items: this.group.items, rows: this.summary ? 2 : 0, onOpen: this.onOpen })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
