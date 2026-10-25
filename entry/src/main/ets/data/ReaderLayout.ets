/** 宽幅图独占一屏，封面偏移只影响第一张普通单页。 */
export function makeSpreads(pages: Array<string>, wide: Set<string>, coverOffset: boolean): Array<Array<string>> {
  const result: Array<Array<string>> = [];
  let index: number = 0;
  while (index < pages.length) {
    if ((index === 0 && coverOffset) || wide.has(pages[index]) || index + 1 >= pages.length || wide.has(pages[index + 1])) {
      result.push([pages[index++]]);
    } else { result.push([pages[index], pages[index + 1]]); index += 2; }
  }
  return result;
}
export function spreadForPage(spreads: Array<Array<string>>, page: number): number {
  let start: number = 0;
  for (let i: number = 0; i < spreads.length; i++) { start += spreads[i].length; if (page < start) { return i; } }
  return Math.max(0, spreads.length - 1);
}
export function lastPageInSpread(spreads: Array<Array<string>>, spread: number): number {
  let page: number = -1;
  for (let i: number = 0; i <= spread && i < spreads.length; i++) { page += spreads[i].length; }
  return Math.max(0, page);
}
