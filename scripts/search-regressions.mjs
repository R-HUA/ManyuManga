import assert from 'node:assert/strict';
import { until } from './core-regressions.mjs';

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

export async function searchTests(test) {
  await test('EH 标签、别名、上传者与标签模式共享精确查询且 URL 仅编码一次', async env => {
    const { ehTermQuery, ehTagQuery } = env.load('data/eh/EhQuery');
    const cases = [['f', 'female'], ['char', 'character'], ['circle', 'group'], ['lang', 'language'],
      ['series', 'parody'], ['loc', 'location'], ['mixed', 'mixed'], ['other', 'other']];
    for (const [alias, full] of cases) {
      assert.equal(ehTermQuery(alias, 'two words'), `${full}:"two words$"`);
      assert.equal(ehTagQuery(` ${alias} : two words `), `${full}:"two words$"`);
    }
    assert.equal(ehTermQuery('', 'two words'), 'tag:"two words$"');
    assert.equal(ehTermQuery('misc', 'two words'), 'tag:"two words$"');
    assert.equal(ehTermQuery('uploader', 'some user', 'author'), 'uploader:"some user"');
    for (const expression of ['a:"two words"$', 'f:one m:two', '-f:one', 'one -two', 'title:hello', 'uploader:name']) {
      assert.equal(ehTagQuery(expression), expression);
    }
    const { EhSearchFilter } = env.load('data/eh/EhSearchFilter');
    const filter = new EhSearchFilter(); filter.mode = 'tag'; filter.categoryMask = 2;
    const url = new URL(filter.buildUrl(' artist : a & b+中文 '));
    assert.equal(url.searchParams.get('f_search'), 'artist:"a & b+中文$"');
    assert.equal(url.searchParams.get('f_cats'), '1021');
    filter.mode = 'normal';
    assert.equal(new URL(filter.buildUrl('title:hello -f:one')).searchParams.get('f_search'), 'title:hello -f:one');
  });

  await test('EH 详情汉化保留命名空间原词，作者与上传者身份分别存储', async env => {
    const { NativeEhClient } = env.load('data/eh/EhNative');
    const { ehSource } = env.load('data/EhSource');
    const detail = { title: '作品', titleJpn: '', cover: '', rating: 0, categoryLabel: '漫画', uploader: '上传者',
      posted: '', fileSize: '', language: '', ratingCount: 0, pages: 1, detailUrl: '',
      tagGroups: [{ name: 'language', tags: ['chinese'] }, { name: 'artist', tags: ['raw artist'] }] };
    NativeEhClient.fetchGalleryDetail = async () => detail;
    const album = await ehSource.album('1234567_a1b2c3d4e5');
    assert.equal(album.tags[0].value, 'chinese'); assert.equal(album.tags[0].namespace, 'language');
    assert.notEqual(album.tags[0].label, 'language:chinese');
    assert.equal(album.author[0].value, 'raw artist'); assert.equal(album.author[0].namespace, 'artist');
    detail.tagGroups = [];
    const uploader = await ehSource.album('1234568_a1b2c3d4e5');
    assert.equal(uploader.author[0].namespace, 'uploader'); assert.equal(uploader.author[0].value, '上传者');
  });

  await test('标签原值和译名经过缓存、书架及索引往返，中文建议提交结构化原值', async env => {
    const { Album, MetadataTerm } = env.load('models/Models');
    const { albumFromJson, albumToJson } = env.load('data/db/RowCodec');
    const album = new Album('eh~1234567_a1b2c3d4e5', '作品');
    album.tags = [new MetadataTerm('two words', '女性：中文标签', 'female')];
    album.author = [new MetadataTerm('raw artist', '作者译名', 'artist')];
    assert.deepEqual(albumFromJson(albumToJson(album)).tags, album.tags);
    await env.load('data/Library').library.add(album);
    await env.load('data/stores/CacheStores').albumCacheStore.put(album);
    const rows = await env.load('data/db/LibraryDao').searchAlbumTags('中文', 'eh', 10);
    assert.equal(rows[0].namespace, 'female'); assert.equal(rows[0].value, 'two words');
    assert.equal(rows[0].label, '女性：中文标签');
    const suggestions = await env.load('data/SearchSuggest').suggestLocal('中文', 'eh');
    assert.equal(suggestions.length, 1); assert.equal(suggestions[0].value, 'two words');
    const { SearchSuggestField } = env.load('pages/search/SearchSuggestField');
    const field = new SearchSuggestField(); let received;
    field.onSubmit = (text, selection) => { received = { text, selection }; };
    field.choose(suggestions[0]);
    assert.equal(received.text, 'two words'); assert.equal(received.selection.term.namespace, 'female');
    assert.equal(received.selection.term.label, '女性：中文标签');
    const plain = new Album('jm~10', '普通标签'); plain.tags = [new MetadataTerm('name:part')];
    await env.load('data/stores/CacheStores').albumCacheStore.put(plain);
    const plainSuggestions = await env.load('data/SearchSuggest').suggestLocal('name:part', 'jm');
    assert.deepEqual(plainSuggestions, []);
  });

  await test('元数据按钮的三个搜索目标保留复合图源身份与原词', async env => {
    const { MetadataSearchChip } = env.load('pages/search/MetadataSearchChip');
    const { MetadataTerm } = env.load('models/Models');
    const chip = new MetadataSearchChip(), routes = [];
    chip.sourceId = 'opaque_source'; chip.sourceName = '当前来源'; chip.field = 'author';
    chip.term = new MetadataTerm('original author', '中文作者', 'artist');
    chip.stack = { pushPathByName: (name, params) => routes.push({ name, params }) };
    for (const scope of ['source', 'library', 'all']) chip.search(scope);
    assert.deepEqual(routes.map(route => route.params.scope), ['source', 'library', 'all']);
    for (const route of routes) {
      assert.equal(route.name, 'search'); assert.equal(route.params.sourceId, 'opaque_source');
      assert.equal(route.params.query, 'original author'); assert.equal(route.params.selection.field, 'author');
      assert.equal(route.params.selection.term.namespace, 'artist');
    }
  });

  await test('书架标签匹配区分同源命名空间，跨源用原词且关联作品仅出现一次', async env => {
    const { Album, MetadataTerm } = env.load('models/Models');
    const { SearchSelection } = env.load('common/Route');
    const { LibraryWork } = env.load('data/Library');
    const { searchLibraryWorks } = env.load('data/SearchQuery');
    const make = (id, namespace, label) => {
      const album = new Album(id, id); album.tags = [new MetadataTerm('shared', label, namespace)]; return album;
    };
    const associated = new LibraryWork(); associated.id = 'one';
    associated.albums = [make('eh~1', 'female', '女性译名'), make('jm~1', '', '其他译名')];
    const otherNamespace = new LibraryWork(); otherNamespace.id = 'two';
    otherNamespace.albums = [make('eh~2', 'male', '男性译名')];
    const works = [associated, otherNamespace];
    const selection = new SearchSelection('eh', 'tag', new MetadataTerm('shared', '女性译名', 'female'));
    assert.deepEqual(searchLibraryWorks(works, '', selection).map(work => work.id), ['one']);
    assert.deepEqual(searchLibraryWorks(works, '女性译名', null).map(work => work.id), ['one']);
    assert.deepEqual(searchLibraryWorks(works, 'shared', null).map(work => work.id), ['one', 'two']);
    const page = new (env.load('pages/SearchAllPage').SearchAllPage)();
    env.load('data/Library').library.list = async () => works;
    env.load('data/SourceApi').sourceApi.searchSource = () => { throw new Error('书架不能发网络搜索'); };
    page.scope = 'library'; page.query = selection.term.value; page.selection = selection; await page.search();
    assert.equal(page.libraryWorks.length, 1); assert.equal(page.groups.length, 0);
  });

  await test('搜索范围严格限定当前图源，全部搜索为每个目标生成自己的原词表达式', async env => {
    const { sourceStore, SourceEntry } = env.load('data/Sources');
    const { MetadataTerm, SearchResult } = env.load('models/Models');
    const { SearchSelection } = env.load('common/Route');
    const api = env.load('data/SourceApi').sourceApi, calls = [];
    await sourceStore.save(new SourceEntry('opaque', '自定义图源', 'eh'));
    api.searchSource = async (source, query, page) => { calls.push({ id: source.id, query, page }); return new SearchResult(); };
    const page = new (env.load('pages/SearchAllPage').SearchAllPage)();
    page.scope = 'source'; page.onlySource = 'opaque'; page.query = 'two words';
    page.selection = new SearchSelection('opaque', 'tag', new MetadataTerm('two words', '中文', 'female'));
    await page.search();
    assert.deepEqual(calls.map(call => call.id), ['opaque']); assert.equal(page.sourceName, '自定义图源');
    assert.equal(calls[0].query, 'female:"two words$"');
    calls.length = 0; page.scope = 'all'; await page.search();
    assert.equal(calls.find(call => call.id === 'jm').query, 'two words');
    assert.equal(calls.find(call => call.id === 'eh').query, 'female:"two words$"');
    const disabled = await sourceStore.get('opaque'); disabled.enabled = false; await sourceStore.save(disabled);
    calls.length = 0; page.scope = 'source'; await page.search();
    assert.equal(calls.length, 0); assert.match(page.error, /停用|移除/); assert.equal(page.groups.length, 0);
  });

  await test('续页沿用提交查询，快速提交和编辑使旧响应失效', async env => {
    const { sourceStore } = env.load('data/Sources'); await sourceStore.list();
    const { AlbumLite, SearchResult } = env.load('models/Models');
    const api = env.load('data/SourceApi').sourceApi, calls = [], old = deferred();
    api.searchSource = async (_source, query, number) => {
      calls.push({ query, number });
      if (query === 'slow') return old.promise;
      return new SearchResult(3, [new AlbumLite(`jm~${query}${number}`, query)]);
    };
    const page = new (env.load('pages/SearchAllPage').SearchAllPage)();
    page.scope = 'source'; page.onlySource = 'jm'; page.query = 'first'; await page.search();
    page.query = 'draft'; await page.loadGroup(0, 2);
    assert.equal(calls.at(-1).query, 'first'); assert.equal(calls.at(-1).number, 2);
    page.query = 'slow'; const pending = page.search(); await until(() => calls.some(call => call.query === 'slow'));
    page.query = 'fast'; await page.search(); old.resolve(new SearchResult(1, [new AlbumLite('jm~old', '旧结果')]));
    await pending; assert.equal(page.groups[0].items[0].title, 'fast');
    const edit = deferred(); api.searchSource = () => edit.promise;
    const editing = page.search(); await until(() => page.groups.length > 0 && page.groups[0].loading);
    page.editQuery(); edit.resolve(new SearchResult(1, [new AlbumLite('jm~late', '迟到结果')]));
    await editing; assert.equal(page.groups.length, 0); assert.equal(page.selection, null);
  });

  await test('隐藏搜索页后的迟到响应不回写，返回时重新完成被中断的搜索', async env => {
    await env.load('data/Sources').sourceStore.list();
    const { AlbumLite, SearchResult } = env.load('models/Models');
    const api = env.load('data/SourceApi').sourceApi, old = deferred(); let calls = 0;
    api.searchSource = () => { calls++; return calls === 1 ? old.promise :
      Promise.resolve(new SearchResult(1, [new AlbumLite('jm~new', '当前结果')])); };
    const page = new (env.load('pages/SearchAllPage').SearchAllPage)();
    page.scope = 'source'; page.onlySource = 'jm'; page.query = 'query';
    const pending = page.search(); await until(() => calls === 1);
    page.hideSearch(); old.resolve(new SearchResult(1, [new AlbumLite('jm~old', '旧结果')]));
    await pending; assert.equal(page.groups[0].items.length, 0);
    page.showSearch(); await until(() => page.groups[0]?.items[0]?.title === '当前结果');
    assert.equal(calls, 2); assert.equal(page.groups[0].loading, false);
  });
}
