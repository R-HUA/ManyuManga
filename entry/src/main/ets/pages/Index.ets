/**
 * 唯一 @Entry 页面。
 *  1. 主题生效：aboutToAppear/onPageShow 读取 themeMode 偏好并经 ApplicationContext.setColorMode 应用。
 *  2. 应用锁：锁开启时，应用启动 / 回到前台（onPageShow）先以不透明全屏遮罩拦截，经 userAuth 指纹验证通过后才放行。
 *  3. 返回逻辑：栈内二级页先 pop；栈空且非首页 Tab 先回书架 Tab，已在书架 Tab 才默认退出。
 */
import userIAM from '@ohos.userIAM.userAuth';
import common from '@ohos.app.ability.common';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import { MainShell } from './MainShell';
import { PRIMARY, READER_BG, PRIVACY_MASK } from '../common/Theme';
import { Prefs, getAppContext } from '../util/Prefs';
import { APP_IN_BACKGROUND_KEY } from '../entryability/EntryAbility';
import { NAV_STACK_DEPTH_KEY } from '../common/Route';

const MAIN_TAB_INDEX_KEY: string = 'mainTabIndex';
const AUTH_RESULT_SUCCESS: number = 12500000;

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

class LockAuthHandler implements userIAM.IAuthCallback {
  private owner: Index;
  private instance: userIAM.UserAuthInstance | null = null;
  private settled: boolean = false;

  constructor(owner: Index) {
    this.owner = owner;
  }

  setInstance(instance: userIAM.UserAuthInstance): void {
    this.instance = instance;
  }

  onResult(result: userIAM.UserAuthResult): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    if (this.instance !== null) {
      try {
        this.instance.off('result');
      } catch (_e) {}
    }
    if (result.result === AUTH_RESULT_SUCCESS) {
      this.owner.onLockAuthResult(true, '');
    } else {
      this.owner.onLockAuthResult(false, `指纹验证未通过（码 ${result.result}），请重试`);
    }
  }
}

@Entry
@Component
struct Index {
  @State locked: boolean = false;
  @State lockMsg: string = '';
  @State lockEnabled: boolean = false;
  @StorageProp(APP_IN_BACKGROUND_KEY) inBackground: boolean = false;
  private authInFlight: boolean = false;

  aboutToAppear(): void {
    this.applyThemeFromPrefs();
  }

  onPageShow(): void {
    this.applyThemeFromPrefs();
    this.checkAppLock();
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

  private checkAppLock(): void {
    Prefs.getInstance().then((p: Prefs): Promise<boolean> => p.securityLock()).then((on: boolean) => {
      this.lockEnabled = on;
      if (!on) {
        this.locked = false;
        return;
      }
      if (this.locked) {
        return;
      }
      this.locked = true;
      this.lockMsg = '';
      this.startLockAuth();
    }).catch(() => {});
  }

  private startLockAuth(): void {
    if (this.authInFlight) {
      return;
    }
    try {
      userIAM.getAvailableStatus(userIAM.UserAuthType.FINGERPRINT, userIAM.AuthTrustLevel.ATL2);
    } catch (_e) {
      this.locked = false;
      this.lockMsg = '指纹不可用，本次已跳过应用锁验证';
      return;
    }
    try {
      this.authInFlight = true;
      const authParam: userIAM.AuthParam = {
        challenge: new Uint8Array([7, 6, 5, 4, 3, 2, 1]),
        authType: [userIAM.UserAuthType.FINGERPRINT],
        authTrustLevel: userIAM.AuthTrustLevel.ATL2
      };
      const widgetParam: userIAM.WidgetParam = { title: '验证指纹以进入漫匣' };
      const auth: userIAM.UserAuthInstance = userIAM.getUserAuthInstance(authParam, widgetParam);
      const handler: LockAuthHandler = new LockAuthHandler(this);
      handler.setInstance(auth);
      auth.on('result', handler);
      auth.start();
    } catch (_e) {
      this.authInFlight = false;
      this.locked = false;
      this.lockMsg = '指纹组件不可用，本次已跳过应用锁验证';
    }
  }

  onLockAuthResult(ok: boolean, msg: string): void {
    this.authInFlight = false;
    if (ok) {
      this.locked = false;
      this.lockMsg = '';
    } else {
      this.lockMsg = msg;
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

      Text('漫匣已锁定')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
      Text(this.lockMsg !== '' ? this.lockMsg : '请验证指纹以继续访问书架与阅读进度')
        .fontSize(13)
        .fontColor('rgba(255,255,255,0.65)')
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 32, right: 32 })
      Button('验证指纹解锁')
        .height(42)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .padding({ left: 28, right: 28 })
        .borderRadius(21)
        .backgroundColor(PRIMARY)
        .onClick(() => {
          this.startLockAuth();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(READER_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private PrivacyMask() {
    Column({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.shield_checkered'))
          .fontSize(32)
          .fontColor([PRIMARY])
      }
      .width(68)
      .height(68)
      .borderRadius(34)
      .backgroundColor('rgba(58,122,254,0.16)')

      Text('漫匣隐私保护中')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('rgba(255,255,255,0.85)')
      Text('回到应用后自动恢复显示')
        .fontSize(12)
        .fontColor('rgba(255,255,255,0.45)')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(PRIVACY_MASK)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  build() {
    Stack() {
      MainShell()
      if (this.lockEnabled && this.inBackground && !this.locked) {
        this.PrivacyMask()
      }
      if (this.locked) {
        this.LockOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
