import { relationalStore } from '@kit.ArkData';
import { dbQuery, dbTransaction, txExecute, txQuery } from './AppDatabase';
import { appendPage, cellLong, cellString, readRows, txExists, txPosition, txUpsert, escapeLike } from './RowCodec';

export function searchFavoriteTags(needle: string, limit: number): Promise<Array<string>> {
  return loadColumn("SELECT tag FROM favorite_tag WHERE LOWER(tag) LIKE ? ESCAPE '\\' " +
    'ORDER BY position ASC, tag ASC LIMIT ?', ['%' + escapeLike(needle.toLowerCase()) + '%', limit], 'tag');
}

export function loadSearchHistory(): Promise<Array<string>> { return loadSearchHistoryPage(0, 0); }

export function loadSearchHistoryPage(offset: number, limit: number): Promise<Array<string>> {
  const args: Array<relationalStore.ValueType> = [];
  const sql: string = appendPage('SELECT query FROM search_history ORDER BY position ASC, query ASC', args, limit, offset);
  return loadColumn(sql, args, 'query');
}

export function recordSearchHistory(query: string): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txUpsert(tx, 'search_history', ['query'], ['query', 'recorded_at', 'position'],
      [query, Date.now(), await txPosition(tx, 'search_history', true)]);
    await trimSearchHistory(tx);
  });
}

export function importSearchHistory(queries: Array<string>): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    for (let i: number = queries.length - 1; i >= 0; i--) {
      const query: string = queries[i].trim();
      if (query === '' || await txExists(tx, 'SELECT query FROM search_history WHERE query = ?', [query])) { continue; }
      await txExecute(tx, 'INSERT INTO search_history (query, recorded_at, position) VALUES (?, ?, ?)',
        [query, Date.now(), await txPosition(tx, 'search_history', true)]);
    }
    await trimSearchHistory(tx);
  });
}

async function trimSearchHistory(tx: relationalStore.Transaction): Promise<void> {
  await txExecute(tx, 'DELETE FROM search_history WHERE query IN ' +
    '(SELECT query FROM search_history ORDER BY position ASC, query ASC LIMIT -1 OFFSET ?)', [50]);
}

export function removeSearchHistory(queries: Array<string>): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    for (const query of queries) { await txExecute(tx, 'DELETE FROM search_history WHERE query = ?', [query]); }
  });
}

export function clearSearchHistory(): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx, 'DELETE FROM search_history', []);
  });
}

export class BlockRuleRow {
  id: number = 0;
  kind: string = 'keyword';
  value: string = '';
  enabled: number = 1;
  sourceId: string = '';
  updatedAt: number = 0;
}

function blockRuleFrom(row: relationalStore.ResultSet): BlockRuleRow {
  const rule: BlockRuleRow = new BlockRuleRow();
  rule.id = cellLong(row, 'id');
  rule.kind = cellString(row, 'kind');
  rule.value = cellString(row, 'value');
  rule.enabled = cellLong(row, 'enabled');
  rule.sourceId = cellString(row, 'source_id');
  rule.updatedAt = cellLong(row, 'updated_at');
  return rule;
}

export async function loadBlockRules(): Promise<Array<BlockRuleRow>> {
  const items: Array<BlockRuleRow> = [];
  await readRows(await dbQuery('SELECT * FROM block_rule ORDER BY id ASC', []),
    (row: relationalStore.ResultSet): void => { items.push(blockRuleFrom(row)); });
  return items;
}

/** 同一事务内取得自增主键，已有规则不会重新编号。 */
export function addBlockRule(rule: BlockRuleRow): Promise<BlockRuleRow> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<BlockRuleRow> => {
    let found: BlockRuleRow | null = null;
    await readRows(await txQuery(tx,
      'SELECT * FROM block_rule WHERE kind = ? AND value = ? AND source_id = ? ORDER BY id ASC LIMIT 1',
      [rule.kind, rule.value, rule.sourceId]), (row: relationalStore.ResultSet): void => { found = blockRuleFrom(row); });
    if (found !== null) { return found; }
    const values: relationalStore.ValuesBucket = {
      kind: rule.kind, value: rule.value, enabled: rule.enabled, source_id: rule.sourceId, updated_at: rule.updatedAt
    };
    const inserted: BlockRuleRow = new BlockRuleRow();
    inserted.id = await tx.insert('block_rule', values);
    if (inserted.id <= 0) { throw new Error('屏蔽规则保存失败'); }
    inserted.kind = rule.kind;
    inserted.value = rule.value;
    inserted.enabled = rule.enabled;
    inserted.sourceId = rule.sourceId;
    inserted.updatedAt = rule.updatedAt;
    return inserted;
  });
}

export function setBlockRuleEnabled(id: number, enabled: boolean, updatedAt: number): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx, 'UPDATE block_rule SET enabled = ?, updated_at = ? WHERE id = ?', [enabled ? 1 : 0, updatedAt, id]);
  });
}

export function removeBlockRule(id: number): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx, 'DELETE FROM block_rule WHERE id = ?', [id]);
  });
}

export function loadCustomCategories(): Promise<Array<string>> {
  return loadColumn('SELECT name FROM custom_category ORDER BY position ASC, name ASC', [], 'name');
}

export function addCustomCategory(name: string): Promise<boolean> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<boolean> => {
    if (await txExists(tx, 'SELECT name FROM custom_category WHERE name = ?', [name])) { return false; }
    await txExecute(tx, 'INSERT INTO custom_category (name, position, updated_at) VALUES (?, ?, ?)',
      [name, await txPosition(tx, 'custom_category', false), Date.now()]);
    return true;
  });
}

export function removeCustomCategory(name: string): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx, 'DELETE FROM custom_category WHERE name = ?', [name]);
  });
}

async function loadColumn(sql: string, args: Array<relationalStore.ValueType>, column: string): Promise<Array<string>> {
  const items: Array<string> = [];
  await readRows(await dbQuery(sql, args), (row: relationalStore.ResultSet): void => {
    const value: string = cellString(row, column);
    if (value !== '') { items.push(value); }
  });
  return items;
}
