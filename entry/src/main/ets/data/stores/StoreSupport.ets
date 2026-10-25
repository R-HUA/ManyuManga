import { asArray } from '../../models/Models';
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
