import { asArray } from '../../models/Models';
import { assertDatabaseGeneration, databaseGeneration } from '../db/AppDatabase';

/** 同一 store 的读改写依次执行，失败只反馈给当前调用方。 */
export class StoreQueue {
  private pending: Promise<void> = Promise.resolve();

  run<T>(action: (generation: number) => Promise<T>): Promise<T> {
    const generation: number = databaseGeneration();
    const result: Promise<T> = this.pending.then(async (): Promise<T> => {
      assertDatabaseGeneration(generation);
      return action(generation);
    });
    this.pending = result.then((): void => {}).catch((): void => {});
    return result;
  }

  wait(): Promise<void> {
    return this.pending;
  }
}
export function parseJsonArray(text: string): Array<Object> {
  if (text === '') {
    return [];
  }
  try {
    const parsed: Object | null = JSON.parse(text) as Object | null;
    const arr: Array<Object> | null = asArray(parsed);
    return arr === null ? [] : arr;
  } catch (e) {
    return [];
  }
}
