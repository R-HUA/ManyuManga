import { Album, Chapter } from '../models/Models';

/** 标题标点与空白不影响同一作品的识别，版本和语言仍需独立核对。 */
export function normalizedTitle(value: string): string {
  return value.toLowerCase().replace(/[\s\[\]【】()（）「」『』《》·:：,，.。!！?？_\-]/g, '');
}
export function highConfidence(a: Album, b: Album): boolean {
  if (a.language !== '' && b.language !== '' && a.language !== b.language) { return false; }
  const variants: RegExp = /(彩色|全彩|单行本|連載|连载|修订|修訂|完全版|英文|日文|汉化|漢化)/g;
  const av: string = (a.name.match(variants) ?? []).sort().join('|');
  const bv: string = (b.name.match(variants) ?? []).sort().join('|');
  if (av !== bv) { return false; }
  if (a.originalUrl !== '' && a.originalUrl === b.originalUrl) { return true; }
  if (normalizedTitle(a.name) !== normalizedTitle(b.name)) { return false; }
  const authors: Array<string> = a.author.map(normalizedTitle).filter((s: string) => s !== '');
  return authors.some((author: string) => b.author.map(normalizedTitle).includes(author));
}
/** 只匹配唯一同类型编号，不把卷、番外和正文当作同一章。 */
export function matchingChapter(chapter: Chapter, candidates: Array<Chapter>): Chapter | null {
  const token: string = chapterToken(chapter);
  if (token === '') { return null; }
  const matches: Array<Chapter> = candidates.filter((c: Chapter) => chapterToken(c) === token);
  return matches.length === 1 ? matches[0] : null;
}
export function chapterToken(chapter: Chapter): string {
  const name: string = chapter.title.toLowerCase();
  const type: string = /番外|extra|special/.test(name) ? 'extra' : /卷|volume|\bvol\b/.test(name) ? 'volume' : 'chapter';
  const explicit: RegExpMatchArray | null = name.match(/(?:第\s*)?(\d+(?:\.\d+)?)\s*(?:话|話|章|卷)|(?:chapter|ch\.?|volume|vol\.?)\s*(\d+(?:\.\d+)?)/i);
  const number: string = explicit === null ? chapter.number : explicit[1] || explicit[2];
  if (number === '' || (type === 'extra' && explicit === null)) {
    return normalizedTitle(name) === '' ? '' : `title:${normalizedTitle(name)}`;
  }
  return `${type}:${Number(number)}`;
}
export function mappedPage(page: number, oldCount: number, newCount: number): number {
  if (newCount <= 0) { throw new Error('目标章节没有页面'); }
  if (oldCount === newCount) { return Math.max(0, Math.min(page, newCount - 1)); }
  return oldCount <= 1 ? 0 : Math.round(Math.max(0, Math.min(1, page / (oldCount - 1))) * (newCount - 1));
}
