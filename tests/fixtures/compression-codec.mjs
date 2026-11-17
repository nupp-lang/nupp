// Independent fixtures: Node's codec, not the provider under test.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
const directory = process.argv[2];
if (!directory) throw new Error('fixture output directory required');
fs.mkdirSync(directory, {recursive: true});
const input = Buffer.from(Array.from({length: 4096}, (_, i) => i % 10 < 8 ? 97 + i % 3 : (i * i + i * 13) & 255));
fs.writeFileSync(path.join(directory, 'input.bin'), input);
for (const [name, compress] of [['gzip', zlib.gzipSync], ['zlib', zlib.deflateSync], ['deflate-raw', zlib.deflateRawSync]]) {
  for (const [kind, options] of [['stored', {level: 0}], ['fixed', {strategy: zlib.constants.Z_FIXED}], ['dynamic', {level: 9}]]) {
    const bytes = compress(input, options);
    if (name === 'deflate-raw') {
      const expected = {stored: 0, fixed: 1, dynamic: 2}[kind];
      if (((bytes[0] >> 1) & 3) !== expected) throw new Error(`fixture did not produce a ${kind} block`);
    }
    fs.writeFileSync(path.join(directory, `${name}-${kind}.bin`), bytes);
  }
}
