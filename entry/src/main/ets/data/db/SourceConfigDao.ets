import { relationalStore } from '@kit.ArkData';
import { SourceAuth, SourceConfiguration, SourceEntry, SourceInstance, SourceKind } from '../Sources';
import { dbQuery, dbTransaction, txExecute, txQuery } from './AppDatabase';
import { cellLong, cellString, readRows } from './RowCodec';
import { registeredSourceKind } from '../source/SourceRegistry';

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
    const active: relationalStore.ResultSet = await txQuery(tx,
      "SELECT value FROM source_setting WHERE source_id = '' AND key = 'suwayomi_active_instance'", []);
    await readRows(active, (row: relationalStore.ResultSet): void => { configuration.activeInstance = cellString(row, 'value'); });
    return configuration;
  });
}

export function saveSourceConfiguration(configuration: SourceConfiguration): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx, 'DELETE FROM source_entry', []);
    await txExecute(tx, 'DELETE FROM source_instance', []);
    for (const instance of configuration.instances) {
      await txExecute(tx, 'INSERT INTO source_instance (id, endpoint, auth, name) VALUES (?, ?, ?, ?)',
        [instance.id, instance.endpoint, instance.auth, instance.name]);
    }
    for (let index: number = 0; index < configuration.entries.length; index++) {
      await writeEntry(tx, configuration.entries[index], index);
    }
    await txExecute(tx, "INSERT OR REPLACE INTO source_setting (source_id, key, value) VALUES ('', 'suwayomi_active_instance', ?)",
      [configuration.activeInstance]);
    await txExecute(tx, "INSERT OR REPLACE INTO source_setting (source_id, key, value) VALUES ('', 'seeded', '1')", []);
  });
}

async function writeEntry(tx: relationalStore.Transaction, entry: SourceEntry, position: number): Promise<void> {
  await txExecute(tx, 'INSERT INTO source_entry (id, instance_id, name, kind, endpoint, remote_id, language, auth, enabled, latency, position) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [entry.id, entry.instanceId, entry.name, entry.kind, entry.endpoint, entry.remoteId, entry.language,
      entry.auth, entry.enabled ? 1 : 0, entry.latency, position]);
}

export async function loadSourceSetting(sourceId: string, key: string): Promise<string | null> {
  const rows: relationalStore.ResultSet = await dbQuery('SELECT value FROM source_setting WHERE source_id = ? AND key = ?', [sourceId, key]);
  let value: string | null = null;
  await readRows(rows, (row: relationalStore.ResultSet): void => { value = cellString(row, 'value'); });
  return value;
}

export function saveSourceSetting(sourceId: string, key: string, value: string): Promise<void> {
  return dbTransaction(async (tx: relationalStore.Transaction): Promise<void> => {
    await txExecute(tx, 'INSERT OR REPLACE INTO source_setting (source_id, key, value) VALUES (?, ?, ?)', [sourceId, key, value]);
  });
}
