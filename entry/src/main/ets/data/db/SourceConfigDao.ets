import { relationalStore } from '@kit.ArkData';
import { SourceAuth, SourceConfiguration, SourceEntry, SourceInstance, SourceKind } from '../Sources';
import { dbTransaction, txExecute, txQuery } from './AppDatabase';
import { cellLong, cellString, readRows } from './RowCodec';
import { registeredSourceKind } from '../source/SourceRegistry';
import { asArray, asRecord, asString } from '../../models/Models';

function sourceKind(value: string): SourceKind {
  const kind: SourceKind | null = registeredSourceKind(value);
  if (kind !== null) {
    return kind;
  }
  throw new Error(`不支持的图源类型：${value}`);
}

function sourceAuth(value: string): SourceAuth {
  if (value === 'none' || value === 'basic' || value === 'login') {
    return value;
  }
  throw new Error('图源鉴权配置格式不正确');
}

/** 首次种子和读取在同一事务内，失败不会发布半份配置。 */
export function loadSourceConfiguration(): Promise<SourceConfiguration> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<SourceConfiguration> => {
    const marker: relationalStore.ResultSet = await txQuery(tx,
      "SELECT value FROM source_setting WHERE source_id = '' AND key = 'seeded'", []);
    let seeded: boolean = false;
    await readRows(marker, (): void => { seeded = true; });
    if (!seeded) {
      const existing: relationalStore.ResultSet = await txQuery(tx, 'SELECT id FROM source_entry LIMIT 1', []);
      let hasEntries: boolean = false;
      await readRows(existing, (): void => { hasEntries = true; });
      if (!hasEntries) {
        const defaults: Array<SourceEntry> = [new SourceEntry('jm', '禁漫', 'jm'),
          new SourceEntry('eh', 'E-Hentai / ExHentai', 'eh'), new SourceEntry('local', '本地漫画', 'local')];
        for (let index: number = 0; index < defaults.length; index++) {
          await writeEntry(tx, defaults[index], index);
        }
      }
      await txExecute(tx, "INSERT OR REPLACE INTO source_setting (source_id, key, value) VALUES ('', 'seeded', '1')", []);
    }
    const configuration: SourceConfiguration = new SourceConfiguration();
    const entries: relationalStore.ResultSet = await txQuery(tx, 'SELECT * FROM source_entry ORDER BY position ASC', []);
    await readRows(entries, (row: relationalStore.ResultSet): void => {
      const entry: SourceEntry = new SourceEntry(cellString(row, 'id'), cellString(row, 'name'), sourceKind(cellString(row, 'kind')));
      entry.instanceId = cellString(row, 'instance_id');
      entry.endpoint = cellString(row, 'endpoint');
      entry.remoteId = cellString(row, 'remote_id');
      entry.language = cellString(row, 'language');
      entry.auth = sourceAuth(cellString(row, 'auth'));
      entry.enabled = cellLong(row, 'enabled') === 1;
      entry.latency = cellLong(row, 'latency');
      configuration.entries.push(entry);
    });
    const instances: relationalStore.ResultSet = await txQuery(tx, 'SELECT * FROM source_instance', []);
    await readRows(instances, (row: relationalStore.ResultSet): void => {
      const instance: SourceInstance = new SourceInstance();
      instance.id = cellString(row, 'id');
      instance.endpoint = cellString(row, 'endpoint');
      instance.auth = sourceAuth(cellString(row, 'auth'));
      instance.name = cellString(row, 'name');
      configuration.instances.push(instance);
    });
    for (const instance of configuration.instances) {
      await applyInstanceProfile(instance, await txQuery(tx,
        "SELECT value FROM source_setting WHERE source_id = ? AND key = 'suwayomi_profile'", [instance.id]));
    }
    const active: relationalStore.ResultSet = await txQuery(tx,
      "SELECT value FROM source_setting WHERE source_id = '' AND key = 'suwayomi_active_instance'", []);
    await readRows(active, (row: relationalStore.ResultSet): void => { configuration.activeInstance = cellString(row, 'value'); });
    const hidden: relationalStore.ResultSet = await txQuery(tx,
      "SELECT value FROM source_setting WHERE source_id = '' AND key = 'hidden_sources'", []);
    await readRows(hidden, (row: relationalStore.ResultSet): void => {
      configuration.hidden = hiddenIdsFrom(cellString(row, 'value'));
    });
    return configuration;
  });
}

/** 隐藏标识存于键值表，避免为展示偏好改动 source_entry 结构。 */
function hiddenIdsFrom(text: string): Array<string> {
  if (text === '') {
    return [];
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(text) as Object;
  } catch (e) {
    return [];
  }
  const items: Array<Object> | null = asArray(parsed);
  if (items === null) {
    return [];
  }
  return items.map((item: Object): string => asString(item)).filter((value: string): boolean => value !== '');
}

/** 坏数据回退成空列表，不能让一条脏配置挡住图源载入。 */
function parseHeaders(text: string): Array<Object> {
  if (text === '') {
    return [];
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(text) as Object;
  } catch (e) {
    return [];
  }
  const items: Array<Object> | null = asArray(parsed);
  return items === null ? [] : items;
}

/** 服务实例的备用地址与自定义请求头，按实例落在键值表，不改动 source_instance 结构。 */
async function applyInstanceProfile(instance: SourceInstance, result: relationalStore.ResultSet): Promise<void> {
  let text: string = '';
  await readRows(result, (row: relationalStore.ResultSet): void => { text = cellString(row, 'value'); });
  if (text === '') {
    return;
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(text) as Object;
  } catch (e) {
    return;
  }
  const profile: Record<string, Object> | null = asRecord(parsed);
  if (profile === null) {
    return;
  }
  instance.lanEndpoint = asString(profile['lan']);
  const headers: Array<Object> | null = asArray(profile['headers']);
  instance.headers = headers === null ? '' : JSON.stringify(headers);
}

export function saveSourceConfiguration(configuration: SourceConfiguration): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx, 'DELETE FROM source_entry', []);
    await txExecute(tx, 'DELETE FROM source_instance', []);
    for (const instance of configuration.instances) {
      await txExecute(tx, 'INSERT INTO source_instance (id, endpoint, auth, name) VALUES (?, ?, ?, ?)',
        [instance.id, instance.endpoint, instance.auth, instance.name]);
      const profile: Record<string, Object> = {};
      profile['lan'] = instance.lanEndpoint;
      profile['headers'] = parseHeaders(instance.headers);
      await txExecute(tx, 'INSERT OR REPLACE INTO source_setting (source_id, key, value) VALUES (?, ?, ?)',
        [instance.id, 'suwayomi_profile', JSON.stringify(profile)]);
    }
    for (let index: number = 0; index < configuration.entries.length; index++) {
      await writeEntry(tx, configuration.entries[index], index);
    }
    await txExecute(tx, "INSERT OR REPLACE INTO source_setting (source_id, key, value) VALUES ('', 'suwayomi_active_instance', ?)",
      [configuration.activeInstance]);
    await txExecute(tx, "INSERT OR REPLACE INTO source_setting (source_id, key, value) VALUES ('', 'hidden_sources', ?)",
      [JSON.stringify(configuration.hidden)]);
    await txExecute(tx, "INSERT OR REPLACE INTO source_setting (source_id, key, value) VALUES ('', 'seeded', '1')", []);
  });
}

async function writeEntry(tx: relationalStore.Transaction, entry: SourceEntry, position: number): Promise<void> {
  await txExecute(tx, 'INSERT INTO source_entry (id, instance_id, name, kind, endpoint, remote_id, language, auth, enabled, latency, position) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [entry.id, entry.instanceId, entry.name, entry.kind, entry.endpoint, entry.remoteId, entry.language,
      entry.auth, entry.enabled ? 1 : 0, entry.latency, position]);
}
