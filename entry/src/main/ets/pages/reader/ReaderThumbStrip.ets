import { BasicDataSource } from '../../common/DataSource';
import { PRIMARY } from '../../common/Theme';
import { PageThumbItem } from './ReaderImageItem';

class ThumbRef {
  index: number = 0;
  filename: string = '';
}

class ThumbSource extends BasicDataSource<ThumbRef> {
  reload(pages: Array<string>): void {
    const items: Array<ThumbRef> = [];
    for (let i: number = 0; i < pages.length; i++) {
      const item: ThumbRef = new ThumbRef();
      item.index = i;
      item.filename = pages[i];
      items.push(item);
    }
    this.setList(items);
  }
}

@Component
export struct ReaderThumbStrip {
  @Prop @Watch('follow') pages: Array<string> = [];
  @Prop @Watch('follow') currentPage: number = 0;
  @Prop photoId: string = '';
  @Prop scrambleId: number = 0;
  jumpToPage: (page: number) => void = (page: number): void => {};
  private scroller: Scroller = new Scroller();
  private source: ThumbSource = new ThumbSource();

  aboutToAppear(): void {
    this.follow();
  }

  follow(): void {
    this.source.reload(this.pages);
    const index: number = Math.max(0, Math.min(this.currentPage, Math.max(this.pages.length - 1, 0)));
    this.scroller.scrollToIndex(index, true);
  }

  build() {
    List({ scroller: this.scroller, space: 8 }) {
      LazyForEach(this.source, (item: ThumbRef) => {
        ListItem() {
          Column() {
            PageThumbItem({
              photoId: this.photoId,
              filename: item.filename,
              scrambleId: this.scrambleId
            })
          }
          .width(48)
          .aspectRatio(0.72)
          .borderRadius(6)
          .clip(true)
          .border({
            width: item.index === this.currentPage ? 2 : 0,
            color: PRIMARY
          })
          .onClick(() => {
            this.jumpToPage(item.index);
          })
        }
      }, (item: ThumbRef) => `${item.index}_${item.filename}`)
    }
    .listDirection(Axis.Horizontal)
    .height(76)
    .width('100%')
    .scrollBar(BarState.Off)
    .alignListItem(ListItemAlign.Center)
  }
}
