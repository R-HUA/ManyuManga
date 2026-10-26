import assert from 'node:assert/strict';
import path from 'node:path';
import { until } from './core-regressions.mjs';

function sourceList(ids) {
  return { sources: { nodes: ids.map(id => ({ id, displayName: `扩展 ${id}`, lang: 'zh' })) } };
}
async function scalar(env, sql, args = []) {
  const result = await env.load('data/db/AppDatabase').dbQuery(sql, args);
  try { assert.ok(result.goToNextRow()); return result.getString(0); }
  finally { result.close(); }
}

export async function sourceContractTests(test) {
  await test('图源注册表、策略与能力入口对未知 kind 明确报错', async env => {
    const registry = env.load('data/source/SourceRegistry');
    const { capabilitiesFor } = env.load('data/source/SourceContracts');
    const { strategyFor } = env.load('data/SourceApi');
    for (const kind of ['unregistered', '', 'JM']) {
      assert.equal(registry.registeredSourceKind(kind), null);
      assert.equal(registry.isRegisteredSourceKind(kind), false);
      for (const resolve of [registry.definitionFor, capabilitiesFor, strategyFor]) {
        assert.throws(() => resolve(kind), /未注册.*图源|不支持.*图源/);
      }
    }
  });
  await test('动态 sourceId 按实际 SourceEntry.kind 解析能力，缺失身份无猜测', async env => {
    const { sourceStore, SourceEntry } = env.load('data/Sources');
    const { capabilitiesForSourceId } = env.load('data/source/SourceContracts');
    const missing = capabilitiesForSourceId('not-loaded');
    assert.equal(missing.kind, null); assert.equal(missing.signedCover, false); assert.equal(missing.pageRestore, false);
    await sourceStore.save(new SourceEntry('suwayomi_looks_remote', '本地来源', 'local'));
    await sourceStore.save(new SourceEntry('extension_9007199254740993123', 'JM 来源', 'jm'));
    await sourceStore.save(new SourceEntry('opaque_gallery', '画廊来源', 'eh'));
    await sourceStore.save(new SourceEntry('jm_looks_builtin', '远程来源', 'suwayomi'));
    const local = capabilitiesForSourceId('suwayomi_looks_remote');
    assert.equal(local.kind, 'local'); assert.equal(local.importPackage, true); assert.equal(local.signedCover, false);
    const jm = capabilitiesForSourceId('extension_9007199254740993123');
    assert.equal(jm.kind, 'jm'); assert.equal(jm.pageRestore, true); assert.equal(jm.comments, true);
    const eh = capabilitiesForSourceId('opaque_gallery');
    assert.equal(eh.kind, 'eh'); assert.equal(eh.signedCover, true); assert.equal(eh.comments, true);
    const remote = capabilitiesForSourceId('jm_looks_builtin');
    assert.equal(remote.kind, 'suwayomi'); assert.equal(remote.pageRestore, false); assert.equal(remote.signedCover, true);
    await sourceStore.remove('suwayomi_looks_remote');
    assert.equal(capabilitiesForSourceId('suwayomi_looks_remote').kind, null);
  });
  await test('同步封面在图源未初始化或未知时保持空，已知动态 JM 身份才计算地址', async env => {
    const { sourceApi } = env.load('data/SourceApi');
    const { sourceStore, SourceEntry, sourceKey } = env.load('data/Sources');
    assert.equal(sourceApi.albumCoverUrl('jm~101'), '');
    assert.equal(sourceApi.albumThumbUrl('missing~101'), '');
    await sourceStore.list();
    assert.equal(sourceApi.albumCoverUrl('missing~101'), '');
    assert.equal(sourceApi.albumThumbUrl('missing~101'), '');
    await sourceStore.save(new SourceEntry('opaque_comic', '动态 JM', 'jm'));
    assert.equal(sourceApi.albumCoverUrl(sourceKey('opaque_comic', '原始/编号')), 'https://cover.invalid/原始/编号.jpg');
    assert.equal(sourceApi.albumThumbUrl(sourceKey('opaque_comic', '原始/编号')), 'https://cover.invalid/原始/编号-thumb.jpg');
    await sourceStore.remove('opaque_comic');
    assert.equal(sourceApi.albumCoverUrl(sourceKey('opaque_comic', '原始/编号')), '');
  });
  await test('JM 评论取消组经过公共入口与策略传入引擎，取消销毁在途请求', async env => {
    const { sourceApi } = env.load('data/SourceApi');
    const { sourceStore, SourceEntry, sourceKey } = env.load('data/Sources');
    const { RequestAbortGroup, RequestCancelled } = env.load('util/RequestAbort');
    await sourceStore.save(new SourceEntry('custom_jm', 'JM', 'jm'));
    const group = new RequestAbortGroup();
    const calls = []; let destroyed = 0;
    env.load('data/JmApi').jmApi.comments = (id, page, signal) => {
      calls.push({ id, page, signal });
      const request = { destroy: () => { destroyed++; } }; signal.track(request);
      return signal.cancelled.then(() => { signal.untrack(request); throw new RequestCancelled(); });
    };
    const pending = sourceApi.comments(sourceKey('custom_jm', '123/456'), 2, group);
    const rejected = assert.rejects(pending, /取消/);
    await until(() => calls.length > 0, 'JM 评论到达引擎');
    assert.equal(calls[0].id, '123/456'); assert.equal(calls[0].page, 2); assert.equal(calls[0].signal, group);
    group.abortAll(); await rejected; assert.equal(destroyed, 1);
    await assert.rejects(sourceApi.comments(sourceKey('custom_jm', '123/456'), 1, group), /取消/);
    assert.equal(calls.length, 1);
  });
  await test('EH 评论取消组经策略转换为同一控制接口并传到底层详情与评论引擎', async env => {
    const { sourceApi } = env.load('data/SourceApi');
    const { sourceStore } = env.load('data/Sources');
    const { RequestAbortGroup, RequestCancelled } = env.load('util/RequestAbort');
    const { NativeEhClient } = env.load('data/eh/EhNative');
    await sourceStore.list();
    const group = new RequestAbortGroup(), controls = [];
    const detail = { gid: 1234567, token: 'a1b2c3d4e5', pages: 1, comments: [] };
    NativeEhClient.fetchGalleryDetail = async (_site, _summary, control) => { controls.push(control); return detail; };
    let commentControl, destroyed = 0;
    NativeEhClient.fetchGalleryDetailComments = (_site, receivedDetail, control) => {
      assert.equal(receivedDetail, detail); commentControl = control;
      const request = { destroy: () => { destroyed++; } }; control.onStart(request);
      return control.cancelled.then(() => { control.onFinish(request); throw new RequestCancelled(); });
    };
    const pending = sourceApi.comments('eh~1234567_a1b2c3d4e5', 1, group);
    const rejected = assert.rejects(pending, /取消/);
    await until(() => commentControl !== undefined, 'EH 评论到达引擎');
    assert.equal(controls[0], commentControl); assert.equal(commentControl.cancelled, group.cancelled);
    assert.equal(commentControl.isCancelled(), false);
    group.abortAll(); await rejected;
    assert.equal(commentControl.isCancelled(), true); assert.equal(destroyed, 1);
  });
  await test('Suwayomi 单服务多扩展重复连接保留实例与扩展身份', async env => {
    const { suwayomi } = env.load('data/Suwayomi'), { sourceStore } = env.load('data/Sources');
    const ids = ['9007199254740993123', '42'];
    env.state.handler = async () => sourceList(ids);
    const first = await suwayomi.connect('https://first.invalid/', '服务', 'none', '', '');
    const connection = await sourceStore.connection();
    env.state.handler = async () => sourceList([...ids].reverse());
    const second = await suwayomi.connect('https://first.invalid', '重命名服务', 'none', '', '');
    assert.equal((await sourceStore.connection()).id, connection.id);
    assert.equal(first.length, 2); assert.equal(second.length, 2);
    for (const old of first) {
      const current = second.find(entry => entry.remoteId === old.remoteId);
      assert.equal(current.id, old.id); assert.equal(current.instanceId, connection.id);
    }
    const stored = (await sourceStore.list()).filter(entry => entry.kind === 'suwayomi');
    assert.equal(stored.length, 2); assert.equal(stored.filter(entry => entry.enabled).length, 2);
    assert.equal(await scalar(env, 'SELECT COUNT(*) FROM source_instance'), '1');
  });
  await test('Suwayomi 扩展减少后保留并禁用旧身份，扩展重新出现仍复用原 ID', async env => {
    const { suwayomi } = env.load('data/Suwayomi'), { sourceStore } = env.load('data/Sources');
    env.state.handler = async () => sourceList(['10', '20']);
    const first = await suwayomi.connect('https://first.invalid', '服务', 'none', '', '');
    env.state.handler = async () => sourceList(['10']);
    await suwayomi.connect('https://first.invalid', '服务', 'none', '', '');
    const stored = (await sourceStore.list()).filter(entry => entry.kind === 'suwayomi');
    assert.equal(stored.length, 2);
    const absent = stored.find(entry => entry.remoteId === '20');
    assert.equal(absent.id, first.find(entry => entry.remoteId === '20').id); assert.equal(absent.enabled, false);
    assert.equal(stored.find(entry => entry.remoteId === '10').enabled, true);
    await assert.rejects(sourceStore.get(absent.id), /停用|移除/);
    env.state.handler = async () => sourceList(['10', '20']);
    const appeared = await suwayomi.connect('https://first.invalid', '服务', 'none', '', '');
    assert.equal(appeared.find(entry => entry.remoteId === '20').id, absent.id);
    assert.equal((await sourceStore.list()).filter(entry => entry.kind === 'suwayomi').length, 2);
  });
  await test('Suwayomi 更换服务先要求显式替换，替换后仅一个活跃服务实例', async env => {
    const { suwayomi } = env.load('data/Suwayomi'), { sourceStore } = env.load('data/Sources');
    env.state.handler = async () => sourceList(['42', '43']);
    const first = await suwayomi.connect('https://first.invalid', '原服务', 'none', '', '');
    const oldConnection = await sourceStore.connection(), requests = env.state.calls.length;
    await assert.rejects(suwayomi.connect('https://second.invalid', '新服务', 'none', '', ''), /确认|替换/);
    assert.equal(env.state.calls.length, requests); assert.equal((await sourceStore.connection()).id, oldConnection.id);
    env.state.handler = async () => sourceList(['42']);
    const replacement = await suwayomi.connect('https://second.invalid', '新服务', 'none', '', '', '', true);
    const connection = await sourceStore.connection();
    assert.equal(connection.endpoint, 'https://second.invalid'); assert.notEqual(connection.id, oldConnection.id);
    assert.notEqual(replacement[0].id, first[0].id);
    const all = (await sourceStore.list()).filter(entry => entry.kind === 'suwayomi');
    assert.ok(all.filter(entry => entry.instanceId === oldConnection.id).every(entry => !entry.enabled));
    assert.equal(new Set(all.filter(entry => entry.enabled).map(entry => entry.instanceId)).size, 1);
    assert.ok(all.filter(entry => entry.enabled).every(entry => entry.instanceId === connection.id));
    assert.equal(await scalar(env, 'SELECT COUNT(*) FROM source_instance'), '1');
  });
  await test('源配置首次初始化失败回滚种子，后续初始化可重试', async env => {
    const { sourceStore } = env.load('data/Sources');
    env.state.failSql = operation => /^INSERT INTO source_entry\b/.test(operation.sql);
    const attempts = await Promise.allSettled([sourceStore.list(), sourceStore.list()]);
    assert.ok(attempts.every(result => result.status === 'rejected'));
    assert.equal(sourceStore.peek('jm'), null);
    env.state.failSql = undefined;
    assert.equal(await scalar(env, 'SELECT COUNT(*) FROM source_entry'), '0');
    const recovered = await sourceStore.list();
    assert.equal(recovered.length, 3); assert.equal(sourceStore.peek('jm').kind, 'jm');
    assert.equal(await scalar(env, 'SELECT COUNT(*) FROM source_entry'), '3');
  });
  await test('备份恢复替换图源后同步快照和能力立即使用恢复值', async env => {
    const { sourceStore, SourceEntry } = env.load('data/Sources');
    const { capabilitiesForSourceId } = env.load('data/source/SourceContracts');
    const backup = env.load('data/Backup');
    await sourceStore.save(new SourceEntry('snapshot', '备份来源', 'local'));
    const file = path.join(env.directory, 'source-snapshot.json'); env.state.saved = [file];
    assert.equal(await backup.exportBackup(), true);
    await sourceStore.save(new SourceEntry('snapshot', '当前来源', 'jm'));
    assert.equal(sourceStore.peek('snapshot').name, '当前来源');
    assert.equal(capabilitiesForSourceId('snapshot').pageRestore, true);
    env.state.selected = [file]; assert.equal(await backup.importBackup(), true);
    assert.equal(sourceStore.peek('snapshot').name, '备份来源');
    assert.equal(sourceStore.peek('snapshot').kind, 'local');
    assert.equal(capabilitiesForSourceId('snapshot').importPackage, true);
    assert.equal(capabilitiesForSourceId('snapshot').pageRestore, false);
    assert.equal((await sourceStore.get('snapshot')).name, '备份来源');
  });
  await test('建表中途失败关闭句柄，重试继续建库并完整发布版本', async env => {
    const db = env.load('data/db/AppDatabase');
    let injected = false;
    env.state.failSql = operation => {
      if (!injected && /^CREATE INDEX\b/.test(operation.sql)) { injected = true; return true; }
      return false;
    };
    const failed = await Promise.allSettled([db.openDatabase(), db.openDatabase()]);
    assert.ok(failed.every(result => result.status === 'rejected' && /SQL/.test(result.reason.message)));
    assert.deepEqual(env.state.closedStores, ['manyu_business_v2.db']);
    const store = await db.openDatabase(); assert.equal(store.version, 1);
    const { TABLE_DELETE_ORDER } = env.load('data/db/Schema');
    for (const table of TABLE_DELETE_ORDER) assert.equal(await scalar(env, `SELECT COUNT(*) FROM ${table}`), '0');
    assert.equal(env.state.opens.length, 2);
    assert.equal((await env.load('data/Sources').sourceStore.list()).length, 3);
  });
}
