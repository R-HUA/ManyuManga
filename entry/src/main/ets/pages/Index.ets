/**
 * 唯一 @Entry 页面。
 *
 * 本页承担的两项入口职责：
 *  1. 主题生效：aboutToAppear/onPageShow 读取 themeMode 偏好并经
 *     ApplicationContext.setColorMode 应用（与 SettingsPage.setThemeMode 同口径）。
 *  2. 应用锁：锁开启时，应用启动 / 回到前台（onPageShow）先以不透明
 *     全屏遮罩拦截，经 userAuth 指纹验证通过后才放行；指纹不可用时按 S 级语义放行
 *     （与 SettingsPage 开启时的降级一致）。
 *  3. 返回逻辑：非发现 Tab 按系统返回先回发现（currentIndex 经 AppStorage 与
 *     MainShell 双向同步），已在发现 Tab 才默认退出。
 */
import userIAM from '@ohos.userIAM.userAuth';
import common from '@ohos.app.ability.common';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import { MainShell } from './MainShell';
import { PRIMARY, READER_BG, PRIVACY_MASK } from '../common/Theme';
import { Prefs, getAppContext } from '../util/Prefs';
import { APP_IN_BACKGROUND_KEY } from '../entryability/EntryAbility';
import { NAV_STACK_DEPTH_KEY } from '../common/Route';

/** MainShell 当前 Tab 索引在 AppStorage 的 key（X-04 返回拦截与 Tab 状态双向同步） */
const MAIN_TAB_INDEX_KEY: string = 'mainTabIndex';
/** userAuth 认证成功结果码（对应 userIAM ResultCode.SUCCESS；与 SettingsPage 同值） */
const AUTH_RESULT_SUCCESS: number = 12500000;

/** 主题生效：system→NOT_SET（跟随系统）/ light→LIGHT / dark→DARK（API 11+ 稳定接口） */
function applyThemeModeToApp(context: common.Context, mode: string): void {
  try {
    const appCtx: common.ApplicationContext = context.getApplicationContext();
    const cm: number = mode === 'dark'
      ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : mode === 'light'
        ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    appCtx.setColorMode(cm);
  } catch (e) {
    // 生效失败静默（下次 onPageShow 重试）
  }
}

/**
 * userAuth 认证结果回调（ArkTS 规则：接口实现用具名 class）。
 * 成功 → 解锁进入应用；失败 → 保留锁屏等待用户重试。
 */
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
      } catch (e) {
        // 取消订阅失败可忽略
      }
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
  /** 应用锁拦截态：true 时以不透明遮罩盖住 MainShell */
  @State locked: boolean = false;
  @State lockMsg: string = '';
  /** 应用锁开关（多任务防窥条件）；后台/前台信号来自 EntryAbility windowStageEvent */
  @State lockEnabled: boolean = false;
  @StorageProp(APP_IN_BACKGROUND_KEY) inBackground: boolean = false;
  private authInFlight: boolean = false;

  aboutToAppear(): void {
    this.applyThemeFromPrefs();
  }

  /** 启动与回到前台都会触发：重新应用主题；锁开启且未在验证中时上锁并验证 */
  onPageShow(): void {
    this.applyThemeFromPrefs();
    this.checkAppLock();
  }

  /**
   * X-04：栈内二级页先 pop（返回 false 交给 Navigation）；
   * 栈空且非发现 Tab 先回发现，发现 Tab 默认退出。
   * 深度由 MainShell 按导航栏显隐写入；深度未知时按栈空处理，避免挡住 Tab 回退。
   */
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
    }).catch((e: Error) => {
      // 偏好读取失败保持默认（跟随系统）
    });
  }

  // ── 应用锁（启动 / 回前台拦截）──

  private checkAppLock(): void {
    Prefs.getInstance().then((p: Prefs): Promise<boolean> => p.securityLock()).then((on: boolean) => {
      this.lockEnabled = on;
      if (!on) {
        this.locked = false;
        return;
      }
      if (this.locked) {
        return; // 已在锁屏（含等待用户重试）
      }
      this.locked = true;
      this.lockMsg = '';
      this.startLockAuth();
    }).catch((e: Error) => {
      // 偏好读取失败不拦截（避免锁死应用）
    });
  }

  private startLockAuth(): void {
    if (this.authInFlight) {
      return;
    }
    // 前置可用性检查（未录入指纹/设备不支持/锁定中会抛错）
    try {
      userIAM.getAvailableStatus(userIAM.UserAuthType.FINGERPRINT, userIAM.AuthTrustLevel.ATL2);
    } catch (e) {
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
      const widgetParam: userIAM.WidgetParam = { title: '验证指纹以进入应用' };
      const auth: userIAM.UserAuthInstance = userIAM.getUserAuthInstance(authParam, widgetParam);
      const handler: LockAuthHandler = new LockAuthHandler(this);
      handler.setInstance(auth);
      auth.on('result', handler);
      auth.start();
    } catch (e) {
      this.authInFlight = false;
      this.locked = false;
      this.lockMsg = '指纹组件不可用，本次已跳过应用锁验证';
    }
  }

  /** 指纹验证结果回传（LockAuthHandler 调用） */
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
    Column({ space: 16 }) {
      Text('🔒')
        .fontSize(52)
      Text('应用已锁定')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
      Text(this.lockMsg !== '' ? this.lockMsg : '验证指纹以继续使用')
        .fontSize(13)
        .fontColor('rgba(255,255,255,0.6)')
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.lockMsg !== '') {
        Text('重试验证')
          .fontSize(15)
          .fontColor(Color.White)
          .padding({ left: 28, right: 28, top: 10, bottom: 10 })
          .borderRadius(22)
          .backgroundColor(PRIMARY)
          .onClick(() => {
            this.startLockAuth();
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(READER_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  /** 多任务防窥遮罩：应用锁开启且切入后台时，以不透明层盖住内容，
   *  防止系统多任务卡片快照泄露当前阅读画面；回到前台自动消失 */
  @Builder
  private PrivacyMask() {
    Column({ space: 14 }) {
      Text('🔒')
        .fontSize(46)
      Text('内容已隐藏')
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
