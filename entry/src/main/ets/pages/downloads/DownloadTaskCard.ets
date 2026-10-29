import { PRIMARY, DANGER, SUB_CARD, TEXT_MAIN, TEXT_SUB, NEUTRAL_PROGRESS } from '../../common/Theme';
import { SourceCover } from '../../common/SourceCover';
import { IconCircleButton } from '../../common/Components';
import { DownloadTask, DownloadChapter } from '../../data/DownloadManager';

/** 任务整体进度（0–100）：导出阶段按导出进度，否则按页数。 */
export function taskProgress(t: DownloadTask): number {
  if (t.exporting && t.exportTotal > 0) {
    return Math.min(100, t.exportDone / t.exportTotal * 100);
  }
  if (t.total > 0) {
    return Math.min(100, t.done / t.total * 100);
  }
  return t.state === 'done' ? 100 : 0;
}

/** 任务状态一行文案。 */
export function taskStatusText(t: DownloadTask): string {
  const chapters: string = t.chapters.length > 0 ? `${t.chapters.length} 章 · ` : '';
  if (t.state === 'queued') {
    return `${chapters}排队中`;
  }
  if (t.state === 'running') {
    if (t.exporting) {
      return `${chapters}生成 CBZ ${t.exportDone}/${t.exportTotal}`;
    }
    return `${chapters}${t.done}/${t.total} 页${t.failedPages > 0 ? ` · 失败 ${t.failedPages} 页` : ''}`;
  }
  if (t.state === 'paused') {
    return `${chapters}已暂停 ${t.done}/${t.total} 页`;
  }
  if (t.state === 'done') {
    return `${chapters}已完成`;
  }
  if (t.state === 'canceled') {
    return '已取消';
  }
  return `失败：${t.error === '' ? '未知错误' : t.error}`;
}

/** 单章状态文案。 */
export function chapterStatusText(c: DownloadChapter, taskState: string): string {
  if (c.state === 'done') {
    return '已完成';
  }
  if (c.state === 'failed') {
    return c.error === '' ? '失败' : `失败：${c.error}`;
  }
  if (c.state === 'running' && taskState === 'running') {
    return c.total > 0 ? `${c.done}/${c.total}` : '获取目录…';
  }
  return taskState === 'paused' ? '已暂停' : '等待';
}

/** 下载任务分组头：封面 + 标题 + 整体进度，行尾为暂停/继续/重试/更多图标。 */
@Component
export struct DownloadTaskCard {
  @Link selectMode: boolean;
  @Link selectedIds: Array<number>;
  toggleSelect: (id: number) => void = (id: number): void => {};
  onPause: (id: number) => Promise<void> = async (id: number): Promise<void> => {};
  onResume: (id: number) => Promise<void> = async (id: number): Promise<void> => {};
  onRetry: (t: DownloadTask) => Promise<void> = async (t: DownloadTask): Promise<void> => {};
  onOpenFile: (t: DownloadTask) => Promise<void> = async (t: DownloadTask): Promise<void> => {};
  onSaveTo: (t: DownloadTask) => Promise<void> = async (t: DownloadTask): Promise<void> => {};
  onDelete: (t: DownloadTask) => void = (t: DownloadTask): void => {};
  enterSelect: (id: number) => void = (id: number): void => {};
  @Prop item: DownloadTask = new DownloadTask();

  private isSelected(id: number): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private failed(): boolean {
    return this.item.state === 'failed' || this.item.state === 'canceled';
  }

  @Builder
  private MoreMenu() {
    Menu() {
      if (this.item.state === 'done') {
        MenuItem({ content: '立即阅读' }).onClick(() => { this.onOpenFile(this.item); })
        MenuItem({ content: '导出 CBZ…' }).onClick(() => { this.onSaveTo(this.item); })
      }
      MenuItem({ content: '删除任务' }).onClick(() => { this.onDelete(this.item); })
    }
  }

  @Builder
  private Trailing() {
    if (this.item.state === 'queued' || this.item.state === 'running') {
      IconCircleButton({ glyph: $r('sys.symbol.pause'), btnSize: 40, iconSize: 18, onTap: (): void => {
        this.onPause(this.item.id);
      } }).accessibilityText('暂停')
    } else if (this.item.state === 'paused') {
      IconCircleButton({ glyph: $r('sys.symbol.play'), btnSize: 40, iconSize: 18, onTap: (): void => {
        this.onResume(this.item.id);
      } }).accessibilityText('继续下载')
    } else if (this.failed()) {
      IconCircleButton({ glyph: $r('sys.symbol.arrow_clockwise'), btnSize: 40, iconSize: 18, iconColor: DANGER,
        onTap: (): void => { this.onRetry(this.item); } }).accessibilityText('重试任务')
    }
    Row() {
      SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(18).fontColor([TEXT_SUB])
    }
    .width(40)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .accessibilityText('更多操作')
    .bindMenu(this.MoreMenu)
  }

  build() {
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
        SourceCover({ url: this.item.cover, sourceKey: this.item.albumId, radius: 6 })
      }
      .width(36)
      .height(48)

      Column({ space: 4 }) {
        Text(this.item.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_MAIN)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(taskStatusText(this.item))
          .fontSize(11)
          .fontColor(this.failed() ? DANGER : TEXT_SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.item.state !== 'done') {
          Progress({ value: taskProgress(this.item), total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(3)
            .color(this.failed() ? DANGER : NEUTRAL_PROGRESS)
            .backgroundColor(SUB_CARD)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (!this.selectMode) {
        this.Trailing()
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
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
}
