import { relationalStore } from '@kit.ArkData';
import common from '@ohos.app.ability.common';
import { getAppContext } from '../../util/Prefs';
import { APP_DB_NAME, APP_DB_VERSION, SCHEMA_V1 } from './Schema';

let opening: Promise<relationalStore.RdbStore> | null = null;
let writeGate: Promise<void> = Promise.resolve();
let maintenance: boolean = false;
let generation: number = 0;

export function databaseGeneration(): number {
  return generation;
}

/** 排队中的旧会话写入不得覆盖恢复后的数据。 */
export function assertDatabaseGeneration(expected: number): void {
  if (maintenance || expected !== generation) {
    throw new Error('数据已恢复，请重新操作');
  }
}

/** 打开业务库。重复调用复用同一次建库。 */
export function openDatabase(context?: common.Context): Promise<relationalStore.RdbStore> {
  if (opening === null) {
    const ctx: common.Context = context !== undefined ? context : getAppContext();
    opening = openNow(ctx).catch((error: Error): Promise<relationalStore.RdbStore> => {
      opening = null;
      throw error;
    });
  }
  return opening;
}

async function openNow(context: common.Context): Promise<relationalStore.RdbStore> {
  const config: relationalStore.StoreConfig = {
    name: APP_DB_NAME,
    securityLevel: relationalStore.SecurityLevel.S2
  };
  const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
  try {
    if (store.version < APP_DB_VERSION) {
      await upgradeFrom(store, store.version);
      store.version = APP_DB_VERSION;
    }
    return store;
  } catch (error) {
    await store.close();
    throw error as Error;
  }
}

/**
 * 版本升级入口。当前只有 v1 建表。
 * 下一版在这里追加 from < 2 的增量语句，不要改写已发布的 v1 语句。
 */
async function upgradeFrom(store: relationalStore.RdbStore, from: number): Promise<void> {
  if (from < 1) {
    for (const sql of SCHEMA_V1) {
      await store.executeSql(sql);
    }
  }
}

export async function dbQuery(sql: string, args: Array<relationalStore.ValueType>): Promise<relationalStore.ResultSet> {
  const ready: Promise<relationalStore.ResultSet> = writeGate.then(async (): Promise<relationalStore.ResultSet> => {
    const store: relationalStore.RdbStore = await openDatabase();
    return store.querySql(sql, args);
  });
  writeGate = ready.then((): void => {}).catch((): void => {});
  return ready;
}

/** 串行写事务。失败回滚，不留下半截记录。 */
export async function dbTransaction<T>(work: (tx: relationalStore.Transaction) => Promise<T>): Promise<T> {
  if (maintenance) {
    throw new Error('正在恢复数据，请稍后重试');
  }
  return enqueueTransaction(work);
}

/** 排空已接收写入，恢复期间拒绝新写入；提交后再同步失效内存快照。 */
export async function withDatabaseMaintenance<T>(work: (tx: relationalStore.Transaction) => Promise<T>,
  afterCommit: () => void = (): void => {}): Promise<T> {
  if (maintenance) {
    throw new Error('正在恢复数据，请稍后重试');
  }
  maintenance = true;
  try {
    const result: T = await enqueueTransaction(work);
    generation++;
    afterCommit();
    return result;
  } finally {
    maintenance = false;
  }
}

async function enqueueTransaction<T>(work: (tx: relationalStore.Transaction) => Promise<T>): Promise<T> {
  const ready: Promise<T> = writeGate.then(async (): Promise<T> => {
    const store: relationalStore.RdbStore = await openDatabase();
    const tx: relationalStore.Transaction = await store.createTransaction();
    try {
      const value: T = await work(tx);
      await tx.commit();
      return value;
    } catch (e) {
      try {
        await tx.rollback();
      } catch (rollbackError) {
      }
      throw e as Error;
    }
  });
  writeGate = ready.then((): void => {}).catch((): void => {});
  return ready;
}

export async function txExecute(tx: relationalStore.Transaction, sql: string,
  args: Array<relationalStore.ValueType>): Promise<void> {
  await tx.execute(sql, args);
}

export async function txQuery(tx: relationalStore.Transaction, sql: string,
  args: Array<relationalStore.ValueType>): Promise<relationalStore.ResultSet> {
  return tx.querySql(sql, args);
}
