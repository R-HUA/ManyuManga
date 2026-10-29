import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HDS_TITLE_STYLE } from '../../common/ImmersiveMaterials';
import { BG, CARD, DIVIDER, TEXT_SUB } from '../../common/Theme';
import { errorMessage } from '../../models/Models';
import { SettingsSnapshot, confirmSecurityLock, loadSettings, savePreview } from '../../data/SettingsService';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';
import { SettingsToggleRow, settingsRowRadius } from './SettingsRows';

/** 隐私与安全：应用锁、多任务预览隐私保护。 */
@Component
export struct PrivacyPage {
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  @State securityLock: boolean = false;
  @State previewOn: boolean = true;
  @State privacyBusy: boolean = false;
  @State lockBusy: boolean = false;
  @State message: string = '';
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.load();
  }

  async load(): Promise<void> {
    this.privacyBusy = true;
    try {
      const snapshot: SettingsSnapshot = await loadSettings();
      this.securityLock = snapshot.securityLock;
      this.previewOn = snapshot.previewOn;
    } catch (e) {
      this.message = errorMessage(e as Error);
    } finally {
      this.privacyBusy = false;
    }
  }

  async saveOption(key: string, value: Object): Promise<void> {
    if (key !== 'preview' || this.privacyBusy || value === this.previewOn) { return; }
    const previous: boolean = this.previewOn;
    this.privacyBusy = true;
    this.previewOn = value as boolean;
    try {
      const windowName: string | undefined = this.getUIContext().getWindowName();
      if (windowName === undefined) { throw new Error('无法获取当前窗口'); }
      await savePreview(value as boolean, windowName);
      this.previewOn = value as boolean;
    } catch (e) {
      this.previewOn = previous;
      this.message = errorMessage(e as Error);
      this.getUIContext().getPromptAction().showToast({ message: `隐私保护设置失败：${this.message}` });
    } finally {
      this.privacyBusy = false;
    }
  }

  async confirmLock(enable: boolean): Promise<void> {
    if (this.lockBusy) { return; }
    const previous: boolean = this.securityLock;
    this.lockBusy = true;
    this.securityLock = enable;
    try {
      const failure: string = await confirmSecurityLock(enable);
      if (failure !== '') {
        this.securityLock = previous;
        this.message = failure;
        this.getUIContext().getPromptAction().showToast({ message: failure });
      } else {
        this.message = '';
      }
    } catch (e) {
      this.securityLock = previous;
      this.message = errorMessage(e as Error);
      this.getUIContext().getPromptAction().showToast({ message: this.message });
    } finally {
      this.lockBusy = false;
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
        ListItemGroup({ header: this.GroupHeader('应用锁'), footer: this.GroupFooter('开启或关闭前需要验证人脸、指纹或锁屏密码；开启后每次回到应用都需验证。') }) {
          ListItem() {
            SettingsToggleRow({ title: '应用锁保护', isOn: this.securityLock, switchEnabled: !this.lockBusy,
              onToggle: (on: boolean): void => { this.confirmLock(on); } })
          }
          .backgroundColor(CARD).borderRadius(settingsRowRadius(0, 1))
        }

        ListItemGroup({ header: this.GroupHeader('隐私保护'), footer: this.GroupFooter('开启后多任务界面不显示应用内容，并禁止截屏与录屏。') }) {
          ListItem() {
            SettingsToggleRow({ title: '隐私保护', isOn: this.previewOn, switchEnabled: !this.privacyBusy,
              onToggle: (on: boolean): void => { this.saveOption('preview', on); } })
          }
          .backgroundColor(CARD).borderRadius(settingsRowRadius(0, 1))
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
    .titleBar({ content: { title: { mainTitle: '隐私与安全' } }, style: HDS_TITLE_STYLE,
      avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller])
    .backgroundColor(BG)
  }
}
