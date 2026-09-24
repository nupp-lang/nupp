# Direct native backend spike (2026-09-23)

Throwaway evidence for `~/projects/nupp-plans/todo/direct-native-backend.md`.
Not for merging.

## What it does

`direct-backend/` lowers five `bench/simd11` kernels from Nupp's AOT IR
straight to AArch64 -- no middle IR -- allocates registers with `regalloc2`
0.15.2, encodes with a hand-written encoder, loads the bytes with a 42-line
relocation-free loader (map, copy, protect, flush), and calls them through
the platform ABI exactly as LuaJIT calls the C entries today. Every result is
checked bit-for-bit against the C backend's own output built by clang at
`-O3` (algebraic sums within 1e-12), for n = 0..17, 63, 1000 and 65,539, then
timed against it.

The IR comes from `nupp aot --format json` with `NUPP_SPIKE_IR_TREE=1`, a
one-line hook in `src/nupp/compiler/cli/aot.nupp` that adds each program's
structured tree to the JSON.

```sh
NUPP_SPIKE_IR_TREE=1 ./bin/nupp aot --features neon --format json \
    bench/simd11/kernels.nupp > spike/direct-backend/kernels.json
(cd spike/direct-backend && cargo build --release && cargo test --release)
./build/rust/target/release/nupp-direct-backend-spike spike/direct-backend/kernels.json [KERNEL-to-disassemble]
```

## Result (Apple ARM64, loaded machine, unqualified)

| kernel | words ours / clang | n=63 | n=1000 | n=65,539 |
| --- | --- | ---: | ---: | ---: |
| `map` (scalar) | 16 / 37 | 2.99 | 2.04 | 2.59 |
| `refine` (scalar) | 48 / 23 | 1.17 | 1.15 | 1.15 |
| `explicitMap` | 104 / 148 | 1.05 | 0.99 | 1.00 |
| `explicitRefine` | 192 / 238 | 1.04 | 1.03 | 1.02 |
| `explicitAlgebraic` | 124 / 151 | 1.24 | 1.03 | 1.02 |

Ratios are our time over clang's; each is the median of 21 alternating
samples. Compile time, lowering through encoding, is 0.1-0.3 ms per kernel.

- Explicit SIMD reaches parity. The species-as-register-pair legalization
  keeps `fixed4` values in registers: no spills in any kernel.
- Scalar `map` loses 2-3x because clang auto-vectorizes it; that is the
  expected, policy-consistent loss.
- Scalar `refine` is 1.15x: clang's inner loop is tighter (it merges the
  loop test into the body with `fccmp` differently and keeps fewer copies).
- `explicitAlgebraic` at n=63 is 1.24x; the loop is at parity, the remaining
  cost is in the short-array path.

## What parity took

In order, each measured:

1. Constants defined once in the entry block (no reload per iteration).
2. Rotated loops: guard, then a bottom test, one branch per iteration.
3. Tree-pattern selection of `a < b and c < d` into compare, conditional
   compare, one branch (`ccmp`/`fccmp`). `refine` 1.45x -> 1.15x.
4. 2x unroll of straight-line vector loops (stand-in for the IR transform the
   plan moves out of the C emitter).
5. Pointer induction variables: accesses become `[ptr, #off]`, pointers
   advance once per iteration. `explicitMap` in cache 1.23x -> 0.99x. This is
   the one genuine optimization the backend needed.
6. Prefix-mask tails: a mask known to be `simd_tail(n)` loads and stores by
   count instead of per-lane tests.

## Answers to the plan's open items

- **No middle IR:** confirmed. `lower.rs` walks the structured IR once,
  building SSA through block parameters from the IR's own `carried` lists.
- **Restricted-signature platform ABI:** confirmed; entries are called
  directly with the C signature. Apple arm64 argument assignment was two
  counters.
- **Relocation-free image:** confirmed; constants live in a PC-relative pool
  after the code, all branches are internal, and the loader is 42 lines.
  (These kernels import nothing, so import slots were not exercised.)
- **Item 5, borrow the AArch64 encoder:** `dynasm-rs` 3 encoded all fifteen
  NEON and conditional-compare forms the backend selects with run-time
  registers (`spike/dynasm-probe`), and each word matches the encoder that is
  checked against the system assembler. Viable.
- **regalloc2 constraints that shaped lowering:** SSA with block parameters,
  no critical edges (every conditional branch targets fresh single-predecessor
  blocks, forwarded away at emission when regalloc leaves them empty),
  reuse-def for destructive `bsl`, early defs for multi-instruction loads.

## Size

2,223 lines of Rust: lowering 996, emission 352, encoder 335 (+112 lines of
assembler-checked tests), machine IR and the `regalloc2` bridge 176, loader
42, driver 210. It covers about 35 IR operations on one target.
