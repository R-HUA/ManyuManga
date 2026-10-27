import { MangaRouteParams, ROUTE_ALBUM } from '../../common/Route';
import { LibraryWork } from '../../data/Library';
import { Album, ReadingProgress } from '../../models/Models';
import { ComicCard } from '../../common/ComicCard';
import { PRIMARY } from '../../common/Theme';

@Component
export struct LibraryCoverCard {
  @Link selected: Array<string>;
  @Link progress: Array<ReadingProgress>;
  @Consume('navPathStack') stack: NavPathStack;
  @Prop work: LibraryWork = new LibraryWork();
  toggle: (work: LibraryWork) => void = (): void => {};

  private progressLabel(): string {
    const progress: ReadingProgress | undefined = this.progress.find((p: ReadingProgress): boolean =>
      this.work.albums.some((album: Album): boolean => album.id === p.aid) && p.totalPages > 0);
    return progress === undefined ? '' : `读至第 ${progress.page + 1} 页`;
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      ComicCard({ aid: this.work.activeKey, coverUrl: this.work.cover, title: this.work.title,
        author: this.work.author || (this.work.read ? '已读完' : '未读'), progressLabel: this.progressLabel(),
        badge: this.selected.length > 0 ? '' : this.work.newChapters > 0 ? `+${this.work.newChapters}` : this.work.albums.length > 1 ? `${this.work.albums.length} 源` : '',
        onCardClick: (): void => {
          if (this.selected.length > 0) { this.toggle(this.work); }
          else { this.stack.pushPathByName(ROUTE_ALBUM, { aid: this.work.activeKey } as MangaRouteParams); }
        } })
      if (this.selected.length > 0) {
        Stack() {
          if (this.selected.includes(this.work.id)) { SymbolGlyph($r('sys.symbol.checkmark')).fontSize(13).fontColor([Color.White]) }
        }.width(24).height(24).borderRadius(12).margin(7)
        .backgroundColor(this.selected.includes(this.work.id) ? PRIMARY : 'rgba(0,0,0,0.6)')
        .hitTestBehavior(HitTestMode.None)
      }
    }.width('100%').gesture(LongPressGesture().onAction(() => this.toggle(this.work)))
  }
}
