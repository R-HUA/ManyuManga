import { saveDownload } from './downloads/DownloadFileExporter';
import { DownloadedPane } from './downloads/DownloadedPane';
import { BasicDataSource } from '../common/DataSource';
import { DownloadTaskCard } from './downloads/DownloadTaskCard';
import { DownloadSummary } from './downloads/DownloadSummary';
import { PRIMARY, PRIMARY_SOFT, BG, CARD, SUB_CARD, DANGER, DANGER_SOFT, COVER_R, CHIP_R, TEXT_MAIN, TEXT_SUB, DIVIDER, MASK_DARK } from '../common/Theme';
import { EmptyView, IconCircleButton } from '../common/Components';
import { errorMessage } from '../models/Models';
import { downloadManager, DownloadTask } from '../data/DownloadManager';
import { ROUTE_READER, MangaRouteParams } from '../common/Route';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';
/* ===== 任务列表懒加载数据源 ===== */

class TaskDataSource extends BasicDataSource<DownloadTask> {
  private rows: Array<DownloadTask> = [];
  private watchers: Array<DataChangeListener> = [];
  totalCount(): number { return this.rows.length; }
  getData(index: number): DownloadTask { return this.rows[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.watchers.includes(listener)) { this.watchers.push(listener); }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.watchers = this.watchers.filter((item: DataChangeListener): boolean => item !== listener);
  }
  reload(items: Array<DownloadTask>): void {
    this.rows = items.slice();
    for (const listener of this.watchers) { listener.onDataReloaded(); }
  }
  replace(task: DownloadTask): boolean {
    const index: number = this.rows.findIndex((item: DownloadTask): boolean => item.id === task.id);
    if (index < 0) { return false; }
    this.rows[index] = task;
    for (const listener of this.watchers) { listener.onDataChange(index); }
    return true;
  }
}

@Component
export struct DownloadsPage {
  @Consume('navPathStack') navPathStack: NavPathStack;

  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 38;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 16;

  /* ===== 页面状态（四态：骨架/空/错误重试；任务列表实时刷新无分页） ===== */
  @State loading: boolean = true;
  @State loadError: string = '';
  @State skelAlpha: number = 1.0;

  /* ===== 数据与选择态 ===== */
  @State tasks: Array<DownloadTask> = [];
  @State section: string = 'offline';
  @State selectMode: boolean = false;
  @State selectedIds: Array<number> = [];
  @State pendingDeleteIds: Array<number> = [];
  @State deleteFileToo: boolean = false;

  private initialized: boolean = false;
  private taskDS: TaskDataSource = new TaskDataSource();
  private changeListener: (task: DownloadTask) => void = (task: DownloadTask): void => {
    const present: boolean = downloadManager.tasks.some((item: DownloadTask): boolean => item.id === task.id);
    if (!present || !this.taskDS.replace(task)) { this.refreshTasks(); return; }
    this.tasks = this.tasks.map((item: DownloadTask): DownloadTask => item.id === task.id ? task : item);
  };

  aboutToAppear(): void {
    downloadManager.onChange(this.changeListener);
    this.initData();
  }

  aboutToDisappear(): void {
    downloadManager.offChange(this.changeListener);
  }

  /* ===== 数据加载与刷新 ===== */

  private async initData(): Promise<void> {
    this.loading = !this.initialized;
    try {
      await downloadManager.init();
      this.refreshTasks();
      this.loadError = '';
      this.initialized = true;
    } catch (e) {
      this.loadError = errorMessage(e as Error);
    } finally {
      this.loading = false;
    }
  }

  private refreshTasks(): void {
    this.tasks = downloadManager.tasks.slice();
    this.taskDS.reload(this.tasks);
  }

  /* ===== 多选 ===== */

  private isSelected(id: number): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private toggleSelect(id: number): void {
    if (this.isSelected(id)) {
      this.selectedIds = this.selectedIds.filter((i: number): boolean => i !== id);
    } else {
      const arr: Array<number> = this.selectedIds.slice();
      arr.push(id);
      this.selectedIds = arr;
    }
  }

  private allSelected(): boolean {
    return this.tasks.length > 0 && this.selectedIds.length === this.tasks.length;
  }

  private toggleSelectAll(): void {
    if (this.allSelected()) {
      this.selectedIds = [];
      return;
    }
    const ids: Array<number> = [];
    for (const t of this.tasks) {
      ids.push(t.id);
    }
    this.selectedIds = ids;
  }

  private enterSelect(id: number): void {
    this.selectMode = true;
    this.selectedIds = [id];
  }

  private exitSelect(): void {
    this.selectMode = false;
    this.selectedIds = [];
  }

  /* ===== 汇总统计（总进度头部） ===== */

  /* ===== 单任务操作 ===== */

  private async onPause(id: number): Promise<void> {
    try {
      await downloadManager.pause(id);
    } catch (e) {
      this.showToast(`操作失败：${errorMessage(e as Error)}`);
    }
  }

  private async onResume(id: number): Promise<void> {
    try {
      await downloadManager.resume(id);
    } catch (e) {
      this.showToast(`操作失败：${errorMessage(e as Error)}`);
    }
  }

  /** 使用同一任务续传，保留已完成页面。 */
  private async onRetry(t: DownloadTask): Promise<void> {
    try {
      this.showToast('正在重新入队…');
      await downloadManager.retry(t.id);
      this.showToast('已重新加入下载队列');
    } catch (e) {
      this.showToast(`重试失败：${errorMessage(e as Error)}`);
    }
  }

  /* ===== 已完成任务：打开 / 保存到用户所选位置 ===== */

  private async onOpenFile(t: DownloadTask): Promise<void> {
    this.navPathStack.pushPathByName(ROUTE_READER, { aid: t.albumId } as MangaRouteParams);
  }

    /** 保存到用户所选位置：DocumentViewPicker 保存选择器 + 分块拷贝到所选 URI */
  private async onSaveTo(t: DownloadTask): Promise<void> {
    try {
      if (await saveDownload(t)) { this.showToast('已保存到所选位置'); }
    } catch (e) { this.showToast(`保存失败：${errorMessage(e as Error)}`); }
  }

  /* ===== 删除 ===== */

  private onDelete(t: DownloadTask): void {
    this.deleteFileToo = false;
    this.pendingDeleteIds = [t.id];
  }

  private onDeleteSelected(): void {
    this.deleteFileToo = false;
    this.pendingDeleteIds = this.selectedIds.slice();
  }

  private pendingHasActive(): boolean {
    for (const id of this.pendingDeleteIds) {
      for (const t of this.tasks) {
        if (t.id === id && (t.state === 'running' || t.state === 'queued')) {
          return true;
        }
      }
    }
    return false;
  }

  private async doDelete(): Promise<void> {
    const ids: Array<number> = this.pendingDeleteIds.slice();
    const delFile: boolean = this.deleteFileToo;
    this.pendingDeleteIds = [];
    for (const id of ids) {
      await downloadManager.removeTask(id, delFile);
    }
    if (this.selectMode) {
      this.exitSelect();
    }
    this.refreshTasks();
    this.showToast(`已删除 ${ids.length} 个任务`);
  }

  /* ===== 展示辅助 ===== */

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000, bottom: '35%' });
    } catch (e) {
      // 提示失败可忽略
    }
  }

  /* ===== UI 构建 ===== */

  /** 评审 Step2：自绘顶栏（返回 + 标题），替代系统 .title()——全屏布局下需自行避让状态栏 */
  @Builder
  private TopBar() {
    Row({ space: 10 }) {
      IconCircleButton({
        glyph: $r('sys.symbol.chevron_left'),
        onTap: (): void => {
          this.navPathStack.pop();
        }
      })
      Text('离线下载与 CBZ 导出')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .layoutWeight(1)
      if (this.section === 'tasks' && this.tasks.length > 0) {
        Text(this.selectMode ? '完成' : '批量管理')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.selectMode ? Color.White : PRIMARY)
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .borderRadius(16)
          .backgroundColor(this.selectMode ? PRIMARY : PRIMARY_SOFT)
          .onClick(() => {
            if (this.selectMode) {
              this.exitSelect();
            } else {
              this.selectMode = true;
              this.selectedIds = [];
            }
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topInset + 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          this.TopBar()
          this.SectionBar()

          if (this.section === 'offline') {
            DownloadedPane()
              .layoutWeight(1)
              .width('100%')
          } else if (this.loading) {
            this.SkeletonList()
          } else if (this.loadError !== '') {
            Column() {
              EmptyView({
                message: `加载失败：${this.loadError}`,
                showRetry: true,
                onRetry: (): void => {
                  this.initData();
                }
              })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.tasks.length === 0) {
            Column() {
              EmptyView({ message: '还没有下载任务', showRetry: false })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            if (this.selectMode) {
              this.SelectBar()
            } else {
              this.SummaryHeader()
            }

            List({ space: 10 }) {
              LazyForEach(this.taskDS, (item: DownloadTask) => {
                ListItem() {
                  this.TaskRow(item)
                }
              }, (item: DownloadTask) => `task_${item.id}`)
            }
            .width('100%')
            .layoutWeight(1)
            .cachedCount(4)
            .scrollBar(BarState.Off)
            .padding({ left: 16, right: 16, top: 8, bottom: (this.selectMode ? 12 : 28 + this.bottomInset) })

            if (this.selectMode) {
              this.SelectBottomBar()
            }
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(BG)

        if (this.pendingDeleteIds.length > 0) {
          this.DeleteOverlay()
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(BG)
  }

  @Builder
  private SectionBar() {
    Row({ space: 8 }) {
      Button('已下载', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.section === 'offline' ? Color.White : PRIMARY)
        .backgroundColor(this.section === 'offline' ? PRIMARY : PRIMARY_SOFT)
        .onClick(() => { this.section = 'offline'; })
      Button('下载任务', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.section === 'tasks' ? Color.White : PRIMARY)
        .backgroundColor(this.section === 'tasks' ? PRIMARY : PRIMARY_SOFT)
        .onClick(() => { this.section = 'tasks'; })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 4 })
  }

  /** 首载骨架（脉冲呼吸占位行） */
  @Builder
  private SkeletonList() {
    Column({ space: 16 }) {
      ForEach([0, 1, 2, 3], (i: number) => {
        Row({ space: 12 }) {
          Column()
            .width(52)
            .height(68)
            .borderRadius(COVER_R)
            .backgroundColor(DIVIDER)
            .opacity(this.skelAlpha)
          Column({ space: 8 }) {
            Column()
              .height(14)
              .width('72%')
              .borderRadius(CHIP_R)
              .backgroundColor(DIVIDER)
              .opacity(this.skelAlpha)
            Column()
              .height(10)
              .width('48%')
              .borderRadius(CHIP_R)
              .backgroundColor(DIVIDER)
              .opacity(this.skelAlpha)
            Column()
              .height(8)
              .width('36%')
              .borderRadius(CHIP_R)
              .backgroundColor(DIVIDER)
              .opacity(this.skelAlpha)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
      }, (i: number) => `sk_${i}`)
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 16 })
    .onAppear(() => {
      this.getUIContext().animateTo({ duration: 800, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate }, () => {
        this.skelAlpha = 0.35;
      });
    })
  }

  /** 总进度头部（总进度条 + 任务计数 + 合计页数 + 并发数展示） */
  @Builder
  private SummaryHeader() {
    DownloadSummary({
      tasks: this.$tasks
    })
  }

  /** 多选态顶栏 */
  @Builder
  private SelectBar() {
    Row({ space: 10 }) {
      Text(`已选 ${this.selectedIds.length} 个任务`)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .layoutWeight(1)
      Text(this.allSelected() ? '取消全选' : '全选')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(PRIMARY)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .borderRadius(14)
        .backgroundColor(PRIMARY_SOFT)
        .onClick(() => {
          this.toggleSelectAll();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
  }

  /** 多选态底栏（删除所选 / 完成） */
  @Builder
  private SelectBottomBar() {
    Row({ space: 10 }) {
      Text('删除所选任务')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(DANGER)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .padding({ top: 11, bottom: 11 })
        .backgroundColor(DANGER_SOFT)
        .borderRadius(20)
        .opacity(this.selectedIds.length > 0 ? 1.0 : 0.45)
        .onClick(() => {
          if (this.selectedIds.length > 0) {
            this.onDeleteSelected();
          }
        })
      Text('退出管理')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_MAIN)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .padding({ top: 11, bottom: 11 })
        .backgroundColor(SUB_CARD)
        .borderRadius(20)
        .onClick(() => {
          this.exitSelect();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 + this.bottomInset })
    .backgroundColor(CARD)
    .border({ width: { top: 0.5 }, color: DIVIDER })
  }

  /** 任务列表项 */
  @Builder
  private TaskRow(item: DownloadTask) {
    DownloadTaskCard({
      selectMode: this.$selectMode,
      selectedIds: this.$selectedIds,
      toggleSelect: (id: number): void => this.toggleSelect(id),
      onPause: (id: number): Promise<void> => this.onPause(id),
      onResume: (id: number): Promise<void> => this.onResume(id),
      onRetry: (t: DownloadTask): Promise<void> => this.onRetry(t),
      onOpenFile: (t: DownloadTask): Promise<void> => this.onOpenFile(t),
      onSaveTo: (t: DownloadTask): Promise<void> => this.onSaveTo(t),
      onDelete: (t: DownloadTask): void => this.onDelete(t),
      enterSelect: (id: number): void => this.enterSelect(id),
      item: item
    })
  }

  /** 删除确认弹层 */
  @Builder
  private DeleteOverlay() {
    Column() {
      Column({ space: 16 }) {
        Text('删除下载任务')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
        Column({ space: 10 }) {
          Text(`将删除 ${this.pendingDeleteIds.length} 个任务记录${this.pendingHasActive() ? '（进行中的任务会被终止，临时文件将一并清理）' : '。'}`)
            .fontSize(13)
            .fontColor(TEXT_SUB)
            .lineHeight(19)
          Row({ space: 8 }) {
            Checkbox()
              .select(this.deleteFileToo)
              .selectedColor(PRIMARY)
              .onChange((value: boolean) => {
                this.deleteFileToo = value;
              })
            Text('同时删除应用内 CBZ 文件')
              .fontSize(12)
              .fontColor(TEXT_MAIN)
              .layoutWeight(1)
          }
          .width('100%')
          .onClick(() => {
            this.deleteFileToo = !this.deleteFileToo;
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row({ space: 10 }) {
          Text('取消')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT_MAIN)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 11, bottom: 11 })
            .borderRadius(20)
            .backgroundColor(SUB_CARD)
            .onClick(() => {
              this.pendingDeleteIds = [];
            })
          Text('确认删除')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 11, bottom: 11 })
            .borderRadius(20)
            .backgroundColor(DANGER)
            .onClick(() => {
              this.doDelete();
            })
        }
        .width('100%')
      }
      .width('86%')
      .padding(22)
      .borderRadius(22)
      .backgroundColor(CARD)
      .border({ width: 0.5, color: DIVIDER })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(MASK_DARK)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
