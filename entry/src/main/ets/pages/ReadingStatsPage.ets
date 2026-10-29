import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { readingActivity, ActivityStats } from '../data/ReadingActivity';
import { errorMessage } from '../models/Models';
import { HDS_TITLE_STYLE } from '../common/ImmersiveMaterials';
import { BG, CARD, TEXT_MAIN, TEXT_SUB, DANGER } from '../common/Theme';

@Component
export struct ReadingStatsPage {
  @StorageProp('activityVersion') @Watch('load') version: number = 0;
  @State private stats: ActivityStats = new ActivityStats();
  @State private error: string = '';

  aboutToAppear(): void { this.load(); }

  private async load(): Promise<void> {
    try { this.stats = await readingActivity.stats(); this.error = ''; }
    catch (e) { this.error = errorMessage(e as Error); }
  }

  private duration(): string {
    const seconds: number = Math.floor(this.stats.milliseconds / 1000);
    return seconds < 60 ? `${seconds} 秒` : seconds < 3600 ? `${Math.floor(seconds / 60)} 分钟` :
      `${Math.floor(seconds / 3600)} 小时 ${Math.floor(seconds % 3600 / 60)} 分钟`;
  }

  @Builder
  private Metric(label: string, value: string) {
    Column({ space: 10 }) {
      Text(label).fontSize(12).fontColor(TEXT_SUB)
      Text() {
        ForEach(value.split(' '), (part: string, index: number) => {
          Span(index % 2 === 0 ? part : ` ${part} `)
            .fontSize(index % 2 === 0 ? 24 : 12)
            .fontWeight(index % 2 === 0 ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(index % 2 === 0 ? TEXT_MAIN : TEXT_SUB)
        }, (part: string, index: number): string => `${index}_${part}`)
      }.fontFeature('"tnum" 1')
    }.width('100%').padding(14).backgroundColor(CARD).borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          GridRow({ columns: { xs: 1, sm: 3 }, gutter: { x: 10, y: 12 },
            breakpoints: { value: [`${360 * this.getUIContext().fp2px(1) / this.getUIContext().vp2px(1)}vp`],
              reference: BreakpointsReference.ComponentSize } }) {
            GridCol() { this.Metric('已读作品', `${this.stats.books.length} 部`) }
            GridCol() { this.Metric('已读页数', `${this.stats.pages.length} 页`) }
            GridCol() { this.Metric('阅读时长', this.duration()) }
          }
          if (this.error !== '') { Text(this.error).fontColor(DANGER).fontSize(13) }
        }.width('100%').padding(16)
      }.width('100%').height('100%').align(Alignment.TopStart)
    }.titleBar({ content: { title: { mainTitle: '阅读统计' } }, style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavDestinationTitleMode.MINI).backgroundColor(BG)
  }
}
