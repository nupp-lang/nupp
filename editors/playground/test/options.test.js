import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DEFAULT_OPTIONS, restoreOptions, sourceFragment, storedOptions} from '../src/options.js';
test('LuaJIT is the fresh default and old explicit shared links retain their runtime', () => {
  assert.deepEqual(restoreOptions(), {strict:true,optimize:true,dialect:'luajit'});
  assert.equal(restoreOptions({dialect:'lua51'}).dialect, 'lua51');
  assert.equal(restoreOptions({dialect:'luajit'}, {dialect:'lua51'}).dialect, 'luajit');
  assert.deepEqual(restoreOptions({dialect:'lua51'}, {dialect:'luajit', compat:'lua51'}),
    {strict:true,optimize:true,dialect:'lua51'});
  assert.deepEqual(restoreOptions({dialect:'lua51', compat:'lua51'}),
    {strict:true,optimize:true,dialect:'lua51'});
  assert.deepEqual(restoreOptions({dialect:'luajit'}, {compat:'lua51'}), DEFAULT_OPTIONS);
});
test('compatibility selects ordinary generation and source links override saved options', () => {
  assert.deepEqual(restoreOptions({compat:'lua51', strict:'0'}, {dialect:'lua51', optimize:false}),
    {strict:false,optimize:false,dialect:'luajit',compat:'lua51'});
  assert.equal(restoreOptions({compat:'invalid'}).compat, undefined);
  assert.equal(restoreOptions({compat:''}, {compat:'lua51'}).compat, undefined);
});
test('old source-only links still inherit saved preferences', () => {
  const saved = {strict:false,optimize:false,dialect:'luajit',compat:'lua51'};
  assert.deepEqual(restoreOptions({source:'print(42)'}, saved), saved);
  assert.deepEqual(restoreOptions({source:'print(42)'}, {dialect:'lua51'}),
    {strict:true,optimize:true,dialect:'lua51'});
});
test('invalid saved state falls back to defaults', () => {
  for (const saved of [null, [], ['lua51'], true, false, 42, 'lua51']) {
    assert.deepEqual(restoreOptions({}, saved), DEFAULT_OPTIONS);
  }
  assert.deepEqual(restoreOptions(null, null), DEFAULT_OPTIONS);
  assert.deepEqual(restoreOptions({}, {strict:'false',optimize:0,dialect:'invalid',compat:'invalid'}), DEFAULT_OPTIONS);
  assert.deepEqual(restoreOptions({}, {dialect:'lua51',compat:'lua51'}),
    {strict:true,optimize:true,dialect:'lua51'});
});
test('stored options tolerate unavailable storage, invalid JSON, and nonobject JSON', () => {
  const previous = Object.getOwnPropertyDescriptor(globalThis, 'localStorage');
  try {
    for (const value of [null, '', '{', 'null', '[]', '["lua51"]', 'true', '42', '"lua51"']) {
      Object.defineProperty(globalThis, 'localStorage', {configurable:true, value:{getItem:()=>value}});
      assert.deepEqual(storedOptions(), {});
    }
    Object.defineProperty(globalThis, 'localStorage', {configurable:true, value:{getItem:()=>'{"dialect":"lua51"}'}});
    assert.deepEqual(storedOptions(), {dialect:'lua51'});
    Object.defineProperty(globalThis, 'localStorage', {configurable:true, get(){throw new Error('Storage unavailable');}});
    assert.deepEqual(storedOptions(), {});
  } finally {
    if (previous) Object.defineProperty(globalThis, 'localStorage', previous);
    else delete globalThis.localStorage;
  }
});
test('new source links round-trip every option independently of recipient preferences', () => {
  const configurations = [];
  for (const strict of [true, false]) for (const optimize of [true, false]) {
    configurations.push({strict,optimize,dialect:'luajit'},
      {strict,optimize,dialect:'lua51'}, {strict,optimize,dialect:'luajit',compat:'lua51'});
  }
  const source = 'print("a+b &=#% — λ")\n--\u0000\r\n';
  for (const options of configurations) {
    const params = Object.fromEntries(new URLSearchParams(sourceFragment(source, options).slice(1)));
    assert.equal(params.source, source);
    for (const key of ['strict', 'optimize', 'dialect', 'compat']) assert.ok(Object.hasOwn(params, key));
    for (const saved of configurations) assert.deepEqual(restoreOptions(params, saved), options);
  }
  const defaults = Object.fromEntries(new URLSearchParams(sourceFragment(source).slice(1)));
  assert.deepEqual(restoreOptions(defaults, {strict:false,optimize:false,dialect:'luajit',compat:'lua51'}), DEFAULT_OPTIONS);
});
