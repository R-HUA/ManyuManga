import { MetadataTerm, Album } from '../models/Models';
import { SearchSelection } from '../common/Route';
import { sourceId } from './Sources';
import { LibraryWork } from './Library';

/** 普通输入同时匹配原词和用户看到的译名。 */
export function albumMatchesText(album: Album, query: string): boolean {
  const needle: string = query.trim().toLowerCase();
  return album.name.toLowerCase().includes(needle) || album.author.concat(album.tags)
    .some((term: MetadataTerm): boolean => `${term.value} ${term.label}`.toLowerCase().includes(needle));
}

/** 同源按完整标签身份匹配，跨源不携带来源专属命名空间。 */
export function searchLibraryWorks(works: Array<LibraryWork>, query: string,
  selection: SearchSelection | null): Array<LibraryWork> {
  return works.filter((work: LibraryWork): boolean => work.albums.some((album: Album): boolean => {
    if (selection === null) { return albumMatchesText(album, query); }
    const terms: Array<MetadataTerm> = selection.field === 'author' ? album.author : album.tags;
    return terms.some((term: MetadataTerm): boolean =>
      term.value.trim().toLowerCase() === selection.term.value.trim().toLowerCase() &&
      (sourceId(album.id) !== selection.sourceId || term.namespace === selection.term.namespace));
  }));
}
