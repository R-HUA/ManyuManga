import { md5Hex, aesEcbDecrypt, javaStringHashCode } from '../util/JmCrypto';
import common from '@ohos.app.ability.common';
import { httpUtil } from '../util/Http';
import { Prefs, PrefKeys, setAppContext } from '../util/Prefs';
import { DomainSpeed, asArray, asNumber, asRecord, asString, errorMessage } from '../models/Models';
/**
 * data/JmApi.ets
 *
 *
 * 加解密三处规则一致（api-spec §9）：AES key = md5hex 字符串的 32 个 ASCII 字节（不是 16 字节摘要）；
 *  - API 信封 / 域名分发之外均用 "185Hcomic3PAPP7R"；scramble 页用 "18comicAPPContent"；
 *  - 域名分发本身是 "diosfjckwpqpdfjkvnqQjsik"。
 *
 */


const TOKEN_SECRET: string = '185Hcomic3PAPP7R';
const DOMAIN_SECRET: string = 'diosfjckwpqpdfjkvnqQjsik';
const SCRAMBLE_SECRET: string = '18comicAPPContent';
const SCRAMBLE_FALLBACK: number = 220980;

const DOMAIN_SERVER_URL: string =
  'https://rup4a04-c02.tos-cn-hongkong.byteplues.com/newsvr-2025.txt';

/** 官方 /setting 下发的图片域名默认值 */
const DEFAULT_IMAGE_HOST: string = 'cdn-msp.jmdanjonproxy.xyz';

/** 备用图片 CDN 池 */
const EXTRA_IMAGE_HOSTS: Array<string> = [
  'cdn-msp.jmapiproxy1.cc',
  'cdn-msp.jmapiproxy2.cc',
  'cdn-msp2.jmapiproxy2.cc',
  'cdn-msp3.jmapiproxy2.cc',
  'cdn-msp.jmapinodeudzn.net',
  'cdn-msp3.jmapinodeudzn.net'
];

/** 内置兜底 API 域名 */
const FALLBACK_DOMAINS: Array<string> = [
  'www.cdnhjk.net',
  'www.cdngwc.cc',
  'www.cdngwc.net',
  'www.cdngwc.club',
  'www.cdnutc.me'
];

const QUARANTINE_MS: number = 5 * 60 * 1000;
const API_BUDGET_MS: number = 18000;
const API_MIN_REMAIN_MS: number = 800;
const API_ATTEMPT_CAP_MS: number = 14000;

// ───────────────────────── 编码 / 摘要辅助（供 JmApi 与 ImageDecode 共用） ─────────────────────────

// ───────────────────────── JmApi 单例 ─────────────────────────

export class JmDomainPool {
  private domains: Array<string> = FALLBACK_DOMAINS.slice();
  private lastDomain: string = '';
  private imageHost: string = DEFAULT_IMAGE_HOST;
  private appVersion: string = '2.0.26';
  private hostOrder: Array<string> = [];
  private domainRefreshed: boolean = false;
  private settingFetched: boolean = false;
  /** 域名 / setting 失败后的进程内重试次数与定时器（最多 3 次） */
  private bootstrapRetry: number = 0;
  private bootstrapTimer: number = -1;
  /** 图床全部探测失败后的进程内重试次数 */
  private hostProbeRetries: number = 0;
  private initialized: boolean = false;
  private domainFailures: Map<string, number> = new Map<string, number>();
  private quarantineUntil: Map<string, number> = new Map<string, number>();
  private scrambleCache: Map<string, number> = new Map<string, number>();
  private healthyImgHosts: Array<string> = [];
  private imgProbeAt: number = 0;

  async init(context?: common.Context): Promise<void> {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    if (context !== undefined) {
      setAppContext(context);
    }
    const prefs: Prefs = await Prefs.getInstance();
    const cached: string = await prefs.getString(PrefKeys.API_DOMAINS, '');
    if (cached !== '') {
      const arr: Array<string> = this.splitList(cached);
      if (arr.length > 0) {
        this.lastDomain = await prefs.getString(PrefKeys.LAST_DOMAIN, '');
        this.domains = this.withLastFirst(arr, this.lastDomain);
      }
    }
    const ih: string = await prefs.getString(PrefKeys.IMAGE_HOST, '');
    if (ih !== '') {
      this.imageHost = ih;
    }
    const ver: string = await prefs.getString(PrefKeys.APP_VERSION, '');
    if (ver !== '') {
      this.appVersion = ver;
    }
    const ho: string = await prefs.getString(PrefKeys.HOST_ORDER, '');
    this.hostOrder = ho === '' ? [] : this.splitList(ho);
    // 后台刷新链（内部各自兜错，不外抛）
    this.bootstrap().catch((e: Error) => {
      console.info(`[JmApi] bootstrap: ${errorMessage(e)}`);
    });
  }

  private async bootstrap(): Promise<void> {
    await this.refreshDomains();
    await this.fetchSetting();
    await this.testHostsIfStale();
  }

  private scheduleBootstrapRetry(): void {
    if (this.bootstrapRetry >= 3 || this.bootstrapTimer >= 0) {
      return;
    }
    this.bootstrapRetry++;
    const waitMs: number = 5000 * this.bootstrapRetry;
    this.bootstrapTimer = setTimeout(() => {
      this.bootstrapTimer = -1;
      this.domainRefreshed = false;
      this.settingFetched = false;
      this.bootstrap().catch((e: Error) => {
        console.info(`[JmApi] bootstrap 重试失败: ${errorMessage(e)}`);
      });
    }, waitMs);
  }

  private splitList(s: string): Array<string> {
    const out: Array<string> = [];
    const parts: Array<string> = s.split(',');
    for (const p of parts) {
      const t: string = p.trim();
      if (t !== '') {
        out.push(t);
      }
    }
    return out;
  }

  private withLastFirst(list: Array<string>, last: string): Array<string> {
    const merged: Array<string> = [];
    for (const d of list) {
      if (merged.indexOf(d) < 0) {
        merged.push(d);
      }
    }
    for (const d of FALLBACK_DOMAINS) {
      if (merged.indexOf(d) < 0) {
        merged.push(d);
      }
    }
    if (last !== '' && merged.indexOf(last) >= 0) {
      const rest: Array<string> = merged.filter((d: string) => d !== last);
      return [last].concat(rest);
    }
    return merged;
  }

  private orderedDomains(): Array<string> {
    const now: number = Date.now();
    const healthy: Array<string> = [];
    for (const d of this.domains) {
      const q: number | undefined = this.quarantineUntil.get(d);
      if (q === undefined || q <= now) {
        healthy.push(d);
      }
    }
    const base: Array<string> = healthy.length > 0 ? healthy : this.domains.slice();
    if (this.domainFailures.size === 0) {
      return base;
    }
    const sorted: Array<string> = base.slice().sort((a: string, b: string) => {
      const fa: number = this.domainFailures.get(a) === undefined ? 0 : this.domainFailures.get(a) as number;
      const fb: number = this.domainFailures.get(b) === undefined ? 0 : this.domainFailures.get(b) as number;
      return fa - fb;
    });
    return sorted;
  }

  private async refreshDomains(): Promise<void> {
    if (this.domainRefreshed) {
      return;
    }
    this.domainRefreshed = true;
    try {
      let text: string = await httpUtil.getText(DOMAIN_SERVER_URL, undefined, 4000, 4000, 5000);
      while (text.length > 0 && text.charCodeAt(0) > 127) {
        text = text.substring(1);
      }
      const plain: string = await aesEcbDecrypt(text.trim(), md5Hex(DOMAIN_SECRET));
      const root: Record<string, Object> | null = asRecord(JSON.parse(plain));
      let servers: Array<string> = [];
      if (root !== null) {
        const arr: Array<Object> | null = asArray(root['Server']);
        if (arr !== null) {
          for (const it of arr) {
            const v: string = asString(it);
            if (v !== '') {
              servers.push(v);
            }
          }
        }
      }
      if (servers.length > 0) {
        const prefs: Prefs = await Prefs.getInstance();
        this.lastDomain = await prefs.getString(PrefKeys.LAST_DOMAIN, '');
        this.domains = this.withLastFirst(servers, this.lastDomain);
        await prefs.putString(PrefKeys.API_DOMAINS, servers.join(','));
      } else {
        this.domainRefreshed = false;
        this.scheduleBootstrapRetry();
      }
    } catch (e) {
      this.domainRefreshed = false;
      this.scheduleBootstrapRetry();
      console.info(`[JmApi] domains 刷新失败: ${errorMessage(e as Error)}`);
    }
  }

  private async fetchSetting(): Promise<void> {
    if (this.settingFetched) {
      return;
    }
    this.settingFetched = true;
    try {
      const root: Record<string, Object> | null = asRecord(await this.apiGet('/setting'));
      if (root === null) {
        this.settingFetched = false;
        this.scheduleBootstrapRetry();
        return;
      }
      const rawHost: string = asString(root['img_host']);
      if (rawHost !== '') {
        let host: string = rawHost;
        if (host.startsWith('https://')) {
          host = host.substring('https://'.length);
        } else if (host.startsWith('http://')) {
          host = host.substring('http://'.length);
        }
        while (host.endsWith('/')) {
          host = host.substring(0, host.length - 1);
        }
        const slash: number = host.indexOf('/');
        if (slash >= 0) {
          host = host.substring(0, slash);
        }
        if (host !== '' && host !== this.imageHost) {
          this.imageHost = host;
          const prefs: Prefs = await Prefs.getInstance();
          await prefs.putString(PrefKeys.IMAGE_HOST, host);
        }
      }
      const ver: string = asString(root['jm3_version']);
      if (ver !== '' && this.isNewerVersion(ver, this.appVersion)) {
        this.appVersion = ver;
        const prefs: Prefs = await Prefs.getInstance();
        await prefs.putString(PrefKeys.APP_VERSION, ver);
      }
    } catch (e) {
      this.settingFetched = false;
      this.scheduleBootstrapRetry();
      console.info(`[JmApi] setting 获取失败: ${errorMessage(e as Error)}`);
    }
  }

  private isNewerVersion(candidate: string, current: string): boolean {
    const a: Array<number> = this.versionParts(candidate);
    const b: Array<number> = this.versionParts(current);
    const n: number = Math.max(a.length, b.length);
    for (let i: number = 0; i < n; i++) {
      const x: number = i < a.length ? a[i] : 0;
      const y: number = i < b.length ? b[i] : 0;
      if (x !== y) {
        return x > y;
      }
    }
    return false;
  }

  private versionParts(v: string): Array<number> {
    const out: Array<number> = [];
    const parts: Array<string> = v.split('.');
    for (const p of parts) {
      const n: number = Number(p);
      if (!Number.isNaN(n)) {
        out.push(n);
      }
    }
    return out;
  }

  private markDomainFailure(domain: string): void {
    const prev: number = this.domainFailures.get(domain) === undefined ? 0 : this.domainFailures.get(domain) as number;
    const fails: number = prev + 1;
    this.domainFailures.set(domain, fails);
    if (fails >= 2) {
      this.quarantineUntil.set(domain, Date.now() + QUARANTINE_MS);
    }
  }

  private async rememberGoodDomain(domain: string): Promise<void> {
    if (this.domains.length === 0 || this.domains[0] !== domain) {
      this.domains = [domain].concat(this.domains.filter((d: string) => d !== domain));
    }
    this.lastDomain = domain;
    try {
      const prefs: Prefs = await Prefs.getInstance();
      await prefs.putString(PrefKeys.LAST_DOMAIN, domain);
    } catch (e) {
      // 持久化失败可忽略
    }
  }

  async apiGet(pathAndQuery: string): Promise<Object> {
    let lastError: Error | null = null;
    const all: Array<string> = this.orderedDomains();
    const maxTries: number = 3;
    const deadline: number = Date.now() + API_BUDGET_MS;
    const candidates: Array<string> = all.slice(0, maxTries);
    for (const domain of candidates) {
      const remain: number = deadline - Date.now();
      if (remain <= API_MIN_REMAIN_MS) {
        if (lastError === null) {
          lastError = new Error('请求总超时');
        }
        break;
      }
      try {
        let callTimeoutMs: number = 15000;
        if (remain < API_ATTEMPT_CAP_MS) {
          callTimeoutMs = remain;
        }
        const ts: string = Math.floor(Date.now() / 1000).toString();
        const token: string = md5Hex(ts + TOKEN_SECRET);
        const headers: Record<string, string> = {};
        headers['token'] = token;
        headers['tokenparam'] = `${ts},${this.appVersion}`;
        const raw: string = await httpUtil.getText(`https://${domain}${pathAndQuery}`, headers,
          5000, 12000, callTimeoutMs);
        const root: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
        const code: number = asNumber(root['code'], -1);
        if (code !== 200) {
          throw new Error(`code=${code}`);
        }
        const data: string = asString(root['data']);
        if (data === '') {
          throw new Error('data 为空');
        }
        const plain: string = await aesEcbDecrypt(data, token);
        await this.rememberGoodDomain(domain);
        this.domainFailures.delete(domain);
        this.quarantineUntil.delete(domain);
        return JSON.parse(plain) as Object;
      } catch (e) {
        lastError = e as Error;
        this.markDomainFailure(domain);
        console.info(`[JmApi] api 失败 [${domain}${pathAndQuery}]: ${errorMessage(e as Error)}`);
      }
    }
    throw lastError !== null ? lastError : new Error('请求失败');
  }

  async scrambleId(photoId: string): Promise<number> {
    const cached: number | undefined = this.scrambleCache.get(photoId);
    if (cached !== undefined) {
      return cached;
    }
    let value: number | null = null;
    const domains: Array<string> = this.orderedDomains();
    for (const domain of domains) {
      try {
        const ts: string = Math.floor(Date.now() / 1000).toString();
        const token: string = md5Hex(ts + SCRAMBLE_SECRET);
        const headers: Record<string, string> = {};
        headers['token'] = token;
        headers['tokenparam'] = `${ts},${this.appVersion}`;
        const body: string = await httpUtil.getText(
          `https://${domain}/chapter_view_template?id=${photoId}&mode=vertical&page=0&app_img_shunt=1&express=off&v=${ts}`,
          headers, 5000, 12000, 15000);
        const match: RegExpMatchArray | null = body.match(/var\s+scramble_id\s*=\s*(\d+)/);
        if (match !== null && match.length >= 2) {
          const n: number = Number(match[1]);
          if (!Number.isNaN(n)) {
            value = Math.floor(n);
            break;
          }
        }
      } catch (e) {
        this.markDomainFailure(domain);
        console.info(`[JmApi] scramble 失败 [${domain}]: ${errorMessage(e as Error)}`);
      }
    }
    const result: number = value === null ? SCRAMBLE_FALLBACK : value;
    // 失败回退值不进缓存，否则同一次启动里这章会一直用错误分段数
    if (value !== null) {
      this.scrambleCache.set(photoId, result);
    }
    return result;
  }

  private allImgHosts(): Array<string> {
    if (this.hostOrder.length > 0) {
      return this.distinct(this.hostOrder.slice(0, 4).concat([this.imageHost]));
    }
    return this.distinct([this.imageHost].concat(EXTRA_IMAGE_HOSTS));
  }

  private distinct(list: Array<string>): Array<string> {
    const out: Array<string> = [];
    for (const s of list) {
      if (out.indexOf(s) < 0) {
        out.push(s);
      }
    }
    return out;
  }

  private imageHostPool(): Array<string> {
    const all: Array<string> = this.allImgHosts();
    const healthy: Array<string> = [];
    for (const h of this.healthyImgHosts) {
      if (all.indexOf(h) >= 0) {
        healthy.push(h);
      }
    }
    return healthy.length > 0 ? healthy : all;
  }

  nextImageHost(current: string): string | null {
    const pool: Array<string> = this.imageHostPool();
    if (pool.length <= 1) {
      return null;
    }
    const idx: number = pool.indexOf(current);
    const next: string = pool[(idx < 0 ? 0 : idx + 1) % pool.length];
    return next === current ? null : next;
  }

  reportImgHostFailure(host: string): void {
    this.healthyImgHosts = this.healthyImgHosts.filter((h: string) => h !== host);
    this.imgProbeAt = 0;
  }

  refreshImageHostsAsync(): void {
    const now: number = Date.now();
    if (now - this.imgProbeAt < 30 * 60 * 1000 && this.healthyImgHosts.length > 0) {
      return;
    }
    this.imgProbeAt = now;
    const hosts: Array<string> = this.allImgHosts();
    const self: JmDomainPool = this;
    const probes: Array<Promise<string | null>> = [];
    for (const h of hosts) {
      probes.push(self.probeImageHost(h));
    }
    Promise.all(probes).then((values: Array<string | null>) => {
      const okHosts: Array<string> = [];
      for (const v of values) {
        if (v !== null) {
          const host: string = v.split('|')[0];
          if (host !== '') {
            okHosts.push(host);
          }
        }
      }
      if (okHosts.length > 0) {
        self.healthyImgHosts = okHosts;
      }
    }).catch((e: Error) => {
      console.info(`[JmApi] 图片域名探测失败: ${errorMessage(e)}`);
    });
  }

  private async probeImageHost(host: string): Promise<string | null> {
    const t0: number = Date.now();
    try {
      await httpUtil.head(`https://${host}/media/albums/1475774_3x4.jpg`, 5000, 8000, 10000);
      return `${host}|${Date.now() - t0}`;
    } catch (e) {
      return null;
    }
  }

  hostForSeed(seed: string, retry: number): string {
    const pool: Array<string> = this.imageHostPool();
    let index: number = (javaStringHashCode(seed) & 0x7FFFFFFF) % pool.length;
    if (retry !== 0) {
      index = (index + retry) % pool.length;
    }
    return pool[index];
  }

  imageUrl(photoId: string, filename: string, retry: number = 0): string {
    return `https://${this.hostForSeed(`${photoId}/${filename}`, retry)}/media/photos/${photoId}/${filename}`;
  }

  albumCoverUrl(albumId: string, retry: number = 0): string {
    return `https://${this.hostForSeed(`album/${albumId}`, retry)}/media/albums/${albumId}.jpg`;
  }

  albumThumbUrl(albumId: string, retry: number = 0): string {
    return `https://${this.hostForSeed(`album/${albumId}`, retry)}/media/albums/${albumId}_3x4.jpg`;
  }

  async fetchBytes(url: string): Promise<ArrayBuffer> {
    return httpUtil.getBytes(url);
  }

  private async testHostsIfStale(): Promise<void> {
    try {
      const prefs: Prefs = await Prefs.getInstance();
      const lastTs: number = await prefs.getNumber(PrefKeys.HOST_ORDER_TS, 0);
      if (Date.now() - lastTs < 12 * 3600 * 1000) {
        return;
      }
      const candidates: Array<string> = this.distinct(EXTRA_IMAGE_HOSTS.concat([DEFAULT_IMAGE_HOST, this.imageHost]));
      const probes: Array<Promise<string | null>> = [];
      for (const host of candidates) {
        probes.push(this.probeImageHostByBytes(host));
      }
      const values: Array<string | null> = await Promise.all(probes);
      const okPairs: Array<string> = [];
      for (const v of values) {
        if (v !== null) {
          okPairs.push(v);
        }
      }
      if (okPairs.length > 0) {
        okPairs.sort((a: string, b: string) => {
          return Number(a.split('|')[1]) - Number(b.split('|')[1]);
        });
        const ordered: Array<string> = [];
        for (const p of okPairs) {
          ordered.push(p.split('|')[0]);
        }
        this.hostOrder = ordered;
        await prefs.putString(PrefKeys.HOST_ORDER, ordered.join(','));
        await prefs.putNumber(PrefKeys.HOST_ORDER_TS, Date.now());
        this.hostProbeRetries = 0;
      } else if (this.hostProbeRetries < 2) {
        // 全部失败不写时间戳，否则 12 小时内不再测速；本次进程再试两次
        this.hostProbeRetries++;
        setTimeout(() => {
          this.testHostsIfStale().catch((err: Error) => {
            console.info(`[JmApi] host 测速重试失败: ${errorMessage(err)}`);
          });
        }, 15000);
      }
    } catch (e) {
      console.info(`[JmApi] host 测速失败: ${errorMessage(e as Error)}`);
    }
  }

  private async probeImageHostByBytes(host: string): Promise<string | null> {
    const t0: number = Date.now();
    try {
      const bytes: ArrayBuffer = await httpUtil.getBytes(
        `https://${host}/media/albums/1447694_3x4.jpg`, undefined, 5000, 10000, 12000);
      if (bytes.byteLength > 0) {
        return `${host}|${Date.now() - t0}`;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  getDomains(): Array<string> {
    return this.orderedDomains();
  }

  async setPreferredDomain(domain: string): Promise<void> {
    await this.rememberGoodDomain(domain);
  }

  getImageHost(): string {
    return this.imageHost;
  }

  getAppVersion(): string {
    return this.appVersion;
  }

  async testDomains(): Promise<Array<DomainSpeed>> {
    const candidates: Array<string> = this.withLastFirst(this.domains, this.lastDomain);
    const probes: Array<Promise<DomainSpeed>> = [];
    for (const domain of candidates) {
      probes.push(this.probeDomain(domain));
    }
    const results: Array<DomainSpeed> = await Promise.all(probes);
    results.sort((a: DomainSpeed, b: DomainSpeed) => {
      if (a.ok !== b.ok) {
        return a.ok ? -1 : 1;
      }
      return a.ms - b.ms;
    });
    return results;
  }

  private async probeDomain(domain: string): Promise<DomainSpeed> {
    const t0: number = Date.now();
    try {
      await this.probeSetting(domain);
      return new DomainSpeed(domain, Date.now() - t0, true);
    } catch (e) {
      return new DomainSpeed(domain, -1, false);
    }
  }

  private async probeSetting(domain: string): Promise<void> {
    const ts: string = Math.floor(Date.now() / 1000).toString();
    const token: string = md5Hex(ts + TOKEN_SECRET);
    const headers: Record<string, string> = {};
    headers['token'] = token;
    headers['tokenparam'] = `${ts},${this.appVersion}`;
    await httpUtil.getText(`https://${domain}/setting`, headers, 5000, 8000, 10000);
  }

  debugInfo(): string {
    const lines: Array<string> = [];
    lines.push(`域名(${this.domains.length}): ${this.domains.join(', ')}`);
    lines.push(`图片域名: ${this.imageHost}`);
    lines.push(`接口版本: ${this.appVersion}`);
    lines.push(`Cookie: ${httpUtil.cookieCount()} 条`);
    return lines.join('\n');
  }

}
