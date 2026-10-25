/**
 * data/JmApi.ets
 *
 *
 * 加解密三处规则一致（api-spec §9）：AES key = md5hex 字符串的 32 个 ASCII 字节（不是 16 字节摘要）；
 *  - API 信封 / 域名分发之外均用 "185Hcomic3PAPP7R"；scramble 页用 "18comicAPPContent"；
 *  - 域名分发本身是 "diosfjckwpqpdfjkvnqQjsik"。
 *
 */

import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';
import common from '@ohos.app.ability.common';
import { httpUtil } from '../util/Http';
import { Prefs, PrefKeys, setAppContext } from '../util/Prefs';
import {
  Album,
  AlbumLite,
  CategoryItem,
  Chapter,
  CommentItem,
  CommentsResult,
  DomainSpeed,
  SearchOptions,
  SearchResult,
  asArray,
  asBool,
  asNumber,
  asRecord,
  asString,
  errorMessage
} from '../models/Models';

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

/** 字符串 → UTF-8 字节 */
export function utf8Encode(s: string): Uint8Array {
  const out: Array<number> = [];
  for (let i: number = 0; i < s.length; i++) {
    const c: number = s.charCodeAt(i);
    if (c < 0x80) {
      out.push(c);
    } else if (c < 0x800) {
      out.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F));
    } else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
      const c2: number = s.charCodeAt(i + 1);
      if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
        const cp: number = 0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00);
        out.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F),
          0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
        i++;
      } else {
        out.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F));
      }
    } else {
      out.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F));
    }
  }
  return Uint8Array.from(out);
}

/** UTF-8 字节 → 字符串 */
export function utf8Decode(bytes: Uint8Array): string {
  let s: string = '';
  let i: number = 0;
  while (i < bytes.length) {
    const b0: number = bytes[i];
    let cp: number = b0;
    if (b0 >= 0xF0 && i + 3 < bytes.length) {
      cp = ((b0 & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) |
        ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
      i += 4;
      const off: number = cp - 0x10000;
      s += String.fromCharCode(0xD800 + (off >> 10), 0xDC00 + (off & 0x3FF));
      continue;
    } else if (b0 >= 0xE0 && i + 2 < bytes.length) {
      cp = ((b0 & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F);
      i += 3;
    } else if (b0 >= 0xC0 && i + 1 < bytes.length) {
      cp = ((b0 & 0x1F) << 6) | (bytes[i + 1] & 0x3F);
      i += 2;
    } else {
      i += 1;
    }
    s += String.fromCharCode(cp);
  }
  return s;
}

/** ASCII 字符串 → 字节 */
function asciiBytes(s: string): Uint8Array {
  const out: Uint8Array = new Uint8Array(s.length);
  for (let i: number = 0; i < s.length; i++) {
    out[i] = s.charCodeAt(i) & 0xFF;
  }
  return out;
}

function bytesToHexLower(bytes: Uint8Array): string {
  const digits: string = '0123456789abcdef';
  let s: string = '';
  for (let i: number = 0; i < bytes.length; i++) {
    s += digits.charAt((bytes[i] >> 4) & 0xF);
    s += digits.charAt(bytes[i] & 0xF);
  }
  return s;
}

/** MD5 摘要，输出 32 位小写 hex */
export function md5Hex(input: string): string {
  try {
    const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
    md.updateSync({ data: utf8Encode(input) });
    const digest: cryptoFramework.DataBlob = md.digestSync();
    return bytesToHexLower(digest.data);
  } catch (e) {
    // Review M-2：设备缺少该系统能力时给出可诊断错误，避免被误判为域名故障
    throw new Error(`加密引擎不可用（MD5）：${errorMessage(e as Error)}`);
  }
}

/**
 * AES-256-ECB(PKCS7) 解密（对应 JmApi.kt:299-303）。
 * key = keyHex 这 32 个 hex 字符的 ASCII 字节（非摘要本身）。
 */
async function aesEcbDecrypt(base64Text: string, keyHex: string): Promise<string> {
  try {
    const keyGen: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
    const symKey: cryptoFramework.SymKey = await keyGen.convertKey({ data: asciiBytes(keyHex) });
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|ECB|PKCS7');
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, null);
    const b64: util.Base64Helper = new util.Base64Helper();
    const cipherBytes: Uint8Array = b64.decodeSync(base64Text);
    const out: cryptoFramework.DataBlob = await cipher.doFinal({ data: cipherBytes });
    return utf8Decode(out.data);
  } catch (e) {
    // Review M-2：AES 能力缺失时给出可诊断错误
    throw new Error(`加密引擎不可用（AES-256-ECB）：${errorMessage(e as Error)}`);
  }
}

/** Java String.hashCode（UTF-16 码元，h = 31*h + c，int32 回绕）——图片 CDN 分流必须与原版一致 */
export function javaStringHashCode(s: string): number {
  let h: number = 0;
  for (let i: number = 0; i < s.length; i++) {
    h = ((h << 5) - h + s.charCodeAt(i)) | 0;
  }
  return h;
}

// ───────────────────────── JmApi 单例 ─────────────────────────

export class JmApi {
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

  /**
   * 进程启动时调用一次（幂等）：读缓存域名/图片域名/版本号，再后台刷新
   * （域名分发服务器 → /setting → 图片域名测速），绝不阻塞首屏（JmApi.kt:193-218）。
   */
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

  /** 域名或 setting 失败时稍后整段重跑，避免一次离线把本次进程钉在内置域名上 */
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

  /** 合并兜底域名去重，并把上次成功域名置顶（JmApi.kt:220-227） */
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

  /** 排序域名：健康优先、失败次数升序；隔离中的剔除（全隔离退回全集）（JmApi.kt:163-168） */
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

  /** 域名分发服务器刷新域名池（JmApi.kt:229-249） */
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

  /** /setting：官方图片域名 + 接口版本号 + 基础 cookie（JmApi.kt:252-279） */
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

  /** 记录域名失败：连续 2 次隔离 5 分钟（JmApi.kt:626-632） */
  private markDomainFailure(domain: string): void {
    const prev: number = this.domainFailures.get(domain) === undefined ? 0 : this.domainFailures.get(domain) as number;
    const fails: number = prev + 1;
    this.domainFailures.set(domain, fails);
    if (fails >= 2) {
      this.quarantineUntil.set(domain, Date.now() + QUARANTINE_MS);
    }
  }

  /** 成功域名移到队首并持久化（JmApi.kt:370-376） */
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

  /**
   * 加密信封 GET（JmApi.kt:320-368）：
   * ts → token=md5(ts+SECRET) → 解析 {code,data} → AES 解密 data → 明文 JSON（对象或数组）。
   * 域名重试：前 3 个健康域名；总预算 18s；剩余 <800ms 放弃；单次尝试封顶剩余预算。
   */
  private async apiGet(pathAndQuery: string): Promise<Object> {
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

  // ───────────────────────── 解析（JmApi.kt:380-407） ─────────────────────────

  private parseComic(o: Record<string, Object>): AlbumLite {
    const id: string = asString(o['id']);
    const title: string = asString(o['name']);
    const author: string = asString(o['author']);
    const img: string = asString(o['image']);
    let coverUrl: string = '';
    if (img === '') {
      coverUrl = `https://${this.hostForSeed(`album/${id}`, 0)}/media/albums/${id}_3x4.jpg`;
    } else if (img.indexOf('http') === 0) {
      coverUrl = img;
    } else {
      coverUrl = `https://${this.hostForSeed(img, 0)}${img}`;
    }
    const cat: Record<string, Object> | null = asRecord(o['category']);
    const catSub: Record<string, Object> | null = asRecord(o['category_sub']);
    return new AlbumLite(id, title, author, coverUrl,
      cat === null ? '' : asString(cat['title']),
      catSub === null ? '' : asString(catSub['title']));
  }

  private parseComicArray(v: Object | null): Array<AlbumLite> {
    const out: Array<AlbumLite> = [];
    const arr: Array<Object> | null = asArray(v);
    if (arr !== null) {
      for (const item of arr) {
        const rec: Record<string, Object> | null = asRecord(item);
        if (rec !== null) {
          out.push(this.parseComic(rec));
        }
      }
    }
    return out;
  }

  /** 评论 HTML 清洗（JmApi.kt:500-507） */
  private cleanCommentHtml(raw: string): string {
    let t: string = raw.replace(/<br\s*\/?>/gi, '\n');
    t = t.replace(/<[^>]+>/g, '');
    t = t.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"').replace(/&#39;/g, '\'').replace(/&nbsp;/g, ' ');
    return t.trim();
  }

  // ───────────────────────── 业务接口 ─────────────────────────

  /** 随机推荐（每批 30 条，服务端按周期轮换；调用方本地洗牌展示）（JmApi.kt:408-410） */
  async random(): Promise<Array<AlbumLite>> {
    const element: Object = await this.apiGet(`/random_recommend?time=${Date.now()}`);
    return this.parseComicArray(element);
  }

  /** 最新上架（每页 80 条）（JmApi.kt:413-415） */
  async latest(page: number = 1): Promise<Array<AlbumLite>> {
    const element: Object = await this.apiGet(`/latest?page=${page}`);
    return this.parseComicArray(element);
  }

  /** 分类/榜单：order = mr(最新)/mv(总榜)/mv_m(月)/mv_w(周)/mv_t(日)（JmApi.kt:417-427） */
  async ranking(category: string, order: string, page: number = 1): Promise<Array<AlbumLite>> {
    const c: string = encodeURIComponent(category === '' ? '0' : category);
    const o: string = encodeURIComponent(order);
    const root: Record<string, Object> | null = asRecord(await this.apiGet(`/categories/filter?page=${page}&c=${c}&o=${o}`));
    return this.parseComicArray(root === null ? null : root['content']);
  }

  /** 分类列表（JmApi.kt:430-443） */
  async categories(): Promise<Array<CategoryItem>> {
    const root: Record<string, Object> | null = asRecord(await this.apiGet('/categories'));
    const out: Array<CategoryItem> = [];
    if (root === null) {
      return out;
    }
    const arr: Array<Object> | null = asArray(root['categories']);
    if (arr === null) {
      return out;
    }
    for (const item of arr) {
      const rec: Record<string, Object> | null = asRecord(item);
      if (rec === null) {
        continue;
      }
      out.push(new CategoryItem(
        asString(rec['id']),
        asString(rec['name']),
        asString(rec['slug']),
        asString(rec['total_albums'])
      ));
    }
    return out;
  }

  /** 本子详情（含章节目录；series 按 sort 升序，空则回退单章节）（JmApi.kt:446-471） */
  async album(albumId: string): Promise<Album> {
    const o: Record<string, Object> | null = asRecord(await this.apiGet(`/album?id=${albumId}`));
    if (o === null) {
      throw new Error('响应格式错误');
    }
    let episodes: Array<Chapter> = [];
    const series: Array<Object> | null = asArray(o['series']);
    if (series !== null) {
      for (const item of series) {
        const rec: Record<string, Object> | null = asRecord(item);
        if (rec === null) {
          continue;
        }
        episodes.push(new Chapter(
          asString(rec['id']),
          asString(rec['name']),
          asString(rec['sort'])
        ));
      }
    }
    episodes = episodes.slice().sort((a: Chapter, b: Chapter) => {
      const sa: number = this.sortInt(a.sort);
      const sb: number = this.sortInt(b.sort);
      return sa - sb;
    });
    const name: string = asString(o['name']);
    if (episodes.length === 0) {
      episodes.push(new Chapter(albumId, name, '1'));
    }
    const result: Album = new Album(albumId, name);
    result.likes = asString(o['likes']);
    result.views = asString(o['total_views']);
    const authors: Array<Object> | null = asArray(o['author']);
    if (authors !== null) {
      for (const a of authors) {
        const v: string = asString(a);
        if (v !== '') {
          result.author.push(v);
        }
      }
    }
    const tags: Array<Object> | null = asArray(o['tags']);
    if (tags !== null) {
      for (const t of tags) {
        const v: string = asString(t);
        if (v !== '') {
          result.tags.push(v);
        }
      }
    }
    result.episodes = episodes;
    return result;
  }

  private sortInt(s: string): number {
    const n: number = Number(s);
    if (s !== '' && !Number.isNaN(n)) {
      return Math.floor(n);
    }
    return 2147483647;
  }

  /** 章节图片文件名列表（JmApi.kt:474-477） */
  async chapterImages(photoId: string): Promise<Array<string>> {
    const o: Record<string, Object> | null = asRecord(await this.apiGet(`/chapter?id=${photoId}`));
    const out: Array<string> = [];
    if (o === null) {
      return out;
    }
    const arr: Array<Object> | null = asArray(o['images']);
    if (arr !== null) {
      for (const item of arr) {
        const v: string = asString(item);
        if (v !== '') {
          out.push(v);
        }
      }
    }
    return out;
  }

  /** 本子评论区（page 从 1 起，每页约 10 条）（JmApi.kt:480-498） */
  async comments(albumId: string, page: number = 1): Promise<CommentsResult> {
    const o: Record<string, Object> | null = asRecord(await this.apiGet(
      `/forum?mode=manhua&aid=${albumId}&page=${page}&lang=CN`));
    const result: CommentsResult = new CommentsResult();
    if (o === null) {
      return result;
    }
    result.total = asNumber(o['total'], 0);
    const arr: Array<Object> | null = asArray(o['list']);
    if (arr !== null) {
      for (const item of arr) {
        const c: Record<string, Object> | null = asRecord(item);
        if (c === null) {
          continue;
        }
        let nickname: string = asString(c['nickname']);
        if (nickname === '') {
          nickname = asString(c['username']);
        }
        let time: string = asString(c['addtime']);
        if (time === '') {
          time = asString(c['update_at']);
        }
        result.list.push(new CommentItem(
          asString(c['CID']),
          nickname,
          this.cleanCommentHtml(asString(c['content'])),
          asString(c['likes']),
          asBool(c['spoiler'], false) || asString(c['spoiler']) === '1',
          time,
          asString(c['parent_CID'])
        ));
      }
    }
    return result;
  }

  /**
   * 章节图片乱序解密参数（JmApi.kt:509-542）：
   * 特殊密钥 18comicAPPContent；返回 HTML 明文用正则提取 scramble_id；
   * 失败回退常量 220980；结果按 photoId 进程内缓存。
   */
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

  // ───────────────────────── 图片 CDN 池（JmApi.kt:544-623） ─────────────────────────

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

  /** 轮换到下一个图片域名（图床失败重试用）（JmApi.kt:564-570） */
  nextImageHost(current: string): string | null {
    const pool: Array<string> = this.imageHostPool();
    if (pool.length <= 1) {
      return null;
    }
    const idx: number = pool.indexOf(current);
    const next: string = pool[(idx < 0 ? 0 : idx + 1) % pool.length];
    return next === current ? null : next;
  }

  /** 记录图片域名失败：从健康池移除并触发下一轮探测（JmApi.kt:573-578） */
  reportImgHostFailure(host: string): void {
    this.healthyImgHosts = this.healthyImgHosts.filter((h: string) => h !== host);
    this.imgProbeAt = 0;
  }

  /** 后台轻量探测：按 HEAD 延迟维护健康池（30 分钟节流）（JmApi.kt:581-604） */
  refreshImageHostsAsync(): void {
    const now: number = Date.now();
    if (now - this.imgProbeAt < 30 * 60 * 1000 && this.healthyImgHosts.length > 0) {
      return;
    }
    this.imgProbeAt = now;
    const hosts: Array<string> = this.allImgHosts();
    const self: JmApi = this;
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

  /** 单图床 HEAD 计时；成功返回 "host|ms"，失败返回 null */
  private async probeImageHost(host: string): Promise<string | null> {
    const t0: number = Date.now();
    try {
      await httpUtil.head(`https://${host}/media/albums/1475774_3x4.jpg`, 5000, 8000, 10000);
      return `${host}|${Date.now() - t0}`;
    } catch (e) {
      return null;
    }
  }

  /** 同资源固定映射同一 CDN：idx = (javaHashCode(seed) & 0x7FFFFFFF) % pool；retry 递增轮换（JmApi.kt:606-611） */
  private hostForSeed(seed: string, retry: number): string {
    const pool: Array<string> = this.imageHostPool();
    let index: number = (javaStringHashCode(seed) & 0x7FFFFFFF) % pool.length;
    if (retry !== 0) {
      index = (index + retry) % pool.length;
    }
    return pool[index];
  }

  /** 章节图片完整地址（retry 递增可轮换图片域名）（JmApi.kt:613-615） */
  imageUrl(photoId: string, filename: string, retry: number = 0): string {
    return `https://${this.hostForSeed(`${photoId}/${filename}`, retry)}/media/photos/${photoId}/${filename}`;
  }

  /** 本子封面大图（JmApi.kt:617-619） */
  albumCoverUrl(albumId: string, retry: number = 0): string {
    return `https://${this.hostForSeed(`album/${albumId}`, retry)}/media/albums/${albumId}.jpg`;
  }

  /** 本子封面小图 3:4（列表/预览用，体积约 1/10）（JmApi.kt:621-623） */
  albumThumbUrl(albumId: string, retry: number = 0): string {
    return `https://${this.hostForSeed(`album/${albumId}`, retry)}/media/albums/${albumId}_3x4.jpg`;
  }

  /** 下载原始图片字节（整本下载用；失败由调用方换域名重试）（JmApi.kt:634-637） */
  async fetchBytes(url: string): Promise<ArrayBuffer> {
    return httpUtil.getBytes(url);
  }

  /** 启动时对图片域名测速排序（12 小时缓存）（JmApi.kt:647-678） */
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

  /** 单图床整图 GET 计时（12h 测速用）；成功返回 "host|ms"，失败返回 null */
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

  /**
   * 关键词搜索（JmApi.kt:686-708）。
   * order: mr 最新 / mv 最多观看 / mp 最多图片 / tf 最多爱心；
   * time: a 全部 / t 今日 / w 本周 / m 本月；year/month 指定上架年月（仅有年时只带 y）。
   */
  async search(query: string, page: number = 1, order: string = 'mr',
    time: string = 'a', year: string = '', month: string = ''): Promise<SearchResult> {
    return this.searchByOptions(new SearchOptions(query, page, order, time, year, month));
  }

  async searchByOptions(options: SearchOptions): Promise<SearchResult> {
    const q: string = encodeURIComponent(options.query);
    const o: string = encodeURIComponent(options.order);
    const t: string = encodeURIComponent(options.time);
    let datePart: string = '';
    if (options.year !== '') {
      if (options.month === '') {
        datePart = `&y=${encodeURIComponent(options.year)}`;
      } else {
        datePart = `&y=${encodeURIComponent(options.year)}&m=${encodeURIComponent(options.month)}`;
      }
    }
    const root: Record<string, Object> | null = asRecord(await this.apiGet(
      `/search?search_query=${q}&page=${options.page}&o=${o}&t=${t}${datePart}`));
    const result: SearchResult = new SearchResult();
    if (root === null) {
      return result;
    }
    result.total = asNumber(root['total'], 0);
    result.list = this.parseComicArray(root['content']);
    return result;
  }

  // ───────────────────────── 镜像切换（SET-21/22/23，鸿蒙版新增 UI 支撑） ─────────────────────────

  /** 当前域名候选池（健康排序后），设置页展示/选择用 */
  getDomains(): Array<string> {
    return this.orderedDomains();
  }

  /** 手动切换镜像：置顶并持久化（等效 rememberGoodDomain 的域名偏好语义） */
  async setPreferredDomain(domain: string): Promise<void> {
    await this.rememberGoodDomain(domain);
  }

  /** 当前图片 CDN 域名（诊断展示） */
  getImageHost(): string {
    return this.imageHost;
  }

  /** 接口版本号（诊断展示） */
  getAppVersion(): string {
    return this.appVersion;
  }

  /** 一键测速：对全部候选域名请求 /setting（带 token 头）计时，按延迟升序返回（SET-22） */
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

  /** 调试信息（设置页展示，对应 JmApi.debugInfo） */
  debugInfo(): string {
    const lines: Array<string> = [];
    lines.push(`域名(${this.domains.length}): ${this.domains.join(', ')}`);
    lines.push(`图片域名: ${this.imageHost}`);
    lines.push(`接口版本: ${this.appVersion}`);
    lines.push(`Cookie: ${httpUtil.cookieCount()} 条`);
    return lines.join('\n');
  }
}

export const jmApi: JmApi = new JmApi();
