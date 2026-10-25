import asset from '@ohos.security.asset';
import { Prefs } from '../util/Prefs';
import { utf8Encode, utf8Decode } from './JmApi';

export type SourceKind = 'jm' | 'suwayomi' | 'local';
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
  private entries: Array<SourceEntry> = [];
  private loading: Promise<void> | null = null;
  private queue: Promise<void> = Promise.resolve();
  private async load(): Promise<void> {
    const p: Prefs = await Prefs.getInstance();
    const saved: string = await p.getString('sources_v1', '');
    this.entries = saved === '' ? [new SourceEntry('jm', '禁漫', 'jm'),
      new SourceEntry('local', '本地漫画', 'local')] : JSON.parse(saved) as Array<SourceEntry>;
  }
  async list(): Promise<Array<SourceEntry>> {
    if (this.loading === null) {
      this.loading = this.load();
    }
    await this.loading;
    return this.entries.slice();
  }
  async get(id: string, requireEnabled: boolean = true): Promise<SourceEntry> {
    const found: SourceEntry | undefined = (await this.list()).find((s: SourceEntry) => s.id === id);
    if (found === undefined || (requireEnabled && !found.enabled)) {
      throw new Error('书源已停用或移除，请重新关联书源');
    }
    return found;
  }
  async save(entry: SourceEntry): Promise<void> {
    const snapshot: SourceEntry = JSON.parse(JSON.stringify(entry)) as SourceEntry;
    const next: Promise<void> = this.queue.then(async (): Promise<void> => {
      const entries: Array<SourceEntry> = (await this.list()).filter((s: SourceEntry) => s.id !== snapshot.id);
      entries.push(snapshot); await this.persist(entries);
    });
    this.queue = next.catch((): void => {});
    return next;
  }
  async remove(id: string): Promise<void> {
    const next: Promise<void> = this.queue.then(async (): Promise<void> => { await this.persist((await this.list()).filter((s: SourceEntry) => s.id !== id)); });
    this.queue = next.catch((): void => {});
    return next;
  }
  private async persist(entries: Array<SourceEntry>): Promise<void> {
    const p: Prefs = await Prefs.getInstance();
    await p.putString('sources_v1', JSON.stringify(entries));
    this.entries = entries;
    AppStorage.setOrCreate('sourceVersion', Date.now());
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
export const sourceStore: SourceStore = new SourceStore();
