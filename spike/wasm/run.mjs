// Runs the directly emitted Wasm kernels against JavaScript references, which
// use the same IEEE-754 binary64 operations in the same order, so maps and
// refinements must match bit for bit; the algebraic sum within 1e-12.
import { readFile } from 'node:fs/promises';

const bytes = await readFile(process.argv[2]);
const { instance } = await WebAssembly.instantiate(bytes, {});
const k = instance.exports;
const mem = () => new Float64Array(k.memory.buffer);
const LEFT = 0, RIGHT = 65540 * 8, OUT = 2 * 65540 * 8;

function fill(n) {
  const m = mem();
  for (let i = 0; i < n; i++) { m[LEFT / 8 + i] = ((i % 97) + 1) * 0.125; m[RIGHT / 8 + i] = ((i % 17) + 1) * 0.0625; }
  for (let i = 0; i < n + 4; i++) m[OUT / 8 + i] = -777;
}
const refine = x => { let rounds = 0; while (x > 1 && rounds < 32) { x *= 0.5; rounds += 1; } return x + rounds; };
const cases = {
  map: [n => k.map(OUT, LEFT, 1.25, -0.5, BigInt(n)), x => x * 1.25 + -0.5],
  explicitMap: [n => k.explicitMap(OUT, LEFT, 1.25, -0.5, BigInt(n), BigInt(n)), x => x * 1.25 + -0.5],
  refine: [n => k.refine(OUT, LEFT, BigInt(n)), refine],
  explicitRefine: [n => k.explicitRefine(OUT, LEFT, BigInt(n), BigInt(n)), refine],
};
let failures = 0;
for (const [name, [run, ref]] of Object.entries(cases)) {
  let bad = null;
  for (const n of [...Array(18).keys(), 63, 1000, 65539]) {
    fill(n); run(n);
    const m = mem(), view = new DataView(k.memory.buffer);
    for (let i = 0; i < n + 4; i++) {
      const want = i < n ? ref(m[LEFT / 8 + i]) : -777;
      if (!Object.is(m[OUT / 8 + i], want)) { bad = `n=${n} [${i}] ${m[OUT / 8 + i]} != ${want}`; break; }
    }
    if (bad) break;
  }
  if (bad) failures++;
  console.log(`  ${bad ? 'FAIL' : 'same'} ${name.padEnd(18)} ${bad ?? 'bit-identical to the JS reference, n=0..17,63,1000,65539'}`);
}
{
  let bad = null;
  for (const n of [...Array(18).keys(), 63, 1000, 65539]) {
    fill(n);
    const got = k.explicitAlgebraic(LEFT, RIGHT, BigInt(n), BigInt(n));
    const m = mem(); let want = 0;
    for (let i = 0; i < n; i++) want += m[LEFT / 8 + i] * m[RIGHT / 8 + i];
    if (Math.abs(got - want) > 1e-12 * Math.max(1, Math.abs(want))) { bad = `n=${n}: ${got} vs ${want}`; break; }
  }
  if (bad) failures++;
  console.log(`  ${bad ? 'FAIL' : 'same'} ${'explicitAlgebraic'.padEnd(18)} ${bad ?? 'within 1e-12 of the JS reference'}`);
}
// Wasm SIMD against the same computation in plain JS, n = 1000, in Node.
fill(1000);
for (const [name, f] of [['explicitMap', () => k.explicitMap(OUT, LEFT, 1.25, -0.5, 1000n, 1000n)],
                         ['explicitAlgebraic', () => k.explicitAlgebraic(LEFT, RIGHT, 1000n, 1000n)]]) {
  const js = name === 'explicitMap'
    ? (() => { const m = mem(); return () => { for (let i = 0; i < 1000; i++) m[OUT / 8 + i] = m[LEFT / 8 + i] * 1.25 + -0.5; }; })()
    : (() => { const m = mem(); return () => { let s = 0; for (let i = 0; i < 1000; i++) s += m[LEFT / 8 + i] * m[RIGHT / 8 + i]; return s; }; })();
  const time = g => { let best = Infinity; for (let r = 0; r < 9; r++) { const t = process.hrtime.bigint(); for (let j = 0; j < 20000; j++) g(); best = Math.min(best, Number(process.hrtime.bigint() - t) / 20000); } return best; };
  const w = time(f), j = time(js);
  console.log(`  time ${name.padEnd(18)} wasm ${w.toFixed(0)} ns  js ${j.toFixed(0)} ns  wasm/js ${(w / j).toFixed(2)}`);
}
process.exit(failures ? 1 : 0);
