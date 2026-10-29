import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HDS_TITLE_STYLE } from '../../common/ImmersiveMaterials';
import { SettingSelectRow } from '../../common/Components';
import { BG, CARD, DIVIDER, TEXT_SUB } from '../../common/Theme';
import { errorMessage } from '../../models/Models';
import {
  PRELOAD_COUNTS, PRELOAD_LABELS, READER_MODE_LABELS, SettingsSnapshot, loadSettings, preloadIndex,
  saveAutoCache, saveHistory, savePreload, saveReaderMode, saveTapTurn
} from '../../data/SettingsService';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';
import { SettingsToggleRow, settingsRowRadius } from './SettingsRows';

/** 阅读设置：默认阅读模式、预加载、自动缓存原图与阅读历史。 */
@Component
export struct ReaderSettingsPage {
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  @State reader: number = 0;
  @State preload: number = 3;
  @State autoCache: boolean = true;
  @State history: boolean = true;
  @State tapTurn: boolean = true;
  @State message: string = '';
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.load();
  }

  async load(): Promise<void> {
    try {
      const snapshot: SettingsSnapshot = await loadSettings();
      this.reader = snapshot.reader;
      this.preload = snapshot.preload;
      this.autoCache = snapshot.autoCache;
      this.history = snapshot.history;
      this.tapTurn = snapshot.tapTurn;
    } catch (e) {
      this.report(errorMessage(e as Error));
    }
  }

  async saveOption(key: string, value: Object): Promise<void> {
    try {
      if (key === 'reader') {
        await saveReaderMode(value as number);
        this.reader = value as number;
      } else if (key === 'preload') {
        await savePreload(value as number);
        this.preload = value as number;
      } else if (key === 'cache') {
        this.autoCache = value as boolean;
        await saveAutoCache(value as boolean);
      } else if (key === 'tapTurn') {
        this.tapTurn = value as boolean;
        await saveTapTurn(value as boolean);
      } else if (key === 'history') {
        this.history = value as boolean;
        await saveHistory(value as boolean);
      }
    } catch (e) {
      // 开关先乐观更新，失败时回写原值，使原生控件同步复位。
      if (key === 'cache') { this.autoCache = !(value as boolean); }
      if (key === 'history') { this.history = !(value as boolean); }
      if (key === 'tapTurn') { this.tapTurn = !(value as boolean); }
      this.report(errorMessage(e as Error));
    }
  }

  private report(message: string): void {
    this.message = message;
    this.getUIContext().getPromptAction().showToast({ message: `设置未保存：${message}` });
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
        ListItemGroup({ header: this.GroupHeader('翻页'), footer: this.GroupFooter('新打开的漫画按默认模式阅读，阅读器内可单独切换。') }) {
          ListItem() {
            SettingSelectRow({
              title: '默认阅读模式',
              subtitle: '',
              options: READER_MODE_LABELS,
              selectedIndex: this.reader,
              onChanged: (idx: number): void => { this.saveOption('reader', idx); }
            })
              .padding({ left: 12, right: 12 })
          }
          .backgroundColor(CARD).borderRadius(settingsRowRadius(0, 2))
          ListItem() {
            SettingSelectRow({
              title: '章节预加载页数',
              subtitle: '',
              options: PRELOAD_LABELS,
              selectedIndex: preloadIndex(this.preload),
              onChanged: (idx: number): void => { this.saveOption('preload', PRELOAD_COUNTS[idx] ?? 3); }
            })
              .padding({ left: 12, right: 12 })
          }
          .backgroundColor(CARD).borderRadius(settingsRowRadius(1, 2))
        }
        .divider({ strokeWidth: '1px', color: DIVIDER, startMargin: 12, endMargin: 12 })

        ListItemGroup({ header: this.GroupHeader('点按'), footer: this.GroupFooter('关闭后点按画面任意位置只呼出菜单，仍可滑动翻页。') }) {
          ListItem() {
            SettingsToggleRow({ title: '点击左右两侧翻页', isOn: this.tapTurn,
              onToggle: (on: boolean): void => { this.saveOption('tapTurn', on); } })
          }
          .backgroundColor(CARD).borderRadius(settingsRowRadius(0, 1))
        }

        ListItemGroup({ header: this.GroupHeader('缓存与记录'), footer: this.GroupFooter('关闭阅读历史后，书架不再更新续读进度。') }) {
          ListItem() {
            SettingsToggleRow({ title: '阅读时自动缓存原图', isOn: this.autoCache,
              onToggle: (on: boolean): void => { this.saveOption('cache', on); } })
          }
          .backgroundColor(CARD).borderRadius(settingsRowRadius(0, 2))
          ListItem() {
            SettingsToggleRow({ title: '记录阅读历史', isOn: this.history,
              onToggle: (on: boolean): void => { this.saveOption('history', on); } })
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
    .titleBar({ content: { title: { mainTitle: '阅读设置' } }, style: HDS_TITLE_STYLE,
      avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller])
    .backgroundColor(BG)
  }
}
