import { ReaderMode } from '../models/Models';

/** 阅读器底栏「模式」按此顺序循环切换。 */
export const READER_MODE_ORDER: Array<ReaderMode> = ['vertical', 'pagedVertical', 'horizontal', 'rtl', 'double'];

export function nextReaderMode(mode: ReaderMode): ReaderMode {
  const index: number = READER_MODE_ORDER.indexOf(mode);
  return READER_MODE_ORDER[(index + 1) % READER_MODE_ORDER.length];
}

export function readerModeLabel(mode: ReaderMode): string {
  switch (mode) {
    case 'vertical': return '纵向条漫';
    case 'pagedVertical': return '纵向翻页';
    case 'horizontal': return '左右翻页';
    case 'rtl': return '日漫右翻';
    case 'double': return '双页拼合';
    default: return '阅读模式';
  }
}
