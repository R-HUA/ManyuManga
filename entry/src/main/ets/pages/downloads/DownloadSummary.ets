import { PRIMARY, CARD, SUB_CARD, TEXT_MAIN, TEXT_SUB, DIVIDER } from '../../common/Theme';
import { DownloadTask, DownloadState } from '../../data/DownloadManager';

const DL_PAGE_CONCURRENCY: number = 3;

@Component
export struct DownloadSummary {
  @Link tasks: Array<DownloadTask>;

  build() {
    Column({ space: 10 }) {
      Row() {
        Text('队列总进度')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)
        Text(`已完成 ${this.countByState('done')} / ${this.tasks.length} 部`)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY)
      }
      .width('100%')

      Progress({ value: this.overallProgress(), total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(6)
        .color(PRIMARY)
        .backgroundColor(SUB_CARD)

      Row({ space: 8 }) {
        this.CountChip(`下载中 ${this.countByState('running')}`)
        this.CountChip(`等待 ${this.countByState('queued')}`)
        this.CountChip(`暂停 ${this.countByState('paused')}`)
        this.CountChip(`失败 ${this.countByState('failed')}`)
      }
      .width('100%')

      Row() {
        Text(`累计进度 ${this.totalDonePages()} / ${this.totalPagesCount()} 页`)
          .fontSize(11)
          .fontColor(TEXT_SUB)
        Text(`${DL_PAGE_CONCURRENCY} 线程并发下载`)
          .fontSize(11)
          .fontColor(TEXT_SUB)
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(CARD)
    .borderRadius(18)
    .border({ width: 0.5, color: DIVIDER })
    .margin({ left: 16, right: 16, top: 4, bottom: 4 })
  }

  @Builder
  private CountChip(label: string) {
    Text(label)
      .fontSize(11)
      .fontColor(TEXT_SUB)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(SUB_CARD)
      .borderRadius(12)
  }

  private countByState(state: DownloadState): number {
    let n: number = 0;
    for (const t of this.tasks) {
      if (t.state === state) {
        n++;
      }
    }
    return n;
  }

  private totalDonePages(): number {
    let n: number = 0;
    for (const t of this.tasks) {
      n += t.exporting && t.exportTotal > 0 ? t.exportDone : t.done;
    }
    return n;
  }

  private totalPagesCount(): number {
    let n: number = 0;
    for (const t of this.tasks) {
      n += t.exporting && t.exportTotal > 0 ? t.exportTotal : t.total;
    }
    return n;
  }

  private overallProgress(): number {
    const total: number = this.totalPagesCount();
    if (total <= 0) {
      return 0;
    }
    return Math.min(100, this.totalDonePages() / total * 100);
  }
}
