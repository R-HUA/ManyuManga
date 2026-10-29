import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import common from '@ohos.app.ability.common';
import { HDS_TITLE_STYLE } from '../../common/ImmersiveMaterials';
import { SettingSelectRow } from '../../common/Components';
import { BG, CARD, TEXT_SUB } from '../../common/Theme';
import { errorMessage } from '../../models/Models';
import { THEME_LABELS, SettingsSnapshot, loadSettings, saveTheme } from '../../data/SettingsService';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';
import { settingsRowRadius } from './SettingsRows';

/** 外观：全局色彩主题。 */
@Component
export struct AppearancePage {
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  @State theme: number = 0;
  @State message: string = '';
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.load();
  }

  async load(): Promise<void> {
    try {
      const snapshot: SettingsSnapshot = await loadSettings();
      this.theme = snapshot.theme;
    } catch (e) {
      this.message = errorMessage(e as Error);
    }
  }

  async changeTheme(index: number): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      await saveTheme(index, context);
      this.theme = index;
    } catch (e) {
      this.message = errorMessage(e as Error);
      this.getUIContext().getPromptAction().showToast({ message: `主题切换失败：${this.message}` });
    }
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
        ListItemGroup({ header: this.GroupHeader('主题'), footer: this.GroupFooter('跟随系统时随系统深浅色自动切换；阅读器画布颜色在阅读器内单独设置。') }) {
          ListItem() {
            SettingSelectRow({
              title: '全局色彩主题',
              subtitle: '',
              options: THEME_LABELS,
              selectedIndex: this.theme,
              onChanged: (idx: number): void => { this.changeTheme(idx); }
            })
              .padding({ left: 12, right: 12 })
          }
          .backgroundColor(CARD).borderRadius(settingsRowRadius(0, 1))
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16 })
      .contentEndOffset(28 + this.bottomInset)
      .scrollBar(BarState.Off)
      .clip(false)
    }
    .titleBar({ content: { title: { mainTitle: '外观' } }, style: HDS_TITLE_STYLE,
      avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller])
    .backgroundColor(BG)
  }
}
