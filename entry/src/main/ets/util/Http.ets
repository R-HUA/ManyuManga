/**
 * 网络请求 HTTP GET/HEAD 封装
 */

import http from '@ohos.net.http';
import { errorMessage } from '../models/Models';

/** 原实现统一 UA（JmApi.kt:88-90），API 与图片请求共用 */
export const JM_UA: string = 'Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) ' +
  'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Safari/537.36';

/** HTTP 封装单例 */
export class Http {
  /** host -> "k1=v1; k2=v2"（对应 Kotlin MemCookieJar，JmApi.kt:98-108） */
  private cookieStore: Map<string, string> = new Map<string, string>();

  /** GET 文本响应 */
  async getText(url: string, headers?: Record<string, string>,
    connectTimeoutMs: number = 5000, readTimeoutMs: number = 12000,
    timeoutMs: number = 15000): Promise<string> {
    const h: Record<string, string> | null = headers === undefined ? null : headers;
    const result: Object = await this.request(url, http.RequestMethod.GET, h,
      http.HttpDataType.STRING, connectTimeoutMs, readTimeoutMs, timeoutMs);
    return `${result}`;
  }

  /** GET 二进制响应 */
  async getBytes(url: string, headers?: Record<string, string>,
    connectTimeoutMs: number = 5000, readTimeoutMs: number = 12000,
    timeoutMs: number = 15000): Promise<ArrayBuffer> {
    const h: Record<string, string> | null = headers === undefined ? null : headers;
    const result: Object = await this.request(url, http.RequestMethod.GET, h,
      http.HttpDataType.ARRAY_BUFFER, connectTimeoutMs, readTimeoutMs, timeoutMs);
    return result as ArrayBuffer;
  }

  /** HEAD 探活（2xx 视为成功，否则抛 HTTP {code}） */
  async head(url: string, connectTimeoutMs: number = 5000, readTimeoutMs: number = 12000,
    timeoutMs: number = 15000): Promise<void> {
    await this.request(url, http.RequestMethod.HEAD, null,
      http.HttpDataType.STRING, connectTimeoutMs, readTimeoutMs, timeoutMs);
  }

  /** cookie 总条数（诊断用，对应 cookieJar.size()） */
  cookieCount(): number {
    let n: number = 0;
    this.cookieStore.forEach((v: string, k: string) => {
      n += v.split('; ').length;
    });
    return n;
  }

  clearCookies(): void {
    this.cookieStore.clear();
  }

  private async request(url: string, method: http.RequestMethod,
    headers: Record<string, string> | null, expect: http.HttpDataType,
    connectTimeoutMs: number, readTimeoutMs: number,
    timeoutMs: number): Promise<Object> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const finalHeaders: Record<string, string> = {};
      finalHeaders['User-Agent'] = JM_UA;
      if (headers !== null) {
        const keys: Array<string> = Object.keys(headers);
        for (const k of keys) {
          finalHeaders[k] = headers[k];
        }
      }
      const cookie: string = this.cookieHeaderFor(url);
      if (cookie !== '') {
        finalHeaders['Cookie'] = cookie;
      }
      const opt: http.HttpRequestOptions = {
        method: method,
        header: finalHeaders,
        expectDataType: expect,
        connectTimeout: connectTimeoutMs,
        readTimeout: readTimeoutMs,
        usingCache: false // API 鉴权头与 AES 密钥由秒级 ts 派生，命中旧缓存会以新钥解旧文导致错乱重试（Review M-1）；图片缓存走应用层 page_cache
      };
      const resp: http.HttpResponse = await this.withTimeout<http.HttpResponse>(
        req.request(url, opt), timeoutMs, req);
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`HTTP ${resp.responseCode}`);
      }
      this.saveCookies(url, resp.header);
      if (resp.result === null || resp.result === undefined) {
        throw new Error('空响应');
      }
      return resp.result as Object;
    } finally {
      try {
        req.destroy();
      } catch (e) {
        // 释放连接失败可忽略
      }
    }
  }

  /** 模拟 OkHttp callTimeout：整体超时即 destroy 请求并 reject */
  private withTimeout<T>(p: Promise<T>, timeoutMs: number, req: http.HttpRequest): Promise<T> {
    return new Promise<T>((resolve: (value: T) => void, reject: (reason: Error) => void) => {
      const timer: number = setTimeout(() => {
        reject(new Error('请求超时'));
        try {
          req.destroy();
        } catch (e) {
          // ignore
        }
      }, timeoutMs);
      p.then((value: T) => {
        clearTimeout(timer);
        resolve(value);
      }).catch((e: Error) => {
        clearTimeout(timer);
        reject(new Error(errorMessage(e)));
      });
    });
  }

  private hostOf(url: string): string {
    const parts: Array<string> = url.split('/');
    if (parts.length >= 3) {
      return parts[2];
    }
    return '';
  }

  private cookieHeaderFor(url: string): string {
    const host: string = this.hostOf(url);
    if (host === '') {
      return '';
    }
    const v: string | undefined = this.cookieStore.get(host);
    return v === undefined ? '' : v;
  }

  /** 按 host 整组覆盖保存（对应 MemCookieJar.saveFromResponse） */
  private saveCookies(url: string, header: Object): void {
    const host: string = this.hostOf(url);
    if (host === '') {
      return;
    }
    const hdr: Record<string, Object> = header as Record<string, Object>;
    let raw: Object | undefined = hdr['set-cookie'];
    if (raw === undefined || raw === null) {
      raw = hdr['Set-Cookie'];
    }
    if (raw === undefined || raw === null) {
      return;
    }
    const parts: Array<string> = [];
    if (raw instanceof Array) {
      const arr: Array<Object> = raw as Array<Object>;
      for (const item of arr) {
        parts.push(`${item}`);
      }
    } else {
      const segs: Array<string> = this.splitSetCookieHeader(`${raw}`);
      for (const seg of segs) {
        parts.push(seg);
      }
    }
    const pairs: Array<string> = [];
    for (const p of parts) {
      const firstSeg: string = p.split(';')[0].trim();
      if (firstSeg.indexOf('=') > 0) {
        pairs.push(firstSeg);
      }
    }
    if (pairs.length > 0) {
      this.cookieStore.set(host, pairs.join('; '));
    }
  }

  /**
   * 合并后的 Set-Cookie 只在「下一个 cookie 名=」前切开。
   * Expires=Wed, 21 Oct 2015 07:28:00 GMT 里的逗号不能当分隔符。
   */
  private splitSetCookieHeader(raw: string): Array<string> {
    const parts: Array<string> = [];
    let start: number = 0;
    for (let i: number = 0; i < raw.length; i++) {
      if (raw.charAt(i) !== ',') {
        continue;
      }
      const rest: string = raw.substring(i + 1).trim();
      const eq: number = rest.indexOf('=');
      const semi: number = rest.indexOf(';');
      const nameEnd: number = semi >= 0 && semi < eq ? semi : eq;
      if (eq > 0 && nameEnd === eq && rest.substring(0, eq).indexOf(' ') < 0) {
        parts.push(raw.substring(start, i));
        start = i + 1;
      }
    }
    parts.push(raw.substring(start));
    return parts;
  }
}

export const httpUtil: Http = new Http();
