import { AlbumLite } from '../models/Models';
const KW_FULLCOLOR: Array<string> = ['全彩', 'フルカラー', 'full color', 'fullcolor', '彩漫', '彩色'];
const KW_ZH: Array<string> = ['中文', '漢化', '汉化', '中字', '中國', '中国', 'chinese', '汉化组', '漢化組', '翻譯組', '翻译组', '烤肉'];
const KW_JA: Array<string> = ['日本語', '日語', '日文', 'japanese', '生肉', '日版'];
const KW_KO: Array<string> = ['한국', '한글', 'korean', '韓文', '韩文', '번역'];
const KW_EN: Array<string> = ['english', '英文', '英譯', '英译', 'translated'];

function containsAny(hay: string, words: Array<string>): boolean {
  for (const w of words) {
    if (hay.indexOf(w) >= 0) {
      return true;
    }
  }
  return false;
}

/** 字符脚本判定  */
function scriptBadge(text: string): string {
  let hangul: number = 0;
  let kana: number = 0;
  let han: number = 0;
  let latin: number = 0;
  for (let i: number = 0; i < text.length; i++) {
    const c: number = text.charCodeAt(i);
    if ((c >= 0xAC00 && c <= 0xD7AF) || (c >= 0x1100 && c <= 0x11FF) || (c >= 0x3130 && c <= 0x318F)) {
      hangul++;
    } else if ((c >= 0x3040 && c <= 0x309F) || (c >= 0x30A0 && c <= 0x30FF) || (c >= 0x31F0 && c <= 0x31FF)) {
      kana++;
    } else if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF)) {
      han++;
    } else if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) {
      latin++;
    }
  }
  if (hangul > 0) {
    return '韩漫';
  }
  if (kana > 0) {
    return '日漫';
  }
  if (han > 0) {
    return '中字';
  }
  if (latin >= 4) {
    return 'EN';
  }
  return '';
}

/** 封面右上角文本徽章：全彩优先，其次语言关键词，最后脚本启发式 */
export function badgeForAlbum(item: AlbumLite): string {
  const hay: string = `${item.title} ${item.author} ${item.category} ${item.categorySub}`.toLowerCase();
  if (containsAny(hay, KW_FULLCOLOR)) {
    return '全彩';
  }
  if (containsAny(hay, KW_ZH)) {
    return '中字';
  }
  if (containsAny(hay, KW_JA)) {
    return '日漫';
  }
  if (containsAny(hay, KW_KO)) {
    return '韩漫';
  }
  if (containsAny(hay, KW_EN)) {
    return 'EN';
  }
  return scriptBadge(`${item.title}${item.author}`);
}


export function formatCount(raw: string): string {
  if (raw === '') {
    return raw;
  }
  const n: number = Number(raw);
  if (Number.isNaN(n)) {
    return raw;
  }
  if (n >= 10000) {
    const w: number = Math.round(n / 1000) / 10;
    return `${w}万`;
  }
  return raw;
}
/**
 * 语言/全彩徽章启发式（全工程统一对齐 badgeForAlbum）。
 */
export function langBadgeFor(item: AlbumLite): string {
  return badgeForAlbum(item);
}

/** 码点计数（≤16 字符校验用，等价 Kotlin codePointCount） */
