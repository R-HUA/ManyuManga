import { ComicCard } from '../../common/Components';

@Component
export struct RandomCardCell {
  @Prop aid: string = '';
  @Prop coverUrl: string = '';
  @Prop title: string = '';
  @Prop author: string = '';
  @Prop badge: string = '';
  @Prop delayMs: number = 0;
  onOpen: (aid: string) => void = () => {};
  @State appearOpacity: number = 0;

  build() {
    Column() {
      ComicCard({
        aid: this.aid,
        coverUrl: this.coverUrl,
        title: this.title,
        author: this.author,
        badge: this.badge,
        onCardClick: (): void => {
          this.onOpen(this.aid);
        }
      })
    }
    .width('100%')
    .opacity(this.appearOpacity)
    .onAppear(() => {
      this.getUIContext().animateTo({ duration: 300, delay: this.delayMs, curve: Curve.EaseOut }, () => {
        this.appearOpacity = 1;
      });
    })
  }
}
