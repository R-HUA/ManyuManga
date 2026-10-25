import common from '@ohos.app.ability.common';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import promptAction from '@ohos.promptAction';
import userIAM_userAuth from '@ohos.userIAM.userAuth';
import uiMaterial from '@ohos.arkui.uiMaterial';
import { MangaRouteParams, ROUTE_DOWNLOADS } from '../common/Route';
import { Prefs } from '../util/Prefs';
import { library, LibraryWork } from '../data/Library';
import { readingActivity, ActivityStats } from '../data/ReadingActivity';
import { sourceStore, SourceEntry, sourceId } from '../data/Sources';
import { jmApi } from '../data/JmApi';
import { blockTagsStore } from '../data/Stores';
import { exportBackup, importBackup } from '../data/Backup';
import { clearPageCache, pageCacheSize } from '../data/ImageDecode';
import { IconCircleButton } from '../common/Components';
import {
  BG,
  CARD,
  SUB_CARD,
  TEXT_MAIN,
  TEXT_SUB,
  PRIMARY,
  PRIMARY_SOFT,
  ACCENT,
  ACCENT_SOFT,
  STATUS_OK,
  STATUS_WARN,
  DANGER,
  DANGER_SOFT,
  DIVIDER,
  TAB_BAR_HEIGHT
} from '../common/Theme';
import { Album, DomainSpeed, errorMessage } from '../models/Models';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

class SourceCount {
  name: string = '';
  count: number = 0;
}

@Component
export struct ProfilePage {
  @Consume('navPathStack') stack: NavPathStack;
  @Prop sourceOnly: boolean = false;
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
  @State message: string = '';
  @State busy: boolean = false;

  // JM Mirror & Block Tags State
  @State currentDomain: string = '';
  @State domains: Array<string> = [];
  @State speeds: Array<DomainSpeed> = [];
  @State testingSpeed: boolean = false;
  @State blockedTags: Array<string> = [];
  @State newBlockTag: string = '';
  @State blockSheet: boolean = false;

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
      this.cache = pageCacheSize();

      this.domains = jmApi.getDomains();
      this.currentDomain = this.domains.length > 0 ? this.domains[0] : '';
      this.blockedTags = await blockTagsStore.getList();
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

  private async saveOption(key: string, value: number | boolean): Promise<void> {
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
      } else if (key === 'lock') {
        const enable: boolean = value as boolean;
        if (enable) {
          try {
            userIAM_userAuth.getAvailableStatus(
              userIAM_userAuth.UserAuthType.FINGERPRINT,
              userIAM_userAuth.AuthTrustLevel.ATL1
            );
          } catch (authErr) {
            promptAction.showToast({ message: '当前设备未录入指纹或不支持生物识别锁' });
            this.securityLock = false;
            return;
          }
        }
        await prefs.setSecurityLock(enable);
        this.securityLock = enable;
        promptAction.showToast({ message: enable ? '已开启指纹隐私锁' : '已关闭指纹隐私锁' });
      } else {
        await prefs.setHistoryEnabled(value as boolean);
        this.history = value as boolean;
      }
    } catch (e) {
      this.message = errorMessage(e as Error);
    }
  }

  private async runSpeedTest(): Promise<void> {
    if (this.testingSpeed) {
      return;
    }
    this.testingSpeed = true;
    try {
      this.speeds = await jmApi.testDomains();
      promptAction.showToast({ message: '节点并发测速完成' });
    } catch (e) {
      this.message = errorMessage(e as Error);
    } finally {
      this.testingSpeed = false;
    }
  }

  private async selectDomain(domain: string): Promise<void> {
    try {
      await jmApi.setPreferredDomain(domain);
      this.domains = jmApi.getDomains();
      this.currentDomain = domain;
      promptAction.showToast({ message: `已切换至节点 ${domain}` });
    } catch (e) {
      this.message = errorMessage(e as Error);
    }
  }

  private speedFor(domain: string): DomainSpeed | undefined {
    return this.speeds.find((s: DomainSpeed) => s.domain === domain);
  }

  private async addBlockedTag(): Promise<void> {
    const raw: string = this.newBlockTag.trim();
    if (raw === '') {
      return;
    }
    try {
      const parts: Array<string> = raw.split(/\s+/);
      for (const p of parts) {
        if (p.trim() !== '') {
          await blockTagsStore.add(p.trim());
        }
      }
      this.blockedTags = await blockTagsStore.getList();
      this.newBlockTag = '';
    } catch (e) {
      this.message = errorMessage(e as Error);
    }
  }

  private async removeBlockedTag(tag: string): Promise<void> {
    try {
      await blockTagsStore.remove(tag);
      this.blockedTags = await blockTagsStore.getList();
    } catch (e) {
      this.message = errorMessage(e as Error);
    }
  }

  private async backup(restore: boolean): Promise<void> {
    this.busy = true;
    try {
      const done: boolean = restore ? await importBackup() : await exportBackup();
      if (done) {
        this.message = restore ? '备份已成功恢复，重新进入页面即生效' : '全量备份文件已导出保存';
        promptAction.showToast({ message: this.message });
        await this.load();
      }
    } catch (e) {
      this.message = errorMessage(e as Error);
    } finally {
      this.busy = false;
    }
  }

  @Builder
  private Metric(value: string, unit: string, label: string) {
    Column({ space: 4 }) {
      Row({ space: 3 }) {
        Text(value)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY)
        Text(unit)
          .fontSize(11)
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
    .borderRadius(16)
    .backgroundColor(SUB_CARD)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private BlockTagsSheet() {
    Column({ space: 16 }) {
      Text('全局内容屏蔽词')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .width('100%')

      Text('包含任意屏蔽标签的作品将在精选广场、分类片库与搜索结果中自动过滤隐藏。')
        .fontSize(12)
        .fontColor(TEXT_SUB)
        .lineHeight(18)
        .width('100%')

      Row({ space: 8 }) {
        TextInput({ text: this.newBlockTag, placeholder: '输入要屏蔽的标签词（支持空格分隔多个）' })
          .layoutWeight(1)
          .height(42)
          .borderRadius(14)
          .backgroundColor(SUB_CARD)
          .fontColor(TEXT_MAIN)
          .placeholderColor(TEXT_SUB)
          .onChange((val: string) => {
            this.newBlockTag = val;
          })
          .onSubmit(() => {
            this.addBlockedTag();
          })

        Text('添加')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .padding({ left: 16, right: 16, top: 11, bottom: 11 })
          .borderRadius(16)
          .backgroundColor(PRIMARY)
          .onClick(() => {
            this.addBlockedTag();
          })
      }
      .width('100%')

      if (this.blockedTags.length === 0) {
        Text('当前未设置任何屏蔽标签')
          .fontSize(13)
          .fontColor(TEXT_SUB)
          .padding({ top: 24, bottom: 24 })
      } else {
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.blockedTags, (tag: string) => {
              Row({ space: 6 }) {
                Text(tag)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(TEXT_MAIN)
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(12)
                  .fontColor([TEXT_SUB])
              }
              .padding({ left: 12, right: 10, top: 7, bottom: 7 })
              .margin({ right: 8, bottom: 8 })
              .borderRadius(14)
              .backgroundColor(SUB_CARD)
              .onClick(() => {
                this.removeBlockedTag(tag);
              })
            }, (tag: string) => tag)
          }
          .width('100%')
        }
        .constraintSize({ maxHeight: 220 })
        .width('100%')
      }

      Text('完成')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(44)
        .borderRadius(22)
        .backgroundColor(PRIMARY)
        .onClick(() => {
          this.blockSheet = false;
        })
    }
    .padding({ left: 24, right: 24, top: 16, bottom: 28 + this.bottomInset })
    .width('100%')
  }

  build() {
    Column() {
      // Top Bar
      Row({ space: 10 }) {
        if (this.sourceOnly) {
          IconCircleButton({
            glyph: $r('sys.symbol.chevron_left'),
            onTap: (): void => {
              this.stack.pop();
            }
          })
        }
        Text(this.sourceOnly ? 'JMComic 节点与过滤设置' : '漫迹与偏好')
          .fontSize(this.sourceOnly ? 18 : 26)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.top + 10, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 16 }) {
          if (!this.sourceOnly) {
            // 1. 漫迹统计看板
            Column({ space: 14 }) {
              Row() {
                Text('漫迹统计看板')
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
                this.Metric(`${this.bookCount}`, '部', '书架藏书')
                this.Metric(`${this.stats.pages.length}`, '页', '累计翻阅')
                this.Metric(`${Math.floor(this.stats.milliseconds / 60000)}`, '分', '专注时长')
              }
              .width('100%')

              if (this.distribution.length > 0) {
                Column({ space: 8 }) {
                  Text('藏书图源分布')
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

            // 2. 光感外观与阅读器预设
            Column({ space: 16 }) {
              Text('光感外观与阅读预设')
                .fontSize(17)
                .fontColor(TEXT_MAIN)
                .fontWeight(FontWeight.Bold)
                .width('100%')

              Column({ space: 8 }) {
                Text('全局色彩主题')
                  .fontSize(13)
                  .fontColor(TEXT_SUB)
                Row({ space: 8 }) {
                  ForEach(['跟随系统', '晨曦浅色', '曜石深色'], (label: string, idx: number) => {
                    Text(label)
                      .fontSize(13)
                      .fontWeight(this.theme === idx ? FontWeight.Bold : FontWeight.Medium)
                      .fontColor(this.theme === idx ? Color.White : TEXT_MAIN)
                      .textAlign(TextAlign.Center)
                      .layoutWeight(1)
                      .padding({ top: 9, bottom: 9 })
                      .borderRadius(16)
                      .backgroundColor(this.theme === idx ? PRIMARY : SUB_CARD)
                      .onClick(() => {
                        this.changeTheme(idx);
                      })
                  }, (label: string) => label)
                }
                .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              Column({ space: 8 }) {
                Text('默认阅读模式')
                  .fontSize(13)
                  .fontColor(TEXT_SUB)
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.modeLabels, (label: string, idx: number) => {
                    Text(label)
                      .fontSize(12)
                      .fontWeight(this.reader === idx ? FontWeight.Bold : FontWeight.Medium)
                      .fontColor(this.reader === idx ? Color.White : TEXT_MAIN)
                      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                      .margin({ right: 8, bottom: 8 })
                      .borderRadius(14)
                      .backgroundColor(this.reader === idx ? PRIMARY : SUB_CARD)
                      .onClick(() => {
                        this.saveOption('reader', idx);
                      })
                  }, (label: string) => label)
                }
                .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              Column({ space: 6 }) {
                Row() {
                  Text('章节预加载页数')
                    .fontSize(13)
                    .fontColor(TEXT_MAIN)
                    .layoutWeight(1)
                  Text(`${this.preload} 页`)
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(PRIMARY)
                }
                .width('100%')

                Slider({ value: this.preload, min: 1, max: 8, step: 1, style: SliderStyle.OutSet })
                  .selectedColor(PRIMARY)
                  .trackColor(DIVIDER)
                  .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
                  .onChange((v: number, mode: SliderChangeMode) => {
                    const rounded: number = Math.round(v);
                    this.preload = rounded;
                    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                      this.saveOption('preload', rounded);
                    }
                  })
              }
              .width('100%')

              Row() {
                Column({ space: 2 }) {
                  Text('阅读时自动缓存原图')
                    .fontSize(14)
                    .fontColor(TEXT_MAIN)
                  Text('开启后翻页更丝滑，关闭可节省存储空间')
                    .fontSize(11)
                    .fontColor(TEXT_SUB)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.autoCache })
                  .selectedColor(PRIMARY)
                  .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
                  .onChange((v: boolean) => {
                    this.saveOption('cache', v);
                  })
              }
              .width('100%')

              Row() {
                Column({ space: 2 }) {
                  Text('记录作品浏览足迹')
                    .fontSize(14)
                    .fontColor(TEXT_MAIN)
                  Text('在「动态」页保留最近查看过的漫画')
                    .fontSize(11)
                    .fontColor(TEXT_SUB)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.history })
                  .selectedColor(PRIMARY)
                  .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
                  .onChange((v: boolean) => {
                    this.saveOption('history', v);
                  })
              }
              .width('100%')
            }
            .padding(18)
            .width('100%')
            .backgroundColor(CARD)
            .borderRadius(20)
            .border({ width: 0.5, color: DIVIDER })
          }

          // 3. JMComic 镜像节点测速与屏蔽词管理
          Column({ space: 14 }) {
            Row() {
              Column({ space: 2 }) {
                Text('JMComic 镜像节点与内容过滤')
                  .fontSize(17)
                  .fontColor(TEXT_MAIN)
                  .fontWeight(FontWeight.Bold)
                Text(`当前生效线路：${this.currentDomain || '默认线路'}`)
                  .fontSize(11)
                  .fontColor(TEXT_SUB)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.testingSpeed ? '测速中…' : '并发测速')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .borderRadius(14)
                .backgroundColor(PRIMARY)
                .opacity(this.testingSpeed ? 0.6 : 1.0)
                .onClick(() => {
                  this.runSpeedTest();
                })
            }
            .width('100%')

            Column({ space: 8 }) {
              ForEach(this.domains, (domain: string) => {
                Row({ space: 10 }) {
                  Circle({ width: 7, height: 7 })
                    .fill(domain === this.currentDomain ? STATUS_OK : TEXT_SUB)
                  Text(domain)
                    .fontSize(13)
                    .fontWeight(domain === this.currentDomain ? FontWeight.Bold : FontWeight.Medium)
                    .fontColor(domain === this.currentDomain ? PRIMARY : TEXT_MAIN)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  if (this.speedFor(domain) !== undefined) {
                    Text(this.speedFor(domain)!.ok ? `${this.speedFor(domain)!.ms} ms` : '不可达')
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.speedFor(domain)!.ok ? STATUS_OK : DANGER)
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .borderRadius(8)
                      .backgroundColor(CARD)
                  }

                  Text(domain === this.currentDomain ? '当前' : '切换')
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(domain === this.currentDomain ? TEXT_SUB : PRIMARY)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .borderRadius(12)
                    .backgroundColor(domain === this.currentDomain ? CARD : PRIMARY_SOFT)
                    .onClick(() => {
                      if (domain !== this.currentDomain) {
                        this.selectDomain(domain);
                      }
                    })
                }
                .padding({ left: 12, right: 10, top: 9, bottom: 9 })
                .borderRadius(14)
                .backgroundColor(SUB_CARD)
                .width('100%')
              }, (domain: string) => `${domain}_${domain === this.currentDomain}_${this.speedFor(domain)?.ms ?? -1}`)
            }
            .width('100%')

            Divider().color(DIVIDER)

            Row() {
              Column({ space: 2 }) {
                Text('全局屏蔽标签过滤')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(TEXT_MAIN)
                Text(`已配置 ${this.blockedTags.length} 个屏蔽词`)
                  .fontSize(11)
                  .fontColor(TEXT_SUB)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text('管理屏蔽词')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(PRIMARY)
                .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                .borderRadius(16)
                .backgroundColor(PRIMARY_SOFT)
                .onClick(() => {
                  this.blockSheet = true;
                })
            }
            .width('100%')
          }
          .padding(18)
          .width('100%')
          .backgroundColor(CARD)
          .borderRadius(20)
          .border({ width: 0.5, color: DIVIDER })

          // 4. 隐私安全、离线缓存与数据备份
          if (!this.sourceOnly) {
            Column({ space: 14 }) {
              Text('隐私安全与数据资产')
                .fontSize(17)
                .fontColor(TEXT_MAIN)
                .fontWeight(FontWeight.Bold)
                .width('100%')

              Row() {
                Column({ space: 2 }) {
                  Text('生物识别指纹隐私锁')
                    .fontSize(14)
                    .fontColor(TEXT_MAIN)
                  Text('启动或从后台返回时需验证指纹，同时开启后台多任务高斯遮罩')
                    .fontSize(11)
                    .fontColor(TEXT_SUB)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.securityLock })
                  .selectedColor(PRIMARY)
                  .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
                  .onChange((v: boolean) => {
                    this.saveOption('lock', v);
                  })
              }
              .width('100%')

              Row({ space: 10 }) {
                Text('离线下载与 CBZ 导出')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
                  .height(42)
                  .borderRadius(21)
                  .backgroundColor(PRIMARY)
                  .onClick(() => {
                    this.stack.pushPathByName(ROUTE_DOWNLOADS, {} as MangaRouteParams);
                  })

                Text(`清理缓存 (${(this.cache / 1048576).toFixed(1)} MB)`)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(TEXT_MAIN)
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
                  .height(42)
                  .borderRadius(21)
                  .backgroundColor(SUB_CARD)
                  .onClick(() => {
                    clearPageCache();
                    this.cache = pageCacheSize();
                    promptAction.showToast({ message: '已释放图片解码内存缓存' });
                  })
              }
              .width('100%')

              Row({ space: 10 }) {
                Text('导出全量备份')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(TEXT_MAIN)
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
                  .height(42)
                  .borderRadius(21)
                  .backgroundColor(SUB_CARD)
                  .onClick(() => {
                    if (!this.busy) {
                      this.backup(false);
                    }
                  })

                Text('恢复备份数据')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(TEXT_MAIN)
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
                  .height(42)
                  .borderRadius(21)
                  .backgroundColor(SUB_CARD)
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
            }
            .padding(18)
            .width('100%')
            .backgroundColor(CARD)
            .borderRadius(20)
            .border({ width: 0.5, color: DIVIDER })
          }

          if (this.message !== '') {
            Text(this.message)
              .fontSize(12)
              .fontColor(TEXT_SUB)
              .textAlign(TextAlign.Center)
              .width('100%')
          }

          Column({ space: 4 }) {
            Text('漫屿 · LuminaManga')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_MAIN)
            Text('HarmonyOS API 26 · 沉浸光感多源聚合阅读器 v1.0.0')
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
          bottom: (this.sourceOnly ? 28 : (this.breakpoint === 'lg' ? 28 : TAB_BAR_HEIGHT + 28)) + this.bottomInset
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
    .bindSheet($$this.blockSheet, this.BlockTagsSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: CARD,
      systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK })
    })
  }
}
