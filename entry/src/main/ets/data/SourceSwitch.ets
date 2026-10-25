import { Album, Chapter, ReadingProgress } from '../models/Models';
import { sourceApi } from './SourceApi';
import { sourceId, sourceStore, SourceEntry } from './Sources';
import { library, LibraryWork } from './Library';
import { matchingChapter, mappedPage, highConfidence, normalizedTitle } from './Matching';
import { offlineStore } from './OfflineStore';

export class SourceSwitchResult {
  album: Album = new Album();
  chapter: Chapter = new Chapter();
  pages: Array<string> = [];
  page: number = 0;
  proportional: boolean = false;
}
export class SourceDiscovery {
  albums: Array<Album> = [];
  failures: Array<string> = [];
}
/** 信息不足的结果保留给人工选择，不因标题相似而自动关联。 */
export async function discoverSources(current: Album, valid: () => boolean): Promise<SourceDiscovery> {
  const result: SourceDiscovery = new SourceDiscovery();
  const sources: Array<SourceEntry> = (await sourceStore.list()).filter((s: SourceEntry) => s.enabled && s.id !== sourceId(current.id));
  let cursor: number = 0;
  const worker = async (): Promise<void> => {
    while (cursor < sources.length && valid()) {
      const source: SourceEntry = sources[cursor++];
      try {
        const candidates = await sourceApi.searchSource(source, current.name, 1);
        if (!valid()) { return; }
        const matches: Array<Album> = [];
        for (const candidate of candidates.list.filter((a) => normalizedTitle(a.title) === normalizedTitle(current.name)).slice(0, 5)) {
          const album: Album = await sourceApi.album(candidate.id);
          if (!valid()) { return; }
          if (highConfidence(current, album)) { matches.push(album); }
        }
        if (matches.length === 1) { result.albums.push(matches[0]); }
      } catch (e) { result.failures.push(`${source.name}：${(e as Error).message}`); }
    }
  };
  await Promise.all([worker(), worker(), worker()]);
  return result;
}
/** 切换成功以前不写入来源和进度，失败候选在本次故障内只尝试一次。 */
export async function prepareSourceSwitch(album: Album, from: Chapter, page: number, count: number): Promise<SourceSwitchResult> {
  const chapter: Chapter | null = matchingChapter(from, album.episodes);
  if (chapter === null) { throw new Error('无法唯一匹配章节，请手动选择对应章节'); }
  const pages: Array<string> = await sourceApi.chapterImages(chapter.id);
  const target: number = mappedPage(page, count, pages.length);
  const bytes: ArrayBuffer = await sourceApi.fetchPage(chapter.id, pages[target]);
  if (bytes.byteLength === 0) { throw new Error('目标书源页面为空'); }
  const result: SourceSwitchResult = new SourceSwitchResult();
  result.album = album; result.chapter = chapter; result.pages = pages; result.page = target;
  result.proportional = count !== pages.length;
  return result;
}
export async function fallbackSource(current: Album, chapter: Chapter, page: number, count: number,
  attempted: Set<string>, valid: () => boolean): Promise<SourceSwitchResult> {
  const work: LibraryWork | null = await library.workFor(current.id);
  const candidates: Array<Album> = work === null ? [] : work.albums.filter((a: Album) => a.id !== current.id && !attempted.has(a.id));
  const failures: Array<string> = [];
  if (candidates.length === 0) {
    const discovered: SourceDiscovery = await discoverSources(current, valid);
    failures.push(...discovered.failures);
    for (const album of discovered.albums) {
      if (!valid()) { throw new Error('阅读请求已取消'); }
      if (!attempted.has(album.id)) { candidates.push(album); }
      if (work !== null) { await library.associate(current.id, album); }
    }
  }
  const sources: Array<SourceEntry> = await sourceStore.list();
  const offline: Set<string> = new Set();
  for (const album of candidates) { if (await offlineStore.album(album.id) !== null) { offline.add(album.id); } }
  candidates.sort((a: Album, b: Album) => {
    if (offline.has(a.id) !== offline.has(b.id)) { return offline.has(a.id) ? -1 : 1; }
    if (work !== null && (a.id === work.activeKey || b.id === work.activeKey)) { return a.id === work.activeKey ? -1 : 1; }
    return (sources.find((s: SourceEntry) => s.id === sourceId(a.id))?.latency || Number.MAX_SAFE_INTEGER)
      - (sources.find((s: SourceEntry) => s.id === sourceId(b.id))?.latency || Number.MAX_SAFE_INTEGER);
  });
  for (const candidate of candidates) {
    if (!valid()) { throw new Error('阅读请求已取消'); }
    attempted.add(candidate.id);
    if (!offline.has(candidate.id) && !sources.some((s: SourceEntry) => s.id === sourceId(candidate.id) && s.enabled)) { continue; }
    try {
      const album: Album = await sourceApi.album(candidate.id);
      const result: SourceSwitchResult = await prepareSourceSwitch(album, chapter, page, count);
      if (!valid()) { throw new Error('阅读请求已取消'); }
      return result;
    } catch (e) { failures.push((e as Error).message); }
  }
  throw new Error(failures.length === 0 ? '没有可自动切换的关联书源，请选择其他书源' : `所有可匹配书源均不可用：${failures.join('；')}`);
}
export function switchedProgress(result: SourceSwitchResult): ReadingProgress {
  return new ReadingProgress(result.album.id, result.chapter.id,
    result.album.episodes.findIndex((c: Chapter) => c.id === result.chapter.id), result.page, result.pages.length,
    Date.now(), result.album.name, result.album.author.join(' · '), result.album.coverUrl);
}
