import userAuth from '@ohos.userIAM.userAuth';
import cryptoFramework from '@ohos.security.cryptoFramework';

/** 与阅读器现有解锁一致，检测和认证都用 ATL2。 */
export const APP_LOCK_TRUST: userAuth.AuthTrustLevel = userAuth.AuthTrustLevel.ATL2;
const AUTH_SUCCESS: number = 12500000;
const AUTH_CANCELED: number = 12500003;
const CHALLENGE_BYTES: number = 16;

export class AuthOutcome {
  ok: boolean = false;
  message: string = '';
}

/** 只保留当前信任等级下设备真正具备的人脸、指纹、锁屏密码。 */
export function availableAuthTypes(): Array<userAuth.UserAuthType> {
  const found: Array<userAuth.UserAuthType> = [];
  const candidates: Array<userAuth.UserAuthType> = [
    userAuth.UserAuthType.FACE,
    userAuth.UserAuthType.FINGERPRINT,
    userAuth.UserAuthType.PIN
  ];
  for (const kind of candidates) {
    try {
      userAuth.getAvailableStatus(kind, APP_LOCK_TRUST);
      found.push(kind);
    } catch (e) {
    }
  }
  return found;
}

export function randomChallenge(): Uint8Array {
  const random = cryptoFramework.createRandom();
  const blob: cryptoFramework.DataBlob = random.generateRandomSync(CHALLENGE_BYTES);
  return blob.data;
}

class AuthCallback implements userAuth.IAuthCallback {
  private instance: userAuth.UserAuthInstance;
  private finish: (outcome: AuthOutcome) => void;
  private settled: boolean = false;

  constructor(instance: userAuth.UserAuthInstance, finish: (outcome: AuthOutcome) => void) {
    this.instance = instance;
    this.finish = finish;
  }

  // 原生桥不会保留调用接收者，使用箭头函数绑定认证实例。
  onResult = (result: userAuth.UserAuthResult): void => {
    const outcome: AuthOutcome = new AuthOutcome();
    outcome.ok = result.result === AUTH_SUCCESS;
    if (!outcome.ok) {
      outcome.message = result.result === AUTH_CANCELED ? '已取消验证' : '验证未通过，请重试';
    }
    this.complete(outcome);
  };

  fail(): void {
    const outcome: AuthOutcome = new AuthOutcome();
    outcome.message = '无法开始身份验证，请重试';
    this.complete(outcome);
  }

  private complete(outcome: AuthOutcome): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    try {
      this.instance.off('result');
    } catch (e) {
    }
    this.finish(outcome);
  }
}

/** 成功才返回 ok。取消、设备不支持或异常都保持未通过。 */
export function authenticate(title: string): Promise<AuthOutcome> {
  return new Promise<AuthOutcome>((resolve: (outcome: AuthOutcome) => void): void => {
    let callback: AuthCallback | null = null;
    try {
      const types: Array<userAuth.UserAuthType> = availableAuthTypes();
      if (types.length === 0) {
        const missing: AuthOutcome = new AuthOutcome();
        missing.message = '此设备没有达到安全等级的人脸、指纹或锁屏密码';
        resolve(missing);
        return;
      }
      const authParam: userAuth.AuthParam = {
        challenge: randomChallenge(),
        authType: types,
        authTrustLevel: APP_LOCK_TRUST
      };
      const widgetParam: userAuth.WidgetParam = { title: title };
      const instance: userAuth.UserAuthInstance = userAuth.getUserAuthInstance(authParam, widgetParam);
      callback = new AuthCallback(instance, resolve);
      instance.on('result', callback);
      instance.start();
    } catch (e) {
      if (callback !== null) {
        callback.fail();
        return;
      }
      const failed: AuthOutcome = new AuthOutcome();
      failed.message = '无法开始身份验证，请重试';
      resolve(failed);
    }
  });
}
