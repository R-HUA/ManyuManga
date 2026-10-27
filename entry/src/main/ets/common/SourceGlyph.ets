/** 展示描述里的图标记号 → 系统 Symbol。$r 需要字面量，所以只在这里展开。 */
export function sourceGlyph(token: string): Resource {
  if (token === 'folder') {
    return $r('sys.symbol.folder');
  }
  if (token === 'gallery') {
    return $r('sys.symbol.website');
  }
  if (token === 'drive') {
    return $r('sys.symbol.externaldrive');
  }
  return $r('sys.symbol.website');
}
