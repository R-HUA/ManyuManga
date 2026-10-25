import { MangaRouteParams, ROUTE_ALBUM } from '../../common/Route';
import { LibraryWork } from '../../data/Library';
import { Album, ReadingProgress } from '../../models/Models';
import { SourceCover } from '../../common/SourceCover';
import { PRIMARY, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';

@Component
export struct LibraryCoverCard {
  @Link selected: Array<string>;
  @Link progress: Array<ReadingProgress>;
  private workProgress(work: LibraryWork): ReadingProgress | undefined {
    return this.progress.find((p: ReadingProgress) => work.albums.some((a: Album) => a.id === p.aid));
  }
  toggle: (work: LibraryWork) => void = (work: LibraryWork): void => {};
  @Consume('navPathStack') stack: NavPathStack;
  @Prop work: LibraryWork = new LibraryWork();

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        SourceCover({ url: this.work.cover, radius: 12 })

        // Top-left & Top-right overlay row
        Row() {
          if (this.work.newChapters > 0) {
            Text(`+${this.work.newChapters}`)
              .fontColor(Color.White)
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .backgroundColor(PRIMARY)
              .borderRadius(9)
          } else if (this.work.albums.length > 1) {
            Text(`${this.work.albums.length} 源`)
              .fontColor(Color.White)
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .backgroundColor('rgba(14, 17, 26, 0.78)')
              .borderRadius(9)
          }
          Blank()
          if (this.selected.length > 0) {
            Stack({ alignContent: Alignment.Center }) {
              if (this.selected.includes(this.work.id)) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(13)
                  .fontColor([Color.White])
              }
            }
            .width(24)
            .height(24)
            .borderRadius(12)
            .backgroundColor(this.selected.includes(this.work.id) ? PRIMARY : 'rgba(14, 17, 26, 0.65)')
            .border({ width: 1.5, color: this.selected.includes(this.work.id) ? PRIMARY : 'rgba(255,255,255,0.65)' })
          }
        }
        .width('100%')
        .padding(7)

        // Bottom reading status bar inside cover
        if (this.workProgress(this.work) !== undefined) {
          Column() {
            Blank()
            Row() {
              Text(`读至 P.${this.workProgress(this.work)!.page + 1}`)
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor('rgba(255,255,255,0.92)')
                .maxLines(1)
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 14, bottom: 6 })
            .linearGradient({
              angle: 180,
              colors: [['rgba(0,0,0,0.0)', 0.0], ['rgba(8,10,16,0.84)', 1.0]]
            })
          }
          .width('100%')
          .height('100%')
          .borderRadius(12)
          .clip(true)
          .hitTestBehavior(HitTestMode.None)
        }
      }
      .width('100%')
      .aspectRatio(0.75)

      Text(this.work.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_MAIN)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(this.work.author || (this.work.read ? '已读完' : '未读'))
        .fontSize(11)
        .fontColor(TEXT_SUB)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .onClick(() => {
      if (this.selected.length > 0) {
        this.toggle(this.work);
      } else {
        this.stack.pushPathByName(ROUTE_ALBUM, { aid: this.work.activeKey } as MangaRouteParams);
      }
    })
    .gesture(LongPressGesture().onAction(() => {
      this.toggle(this.work);
    }))
  }
}
