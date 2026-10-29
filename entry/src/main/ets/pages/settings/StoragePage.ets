import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HDS_TITLE_STYLE } from '../../common/ImmersiveMaterials';
import { SettingSelectRow } from '../../common/Components';
import { clearPageCache, pageCacheSize } from '../../data/ImageDecode';
import { BG, CARD, DIVIDER, DANGER, PRIMARY, TEXT_SUB } from '../../common/Theme';
import { errorMessage } from '../../models/Models';
import { SettingsSnapshot, cleanLegacy, loadSettings, runBackup, saveArchiveQuality } from '../../data/SettingsService';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';
import { SettingsActionRow, settingsRowRadius } from './SettingsRows';

/** 存储与备份：导出画质、图片缓存、全量备份恢复与旧版数据清理。所有破坏性操作先确认、后 Toast。 */
@Component
export struct StoragePage {
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  @State archiveQuality: number = 0;
  @State cache: number = 0;
  @State busy: boolean = false;
  @State message: string = '';
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.load();
  }

  async load(): Promise<void> {
    try {
      const snapshot: SettingsSnapshot = await loadSettings();
      this.archiveQuality = snapshot.archiveQuality;
      this.cache = pageCacheSize();
    } catch (e) {
      this.message = errorMessage(e as Error);
    }
  }

  async saveOption(key: string, value: Object): Promise<void> {
    if (key !== 'archiveQuality') { return; }
    try {
      await saveArchiveQuality(value as number);
      this.archiveQuality = value as number;
    } catch (e) {
      this.message = errorMessage(e as Error);
      this.toast(`设置未保存：${this.message}`);
    }
  }

  cacheLabel(): string {
    return `${(this.cache / 1048576).toFixed(1)} MB`;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  confirmClearCache(): void {
    this.getUIContext().showAlertDialog({
      title: '清理图片缓存',
      message: `将释放约 ${this.cacheLabel()} 的在线阅读缓存，离线下载的漫画不受影响。`,
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: {
        value: '清理',
        fontColor: DANGER,
        action: (): void => {
          clearPageCache();
          this.cache = pageCacheSize();
          this.toast('已释放图片缓存');
        }
      }
    });
  }

  async backup(isRestore: boolean): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      const ok: boolean = await runBackup(isRestore);
      if (ok) {
        await this.load();
        this.toast(isRestore ? '备份数据恢复成功' : '备份导出成功');
      }
    } catch (e) {
      this.message = errorMessage(e as Error);
      this.toast(isRestore ? `恢复失败：${this.message}` : `导出失败：${this.message}`);
    } finally {
      this.busy = false;
    }
  }

  confirmRestore(): void {
    if (this.busy) { return; }
    this.getUIContext().showAlertDialog({
      title: '恢复全量备份',
      message: '将使用备份文件替换当前的书架、书源配置与阅读记录，确认继续吗？',
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: { value: '选择备份文件', fontColor: PRIMARY, action: (): void => { this.backup(true); } }
    });
  }

  confirmCleanLegacy(): void {
    if (this.busy) { return; }
    this.getUIContext().showAlertDialog({
      title: '清理旧版数据',
      message: '将删除旧版本遗留的记录、书源配置和旧离线目录。当前书架、离线漫画和已导出文件会保留。',
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: {
        value: '清理',
        fontColor: DANGER,
        action: (): void => {
          this.busy = true;
          cleanLegacy().then((): void => {
            this.message = '';
            this.cache = pageCacheSize();
            this.toast('已清理旧版数据');
          }).catch((e: Error) => {
            this.message = errorMessage(e);
            this.toast(`清理失败：${this.message}`);
          }).finally((): void => {
            this.busy = false;
          });
        }
      }
    });
  }

  @Builder
  private GroupHeader(title: string) {
    Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(TEXT_SUB)
      .width('100%').padding({ left: 12, top: 16, bottom: 8 })
  }

  @Builder
  private GroupFooter(text: string) {
    Text(text).fontSize(12).fontColor(TEXT_SUB).width('100%').padding({ left: 12, right: 12, top: 8 })
  }

  build() {
    HdsNavDestination() {
      List({ scroller: this.scroller }) {
        ListItemGroup({ header: this.GroupHeader('导出'), footer: this.GroupFooter('影响导出 CBZ 时的图片编码质量。') }) {
          ListItem() {
            SettingSelectRow({
              title: $r('app.string.export_quality'),
              options: [$r('app.string.export_quality_visual'), $r('app.string.export_quality_compact')],
              selectedIndex: this.archiveQuality,
              onChanged: (index: number): void => { this.saveOption('archiveQuality', index); }
            })
              .padding({ left: 12, right: 12 })
          }
          .backgroundColor(CARD).borderRadius(settingsRowRadius(0, 1))
        }

        ListItemGroup({ header: this.GroupHeader('备份'), footer: this.GroupFooter('备份包含书架、书源配置、屏蔽规则与阅读记录，不含离线图片。') }) {
          ListItem() {
            SettingsActionRow({ title: '导出备份', rowEnabled: !this.busy,
              onTap: (): void => { this.backup(false); } })
          }
          .backgroundColor(CARD).borderRadius(settingsRowRadius(0, 2))
          ListItem() {
            SettingsActionRow({ title: '从文件恢复', rowEnabled: !this.busy,
              onTap: (): void => { this.confirmRestore(); } })
          }
          .backgroundColor(CARD).borderRadius(settingsRowRadius(1, 2))
        }
        .divider({ strokeWidth: '1px', color: DIVIDER, startMargin: 12, endMargin: 12 })

        ListItemGroup({ header: this.GroupHeader('清理'), footer: this.GroupFooter('清理操作不会删除书架和离线下载的漫画。') }) {
          ListItem() {
            SettingsActionRow({ title: '清理图片缓存', value: this.cacheLabel(), showChevron: false,
              rowEnabled: !this.busy, onTap: (): void => { this.confirmClearCache(); } })
          }
          .backgroundColor(CARD).borderRadius(settingsRowRadius(0, 2))
          ListItem() {
            SettingsActionRow({ title: '清理旧版遗留数据', danger: true, showChevron: false,
              rowEnabled: !this.busy, onTap: (): void => { this.confirmCleanLegacy(); } })
          }
          .backgroundColor(CARD).borderRadius(settingsRowRadius(1, 2))
        }
        .divider({ strokeWidth: '1px', color: DIVIDER, startMargin: 12, endMargin: 12 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16 })
      .contentEndOffset(28 + this.bottomInset)
      .scrollBar(BarState.Off)
      .clip(false)
    }
    .titleBar({ content: { title: { mainTitle: '存储与备份' } }, style: HDS_TITLE_STYLE,
      avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller])
    .backgroundColor(BG)
  }
}
