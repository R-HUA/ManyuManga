/** EH 协议命名空间与显示译名分别处理。 */
export function ehNamespace(raw: string): string {
  const ns: string = raw.trim().toLowerCase();
  switch (ns) {
    case 'a': return 'artist';
    case 'c': case 'char': return 'character';
    case 'cos': return 'cosplayer';
    case 'f': return 'female';
    case 'g': case 'circle': return 'group';
    case 'l': case 'lang': return 'language';
    case 'loc': return 'location';
    case 'm': return 'male';
    case 'x': return 'mixed';
    case 'o': return 'other';
    case 'p': case 'series': return 'parody';
    case 'r': return 'reclass';
    case 'misc': return '';
    default: return ns;
  }
}

/** 单个标签必须限定原始命名空间，并避免前缀匹配扩大结果。 */
export function ehTermQuery(namespace: string, value: string, field: string = 'tag'): string {
  const name: string = value.trim();
  const ns: string = ehNamespace(namespace);
  if (ns === 'uploader') { return `uploader:"${name}"`; }
  if (ns === '' && field === 'author') { return `"${name}"`; }
  return `${ns === '' ? 'tag' : ns}:"${name}$"`;
}

/** 用户写好的表达式保持原义，标签模式仅包装单个原始标签。 */
export function ehTagQuery(raw: string): string {
  const text: string = raw.trim();
  if (text === '' || /["$~]|(?:^|\s)-\S|\s[a-z]+:/i.test(text)) { return text; }
  const cut: number = text.indexOf(':');
  if (cut > 0) {
    const ns: string = ehNamespace(text.substring(0, cut));
    if (!['', 'artist', 'character', 'cosplayer', 'female', 'group', 'language', 'location',
      'male', 'mixed', 'other', 'parody', 'reclass', 'tag'].includes(ns)) { return text; }
    return ehTermQuery(ns, text.substring(cut + 1));
  }
  return ehTermQuery('', text);
}
