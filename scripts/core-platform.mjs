import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';

const turn = () => new Promise(resolve => setImmediate(resolve));

/** 真正运行建表、约束和事务；只转换 HarmonyOS 接口形状。 */
export function makeRelationalStore(state) {
  const databases = new Map();
  state.sql = [];
  state.opens = [];
  state.closedStores = [];
  state.openResults = new Set();
  const close = () => {
    assert.equal(state.openResults.size, 0, 'ResultSet 必须关闭');
    for (const entry of databases.values()) entry.database.close();
  };
  const makeStore = (name, database = new DatabaseSync(':memory:')) => {
    let inTransaction = false;
    let closed = false;
    const statement = (sql, args, tx, query) => {
      assert.equal(closed, false, 'RdbStore 已关闭');
      const record = { sql, args: [...args], tx, kind: query ? 'read' : 'write', rows: 0, changes: 0 };
      state.sql.push(record);
      if (state.failSql?.(record)) throw new Error('注入 SQL 写入失败');
      const stmt = database.prepare(sql);
      if (query) {
        const columns = stmt.columns().map(column => column.name);
        const rows = stmt.all(...args);
        record.rows = rows.length;
        return resultSet(columns, rows);
      }
      const result = stmt.run(...args);
      record.changes = Number(result.changes);
      return /^\s*(INSERT|REPLACE)\b/i.test(sql) ? Number(result.lastInsertRowid) : Number(result.changes);
    };
    const resultSet = (columns, rows) => {
      let index = -1;
      let closed = false;
      const cell = column => {
        assert.equal(closed, false, 'ResultSet 已关闭');
        assert.ok(index >= 0 && index < rows.length, 'ResultSet 游标越界');
        assert.ok(column >= 0 && column < columns.length, 'ResultSet 列下标越界');
        return rows[index][columns[column]];
      };
      const result = {
        rowCount: rows.length, columnNames: columns, columnCount: columns.length,
        get rowIndex() { return index; },
        goToNextRow() { assert.equal(closed, false); return ++index < rows.length; },
        goToFirstRow() { assert.equal(closed, false); index = 0; return rows.length > 0; },
        getColumnIndex: name => columns.indexOf(name),
        getColumnName: column => columns[column],
        getString: column => cell(column) === null ? '' : String(cell(column)),
        getLong: column => Number(cell(column) ?? 0),
        getDouble: column => Number(cell(column) ?? 0),
        getBlob: column => new Uint8Array(cell(column)),
        isColumnNull: column => cell(column) === null,
        close() { closed = true; state.openResults.delete(result); }
      };
      state.openResults.add(result);
      return result;
    };
    const execute = async (sql, args = [], tx = false) => {
      await turn();
      return statement(sql, args, tx, false);
    };
    const querySql = async (sql, args = [], tx = false) => {
      await turn();
      return statement(sql, args, tx, true);
    };
    const insert = async (table, values, conflict = 0, tx = false) => {
      const resolution = ['', 'OR ROLLBACK ', 'OR ABORT ', 'OR FAIL ', 'OR IGNORE ', 'OR REPLACE '][conflict];
      assert.notEqual(resolution, undefined);
      const keys = Object.keys(values);
      return execute(`INSERT ${resolution}INTO ${table} (${keys.join(', ')}) VALUES (${keys.map(() => '?').join(', ')})`, Object.values(values), tx);
    };
    const store = {
      get version() { assert.equal(closed, false); return database.prepare('PRAGMA user_version').get().user_version; },
      set version(value) { assert.equal(closed, false); assert.ok(Number.isInteger(value)); database.exec(`PRAGMA user_version = ${value}`); },
      async close() {
        await turn(); assert.equal(closed, false);
        if (inTransaction) { database.exec('ROLLBACK'); inTransaction = false; }
        closed = true; state.closedStores.push(name);
      },
      executeSql: async (sql, args = []) => { await execute(sql, args); },
      execute, querySql, insert,
      async createTransaction() {
        await turn();
        assert.equal(closed, false, 'RdbStore 已关闭');
        assert.equal(inTransaction, false, '不应同时开启多个事务');
        database.exec('BEGIN IMMEDIATE');
        inTransaction = true;
        let ended = false;
        const active = () => assert.equal(ended, false, '事务已结束');
        return {
          execute: async (sql, args = []) => { active(); return execute(sql, args, true); },
          querySql: async (sql, args = []) => { active(); return querySql(sql, args, true); },
          insert: async (table, values, conflict = 0) => { active(); return insert(table, values, conflict, true); },
          async commit() {
            await turn(); active();
            if (state.failFlush) { state.failFlush = false; throw new Error('磁盘写入失败'); }
            database.exec('COMMIT'); ended = true; inTransaction = false;
          },
          async rollback() { await turn(); active(); database.exec('ROLLBACK'); ended = true; inTransaction = false; }
        };
      }
    };
    // 内存连接保存文件内容，关闭后新建句柄；模拟同一业务文件重新打开。
    return { database, store, isClosed: () => closed };
  };
  return {
    close,
    platform: {
      SecurityLevel: { S1: 1, S2: 2, S3: 3, S4: 4 },
      ConflictResolution: { ON_CONFLICT_NONE: 0, ON_CONFLICT_ROLLBACK: 1, ON_CONFLICT_ABORT: 2, ON_CONFLICT_FAIL: 3, ON_CONFLICT_IGNORE: 4, ON_CONFLICT_REPLACE: 5 },
      async getRdbStore(_context, config) {
        await turn(); state.opens.push(config.name);
        if (state.failOpen) { state.failOpen = false; throw new Error('业务库暂时无法打开'); }
        if (!databases.has(config.name)) databases.set(config.name, makeStore(config.name));
        else if (databases.get(config.name).isClosed()) databases.set(config.name, makeStore(config.name, databases.get(config.name).database));
        return databases.get(config.name).store;
      },
      async deleteRdbStore(_context, config) {
        await turn();
        const name = typeof config === 'string' ? config : config.name;
        if (databases.has(name)) { databases.get(name).database.close(); databases.delete(name); }
        state.deletedDatabases ??= []; state.deletedDatabases.push(name);
      }
    }
  };
}

export function makeNativeFs(directory, state) {
  const filePath = value => typeof value === 'string' && value.startsWith('file://') ? fileURLToPath(value) : value;
  const bytes = value => typeof value === 'string' ? value : new Uint8Array(value);
  const pointers = new Map();
  state.openFiles = pointers;
  const api = {
    OpenMode: { READ_ONLY: fs.constants.O_RDONLY, READ_WRITE: fs.constants.O_RDWR, CREATE: fs.constants.O_CREAT, TRUNC: fs.constants.O_TRUNC },
    openSync: (file, mode) => { const fd = fs.openSync(filePath(file), mode); pointers.set(fd, 0); return { fd }; },
    closeSync: file => { const fd = typeof file === 'number' ? file : file.fd; fs.closeSync(fd); pointers.delete(fd); },
    statSync: file => typeof file === 'number' ? fs.fstatSync(file) : fs.statSync(filePath(file)),
    readSync: (fd, buffer, options = {}) => {
      const position = pointers.get(fd) + (options.offset ?? 0);
      const length = Math.min(options.length ?? buffer.byteLength, state.readChunkLimit ?? Infinity);
      const count = fs.readSync(fd, new Uint8Array(buffer), 0, length, position);
      pointers.set(fd, position + count); return count;
    },
    writeSync: (fd, value, options = {}) => {
      const position = pointers.get(fd) + (options.offset ?? 0);
      const data = typeof value === 'string' ? Buffer.from(value, options.encoding ?? 'utf8') : bytes(value);
      const length = Math.min(options.length ?? data.byteLength, state.writeChunkLimit ?? Infinity);
      const count = fs.writeSync(fd, data, 0, length, position);
      pointers.set(fd, position + count); return count;
    },
    readTextSync: file => fs.readFileSync(filePath(file), 'utf8'),
    mkdirSync: (file, recursive) => fs.mkdirSync(filePath(file), { recursive: !!recursive }),
    unlinkSync: file => fs.unlinkSync(filePath(file)),
    accessSync: file => fs.existsSync(filePath(file)),
    rmdirSync: file => {
      assert.ok(path.resolve(file).startsWith(directory + path.sep));
      fs.rmSync(filePath(file), { recursive: true });
    },
    renameSync: (from, to) => fs.renameSync(filePath(from), filePath(to)),
    copyFileSync: (source, target) => {
      if (state.failCopy?.(source, target)) throw new Error('注入文件复制失败');
      const data = fs.readFileSync(filePath(source));
      if (typeof target === 'number') fs.writeSync(target, data);
      else fs.writeFileSync(filePath(target), data);
    },
    listFileSync: (root, options = {}) => {
      const result = [];
      const visit = (folder, prefix) => {
        for (const item of fs.readdirSync(folder, { withFileTypes: true })) {
          const name = prefix + item.name;
          if (item.isDirectory() && options.recursion) visit(path.join(folder, item.name), name + '/');
          else result.push(name);
        }
      };
      visit(filePath(root), ''); return result;
    }
  };
  for (const name of ['open', 'close', 'stat', 'read', 'write', 'readText', 'mkdir', 'unlink', 'access', 'rmdir', 'rename', 'copyFile', 'listFile']) {
    api[name] = async (...args) => { await turn(); return api[`${name}Sync`](...args); };
  }
  return api;
}

/** SDK 随机数返回 DataBlob；认证回调通过 on('result', IAuthCallback) 注册。 */
export function makeAuthentication(state) {
  state.authCalls = [];
  const cryptoFramework = {
    CryptoMode: { DECRYPT_MODE: 1 },
    createMd(algorithm) {
      const hash = crypto.createHash(algorithm.toLowerCase());
      return { updateSync: blob => { hash.update(blob.data); }, digestSync: () => ({ data: new Uint8Array(hash.digest()) }) };
    },
    createSymKeyGenerator(algorithm) {
      assert.equal(algorithm, 'AES256');
      return { convertKey: async blob => ({ bytes: blob.data }) };
    },
    createCipher(algorithm) {
      assert.equal(algorithm, 'AES256|ECB|PKCS7');
      let decipher;
      return {
        async init(mode, key, params) { assert.equal(mode, 1); assert.equal(params, null); decipher = crypto.createDecipheriv('aes-256-ecb', key.bytes, null); },
        async doFinal(blob) { return { data: new Uint8Array(Buffer.concat([decipher.update(blob.data), decipher.final()])) }; }
      };
    },
    createRandom: () => ({
      generateRandomSync(length) {
        if (state.failRandom) { state.failRandom = false; throw new Error('安全随机数暂时不可用'); }
        return { data: new Uint8Array(crypto.randomBytes(length)) };
      },
      async generateRandom(length) { return this.generateRandomSync(length); }
    })
  };
  const userAuth = {
    AuthTrustLevel: { ATL2: 20000 }, UserAuthType: { PIN: 1, FACE: 2, FINGERPRINT: 4 },
    getAvailableStatus: () => {},
    getUserAuthInstance(param, widget) {
      assert.ok(param.challenge instanceof Uint8Array);
      assert.equal(param.challenge.length, 16);
      state.authCalls.push({ param, widget });
      let callback;
      return {
        on(event, value) { assert.equal(event, 'result'); callback = value; },
        off(event) { assert.equal(event, 'result'); callback = undefined; },
        start() { queueMicrotask(() => callback?.onResult({ result: state.authResult ?? 12500000 })); },
        cancel() {}
      };
    }
  };
  return { cryptoFramework, userAuth };
}
