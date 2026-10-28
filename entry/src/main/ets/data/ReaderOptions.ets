import { Prefs } from '../util/Prefs';
import { ReaderMode, ReadingProgress } from '../models/Models';
import { library } from './Library';
import { loadBookmarks, loadReaderPref, ReaderPrefRow, saveReaderPref, tapsFrom, toggleBookmark, copyProgress } from './db/ReadingDao';
import { StoreQueue } from './stores/StoreSupport';
import { assertDatabaseGeneration } from './db/AppDatabase';

/** 九宫格动作编号：0 呼出菜单、1 上一页、2 下一页、3 上一话、4 下一话。 */
export const TAP_ACTIONS: Array<string> = ['呼出菜单', '上一页', '下一页', '上一话', '下一话'];
/** 经典左右翻页布局；恢复默认与首次加载共用同一份常量，避免两处定义漂移。 */
export const DEFAULT_TAPS: Array<number> = [1, 0, 2, 1, 0, 2, 3, 0, 4];
/** 护眼滤镜强度档位：0 关闭，其余为叠加透明度百分比。 */
export const EYE_COMFORT_DEFAULT: number = 45;
export const EYE_COMFORT_MIN: number = 15;
export const EYE_COMFORT_MAX: number = 70;
/** 后台预加载档位，索引即分段控件的选中位。 */
export const PRELOAD_LEVELS: Array<number> = [1, 3, 5, 8];
/** 阅读器二级抽屉：目录与缩略图、画面调节、阅读偏好。 */
export type ReaderSheetKind = 'index' | 'picture' | 'prefs';

export class ReaderOptions {
  mode: ReaderMode = 'vertical';
  coverOffset: boolean = true;
  cropWhite: boolean = false;
  eyeComfort: number = 0;
  preload: number = 3;
  paper: boolean = false;
  taps: Array<number> = DEFAULT_TAPS.slice();
}
class ReaderPreferences {
  private queue: StoreQueue = new StoreQueue();
  async key(aid: string): Promise<string> { return (await library.workFor(aid))?.id ?? aid; }
  async load(aid: string): Promise<ReaderOptions> {
    await this.queue.wait();
    const row: ReaderPrefRow | null = await loadReaderPref(await this.key(aid));
    if (row !== null) {
      return optionsFrom(row);
    }
    const prefs: Prefs = await Prefs.getInstance();
    const options: ReaderOptions = new ReaderOptions();
    options.mode = await prefs.readerMode() as ReaderMode;
    options.preload = await prefs.preloadPages();
    options.paper = await prefs.readerBgPaper();
    return options;
  }
  save(aid: string, options: ReaderOptions): Promise<void> {
    const snapshot: ReaderOptions = copyOptions(options);
    return this.queue.run(async (generation: number): Promise<void> => {
      const row: ReaderPrefRow = new ReaderPrefRow();
      row.mode = snapshot.mode;
      row.coverOffset = snapshot.coverOffset ? 1 : 0;
      row.cropWhite = snapshot.cropWhite ? 1 : 0;
      row.eyeComfort = snapshot.eyeComfort;
      row.preload = snapshot.preload;
      row.paper = snapshot.paper ? 1 : 0;
      row.taps = JSON.stringify(snapshot.taps);
      const key: string = await this.key(aid);
      assertDatabaseGeneration(generation);
      await saveReaderPref(key, row);
    });
  }
  async bookmarks(aid: string): Promise<Array<ReadingProgress>> {
    await this.queue.wait();
    return loadBookmarks(aid);
  }
  toggleBookmark(progress: ReadingProgress): Promise<void> {
    const snapshot: ReadingProgress = copyProgress(progress);
    return this.queue.run(async (): Promise<void> => {
      await toggleBookmark(snapshot);
    });
  }
}

function copyOptions(options: ReaderOptions): ReaderOptions {
  const next: ReaderOptions = new ReaderOptions();
  next.mode = options.mode;
  next.coverOffset = options.coverOffset;
  next.cropWhite = options.cropWhite;
  next.eyeComfort = options.eyeComfort;
  next.preload = options.preload;
  next.paper = options.paper;
  next.taps = options.taps.slice();
  return next;
}

function eyeLevelFrom(stored: number): number {
  // 历史版本只在 0/1 之间切换；旧的"开启"等价于当前默认强度。
  if (stored <= 0) {
    return 0;
  }
  return stored === 1 ? EYE_COMFORT_DEFAULT : Math.min(EYE_COMFORT_MAX, stored);
}

function optionsFrom(row: ReaderPrefRow): ReaderOptions {
  const options: ReaderOptions = new ReaderOptions();
  options.mode = row.mode as ReaderMode;
  options.coverOffset = row.coverOffset === 1;
  options.cropWhite = row.cropWhite === 1;
  options.eyeComfort = eyeLevelFrom(row.eyeComfort);
  options.preload = row.preload;
  options.paper = row.paper === 1;
  options.taps = tapsFrom(row.taps);
  return options;
}

export const readerPreferences: ReaderPreferences = new ReaderPreferences();
