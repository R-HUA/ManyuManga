import http from '@ohos.net.http';

/** 取消是独立结果，不计入失败，也不触发换源。 */
export class RequestCancelled extends Error {
  constructor() {
    super('请求已取消');
  }
}

export function isRequestCancelled(error: Error): boolean {
  return error instanceof RequestCancelled || error.message === '请求已取消';
}

/** 与 EhNative.NativeRequestControl 同形，避免再做一套取消接口。 */
export interface AbortControl {
  onStart: (request: http.HttpRequest) => void;
  onFinish: (request: http.HttpRequest) => void;
  isCancelled: () => boolean;
  cancelled: Promise<void>;
}

/**
 * 一组请求的取消范围。abortAll 之后该组作废，调用方必须新建一组。
 */
export class RequestAbortGroup {
  private dead: boolean = false;
  private inflight: Array<http.HttpRequest> = [];
  private settle: () => void = (): void => {};
  readonly cancelled: Promise<void>;

  constructor() {
    const group: RequestAbortGroup = this;
    this.cancelled = new Promise<void>((resolve: () => void): void => {
      group.settle = resolve;
    });
  }

  aborted(): boolean {
    return this.dead;
  }

  throwIfAborted(): void {
    if (this.dead) {
      throw new RequestCancelled();
    }
  }

  track(request: http.HttpRequest): void {
    if (this.dead) {
      try {
        request.destroy();
      } catch (e) {
      }
      return;
    }
    this.inflight.push(request);
  }

  untrack(request: http.HttpRequest): void {
    const next: Array<http.HttpRequest> = [];
    for (const item of this.inflight) {
      if (item !== request) {
        next.push(item);
      }
    }
    this.inflight = next;
  }

  abortAll(): void {
    if (this.dead) {
      return;
    }
    this.dead = true;
    this.settle();
    const pending: Array<http.HttpRequest> = this.inflight;
    this.inflight = [];
    for (const request of pending) {
      try {
        request.destroy();
      } catch (e) {
      }
    }
  }

  control(): AbortControl {
    const group: RequestAbortGroup = this;
    const ctrl: AbortControl = {
      onStart: (request: http.HttpRequest): void => {
        group.track(request);
      },
      onFinish: (request: http.HttpRequest): void => {
        group.untrack(request);
      },
      isCancelled: (): boolean => {
        return group.aborted();
      },
      cancelled: group.cancelled
    };
    return ctrl;
  }
}
