import assert from 'node:assert/strict';
import {test} from 'node:test';
import {loweredEntryName} from './wasm-entry-name.mjs';

test('Wasm entry lookup follows the compiler for canonical names', () => {
  assert.equal(loweredEntryName('sum'), 'sum');
  assert.equal(loweredEntryName('wrappingSum'), 'wrapping_sum');
  assert.equal(loweredEntryName('x9y'), 'x9y');
});

test('Wasm entry lookup carries the source bytes of other names', () => {
  assert.equal(loweredEntryName('fields_2'), 'fields_2__6669656c64735f32');
  assert.equal(loweredEntryName('masked_i32_Min'), 'masked_i32_min__6d61736b65645f6933325f4d696e');
  assert.equal(loweredEntryName('masked_i32_wrappingSum'),
    'masked_i32_wrapping_sum__6d61736b65645f6933325f7772617070696e6753756d');
  assert.equal(loweredEntryName('parseJSONValue'), 'parse_json_value__70617273654a534f4e56616c7565');
  assert.equal(loweredEntryName('HTTPServer'), 'http_server__48545450536572766572');
  assert.equal(loweredEntryName('a-b'), 'a_b__612d62');
  assert.equal(loweredEntryName('é'), '____c3a9');
});
