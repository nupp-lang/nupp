import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const shards = JSON.parse(readFileSync(path.join(root, '.github/simd-native-shards.json'), 'utf8'));
const expectedTypes = ['float', 'number', 'int8', 'uint8', 'int16', 'uint16', 'int32', 'uint32', 'int64', 'uint64'];
const expectedAlgorithms = ['utf8simd', 'base64simd', 'simd-json', 'fused-json'];

function entries(value) {
  return value === 'none' ? [] : value.split(',');
}

test('native shards partition every type and algorithm exactly once', () => {
  assert.ok(shards.length > 1, 'the native corpus must remain partitioned');
  assert.deepEqual(new Set(shards.map(({ name }) => name)).size, shards.length);
  for (const { name, types, algorithms } of shards) {
    assert.match(name, /^[a-z0-9-]+$/);
    assert.ok(entries(types).length, `${name} has no element types`);
    assert.equal(typeof algorithms, 'string');
  }
  assert.deepEqual(shards.flatMap(({ types }) => entries(types)).sort(), expectedTypes.sort());
  assert.deepEqual(shards.flatMap(({ algorithms }) => entries(algorithms)).sort(), expectedAlgorithms.sort());
});
