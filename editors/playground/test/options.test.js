import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DEFAULT_OPTIONS, restoreOptions, sourceFragment, storedOptions} from '../src/options.js';

test('LuaJIT is the only runtime and stale dialect settings are ignored', () => {
  assert.deepEqual(restoreOptions(), {strict:true,optimize:true,dialect:'luajit'});
  assert.deepEqual(restoreOptions({dialect:'lua51'}, {dialect:'lua51'}), DEFAULT_OPTIONS);
  assert.deepEqual(restoreOptions({source:'print(42)',dialect:'lua51'}, {compat:'lua51'}), DEFAULT_OPTIONS);
  assert.deepEqual(restoreOptions({source:'print(42)',dialect:'luajit'}, {compat:'lua51'}), DEFAULT_OPTIONS);
  assert.deepEqual(restoreOptions({source:'print(42)',dialect:'lua51'},
    {strict:false,optimize:false,compat:'lua51'}), {strict:false,optimize:false,dialect:'luajit'});
});

test('compatibility selects the checked stock Lua source subset', () => {
  assert.deepEqual(restoreOptions({compat:'lua51', strict:'0'}, {optimize:false}),
    {strict:false,optimize:false,dialect:'luajit',compat:'lua51'});
  assert.equal(restoreOptions({compat:'invalid'}).compat, undefined);
  assert.equal(restoreOptions({compat:''}, {compat:'lua51'}).compat, undefined);
});

test('source-only links inherit saved preferences', () => {
  const saved = {strict:false,optimize:false,dialect:'luajit',compat:'lua51'};
  assert.deepEqual(restoreOptions({source:'print(42)'}, saved), saved);
});

test('invalid saved state falls back to defaults', () => {
  for (const saved of [null, [], ['lua51'], true, false, 42, 'lua51']) {
    assert.deepEqual(restoreOptions({}, saved), DEFAULT_OPTIONS);
  }
  assert.deepEqual(restoreOptions(null, null), DEFAULT_OPTIONS);
  assert.deepEqual(restoreOptions({}, {strict:'false',optimize:0,dialect:'lua51',compat:'invalid'}), DEFAULT_OPTIONS);
});

test('stored options tolerate unavailable storage and malformed values', () => {
  const previous = Object.getOwnPropertyDescriptor(globalThis, 'localStorage');
  try {
    for (const value of [null, '', '{', 'null', '[]', '["lua51"]', 'true', '42', '"lua51"']) {
      Object.defineProperty(globalThis, 'localStorage', {configurable:true, value:{getItem:()=>value}});
      assert.deepEqual(storedOptions(), {});
    }
    Object.defineProperty(globalThis, 'localStorage', {configurable:true, value:{getItem:()=>'{}'}});
    assert.deepEqual(storedOptions(), {});
    Object.defineProperty(globalThis, 'localStorage', {configurable:true, get(){throw new Error('Storage unavailable');}});
    assert.deepEqual(storedOptions(), {});
  } finally {
    if (previous) Object.defineProperty(globalThis, 'localStorage', previous);
    else delete globalThis.localStorage;
  }
});

test('source links round-trip every retained option', () => {
  const configurations = [];
  for (const strict of [true, false]) for (const optimize of [true, false]) {
    configurations.push({strict,optimize,dialect:'luajit'},
      {strict,optimize,dialect:'luajit',compat:'lua51'});
  }
  const source = 'print("a+b &=#% — λ")\n--\u0000\r\n';
  for (const options of configurations) {
    const params = Object.fromEntries(new URLSearchParams(sourceFragment(source, options).slice(1)));
    assert.equal(params.source, source);
    for (const key of ['strict', 'optimize', 'compat']) assert.ok(Object.hasOwn(params, key));
    assert.ok(!Object.hasOwn(params, 'dialect'));
    for (const saved of configurations) assert.deepEqual(restoreOptions(params, saved), options);
  }
  const defaults = Object.fromEntries(new URLSearchParams(sourceFragment(source).slice(1)));
  assert.deepEqual(restoreOptions(defaults, {strict:false,optimize:false,dialect:'luajit',compat:'lua51'}), DEFAULT_OPTIONS);
});
