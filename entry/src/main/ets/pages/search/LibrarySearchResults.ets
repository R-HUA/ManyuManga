import { LibraryWork } from '../../data/Library';
import { AlbumLite } from '../../models/Models';
import { MangaRouteParams, ROUTE_ALBUM } from '../../common/Route';
import { ComicGrid } from '../../common/ComicGrid';
import { PRIMARY, TEXT_SUB } from '../../common/Theme';

@Component
export struct LibrarySearchResults {
  @Consume('navPathStack') stack: NavPathStack;
  @Prop works: Array<LibraryWork> = [];
  @Prop loading: boolean = false;

  private items(): Array<AlbumLite> {
    return this.works.map((work: LibraryWork): AlbumLite =>
      new AlbumLite(work.activeKey, work.title, work.author, work.cover));
  }

  build() {
    if (this.loading) {
      LoadingProgress().width(32).height(32).color(PRIMARY)
    } else if (this.works.length === 0) {
      Text('书架中没有匹配的作品').fontColor(TEXT_SUB).padding(24)
    } else {
      ComicGrid({ items: this.items(), onOpen: (item: AlbumLite): void => {
        this.stack.pushPathByName(ROUTE_ALBUM, { aid: item.id } as MangaRouteParams);
      } })
    }
  }
}
