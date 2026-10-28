import {
  BlockRuleRow,
  loadBlockRules,
  loadCustomCategories,
  loadSearchHistory,
  loadSearchHistoryPage,
  addBlockRule,
  setBlockRuleEnabled,
  removeBlockRule,
  addCustomCategory,
  removeCustomCategory,
  recordSearchHistory,
  importSearchHistory,
  removeSearchHistory,
  clearSearchHistory
} from '../db/CatalogDao';
import { AlbumLite } from '../../models/Models';
import { sourceId } from '../Sources';
import { StoreQueue } from './StoreSupport';
import { assertDatabaseGeneration, databaseGeneration } from '../db/AppDatabase';
const BLOCK_TAGS_VERSION_KEY: string = 'blockTagsVersion';
function bumpBlockTagsVersion(): void {
  AppStorage.setOrCreate(BLOCK_TAGS_VERSION_KEY, Date.now());
}
function codePointCount(s: string): number {
  let n: number = 0;
  for (let i: number = 0; i < s.length; i++) {
    const c: number = s.charCodeAt(i);
    // 高代理不单独计数（与低代理组成一个码点）
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
      const c2: number = s.charCodeAt(i + 1);
      if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
        i++;
      }
    }
    n++;
  }
  return n;
}
export class SearchHistoryStore {
  private queue: StoreQueue = new StoreQueue();

  async getList(): Promise<Array<string>> {
    await this.queue.wait();
    return loadSearchHistory();
  }

  async getPage(offset: number, limit: number): Promise<Array<string>> {
    await this.queue.wait();
    return loadSearchHistoryPage(offset, limit);
  }

  record(query: string): Promise<void> {
    const value: string = query.trim();
    if (value === '') { return Promise.resolve(); }
    return this.queue.run(async (): Promise<void> => { await recordSearchHistory(value); });
  }

  removeAll(queries: Array<string>): Promise<void> {
    const snapshot: Array<string> = queries.slice();
    return this.queue.run(async (): Promise<void> => { await removeSearchHistory(snapshot); });
  }

  clear(): Promise<void> {
    return this.queue.run(async (): Promise<void> => { await clearSearchHistory(); });
  }

  importAll(queries: Array<string>): Promise<void> {
    const snapshot: Array<string> = queries.slice();
    return this.queue.run(async (): Promise<void> => { await importSearchHistory(snapshot); });
  }
}

export class BlockRule {
  id: number = 0;
  kind: string = 'keyword';
  value: string = '';
  enabled: number = 1;
  sourceId: string = '';
  updatedAt: number = 0;
}

/**
 * kind 映射：keyword 为关键词；tag、exact、exact_tag 为精确标签。
 * 其他旧值仍按关键词，避免已有行失效。
 */
export function canonicalBlockKind(kind: string): string {
  if (kind === 'tag' || kind === 'exact' || kind === 'exact_tag') {
    return 'tag';
  }
  return 'keyword';
}

export class BlockTagsStore {
  private queue: StoreQueue = new StoreQueue();
  private rules: Array<BlockRule> = [];
  private loaded: boolean = false;
  private loading: Promise<void> | null = null;

  private ensureLoaded(): Promise<void> {
    if (this.loading === null) {
      this.loading = this.doLoad().catch((error: Error): void => {
        this.loading = null;
        throw error;
      });
    }
    return this.loading;
  }

  private async doLoad(): Promise<void> {
    if (this.loaded) {
      return;
    }
    const generation: number = databaseGeneration();
    const rows: Array<BlockRuleRow> = await loadBlockRules();
    assertDatabaseGeneration(generation);
    const next: Array<BlockRule> = [];
    for (const row of rows) {
      next.push(ruleFromRow(row));
    }
    this.rules = next;
    this.loaded = true;
  }

  async rulesFor(sourceId: string): Promise<Array<BlockRule>> {
    await this.queue.wait();
    await this.ensureLoaded();
    const items: Array<BlockRule> = [];
    for (const rule of this.rules) {
      if (rule.sourceId === sourceId) {
        items.push(copyRule(rule));
      }
    }
    return items;
  }

  addRule(sourceId: string, kind: string, value: string): Promise<void> {
    const text: string = value.trim();
    if (text === '') { return Promise.resolve(); }
    return this.queue.run(async (): Promise<void> => {
      const row: BlockRuleRow = new BlockRuleRow();
      row.kind = canonicalBlockKind(kind);
      row.value = text;
      row.sourceId = sourceId;
      row.updatedAt = Date.now();
      const inserted: BlockRuleRow = await addBlockRule(row);
      if (this.loaded && !this.rules.some((rule: BlockRule): boolean => rule.id === inserted.id)) {
        this.rules.push(ruleFromRow(inserted));
      }
      bumpBlockTagsVersion();
    });
  }

  setEnabled(id: number, enabled: boolean): Promise<void> {
    return this.queue.run(async (): Promise<void> => {
      const updatedAt: number = Date.now();
      await setBlockRuleEnabled(id, enabled, updatedAt);
      if (this.loaded) {
        this.rules = this.rules.map((rule: BlockRule): BlockRule => {
          const next: BlockRule = copyRule(rule);
          if (next.id === id) { next.enabled = enabled ? 1 : 0; next.updatedAt = updatedAt; }
          return next;
        });
      }
      bumpBlockTagsVersion();
    });
  }

  removeRule(id: number): Promise<void> {
    return this.queue.run(async (): Promise<void> => {
      await removeBlockRule(id);
      if (this.loaded) { this.rules = this.rules.filter((rule: BlockRule): boolean => rule.id !== id); }
      bumpBlockTagsVersion();
    });
  }

  async isBlocked(title: string, author: string, category: string, categorySub: string,
    itemSource: string = ''): Promise<boolean> {
    await this.queue.wait();
    await this.ensureLoaded();
    for (const rule of this.rules) {
      if (rule.enabled !== 1) {
        continue;
      }
      if (rule.sourceId !== '' && rule.sourceId !== itemSource) {
        continue;
      }
      if (ruleHits(rule, title, author, category, categorySub)) {
        return true;
      }
    }
    return false;
  }

  invalidate(): void {
    this.loading = null;
    this.loaded = false;
    this.rules = [];
  }

}

function ruleFromRow(row: BlockRuleRow): BlockRule {
  const rule: BlockRule = new BlockRule();
  rule.id = row.id;
  rule.kind = canonicalBlockKind(row.kind);
  rule.value = row.value;
  rule.enabled = row.enabled === 1 ? 1 : 0;
  rule.sourceId = row.sourceId;
  rule.updatedAt = row.updatedAt;
  return rule;
}

function copyRule(rule: BlockRule): BlockRule {
  const next: BlockRule = new BlockRule();
  next.id = rule.id;
  next.kind = rule.kind;
  next.value = rule.value;
  next.enabled = rule.enabled;
  next.sourceId = rule.sourceId;
  next.updatedAt = rule.updatedAt;
  return next;
}

function ruleHits(rule: BlockRule, title: string, author: string, category: string, categorySub: string): boolean {
  if (rule.kind === 'tag') {
    return exactTagHit(rule.value, title, author, category, categorySub);
  }
  const needle: string = rule.value.trim().toLowerCase();
  if (needle === '') {
    return false;
  }
  const joined: string = `${title}${author}${category}${categorySub}`.toLowerCase();
  return joined.indexOf(needle) >= 0;
}

function exactTagHit(stored: string, title: string, author: string, category: string, categorySub: string): boolean {
  const text: string = stored.trim();
  if (text === '') {
    return false;
  }
  const fields: Array<string> = [title, author, category, categorySub];
  for (const field of fields) {
    if (sameText(field, text)) {
      return true;
    }
  }
  const cut: number = text.indexOf(':');
  if (cut <= 0 || cut >= text.length - 1) {
    return false;
  }
  const namespace: string = text.substring(0, cut).trim();
  const name: string = text.substring(cut + 1).trim();
  return sameText(category, namespace) && (sameText(categorySub, name) || sameText(title, name));
}

function sameText(left: string, right: string): boolean {
  return left.trim().toLowerCase() === right.trim().toLowerCase();
}

export class CustomCatStore {
  private queue: StoreQueue = new StoreQueue();

  async getList(): Promise<Array<string>> {
    await this.queue.wait();
    return loadCustomCategories();
  }

  add(raw: string): Promise<string> {
    const name: string = raw.trim();
    if (name === '') { return Promise.resolve('不能为空'); }
    const count: number = codePointCount(name);
    if (count > 16) { return Promise.resolve(`最多 16 个字符（当前 ${count}）`); }
    return this.queue.run(async (): Promise<string> => {
      return await addCustomCategory(name) ? '' : '已存在';
    });
  }

  remove(name: string): Promise<void> {
    return this.queue.run(async (): Promise<void> => { await removeCustomCategory(name); });
  }

}

export const searchHistoryStore: SearchHistoryStore = new SearchHistoryStore();
export const blockTagsStore: BlockTagsStore = new BlockTagsStore();
export const customCatStore: CustomCatStore = new CustomCatStore();

/** 列表过滤只调用 isBlocked，不另写一套命中规则。 */
export async function withoutBlockedAlbums(list: Array<AlbumLite>, fallbackSource: string): Promise<Array<AlbumLite>> {
  const kept: Array<AlbumLite> = [];
  for (const item of list) {
    const owner: string = item.id.indexOf('~') > 0 ? sourceId(item.id) : fallbackSource;
    const blocked: boolean = await blockTagsStore.isBlocked(
      item.title, item.author, item.category, item.categorySub, owner);
    if (!blocked) {
      kept.push(item);
    }
  }
  return kept;
}
