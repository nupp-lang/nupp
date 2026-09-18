import fs from 'node:fs';
import {brotliCompressSync, constants} from 'node:zlib';
import {createHash} from 'node:crypto';

const root = 'build/v86-spike/performance/';
const files = JSON.parse(fs.readFileSync('bench/v86-spike/results/assets.json')).gameFiles.map(name =>
  name === 'app.ljbc' ? 'compiler-performance.lua' : name === 'assets/bzimage.bin' ? 'assets/kernel-empty-rootfs.bin' : name);
const rows = files.map(name => {
  const bytes = fs.readFileSync(root + 'web/' + name);
  const br = brotliCompressSync(bytes, {params: {[constants.BROTLI_PARAM_QUALITY]: 9}});
  return {name, rawBytes: bytes.length, encodedBytes: Math.min(bytes.length, br.length),
    sha256: createHash('sha256').update(bytes).digest('hex')};
});
const report = {
  scope: 'Compiler fixture asset inventory with Brotli quality 9 when smaller; not a network capture or the full playground UI. Contains its own combined initramfs. Shared URLs/base-image deduplication are not implemented.',
  payloadBytes: rows.reduce((sum, row) => sum + row.encodedBytes, 0), files: rows,
};
fs.writeFileSync(root + 'compiler-assets.json', JSON.stringify(report, null, 2) + '\n');
console.log(report.payloadBytes);
