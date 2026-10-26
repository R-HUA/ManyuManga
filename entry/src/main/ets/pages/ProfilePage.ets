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

  private openBackupMenu(): void {
    this.getUIContext().showAlertDialog({
      title: '全量备份与恢复',
      message: '请选择导出备份文件或从文件恢复备份：',
      primaryButton: {
        value: '导出备份',
        fontColor: PRIMARY,
        action: () => {
          if (!this.busy) {
            this.backup(false);
          }
        }
      },
      secondaryButton: {
        value: '恢复备份',
        fontColor: PRIMARY,
        action: () => {
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
        }
      }
    });
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

  @Builder
  private NavRow(icon: Resource, title: string, valueText: string, onTap: () => void) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([PRIMARY])
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_MAIN)
        .layoutWeight(1)
      if (valueText !== '') {
        Text(valueText)
          .fontSize(13)
          .fontColor(TEXT_SUB)
      }
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([TEXT_SUB])
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .alignItems(VerticalAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  private ToggleRow(icon: Resource, title: string, isOn: boolean, onChange: (val: boolean) => void) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([PRIMARY])
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_MAIN)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(PRIMARY)
        .systemMaterial(IMMERSIVE_REGULAR_MATERIAL)
        .onChange((v: boolean) => {
          onChange(v);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: 10 }) {
        Text('我的')
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
          // 1. 阅读统计看板
          Column({ space: 14 }) {
            Row() {
              Text('漫屿阅读看板')
                .fontSize(16)
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
          }
          .padding(18)
          .width('100%')
          .backgroundColor(CARD)
          .borderRadius(20)
          .border({ width: 0.5, color: DIVIDER })

          // 2. 常用功能快捷入口
          Column({ space: 6 }) {
            this.NavRow($r('sys.symbol.arrow_down_circle'), '离线下载与导出', '', () => {
              this.stack.pushPathByName(ROUTE_DOWNLOADS, {} as MangaRouteParams);
            })
            Divider().color(DIVIDER).margin({ left: 32 })
            this.NavRow($r('sys.symbol.shield_checkered'), '全局屏蔽规则', '', () => {
              this.stack.pushPathByName(ROUTE_BLOCK_RULES, { sourceId: '' } as MangaRouteParams);
            })
          }
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .width('100%')
          .backgroundColor(CARD)
          .borderRadius(20)
          .border({ width: 0.5, color: DIVIDER })

          // 3. 外观与阅读偏好
          Column({ space: 4 }) {
            SettingSelectRow({
              title: '全局色彩主题',
              subtitle: '',
              options: ['跟随系统', '浅色', '深色'],
              selectedIndex: this.theme,
              onChanged: (idx: number): void => {
                this.changeTheme(idx);
              }
            })
            Divider().color(DIVIDER).margin({ left: 16 })

            SettingSelectRow({
              title: '默认阅读模式',
              subtitle: '',
              options: this.modeLabels,
              selectedIndex: this.reader,
              onChanged: (idx: number): void => {
                this.saveOption('reader', idx);
              }
            })
            Divider().color(DIVIDER).margin({ left: 16 })

            SettingSelectRow({
              title: '章节预加载页数',
              subtitle: '',
              options: ['省流 (1 页)', '标准 (3 页)', '进取 (5 页)', '极速 (8 页)'],
              selectedIndex: [1, 3, 5, 8].indexOf(this.preload) >= 0 ? [1, 3, 5, 8].indexOf(this.preload) : 1,
              onChanged: (idx: number): void => {
                const counts: Array<number> = [1, 3, 5, 8];
                this.saveOption('preload', counts[idx] ?? 3);
              }
            })
            Divider().color(DIVIDER).margin({ left: 16 })

            Row() {
              Text('阅读时自动缓存原图')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
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

            Divider().color(DIVIDER).margin({ left: 16 })

            Row() {
              Text('记录浏览历史')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
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
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .width('100%')
          .backgroundColor(CARD)
          .borderRadius(20)
          .border({ width: 0.5, color: DIVIDER })

          // 4. 存储、隐私与数据备份
          Column({ space: 4 }) {
            this.ToggleRow($r('sys.symbol.lock_fill'), '应用锁保护', this.securityLock, (on: boolean) => {
              this.confirmLock(on);
            })
            Divider().color(DIVIDER).margin({ left: 32 })

            this.ToggleRow($r('sys.symbol.eye_slash'), '后台多任务模糊保护', this.previewOn, (on: boolean) => {
              this.saveOption('preview', on);
            })
            Divider().color(DIVIDER).margin({ left: 32 })

            this.NavRow($r('sys.symbol.arrow_clockwise'), '全量备份与恢复', '', () => {
              this.openBackupMenu();
            })
            Divider().color(DIVIDER).margin({ left: 32 })

            this.NavRow(
              $r('sys.symbol.trash'),
              '清理图片缓存',
              `${(this.cache / 1048576).toFixed(1)} MB`,
              () => {
                clearPageCache();
                this.cache = pageCacheSize();
                promptAction.showToast({ message: '已释放图片缓存' });
              }
            )
            Divider().color(DIVIDER).margin({ left: 32 })

            this.NavRow($r('sys.symbol.exclamationmark_circle'), '清理旧版遗留数据', '', () => {
              this.cleanLegacy();
            })
          }
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
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

          // 品牌标识
          Column({ space: 4 }) {
            Text('漫屿')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_MAIN)
            Text('Manyu Manga v1.0.0')
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
