import { ComicCard } from '../../common/ComicCard';
import promptAction from '@ohos.promptAction';
import { EmptyView } from '../../common/Components';
import { comicColumns, BG, TEXT_MAIN, TEXT_SUB, DANGER } from '../../common/Theme';
import { ToolBarOptions } from '@kit.ArkUI';
import { SelectionToolBar, ToolAction, buildToolBar } from '../../common/SelectionToolBar';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';
import { ROUTE_READER, MangaRouteParams } from '../../common/Route';
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
  @State private contentWidth: number = 328;
  @Consume('navPathStack') stack: NavPathStack;
  /** 多选状态由父页面标题栏控制（“选择 / 已选 N 项 / 关闭”）。 */
  @Link @Watch('syncSelection') managing: boolean;
  @Link selectedCount: number;
  @Link totalCount: number;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  @State items: Array<OfflineItem> = [];
  @State @Watch('syncSelection') selected: Array<string> = [];
  @State @Watch('syncSelection') jobs: Array<ExportJob> = [];
  @State folderUri: string = '';
  @State @Watch('syncSelection') busy: boolean = false;
  @State toolbar: ToolBarOptions = new ToolBarOptions();
  private stopExport: boolean = false;
  private visible: boolean = false;
  private reloadVersion: number = 0;
  private lastExportFolder: string = '';
  private contentListener: () => void = (): void => {
    this.reload().catch((e: Error): void => { this.toast(errorMessage(e)); });
  };
  private taskListener: (task: DownloadTask) => void = (task: DownloadTask): void => {
    if (task.state === 'done') { this.contentListener(); }
  };

  aboutToAppear(): void {
    this.visible = true;
    offlineStore.onChange(this.contentListener);
    downloadManager.onChange(this.taskListener);
    this.initialize().catch((e: Error): void => { this.toast(errorMessage(e)); });
    this.syncSelection();
  }

  /** 结果提示统一用 Toast，不再在面板底部常驻一行文字（避免压住导航条）。 */
  private toast(message: string): void {
    if (message === '') { return; }
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
      // 页面已销毁时忽略
    }
  }

  private syncSelection(): void {
    if (!this.managing && this.selected.length > 0) {
      this.selected = [];
      return;
    }
    this.selectedCount = this.selected.length;
    this.totalCount = this.items.length;
    this.toolbar = this.makeToolbar();
  }

  private allSelected(): boolean {
    return this.items.length > 0 && this.selected.length === this.items.length;
  }

  private makeToolbar(): ToolBarOptions {
    const some: boolean = this.selected.length > 0;
    return buildToolBar([
      new ToolAction(this.busy ? '取消导出' : '导出', $r('sys.symbol.square_and_arrow_up'), this.busy || some, false, (): void => {
        if (this.busy) {
          this.stopExport = true;
        } else if (this.selected.length === 1) {
          this.exportSingle();
        } else {
          this.exportSelected(false);
        }
      }),
      new ToolAction('删除', $r('sys.symbol.trash'), !this.busy && some, true, (): void => { this.deleteSelected(); }),
      new ToolAction(this.allSelected() ? '取消全选' : '全选', $r('sys.symbol.checkmark_square_on_square'), this.items.length > 0, false, (): void => {
        this.selected = this.allSelected() ? [] : this.items.map((item: OfflineItem): string => item.albumId);
      }),
      new ToolAction('更多', $r('sys.symbol.ellipsis_circle'), true, false, (): void => { this.showMore(); })
    ]);
  }

  private showMore(): void {
    const failed: boolean = !this.busy && this.jobs.some((job: ExportJob): boolean => job.state === 'failed');
    this.getUIContext().getPromptAction().showActionMenu({
      title: '更多',
      buttons: [{ text: '重试失败项', color: failed ? TEXT_MAIN : TEXT_SUB }, { text: '打开导出目录', color: TEXT_MAIN }]
    }).then((picked: promptAction.ActionMenuSuccessResponse): void => {
      if (picked.index === 0) {
        if (failed) { this.exportSelected(true); } else { this.toast('没有失败项'); }
      } else if (picked.index === 1) {
        this.openFolder();
      }
    }).catch((): void => {});
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
      this.totalCount = next.length;
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
      this.toast(onlyFailed ? '没有失败项' : '请先选择已下载的漫画');
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
      this.toast(errorMessage(e as Error));
      this.busy = false;
      return;
    }
    if (!onlyFailed) {
      this.jobs = queue;
    }
    this.stopExport = false;
    this.busy = true;
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
        this.toast('已导出');
      }
    } catch (e) { this.toast(errorMessage(e as Error)); }
    finally { this.busy = false; }
  }

  private async deleteSelected(): Promise<void> {
    if (this.busy || this.selected.length === 0) { return; }
    this.getUIContext().getPromptAction().showDialog({
      title: '删除离线内容', message: `将删除所选 ${this.selected.length} 本漫画的离线页面和应用内漫画包。`,
      buttons: [{ text: '取消', color: TEXT_SUB }, { text: '删除', color: DANGER }]
    }).then(async (result: promptAction.ShowDialogSuccessResponse): Promise<void> => {
      if (result.index !== 1) { return; }
      this.busy = true;
      try {
        for (const id of this.selected.slice()) { await offlineStore.remove(id); }
        this.selected = [];
        await this.reload();
      } catch (e) { this.toast(errorMessage(e as Error)); }
      finally { this.busy = false; }
    }).catch((e: Error): void => { this.toast(errorMessage(e)); });
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
      this.toast('还没有导出记录');
      return;
    }
    try {
      await openExportFolder(folder);
    } catch (e) {
      this.toast(errorMessage(e as Error));
    }
  }

  build() {
    Column() {
      if (this.items.length === 0 && this.jobs.length === 0) {
        Column() {
          EmptyView({ message: '还没有已下载的漫画', showRetry: false, quiet: true })
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
                  badge: this.managing ? (this.selected.indexOf(item.albumId) >= 0 ? '已选' : '') : '',
                  onCardClick: (): void => {
                    if (this.managing) {
                      this.toggle(item.albumId);
                    } else {
                      this.stack.pushPathByName(ROUTE_READER, { aid: item.albumId } as MangaRouteParams);
                    }
                  }
                })
              }
              .width('100%')
              .gesture(
                LongPressGesture().onAction(() => {
                  if (!this.managing) {
                    this.managing = true;
                    this.selected = [item.albumId];
                  }
                })
              )
            }
          }, (item: OfflineItem) => item.albumId)
        }
        .columnsTemplate('1fr '.repeat(comicColumns(this.contentWidth)))
        .columnsGap(12)
        .rowsGap(12)
        .onAreaChange((_old: Area, area: Area): void => { this.contentWidth = Number(area.width); })
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 4, bottom: this.managing ? 8 : 28 + this.bottomInset })

        if (this.managing) {
          SelectionToolBar({ items: this.toolbar, bottomInset: this.bottomInset })
        }
      }
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
            .fontColor(job.state === 'failed' ? $r('sys.color.warning') : TEXT_SUB)
        }
        .width('100%')
      }, (job: ExportJob) => `${job.albumId}_${job.state}_${job.message}`)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 4 })
    .constraintSize({ maxHeight: 160 })
  }
}
