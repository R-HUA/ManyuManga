import asset from '@ohos.security.asset';
import { utf8Encode, utf8Decode } from './JmApi';
import { loadSourceConfiguration, saveSourceConfiguration } from './db/SourceConfigDao';
import { assertDatabaseGeneration, databaseGeneration } from './db/AppDatabase';

export type SourceKind = 'jm' | 'suwayomi' | 'local' | 'eh';
export type SourceAuth = 'none' | 'basic' | 'login';

/** 每个服务端子书源独立参与检索，凭据由同一服务实例共享。 */
export class SourceEntry {
  id: string = '';
  instanceId: string = '';
  name: string = '';
  kind: SourceKind = 'jm';
  endpoint: string = '';
  remoteId: string = '';
  language: string = '';
  auth: SourceAuth = 'none';
  enabled: boolean = true;
  latency: number = 0;
  constructor(id: string = '', name: string = '', kind: SourceKind = 'jm') {
    this.id = id;
    this.instanceId = id;
    this.name = name;
    this.kind = kind;
  }
}

export class SourceInstance {
  id: string = '';
  endpoint: string = '';
  auth: SourceAuth = 'none';
  name: string = '';
}

export class SourceConfiguration {
  entries: Array<SourceEntry> = [];
  instances: Array<SourceInstance> = [];
  activeInstance: string = '';
}

export function copySource(entry: SourceEntry): SourceEntry {
  const copy: SourceEntry = new SourceEntry(entry.id, entry.name, entry.kind);
  copy.instanceId = entry.instanceId;
  copy.endpoint = entry.endpoint;
  copy.remoteId = entry.remoteId;
  copy.language = entry.language;
  copy.auth = entry.auth;
  copy.enabled = entry.enabled;
  copy.latency = entry.latency;
  return copy;
}

/** 来源身份必须进入所有持久化主键，服务端编号只在适配边界解包。 */
export function sourceKey(sourceId: string, nativeId: string): string {
  return `${sourceId}~${encodeURIComponent(nativeId)}`;
}
export function sourceId(key: string): string {
  const cut: number = key.indexOf('~');
  if (cut < 1) {
    throw new Error('作品缺少书源标识');
  }
  return key.substring(0, cut);
}
export function nativeId(key: string): string {
  sourceId(key);
  return decodeURIComponent(key.substring(key.indexOf('~') + 1));
}

class SourceStore {
  private configuration: SourceConfiguration = new SourceConfiguration();
  private initialized: boolean = false;
  private loading: Promise<void> | null = null;
  private queue: Promise<void> = Promise.resolve();
  private generation: number = 0;

  invalidate(): void {
    this.generation++;
    this.initialized = false;
    this.loading = null;
    this.configuration = new SourceConfiguration();
    AppStorage.setOrCreate('sourceVersion', Date.now());
  }

  private async load(ticket: number): Promise<void> {
    const configuration: SourceConfiguration = await loadSourceConfiguration();
    if (ticket === this.generation) {
      this.configuration = configuration;
      this.initialized = true;
    }
  }
  async list(): Promise<Array<SourceEntry>> {
    while (!this.initialized) {
      if (this.loading === null) {
        const ticket: number = this.generation;
        this.loading = this.load(ticket).catch((e: Error): void => {
          if (ticket === this.generation) {
            this.loading = null;
          }
          throw e;
        });
      }
      await this.loading;
    }
    return this.configuration.entries.map((entry: SourceEntry): SourceEntry => copySource(entry));
  }
  /** 同步渲染只读已提交快照；缺少初始化或身份时明确返回空。 */
  peek(id: string): SourceEntry | null {
    if (!this.initialized) {
      return null;
    }
    const entry: SourceEntry | undefined = this.configuration.entries.find((item: SourceEntry): boolean => item.id === id);
    return entry === undefined ? null : copySource(entry);
  }
  async get(id: string, requireEnabled: boolean = true): Promise<SourceEntry> {
    const found: SourceEntry | undefined = (await this.list()).find((s: SourceEntry) => s.id === id);
    if (found === undefined || (requireEnabled && !found.enabled)) {
      throw new Error('书源已停用或移除，请重新关联书源');
    }
    return found;
  }
  async save(entry: SourceEntry): Promise<void> {
    const expected: number = databaseGeneration();
    const snapshot: SourceEntry = copySource(entry);
    const next: Promise<void> = this.queue.then(async (): Promise<void> => {
      assertDatabaseGeneration(expected);
      const entries: Array<SourceEntry> = await this.list();
      assertDatabaseGeneration(expected);
      const index: number = entries.findIndex((s: SourceEntry): boolean => s.id === snapshot.id);
      if (index >= 0) {
        entries[index] = snapshot;
      } else {
        entries.push(snapshot);
      }
      const configuration: SourceConfiguration = this.copyConfiguration(entries);
      await this.persist(configuration);
    });
    this.queue = next.catch((): void => {});
    return next;
  }
  async remove(id: string): Promise<void> {
    const expected: number = databaseGeneration();
    const next: Promise<void> = this.queue.then(async (): Promise<void> => {
      assertDatabaseGeneration(expected);
      const entries: Array<SourceEntry> = (await this.list()).filter((s: SourceEntry): boolean => s.id !== id);
      assertDatabaseGeneration(expected);
      await this.persist(this.copyConfiguration(entries));
    });
    this.queue = next.catch((): void => {});
    return next;
  }
  async connection(): Promise<SourceInstance | null> {
    await this.list();
    const instance: SourceInstance | undefined = this.configuration.instances.find(
      (item: SourceInstance): boolean => item.id === this.configuration.activeInstance);
    if (instance === undefined) {
      return null;
    }
    const copy: SourceInstance = new SourceInstance();
    copy.id = instance.id;
    copy.endpoint = instance.endpoint;
    copy.auth = instance.auth;
    copy.name = instance.name;
    return copy;
  }

  /** 同一服务按 remoteId 保留身份；更换服务必须由连接页显式确认。 */
  syncSuwayomi(instance: SourceInstance, incoming: Array<SourceEntry>, replace: boolean = false): Promise<void> {
    const expected: number = databaseGeneration();
    const next: Promise<void> = this.queue.then(async (): Promise<void> => {
      assertDatabaseGeneration(expected);
      const entries: Array<SourceEntry> = await this.list();
      const current: SourceInstance | null = await this.connection();
      assertDatabaseGeneration(expected);
      if (current !== null && current.endpoint !== instance.endpoint && !replace) {
        throw new Error('更换服务地址前请确认替换连接');
      }
      if (current !== null && current.endpoint === instance.endpoint && current.id !== instance.id) {
        throw new Error('服务连接身份已改变，请重新同步');
      }
      const configuration: SourceConfiguration = this.copyConfiguration(entries);
      for (const entry of configuration.entries) {
        if (entry.kind === 'suwayomi' && (entry.instanceId === instance.id || replace)) {
          entry.enabled = false;
        }
      }
      for (const supplied of incoming) {
        const item: SourceEntry = copySource(supplied);
        const old: SourceEntry | undefined = entries.find((entry: SourceEntry): boolean =>
          entry.kind === 'suwayomi' && entry.instanceId === instance.id && entry.remoteId === item.remoteId);
        if (old !== undefined) {
          item.id = old.id;
          item.enabled = old.enabled;
        }
        const index: number = configuration.entries.findIndex((entry: SourceEntry): boolean => entry.id === item.id);
        if (index >= 0) {
          configuration.entries[index] = item;
        } else {
          configuration.entries.push(item);
        }
      }
      configuration.instances = [instance];
      configuration.activeInstance = instance.id;
      await this.persist(configuration);
    });
    this.queue = next.catch((): void => {});
    return next;
  }

  private copyConfiguration(entries: Array<SourceEntry>): SourceConfiguration {
    const configuration: SourceConfiguration = new SourceConfiguration();
    configuration.entries = entries.map((entry: SourceEntry): SourceEntry => copySource(entry));
    configuration.instances = this.configuration.instances.slice();
    configuration.activeInstance = this.configuration.activeInstance;
    return configuration;
  }

  private async persist(configuration: SourceConfiguration): Promise<void> {
    const ticket: number = this.generation;
    await saveSourceConfiguration(configuration);
    if (ticket === this.generation) {
      this.configuration = configuration;
      this.initialized = true;
      AppStorage.setOrCreate('sourceVersion', Date.now());
    }
  }
}

/** 凭据交给系统资产服务，备份文件只包含非敏感书源配置。 */
export async function saveSourceSecret(instance: string, secret: string): Promise<void> {
  const values: asset.AssetMap = new Map();
  values.set(asset.Tag.ALIAS, utf8Encode(`manyu.source.${instance}`));
  values.set(asset.Tag.SECRET, utf8Encode(secret));
  values.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
  values.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
  await asset.add(values);
}
export async function readSourceSecret(instance: string): Promise<string> {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, utf8Encode(`manyu.source.${instance}`));
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
  const result: Array<asset.AssetMap> = await asset.query(query);
  if (result.length === 0) {
    throw new Error('书源需要重新登录');
  }
  return utf8Decode(result[0].get(asset.Tag.SECRET) as Uint8Array);
}

/** 清除系统资产服务中的书源凭据；本就未存过时静默成功。 */
export async function clearSourceSecret(instance: string): Promise<void> {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, utf8Encode(`manyu.source.${instance}`));
  try {
    await asset.remove(query);
  } catch (e) {
    // 不存在即视为已清除
  }
}
export const sourceStore: SourceStore = new SourceStore();
