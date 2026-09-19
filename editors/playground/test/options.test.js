import {test} from 'node:test';
import assert from 'node:assert/strict';
import {restoreOptions} from '../src/options.js';
test('LuaJIT is the fresh default and old explicit shared links retain their runtime', () => {
  assert.deepEqual(restoreOptions(), {strict:true,optimize:true,dialect:'luajit'});
  assert.equal(restoreOptions({dialect:'lua51'}).dialect, 'lua51');
  assert.equal(restoreOptions({dialect:'luajit'}, {dialect:'lua51'}).dialect, 'luajit');
});
test('compatibility selects ordinary generation and source links override saved options', () => {
  assert.deepEqual(restoreOptions({compat:'lua51', strict:'0'}, {dialect:'lua51', optimize:false}),
    {strict:false,optimize:false,dialect:'luajit',compat:'lua51'});
  assert.equal(restoreOptions({compat:'invalid'}).compat, undefined);
});
