import { Album, MetadataTerm } from '../models/Models';
import { sourceId } from './Sources';
import { searchAlbumTags } from './db/LibraryDao';
import { AlbumTagRow } from './db/RowCodec';
import { albumCacheStore } from './stores/CacheStores';
import { searchFavoriteTags } from './db/CatalogDao';
import { searchHistoryStore } from './stores/FilterStores';

const SUGGEST_LIMIT: number = 10;

export class SearchSuggestion {
  kind: string = 'history';
  label: string = '';
  sourceId: string = '';
  namespace: string = '';
  value: string = '';
}

export async function suggestLocal(text: string, onlySource: string): Promise<Array<SearchSuggestion>> {
  const needle: string = text.trim().toLowerCase();
  if (needle === '') {
    return [];
  }
  const items: Array<SearchSuggestion> = [];
  const seen: Array<string> = [];
  const history: Array<string> = await searchHistoryStore.getList();
  const historyHits: Array<string> = [];
  const historyRest: Array<string> = [];
  for (const query of history) {
    const lower: string = query.toLowerCase();
    if (lower.trim() === needle || lower.indexOf(needle) < 0) {
      continue;
    }
    if (lower.indexOf(needle) === 0) {
      historyHits.push(query);
    } else {
      historyRest.push(query);
    }
  }
  for (const query of historyHits.concat(historyRest)) {
    pushSuggestion(items, seen, historySuggestion(query), onlySource);
    if (items.length >= SUGGEST_LIMIT) {
      return items;
    }
  }
  const albums: Array<Album> = [];
  const cached: Array<Album> = await albumCacheStore.list();
  for (const album of cached) {
    albums.push(album);
  }
  for (const album of albums) {
    let owner: string = '';
    if (album.id.indexOf('~') > 0) {
      owner = sourceId(album.id);
    }
    for (const tag of album.tags) {
      const suggestion: SearchSuggestion = tagSuggestion(owner, tag);
      if (suggestion.label.trim().toLowerCase() === needle || suggestion.value.trim().toLowerCase() === needle) {
        continue;
      }
      if (`${suggestion.label} ${suggestion.namespace}:${suggestion.value}`.toLowerCase().indexOf(needle) < 0) {
        continue;
      }
      pushSuggestion(items, seen, suggestion, onlySource);
      if (items.length >= SUGGEST_LIMIT) {
        return items;
      }
    }
  }
  const tags: Array<AlbumTagRow> = await searchAlbumTags(needle, onlySource, SUGGEST_LIMIT * 3);
  for (const tag of tags) {
    if (tag.label.trim().toLowerCase() === needle || tag.value.trim().toLowerCase() === needle) { continue; }
    pushSuggestion(items, seen, tagSuggestion(sourceId(tag.albumId),
      new MetadataTerm(tag.value, tag.label, tag.namespace)), onlySource);
    if (items.length >= SUGGEST_LIMIT) { return items; }
  }
  const favorites: Array<string> = await searchFavoriteTags(needle, SUGGEST_LIMIT);
  for (const tag of favorites) {
    const suggestion: SearchSuggestion = tagSuggestion('', new MetadataTerm(tag));
    if (suggestion.label.trim().toLowerCase() === needle || suggestion.label.toLowerCase().indexOf(needle) < 0) {
      continue;
    }
    pushSuggestion(items, seen, suggestion, onlySource);
    if (items.length >= SUGGEST_LIMIT) {
      return items;
    }
  }
  return items;
}

function historySuggestion(query: string): SearchSuggestion {
  const item: SearchSuggestion = new SearchSuggestion();
  item.kind = 'history';
  item.label = query;
  item.value = query;
  return item;
}

function tagSuggestion(owner: string, raw: MetadataTerm): SearchSuggestion {
  const item: SearchSuggestion = new SearchSuggestion();
  item.kind = 'tag';
  item.sourceId = owner;
  item.namespace = raw.namespace;
  item.value = raw.value;
  item.label = raw.label;
  return item;
}

function pushSuggestion(items: Array<SearchSuggestion>, seen: Array<string>, item: SearchSuggestion,
  onlySource: string): void {
  if (onlySource !== '' && item.kind === 'tag' && item.sourceId !== '' && item.sourceId !== onlySource) {
    return;
  }
  const key: string = `${item.kind}|${item.sourceId}|${item.namespace}|${item.value}`;
  if (seen.indexOf(key) >= 0) {
    return;
  }
  seen.push(key);
  items.push(item);
}
