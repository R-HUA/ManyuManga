import { PRIMARY, ACCENT, CARD, SUB_CARD, DANGER, DANGER_SOFT, TEXT_MAIN, TEXT_SUB, CHIP_BG, DIVIDER, MASK_DARK, TAB_INACTIVE } from '../../common/Theme';
import { SourceCover } from '../../common/SourceCover';
import { DownloadTask, DownloadState } from '../../data/DownloadManager';

function formatDateTime(ms: number): string {
  if (ms <= 0) {
    return '';
  }
  const d: Date = new Date(ms);
  const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

@Component
export struct DownloadTaskCard {
  @Link selectMode: boolean;
  @Link selectedIds: Array<number>;
  private isSelected(id: number): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }
  toggleSelect: (id: number) => void = (id: number): void => {};
  onPause: (id: number) => Promise<void> = async (id: number): Promise<void> => {};
  onResume: (id: number) => Promise<void> = async (id: number): Promise<void> => {};
  onRetry: (t: DownloadTask) => Promise<void> = async (t: DownloadTask): Promise<void> => {};
  onOpenFile: (t: DownloadTask) => Promise<void> = async (t: DownloadTask): Promise<void> => {};
  onSaveTo: (t: DownloadTask) => Promise<void> = async (t: DownloadTask): Promise<void> => {};
  onDelete: (t: DownloadTask) => void = (t: DownloadTask): void => {};
  enterSelect: (id: number) => void = (id: number): void => {};
  @Prop item: DownloadTask = new DownloadTask();

  build() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        if (this.selectMode) {
          Checkbox()
            .select(this.isSelected(this.item.id))
            .selectedColor(PRIMARY)
            .onChange((value: boolean) => {
              this.toggleSelect(this.item.id);
            })
        }
        Column() {
          SourceCover({ url: this.item.cover, sourceKey: this.item.albumId, radius: 8 })
        }
        .width(50)
        .height(66)

        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text(this.item.title)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_MAIN)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(this.stateLabel(this.item.state))
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.badgeTextColor(this.item.state))
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.badgeBgColor(this.item.state))
              .borderRadius(8)
          }
          .width('100%')

          Text(this.statusText(this.item))
            .fontSize(11)
            .fontColor(TEXT_SUB)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.item.createdAt > 0) {
            Text(`创建于 ${formatDateTime(this.item.createdAt)}`)
              .fontSize(10)
              .fontColor(TAB_INACTIVE)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      if (this.item.state === 'running' || this.item.state === 'queued' || this.item.state === 'paused') {
        Progress({ value: this.progressValue(this.item), total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(5)
          .color(this.progressBarColor(this.item.state))
          .backgroundColor(SUB_CARD)
      }

      if (!this.selectMode) {
        Row({ space: 8 }) {
          if (this.item.state === 'queued' || this.item.state === 'running') {
            this.TaskActionPill('暂停', false, false, () => {
              this.onPause(this.item.id);
            })
          }
          if (this.item.state === 'paused') {
            this.TaskActionPill('继续下载', true, false, () => {
              this.onResume(this.item.id);
            })
          }
          if (this.item.state === 'failed' || this.item.state === 'canceled') {
            this.TaskActionPill('重试任务', true, false, () => {
              this.onRetry(this.item);
            })
          }
          if (this.item.state === 'done') {
            this.TaskActionPill('立即阅读', true, false, () => {
              this.onOpenFile(this.item);
            })
            this.TaskActionPill('导出 CBZ…', false, false, () => {
              this.onSaveTo(this.item);
            })
          }
          Blank()
          this.TaskActionPill('删除', false, true, () => {
            this.onDelete(this.item);
          })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(CARD)
    .borderRadius(18)
    .border({ width: 0.5, color: DIVIDER })
    .onClick(() => {
      if (this.selectMode) {
        this.toggleSelect(this.item.id);
      }
    })
    .gesture(LongPressGesture().onAction(() => {
      if (!this.selectMode) {
        this.enterSelect(this.item.id);
      }
    }))
  }

  @Builder
  private TaskActionPill(label: string, primary: boolean, danger: boolean, onTap: () => void) {
    Text(label)
      .fontSize(12)
      .fontWeight(primary ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(primary ? Color.White : (danger ? DANGER : TEXT_MAIN))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(primary ? PRIMARY : (danger ? DANGER_SOFT : SUB_CARD))
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
      .onClick(() => {
        onTap();
      })
  }

  private statusText(t: DownloadTask): string {
    if (t.state === 'queued') {
      return '排队中…';
    }
    if (t.state === 'running') {
      if (t.exporting) {
        return `导出中 ${t.exportDone}/${t.exportTotal}（生成 CBZ）`;
      }
      return `下载中 ${t.done}/${t.total}（失败 ${t.failedPages} 页）`;
    }
    if (t.state === 'paused') {
      return `已暂停（已完成 ${t.done}/${t.total} 页）`;
    }
    if (t.state === 'done') {
      return `已导出 CBZ：${t.savedTo}`;
    }
    if (t.state === 'canceled') {
      return '失败：已取消，可重试';
    }
    if (t.state === 'failed') {
      return `失败：${t.error === '' ? '未知错误' : t.error}`;
    }
    return '等待中';
  }

  private stateLabel(state: DownloadState): string {
    if (state === 'queued') {
      return '等待';
    }
    if (state === 'running') {
      return '下载中';
    }
    if (state === 'paused') {
      return '暂停';
    }
    if (state === 'done') {
      return '完成';
    }
    if (state === 'failed' || state === 'canceled') {
      return '失败';
    }
    return '等待';
  }

  private badgeTextColor(state: DownloadState): ResourceColor {
    if (state === 'running' || state === 'done' || state === 'failed' || state === 'canceled') {
      return Color.White;
    }
    if (state === 'queued') {
      return TEXT_SUB;
    }
    return TEXT_MAIN;
  }

  private badgeBgColor(state: DownloadState): ResourceColor {
    if (state === 'running') {
      return ACCENT;
    }
    if (state === 'done') {
      return PRIMARY;
    }
    if (state === 'failed' || state === 'canceled') {
      return MASK_DARK;
    }
    if (state === 'queued') {
      return CHIP_BG;
    }
    return DIVIDER;
  }

  private progressBarColor(state: DownloadState): ResourceColor {
    if (state === 'running') {
      return ACCENT;
    }
    return TAB_INACTIVE;
  }

  private progressValue(t: DownloadTask): number {
    if (t.exporting && t.exportTotal > 0) {
      return Math.min(100, t.exportDone / t.exportTotal * 100);
    }
    if (t.total > 0) {
      return Math.min(100, t.done / t.total * 100);
    }
    return 0;
  }
}
