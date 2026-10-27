import { makeRelationalStore, makeNativeFs, makeAuthentication } from './core-platform.mjs';
import { regressionTests, installOfflineFixture, until, finishTask } from './core-regressions.mjs';
import { sourceContractTests } from './source-contract-regressions.mjs';
import { searchTests } from './search-regressions.mjs';
import { interfaceTests } from './interface-regressions.mjs';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
if (!process.argv[2]) throw new Error('请传入 DevEco Studio 自带的 TypeScript 模块路径');
const ts = require(process.argv[2]);
const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ets = path.join(project, 'entry/src/main/ets');
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'manyu-core-'));
let checks = 0;
const failures = [];
const environments = [];

function environment() {
  const directory = fs.mkdtempSync(path.join(fixture, 'case-'));
  const disk = new Map();
  const secrets = new Map();
  const state = { selected: [], saved: [], calls: [], decoded: [], packed: [], failFlush: false, unzip: async () => {}, handler: async () => ({}) };
  const timers = new Set();
  const later = (callback, delay) => {
    const timer = setTimeout(() => { timers.delete(timer); callback(); }, delay);
    timers.add(timer); return timer;
  };
  const cancelLater = timer => { timers.delete(timer); clearTimeout(timer); };
  const memory = { getSync: (key, fallback) => disk.has(key) ? disk.get(key) : fallback,
    put: async (key, value) => { disk.set(key, value); },
    delete: async key => { disk.delete(key); },
    flush: async () => { await new Promise(resolve => setImmediate(resolve)); if (state.failFlush) { state.failFlush = false; throw new Error('磁盘写入失败'); } } };
  const nativeFs = makeNativeFs(directory, state);
  const authentication = makeAuthentication(state);
  const asset = { Tag: { ALIAS: 1, SECRET: 2, ACCESSIBILITY: 3, CONFLICT_RESOLUTION: 4, RETURN_TYPE: 5 },
    Accessibility: { DEVICE_FIRST_UNLOCKED: 1 }, ConflictResolution: { OVERWRITE: 0 }, ReturnType: { ALL: 0 },
    add: async values => { secrets.set(Buffer.from(values.get(1)).toString(), new Map(values)); },
    query: async query => { const value = secrets.get(Buffer.from(query.get(1)).toString()); return value ? [value] : []; },
    remove: async query => { secrets.delete(Buffer.from(query.get(1)).toString()); } };
  const jm = { utf8Encode: value => new Uint8Array(Buffer.from(value)), utf8Decode: value => Buffer.from(value).toString(),
    md5Hex: value => crypto.createHash('md5').update(value).digest('hex'),
    jmApi: { init: async () => {}, albumCoverUrl: id => `https://cover.invalid/${id}.jpg`, albumThumbUrl: id => `https://cover.invalid/${id}-thumb.jpg` } };
  const httpUtil = { getBytes: async () => new ArrayBuffer(8),
    getText: async (...args) => { state.textCalls ??= []; state.textCalls.push(args); return state.textHandler(...args); } };
  const imageDecode = {
    cachedRawFilePath: () => null,
    async descrambleFromBytes(bytes, photoId, filename, scrambleId) {
      state.decoded.push({ photoId, filename, scrambleId });
      if (state.decodeFailure) throw new Error('图片解码失败');
      return { bytes, release: async () => { state.released = (state.released ?? 0) + 1; } };
    },
    async packImage(pm, format, quality) {
      state.packed.push({ format, quality });
      if (state.packFailure) throw new Error('图片编码失败');
      return pm.bytes.slice(0);
    }
  };
  const http = { RequestMethod: { POST: 'POST' }, HttpDataType: { STRING: 'string' }, createHttp: () => ({
    request: async (url, options) => {
      const request = { url, ...options, body: JSON.parse(options.extraData) }; state.calls.push(request);
      return { responseCode: 200, result: JSON.stringify({ data: await state.handler(request) }) };
    }, destroy: () => {} }) };
  const modules = new Map();
  const context = { filesDir: path.join(directory, 'files'), cacheDir: path.join(directory, 'cache') };
  fs.mkdirSync(context.filesDir); fs.mkdirSync(context.cacheDir);
  globalThis.AppStorage = { setOrCreate: () => {}, get: () => undefined };
  globalThis.Scroller = class { scrollTo() {} scrollEdge() {} };
  globalThis.SwiperController = class { changeIndex() {} };
  globalThis.Curve = { EaseOut: 'easeOut', Friction: 'friction' };
  const relational = makeRelationalStore(state);
  function load(file) {
    file = path.resolve(file);
    if (file.endsWith(path.normalize('/data/JmApi.ets'))) return jm;
    if (file.endsWith(path.normalize('/data/ImageDecode.ets'))) return imageDecode;
    if (file.endsWith(path.normalize('/util/Http.ets'))) return { httpUtil };
    if (file.endsWith(path.normalize('/entryability/EntryAbility.ets'))) return {
      TOP_RECT_HEIGHT_KEY: 'topRectHeight', BOTTOM_RECT_HEIGHT_KEY: 'bottomRectHeight', IS_DARK_MODE_KEY: 'isDarkMode'
    };
    if (modules.has(file)) return modules.get(file).exports;
    const module = { exports: {} }; modules.set(file, module);
    let source = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
    if (file.endsWith(path.normalize('/pages/reader/ReaderImageItem.ets'))) {
      source = source.slice(0, source.indexOf('@Component')) + source.slice(source.indexOf('@Component\nexport struct ReaderImageItem'));
      source = source.replace(/  build\(\) \{[\s\S]*?(?=  private reportVisibility)/, '');
    }
    // 保留真实页面方法，只移除本地 Node 无法执行的 ArkUI 声明式布局。
    if (/[/\\]pages[/\\](SearchAllPage|ExplorePage|UpdatesPage|ProfilePage|ReadingStatsPage|jm[/\\]JmBrowsePage|eh[/\\]EhBrowsePage|detail[/\\]WorkTags|reader[/\\]ReaderImageItem|search[/\\](SearchHistory|SearchSuggestField|MetadataSearchChip))\.ets$/.test(file) || file.endsWith(path.normalize('/common/ComicGrid.ets'))) {
      const builder = source.indexOf('  @Builder');
      const end = builder >= 0 ? builder : source.indexOf('  build()');
      assert.ok(end > 0);
      source = (source.slice(0, end) + '\n}').replace(/@Component\s+export struct /g, 'export class ')
        .replace(/@(Consume|StorageProp|Watch|Prop|Link)\([^)]*\)\s*/g, '')
        .replace(/@(State|Prop|Link)\s+/g, '');
    }
    const output = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true } }).outputText;
    const native = {
      "@ohos.security.cryptoFramework": authentication.cryptoFramework, "@ohos.userIAM.userAuth": authentication.userAuth,
      '@ohos.data.preferences': { getPreferencesSync: () => memory }, '@ohos.security.asset': asset,
      '@ohos.file.fs': nativeFs, '@ohos.file.picker': { DocumentViewPicker: class { async select() { return state.selected; } async save() { return state.saved; } } },
      '@ohos.zlib': { decompressFile: (...args) => state.unzip(...args) }, '@ohos.net.http': http,
      '@ohos.util': { Base64Helper: class {
        encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64'); }
        decodeSync(value) { return new Uint8Array(Buffer.from(value, 'base64')); }
      }, TextDecoder: { create: () => ({ decodeToString: bytes => Buffer.from(bytes).toString('utf8') }) } },
      '@ohos.app.ability.common': {}, '@ohos.multimedia.image': {},
      '@ohos.display': { getDefaultDisplaySync: () => ({ width: 1080 }) }, '@kit.ArkUI': { window: {} },
      '@ohos.app.ability.ConfigurationConstant': {}, '@ohos.promptAction': { showToast: () => {} },
      '@ohos.window': { findWindow: name => {
        state.privacyWindows ??= []; state.privacyWindows.push(name);
        return { setWindowPrivacyMode: async value => {
        state.privacyCalls ??= []; state.privacyCalls.push(value);
        if (state.privacyFailure) throw new Error('系统隐私保护设置失败');
      } }; } },
      '@kit.AbilityKit': {},
      '@ohos.net.connection': {},
      '@ohos.url': require('node:url'),
      '@ohos.web.webview': { WebviewController: class {}, WebCookieManager: { fetchCookieSync: () => '', configCookieSync: () => {}, saveCookieSync: () => {} } },
      '@kit.PerformanceAnalysisKit': { hilog: { debug: () => {}, info: () => {}, warn: () => {}, error: () => {} } },
      '@kit.ArkData': { relationalStore: relational.platform }
    };
    const localRequire = name => name.startsWith('.') ? load(path.resolve(path.dirname(file), name + '.ets')) : native[name] ?? (() => { throw new Error(`未模拟的平台边界：${name}`); })();
    vm.runInThisContext(`(function(exports, require, module, setTimeout, clearTimeout, $r) { ${output}\n})`, { filename: file })(module.exports, localRequire, module, later, cancelLater, value => value);
    return module.exports;
  }
  load(path.join(ets, 'util/Prefs.ets')).setAppContext(context);
  const env = { load: name => load(path.join(ets, name + '.ets')), state, disk, secrets, directory, context,
    close: () => { for (const timer of timers) clearTimeout(timer); timers.clear(); relational.close(); } };
  environments.push(env);
  return env;
}
async function test(name, run) {
  const env = environment();
  try { await run(env); checks++; console.log(`通过：${name}`); }
  catch (error) { failures.push({ name, error }); console.error(`失败：${name}\n${error.stack}`); }
}
function book(models, id, title = '作品', author = '作者') { const a = new models.Album(id, title); a.author = author ? [new models.MetadataTerm(author)] : []; return a; }

try {
  await test('共享列表数据源保留重载、逐项追加和监听器注销语义', async env => {
    const { BasicDataSource } = env.load('common/DataSource');
    const source = new BasicDataSource(), events = [];
    const listener = { onDataReloaded: () => events.push('reload'), onDataAdd: index => events.push(index) };
    source.registerDataChangeListener(listener); source.registerDataChangeListener(listener);
    const items = ['a']; source.setList(items); items.push('outside');
    source.appendItems(['b', 'c']); source.appendItems([]);
    assert.equal(source.totalCount(), 3); assert.equal(source.getData(2), 'c');
    assert.deepEqual(events, ['reload', 1, 2]);
    source.unregisterDataChangeListener(listener); source.setList([]); assert.deepEqual(events, ['reload', 1, 2]);
  });
  await test('拆分后的 CBZ 打包器保留文件内容、目录偏移及失败清理', async env => {
    const { writeZipFile, ZipEntry } = env.load('data/CbzPacker');
    const file = path.join(env.directory, 'pages.cbz'), payload = new Uint8Array([1, 2, 3]);
    await writeZipFile(file, 1, async () => new ZipEntry('001.jpg', payload.buffer));
    const data = fs.readFileSync(file), nameLength = data.readUInt16LE(26), end = data.length - 22;
    assert.equal(data.readUInt32LE(0), 0x04034b50);
    assert.equal(data.subarray(30, 30 + nameLength).toString(), '001.jpg');
    assert.deepEqual([...data.subarray(30 + nameLength, 33 + nameLength)], [...payload]);
    assert.equal(data.readUInt32LE(end), 0x06054b50); assert.equal(data.readUInt16LE(end + 10), 1);
    assert.equal(data.readUInt32LE(data.readUInt32LE(end + 16)), 0x02014b50);
    await assert.rejects(writeZipFile(file, 1, async () => { throw new Error('页面读取失败'); }), /页面读取失败/);
    assert.equal(fs.existsSync(file), false);
  });
  await test('来源主键隔离与无损解包', async env => {
    const s = env.load('data/Sources');
    const id = '同名/作品~1'; assert.notEqual(s.sourceKey('jm', id), s.sourceKey('local', id));
    assert.equal(s.nativeId(s.sourceKey('jm', id)), id); assert.throws(() => s.sourceId('123'));
    const a = new s.SourceEntry('a', '甲', 'suwayomi'); const b = new s.SourceEntry('b', '乙', 'suwayomi');
    await Promise.all([s.sourceStore.save(a), s.sourceStore.save(b)]);
    assert.ok((await s.sourceStore.list()).some(x => x.id === 'a')); assert.ok((await s.sourceStore.list()).some(x => x.id === 'b'));
    a.enabled = false; await s.sourceStore.save(a); await assert.rejects(s.sourceStore.get('a'), /停用/);
  });
  await test('作品匹配拒绝作者缺失、语言和版本冲突', async env => {
    const m = env.load('models/Models'), match = env.load('data/Matching');
    const a = book(m, 'jm~1', '作品：甲'), b = book(m, 's~1', '作品 甲');
    assert.ok(match.highConfidence(a, b)); b.author = []; assert.equal(match.highConfidence(a, b), false);
    b.author = [new m.MetadataTerm('作者')]; a.language = 'zh'; b.language = 'ja'; assert.equal(match.highConfidence(a, b), false);
    b.language = 'zh'; b.name = '作品甲 全彩'; assert.equal(match.highConfidence(a, b), false);
  });
  await test('章节匹配拒绝卷章混用、重复编号和排列序号猜测', async env => {
    const m = env.load('models/Models'), match = env.load('data/Matching');
    const a = new m.Chapter('a', '第 2 话', '1'), b = new m.Chapter('b', 'Chapter 2', '9');
    assert.equal(match.matchingChapter(a, [b]).id, 'b'); assert.equal(match.matchingChapter(a, [b, b]), null);
    assert.equal(match.matchingChapter(a, [new m.Chapter('c', '第2卷', '1')]), null);
    assert.equal(match.matchingChapter(new m.Chapter('a', '起点', '1'), [new m.Chapter('b', '开始', '1')]), null);
    assert.equal(match.mappedPage(49, 100, 51), 25); assert.equal(match.mappedPage(200, 100, 51), 50);
  });
  await test('双页封面偏移和宽图的页码映射', async env => {
    const layout = env.load('data/ReaderLayout');
    for (let count = 1; count <= 20; count++) {
      const pages = Array.from({ length: count }, (_, i) => `${i}`);
      for (const offset of [true, false]) {
        const wide = new Set(pages.filter((_, i) => i % 4 === 2));
        const spreads = layout.makeSpreads(pages, wide, offset);
        assert.deepEqual(spreads.flat(), pages);
        for (const spread of spreads) if (spread.some(p => wide.has(p))) assert.equal(spread.length, 1);
        for (let page = 0; page < count; page++) {
          const index = layout.spreadForPage(spreads, page); assert.ok(spreads[index].includes(pages[page]));
          assert.equal(pages[layout.lastPageInSpread(spreads, index)], spreads[index].at(-1));
        }
      }
    }
  });
  await test('书架关联、取消关联、分类与写入失败回滚', async env => {
    const m = env.load('models/Models'), { library } = env.load('data/Library');
    await Promise.all([library.add(book(m, 'jm~1')), library.add(book(m, 's~1'))]);
    assert.equal((await library.list()).length, 1); assert.equal((await library.list())[0].albums.length, 2);
    await library.detach('s~1'); assert.equal((await library.list()).length, 2);
    await library.associate('jm~1', book(m, 's~1')); assert.equal((await library.list()).length, 1);
    const work = (await library.list())[0]; env.state.failFlush = true;
    await assert.rejects(library.categorize([work.id], '失败分类'), /磁盘/);
    assert.deepEqual((await library.list())[0].categories, []);
    await library.categorize([work.id], '收藏'); assert.deepEqual((await library.list())[0].categories, ['收藏']);
  });
  await test('更新以首次快照为基线，重复检查不重复计数', async env => {
    const m = env.load('models/Models'), { library } = env.load('data/Library');
    const album = book(m, 'jm~1'); album.episodes = [new m.Chapter('jm~c1', '第1话')]; await library.add(album);
    assert.equal(await library.updateSnapshot(album), 0); album.episodes.push(new m.Chapter('jm~c2', '第2话'));
    assert.equal(await library.updateSnapshot(album), 1); assert.equal(await library.updateSnapshot(album), 0);
  });
  await test('来源进度分别保存，落盘失败不改变既有进度', async env => {
    const m = env.load('models/Models'), { readProgressStore } = env.load('data/Stores');
    await Promise.all([readProgressStore.save(new m.ReadingProgress('jm~1', 'jm~2', 0, 4, 20)),
      readProgressStore.save(new m.ReadingProgress('s~1', 's~2', 0, 8, 20))]);
    env.state.failFlush = true; await assert.rejects(readProgressStore.save(new m.ReadingProgress('jm~1', 'jm~2', 0, 10, 20)));
    assert.equal((await readProgressStore.get('jm~1')).page, 4); assert.equal((await readProgressStore.get('s~1')).page, 8);
  });
  await test('Suwayomi 稳定版数据契约和认证凭据隔离', async env => {
    const { suwayomi } = env.load('data/Suwayomi');
    env.state.handler = async request => {
      const query = request.body.query;
      if (query.includes('query { sources')) return { sources: { nodes: [{ id: '9007199254740993123', displayName: '测试书源', lang: 'zh' }] } };
      if (query.includes('fetchSourceManga')) return { fetchSourceManga: { mangas: [{ id: 5, title: '作品', thumbnailUrl: '/cover.jpg' }], hasNextPage: false } };
      if (query.includes('fetchMangaAndChapters')) return { fetchMangaAndChapters: { manga: { id: 5, title: '作品', author: '作者', genre: ['冒险'], thumbnailUrl: '/cover.jpg' }, chapters: [
        { id: 8, name: '第2话', chapterNumber: 2, sourceOrder: 0 }, { id: 9, name: '第1话', chapterNumber: 1, sourceOrder: 1 }] } };
      if (query.includes('fetchChapterPages')) return { fetchChapterPages: { pages: ['/api/v1/manga/5/chapter/0/page/0'] } };
      throw new Error(query);
    };
    const [source] = await suwayomi.connect('http://server:4567/', '服务', 'basic', '账号', '密码', 'server');
    assert.equal(source.remoteId, '9007199254740993123'); assert.ok(env.state.calls[0].header.Authorization.startsWith('Basic '));
    const list = await suwayomi.search(source, '作品', 1); assert.equal(list.list[0].coverUrl, 'http://server:4567/cover.jpg');
    assert.equal(list.hasNext, false);
    env.state.handler = async () => ({ fetchSourceManga: { mangas: [], hasNextPage: true } });
    assert.equal((await suwayomi.search(source, '作品', 2)).hasNext, true);
    env.state.handler = async request => {
      if (request.body.query.includes('fetchMangaAndChapters')) return { fetchMangaAndChapters: { manga: { id: 5, title: '作品', author: '作者', genre: ['冒险'] }, chapters: [{ id: 9, name: '第1话', chapterNumber: 1, sourceOrder: 1 }] } };
      return { fetchChapterPages: { pages: ['/api/v1/manga/5/chapter/0/page/0'] } };
    };
    const album = await suwayomi.album(source, '5');
    assert.deepEqual(album.tags.map(term => ({ value: term.value, label: term.label })), [{ value: '冒险', label: '冒险' }]);
    assert.equal(album.episodes[0].number, '1');
    assert.equal((await suwayomi.pages(source, '8'))[0], 'http://server:4567/api/v1/manga/5/chapter/0/page/0');
    assert.ok(!JSON.stringify([...env.disk]).includes('密码')); assert.equal(env.secrets.size, 1);
    const secretAlias = `manyu.source.${source.instanceId}`;
    const before = JSON.stringify([...env.secrets.get(secretAlias)]);
    env.state.handler = async () => { throw new Error('服务不可用'); };
    await assert.rejects(suwayomi.connect('http://server:4567', '服务', 'basic', '账号', '新密码', 'server'));
    assert.equal(JSON.stringify([...env.secrets.get(secretAlias)]), before);
  });
  await test('搜索响应返回前停用书源，旧响应被拒绝', async env => {
    const s = env.load('data/Sources'), { sourceApi } = env.load('data/SourceApi');
    const source = new s.SourceEntry('server_1', '服务', 'suwayomi'); source.endpoint = 'http://server'; source.remoteId = '1';
    await s.sourceStore.save(source);
    let finish; env.state.handler = () => new Promise(resolve => { finish = resolve; });
    const pending = sourceApi.searchSource(source, '作品', 1);
    while (!finish) await new Promise(resolve => setImmediate(resolve));
    source.enabled = false; await s.sourceStore.save(source); finish({ fetchSourceManga: { mangas: [], hasNextPage: false } });
    await assert.rejects(pending, /停用/);
  });
  await test('换源验证目标页、比例进度、歧义和取消', async env => {
    const m = env.load('models/Models'), s = env.load('data/Sources'), { library } = env.load('data/Library');
    const { sourceApi } = env.load('data/SourceApi'), switching = env.load('data/SourceSwitch');
    const a = book(m, 'jm~1'); a.episodes = [new m.Chapter('jm~c', '第1话')];
    const b = book(m, 's~1'); b.episodes = [new m.Chapter('s~c', '第1话')];
    await s.sourceStore.save(new s.SourceEntry('s', '服务', 'suwayomi')); await library.add(a); await library.associate(a.id, b);
    let reads = 0; sourceApi.album = async () => b; sourceApi.chapterImages = async () => ['1', '2', '3', '4', '5'];
    sourceApi.fetchPage = async () => { reads++; return new ArrayBuffer(2); };
    const attempted = new Set([a.id]); const result = await switching.fallbackSource(a, a.episodes[0], 9, 10, attempted, () => true);
    assert.equal(result.page, 4); assert.ok(result.proportional); assert.equal(reads, 1); assert.ok(attempted.has(b.id));
    await assert.rejects(switching.prepareSourceSwitch({ ...b, episodes: [b.episodes[0], b.episodes[0]] }, a.episodes[0], 0, 10), /唯一/);
    await assert.rejects(switching.fallbackSource(a, a.episodes[0], 0, 10, new Set(), () => false), /取消/);
  });
  await test('本地压缩包自然排序、取消和失败清理', async env => {
    const { localSource } = env.load('data/LocalSource'); const archive = path.join(env.directory, '漫画.cbz'); fs.writeFileSync(archive, 'fixture');
    env.state.selected = [archive];
    env.state.unzip = async (_input, output) => {
      for (const name of ['10.jpg', '2.jpg', '1.jpg']) fs.writeFileSync(path.join(output, name), 'image');
      fs.writeFileSync(path.join(output, 'ComicInfo.xml'), '<ComicInfo><Title>本地作品</Title><Writer>作者</Writer></ComicInfo>');
    };
    const album = await localSource.importFiles(''); assert.equal(album.name, '本地作品');
    assert.deepEqual((await localSource.pages(album.episodes[0].id)).map(p => path.basename(p)), ['1.jpg', '2.jpg', '10.jpg']);
    env.state.selected = []; assert.equal(await localSource.importFiles(''), null);
    env.state.selected = [archive]; env.state.unzip = async () => { throw new Error('压缩包损坏'); };
    await new Promise(resolve => setTimeout(resolve, 2)); await assert.rejects(localSource.importFiles(''), /损坏/);
    assert.equal((await localSource.search('')).list.length, 1);
  });
  await test('离线清单完整发布，取消时回滚且可在停用来源后阅读', async env => {
    const m = env.load('models/Models'), { offlineStore } = env.load('data/OfflineStore');
    const album = book(m, 'jm~1'), page = new m.ChapterPage('jm~c', '1.jpg', 220980);
    const file = path.join(env.directory, 'page.bin'); fs.writeFileSync(file, 'offline-bytes');
    let checks = 0;
    await assert.rejects(installOfflineFixture(env, album, [page], [file], () => { if (++checks === 3) throw new Error('已取消'); }), /取消/);
    assert.equal(await offlineStore.album(album.id), null);
    await installOfflineFixture(env, album, [page], [file]);
    const { sourceStore } = env.load('data/Sources'), { sourceApi } = env.load('data/SourceApi');
    const source = await sourceStore.get('jm'); source.enabled = false; await sourceStore.save(source);
    assert.equal((await sourceApi.album(album.id)).name, '作品'); assert.ok((await sourceApi.fetchPage(page.photoId, page.filename)).byteLength > 0);
  });
  await test('每本漫画阅读偏好、书签和统计顺序保存', async env => {
    const { readerPreferences, ReaderOptions } = env.load('data/ReaderOptions'), m = env.load('models/Models');
    const options = new ReaderOptions(); options.mode = 'pagedVertical'; options.coverOffset = false;
    await readerPreferences.save('jm~1', options); assert.equal((await readerPreferences.load('jm~1')).mode, 'pagedVertical');
    const mark = new m.ReadingProgress('jm~1', 'jm~c', 0, 2, 10); await readerPreferences.toggleBookmark(mark);
    assert.equal((await readerPreferences.bookmarks('jm~1')).length, 1); await readerPreferences.toggleBookmark(mark);
    assert.equal((await readerPreferences.bookmarks('jm~1')).length, 0);
    const { readingActivity } = env.load('data/ReadingActivity');
    await Promise.all([readingActivity.record('w1', 'c~1', 1000), readingActivity.record('w1', 'c~1', 2000)]);
    const stats = await readingActivity.stats(); assert.equal(stats.milliseconds, 3000); assert.equal(stats.pages.length, 1);
  });
  await test('下载缺页时失败，不发布离线漫画或导出文件', async env => {
    const m = env.load('models/Models'), { sourceApi } = env.load('data/SourceApi');
    const { DownloadManager } = env.load('data/DownloadManager');
    const album = book(m, 'jm~1'); album.episodes = [new m.Chapter('jm~c', '第1话')];
    sourceApi.album = async () => album; sourceApi.chapterImages = async () => ['1.jpg']; sourceApi.scrambleId = async () => 0;
    sourceApi.fetchPage = async () => { throw new Error('页面不存在'); };
    const manager = new DownloadManager(); await manager.enqueue(album);
    const task = await finishTask(manager, 'failed');
    assert.equal(task.state, 'failed'); assert.match(task.error, /1 页下载失败.*页面不存在/); assert.equal(task.savedTo, '');
    assert.equal(await env.load('data/OfflineStore').offlineStore.album(album.id), null);
    assert.equal(fs.existsSync(path.join(env.context.cacheDir, `dl_${task.id}`)), false);
  });
  await test('删除下载等待并发请求结束，迟到页面不再写入', async env => {
    const m = env.load('models/Models'), { sourceApi } = env.load('data/SourceApi');
    const { DownloadManager } = env.load('data/DownloadManager');
    const album = book(m, 'jm~1'); album.episodes = [new m.Chapter('jm~c', '第1话')];
    sourceApi.album = async () => album; sourceApi.chapterImages = async () => ['1.jpg', '2.jpg', '3.jpg', '4.jpg']; sourceApi.scrambleId = async () => 0;
    const replies = []; sourceApi.fetchPage = () => new Promise(resolve => replies.push(resolve));
    const manager = new DownloadManager(); await manager.enqueue(album);
    const task = manager.tasks[0];
    await until(() => replies.length >= 3, '并发下载开始');
    let removed = false;
    const removing = manager.removeTask(task.id, true).then(() => { removed = true; });
    await new Promise(resolve => setImmediate(resolve)); assert.equal(removed, false);
    for (const reply of replies) reply(new ArrayBuffer(32)); await removing;
    assert.equal(fs.existsSync(path.join(env.context.cacheDir, `dl_${task.id}`)), false); assert.equal(manager.tasks.length, 0);
    assert.equal(await env.load('data/OfflineStore').offlineStore.album(album.id), null);
  });
  await test('备份默认值有效、取消不写入、失败整批回滚', async env => {
    const backup = env.load('data/Backup');
    const { library } = env.load('data/Library');
    const models = env.load('models/Models');
    const file = path.join(env.directory, 'backup.json');
    env.state.saved = [file];
    assert.ok(await backup.exportBackup());
    const document = JSON.parse(fs.readFileSync(file, 'utf8'));
    assert.equal(document.magic, 'manyu-backup');
    assert.equal(document.version, 3);
    assert.equal(document.tables.source_entry.length, 3);
    assert.deepEqual(document.tables.library_work, []);
    env.state.selected = [];
    assert.equal(await backup.importBackup(), false);
    await library.add(book(models, 'jm~1'));
    env.state.selected = [file];
    env.state.failFlush = true;
    await assert.rejects(backup.importBackup(), /磁盘/);
    assert.equal((await library.list()).length, 1);
    assert.ok(await backup.importBackup());
    assert.equal((await library.list()).length, 0);
    await library.add(book(models, 'jm~2'));
    document.version = 99;
    fs.writeFileSync(file, JSON.stringify(document));
    await assert.rejects(backup.importBackup(), /有效/);
    assert.equal((await library.list()).length, 1);
  });
  await test('E-Hentai 复合键解析与默认注册重启语义', async env => {
    const eh = env.load('data/EhSource');
    const fromUrl = eh.ehSource.parseIdentity('https://e-hentai.org/g/1234567/a1b2c3d4e5/');
    assert.equal(fromUrl.gid, 1234567); assert.equal(fromUrl.token, 'a1b2c3d4e5');
    assert.equal(eh.ehSource.fullKey(fromUrl), 'eh~1234567_a1b2c3d4e5');
    assert.equal(eh.ehSource.keyFromInput('123456/abcdef1234'), 'eh~123456_abcdef1234');
    assert.equal(eh.ehSource.keyFromInput(eh.ehSource.fullKey(fromUrl)), 'eh~1234567_a1b2c3d4e5');
    assert.throws(() => eh.ehSource.parseIdentity('abc'), /无效/);
    assert.throws(() => eh.ehSource.parseIdentity('123456/short'), /无效/);
    assert.equal(eh.ehSource.isEhImageUrl('https://ehgt.org/x/y.webp'), true);
    assert.equal(eh.ehSource.isEhImageUrl('https://e-hentai.org/t/abc.jpg'), true);
    assert.equal(eh.ehSource.isEhImageUrl('https://foo.hath.network/1.jpg'), false);
    const secondPage = await eh.ehSource.comments('eh~1234567_a1b2c3d4e5', 2);
    assert.equal(secondPage.list.length, 0);
    assert.equal(secondPage.total, 0);
    const fresh = await env.load('data/Sources').sourceStore.list();
    assert.ok(fresh.some(x => x.id === 'eh' && x.kind === 'eh' && x.enabled));
    const sources = env.load('data/Sources').sourceStore;
    await sources.remove('eh'); sources.invalidate();
    assert.equal((await sources.list()).some(entry => entry.id === 'eh'), false);
  });
  await regressionTests(test);
  await sourceContractTests(test);
  await searchTests(test);
  await interfaceTests(test);
  console.log(`共 ${checks} 项通过，${failures.length} 项失败（真实内存 SQLite，其余平台边界使用本地替身）。`);
  if (failures.length) process.exitCode = 1;
} finally {
  for (const env of environments) env.close();
  assert.ok(path.resolve(fixture).startsWith(path.resolve(os.tmpdir()) + path.sep + 'manyu-core-'));
  fs.rmSync(fixture, { recursive: true, force: true });
}
