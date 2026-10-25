import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';
import { errorMessage } from '../models/Models';
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
export async function aesEcbDecrypt(base64Text: string, keyHex: string): Promise<string> {
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
