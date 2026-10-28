import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const turn = () => new Promise(resolve => setImmediate(resolve));
export async function until(predicate, description) {
  const deadline = Date.now() + 8000;
  while (!predicate()) {
    assert.ok(Date.now() < deadline, `等待超时：${description}`);
    await new Promise(resolve => setTimeout(resolve, 2));
  }
  await turn();
}
function albumFixture(env, id = 'jm~101') {
  const models = env.load('models/Models');
  const album = new models.Album(id, '完整作品');
  album.author = [new models.MetadataTerm('作者')];
  album.episodes = [new models.Chapter('jm~201', '第一话')];
  return album;
}
function downloadFixture(env, filenames = ['001.jpg', '002.png']) {
  const album = albumFixture(env);
  const { sourceApi } = env.load('data/SourceApi');
  sourceApi.album = async () => album;
  sourceApi.albumCoverUrl = () => 'https://cover.invalid/101.jpg';
  sourceApi.chapterImages = async () => filenames;
  sourceApi.scrambleId = async () => 220980;
  const fetched = [];
  sourceApi.fetchPage = async (_chapter, filename) => {
    fetched.push(filename);
    return Uint8Array.from({ length: 2048 }, (_, i) => i % 251).buffer;
  };
  const { DownloadManager } = env.load('data/DownloadManager');
  return { album, sourceApi, fetched, manager: new DownloadManager() };
}
export async function finishTask(manager, expected = 'done') {
  await until(() => manager.tasks.length > 0 && ['done', 'failed', 'canceled'].includes(manager.tasks[0].state), '下载任务结束');
  const task = manager.tasks[0];
  assert.equal(task.state, expected, task.error);
  await manager.withSuspendedWrites(async () => {});
  return task;
}
function zipEntries(file) {
  const bytes = fs.readFileSync(file), entries = [];
  let offset = 0;
  while (bytes.readUInt32LE(offset) === 0x04034b50) {
    const size = bytes.readUInt32LE(offset + 18);
    const length = bytes.readUInt16LE(offset + 26), extra = bytes.readUInt16LE(offset + 28);
    const start = offset + 30 + length + extra;
    entries.push({ name: bytes.subarray(offset + 30, offset + 30 + length).toString('utf8'), data: bytes.subarray(start, start + size) });
    offset = start + size;
  }
  assert.equal(entries.length, bytes.readUInt16LE(bytes.length - 12));
  return entries;
}
async function rows(env, sql, args = []) {
  const result = await env.load('data/db/AppDatabase').dbQuery(sql, args);
  const values = [];
  try {
    while (result.goToNextRow()) values.push(Object.fromEntries(result.columnNames.map((name, i) => [name, result.getString(i)])));
  } finally { result.close(); }
  return values;
}
export async function installOfflineFixture(env, album, pages, files, validate = () => {}) {
  const { TaskRow } = env.load('data/db/ContentDao');
  const task = new TaskRow();
  env.state.fixtureTaskId = (env.state.fixtureTaskId ?? 90000) + 1;
  task.id = env.state.fixtureTaskId;
  task.albumId = album.id; task.title = album.name;
  const archive = path.join(env.directory, `install-${task.id}.cbz`);
  const { writeZipFile, ZipEntry } = env.load('data/CbzPacker');
  await writeZipFile(archive, files.length, async index => new ZipEntry(`${index + 1}.jpg`, new Uint8Array(fs.readFileSync(files[index])).buffer));
  return env.load('data/OfflineStore').offlineStore.install(album, pages, files, archive, task, validate);
}
async function seedMany(env, count) {
  const db = env.load('data/db/AppDatabase');
  const models = env.load('models/Models');
  const store = await db.openDatabase();
  await store.executeSql('WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < ?) INSERT INTO favorite SELECT \'jm~\' || i, \'作品\' || i, \'作者\', \'\', \'jm\', i, i FROM n', [count - 1]);
  await store.executeSql('WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < ?) INSERT INTO library_work SELECT \'w\' || i, \'作品\' || i, \'作者\', \'\', \'jm~\' || i, 0, i, 0, 0, i, i FROM n', [count - 1]);
  const template = albumFixture(env, 'jm~seed'); template.tags = [new models.MetadataTerm('测试', '测试', '题材')];
  await store.executeSql('INSERT INTO library_album SELECT active_key, id, \'jm\', 0, json_set(?, \'$.id\', active_key, \'$.name\', title, \'$.episodes[0].id\', \'jm~chapter\' || position), position FROM library_work', [JSON.stringify(template)]);
  await store.executeSql('INSERT INTO album_chapter SELECT active_key, \'jm~chapter\' || position, \'第一话\', \'\', 0 FROM library_work');
  await store.executeSql('INSERT INTO album_tag (album_id, namespace, value, label, position) SELECT active_key, \'题材\', \'测试\', \'测试\', 0 FROM library_work');
  await store.executeSql('WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < ?) INSERT INTO history SELECT \'jm~\' || i, \'作品\' || i, \'作者\', \'\', \'jm\', i, i FROM n', [count - 1]);
  await store.executeSql('WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < ?) INSERT INTO reading_progress SELECT \'jm~\' || i, \'jm~chapter\' || i, 0, 2, 10, i, \'作品\' || i, \'作者\', \'\', \'jm\' FROM n', [count - 1]);
}
function boundedReads(env, pageSize, label) {
  const reads = env.state.sql.filter(item => item.kind === 'read' && /\b(?:library_\w+|album_\w+|favorite|history|reading_progress)\b/.test(item.sql));
  const total = reads.reduce((n, item) => n + item.rows, 0);
  assert.ok(total <= pageSize * 6, `${label} 读取 ${total} 行，应与页大小 ${pageSize} 成比例`);
  console.log(`  ${label}：${reads.length} 次 SQL，读取 ${total} 行`);
}

export async function regressionTests(test) {
  await test('SQLite 主键、非空、唯一约束与真实事务回滚', async env => {
    const db = env.load('data/db/AppDatabase');
    const store = await db.openDatabase();
    await store.executeSql('CREATE TABLE regression_constraint (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE)');
    await db.dbTransaction(async tx => { assert.equal(await tx.execute('INSERT INTO regression_constraint (id, name) VALUES (?, ?)', [1, '原始']), 1); });
    for (const args of [[1, '重复主键'], [2, '原始'], [2, null]]) {
      await assert.rejects(db.dbTransaction(async tx => {
        await tx.execute('INSERT INTO regression_constraint (id, name) VALUES (?, ?)', [99, '应回滚']);
        await tx.execute('INSERT INTO regression_constraint (id, name) VALUES (?, ?)', args);
      }), /constraint|UNIQUE|NOT NULL/i);
      assert.deepEqual(await rows(env, 'SELECT * FROM regression_constraint'), [{ id: '1', name: '原始' }]);
    }
  });
  await test('开库失败释放共享 Promise，后续调用可重试且使用新库', async env => {
    env.state.failOpen = true;
    const db = env.load('data/db/AppDatabase');
    const first = db.openDatabase(), concurrent = db.openDatabase();
    const failed = await Promise.allSettled([first, concurrent]);
    assert.ok(failed.every(result => result.status === 'rejected'));
    const store = await db.openDatabase();
    assert.equal(store.version, 1);
    assert.deepEqual(env.state.opens, ['manyu_business_v2.db', 'manyu_business_v2.db']);
  });
  await test('首次完整下载发布全部页、可读离线书目和完整 CBZ', async env => {
    const { album, fetched, manager } = downloadFixture(env);
    await manager.enqueue(album);
    const task = await finishTask(manager);
    assert.equal(task.done, 2); assert.equal(task.total, 2); assert.equal(task.failedPages, 0);
    assert.deepEqual(fetched.sort(), ['001.jpg', '002.png']);
    const offline = env.load('data/OfflineStore').offlineStore;
    assert.equal((await offline.album(album.id)).name, album.name);
    assert.deepEqual(await offline.pages('jm~201'), ['001.jpg', '002.png']);
    assert.equal((await offline.bytes('jm~201', '001.jpg')).byteLength, 2048);
    assert.deepEqual(zipEntries(task.savedTo).map(entry => entry.name), ['00001.jpg', '00002.webp']);
    assert.equal(env.state.released, 2);
  });
  await test('下载失败已完成页可恢复，重建管理器后续传只请求缺页', async env => {
    const { album, sourceApi, manager } = downloadFixture(env);
    sourceApi.fetchPage = async (_chapter, filename) => {
      if (filename === '002.png') throw new Error('页面临时不可用');
      return new Uint8Array(2048).fill(19).buffer;
    };
    await manager.enqueue(album);
    const failed = await finishTask(manager, 'failed');
    assert.equal(await env.load('data/OfflineStore').offlineStore.album(album.id), null);
    const fetched = [];
    sourceApi.fetchPage = async (_chapter, filename) => { fetched.push(filename); return new Uint8Array(2048).fill(23).buffer; };
    const { DownloadManager } = env.load('data/DownloadManager');
    const resumed = new DownloadManager(); await resumed.init();
    const recovered = resumed.tasks.find(task => task.id === failed.id);
    assert.ok(recovered, '失败任务必须落盘');
    await resumed.retry(recovered.id);
    await finishTask(resumed);
    assert.deepEqual(fetched, ['002.png']);
    assert.deepEqual(await env.load('data/OfflineStore').offlineStore.pages('jm~201'), ['001.jpg', '002.png']);
  });
  await test('重复下载不重复任务，删除任务文件后仍能读取离线内容', async env => {
    const { album, manager } = downloadFixture(env);
    await manager.enqueue(album); const task = await finishTask(manager);
    await assert.rejects(manager.enqueue(album), /已有下载/);
    assert.equal(manager.tasks.length, 1);
    await manager.removeTask(task.id, true);
    assert.equal(fs.existsSync(task.savedTo), false);
    assert.equal(manager.tasks.length, 0);
    const offline = env.load('data/OfflineStore').offlineStore;
    assert.equal((await offline.album(album.id)).id, album.id);
    assert.equal((await offline.bytes('jm~201', '002.png')).byteLength, 2048);
    await manager.enqueue(album); await finishTask(manager);
    assert.equal((await rows(env, 'SELECT * FROM offline_page WHERE album_id = ?', [album.id])).length, 2);
  });
  await test('离线重装提交失败保留旧书目、旧页面与字节', async env => {
    const album = albumFixture(env), models = env.load('models/Models');
    const page = new models.ChapterPage('jm~201', 'same.jpg', 220980);
    const old = path.join(env.directory, 'old.bin'), newer = path.join(env.directory, 'new.bin');
    fs.writeFileSync(old, 'old-content'); fs.writeFileSync(newer, 'new-content');
    const offline = env.load('data/OfflineStore').offlineStore;
    await installOfflineFixture(env, album, [page], [old]);
    env.state.failFlush = true;
    await assert.rejects(installOfflineFixture(env, album, [page], [newer]), /磁盘/);
    assert.equal((await offline.album(album.id)).id, album.id);
    assert.equal(Buffer.from(await offline.bytes(page.photoId, page.filename)).toString(), 'old-content');
    assert.equal((await rows(env, 'SELECT * FROM offline_page WHERE album_id = ?', [album.id])).length, 1);
  });
  await test('JM 还原回退键随页面进入 CBZ 转换，危险源文件名不进入归档路径', async env => {
    const { album, manager } = downloadFixture(env, ['../escape.jpg', '..\\escape.webp', '/absolute.png']);
    await manager.enqueue(album); const task = await finishTask(manager);
    assert.ok(env.state.decoded.every(page => page.scrambleId === 220980));
    assert.deepEqual(env.state.packed.map(item => item.format), ['image/jpeg', 'image/webp', 'image/webp']);
    const entries = zipEntries(task.savedTo);
    assert.deepEqual(entries.map(entry => entry.name), ['00001.jpg', '00002.webp', '00003.webp']);
    for (const entry of entries) assert.equal(entry.data.length, 2048);
  });
  await test('归档转换失败不发布离线书目或半成品文件', async env => {
    const { album, manager } = downloadFixture(env);
    env.state.packFailure = true;
    await manager.enqueue(album); const task = await finishTask(manager, 'failed');
    assert.match(task.error, /编码失败/); assert.equal(task.savedTo, '');
    assert.equal(await env.load('data/OfflineStore').offlineStore.album(album.id), null);
    assert.equal(fs.existsSync(path.join(env.context.cacheDir, `cbz_${task.id}.cbz`)), false);
    assert.ok(env.state.released > 0);
  });
  await test('离线回退导出重新还原和编码全部页，丢失文件时拒绝半本归档', async env => {
    const { album, manager } = downloadFixture(env);
    await manager.enqueue(album); const task = await finishTask(manager);
    fs.unlinkSync(task.savedTo);
    env.state.decoded.length = 0; env.state.packed.length = 0;
    const { stageCbz, discardStaged } = env.load('data/BatchExport');
    const staged = await stageCbz(album.id, task.savedTo);
    assert.equal(staged.temporary, true);
    assert.deepEqual(zipEntries(staged.path).map(entry => entry.name), ['00001.jpg', '00002.webp']);
    assert.equal(env.state.decoded.length, 2);
    assert.ok(env.state.decoded.every(page => page.scrambleId === 220980));
    assert.deepEqual(env.state.packed.map(item => item.format), ['image/jpeg', 'image/webp']);
    discardStaged(staged); assert.equal(fs.existsSync(staged.path), false);
    const [page] = await rows(env, 'SELECT relative_path FROM offline_page WHERE album_id = ? ORDER BY page_order ASC', [album.id]);
    fs.unlinkSync(path.join(env.context.filesDir, page.relative_path));
    await assert.rejects(stageCbz(album.id, ''), /缺失|损坏/);
  });
  await test('CBZ 写入拒绝路径穿越、绝对路径、控制字符和重复文件名', async env => {
    const { writeZipFile, ZipEntry } = env.load('data/CbzPacker');
    const file = path.join(env.directory, 'unsafe.cbz');
    for (const name of ['../a.jpg', '/a.jpg', 'C:\\a.jpg', 'a\\b.jpg', 'a\u0000.jpg']) {
      await assert.rejects(writeZipFile(file, 1, async () => new ZipEntry(name, new ArrayBuffer(3))), /文件名|路径/);
      assert.equal(fs.existsSync(file), false);
    }
    await assert.rejects(writeZipFile(file, 2, async () => new ZipEntry('same.jpg', new ArrayBuffer(3))), /重复|文件名/);
    assert.equal(fs.existsSync(file), false);
  });
  await test('异步分块复制与备份支持短读短写，文件指针顺序推进', async env => {
    env.state.readChunkLimit = 109; env.state.writeChunkLimit = 67;
    const input = path.join(env.directory, 'source.bin'), output = path.join(env.directory, 'copied.bin');
    const payload = Buffer.from(Array.from({ length: 4097 }, (_, index) => index % 251));
    fs.writeFileSync(input, payload);
    await env.load('data/CbzPacker').copyBytesAsync(input, output);
    assert.deepEqual(fs.readFileSync(output), payload);
    const backup = env.load('data/Backup'), file = path.join(env.directory, 'short-io.json');
    env.state.saved = [file]; assert.equal(await backup.exportBackup(), true);
    assert.equal(JSON.parse(fs.readFileSync(file, 'utf8')).version, 3);
    env.state.selected = [file]; assert.equal(await backup.importBackup(), true);
    assert.equal(env.state.openFiles.size, 0);
  });
  await test('备份 v3 在同一事务恢复业务、源配置和 EH 站点，任一步失败全体回滚', async env => {
    const backup = env.load('data/Backup'), { library } = env.load('data/Library');
    const { sourceStore, SourceEntry, SourceInstance, saveSourceSecret, readSourceSecret } = env.load('data/Sources');
    const { EhSettings } = env.load('data/eh/EhSettings');
    const original = albumFixture(env, 'jm~original');
    await library.add(original);
    const source = new SourceEntry('backup-source', '备份源', 'suwayomi');
    source.endpoint = 'https://source.invalid'; source.remoteId = '42';
    const instance = new SourceInstance(); instance.id = source.instanceId; instance.endpoint = source.endpoint; instance.name = '备份服务';
    await sourceStore.syncSuwayomi(instance, [source]); await EhSettings.setSite('ex');
    await saveSourceSecret('backup-source', 'credential-remains-local');
    const file = path.join(env.directory, 'atomic.json');
    env.state.saved = [file]; assert.equal(await backup.exportBackup(), true);
    const document = JSON.parse(fs.readFileSync(file, 'utf8'));
    assert.equal(document.version, 3);
    assert.equal(document.sources, undefined); assert.equal(document.ehSite, undefined);
    assert.ok(document.tables.source_entry.some(row => row.id === 'backup-source'));
    assert.ok(document.tables.source_instance.some(row => row.id === instance.id));
    assert.ok(document.tables.source_setting.some(row => row.source_id === 'eh' && row.key === 'site' && row.value === 'ex'));
    assert.ok(!JSON.stringify(document).includes('credential-remains-local'));
    const models = env.load('models/Models');
    const additional = albumFixture(env, 'jm~additional'); additional.name = '后来作品';
    additional.author = [new models.MetadataTerm('另一作者')];
    await library.add(additional);
    source.name = '当前源'; await sourceStore.save(source); await EhSettings.setSite('e');
    env.state.selected = [file];
    env.state.failSql = item => /^INSERT INTO source_entry\b/.test(item.sql);
    await assert.rejects(backup.importBackup(), /SQL/);
    env.state.failSql = undefined;
    assert.equal((await library.list()).length, 2);
    assert.equal((await sourceStore.get(source.id)).name, '当前源'); assert.equal(EhSettings.site(), 'e');
    assert.equal((await rows(env, 'SELECT name FROM source_entry WHERE id = ?', [source.id]))[0].name, '当前源');
    assert.equal((await rows(env, 'SELECT value FROM source_setting WHERE source_id = ? AND key = ?', ['eh', 'site']))[0].value, 'e');
    assert.equal(await backup.importBackup(), true);
    assert.equal((await library.list()).length, 1);
    assert.equal((await sourceStore.get(source.id)).name, '备份源'); assert.equal(EhSettings.site(), 'ex');
    assert.equal(await readSourceSecret('backup-source'), 'credential-remains-local');
  });
  await test('恢复维护排空旧写入、拒绝新写入，提交后立即刷新缓存并恢复写入', async env => {
    const db = env.load('data/db/AppDatabase');
    await db.openDatabase();
    let finishOld, finishRestore, maintenanceStarted = false, invalidated = false;
    const oldWrite = db.dbTransaction(async tx => {
      await new Promise(resolve => { finishOld = resolve; });
      await tx.execute('INSERT INTO custom_category (name, position, updated_at) VALUES (?, ?, ?)', ['旧写入', 0, 0]);
    });
    await until(() => finishOld, '旧写入开始');
    const restore = db.withDatabaseMaintenance(async tx => {
      maintenanceStarted = true;
      await new Promise(resolve => { finishRestore = resolve; });
      await tx.execute('DELETE FROM custom_category');
      await tx.execute('INSERT INTO custom_category (name, position, updated_at) VALUES (?, ?, ?)', ['恢复结果', 0, 0]);
    }, () => { invalidated = true; });
    await assert.rejects(db.dbTransaction(async () => {}));
    assert.equal(maintenanceStarted, false);
    finishOld(); await oldWrite;
    await until(() => maintenanceStarted, '恢复开始');
    assert.equal(invalidated, false);
    finishRestore(); await restore;
    assert.equal(invalidated, true);
    assert.deepEqual(await rows(env, 'SELECT name FROM custom_category'), [{ name: '恢复结果' }]);
    await db.dbTransaction(async tx => { await tx.execute('INSERT INTO custom_category (name, position, updated_at) VALUES (?, ?, ?)', ['新写入', 1, 0]); });
    assert.equal((await rows(env, 'SELECT name FROM custom_category')).length, 2);
  });
  for (const count of [1000, 10000]) {
    await test(`${count} 条书架、历史和进度分页只读取请求页`, async env => {
      await seedMany(env, count);
      const { library } = env.load('data/Library');
      const { historyStore, readProgressStore } = env.load('data/stores/ReadingStores');
      for (const [label, read, key, expected] of [
        ['书架', () => library.listPage(127, 17), 'id', 'w127'],
        ['历史', () => historyStore.getPage(127, 17), 'id', `jm~${count - 128}`],
        ['进度', () => readProgressStore.listPage(127, 17), 'aid', `jm~${count - 128}`]
      ]) {
        env.state.sql.length = 0;
        const page = await read(); assert.equal(page.length, 17); assert.equal(page[0][key], expected);
        boundedReads(env, 17, `${count}/${label}`);
      }
    });
  }
  await test('万条书架入架仅写目标作品，移出失败后数据库与读取结果一致', async env => {
    await seedMany(env, 10000);
    const { library } = env.load('data/Library');
    env.state.sql.length = 0;
    const album = albumFixture(env, 'jm~new');
    album.name = '新增独立作品';
    await library.add(album);
    const writes = env.state.sql.filter(item => item.kind === 'write' && /\blibrary_work\b/.test(item.sql));
    assert.ok(writes.reduce((n, item) => n + item.changes, 0) <= 2, '增量修改不应重写整表');
    assert.ok(!writes.some(item => /^DELETE FROM library_work\s*$/i.test(item.sql.trim())));
    const work = await library.workFor(album.id);
    assert.ok(work);
    assert.equal((await rows(env, 'SELECT COUNT(*) AS count FROM library_work'))[0].count, '10001');
    env.state.failFlush = true;
    await assert.rejects(library.remove([work.id]), /磁盘/);
    assert.ok(await library.workFor(album.id));
    assert.equal((await rows(env, 'SELECT COUNT(*) AS count FROM library_work'))[0].count, '10001');
    await library.remove([work.id]);
    assert.equal(await library.workFor(album.id), null);
    assert.equal((await rows(env, 'SELECT COUNT(*) AS count FROM library_work'))[0].count, '10000');
    console.log(`  万条书架入架：${writes.length} 次写入，影响 ${writes.reduce((n, item) => n + item.changes, 0)} 行`);
  });
  await test('万条书架标记和分类仅修改目标作品及关系行', async env => {
    await seedMany(env, 10000);
    const { library } = env.load('data/Library');
    env.state.sql.length = 0;
    await library.markRead(['w5127'], true);
    await library.categorize(['w5127'], '精选');
    const operations = [...env.state.sql];
    const writes = operations.filter(item => item.kind === 'write');
    const changed = writes.reduce((n, item) => n + item.changes, 0);
    assert.ok(changed <= 3, `只改目标作品，应影响至多 3 行，实际 ${changed}`);
    assert.ok(operations.filter(item => item.kind === 'read').reduce((n, item) => n + item.rows, 0) <= 10);
    assert.deepEqual(await rows(env, 'SELECT read FROM library_work WHERE id = ?', ['w5127']), [{ read: '1' }]);
    assert.deepEqual(await rows(env, 'SELECT name FROM library_category WHERE work_id = ?', ['w5127']), [{ name: '精选' }]);
    assert.equal((await rows(env, 'SELECT COUNT(*) AS count FROM library_work WHERE read = 1'))[0].count, '1');
    assert.equal((await rows(env, 'SELECT COUNT(*) AS count FROM album_chapter'))[0].count, '10000');
    console.log(`  万条书架增量：${writes.length} 次写入，影响 ${changed} 行`);
  });
  await test('屏蔽规则 ID 在新增、启停、删除、重新加载后稳定', async env => {
    const { blockTagsStore } = env.load('data/stores/FilterStores');
    await blockTagsStore.addRule('jm', 'keyword', '甲');
    const [first] = await blockTagsStore.rulesFor('jm'); assert.ok(first.id > 0);
    await blockTagsStore.addRule('jm', 'tag', '乙');
    const two = await blockTagsStore.rulesFor('jm');
    assert.equal(two.find(rule => rule.value === '甲').id, first.id);
    const second = two.find(rule => rule.value === '乙');
    await blockTagsStore.setEnabled(first.id, false);
    assert.equal((await blockTagsStore.rulesFor('jm')).find(rule => rule.value === '甲').id, first.id);
    await blockTagsStore.removeRule(second.id); blockTagsStore.invalidate();
    const [remaining] = await blockTagsStore.rulesFor('jm');
    assert.equal(remaining.id, first.id); assert.equal(remaining.enabled, 0);
    await blockTagsStore.addRule('jm', 'tag', '丙');
    assert.ok((await blockTagsStore.rulesFor('jm')).find(rule => rule.value === '丙').id > second.id);
  });
  await test('认证随机数失败返回可重试结果，下一次可正常认证', async env => {
    const lock = env.load('util/AppLock');
    env.state.failRandom = true;
    const failed = await lock.authenticate('解锁');
    assert.equal(failed.ok, false); assert.ok(failed.message);
    assert.equal(env.state.authCalls.length, 0);
    const success = await lock.authenticate('解锁');
    assert.equal(success.ok, true); assert.equal(env.state.authCalls.length, 1);
    env.state.authResult = 12500003;
    assert.equal((await lock.authenticate('解锁')).message, '已取消验证');
  });
  await test('JM 请求取消立即结束，不跨域名重试或累计域名失败', async env => {
    const { JmDomainPool } = env.load('data/JmDomainPool');
    const { RequestAbortGroup, RequestCancelled } = env.load('util/RequestAbort');
    const pool = new JmDomainPool();
    env.state.textHandler = async () => { throw new RequestCancelled(); };
    const before = new RequestAbortGroup(); before.abortAll();
    await assert.rejects(pool.apiGet('/album?id=1', before), /取消/);
    assert.equal(env.state.textCalls?.length ?? 0, 0);
    await assert.rejects(pool.apiGet('/album?id=1', new RequestAbortGroup()), /取消/);
    assert.equal(env.state.textCalls.length, 1);
    env.state.textCalls.length = 0;
    env.state.textHandler = async () => { throw new RequestCancelled(); };
    await assert.rejects(pool.apiGet('/album?id=1', new RequestAbortGroup()), /取消/);
    assert.equal(env.state.textCalls.length, 1);
    // 相同首选域名仍被选中，取消未触发隔离或改变排序。
    assert.equal(env.state.textCalls[0][0].split('/')[2], 'www.cdnhjk.net');
  });
  await test('JM 还原接口网络故障回退，取消保持取消且可随后重试', async env => {
    const { JmDomainPool } = env.load('data/JmDomainPool');
    const { RequestAbortGroup, RequestCancelled } = env.load('util/RequestAbort');
    const pool = new JmDomainPool();
    env.state.textHandler = async () => { throw new Error('网络离线'); };
    assert.equal(await pool.scrambleId('201'), 220980);
    env.state.textHandler = async () => { throw new RequestCancelled(); };
    await assert.rejects(pool.scrambleId('202', new RequestAbortGroup()), /取消/);
    env.state.textHandler = async () => 'var scramble_id = 301234;';
    assert.equal(await pool.scrambleId('202'), 301234);
  });
}
