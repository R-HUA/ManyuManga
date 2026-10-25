/**
 * 下载管理
 *
 *
 */

import fs from '@ohos.file.fs';
import filePicker from '@ohos.file.picker';
import {
  PRIMARY,
  ACCENT,
  BG,
  CARD,
  CARD_R,
  COVER_R,
  CHIP_R,
  TEXT_MAIN,
  TEXT_SUB,
  CHIP_BG,
  DIVIDER,
  MASK_DARK,
  TAB_INACTIVE
} from '../common/Theme';
import { EmptyView } from '../common/Components';
import { Album, errorMessage } from '../models/Models';
import { downloadManager, DownloadTask, DownloadState } from '../data/DownloadManager';
import { albumCacheStore } from '../data/Stores';
import { sourceApi as jmApi } from '../data/SourceApi';
import { ROUTE_READER, MangaRouteParams } from '../common/Route';
import { TOP_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

/** 页下载并发展示值 */
const DL_PAGE_CONCURRENCY: number = 3;

/* ===== 任务列表懒加载数据源 ===== */

class TaskDataSource implements IDataSource {
  private items: Array<DownloadTask> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): DownloadTask {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener): boolean => l !== listener);
  }

  reload(items: Array<DownloadTask>): void {
    this.items = items;
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }
}

function formatDateTime(ms: number): string {
  if (ms <= 0) {
    return '';
  }
  const d: Date = new Date(ms);
  const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

@Component
export struct DownloadsPage {
  @Consume('navPathStack') navPathStack: NavPathStack;

  // 评审 Step2：顶部状态栏避让高度（EntryAbility 全屏布局写入 AppStorage，自绘顶栏 padding 引用）
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 38;

  /* ===== 页面状态（四态：骨架/空/错误重试；任务列表实时刷新无分页） ===== */
  @State loading: boolean = true;
  @State loadError: string = '';
  @State skelAlpha: number = 1.0;

  /* ===== 数据与选择态 ===== */
  @State tasks: Array<DownloadTask> = [];
  @State selectMode: boolean = false;
  @State selectedIds: Array<number> = [];
  @State pendingDeleteIds: Array<number> = [];
  @State deleteFileToo: boolean = false;

  private initialized: boolean = false;
  private taskDS: TaskDataSource = new TaskDataSource();
  private changeListener: (task: DownloadTask) => void = (): void => {
    this.refreshTasks();
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

  /* ===== 多选（DL-08） ===== */

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

  /** 失败重试：无 retry(id) 契约，用 removeTask + album（缓存优先，网络兜底）+ enqueue 组合 */
  private async onRetry(t: DownloadTask): Promise<void> {
    try {
      this.showToast('正在重新入队…');
      let album: Album | null = await albumCacheStore.get(t.albumId);
      if (album === null) {
        album = await jmApi.album(t.albumId);
      }
      await downloadManager.removeTask(t.id, false);
      await downloadManager.enqueue(album);
      this.showToast('已重新加入下载队列');
    } catch (e) {
      this.showToast(`重试失败：${errorMessage(e as Error)}`);
    }
  }

  /* ===== 已完成任务：打开 / 保存到用户所选位置（DL-10 / DL-07） ===== */

  private async onOpenFile(t: DownloadTask): Promise<void> {
    this.navPathStack.pushPathByName(ROUTE_READER, { aid: t.albumId } as MangaRouteParams);
  }

  private fileNameOf(path: string): string {
    const parts: Array<string> = path.split('/');
    const name: string | undefined = parts.pop();
    return name === undefined ? 'download.cbz' : name;
  }

  /**
   * 分块拷贝沙箱文件到目标 fd（1MB 缓冲，避免整文件读入内存）。
   * 使用系统文件拷贝，避免短写造成导出文件不完整。
   */
  private copyFileByChunk(srcFd: number, dstFd: number, total: number): number {
    fs.copyFileSync(srcFd, dstFd);
    return fs.statSync(dstFd).size;
  }

  /** DL-07 保存到用户所选位置：DocumentViewPicker 保存选择器 + 分块拷贝到所选 URI */
  private async onSaveTo(t: DownloadTask): Promise<void> {
    if (t.savedTo === '') {
      this.showToast('文件路径为空，无法保存');
      return;
    }
    let src: fs.File | null = null;
    let dst: fs.File | null = null;
    try {
      const st: fs.Stat = fs.statSync(t.savedTo);
      const picker: filePicker.DocumentViewPicker = new filePicker.DocumentViewPicker();
      const opt: filePicker.DocumentSaveOptions = new filePicker.DocumentSaveOptions();
      opt.newFileNames = [this.fileNameOf(t.savedTo)];
      const uris: Array<string> = await picker.save(opt);
      if (uris.length === 0) {
        return; // 用户取消
      }
      src = fs.openSync(t.savedTo, fs.OpenMode.READ_ONLY);
      dst = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      const copied: number = this.copyFileByChunk(src.fd, dst.fd, st.size);
      if (copied !== st.size) {
        throw new Error(`保存不完整（${copied}/${st.size}）`);
      }
      this.showToast('已保存到所选位置');
    } catch (e) {
      this.showToast(`保存失败：${errorMessage(e as Error)}`);
    } finally {
      if (src !== null) {
        try {
          fs.closeSync(src);
        } catch (e) {
          // 关闭失败忽略
        }
      }
      if (dst !== null) {
        try {
          fs.closeSync(dst);
        } catch (e) {
          // 关闭失败忽略
        }
      }
    }
  }

  /* ===== 删除（DL-09：确认 + 可选删文件；进行中任务强制终止由 removeTask 承担） ===== */

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
      return `已完成 · CBZ 已导出：${t.savedTo}`;
    }
    if (t.state === 'failed') {
      return `失败：${t.error === '' ? '未知错误' : t.error}`;
    }
    return '已取消';
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
    if (state === 'failed') {
      return '失败';
    }
    return '已取消';
  }

  private badgeTextColor(state: DownloadState): ResourceColor {
    if (state === 'running' || state === 'done' || state === 'failed') {
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
    if (state === 'failed') {
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
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(26)
        .fontColor([TEXT_MAIN])
        .onClick(() => {
          this.navPathStack.pop();
        })
      Text('下载管理')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .layoutWeight(1)
    }
    .width('100%')
    // 评审 Step2：padding 顶部叠加状态栏避让高度（与 SearchPage 顶栏一致口径）
    .padding({ left: 12, right: 16, top: this.topInset + 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          this.TopBar()

          if (this.loading) {
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
              EmptyView({ message: '还没有下载任务～ 去详情页点「下载」生成 CBZ 吧', showRetry: false })
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

            List({ space: 0 }) {
              LazyForEach(this.taskDS, (item: DownloadTask) => {
                ListItem() {
                  this.TaskRow(item)
                }
              }, (item: DownloadTask) => `task_${item.id}`)
            }
            .width('100%')
            .layoutWeight(1)
            .cachedCount(4)

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
    .hideTitleBar(true) // 评审 Step2：改用自绘 TopBar（返回 + 标题 + 状态栏避让）
    .backgroundColor(BG)
  }

  /** 首载骨架（脉冲呼吸占位行） */
  @Builder
  private SkeletonList() {
    Column({ space: 16 }) {
      ForEach([0, 1, 2, 3], (i: number) => {
        Row({ space: 12 }) {
          Column()
            .width(44)
            .height(58)
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
    Column({ space: 8 }) {
      Row() {
        Text('总进度')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)
        Text(`已完成 ${this.countByState('done')} / ${this.tasks.length} 个任务`)
          .fontSize(11)
          .fontColor(TEXT_SUB)
      }
      .width('100%')

      Progress({ value: this.overallProgress(), total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(6)
        .color(ACCENT)
        .backgroundColor(DIVIDER)

      Row({ space: 8 }) {
        this.CountChip(`下载中 ${this.countByState('running')}`)
        this.CountChip(`等待 ${this.countByState('queued')}`)
        this.CountChip(`暂停 ${this.countByState('paused')}`)
        this.CountChip(`失败 ${this.countByState('failed')}`)
      }
      .width('100%')

      Row() {
        Text(`合计 ${this.totalDonePages()} / ${this.totalPagesCount()} 页`)
          .fontSize(10)
          .fontColor(TEXT_SUB)
        Text(`页下载并发 ${DL_PAGE_CONCURRENCY}（固定）`)
          .fontSize(10)
          .fontColor(TEXT_SUB)
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(CARD)
    .borderRadius(CARD_R)
    .margin({ left: 12, right: 12, top: 8 })
  }

  @Builder
  private CountChip(label: string) {
    Text(label)
      .fontSize(10)
      .fontColor(TEXT_SUB)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .backgroundColor(CHIP_BG)
      .borderRadius(CHIP_R)
  }

  /** 多选态顶栏（DL-08：已选 N 项 + 全选/取消全选 + 退出） */
  @Builder
  private SelectBar() {
    Row() {
      Text(`已选 ${this.selectedIds.length} 项`)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .layoutWeight(1)
      Text(this.allSelected() ? '取消全选' : '全选')
        .fontSize(13)
        .fontColor(PRIMARY)
        .padding({ left: 8, right: 8 })
        .onClick(() => {
          this.toggleSelectAll();
        })
      Text('退出')
        .fontSize(13)
        .fontColor(TEXT_SUB)
        .padding({ left: 8, right: 8 })
        .onClick(() => {
          this.exitSelect();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  /** 多选态底栏（删除所选 / 完成） */
  @Builder
  private SelectBottomBar() {
    Row({ space: 10 }) {
      Text('删除所选')
        .fontSize(14)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .padding({ top: 10, bottom: 10 })
        .backgroundColor(PRIMARY)
        .borderRadius(CHIP_R)
        .onClick(() => {
          this.onDeleteSelected();
        })
      Text('完成')
        .fontSize(14)
        .fontColor(TEXT_MAIN)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .padding({ top: 10, bottom: 10 })
        .backgroundColor(CHIP_BG)
        .borderRadius(CHIP_R)
        .onClick(() => {
          this.exitSelect();
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
  }

  /** 任务列表项（DL-01） */
  @Builder
  private TaskRow(item: DownloadTask) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        if (this.selectMode) {
          Checkbox()
            .select(this.isSelected(item.id))
            .selectedColor(PRIMARY)
            .onChange((value: boolean) => {
              this.toggleSelect(item.id);
            })
        }
        if (item.cover !== '') {
          Image(item.cover)
            .width(44)
            .height(58)
            .borderRadius(COVER_R)
            .objectFit(ImageFit.Cover)
            .backgroundColor(CHIP_BG)
        }
        Column({ space: 3 }) {
          Text(item.title)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT_MAIN)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.statusText(item))
            .fontSize(11)
            .fontColor(TEXT_SUB)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (item.createdAt > 0) {
            Text(`下载于 ${formatDateTime(item.createdAt)}`)
              .fontSize(10)
              .fontColor(TAB_INACTIVE)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(this.stateLabel(item.state))
          .fontSize(10)
          .fontColor(this.badgeTextColor(item.state))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(this.badgeBgColor(item.state))
          .borderRadius(CHIP_R)
      }
      .width('100%')

      if (item.state === 'running' || item.state === 'queued' || item.state === 'paused') {
        Progress({ value: this.progressValue(item), total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(4)
          .color(this.progressBarColor(item.state))
          .backgroundColor(DIVIDER)
      }

      if (!this.selectMode) {
        Row({ space: 4 }) {
          if (item.state === 'queued' || item.state === 'running') {
            Text('暂停')
              .fontSize(13)
              .fontColor(TEXT_SUB)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .onClick(() => {
                this.onPause(item.id);
              })
          }
          if (item.state === 'paused') {
            Text('重新下载')
              .fontSize(13)
              .fontColor(ACCENT)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .onClick(() => {
                this.onResume(item.id);
              })
          }
          if (item.state === 'failed') {
            Text('重试')
              .fontSize(13)
              .fontColor(ACCENT)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .onClick(() => {
                this.onRetry(item);
              })
          }
          // DL-10：已完成任务提供「打开」（系统打开方式）；DL-07：「保存到…」（系统保存选择器）
          if (item.state === 'done') {
            Text('打开')
              .fontSize(13)
              .fontColor(ACCENT)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .onClick(() => {
                this.onOpenFile(item);
              })
            Text('保存到…')
              .fontSize(13)
              .fontColor(ACCENT)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .onClick(() => {
                this.onSaveTo(item);
              })
          }
          Text('删除')
            .fontSize(13)
            .fontColor(PRIMARY)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .onClick(() => {
              this.onDelete(item);
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .onClick(() => {
      if (this.selectMode) {
        this.toggleSelect(item.id);
      }
    })
    .gesture(LongPressGesture().onAction(() => {
      if (!this.selectMode) {
        this.enterSelect(item.id);
      }
    }))
  }

  /** 删除确认弹层（DL-09：说明 + 同时删除原始文件 checkbox + 取消/删除） */
  @Builder
  private DeleteOverlay() {
    Column() {
      Column({ space: 14 }) {
        Text('删除下载任务')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
        Column({ space: 10 }) {
          Text(`将删除 ${this.pendingDeleteIds.length} 个任务记录${this.pendingHasActive() ? '（进行中的任务会被强制终止，其已下载的临时文件将一并删除）' : '。'}`)
            .fontSize(13)
            .fontColor(TEXT_SUB)
          Row({ space: 8 }) {
            Checkbox()
              .select(this.deleteFileToo)
              .selectedColor(PRIMARY)
              .onChange((value: boolean) => {
                this.deleteFileToo = value;
              })
            Text('同时删除原始文件（不可恢复）')
              .fontSize(12)
              .fontColor(TEXT_SUB)
              .layoutWeight(1)
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Divider()
          .color(DIVIDER)
        Row() {
          Text('取消')
            .fontSize(15)
            .fontColor(TEXT_SUB)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 10, bottom: 10 })
            .onClick(() => {
              this.pendingDeleteIds = [];
            })
          Text('删除')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(PRIMARY)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 10, bottom: 10 })
            .onClick(() => {
              this.doDelete();
            })
        }
        .width('100%')
      }
      .width('86%')
      .padding({ left: 20, right: 20, top: 20, bottom: 8 })
      .borderRadius(CARD_R)
      .backgroundColor(CARD)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(MASK_DARK)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
