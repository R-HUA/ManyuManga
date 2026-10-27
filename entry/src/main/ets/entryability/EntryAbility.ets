import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want, errorManager } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import fs from '@ohos.file.fs';
import promptAction from '@ohos.promptAction';
import { sourceApi } from '../data/SourceApi';
import { openDatabase } from '../data/db/AppDatabase';
import { Prefs, setAppContext } from '../util/Prefs';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';
// 全局错误信息在 AppStorage 中的 key，MainShell 监听该 key 展示友好错误页
const CRASH_MESSAGE_KEY: string = 'crashErrorMessage';

/* ===== 全局 AppStorage 契约 key（页面经 @StorageProp 消费，评审 Step1 统一下发） ===== */
/** 顶部状态栏避让高度 vp（全屏布局下所有自绘顶栏 padding(top) 引用） */
export const TOP_RECT_HEIGHT_KEY: string = 'topRectHeight';
/** 底部系统导航条避让高度 vp */
export const BOTTOM_RECT_HEIGHT_KEY: string = 'bottomRectHeight';
/** 一多响应式断点：sm(<600vp) / md(<840vp) / lg */
export const CURRENT_BREAKPOINT_KEY: string = 'currentBreakpoint';
/** 当前是否深色模式（setColorMode 生效后经 onConfigurationUpdate 同步） */
export const IS_DARK_MODE_KEY: string = 'isDarkMode';
/** 阅读计时与应用锁使用的后台状态。 */
export const APP_IN_BACKGROUND_KEY: string = 'appInBackground';

/** 浅色页面下的状态栏文字色（深色文字配浅色背景，修复白底白字） */
const BAR_TEXT_DARK: string = '#1E293B';
/** 深色页面/深色模式下的状态栏文字色 */
const BAR_TEXT_LIGHT: string = '#FFFFFF';

/**
 * 全局未捕获异常观察者：写 crash 日志文件 + 通知 UI 层展示友好错误页。
 * 说明：本 SDK 的 errorManager.ErrorObserver 声明为 class（ArkTS 禁止 implements class，
 * 且 ErrorObserver 仅是命名空间里的类型别名、无法 extends），故这里定义结构兼容的
 * 具名 class（含 onUnhandledException(errMsg: string): void），按结构化类型直接传给
 * errorManager.on('error', ...)。
 */
class GlobalErrorObserver {
  private owner: EntryAbility;

  constructor(owner: EntryAbility) {
    this.owner = owner;
  }

  onUnhandledException(err: string): void {
    this.owner.handleGlobalError(err);
  }
}

export default class EntryAbility extends UIAbility {
  private errorObserver: GlobalErrorObserver = new GlobalErrorObserver(this);
  /** errorManager.on('error') 返回的观察者 id，off 时必须回传该 number */
  private observerId: number = -1;
  private mainWindow: window.Window | null = null;
  private privacyError: string = '';

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.observerId = errorManager.on('error', this.errorObserver);
    AppStorage.setOrCreate(IS_DARK_MODE_KEY,
      this.context.config?.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    setAppContext(this.context);
    openDatabase(this.context).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'database init: %{public}s', errorMessageText(e));
    }).then((): Promise<void> => sourceApi.init(this.context)).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'source init: %{public}s', errorMessageText(e));
    });
  }

  onDestroy(): void {
    if (this.observerId >= 0) {
      errorManager.off('error', this.observerId);
      this.observerId = -1;
    }
  }

  /** 深浅色切换（含 Settings setColorMode 主动触发）：同步全局 key + 状态栏文字反色 */
  onConfigurationUpdate(newConfig: Configuration): void {
    const isDark: boolean = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.setOrCreate(IS_DARK_MODE_KEY, isDark);
    this.updateStatusBarText(isDark);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 阅读计时与应用锁共用系统窗口生命周期信号。
    windowStage.on('windowStageEvent', (stageEvent: window.WindowStageEventType) => {
      const inBg: boolean = stageEvent === window.WindowStageEventType.INACTIVE
        || stageEvent === window.WindowStageEventType.PAUSED
        || stageEvent === window.WindowStageEventType.HIDDEN;
      AppStorage.setOrCreate(APP_IN_BACKGROUND_KEY, inBg);
    });
    this.setupImmersiveWindow(windowStage).then((): void => {
      windowStage.loadContent('pages/Index', (err: BusinessError<void>) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed, cause: %{public}s', JSON.stringify(err));
        return;
      }
      if (this.privacyError !== '') {
        promptAction.showToast({ message: this.privacyError });
        this.privacyError = '';
      }
      });
    });
  }

  /**
   * 沉浸式与全局窗口契约（评审 Step1）：
   *  1. 全屏布局 + 状态栏文字默认深色（主界面为浅色底，修复白底白字隐形）；
   *  2. 量取状态栏/底部导航条避让高度写入 AppStorage，页面统一 @StorageProp 消费；
   *  3. 监听窗口宽度驱动 sm/md/lg 断点（MainShell 一多侧边栏）。
   */
  private async setupImmersiveWindow(windowStage: window.WindowStage): Promise<void> {
    try {
      const win: window.Window = await windowStage.getMainWindow();
      this.mainWindow = win;
      try {
        const prefs: Prefs = await Prefs.getInstance();
        await win.setWindowPrivacyMode(await prefs.previewProtection());
      } catch (e) {
        this.privacyError = `隐私保护设置失败：${errorMessageText(e as Error)}`;
      }
      await win.setWindowLayoutFullScreen(true);
      const isDark: boolean = AppStorage.get<boolean>(IS_DARK_MODE_KEY) ?? false;
      await this.updateStatusBarText(isDark);

      const updateAvoidAreas = (): void => {
        const sysArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const navArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        const topVp: number = px2vp(sysArea.topRect.height);
        const bottomVp: number = px2vp(navArea.bottomRect.height);
        AppStorage.setOrCreate(TOP_RECT_HEIGHT_KEY, topVp);
        AppStorage.setOrCreate(BOTTOM_RECT_HEIGHT_KEY, bottomVp);
      };
      updateAvoidAreas();
      win.on('avoidAreaChange', () => {
        updateAvoidAreas();
      });

      const updateBreakpoint = (widthPx: number): void => {
        const widthVp: number = px2vp(widthPx);
        const bp: string = widthVp < 600 ? 'sm' : (widthVp < 840 ? 'md' : 'lg');
        AppStorage.setOrCreate(CURRENT_BREAKPOINT_KEY, bp);
      };
      updateBreakpoint(win.getWindowProperties().windowRect.width);
      win.on('windowSizeChange', (size: window.Size) => {
        updateBreakpoint(size.width);
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'setup immersive window failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 状态栏文字颜色：useLight=true 白字（深色底），false 深字（浅色底） */
  private async updateStatusBarText(useLight: boolean): Promise<void> {
    if (this.mainWindow === null) {
      return;
    }
    try {
      await this.mainWindow.setWindowSystemBarProperties({
        statusBarContentColor: useLight ? BAR_TEXT_LIGHT : BAR_TEXT_DARK
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'set system bar failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 最简全局错误兜底：hilog 记录 + 写 crash 日志文件（filesDir/crash/）+ 通过 AppStorage 通知 UI。
   */
  handleGlobalError(detail: string): void {
    hilog.error(DOMAIN, TAG, 'unhandled exception: %{public}s', detail);
    this.writeCrashLog(detail);
    AppStorage.setOrCreate(CRASH_MESSAGE_KEY, detail);
  }

  private writeCrashLog(detail: string): void {
    try {
      const crashDir: string = this.context.filesDir + '/crash';
      // accessSync 在目录不存在时会抛错；先探测再创建，避免第一次崩溃写不出日志
      let crashDirExists: boolean = false;
      try {
        crashDirExists = fs.accessSync(crashDir);
      } catch (e) {
        crashDirExists = false;
      }
      if (!crashDirExists) {
        fs.mkdirSync(crashDir, true);
      }
      const logPath: string = crashDir + '/crash_' + Date.now().toString() + '.log';
      const time: string = new Date().toISOString();
      const content: string = 'time=' + time + '\ndetail=' + detail + '\n';
      const file: fs.File = fs.openSync(logPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'write crash log failed: %{public}s', JSON.stringify(e));
    }
  }
}

/** Error → 可读文本（本文件内联，避免为两处 catch 引入 util 依赖） */
function errorMessageText(e: Error): string {
  return e !== undefined && e !== null && e.message !== undefined ? e.message : String(e);
}
