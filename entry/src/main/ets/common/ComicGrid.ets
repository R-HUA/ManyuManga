import { AlbumLite } from '../models/Models';
import { ComicCard } from './ComicCard';
import { comicColumns } from './Theme';

/** 摘要与搜索结果使用相同的卡片行，末行保留左对齐。 */
@Component
export struct ComicGrid {
  @Prop items: Array<AlbumLite> = [];
  @Prop rows: number = 0;
  onOpen: (item: AlbumLite) => void = (_item: AlbumLite): void => {};
  @State contentWidth: number = 328;

  private grouped(): Array<Array<AlbumLite>> {
    const columns: number = comicColumns(this.contentWidth);
    const shown: Array<AlbumLite> = this.rows > 0 ? this.items.slice(0, columns * this.rows) : this.items;
    const result: Array<Array<AlbumLite>> = [];
    for (let i: number = 0; i < shown.length; i += columns) {
      result.push(shown.slice(i, i + columns));
    }
    return result;
  }

  private fillers(count: number): Array<number> {
    const result: Array<number> = [];
    for (let i: number = count; i < comicColumns(this.contentWidth); i++) { result.push(i); }
    return result;
  }

  build() {
    Column({ space: 16 }) {
      ForEach(this.grouped(), (row: Array<AlbumLite>) => {
        Row({ space: 12 }) {
          ForEach(row, (item: AlbumLite) => {
            ComicCard({ aid: item.id, coverUrl: item.coverUrl, title: item.title, author: item.author,
              badge: item.category, onCardClick: (): void => this.onOpen(item) })
              .layoutWeight(1)
          }, (item: AlbumLite) => item.id)
          ForEach(this.fillers(row.length), (index: number) => {
            Blank().layoutWeight(1)
          }, (index: number) => `${index}`)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (row: Array<AlbumLite>) => row.map((item: AlbumLite) => item.id).join('|'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onAreaChange((_old: Area, area: Area) => { this.contentWidth = Number(area.width); })
  }
}
