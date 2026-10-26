import { relationalStore } from '@kit.ArkData';
import { Album, Chapter, asArray, asRecord, asString } from '../../models/Models';
import { txExecute, txQuery } from './AppDatabase';

/** 表名和列名仅由 DAO 常量提供，业务数据始终使用绑定参数。 */
export async function txUpsert(tx: relationalStore.Transaction, table: string, keys: Array<string>,
  columns: Array<string>, values: Array<relationalStore.ValueType>): Promise<void> {
  const updates: Array<string> = columns.filter((column: string): boolean => keys.indexOf(column) < 0)
    .map((column: string): string => `${column} = excluded.${column}`);
  const placeholders: string = columns.map((): string => '?').join(', ');
  await txExecute(tx, `INSERT INTO ${table} (${columns.join(', ')}) VALUES (${placeholders}) ` +
    `ON CONFLICT (${keys.join(', ')}) DO UPDATE SET ${updates.join(', ')}`, values);
}

export async function txExists(tx: relationalStore.Transaction, sql: string,
  args: Array<relationalStore.ValueType>): Promise<boolean> {
  let found: boolean = false;
  await readRows(await txQuery(tx, sql, args), (): void => { found = true; });
  return found;
}

export async function txPosition(tx: relationalStore.Transaction, table: string, first: boolean): Promise<number> {
  let position: number = 0;
  const aggregate: string = first ? 'MIN' : 'MAX';
  await readRows(await txQuery(tx, `SELECT COALESCE(${aggregate}(position), 0) AS position FROM ${table}`, []),
    (row: relationalStore.ResultSet): void => { position = cellLong(row, 'position'); });
  return position + (first ? -1 : 1);
}

export function cellString(row: relationalStore.ResultSet, name: string): string {
  const index: number = row.getColumnIndex(name);
  if (index < 0 || row.isColumnNull(index)) {
    return '';
  }
  return row.getString(index);
}

export function cellLong(row: relationalStore.ResultSet, name: string): number {
  const index: number = row.getColumnIndex(name);
  if (index < 0 || row.isColumnNull(index)) {
    return 0;
  }
  return row.getLong(index);
}

export function sourcePrefix(key: string): string {
  const cut: number = key.indexOf('~');
  if (cut < 1) {
    return '';
  }
  return key.substring(0, cut);
}

export function escapeLike(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
}

export function albumToJson(album: Album): string {
  return JSON.stringify(album);
}

export class AlbumTagRow {
  albumId: string = '';
  namespace: string = '';
  value: string = '';
  position: number = 0;
}

export function albumTag(albumId: string, raw: string, position: number): AlbumTagRow {
  const tag: AlbumTagRow = new AlbumTagRow();
  tag.albumId = albumId;
  tag.position = position;
  const cut: number = raw.indexOf(':');
  if (cut > 0 && cut < raw.length - 1) {
    tag.namespace = raw.substring(0, cut).trim();
    tag.value = raw.substring(cut + 1).trim();
  } else { tag.value = raw.trim(); }
  return tag;
}

/** 只同步当前本子的章节和标签；保留未变化行及其主键。 */
export async function syncAlbumRelations(tx: relationalStore.Transaction, album: Album): Promise<void> {
  const chapters: Map<string, string> = new Map<string, string>();
  await readRows(await txQuery(tx, 'SELECT * FROM album_chapter WHERE album_id = ?', [album.id]),
    (row: relationalStore.ResultSet): void => {
      chapters.set(cellString(row, 'chapter_id'), JSON.stringify([
        cellString(row, 'title'), cellString(row, 'sort'), cellLong(row, 'position')]));
    });
  for (let index: number = 0; index < album.episodes.length; index++) {
    const chapter: Chapter = album.episodes[index];
    if (chapters.get(chapter.id) !== JSON.stringify([chapter.title, chapter.sort, index])) {
      await txUpsert(tx, 'album_chapter', ['album_id', 'chapter_id'],
        ['album_id', 'chapter_id', 'title', 'sort', 'position'],
        [album.id, chapter.id, chapter.title, chapter.sort, index]);
    }
    chapters.delete(chapter.id);
  }
  for (const id of chapters.keys()) {
    await txExecute(tx, 'DELETE FROM album_chapter WHERE album_id = ? AND chapter_id = ?', [album.id, id]);
  }
  const tags: Map<string, AlbumTagRow> = new Map<string, AlbumTagRow>();
  await readRows(await txQuery(tx, 'SELECT * FROM album_tag WHERE album_id = ?', [album.id]),
    (row: relationalStore.ResultSet): void => {
      const tag: AlbumTagRow = new AlbumTagRow();
      tag.namespace = cellString(row, 'namespace');
      tag.value = cellString(row, 'value');
      tag.position = cellLong(row, 'position');
      tags.set(JSON.stringify([tag.namespace, tag.value]), tag);
    });
  const seen: Set<string> = new Set<string>();
  for (let index: number = 0; index < album.tags.length; index++) {
    const tag: AlbumTagRow = albumTag(album.id, album.tags[index], index);
    const key: string = JSON.stringify([tag.namespace, tag.value]);
    if (tag.value === '' || seen.has(key)) { continue; }
    seen.add(key);
    const old: AlbumTagRow | undefined = tags.get(key);
    if (old === undefined || old.position !== index) {
      await txUpsert(tx, 'album_tag', ['album_id', 'namespace', 'value'],
        ['album_id', 'namespace', 'value', 'position'], [album.id, tag.namespace, tag.value, index]);
    }
    tags.delete(key);
  }
  for (const tag of tags.values()) {
    await txExecute(tx, 'DELETE FROM album_tag WHERE album_id = ? AND namespace = ? AND value = ?',
      [album.id, tag.namespace, tag.value]);
  }
}

export function albumFromJson(text: string): Album {
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(text) as Object;
  } catch (e) {
    throw new Error('漫画资料已损坏，请重新获取');
  }
  const rec: Record<string, Object> | null = asRecord(parsed);
  if (rec === null || asString(rec['id']) === '' || typeof rec['name'] !== 'string') {
    throw new Error('漫画资料格式无效，请重新获取');
  }
  const album: Album = new Album(asString(rec['id']), asString(rec['name']));
  album.coverUrl = asString(rec['coverUrl']);
  album.description = asString(rec['description']);
  album.language = asString(rec['language']);
  album.originalUrl = asString(rec['originalUrl']);
  album.likes = asString(rec['likes']);
  album.views = asString(rec['views']);
  const authors: Array<Object> | null = asArray(rec['author']);
  if (authors === null) { throw new Error('漫画作者资料格式无效'); }
  for (const item of authors) {
    if (typeof item !== 'string') { throw new Error('漫画作者资料格式无效'); }
    album.author.push(asString(item));
  }
  const tags: Array<Object> | null = asArray(rec['tags']);
  if (tags === null) { throw new Error('漫画标签资料格式无效'); }
  for (const item of tags) {
    if (typeof item !== 'string') { throw new Error('漫画标签资料格式无效'); }
    album.tags.push(asString(item));
  }
  const episodes: Array<Object> | null = asArray(rec['episodes']);
  if (episodes === null) { throw new Error('漫画章节资料格式无效'); }
  const seen: Set<string> = new Set<string>();
  for (const item of episodes) {
    const row: Record<string, Object> | null = asRecord(item);
    if (row === null || asString(row['id']) === '' || typeof row['title'] !== 'string' || typeof row['sort'] !== 'string') {
      throw new Error('漫画章节资料格式无效');
    }
    const chapter: Chapter = new Chapter(asString(row['id']), asString(row['title']), asString(row['sort']));
    if (seen.has(chapter.id)) { throw new Error('漫画章节重复，请重新获取'); }
    seen.add(chapter.id);
    chapter.number = asString(row['number']);
    album.episodes.push(chapter);
  }
  return album;
}

export async function readRows(result: relationalStore.ResultSet,
  map: (row: relationalStore.ResultSet) => void): Promise<void> {
  try {
    while (result.goToNextRow()) {
      map(result);
    }
  } finally {
    result.close();
  }
}

/** 分页占位符。limit <= 0 表示不截断。数值只走绑定参数。 */
export function appendPage(sql: string, args: Array<relationalStore.ValueType>, limit: number, offset: number): string {
  if (limit <= 0) {
    return sql;
  }
  args.push(Math.floor(limit));
  args.push(offset < 0 ? 0 : Math.floor(offset));
  return `${sql} LIMIT ? OFFSET ?`;
}
