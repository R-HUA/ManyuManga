import { Album } from '../models/Models';
import { sourceId } from './Sources';
import { searchAlbumTags } from './db/LibraryDao';
import { AlbumTagRow } from './db/RowCodec';
import { albumCacheStore } from './stores/CacheStores';
import { favStore } from './stores/FavoriteStore';
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
    if (lower.indexOf(needle) < 0) {
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
      if (suggestion.label.toLowerCase().indexOf(needle) < 0) {
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
    const label: string = tag.namespace === '' ? tag.value : `${tag.namespace}:${tag.value}`;
    pushSuggestion(items, seen, tagSuggestion(sourceId(tag.albumId), label), onlySource);
    if (items.length >= SUGGEST_LIMIT) { return items; }
  }
  const favorites: Array<string> = await favStore.searchTags(needle, SUGGEST_LIMIT);
  for (const tag of favorites) {
    const suggestion: SearchSuggestion = tagSuggestion('', tag);
    if (suggestion.label.toLowerCase().indexOf(needle) < 0) {
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

function tagSuggestion(owner: string, raw: string): SearchSuggestion {
  const item: SearchSuggestion = new SearchSuggestion();
  item.kind = 'tag';
  item.sourceId = owner;
  const cut: number = raw.indexOf(':');
  if (cut > 0 && cut < raw.length - 1) {
    item.namespace = raw.substring(0, cut).trim();
    item.value = raw.substring(cut + 1).trim();
  } else {
    item.value = raw.trim();
  }
  item.label = item.namespace === '' ? item.value : `${item.namespace}:${item.value}`;
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
