import { ComicCard } from '../../common/ComicCard';
import promptAction from '@ohos.promptAction';
import { EmptyView } from '../../common/Components';
import { BG, CARD, PRIMARY, PRIMARY_SOFT, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
import { Album, MetadataTerm, errorMessage } from '../../models/Models';
import { downloadManager, DownloadTask } from '../../data/DownloadManager';
import { offlineStore } from '../../data/OfflineStore';
import {
  assertFolderWritable,
  exportTo,
  ExportJob,
  openExportFolder,
  pickExportFolder,
  recentExportFolder,
  saveExportJob,
  uniqueChildUri
} from '../../data/BatchExport';

class OfflineItem {
  albumId: string = '';
  title: string = '';
  author: string = '';
  cover: string = '';
  taskId: number = 0;
  savedTo: string = '';
}

@Component
export struct DownloadedPane {
  @State items: Array<OfflineItem> = [];
  @State selected: Array<string> = [];
  @State jobs: Array<ExportJob> = [];
  @State folderUri: string = '';
  @State busy: boolean = false;
  @State note: string = '';
  private stopExport: boolean = false;
  private visible: boolean = false;
  private reloadVersion: number = 0;
  private lastExportFolder: string = '';
  private contentListener: () => void = (): void => {
    this.reload().catch((e: Error): void => { this.note = errorMessage(e); });
  };
  private taskListener: (task: DownloadTask) => void = (task: DownloadTask): void => {
    if (task.state === 'done') { this.contentListener(); }
  };

  aboutToAppear(): void {
    this.visible = true;
    offlineStore.onChange(this.contentListener);
    downloadManager.onChange(this.taskListener);
    this.initialize().catch((e: Error): void => { this.note = errorMessage(e); });
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.stopExport = true;
    this.reloadVersion++;
    offlineStore.offChange(this.contentListener);
    downloadManager.offChange(this.taskListener);
  }

  private async initialize(): Promise<void> {
    await downloadManager.init();
    this.lastExportFolder = await recentExportFolder();
    await this.reload();
  }

  private async reload(): Promise<void> {
    const version: number = ++this.reloadVersion;
    await downloadManager.init();
    const ids: Array<string> = await offlineStore.albumIds();
    const next: Array<OfflineItem> = [];
    for (const id of ids) {
      const album: Album | null = await offlineStore.album(id);
      if (album === null) {
        continue;
      }
      const item: OfflineItem = new OfflineItem();
      item.albumId = album.id;
      item.title = album.name;
      item.author = album.author.map((term: MetadataTerm): string => term.label).join(' / ');
      item.cover = album.coverUrl;
      for (const task of downloadManager.tasks) {
        if (task.albumId === album.id && task.state === 'done' && task.savedTo !== '') {
          item.taskId = task.id;
          item.savedTo = task.savedTo;
        }
      }
      next.push(item);
    }
    if (this.visible && version === this.reloadVersion) {
      this.items = next;
      this.selected = this.selected.filter((id: string): boolean => next.some((item: OfflineItem): boolean => item.albumId === id));
    }
  }

  private toggle(id: string): void {
    if (this.selected.indexOf(id) >= 0) {
      this.selected = this.selected.filter((value: string): boolean => value !== id);
    } else {
      const next: Array<string> = this.selected.slice();
      next.push(id);
      this.selected = next;
    }
  }

  private async exportSelected(onlyFailed: boolean): Promise<void> {
    if (this.busy) {
      return;
    }
    const queue: Array<ExportJob> = onlyFailed
      ? this.jobs.filter((job: ExportJob): boolean => job.state === 'failed')
      : this.jobsForSelection();
    if (queue.length === 0) {
      this.note = onlyFailed ? '没有失败项' : '请先选择已下载的漫画';
      return;
    }
    this.busy = true;
    try {
      if (this.folderUri === '') {
        const uri: string = await pickExportFolder();
        if (uri === '') {
          this.busy = false;
          return;
        }
        await assertFolderWritable(uri);
        this.folderUri = uri;
      } else {
        await assertFolderWritable(this.folderUri);
      }
    } catch (e) {
      this.note = errorMessage(e as Error);
      this.busy = false;
      return;
    }
    if (!onlyFailed) {
      this.jobs = queue;
    }
    this.stopExport = false;
    this.busy = true;
    this.note = '';
    for (const job of queue) {
      if (this.stopExport) {
        break;
      }
      job.state = 'running';
      job.message = '正在导出';
      this.jobs = this.jobs.slice();
      try {
        const dest: string = uniqueChildUri(this.folderUri, job.title);
        await exportTo(job, dest, (): void => {
          if (this.stopExport || !this.visible) { throw new Error('已取消导出'); }
        });
        this.lastExportFolder = this.folderUri;
        job.state = 'done';
        job.message = '已导出';
      } catch (e) {
        job.state = this.stopExport ? 'canceled' : 'failed';
        job.message = errorMessage(e as Error);
      }
      this.jobs = this.jobs.slice();
    }
    this.busy = false;
  }

  private async exportSingle(): Promise<void> {
    const queue: Array<ExportJob> = this.jobsForSelection();
    if (this.busy || queue.length !== 1) { return; }
    this.stopExport = false;
    this.busy = true;
    try {
      if (await saveExportJob(queue[0], (): void => {
        if (this.stopExport || !this.visible) { throw new Error('已取消导出'); }
      })) {
        this.lastExportFolder = await recentExportFolder();
        this.note = '已导出';
      }
    } catch (e) { this.note = errorMessage(e as Error); }
    finally { this.busy = false; }
  }

  private async deleteSelected(): Promise<void> {
    if (this.busy || this.selected.length === 0) { return; }
    this.getUIContext().getPromptAction().showDialog({
      title: '删除离线内容', message: `将删除所选 ${this.selected.length} 本漫画的离线页面和应用内漫画包。`,
      buttons: [{ text: '取消', color: TEXT_SUB }, { text: '删除', color: PRIMARY }]
    }).then(async (result: promptAction.ShowDialogSuccessResponse): Promise<void> => {
      if (result.index !== 1) { return; }
      this.busy = true;
      try {
        for (const id of this.selected.slice()) { await offlineStore.remove(id); }
        this.selected = [];
        await this.reload();
      } catch (e) { this.note = errorMessage(e as Error); }
      finally { this.busy = false; }
    }).catch((e: Error): void => { this.note = errorMessage(e); });
  }

  private jobsForSelection(): Array<ExportJob> {
    const jobs: Array<ExportJob> = [];
    for (const item of this.items) {
      if (this.selected.indexOf(item.albumId) < 0) {
        continue;
      }
      const job: ExportJob = new ExportJob();
      job.albumId = item.albumId;
      job.title = item.title;
      job.taskId = item.taskId;
      job.sourcePath = item.savedTo;
      jobs.push(job);
    }
    return jobs;
  }

  private async openFolder(): Promise<void> {
    const folder: string = this.lastExportFolder || this.folderUri;
    if (folder === '') {
      this.note = '还没有导出记录';
      return;
    }
    try {
      await openExportFolder(folder);
    } catch (e) {
      this.note = errorMessage(e as Error);
    }
  }

  build() {
    Column() {
      if (this.items.length === 0 && this.jobs.length === 0) {
        Column() {
          EmptyView({ message: '还没有已下载的漫画', showRetry: false })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        if (this.jobs.length > 0) {
          this.ExportList()
        }
        Grid() {
          ForEach(this.items, (item: OfflineItem) => {
            GridItem() {
              Column() {
                ComicCard({
                  coverUrl: item.cover,
                  aid: item.albumId,
                  title: item.title,
                  author: item.author,
                  badge: this.selected.indexOf(item.albumId) >= 0 ? '已选' : '',
                  onCardClick: (): void => {
                    this.toggle(item.albumId);
                  }
                })
              }
              .width('100%')
            }
          }, (item: OfflineItem) => item.albumId)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(12)
        .rowsGap(12)
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        this.ExportBar()
      }
      if (this.note !== '') { Text(this.note).fontSize(12).fontColor(TEXT_SUB).padding(8) }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
  }

  @Builder
  private ExportList() {
    Column({ space: 6 }) {
      ForEach(this.jobs, (job: ExportJob) => {
        Row() {
          Text(job.title)
            .fontSize(13)
            .fontColor(TEXT_MAIN)
            .maxLines(1)
            .layoutWeight(1)
          Text(job.state === 'done' ? '完成' : job.state === 'failed' ? '失败' : job.state === 'canceled' ? '已取消' : job.state === 'running' ? '导出中' : '等待')
            .fontSize(12)
            .fontColor(job.state === 'failed' ? Color.Red : TEXT_SUB)
        }
        .width('100%')
      }, (job: ExportJob) => `${job.albumId}_${job.state}_${job.message}`)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 4 })
    .constraintSize({ maxHeight: 160 })
  }

  @Builder
  private ExportBar() {
    Row({ space: 8 }) {
      Button(this.busy ? '导出中' : '导出所选', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
        .fontColor(Color.White)
        .backgroundColor(PRIMARY)
        .enabled(!this.busy)
        .onClick(() => { this.exportSelected(false); })
      Button('重试失败', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
        .fontColor(PRIMARY)
        .backgroundColor(PRIMARY_SOFT)
        .enabled(!this.busy && this.jobs.some((job: ExportJob): boolean => job.state === 'failed'))
        .onClick(() => { this.exportSelected(true); })
      Button(this.busy ? '取消' : '打开目录', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
        .fontColor(TEXT_MAIN)
        .backgroundColor(CARD)
        .onClick(() => {
          if (this.busy) {
            this.stopExport = true;
          } else {
            this.openFolder();
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 12 })
    Row({ space: 8 }) {
      Button('单本导出', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
        .fontColor(PRIMARY)
        .backgroundColor(PRIMARY_SOFT)
        .enabled(!this.busy && this.selected.length === 1)
        .onClick(() => { this.exportSingle(); })
      Button('删除离线内容', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
        .fontColor(TEXT_SUB)
        .backgroundColor(CARD)
        .enabled(!this.busy && this.selected.length > 0)
        .onClick(() => { this.deleteSelected(); })
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 12 })
  }
}
