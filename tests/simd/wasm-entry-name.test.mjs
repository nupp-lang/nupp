import assert from 'node:assert/strict';
import {test} from 'node:test';
import {loweredEntryName} from './wasm-entry-name.mjs';

test('Wasm entry lookup follows emitted names after an underscore', () => {
  assert.equal(loweredEntryName('masked_i32_Min'), 'masked_i32_min');
  assert.equal(loweredEntryName('masked_i32_wrappingSum'), 'masked_i32_wrapping_sum');
});
