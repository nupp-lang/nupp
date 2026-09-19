import {test} from 'node:test';
import assert from 'node:assert/strict';
import {describeError} from '../src/describe-error.js';

test('boot failures retain their message when WebKit omits it from the stack', () => {
  const error = new Error('LuaJIT compiler initialization timed out');
  error.stack = 'boot@http://localhost/worker.js:12:5';
  assert.equal(describeError(error),
    'LuaJIT compiler initialization timed out\nboot@http://localhost/worker.js:12:5');
});

test('a stack containing the error message is preserved without duplication', () => {
  const error = new Error('Compiler asset digest mismatch');
  error.stack = 'Error: Compiler asset digest mismatch\n    at boot (worker.js:12:5)';
  assert.equal(describeError(error), error.stack);
});

test('an error without a stack retains its message', () => {
  const error = new Error('Compiler asset unavailable');
  error.stack = undefined;
  assert.equal(describeError(error), 'Compiler asset unavailable');
});

test('non-Error thrown values are printable, including null and undefined', () => {
  for (const value of ['boot failed', null, undefined, 17, {reason: 'unavailable'}]) {
    assert.equal(describeError(value), String(value));
  }
});
