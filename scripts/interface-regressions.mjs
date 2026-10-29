import assert from 'node:assert/strict';
import { until } from './core-regressions.mjs';

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

async function remoteFixture(env) {
  const { SourceEntry, SourceInstance, sourceStore } = env.load('data/Sources');
  const instance = new SourceInstance();
  instance.id = 'gateway'; instance.endpoint = 'https://example.invalid'; instance.name = '服务';
  const source = new SourceEntry('existing_extension', '服务来源', 'suwayomi');
  source.instanceId = instance.id; source.remoteId = '9007199254740993123'; source.endpoint = instance.endpoint;
  await sourceStore.syncSuwayomi(instance, [source]);
  const gateway = await sourceStore.gateway();
  const manga = (id, saved = true, remoteId = source.remoteId) => ({ id, sourceId: remoteId,
    url: `/manga/${id}`, title: `作品${id}`, author: '作者', artist: null, genre: ['冒险'], thumbnailUrl: `/cover/${id}.jpg`,
    inLibrary: saved, unreadCount: 2, downloadCount: 1 });
  return { sourceStore, source, gateway, manga };
}

function reader(env) {
  const { Album, Chapter } = env.load('models/Models');
  const album = new Album('jm~reading', '阅读作品');
  album.episodes = [new Chapter('jm~chapter', '第一话')];
  const host = { aid: album.id, albumTitle: album.name, authorLine: '', chapters: album.episodes,
    chapterIndex: 0, pages: ['1.jpg', '2.jpg'], loadState: 'ready', currentPage: 0,
    inBackground: false, mode: 'horizontal', panel: 'none', sheetVisible: false, sliderDragging: false,
    hudVisible: false, canvasWidthVp: 360, canvasHeightVp: 720, zoomScale: 1, zoomOffsetX: 0, zoomOffsetY: 0,
    options: { taps: [1, 0, 2, 1, 0, 2, 3, 0, 4] }, getUIContext: () => ({ animateTo: (_options, run) => run(),
      getPromptAction: () => ({ showToast: () => {} }) }) };
  env.load('data/SourceApi').sourceApi.albumThumbUrl = () => '';
  const { ReaderController } = env.load('pages/reader/ReaderController');
  const controller = new ReaderController(host);
  controller.currentAlbum = album;
  return { host, controller, album };
}

export async function interfaceTests(test) {
  await test('图源管理恢复停用状态，隐藏保存失败回滚，展示开关同步生效', async env => {
    const { SourceEntry, sourceStore } = env.load('data/Sources');
    const { SourceManagementPage } = env.load('pages/sources/SourceManagementPage');
    const onlineA = new SourceEntry('jm_a', '在线一', 'jm'); onlineA.enabled = false;
    const onlineB = new SourceEntry('eh_b', '在线二', 'eh');
    const local = new SourceEntry('local_a', '本地', 'local');
    for (const source of [local, onlineA, onlineB]) await sourceStore.save(source);
    const page = new SourceManagementPage();
    page.sources = [local, onlineA, onlineB]; page.hidden = [];
    const notices = [];
    page.getUIContext = () => ({ getPromptAction: () => ({ showToast: notice => notices.push(notice.message) }) });
    env.state.failFlush = true;
    await page.applyHidden('jm_a', true);
    assert.deepEqual(page.hidden, []); assert.deepEqual(await sourceStore.hiddenIds(), []);
    assert.match(page.error, /磁盘/); assert.match(notices.at(-1), /磁盘/);
    await page.applyHidden('jm_a', true);
    assert.deepEqual(await sourceStore.hiddenIds(), ['jm_a']);
    await page.enable('jm_a');
    assert.equal((await sourceStore.get('jm_a')).enabled, true);
  });

  await test('远程书架保留分类与游标，缺失状态或重复游标明确失败', async env => {
    const { gateway, manga } = await remoteFixture(env);
    const { suwayomiLibrary } = env.load('data/SuwayomiLibrary');
    let malformed = false;
    env.state.handler = async request => {
      if (request.body.query.includes('categories')) return { categories: { nodes: [{ id: 0, name: '默认', order: -1, default: true }] } };
      return { mangas: { nodes: malformed ? [{ ...manga(1), inLibrary: null }] : [manga(1)],
        totalCount: 2, pageInfo: { hasNextPage: true, endCursor: 'next' } } };
    };
    assert.equal((await suwayomiLibrary.categories(gateway))[0].order, -1);
    const page = await suwayomiLibrary.library(gateway, 0, '作品', 'added', '');
    assert.equal(page.items[0].remoteSourceId, '9007199254740993123');
    assert.equal(page.items[0].coverUrl, 'https://example.invalid/cover/1.jpg');
    assert.equal(page.endCursor, 'next'); assert.equal(page.totalCount, 2); assert.equal(page.hasNextPage, true);
    const variables = env.state.calls.at(-1).body.variables;
    const query = env.state.calls.at(-1).body.query;
    assert.match(query, /\$filter: MangaFilterInput/);
    assert.match(query, /\$order: \[MangaOrderInput!\]/);
    assert.match(query, /inLibrary unreadCount downloadCount/);
    assert.deepEqual(variables.filter.categoryId, { isNull: true });
    assert.deepEqual(variables.filter.title, { includesInsensitive: '作品' });
    assert.deepEqual(variables.order, [{ by: 'IN_LIBRARY_AT', byType: 'DESC' }]);
    env.state.handler = async () => ({ fetchSourceManga: { mangas: [manga(2, false)], hasNextPage: false } });
    const browse = await suwayomiLibrary.browseSource(gateway, manga(2).sourceId, '作品', 1);
    assert.equal(browse.items[0].unread, 2); assert.equal(browse.items[0].downloaded, 1);
    assert.match(env.state.calls.at(-1).body.query, /inLibrary unreadCount downloadCount/);
    env.state.handler = async () => ({ mangas: { nodes: malformed ? [{ ...manga(1), inLibrary: null }] : [manga(1)], totalCount: 2,
      pageInfo: { hasNextPage: true, endCursor: 'next' } } });
    await assert.rejects(suwayomiLibrary.library(gateway, -1, '', 'title', 'next'), /游标/);
    malformed = true;
    await assert.rejects(suwayomiLibrary.library(gateway, -1, '', 'title', ''), /状态|数字/);
    env.state.handler = async () => ({ mangas: { nodes: [] } });
    await assert.rejects(suwayomiLibrary.library(gateway, -1, '', 'title', ''), /格式/);
    env.state.handler = async request => request.body.query.includes('query Shelf') ?
      { manga: { inLibrary: true } } : { updateManga: { manga: { id: 1, inLibrary: false } } };
    assert.equal(await suwayomiLibrary.inLibrary(gateway, 1), true);
    assert.equal(await suwayomiLibrary.setInLibrary(gateway, 1, false), false);
  });

  await test('网关搜索单独成组，隐藏扩展不丢旧作品身份，新身份保存失败不发布', async env => {
    const { sourceStore, source, gateway, manga } = await remoteFixture(env);
    const { sourceApi } = env.load('data/SourceApi');
    const { RequestAbortGroup } = env.load('util/RequestAbort');
    const { SourceManagementPage } = env.load('pages/sources/SourceManagementPage');
    await sourceStore.setHidden(source.id, true);
    const entries = await sourceApi.searchEntries();
    assert.deepEqual(entries.filter(item => item.kind === 'suwayomi').map(item => item.id), [gateway.id]);
    const settings = new SourceManagementPage(); await settings.load();
    assert.equal(settings.sources.some(item => item.kind === 'suwayomi'), false);
    source.enabled = false; await sourceStore.save(source);
    let items = [manga(1)];
    env.state.handler = async () => ({ mangas: { nodes: items, totalCount: items.length,
      pageInfo: { hasNextPage: false, endCursor: null } } });
    const result = await sourceApi.remoteLibrary(gateway, -1, '', 'added', '', new RequestAbortGroup());
    assert.equal(result.albums[0].id, 'existing_extension~1');
    assert.equal((await sourceStore.get(source.id)).enabled, true);
    assert.equal(result.items[0].key, result.albums[0].id);
    const rules = env.load('data/stores/FilterStores').blockTagsStore;
    await rules.addRule('', 'tag', '冒险');
    const blocked = await sourceApi.remoteLibrary(gateway, -1, '', 'added', '', new RequestAbortGroup());
    assert.equal(blocked.albums.length, 0);
    items = [manga(2, true, 'new_remote')]; env.state.failFlush = true;
    await assert.rejects(sourceApi.remoteLibrary(gateway, -1, '', 'added', '', new RequestAbortGroup()), /磁盘/);
    assert.equal(sourceStore.peek('gateway_new_remote'), null);
    const [a, b] = await Promise.all([
      sourceStore.bindSuwayomiSources(gateway, ['new_remote']), sourceStore.bindSuwayomiSources(gateway, ['new_remote'])]);
    assert.equal(a[0].id, b[0].id);
    assert.equal((await sourceStore.list()).filter(item => item.remoteId === 'new_remote').length, 1);
  });

  await test('远程接口错误展示中文提示，服务端异常不会切换备用地址', async env => {
    const { gateway } = await remoteFixture(env);
    const { suwayomi } = env.load('data/Suwayomi');
    gateway.lanEndpoint = 'https://backup.invalid';
    env.state.httpResponse = { responseCode: 200, result: JSON.stringify({ errors: [
      { message: "Validation error (UnknownType): Unknown type 'MangaFilter'" }
    ] }) };
    await assert.rejects(suwayomi.query(gateway, 'query { mangas { totalCount } }', {}), /接口不兼容/);
    assert.equal(env.state.calls.length, 1);
    env.state.httpResponse.result = JSON.stringify({ errors: [{ message: 'Unauthorized' }] });
    await assert.rejects(suwayomi.query(gateway, 'query { mangas { totalCount } }', {}), /登录失效/);
    env.state.httpResponse.result = JSON.stringify({ errors: [{ message: 'Exception with sensitive details' }] });
    await assert.rejects(suwayomi.query(gateway, 'query { mangas { totalCount } }', {}), error =>
      /服务端处理异常/.test(error.message) && !error.message.includes('sensitive'));
    env.state.httpResponse = null;
    env.state.handler = async () => { throw new Error('socket failed'); };
    await assert.rejects(suwayomi.query(gateway, 'query { mangas { totalCount } }', {}), /无法连接服务/);
    assert.equal(env.state.calls.length, 5);
  });

  await test('远程分类切换取消旧请求，空的可见页仍能按服务端游标继续，离页拒收结果', async env => {
    const { gateway, manga } = await remoteFixture(env);
    const api = env.load('data/SourceApi').sourceApi;
    const { RemoteMangaPage } = env.load('data/SuwayomiLibrary');
    const { AlbumLite } = env.load('models/Models');
    const { SuwayomiLibraryPage } = env.load('pages/SuwayomiLibraryPage');
    const pending = deferred(), requests = [];
    api.remoteLibrary = async (_source, category, _query, _sort, cursor, signal) => {
      requests.push({ category, cursor, signal });
      if (category === 1) return pending.promise;
      const result = new RemoteMangaPage();
      if (cursor === '') { result.hasNextPage = true; result.endCursor = 'next'; }
      else result.albums = [new AlbumLite('existing_extension~2', '新分类作品')];
      return result;
    };
    const page = new SuwayomiLibraryPage(); page.active = true; page.gateway = gateway; page.connected = true;
    page.categoryId = 1; const old = page.reload(); await until(() => requests.length === 1);
    page.categoryId = 2; await page.reload();
    assert.equal(requests[0].signal.aborted(), true); assert.equal(page.more, true); assert.equal(page.albums.length, 0);
    await page.loadLibrary(); assert.equal(requests.at(-1).cursor, 'next');
    assert.equal(page.albums[0].title, '新分类作品'); assert.equal(page.more, false);
    const oldResult = new RemoteMangaPage(); oldResult.albums = [new AlbumLite('old~1', '旧分类')];
    pending.resolve(oldResult); await old; assert.equal(page.albums[0].title, '新分类作品');
    const hidden = deferred(); api.remoteLibrary = async () => hidden.promise;
    const late = page.reload(); page.hide(); hidden.resolve(oldResult); await late;
    assert.equal(page.albums.length, 0); assert.equal(page.loading, false);
    page.active = true;
    const editing = deferred(); api.remoteLibrary = async () => editing.promise;
    const beforeEdit = page.reload(); page.editQuery('新关键词'); editing.resolve(oldResult); await beforeEdit;
    assert.equal(page.editing, true); assert.equal(page.albums.length, 0); assert.equal(page.more, false);
  });

  await test('远程扩展检索隐藏已收藏不提前结束分页，单源失败独立重试', async env => {
    const { gateway } = await remoteFixture(env);
    const { suwayomiLibrary, RemoteSource, RemoteMangaPage, RemoteManga } = env.load('data/SuwayomiLibrary');
    const { AlbumLite } = env.load('models/Models');
    const api = env.load('data/SourceApi').sourceApi, calls = [];
    suwayomiLibrary.serverSources = async () => ['a', 'b'].map(id => {
      const source = new RemoteSource(); source.id = id; source.displayName = id; return source;
    });
    let fail = true;
    api.remoteSearch = async (_gateway, source, query, number) => {
      calls.push({ source, query, number });
      if (source === 'b' && fail) throw new Error('单源失败');
      const result = new RemoteMangaPage(), item = new RemoteManga();
      item.key = `${source}~${number}`; item.inLibrary = number === 1;
      result.items = [item]; result.albums = [new AlbumLite(item.key, '作品')]; result.hasNextPage = number === 1;
      return result;
    };
    const page = new (env.load('pages/SuwayomiLibraryPage').SuwayomiLibraryPage)();
    page.active = true; page.gateway = gateway; page.explore = true; page.submitted = '书名'; page.hideSaved = true;
    await page.reload(); const [a, b] = page.groups;
    assert.equal(a.items.length, 0); assert.equal(a.more, true); assert.equal(a.page, 1);
    assert.match(b.error, /单源失败/); assert.equal(b.page, 0);
    await page.loadRemote(a); assert.equal(a.items[0].id, 'a~2'); assert.equal(a.more, false);
    fail = false; await page.loadRemote(b); assert.equal(b.page, 1); assert.equal(b.error, '');
    assert.ok(calls.every(call => call.query === '书名'));
  });

  await test('详情远程收藏与本地收藏隔离，失败保留状态，迟到响应不覆盖新页面', async env => {
    await remoteFixture(env);
    const remote = env.load('data/SuwayomiLibrary').suwayomiLibrary;
    const { library } = env.load('data/Library'), { Album } = env.load('models/Models');
    const key = 'existing_extension~1'; await library.add(new Album(key, '本地收藏'));
    const page = new (env.load('pages/WorkDetailPage').WorkDetailPage)(); page.aid = key;
    remote.inLibrary = async () => false;
    await page.loadRemoteShelf(); assert.equal(page.remoteReady, true); assert.equal(page.remoteSaved, false);
    remote.setInLibrary = async () => { throw new Error('保存失败'); };
    await page.saveRemoteShelf(true); assert.equal(page.remoteSaved, false); assert.match(page.remoteError, /保存失败/);
    remote.setInLibrary = async (_source, _id, saved) => saved;
    await page.saveRemoteShelf(true); assert.equal(page.remoteSaved, true);
    let dialog; page.getUIContext = () => ({ showAlertDialog: value => { dialog = value; } });
    page.toggleRemoteShelf(); assert.ok(dialog); assert.equal(page.remoteSaved, true);
    dialog.primaryButton.action(); assert.equal(page.remoteSaved, true);
    await page.saveRemoteShelf(false); assert.equal(page.remoteSaved, false);
    assert.ok(await library.workFor(key));
    const late = deferred(); let writeStarted = false;
    remote.setInLibrary = async () => { writeStarted = true; return late.promise; };
    const saving = page.saveRemoteShelf(true); await until(() => writeStarted);
    page.cancelRequests(); late.resolve(true); await saving; assert.equal(page.remoteSaved, false);
    assert.equal(page.remoteBusy, false);
    page.renewRequests(); await page.loadRemoteShelf(); assert.equal(page.remoteReady, true);
  });

  await test('全局搜索只请求远程书架，不散开扩展分组且编辑时取消远程请求', async env => {
    const { source, manga } = await remoteFixture(env);
    const { sourceApi } = env.load('data/SourceApi'), { SearchResult } = env.load('models/Models');
    sourceApi.searchSource = async () => new SearchResult(0, []);
    env.state.handler = async request => {
      assert.ok(request.body.query.includes('query Library'));
      return { mangas: { nodes: [manga(1)], totalCount: 1, pageInfo: { hasNextPage: false, endCursor: null } } };
    };
    const page = new (env.load('pages/SearchAllPage').SearchAllPage)(); page.query = '作品';
    await page.search(); const remote = page.groups.filter(group => group.source.kind === 'suwayomi');
    assert.equal(remote.length, 1); assert.equal(remote[0].source.id, 'gateway');
    assert.equal(remote[0].items[0].id, `${source.id}~1`); assert.equal(env.state.calls.length, 1);
    const signal = page.remoteRequests; page.editQuery(); assert.equal(signal.aborted(), true);
    const { Album } = env.load('models/Models');
    await env.load('data/SourceSwitch').discoverSources(new Album('jm~1', '不同标题'), () => true);
    assert.equal(env.state.calls.length, 2);
  });

  await test('图源入口按注册动作执行浏览、配置和导入，停用图源仍可管理', async env => {
    const { SourceEntryCard } = env.load('pages/sources/SourceEntryCard');
    const { SourceEntry } = env.load('data/Sources');
    const { sourceActions } = env.load('data/source/SourceCatalog');
    const { ROUTE_SOURCE_BROWSE, ROUTE_BLOCK_RULES, ROUTE_JM_SETTINGS, ROUTE_SOURCE_SETTINGS } = env.load('common/Route');
    const card = new SourceEntryCard(), routes = [], configured = [];
    card.stack = { pushPathByName: (name, params) => routes.push({ name, params }) };
    card.openSettings = source => configured.push(source.id);
    card.connectSource = source => configured.push(source.id);
    let imported = 0; card.importLocal = () => { imported++; };
    for (const kind of ['jm', 'eh', 'local', 'suwayomi']) {
      card.source = new SourceEntry(`opaque_${kind}`, '图源', kind);
      card.onPrimaryBrowse();
      assert.equal(routes.at(-1).params.sourceId, card.source.id);
      const secondary = card.secondaryActions();
      if (kind !== 'local') assert.ok(secondary.length > 0);
      for (const action of secondary.filter(action => !action.danger)) card.run(action);
    }
    assert.deepEqual(configured, ['opaque_eh', 'opaque_suwayomi']);
    assert.ok(routes.some(route => route.name === ROUTE_JM_SETTINGS));
    assert.ok(routes.some(route => route.name === ROUTE_SOURCE_BROWSE));
    assert.deepEqual(routes.filter(route => route.name === ROUTE_BLOCK_RULES).map(route => route.params.sourceId),
      ['opaque_suwayomi']);
    card.source = new SourceEntry('local', '本地', 'local');
    const importAction = sourceActions(card.source).find(action => action.kind === 'import');
    card.run(importAction); assert.equal(imported, 1);
    card.busy = true; card.run(importAction); assert.equal(imported, 1); card.busy = false;
    card.source.enabled = false; card.run(importAction); assert.equal(imported, 1);
    card.onPrimaryBrowse(); assert.equal(routes.at(-1).name, ROUTE_SOURCE_SETTINGS);
    card.source = new SourceEntry('remote', '扩展', 'suwayomi'); card.source.enabled = false;
    card.onPrimaryBrowse(); assert.equal(card.actionsVisible, true);
    assert.ok(card.secondaryActions().some(action => action.kind === 'remove'));
  });

  await test('扩展图源移除须确认，失败保留配置，成功刷新且保留书架', async env => {
    const { sourceStore, SourceEntry } = env.load('data/Sources');
    const { library } = env.load('data/Library');
    const { Album } = env.load('models/Models');
    const { SourceEntryCard } = env.load('pages/sources/SourceEntryCard');
    const source = new SourceEntry('extension', '扩展', 'suwayomi'); await sourceStore.save(source);
    await library.add(new Album('extension~book', '保留作品'));
    const card = new SourceEntryCard(); card.source = source;
    let dialog, reloads = 0; const errors = [];
    card.getUIContext = () => ({ showAlertDialog: value => { dialog = value; } });
    card.reloadSources = () => { reloads++; }; card.reportError = message => errors.push(message);
    card.run(card.secondaryActions().find(action => action.kind === 'remove'));
    dialog.primaryButton.action(); assert.ok(sourceStore.peek(source.id));
    env.state.failFlush = true; dialog.secondaryButton.action();
    await until(() => reloads === 1, '移除失败反馈');
    assert.ok(sourceStore.peek(source.id)); assert.match(errors[0], /磁盘/);
    dialog.secondaryButton.action(); await until(() => reloads === 2, '移除成功刷新');
    assert.equal(sourceStore.peek(source.id), null);
    assert.ok(await library.workFor('extension~book'));
  });

  await test('导出画质设置写入后参与编码，保存失败保留原选择', async env => {
    const { StoragePage } = env.load('pages/settings/StoragePage'), page = new StoragePage();
    page.getUIContext = () => ({ getPromptAction: () => ({ showToast: () => {} }) });
    const { Prefs } = env.load('util/Prefs'), prefs = await Prefs.getInstance();
    const { makeArchiveEntry } = env.load('data/CbzPacker');
    const { ChapterPage } = env.load('models/Models');
    const fs = await import('node:fs');
    const path = `${env.directory}/quality.jpg`; fs.writeFileSync(path, Buffer.from('image'));
    await page.saveOption('archiveQuality', 1);
    await makeArchiveEntry(path, new ChapterPage('jm~chapter', '1.jpg'), 0, await prefs.archiveImgQuality());
    assert.equal(page.archiveQuality, 1); assert.equal(env.state.packed.at(-1).quality, 85);
    env.state.failFlush = true; await page.saveOption('archiveQuality', 0);
    assert.equal(page.archiveQuality, 1); assert.equal(await prefs.archiveImgQuality(), 'compact');
    assert.match(page.message, /磁盘/);
    await page.saveOption('archiveQuality', 0);
    await makeArchiveEntry(path, new ChapterPage('jm~chapter', '1.jpg'), 0, await prefs.archiveImgQuality());
    assert.equal(page.archiveQuality, 0); assert.equal(env.state.packed.at(-1).quality, 95);
  });

  await test('三种搜索范围的空输入均为零请求，编辑时清除旧结果与提交条件', async env => {
    const { SearchAllPage } = env.load('pages/SearchAllPage');
    const api = env.load('data/SourceApi').sourceApi;
    let requests = 0;
    api.searchSource = async () => { requests++; throw new Error('不应请求'); };
    for (const scope of ['all', 'source', 'library']) {
      const page = new SearchAllPage(); page.scope = scope; page.query = '  ';
      page.groups = [{}]; page.submitted = '旧条件';
      await page.search();
      assert.equal(page.submitted, ''); assert.deepEqual(page.groups, []);
    }
    assert.equal(requests, 0);
  });

  await test('搜索建议排除原样输入，无匹配不显示，清空与离页使迟到候选失效', async env => {
    const history = env.load('data/stores/FilterStores').searchHistoryStore;
    await history.record('输入词'); await history.record('输入词扩展');
    const suggest = env.load('data/SearchSuggest');
    assert.deepEqual((await suggest.suggestLocal('输入词', '')).map(item => item.value), ['输入词扩展']);
    assert.deepEqual(await suggest.suggestLocal('绝无匹配', ''), []);
    const { SearchSuggestField } = env.load('pages/search/SearchSuggestField');
    const field = new SearchSuggestField(), late = deferred();
    suggest.suggestLocal = async () => late.promise;
    const pending = field.load('输入', field.generation);
    field.reset(); field.aboutToDisappear(); late.resolve([{ label: '迟到' }]); await pending;
    assert.equal(field.open, false); assert.equal(field.source.totalCount(), 0);
  });

  await test('搜索历史清空失败保留词条与展开状态，成功后恢复空态', async env => {
    const store = env.load('data/stores/FilterStores').searchHistoryStore;
    await store.record('关键词');
    const { SearchHistory } = env.load('pages/search/SearchHistory');
    const page = new SearchHistory(); await page.load(); page.expanded = true;
    const clear = store.clear.bind(store);
    store.clear = async () => { throw new Error('清空失败'); };
    await page.clear();
    assert.deepEqual(page.items, ['关键词']); assert.equal(page.expanded, true); assert.match(page.error, /清空失败/);
    store.clear = clear; await page.clear();
    assert.deepEqual(page.items, []); assert.equal(page.expanded, false); assert.equal(page.error, '');
  });

  await test('宫格随实际宽度扩列且首页最多两行，标签切换作品恢复收起', async env => {
    const { ComicGrid } = env.load('common/ComicGrid');
    const { AlbumLite } = env.load('models/Models');
    const grid = new ComicGrid(); grid.rows = 2;
    grid.items = Array.from({ length: 30 }, (_, i) => new AlbumLite(`jm~${i}`));
    grid.contentWidth = 328;
    assert.deepEqual(grid.grouped().map(row => row.length), [3, 3]);
    grid.contentWidth = 600;
    assert.deepEqual(grid.grouped().map(row => row.length), [5, 5]);
    grid.rows = 0; grid.items = grid.items.slice(0, 7);
    assert.deepEqual(grid.grouped().map(row => row.length), [5, 2]); assert.equal(grid.fillers(2).length, 3);
    const { WorkTags } = env.load('pages/detail/WorkTags');
    const tags = new WorkTags(); tags.expanded = true; tags.contentHeight = 240; tags.reset();
    assert.equal(tags.expanded, false); assert.equal(tags.contentHeight, 80);
  });

  await test('首页随机换批替换列表，旧榜单响应不覆盖新排序，离页响应不回写', async env => {
    const api = env.load('data/SourceApi').sourceApi;
    const { ExplorePage } = env.load('pages/ExplorePage');
    const page = new ExplorePage(); page.randomItems = [{ id: '旧批次' }];
    api.random = async () => [{ id: '新批次' }];
    await page.fetchSection('random'); assert.deepEqual(page.randomItems.map(item => item.id), ['新批次']);
    const first = deferred(), second = deferred(); let calls = 0;
    api.ranking = async () => (++calls === 1 ? first.promise : second.promise);
    const old = page.fetchSection('ranking'); page.currentRank = 'mv_w'; const current = page.fetchSection('ranking');
    second.resolve([{ id: '周榜' }]); await current; first.resolve([{ id: '日榜' }]); await old;
    assert.equal(page.rankItems[0].id, '周榜');
    const late = deferred(); api.latest = async () => late.promise;
    const pending = page.fetchSection('latest'); page.aboutToDisappear(); late.resolve([{ id: '迟到' }]); await pending;
    assert.deepEqual(page.latestItems, []);
  });

  await test('分类筛选整体提交默认排序、自定义关键词，后续修改不改变旧查询', async env => {
    const { JmBrowsePage } = env.load('pages/jm/JmBrowsePage');
    const page = new JmBrowsePage();
    assert.equal(page.categoryQuery.order, 'mr');
    page.selectCategory({ id: 'doujin', name: '同人', slug: 'doujin' });
    const category = page.categoryQuery;
    assert.deepEqual([category.categoryId, category.categoryName, category.categorySlug, category.order, category.customQuery],
      ['doujin', '同人', 'doujin', 'mv', '']);
    page.selectCategory({ id: 'doujin', name: '同人', slug: 'doujin' });
    assert.equal(page.categoryQuery, category);
    page.selectOrder('mv_w');
    const weekly = page.categoryQuery;
    assert.notEqual(weekly, category); assert.equal(category.order, 'mv');
    assert.deepEqual([weekly.categoryId, weekly.categoryName, weekly.categorySlug, weekly.order, weekly.customQuery],
      ['doujin', '同人', 'doujin', 'mv_w', '']);
    page.selectOrder('mv_w'); assert.equal(page.categoryQuery, weekly);
    page.selectCategory({ id: 'other', name: '其他', slug: '' });
    assert.equal(page.categoryQuery.order, 'mr');
    page.selectCustom('自定义');
    const custom = page.categoryQuery;
    assert.deepEqual([custom.categoryId, custom.categoryName, custom.categorySlug, custom.order, custom.customQuery],
      ['custom:自定义', '自定义', '', 'mr', '自定义']);
    page.selectOrder('mv_m');
    assert.equal(page.categoryQuery.customQuery, '自定义'); assert.equal(custom.order, 'mr');
    page.selectAll();
    assert.deepEqual([page.categoryQuery.categoryId, page.categoryQuery.categorySlug, page.categoryQuery.order, page.categoryQuery.customQuery], ['', '', 'mr', '']);
  });

  await test('分类列表使用当前查询快照重载、分页，并拒收上一分类的迟到结果', async env => {
    const { JmBrowsePage } = env.load('pages/jm/JmBrowsePage');
    const { CategoryPage } = env.load('pages/CategoryPage');
    const api = env.load('data/SourceApi').sourceApi;
    const old = deferred(), calls = [];
    api.ranking = async (sourceId, slug, order, page) => {
      calls.push([sourceId, slug, order, page]);
      return calls.length === 1 ? old.promise : [{ id: `jm~${slug}-${page}`, title: slug, author: [], category: '', categorySub: '' }];
    };
    const owner = new JmBrowsePage(), page = new CategoryPage(); page.sourceIdValue = 'jm';
    page.query = owner.categoryQuery;
    const pending = page.reload();
    owner.selectCategory({ id: 'doujin', name: '同人', slug: 'doujin' });
    owner.selectOrder('mv_w'); page.query = owner.categoryQuery;
    await page.reload();
    old.resolve([{ id: 'jm~old', title: '旧分类', author: [], category: '', categorySub: '' }]); await pending;
    assert.deepEqual(calls, [['jm', '0', 'mr', 1], ['jm', 'doujin', 'mv_w', 1]]);
    assert.deepEqual(page.rawItems.map(item => item.id), ['jm~doujin-1']);
    await page.loadMore();
    assert.deepEqual(calls[2], ['jm', 'doujin', 'mv_w', 2]);
    assert.deepEqual(page.rawItems.map(item => item.id), ['jm~doujin-1', 'jm~doujin-2']);
    assert.equal(page.firstLoading, false); assert.equal(page.loadingMore, false);
  });

  await test('图源重新进入使用默认会话，已有浏览实例保留当前筛选', async env => {
    const { JmBrowsePage } = env.load('pages/jm/JmBrowsePage');
    const existing = new JmBrowsePage(); existing.tab = 1;
    assert.equal(new JmBrowsePage().tab, 0); assert.equal(existing.tab, 1);
    const { EhSearchFilter } = env.load('data/eh/EhSearchFilter');
    const saved = new EhSearchFilter(); saved.categoryMask = 1; saved.minRating = 5; await saved.save();
    const { EhBrowsePage } = env.load('pages/eh/EhBrowsePage');
    const fresh = new EhBrowsePage(); fresh.aboutToAppear();
    assert.equal(fresh.tab, 0);
    assert.equal(fresh.filter.categoryMask, new EhSearchFilter().categoryMask);
    assert.equal(fresh.filter.minRating, new EhSearchFilter().minRating);
  });

  await test('阅读图片只有显示成功且可见才上报，旧图片完成事件不冒充新页面', async env => {
    const { ReaderImageItem } = env.load('pages/reader/ReaderImageItem');
    const item = new ReaderImageItem(), events = [];
    item.photoId = item.displayedChapter = 'jm~chapter'; item.filename = item.displayedFilename = '1.jpg';
    item.loading = false; item.onDisplayed = (...event) => events.push(event);
    item.imageComplete(0, item.photoId, item.filename);
    assert.equal(events.at(-1)[2], false);
    item.inViewport = true; item.reportVisibility(); assert.equal(events.at(-1)[2], true);
    item.active = false; item.reportVisibility(); assert.equal(events.at(-1)[2], false);
    item.displayed = false; item.loadToken = 2;
    item.imageComplete(1, item.photoId, item.filename); assert.equal(item.displayed, false);
  });

  await test('实际阅读前不写历史或进度，旧章节和不可见回调不推进记录，清空历史保留续读', async env => {
    const { controller, host } = reader(env), stores = env.load('data/Stores');
    controller.flushProgress(); controller.pageDisplayed('旧章节', '1.jpg', true);
    controller.pageDisplayed('jm~chapter', '1.jpg', false);
    assert.deepEqual(await stores.historyStore.getList(), []); assert.equal(await stores.readProgressStore.get(host.aid), null);
    controller.pageDisplayed('jm~chapter', '2.jpg', true);
    assert.equal((await stores.readProgressStore.get(host.aid)).page, 1);
    assert.equal((await stores.historyStore.getList())[0].id, host.aid);
    controller.readerVisible = false;
    await stores.historyStore.clear(); controller.flushProgress(); controller.pageDisplayed('jm~chapter', '1.jpg', true);
    assert.deepEqual(await stores.historyStore.getList(), []);
    assert.equal((await stores.readProgressStore.get(host.aid)).page, 1);
  });

  await test('阅读计时在后台与不可见时停止，重复显示回调按页面去重', async env => {
    const { controller, host } = reader(env), activity = env.load('data/ReadingActivity').readingActivity;
    controller.pageDisplayed('jm~chapter', '1.jpg', true); controller.pageDisplayed('jm~chapter', '1.jpg', true);
    controller.activitySince = Date.now() - 1500; host.inBackground = true; controller.backgroundChanged();
    let stats = await activity.stats(); assert.equal(stats.pages.length, 1); assert.equal(stats.books.length, 1);
    assert.ok(stats.milliseconds >= 1500 && stats.milliseconds < 2500);
    const elapsed = stats.milliseconds; controller.flushProgress(); controller.pageDisplayed('jm~chapter', '2.jpg', true);
    stats = await activity.stats(); assert.equal(stats.milliseconds, elapsed); assert.equal(stats.pages.length, 1);
    host.inBackground = false; controller.backgroundChanged(); controller.pageDisplayed('jm~chapter', '2.jpg', true);
    controller.pageDisplayed('jm~chapter', '1.jpg', false); controller.activitySince = Date.now() - 500;
    controller.pageDisplayed('jm~chapter', '2.jpg', false);
    stats = await activity.stats(); assert.equal(stats.pages.length, 2); assert.ok(stats.milliseconds >= elapsed + 500);
    const final = stats.milliseconds; controller.flushProgress(); assert.equal((await activity.stats()).milliseconds, final);
    const { ReadingStatsPage } = env.load('pages/ReadingStatsPage');
    const page = new ReadingStatsPage(); await page.load(); assert.match(page.duration(), /秒$/);
  });

  await test('自动换源先结算旧画面，目标图片尚未显示时不写新来源进度', async env => {
    const { controller, host } = reader(env), { Album, Chapter } = env.load('models/Models');
    controller.pageDisplayed('jm~chapter', '1.jpg', true); controller.activitySince = Date.now() - 1000;
    const target = new Album('jm~target', '目标作品'); target.episodes = [new Chapter('jm~next', '第一话')];
    env.load('data/SourceSwitch').fallbackSource = async () => ({ album: target, chapter: target.episodes[0], page: 0 });
    env.load('data/Library').library.activate = async () => {};
    const gate = deferred(); controller.loadPrefs = async () => gate.promise; controller.loadChapter = async () => {};
    const pending = controller.tryFallback(new Error('图片失败'), false);
    await until(() => host.aid === target.id);
    assert.equal(controller.activitySince, 0); assert.equal(controller.visiblePages.size, 0);
    assert.equal(await env.load('data/Stores').readProgressStore.get(target.id), null);
    gate.resolve(); assert.equal(await pending, true);
  });

  await test('阅读历史过滤无有效进度的旧详情记录', async env => {
    const { Album, ReadingProgress } = env.load('models/Models'), stores = env.load('data/Stores');
    for (const id of ['jm~old', 'jm~valid', 'jm~invalid']) await stores.historyStore.record(new Album(id, id), '');
    await stores.readProgressStore.save(new ReadingProgress('jm~valid', 'jm~chapter', 0, 1, 3));
    await stores.readProgressStore.save(new ReadingProgress('jm~invalid', 'jm~chapter', 0, 10, 3));
    const { UpdatesPage } = env.load('pages/UpdatesPage'); const page = new UpdatesPage(); await page.load();
    assert.deepEqual(page.history.map(item => item.id), ['jm~valid']);
    const snapshot = await stores.historyStore.getList(), late = deferred(); let reading = false;
    stores.historyStore.getList = async () => { reading = true; return late.promise; };
    const pending = page.load(); await until(() => reading);
    page.getUIContext = () => ({ showAlertDialog: options => options.secondaryButton.action() });
    page.clearHistory(); await until(() => page.history.length === 0);
    late.resolve(snapshot); await pending;
    assert.deepEqual(page.history, []); assert.notEqual(await stores.readProgressStore.get('jm~valid'), null);
  });

  await test('缩放和平移后中央点按仍可唤出菜单，双击按原画布坐标定位并可复位', async env => {
    const { host, controller } = reader(env);
    host.zoomScale = 4; host.zoomOffsetX = 300; host.zoomOffsetY = -200;
    controller.handleCanvasClick(180, 360); assert.equal(host.hudVisible, true); assert.equal(host.panel, 'progress');
    host.panel = 'prefs'; controller.handleCanvasClick(180, 100);
    assert.equal(host.hudVisible, false); assert.equal(host.panel, 'none');
    controller.resetZoom(false); controller.onDoubleTap(90, 180);
    assert.equal(host.zoomScale, 2); assert.equal(host.zoomOffsetX, 90); assert.equal(host.zoomOffsetY, 180);
    controller.onDoubleTap(90, 180); assert.equal(host.zoomScale, 1); assert.equal(host.zoomOffsetX, 0);
    controller.onHudTouch(true); host.hudVisible = true; controller.syncHudTimer(); assert.equal(controller.hudTimer, -1);
    controller.aboutToDisappear();
  });

  await test('隐私保护定位页面所属窗口，关闭可持久化，系统或保存失败恢复原值', async env => {
    const { Prefs } = env.load('util/Prefs'), prefs = await Prefs.getInstance();
    env.state.privacyFailure = true;
    await assert.rejects(prefs.setPreviewProtection(false, 'main-window'), /系统隐私保护设置失败/); assert.equal(await prefs.previewProtection(), true);
    env.state.privacyFailure = false; env.state.failFlush = true;
    await assert.rejects(prefs.setPreviewProtection(false, 'main-window'), /磁盘写入失败/); assert.equal(await prefs.previewProtection(), true);
    assert.deepEqual(env.state.privacyCalls, [false, false, true]);
    await prefs.setPreviewProtection(false, 'main-window'); assert.equal(await prefs.previewProtection(), false);
    const { PrivacyPage } = env.load('pages/settings/PrivacyPage'), page = new PrivacyPage(); page.previewOn = false;
    page.getUIContext = () => ({ getWindowName: () => 'main-window', getPromptAction: () => ({
      showToast: ({ message }) => { env.state.toasts ??= []; env.state.toasts.push(message); }
    }) });
    env.state.privacyFailure = true;
    await page.saveOption('preview', true);
    assert.equal(page.previewOn, false); assert.equal(page.privacyBusy, false); assert.match(page.message, /系统隐私保护设置失败/);
    assert.match(env.state.toasts[0], /隐私保护设置失败/);
    assert.deepEqual(env.state.privacyWindows, Array(4).fill('main-window'));
    env.state.privacyFailure = false;
    await page.saveOption('preview', true); await page.saveOption('preview', false);
    assert.equal(page.previewOn, false); assert.equal(await prefs.previewProtection(), false);
    const calls = env.state.privacyCalls.length;
    await page.saveOption('preview', false); assert.equal(env.state.privacyCalls.length, calls);
    const gate = deferred(); prefs.setPreviewProtection = async () => gate.promise;
    const pending = page.saveOption('preview', true); await page.saveOption('preview', false);
    assert.equal(page.previewOn, true); assert.equal(page.privacyBusy, true);
    gate.resolve(); await pending; assert.equal(page.privacyBusy, false);
  });

  await test('静态检查：同一节点不重复链式 bindSheet，“我的”页只保留导航行', async () => {
    const fs = await import('node:fs');
    const nodePath = await import('node:path');
    const root = new URL('../entry/src/main/ets/', import.meta.url).pathname;
    const files = [];
    const walk = dir => {
      for (const name of fs.readdirSync(dir)) {
        const full = nodePath.join(dir, name);
        if (fs.statSync(full).isDirectory()) walk(full); else if (full.endsWith('.ets')) files.push(full);
      }
    };
    walk(root);
    const closeOf = (text, open) => {
      let depth = 0;
      for (let i = open; i < text.length; i++) {
        if (text[i] === '(') depth++;
        else if (text[i] === ')' && --depth === 0) return i;
      }
      return text.length;
    };
    const doubled = [];
    for (const file of files) {
      const text = fs.readFileSync(file, 'utf8').replace(/\/\/[^\n]*/g, '');
      let at = text.indexOf('.bindSheet(');
      while (at >= 0) {
        let cursor = closeOf(text, at + '.bindSheet'.length) + 1;
        for (;;) {
          const rest = text.slice(cursor);
          const match = /^\s*\.([A-Za-z]+)\(/.exec(rest);
          if (match === null) break;
          if (match[1] === 'bindSheet') { doubled.push(nodePath.relative(root, file)); break; }
          cursor = closeOf(text, cursor + match[0].length - 1) + 1;
        }
        at = text.indexOf('.bindSheet(', at + 1);
      }
    }
    assert.deepEqual(doubled, []);
    const profile = fs.readFileSync(nodePath.join(root, 'pages/ProfilePage.ets'), 'utf8');
    assert.doesNotMatch(profile, /\bToggle\(|SettingSelectRow|bindSheet/);
    const registry = fs.readFileSync(nodePath.join(root, 'data/source/SourceRegistry.ets'), 'utf8');
    const localBlock = registry.slice(registry.indexOf('local.actions'), registry.indexOf('definitions.set(local.kind'));
    assert.doesNotMatch(localBlock, /ROUTE_BLOCK_RULES/);
    const shell = fs.readFileSync(nodePath.join(root, 'pages/MainShell.ets'), 'utf8');
    for (const route of ['ROUTE_SUWAYOMI_CONNECT', 'ROUTE_EH_SITE', 'ROUTE_READER_SETTINGS', 'ROUTE_APPEARANCE', 'ROUTE_PRIVACY', 'ROUTE_STORAGE']) {
      assert.match(shell, new RegExp(`name === ${route}\\)`));
    }
  });

  await test('详情页章节行：已读弱化、当前章进度、未读过滤与倒序、LazyForEach 数据源重载', async env => {
    const { Album, Chapter, ReadingProgress } = env.load('models/Models');
    const { buildChapterRows, ChapterDataSource, ChapterDownloadInfo } = env.load('pages/detail/ChapterRows');
    const album = new Album('jm~1', '作品');
    album.episodes = [new Chapter('a', '第1话', '1'), new Chapter('b', '第2话', '2'), new Chapter('c', '', '3')];
    const progress = new ReadingProgress('jm~1', 'b', 1, 4, 10);
    const downloads = new Map([['c', new ChapterDownloadInfo('running', 2, 5)]]);
    const rows = buildChapterRows(album, progress, '', false, true, downloads);
    assert.deepEqual(rows.map(row => [row.chapter.id, row.read, row.current, row.progressText]),
      [['a', true, false, ''], ['b', false, true, '5/10'], ['c', false, false, '']]);
    assert.equal(rows[2].download.state, 'running');
    assert.equal(rows[0].download.state, 'none');
    assert.deepEqual(buildChapterRows(album, progress, '', true, false, new Map()).map(row => row.chapter.id), ['c', 'b']);
    assert.deepEqual(buildChapterRows(album, progress, '第2', false, true, new Map()).map(row => row.chapter.id), ['b']);
    const finished = new ReadingProgress('jm~1', 'b', 1, 9, 10);
    assert.equal(buildChapterRows(album, finished, '', true, true, new Map()).length, 1);
    assert.deepEqual(buildChapterRows(null, null, '', false, true, new Map()), []);
    assert.notEqual(rows[0].key(), buildChapterRows(album, null, '', false, true, new Map())[0].key());
    const source = new ChapterDataSource();
    let reloaded = 0;
    const listener = { onDataReloaded: () => { reloaded++; } };
    source.registerDataChangeListener(listener);
    source.registerDataChangeListener(listener);
    source.setRows(rows);
    assert.equal(reloaded, 1);
    assert.equal(source.totalCount(), 3);
    assert.equal(source.getData(1).chapter.id, 'b');
    source.unregisterDataChangeListener(listener);
    source.setRows([]);
    assert.equal(reloaded, 1);
  });

  await test('详情页沉浸式单列表：无眼睛按钮、换源进标题菜单、预览页中性滑杆', async () => {
    const fs = await import('node:fs');
    const nodePath = await import('node:path');
    const root = new URL('../entry/src/main/ets/', import.meta.url).pathname;
    const read = file => fs.readFileSync(nodePath.join(root, file), 'utf8');
    const list = read('pages/detail/WorkChapterList.ets');
    assert.match(list, /LazyForEach\(this\.source/);
    assert.match(list, /swipeAction\(/);
    assert.match(list, /LongPressGesture/);
    assert.match(list, /SegmentButton\(/);
    assert.doesNotMatch(list, /阅读中/);
    const detail = read('pages/WorkDetailPage.ets');
    assert.match(detail, /enableComponentSafeArea: false/);
    assert.match(detail, /label: this\.sourceMenuLabel\(\)/);
    assert.match(detail, /label: this\.remoteMenuLabel\(\)/);
    assert.doesNotMatch(detail, /Scroll\(this\.chaptersScroller\)/);
    const hero = read('pages/detail/WorkHeroInfo.ets');
    assert.doesNotMatch(hero, /'换源'/);
    assert.match(hero, /blur\(40\)/);
    const preview = read('pages/ChapterPreviewPage.ets');
    assert.doesNotMatch(preview, /从头阅读|读 P\./);
    assert.match(preview, /selectedColor\(NEUTRAL_PROGRESS\)/);
    assert.match(preview, /contentStartOffset/);
  });
  await test('静态检查：下载管理按作品分组展开章节、单行摘要、详情页多选工具栏', async () => {
    const fs = await import('node:fs');
    const nodePath = await import('node:path');
    const root = new URL('../entry/src/main/ets/', import.meta.url).pathname;
    const read = file => fs.readFileSync(nodePath.join(root, file), 'utf8');
    const page = read('pages/DownloadsPage.ets');
    assert.match(page, /ListItemGroup\(\{ ?header: this\.TaskRow\(item\)/);
    assert.match(page, /removeChapter\(/);
    assert.doesNotMatch(page, /bindSheet/);
    const summary = read('pages/downloads/DownloadSummary.ets');
    assert.match(summary, /downloadSummaryText\(/);
    assert.doesNotMatch(summary, /Grid\(|Progress\(/);
    const detail = read('pages/WorkDetailPage.ets');
    assert.match(detail, /showActionMenu/);
    for (const label of ['标记已读', '标记未读', '自定义选择']) assert.ok(detail.includes(label), label);
    const card = read('pages/downloads/DownloadTaskCard.ets');
    assert.match(card, /NEUTRAL_PROGRESS/);
  });
  await test('阅读器目录改为 HUD 上方浮层：不再弹半模态，进度卡用图标切话与中性滑杆，未放大隐藏复位缩放', async env => {
    const { host, controller } = reader(env);
    controller.openSheet('index');
    assert.equal(host.panel, 'index'); assert.equal(host.hudVisible, true); assert.equal(host.sheetVisible, false);
    controller.openSheet('picture');
    assert.equal(host.panel, 'picture');
    const fs = await import('node:fs');
    const nodePath = await import('node:path');
    const root = new URL('../entry/src/main/ets/', import.meta.url).pathname;
    const read = file => fs.readFileSync(nodePath.join(root, file), 'utf8');
    const page = read('pages/ReaderPage.ets');
    assert.doesNotMatch(page, /bindSheet|ReaderChapterSheet/);
    assert.doesNotMatch(page, /isEnabled: this\.zoomScale/);
    assert.match(page, /menu: \{ value: this\.zoomScale > 1 \? \[/);
    const hud = read('pages/reader/ReaderHud.ets');
    assert.match(hud, /ReaderCatalogPanel\(/);
    assert.match(hud, /sys\.symbol\.chevron_left/); assert.match(hud, /sys\.symbol\.chevron_right/);
    assert.doesNotMatch(hud, /Button\('上一话'|Button\('下一话'/);
    assert.match(hud, /selectedColor\(NEUTRAL_PROGRESS\)/);
    const panel = read('pages/reader/ReaderCatalogPanel.ets');
    assert.match(panel, /Tabs\(/); assert.match(panel, /'目录'/); assert.match(panel, /'缩略图'/);
    assert.match(panel, /listDirection\(Axis\.Horizontal\)/);
    assert.match(panel, /initialIndex: Math\.max\(0, this\.chapterIndex/);
  });
}
