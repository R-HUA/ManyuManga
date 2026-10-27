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
    Row() {
      Text(label).fontSize(16).fontColor(TEXT_SUB).layoutWeight(1)
      Text(value).fontSize(24).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN)
    }.width('100%').padding(20).backgroundColor(CARD).borderRadius(16)
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          this.Metric('已读作品', `${this.stats.books.length} 部`)
          this.Metric('已读页数', `${this.stats.pages.length} 页`)
          this.Metric('阅读时长', this.duration())
          if (this.error !== '') { Text(this.error).fontColor(DANGER).fontSize(13) }
        }.width('100%').padding(16)
      }.width('100%').height('100%').align(Alignment.TopStart)
    }.titleBar({ content: { title: { mainTitle: '阅读统计' } }, style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavDestinationTitleMode.MINI).backgroundColor(BG)
  }
}
