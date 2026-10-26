import { MangaRouteParams, ROUTE_READER } from '../../common/Route';
import { ReadingProgress } from '../../models/Models';
import { SourceCover } from '../../common/SourceCover';
import { IconCircleButton } from '../../common/Components';
import { CARD, PRIMARY, TEXT_MAIN, DIVIDER, TAB_BAR_HEIGHT } from '../../common/Theme';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

@Component
export struct LibraryContinueBanner {
  @Link progress: Array<ReadingProgress>;
  @Consume('navPathStack') stack: NavPathStack;
  @Link hideContinueBanner: boolean;
  @StorageProp('currentBreakpoint') breakpoint: string = 'sm';
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;

  build() {
    Row({ space: 12 }) {
      Column() {
        SourceCover({ url: this.progress[0].coverUrl, sourceKey: this.progress[0].aid, radius: 8 })
      }
      .width(36)
      .height(48)

      Column({ space: 3 }) {
        Text(`继续阅读 第 ${this.progress[0].page + 1}/${Math.max(1, this.progress[0].totalPages)} 页`)
          .fontColor(PRIMARY)
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
        Text(this.progress[0].title)
          .fontColor(TEXT_MAIN)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('续读')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .borderRadius(16)
        .backgroundColor(PRIMARY)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
        .onClick(() => {
          this.stack.pushPathByName(ROUTE_READER, { aid: this.progress[0].aid } as MangaRouteParams);
        })

      IconCircleButton({
        glyph: $r('sys.symbol.xmark'),
        btnSize: 28,
        iconSize: 13,
        onTap: (): void => {
          this.hideContinueBanner = true;
        }
      })
    }
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .margin({
      left: 16,
      right: 16,
      bottom: (this.breakpoint === 'lg' ? 16 : TAB_BAR_HEIGHT + 14) + this.bottomInset
    })
    .borderRadius(20)
    .backgroundColor(CARD)
    .border({ width: 0.5, color: DIVIDER })
  }
}
