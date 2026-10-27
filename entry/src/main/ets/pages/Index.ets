/**
 * 唯一 @Entry 页面。
 *  1. 主题生效：aboutToAppear/onPageShow 读取 themeMode 偏好并经 ApplicationContext.setColorMode 应用。
 *  2. 应用锁：锁开启时，应用启动 / 回到前台（onPageShow）先以不透明全屏遮罩拦截，经 userAuth 指纹验证通过后才放行。
 *  3. 返回逻辑：栈内二级页先 pop；栈空且非首页 Tab 先回书架 Tab，已在书架 Tab 才默认退出。
 */
import common from '@ohos.app.ability.common';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import { MainShell } from './MainShell';
import { PRIMARY } from '../common/Theme';
import { Prefs, getAppContext } from '../util/Prefs';
import { APP_IN_BACKGROUND_KEY } from '../entryability/EntryAbility';
import { NAV_STACK_DEPTH_KEY } from '../common/Route';
import { AuthOutcome, authenticate } from '../util/AppLock';

const MAIN_TAB_INDEX_KEY: string = 'mainTabIndex';

function applyThemeModeToApp(context: common.Context, mode: string): void {
  try {
    const appCtx: common.ApplicationContext = context.getApplicationContext();
    const cm: number = mode === 'dark'
      ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : mode === 'light'
        ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    appCtx.setColorMode(cm);
  } catch (_e) {}
}

@Entry
@Component
struct Index {
  @State locked: boolean = true;
  @State lockMsg: string = '';
  @State lockEnabled: boolean = false;
  @State previewOn: boolean = true;
  @State authActive: boolean = false;
  @StorageProp(APP_IN_BACKGROUND_KEY) @Watch('onBackground') inBackground: boolean = false;
  private leftForeground: boolean = false;
  private coldChecked: boolean = false;

  aboutToAppear(): void {
    this.applyThemeFromPrefs();
  }

  onPageShow(): void {
    this.applyThemeFromPrefs();
    if (!this.coldChecked) {
      this.coldChecked = true;
      this.armLock();
    }
  }

  onBackground(): void {
    if (this.authActive) {
      return;
    }
    if (this.inBackground) {
      this.leftForeground = true;
      return;
    }
    if (this.leftForeground) {
      this.leftForeground = false;
      this.armLock();
    }
  }

  onBackPress(): boolean {
    const depth: number | undefined = AppStorage.get<number>(NAV_STACK_DEPTH_KEY);
    if (depth !== undefined && depth > 0) {
      return false;
    }
    const idx: number | undefined = AppStorage.get<number>(MAIN_TAB_INDEX_KEY);
    if (idx !== undefined && idx !== 0) {
      AppStorage.setOrCreate(MAIN_TAB_INDEX_KEY, 0);
      return true;
    }
    return false;
  }

  private applyThemeFromPrefs(): void {
    Prefs.getInstance().then((p: Prefs): Promise<string> => p.themeMode()).then((mode: string) => {
      applyThemeModeToApp(getAppContext(), mode);
    }).catch(() => {});
  }

  private armLock(): void {
    this.locked = true;
    Prefs.getInstance().then(async (p: Prefs): Promise<void> => {
      this.lockEnabled = await p.securityLock();
      this.previewOn = await p.previewProtection();
      if (!this.lockEnabled) {
        this.locked = false;
        return;
      }
      if (this.authActive) {
        return;
      }
      this.locked = true;
      this.lockMsg = '';
      this.beginAuth();
    }).catch((): void => {
      this.locked = true;
      this.lockMsg = '暂时无法确认应用锁状态，请重试';
    });
  }

  private async beginAuth(): Promise<void> {
    if (this.authActive) {
      return;
    }
    this.authActive = true;
    try {
      const outcome: AuthOutcome = await authenticate('验证身份以继续');
      if (outcome.ok) {
        this.locked = false;
        this.lockMsg = '';
        return;
      }
      this.locked = true;
      this.lockMsg = outcome.message === '' ? '验证未通过，请重试' : outcome.message;
    } catch (e) {
      this.locked = true;
      this.lockMsg = '无法开始身份验证，请重试';
    } finally {
      this.authActive = false;
    }
  }

  @Builder
  private LockOverlay() {
    Column({ space: 18 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.lock_fill'))
          .fontSize(34)
          .fontColor([PRIMARY])
      }
      .width(76)
      .height(76)
      .borderRadius(38)
      .backgroundColor('rgba(58,122,254,0.16)')

      Text('应用已锁定')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
      Text(this.lockMsg !== '' ? this.lockMsg : '请验证人脸、指纹或锁屏密码以继续')
        .fontSize(13)
        .fontColor('rgba(255,255,255,0.65)')
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 32, right: 32 })
      Button('重试解锁')
        .height(42)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .padding({ left: 28, right: 28 })
        .borderRadius(21)
        .backgroundColor(PRIMARY)
        .onClick(() => {
          this.beginAuth();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('rgba(14, 17, 26, 0.72)')
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  build() {
    Stack() {
      MainShell()
      if (this.locked) {
        this.LockOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
