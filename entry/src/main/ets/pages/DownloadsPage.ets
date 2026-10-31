import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HDS_TITLE_STYLE } from '../common/ImmersiveMaterials';
import { SegmentButton, SegmentButtonOptions, SegmentButtonTextItem, ItemRestriction, ToolBarOptions } from '@kit.ArkUI';
import { SelectionToolBar, ToolAction, buildToolBar } from '../common/SelectionToolBar';
import { saveDownload } from './downloads/DownloadFileExporter';
import { DownloadedPane } from './downloads/DownloadedPane';
import { BasicDataSource } from '../common/DataSource';
import { DownloadTaskCard, chapterStatusText } from './downloads/DownloadTaskCard';
import { DownloadSummary } from './downloads/DownloadSummary';
import { ON_PRIMARY, PRIMARY, PRIMARY_SOFT, BG, CARD, SUB_CARD, DANGER, DANGER_SOFT, COVER_R, CHIP_R, TEXT_MAIN, TEXT_SUB, DIVIDER, MASK_DARK, NEUTRAL_PROGRESS } from '../common/Theme';
import { IconCircleButton } from '../common/Components';
import { EmptyView } from '../common/Components';
import { errorMessage } from '../models/Models';
import { downloadManager, DownloadTask, DownloadChapter } from '../data/DownloadManager';
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
  @State @Watch('syncTaskToolbar') selectMode: boolean = false;
  @State @Watch('syncTaskToolbar') selectedIds: Array<number> = [];
  @State taskToolbar: ToolBarOptions = new ToolBarOptions();
  /* 已下载子页的多选态（标题栏统一控制） */
  @State offlineManaging: boolean = false;
  @State offlineSelected: number = 0;
  @State offlineTotal: number = 0;
  @State @Watch('sectionChanged') sectionIndexes: number[] = [0];
  @State sectionOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [{ text: '已下载' }, { text: '下载任务' }] as ItemRestriction<SegmentButtonTextItem>
  });
  private taskScroller: Scroller = new Scroller();
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

  private sectionChanged(): void {
    const next: string = (this.sectionIndexes[0] ?? 0) === 1 ? 'tasks' : 'offline';
    if (next === this.section) { return; }
    this.exitSelect();
    this.offlineManaging = false;
    this.section = next;
  }

  private syncTaskToolbar(): void {
    const some: boolean = this.selectedIds.length > 0;
    this.taskToolbar = buildToolBar([
      new ToolAction('删除', $r('sys.symbol.trash'), some, true, (): void => { this.onDeleteSelected(); }),
      new ToolAction(this.allSelected() ? '取消全选' : '全选', $r('sys.symbol.checkmark_square_on_square'), this.tasks.length > 0, false,
        (): void => { this.toggleSelectAll(); })
    ]);
  }

  private selecting(): boolean {
    return this.section === 'offline' ? this.offlineManaging : this.selectMode;
  }

  private pageTitle(): string {
    if (this.section === 'offline' && this.offlineManaging) { return `已选 ${this.offlineSelected} 项`; }
    if (this.section === 'tasks' && this.selectMode) { return `已选 ${this.selectedIds.length} 项`; }
    return '离线下载';
  }

  private canSelect(): boolean {
    return this.section === 'offline' ? this.offlineTotal > 0 : this.tasks.length > 0;
  }

  private quitSelect(): void {
    this.exitSelect();
    this.offlineManaging = false;
  }

  private enterSelect(): void {
    if (this.section === 'offline') { this.offlineManaging = true; } else { this.selectMode = true; this.selectedIds = []; }
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

  /** 取消单章：从任务中移除尚未完成的章节。 */
  private async onCancelChapter(t: DownloadTask, c: DownloadChapter): Promise<void> {
    try {
      await downloadManager.removeChapter(t.id, c.chapterId);
      this.showToast('已取消该章节');
    } catch (e) {
      this.showToast(`取消失败：${errorMessage(e as Error)}`);
    }
  }

  /** 单章重试：任务续传，已完成页面会被复用。 */
  private async onRetryChapter(t: DownloadTask): Promise<void> {
    if (t.state === 'running' || t.state === 'queued') {
      return;
    }
    await this.onRetry(t);
  }

  /** 分组内展示的章节：已完成任务折叠章节，只看分组头。 */
  private visibleChapters(t: DownloadTask): Array<DownloadChapter> {
    return this.selectMode || t.state === 'done' ? [] : t.chapters;
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

  build() {
    HdsNavDestination() {
      Stack() {
        Column() {
          if (!this.selecting()) {
            this.SectionBar()
          }

          if (this.section === 'offline') {
            DownloadedPane({ managing: $offlineManaging, selectedCount: $offlineSelected, totalCount: $offlineTotal })
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
              EmptyView({ message: '还没有下载任务', showRetry: false, quiet: true })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            if (!this.selectMode) {
              this.SummaryHeader()
            }

            List({ space: 12, scroller: this.taskScroller }) {
              LazyForEach(this.taskDS, (item: DownloadTask) => {
                ListItemGroup({ header: this.TaskRow(item) }) {
                  ForEach(this.visibleChapters(item), (c: DownloadChapter) => {
                    ListItem() {
                      this.ChapterItem(item, c)
                    }
                    .swipeAction(c.state === 'done' ? {} : { end: { builder: (): void => { this.CancelAction(item, c); } } })
                  }, (c: DownloadChapter) => `${item.id}_${c.chapterId}_${c.state}_${c.done}_${c.total}`)
                }
                .padding({ left: 12, right: 12, bottom: 4 })
                .backgroundColor(CARD)
                .borderRadius(16)
                .divider({ strokeWidth: '1px', color: DIVIDER, startMargin: 48, endMargin: 0 })
              }, (item: DownloadTask) => `task_${item.id}`)
            }
            .width('100%')
            .layoutWeight(1)
            .cachedCount(4)
            .scrollBar(BarState.Off)
            .padding({ left: 16, right: 16, top: 8, bottom: (this.selectMode ? 12 : 28 + this.bottomInset) })

            if (this.selectMode) {
              SelectionToolBar({ items: this.taskToolbar, bottomInset: this.bottomInset })
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
    .titleBar({ content: { title: { mainTitle: this.pageTitle() }, menu: { value: this.selecting()
      ? [{ content: { icon: $r('sys.symbol.xmark'), label: '退出选择', action: (): void => { this.quitSelect(); } } }]
      : (this.canSelect() ? [{ content: { icon: $r('sys.symbol.checkmark_square_on_square'), label: '选择', action: (): void => { this.enterSelect(); } } }] : []) } },
      style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.taskScroller])
    .backgroundColor(BG)
  }

  /** 一级互斥视图：标题栏下方的分段按钮（SegmentButton tab 样式） */
  @Builder
  private SectionBar() {
    Row() {
      SegmentButton({ options: this.sectionOptions, selectedIndexes: $sectionIndexes })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 8 })
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

  @Builder
  private CancelAction(t: DownloadTask, c: DownloadChapter) {
    Row() {
      Text('取消').fontSize(14).fontColor(ON_PRIMARY)
    }
    .width(72)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(DANGER)
    .accessibilityText('取消下载本章')
    .onClick(() => {
      this.onCancelChapter(t, c);
    })
  }

  @Builder
  private ChapterItem(t: DownloadTask, c: DownloadChapter) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(c.title)
            .fontSize(13)
            .fontColor(c.state === 'done' ? TEXT_SUB : TEXT_MAIN)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(chapterStatusText(c, t.state))
            .fontSize(11)
            .fontColor(c.state === 'failed' ? DANGER : TEXT_SUB)
            .maxLines(1)
            .constraintSize({ maxWidth: '50%' })
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        if (c.state === 'running' && t.state === 'running' && c.total > 0) {
          Progress({ value: c.done, total: Math.max(1, c.total), type: ProgressType.Linear })
            .width('100%')
            .height(2)
            .color(NEUTRAL_PROGRESS)
            .backgroundColor(SUB_CARD)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (c.state === 'failed') {
        IconCircleButton({ glyph: $r('sys.symbol.arrow_clockwise'), btnSize: 36, iconSize: 16, iconColor: DANGER,
          onTap: (): void => { this.onRetryChapter(t); } }).accessibilityText('重试本章')
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 44 })
    .padding({ left: 48, right: 4 })
    .alignItems(VerticalAlign.Center)
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
            .fontColor(ON_PRIMARY)
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
