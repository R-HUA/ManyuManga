import common from '@ohos.app.ability.common';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import promptAction from '@ohos.promptAction';
import { MangaRouteParams, ROUTE_BLOCK_RULES, ROUTE_DOWNLOADS } from '../common/Route';
import { Prefs } from '../util/Prefs';
import { library, LibraryWork } from '../data/Library';
import { readingActivity, ActivityStats } from '../data/ReadingActivity';
import { sourceStore, SourceEntry, sourceId } from '../data/Sources';
import { exportBackup, importBackup } from '../data/Backup';
import { cleanLegacyData } from '../data/LegacyCleanup';
import { AuthOutcome, authenticate } from '../util/AppLock';
import { IMMERSIVE_REGULAR_MATERIAL } from '../common/ImmersiveMaterials';
import { clearPageCache, pageCacheSize } from '../data/ImageDecode';
import { SettingSelectRow } from '../common/Components';
import {
  BG,
  CARD,
  SUB_CARD,
  TEXT_MAIN,
  TEXT_SUB,
  PRIMARY,
  PRIMARY_SOFT,
  DIVIDER,
  TAB_BAR_HEIGHT
} from '../common/Theme';
import { Album, errorMessage } from '../models/Models';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

class SourceCount {
  name: string = '';
  count: number = 0;
}

@Component
export struct ProfilePage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp(TOP_RECT_HEIGHT_KEY) top: number = 0;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  @StorageProp('currentBreakpoint') breakpoint: string = 'sm';
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
  @State securityLock: boolean = false;
  @State previewOn: boolean = true;
  @State message: string = '';
  @State busy: boolean = false;

  private readonly modes: Array<string> = ['vertical', 'pagedVertical', 'horizontal', 'rtl', 'double'];
  private readonly modeLabels: Array<string> = ['纵向条漫', '纵向翻页', '左翻单页', '日漫右翻', '双页拼合'];

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      const works: Array<LibraryWork> = await library.list();
      this.bookCount = works.length;
      this.stats = await readingActivity.stats();
      const sources: Array<SourceEntry> = await sourceStore.list();
      this.distribution = sources.map((source: SourceEntry): SourceCount => {
        const count: SourceCount = new SourceCount();
        count.name = source.name;
        count.count = works.filter((w: LibraryWork) => w.albums.some((a: Album) => sourceId(a.id) === source.id)).length;
        return count;
      }).filter((count: SourceCount) => count.count > 0);

      const prefs: Prefs = await Prefs.getInstance();
      this.theme = Math.max(0, ['system', 'light', 'dark'].indexOf(await prefs.themeMode()));
      this.reader = Math.max(0, this.modes.indexOf(await prefs.readerMode()));
      this.preload = await prefs.preloadPages();
      this.autoCache = await prefs.autoCache();
      this.history = await prefs.historyEnabled();
      this.securityLock = await prefs.securityLock();
      this.previewOn = await prefs.previewProtection();
      this.cache = pageCacheSize();
    } catch (e) {
      this.message = errorMessage(e as Error);
    }
  }

  private async changeTheme(index: number): Promise<void> {
    try {
      const mode: string = ['system', 'light', 'dark'][index];
      await (await Prefs.getInstance()).setThemeMode(mode);
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      context.getApplicationContext().setColorMode(
        index === 2 ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : index === 1 ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
          : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
      );
      this.theme = index;
    } catch (e) {
      this.message = errorMessage(e as Error);
    }
  }

  private async saveOption(key: string, value: Object): Promise<void> {
    try {
      const prefs: Prefs = await Prefs.getInstance();
      if (key === 'reader') {
        await prefs.setReaderMode(this.modes[value as number]);
        this.reader = value as number;
      } else if (key === 'preload') {
        await prefs.setPreloadPages(value as number);
        this.preload = value as number;
      } else if (key === 'cache') {
        await prefs.setAutoCache(value as boolean);
        this.autoCache = value as boolean;
      } else if (key === 'history') {
        await prefs.setHistoryEnabled(value as boolean);
        this.history = value as boolean;
      } else if (key === 'preview') {
        await prefs.setPreviewProtection(value as boolean);
        this.previewOn = value as boolean;
      }
    } catch (e) {
      this.message = errorMessage(e as Error);
    }
  }

  private confirmLock(enable: boolean): void {
    authenticate(enable ? '验证身份以开启应用锁' : '验证身份以关闭应用锁').then((outcome: AuthOutcome): void => {
      if (!outcome.ok) {
        this.message = outcome.message === '' ? '验证未通过，应用锁未更改' : outcome.message;
        return;
      }
      Prefs.getInstance().then((prefs: Prefs): Promise<void> => prefs.setSecurityLock(enable)).then((): void => {
        this.securityLock = enable;
        this.message = '';
      }).catch((e: Error) => {
        this.message = errorMessage(e);
      });
    });
  }

  private async backup(isRestore: boolean): Promise<void> {
    this.busy = true;
    try {
      if (isRestore) {
        const ok: boolean = await importBackup();
        if (ok) {
          await this.load();
          promptAction.showToast({ message: '备份数据恢复成功' });
        }
      } else {
        const ok: boolean = await exportBackup();
        if (ok) {
          promptAction.showToast({ message: '备份导出成功' });
        }
      }
    } catch (e) {
      this.message = errorMessage(e as Error);
    } finally {
      this.busy = false;
    }
  }

  private cleanLegacy(): void {
    if (this.busy) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '清理旧版数据',
      message: '将删除旧版本遗留的记录、书源配置和旧离线目录。当前书架、离线漫画和已导出文件会保留。',
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: {
        value: '清理',
        fontColor: PRIMARY,
        action: (): void => {
          this.busy = true;
          cleanLegacyData().then((): void => {
            this.message = '';
            promptAction.showToast({ message: '已清理旧版数据' });
          }).catch((e: Error) => {
            this.message = errorMessage(e);
          }).finally((): void => {
            this.busy = false;
          });
        }
      }
    });
  }

  @Builder
  private Metric(val: string, unit: string, label: string) {
    Column({ space: 4 }) {
      Row({ space: 2 }) {
        Text(val)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
        Text(unit)
          .fontSize(12)
          .fontColor(TEXT_SUB)
          .margin({ bottom: 3 })
      }
      .alignItems(VerticalAlign.Bottom)

      Text(label)
        .fontSize(12)
        .fontColor(TEXT_SUB)
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12 })
    .borderRadius(14)
    .backgroundColor(SUB_CARD)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: 10 }) {
        Text('设置')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.top + 10, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 16 }) {
          // 1. 阅读统计
          Column({ space: 14 }) {
            Row() {
              Text('阅读统计')
                .fontSize(17)
                .fontColor(TEXT_MAIN)
                .fontWeight(FontWeight.Bold)
                .layoutWeight(1)
              Text('实时累计')
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(PRIMARY)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(8)
                .backgroundColor(PRIMARY_SOFT)
            }
            .width('100%')

            Row({ space: 10 }) {
              this.Metric(`${this.bookCount}`, '部', '书架漫画')
              this.Metric(`${this.stats.pages.length}`, '页', '累计已读')
              this.Metric(`${Math.floor(this.stats.milliseconds / 60000)}`, '分', '阅读时长')
            }
            .width('100%')

            if (this.distribution.length > 0) {
              Column({ space: 8 }) {
                Text('书架书源分布')
                  .fontSize(12)
                  .fontColor(TEXT_SUB)
                  .width('100%')
                ForEach(this.distribution, (item: SourceCount) => {
                  Column({ space: 4 }) {
                    Row() {
                      Text(item.name)
                        .fontColor(TEXT_MAIN)
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .layoutWeight(1)
                      Text(`${item.count} 部`)
                        .fontColor(PRIMARY)
                        .fontSize(12)
                        .fontWeight(FontWeight.Bold)
                    }
                    .width('100%')

                    Progress({
                      value: this.bookCount > 0 ? Math.round((item.count / this.bookCount) * 100) : 0,
                      total: 100,
                      type: ProgressType.Linear
                    })
                      .width('100%')
                      .height(5)
                      .color(PRIMARY)
                      .backgroundColor(SUB_CARD)
                  }
                  .width('100%')
                }, (item: SourceCount) => item.name)
              }
              .width('100%')
              .padding({ top: 4 })
            }
          }
          .padding(18)
          .width('100%')
          .backgroundColor(CARD)
          .borderRadius(20)
          .border({ width: 0.5, color: DIVIDER })

          // 2. 外观与阅读
          Column({ space: 12 }) {
            Text('外观与阅读')
              .fontSize(17)
              .fontColor(TEXT_MAIN)
              .fontWeight(FontWeight.Bold)
              .width('100%')

            SettingSelectRow({
              title: '全局色彩主题',
              subtitle: '浅色、深色或跟随系统昼夜模式',
              options: ['跟随系统', '浅色', '深色'],
              selectedIndex: this.theme,
              onChanged: (idx: number): void => {
                this.changeTheme(idx);
              }
            })

            Divider().color(DIVIDER)

            SettingSelectRow({
              title: '默认阅读模式',
              subtitle: '打开漫画时默认采用的翻页方式',
              options: this.modeLabels,
              selectedIndex: this.reader,
              onChanged: (idx: number): void => {
                this.saveOption('reader', idx);
              }
            })

            Divider().color(DIVIDER)

            SettingSelectRow({
              title: '章节预加载页数',
              subtitle: '翻页时后台提前解码缓存的页数',
              options: ['省流 (1 页)', '标准 (3 页)', '进取 (5 页)', '极速 (8 页)'],
              selectedIndex: [1, 3, 5, 8].indexOf(this.preload) >= 0 ? [1, 3, 5, 8].indexOf(this.preload) : 1,
              onChanged: (idx: number): void => {
                const counts: Array<number> = [1, 3, 5, 8];
                this.saveOption('preload', counts[idx] ?? 3);
              }
            })

            Divider().color(DIVIDER)

            Row() {
              Column({ space: 2 }) {
                Text('阅读时自动缓存原图')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary'))
                Text('开启后翻页更流畅，关闭可节省空间')
                  .fontSize(11)
                  .fontColor($r('sys.color.font_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.autoCache })
                .selectedColor(PRIMARY)
                .systemMaterial(IMMERSIVE_REGULAR_MATERIAL)
                .onChange((v: boolean) => {
                  this.saveOption('cache', v);
                })
            }
            .width('100%')
            .constraintSize({ minHeight: 48 })

            Divider().color(DIVIDER)

            Row() {
              Column({ space: 2 }) {
                Text('记录浏览历史')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary'))
                Text('在更新页保留最近阅读与浏览记录')
                  .fontSize(11)
                  .fontColor($r('sys.color.font_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.history })
                .selectedColor(PRIMARY)
                .systemMaterial(IMMERSIVE_REGULAR_MATERIAL)
                .onChange((v: boolean) => {
                  this.saveOption('history', v);
                })
            }
            .width('100%')
            .constraintSize({ minHeight: 48 })
          }
          .padding(18)
          .width('100%')
          .backgroundColor(CARD)
          .borderRadius(20)
          .border({ width: 0.5, color: DIVIDER })

          // 3. 存储与隐私
          Column({ space: 14 }) {
            Text('存储与隐私')
              .fontSize(17)
              .fontColor(TEXT_MAIN)
              .fontWeight(FontWeight.Bold)
              .width('100%')

            Row() {
              Column({ space: 2 }) {
                Text('应用锁')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary'))
                Text(this.securityLock ? '已开启，关闭前需要再次验证' : '关闭。开启后冷启动和回到前台需要验证')
                  .fontSize(11)
                  .fontColor($r('sys.color.font_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Button(this.securityLock ? '关闭' : '开启', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(PRIMARY)
                .backgroundColor(PRIMARY_SOFT)
                .height(36)
                .onClick((): void => {
                  this.confirmLock(!this.securityLock);
                })
            }
            .width('100%')
            .constraintSize({ minHeight: 48 })

            Divider().color(DIVIDER)

            Row() {
              Column({ space: 2 }) {
                Text('后台预览保护')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary'))
                Text('切到多任务时遮住画面，与应用锁分开')
                  .fontSize(11)
                  .fontColor($r('sys.color.font_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.previewOn })
                .selectedColor(PRIMARY)
                .systemMaterial(IMMERSIVE_REGULAR_MATERIAL)
                .onChange((on: boolean) => {
                  this.saveOption('preview', on);
                })
            }
            .width('100%')
            .constraintSize({ minHeight: 48 })

            Divider().color(DIVIDER)

            Button('全局屏蔽规则', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(PRIMARY)
              .backgroundColor(PRIMARY_SOFT)
              .width('100%')
              .height(40)
              .onClick(() => {
                this.stack.pushPathByName(ROUTE_BLOCK_RULES, { sourceId: '' } as MangaRouteParams);
              })

            Row({ space: 10 }) {
              Button('离线下载管理', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(PRIMARY)
                .backgroundColor(PRIMARY_SOFT)
                .layoutWeight(1)
                .height(40)
                .onClick(() => {
                  this.stack.pushPathByName(ROUTE_DOWNLOADS, {} as MangaRouteParams);
                })

              Button(`清理缓存 (${(this.cache / 1048576).toFixed(1)} MB)`, {
                type: ButtonType.Capsule,
                buttonStyle: ButtonStyleMode.NORMAL
              })
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(TEXT_MAIN)
                .backgroundColor(SUB_CARD)
                .layoutWeight(1)
                .height(40)
                .onClick(() => {
                  clearPageCache();
                  this.cache = pageCacheSize();
                  promptAction.showToast({ message: '已释放图片缓存' });
                })
            }
            .width('100%')

            Row({ space: 10 }) {
              Button('导出全量备份', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(TEXT_MAIN)
                .backgroundColor(SUB_CARD)
                .layoutWeight(1)
                .height(40)
                .onClick(() => {
                  if (!this.busy) {
                    this.backup(false);
                  }
                })

              Button('恢复备份数据', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(TEXT_MAIN)
                .backgroundColor(SUB_CARD)
                .layoutWeight(1)
                .height(40)
                .onClick(() => {
                  if (!this.busy) {
                    this.getUIContext().showAlertDialog({
                      title: '恢复全量备份',
                      message: '将使用备份文件替换当前的书架、书源配置与阅读记录，确认继续吗？',
                      primaryButton: { value: '取消', action: () => {} },
                      secondaryButton: {
                        value: '选择备份文件',
                        fontColor: PRIMARY,
                        action: () => {
                          this.backup(true);
                        }
                      }
                    });
                  }
                })
            }
            .width('100%')

            Button('清理旧版数据', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(TEXT_MAIN)
              .backgroundColor(SUB_CARD)
              .width('100%')
              .height(40)
              .onClick((): void => {
                this.cleanLegacy();
              })
          }
          .padding(18)
          .width('100%')
          .backgroundColor(CARD)
          .borderRadius(20)
          .border({ width: 0.5, color: DIVIDER })

          if (this.message !== '') {
            Text(this.message)
              .fontSize(12)
              .fontColor(TEXT_SUB)
              .textAlign(TextAlign.Center)
              .width('100%')
          }

          Column({ space: 4 }) {
            Text('漫语')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_MAIN)
            Text('版本 v1.0.0')
              .fontSize(11)
              .fontColor(TEXT_SUB)
          }
          .padding({ top: 8, bottom: 12 })
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }
        .padding({
          left: 16,
          right: 16,
          bottom: (this.breakpoint === 'lg' ? 28 : TAB_BAR_HEIGHT + 28) + this.bottomInset
        })
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
  }
}
