import { ComicCard } from '../../common/ComicCard';
import promptAction from '@ohos.promptAction';
import { EmptyView } from '../../common/Components';
import { BasicDataSource } from '../../common/DataSource';
import { comicColumns, BG, TEXT_MAIN, TEXT_SUB, DANGER, PRIMARY, ON_PRIMARY, OVERLAY_SCRIM } from '../../common/Theme';
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
  @State loading: boolean = true;
  @State loadError: string = '';
  @State @Watch('syncSelection') selected: Array<string> = [];
  @State @Watch('syncSelection') jobs: Array<ExportJob> = [];
  @State folderUri: string = '';
  @State @Watch('syncSelection') busy: boolean = false;
  @State toolbarItems: ToolBarOptions = new ToolBarOptions();
  private stopExport: boolean = false;
  private visible: boolean = false;
  private reloadVersion: number = 0;
  private reloadTimer: number = -1;
  private itemSource: BasicDataSource<OfflineItem> = new BasicDataSource<OfflineItem>();
  private lastExportFolder: string = '';
  private contentListener: () => void = (): void => {
    if (!this.visible || this.reloadTimer >= 0) { return; }
    this.reloadTimer = setTimeout((): void => {
      this.reloadTimer = -1;
      this.reload();
    }, 250);
  };
  private taskListener: (task: DownloadTask) => void = (task: DownloadTask): void => {
    if (task.state === 'done') { this.contentListener(); }
  };

  aboutToAppear(): void {
    this.visible = true;
    offlineStore.onChange(this.contentListener);
    downloadManager.onChange(this.taskListener);
    this.reload();
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
    this.toolbarItems = this.makeToolbar();
  }

  private allSelected(): boolean {
    return this.items.length > 0 && this.selected.length === this.items.length;
  }

  private makeToolbar(): ToolBarOptions {
    const some: boolean = this.selected.length > 0;
    return buildToolBar([
      new ToolAction(this.busy ? '取消导出' : '导出', $r('sys.symbol.share'), this.busy || some, false, (): void => {
        if (this.busy) {
          this.stopExport = true;
        } else {
          this.exportSelected(false);
        }
      }),
      new ToolAction('删除', $r('sys.symbol.trash'), !this.busy && some, true, (): void => { this.deleteSelected(); }),
      new ToolAction(this.allSelected() ? '取消全选' : '全选', $r('sys.symbol.checkmark_square_on_square'), this.items.length > 0, false, (): void => {
        this.selected = this.allSelected() ? [] : this.items.map((item: OfflineItem): string => item.albumId);
      }),
      new ToolAction('更多', $r('sys.symbol.ellipsis_circle'), !this.busy, false, (): void => { this.showMore(); })
    ]);
  }

  private showMore(): void {
    const single: boolean = this.selected.length === 1;
    const failed: boolean = this.jobs.some((job: ExportJob): boolean => job.state === 'failed');
    const options: promptAction.ActionMenuOptions = {
      title: '更多',
      buttons: [{ text: '打开导出目录', color: TEXT_MAIN }]
    };
    if (single) {
      options.buttons.push({ text: '单本导出', color: TEXT_MAIN });
    }
    if (failed) {
      options.buttons.push({ text: '重试失败项', color: TEXT_MAIN });
    }
    this.getUIContext().getPromptAction().showActionMenu(options).then((picked: promptAction.ActionMenuSuccessResponse): void => {
      if (picked.index === 0) {
        this.openFolder();
      } else if (single && picked.index === 1) {
        this.exportSingle();
      } else {
        this.exportSelected(true);
      }
    }).catch((): void => {});
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.stopExport = true;
    this.reloadVersion++;
    if (this.reloadTimer >= 0) {
      clearTimeout(this.reloadTimer);
      this.reloadTimer = -1;
    }
    offlineStore.offChange(this.contentListener);
    downloadManager.offChange(this.taskListener);
  }

  private async reload(): Promise<void> {
    if (this.reloadTimer >= 0) {
      clearTimeout(this.reloadTimer);
      this.reloadTimer = -1;
    }
    const version: number = ++this.reloadVersion;
    this.loading = true;
    this.loadError = '';
    try {
      await downloadManager.init();
      const folder: string = await recentExportFolder();
      const albums: Array<Album> = await offlineStore.albums();
      if (!this.visible || version !== this.reloadVersion) { return; }
      const tasks: Map<string, DownloadTask> = new Map<string, DownloadTask>();
      for (const task of downloadManager.tasks) {
        if (task.state === 'done' && task.savedTo !== '') { tasks.set(task.albumId, task); }
      }
      const next: Array<OfflineItem> = [];
      for (const album of albums) {
        const item: OfflineItem = new OfflineItem();
        item.albumId = album.id;
        item.title = album.name;
        item.author = album.author.map((term: MetadataTerm): string => term.label).join(' / ');
        item.cover = album.coverUrl;
        const task: DownloadTask | undefined = tasks.get(album.id);
        if (task !== undefined) {
          item.taskId = task.id;
          item.savedTo = task.savedTo;
        }
        next.push(item);
      }
      this.lastExportFolder = folder;
      this.items = next;
      this.itemSource.setList(next);
      this.totalCount = next.length;
      this.selected = this.selected.filter((id: string): boolean => next.some((item: OfflineItem): boolean => item.albumId === id));
    } catch (e) {
      if (this.visible && version === this.reloadVersion) { this.loadError = errorMessage(e as Error); }
    } finally {
      if (this.visible && version === this.reloadVersion) { this.loading = false; }
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
      if (this.loading && this.items.length === 0 && this.jobs.length === 0) {
        Column() {
          LoadingProgress().width(36).height(36).color(PRIMARY)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.loadError !== '') {
        Column() {
          EmptyView({ message: this.loadError, onRetry: (): void => { this.reload(); } })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.items.length === 0 && this.jobs.length === 0) {
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
          LazyForEach(this.itemSource, (item: OfflineItem) => {
            GridItem() {
              Stack({ alignContent: Alignment.TopEnd }) {
                ComicCard({
                  coverUrl: item.cover,
                  aid: item.albumId,
                  title: item.title,
                  author: item.author,
                  badge: '',
                  onCardClick: (): void => {
                    if (this.managing) {
                      this.toggle(item.albumId);
                    } else {
                      this.stack.pushPathByName(ROUTE_READER, { aid: item.albumId } as MangaRouteParams);
                    }
                  }
                })
                if (this.managing) {
                  Stack() {
                    if (this.selected.indexOf(item.albumId) >= 0) {
                      SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([ON_PRIMARY])
                    }
                  }
                  .width(24).height(24).borderRadius(12).margin(7)
                  .backgroundColor(this.selected.indexOf(item.albumId) >= 0 ? PRIMARY : OVERLAY_SCRIM)
                  .hitTestBehavior(HitTestMode.None)
                }
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
          }, (item: OfflineItem): string => JSON.stringify([item.albumId, item.title, item.author, item.cover]))
        }
        .columnsTemplate('1fr '.repeat(comicColumns(this.contentWidth)))
        .columnsGap(12)
        .rowsGap(12)
        .cachedCount(2)
        .onAreaChange((_old: Area, area: Area): void => { this.contentWidth = Number(area.width); })
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 4, bottom: this.managing ? 8 : 28 + this.bottomInset })

        if (this.managing) {
          SelectionToolBar({ items: this.toolbarItems, bottomInset: this.bottomInset })
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
            .fontSize(14)
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
