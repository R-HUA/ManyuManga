import assert from 'node:assert/strict';
import { until } from './core-regressions.mjs';

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

function reader(env) {
  const { Album, Chapter } = env.load('models/Models');
  const album = new Album('jm~reading', '阅读作品');
  album.episodes = [new Chapter('jm~chapter', '第一话')];
  const host = { aid: album.id, albumTitle: album.name, authorLine: '', chapters: album.episodes,
    chapterIndex: 0, pages: ['1.jpg', '2.jpg'], loadState: 'ready', currentPage: 0,
    inBackground: false, mode: 'horizontal', panel: 'none', sheetVisible: false, sliderDragging: false,
    hudVisible: false, canvasWidthVp: 360, canvasHeightVp: 720, zoomScale: 1, zoomOffsetX: 0, zoomOffsetY: 0,
    options: { taps: Array(9).fill(2) }, getUIContext: () => ({ animateTo: (_options, run) => run(),
      getPromptAction: () => ({ showToast: () => {} }) }) };
  env.load('data/SourceApi').sourceApi.albumThumbUrl = () => '';
  const { ReaderController } = env.load('pages/reader/ReaderController');
  const controller = new ReaderController(host);
  controller.currentAlbum = album;
  return { host, controller, album };
}

export async function interfaceTests(test) {
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

  await test('图源重新进入使用默认会话，已有浏览实例保留当前筛选', async env => {
    const { JmBrowsePage } = env.load('pages/jm/JmBrowsePage');
    const existing = new JmBrowsePage(); existing.tab = 1;
    assert.equal(new JmBrowsePage().tab, 0); assert.equal(existing.tab, 1);
    const { EhSearchFilter } = env.load('data/eh/EhSearchFilter');
    const saved = new EhSearchFilter(); saved.categoryMask = 1; saved.minRating = 5; await saved.save();
    const { EhBrowsePage } = env.load('pages/eh/EhBrowsePage');
    const fresh = new EhBrowsePage(); fresh.load = async () => {}; await fresh.bootstrap();
    assert.equal(fresh.tab, 0); assert.equal(fresh.query, '');
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
    controller.handleCanvasClick(180, 360); assert.equal(host.hudVisible, true);
    host.panel = 'settings'; controller.handleCanvasClick(180, 100);
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
    const { ProfilePage } = env.load('pages/ProfilePage'), page = new ProfilePage(); page.previewOn = false;
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
}
