import { LibraryWork } from '../../data/Library';
import { MangaRouteParams, ROUTE_ALBUM } from '../../common/Route';
import { ComicCard } from '../../common/ComicCard';
import { PRIMARY, TEXT_SUB } from '../../common/Theme';

@Component
export struct LibrarySearchResults {
  @Consume('navPathStack') stack: NavPathStack;
  @Prop works: Array<LibraryWork> = [];
  @Prop loading: boolean = false;

  build() {
    if (this.loading) {
      LoadingProgress().width(32).height(32).color(PRIMARY)
    } else if (this.works.length === 0) {
      Text('书架中没有匹配的作品').fontColor(TEXT_SUB).padding(24)
    } else {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.works, (work: LibraryWork) => {
          Column() {
            ComicCard({ aid: work.activeKey, title: work.title, author: work.author, coverUrl: work.cover,
              onCardClick: (): void => {
                this.stack.pushPathByName(ROUTE_ALBUM, { aid: work.activeKey } as MangaRouteParams);
              } })
          }
          .width('33.33%')
          .padding({ left: 4, right: 4, bottom: 16 })
        }, (work: LibraryWork) => work.id)
      }
      .width('100%')
    }
  }
}
