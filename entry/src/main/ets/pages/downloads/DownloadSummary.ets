import { TEXT_SUB } from '../../common/Theme';
import { DownloadTask, DownloadState } from '../../data/DownloadManager';

/** 一行队列汇总，替代原先的大卡片。 */
export function downloadSummaryText(tasks: Array<DownloadTask>): string {
  const count: (state: DownloadState) => number = (state: DownloadState): number => tasks.filter((t: DownloadTask): boolean => t.state === state).length;
  const parts: Array<string> = [];
  const running: number = count('running');
  const queued: number = count('queued');
  const paused: number = count('paused');
  const failed: number = count('failed') + count('canceled');
  if (running > 0) { parts.push(`下载中 ${running}`); }
  if (queued > 0) { parts.push(`等待 ${queued}`); }
  if (paused > 0) { parts.push(`暂停 ${paused}`); }
  if (failed > 0) { parts.push(`失败 ${failed}`); }
  parts.push(`已完成 ${count('done')}/${tasks.length} 部`);
  return parts.join(' · ');
}

@Component
export struct DownloadSummary {
  @Link tasks: Array<DownloadTask>;

  build() {
    Text(downloadSummaryText(this.tasks))
      .fontSize(12)
      .fontColor(TEXT_SUB)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .padding({ left: 20, right: 20, top: 6, bottom: 2 })
  }
}
