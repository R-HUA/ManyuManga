import common from '@ohos.app.ability.common';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import { MangaRouteParams } from '../common/Route';
import { Prefs } from '../util/Prefs';
import { library, LibraryWork } from '../data/Library';
import { readingActivity, ActivityStats } from '../data/ReadingActivity';
import { sourceStore, SourceEntry, sourceId } from '../data/Sources';
import { exportBackup, importBackup } from '../data/Backup';
import { clearPageCache, pageCacheSize } from '../data/ImageDecode';
import { ROUTE_DOWNLOADS } from '../common/Route';
import { BG, CARD, TEXT_MAIN, TEXT_SUB, PRIMARY } from '../common/Theme';
import { errorMessage } from '../models/Models';

class SourceCount {
  name: string = '';
  count: number = 0;
}
@Component
export struct ProfilePage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp('topRectHeight') top: number = 0;
  @StorageProp('activityVersion') @Watch('load') activityVersion: number = 0;
  @StorageProp('bookshelfDataVersion') @Watch('load') version: number = 0;
  @State bookCount: number = 0;
  @State stats: ActivityStats = new ActivityStats();
  @State distribution: Array<SourceCount> = [];
  @State theme: number = 0;
  @State reader: number = 0;
  @State preload: number = 3;
  @State cache: number = 0;
  @State autoCache: boolean = true;
  @State history: boolean = true;
  @State message: string = '';
  @State busy: boolean = false;
  private readonly modes: Array<string> = ['vertical', 'pagedVertical', 'horizontal', 'rtl', 'double'];
  aboutToAppear(): void { this.load(); }
  private async load(): Promise<void> {
    try {
      const works: Array<LibraryWork> = await library.list();
      this.bookCount = works.length; this.stats = await readingActivity.stats();
      const sources: Array<SourceEntry> = await sourceStore.list();
      this.distribution = sources.map((source: SourceEntry): SourceCount => {
        const count: SourceCount = new SourceCount(); count.name = source.name;
        count.count = works.filter((w: LibraryWork) => w.albums.some((a) => sourceId(a.id) === source.id)).length;
        return count;
      }).filter((count: SourceCount) => count.count > 0);
      const prefs: Prefs = await Prefs.getInstance();
      this.theme = ['system', 'light', 'dark'].indexOf(await prefs.themeMode());
      this.reader = this.modes.indexOf(await prefs.readerMode());
      this.preload = await prefs.preloadPages(); this.autoCache = await prefs.autoCache(); this.history = await prefs.historyEnabled();
      this.cache = pageCacheSize();
    } catch (e) { this.message = errorMessage(e as Error); }
  }
  private async changeTheme(index: number): Promise<void> {
    try {
      const mode: string = ['system', 'light', 'dark'][index];
      await (await Prefs.getInstance()).setThemeMode(mode);
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      context.getApplicationContext().setColorMode(index === 2 ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : index === 1 ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      this.theme = index;
    } catch (e) { this.message = errorMessage(e as Error); }
  }
  private async saveOption(key: string, value: number | boolean): Promise<void> {
    try {
      const prefs: Prefs = await Prefs.getInstance();
      if (key === 'reader') { await prefs.setReaderMode(this.modes[value as number]); this.reader = value as number; }
      else if (key === 'preload') { await prefs.setPreloadPages(value as number); this.preload = value as number; }
      else if (key === 'cache') { await prefs.setAutoCache(value as boolean); this.autoCache = value as boolean; }
      else { await prefs.setHistoryEnabled(value as boolean); this.history = value as boolean; }
    } catch (e) { this.message = errorMessage(e as Error); }
  }
  private async backup(restore: boolean): Promise<void> {
    this.busy = true;
    try {
      const done: boolean = restore ? await importBackup() : await exportBackup();
      if (done) { this.message = restore ? '备份已恢复，重新打开应用后生效' : '备份已保存'; }
    } catch (e) { this.message = errorMessage(e as Error); }
    finally { this.busy = false; }
  }
  @Builder
  private Metric(value: string, label: string) {
    Column({ space: 6 }) { Text(value).fontSize(24).fontWeight(FontWeight.Bold).fontColor(PRIMARY); Text(label).fontSize(12).fontColor(TEXT_SUB) }.layoutWeight(1)
  }
  build() {
    Column() {
      Text('我的').fontSize(30).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN).width('100%').padding({ left: 24, top: this.top + 12, bottom: 20 })
      Scroll() {
        Column({ space: 20 }) {
          Column({ space: 18 }) {
            Text('阅读统计').fontSize(20).fontColor(TEXT_MAIN).fontWeight(FontWeight.Bold).width('100%')
            Row() { this.Metric(`${this.bookCount}`, '书架漫画'); this.Metric(`${this.stats.pages.length}`, '已读页面'); this.Metric(`${Math.floor(this.stats.milliseconds / 60000)}`, '阅读分钟') }.width('100%')
            ForEach(this.distribution, (item: SourceCount) => {
              Row() { Text(item.name).fontColor(TEXT_SUB).fontSize(13).layoutWeight(1); Text(`${item.count} 本`).fontColor(TEXT_MAIN).fontSize(13) }.width('100%')
            })
          }.padding(20).width('100%').backgroundColor(CARD).borderRadius(24)
          Column({ space: 16 }) {
            Text('偏好设置').fontSize(20).fontColor(TEXT_MAIN).fontWeight(FontWeight.Bold).width('100%')
            Row() { Text('外观').fontColor(TEXT_MAIN).layoutWeight(1); Select([{ value: '跟随系统' }, { value: '浅色' }, { value: '深色' }]).selected(this.theme).onSelect((i: number) => { this.changeTheme(i); }) }.width('100%')
            Text('默认阅读模式').fontColor(TEXT_MAIN).width('100%')
            Select([{ value: '连续纵向' }, { value: '纵向翻页' }, { value: '从左向右' }, { value: '从右向左' }, { value: '双页阅读' }]).selected(this.reader).onSelect((i: number) => { this.saveOption('reader', i); })
            Text(`预加载 ${this.preload} 页`).fontColor(TEXT_MAIN).width('100%')
            Slider({ value: this.preload, min: 1, max: 8, step: 1 }).onChange((v: number, mode: SliderChangeMode) => { if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) { this.saveOption('preload', v); } })
            Row() { Text('阅读时缓存图片').fontColor(TEXT_MAIN).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.autoCache }).onChange((v: boolean) => { this.saveOption('cache', v); }) }.width('100%')
            Row() { Text('记录浏览历史').fontColor(TEXT_MAIN).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.history }).onChange((v: boolean) => { this.saveOption('history', v); }) }.width('100%')
          }.padding(20).width('100%').backgroundColor(CARD).borderRadius(24)
          Column({ space: 14 }) {
            Button('下载管理').width('100%').onClick(() => { this.stack.pushPathByName(ROUTE_DOWNLOADS, {} as MangaRouteParams); })
            Button(`清理图片缓存 · ${(this.cache / 1048576).toFixed(1)} MB`).width('100%').onClick(() => { clearPageCache(); this.cache = pageCacheSize(); })
            Button('导出备份').width('100%').enabled(!this.busy).onClick(() => { this.backup(false); })
            Button('恢复备份').width('100%').enabled(!this.busy).onClick(() => { AlertDialog.show({ title: '恢复备份', message: '将用备份替换书架、书源配置和阅读记录。',
              primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '选择备份', action: () => { this.backup(true); } } }); })
          }.padding(20).width('100%').backgroundColor(CARD).borderRadius(24)
          if (this.message !== '') { Text(this.message).fontColor(TEXT_SUB).width('100%') }
          Text('漫屿').fontSize(22).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN)
          Text('1.0.0').fontSize(12).fontColor(TEXT_SUB)
        }.padding({ left: 20, right: 20, bottom: 120 }).width('100%')
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor(BG)
  }
}
