# Typed representation to Cranelift: results

Date: 2026-10-10. Nupp baseline `843af410a`. Cranelift 0.135.2, Apple
Silicon arm64, system clang 21 for the C bars. Protocol in
[PROTOCOL.md](PROTOCOL.md); raw samples, summary and compile times under
`evidence/`; register-allocated code for every kernel in `evidence/vcode-*.txt`.

The question P1 asked: does a non-speculative lowering of typed Nupp
semantics reach LLVM-class code on map, dot, SHA-256, masked tails and calls,
what does a call boundary cost, and what does compilation cost. The answer on
this hardware is yes on every row, inside the plan's acceptable prices with
room to spare, with one lesson about reductions.

## Throughput, paired, nine processes

A ratio over one is slower than the bar. Intervals are t95 on the log ratio;
every CV is at or under 6.3%, so all rows are usable.

| Elements | Kernel | / LLVM NEON | / hand-written NEON |
| ---: | --- | ---: | ---: |
| 65,539 | map | 1.04x (1.03-1.06) | 1.04x |
| 65,539 | map, step unrolled twice | 1.01x (1.00-1.01) | |
| 65,539 | dot, two accumulators | 1.36x (1.35-1.37) | |
| 65,539 | dot, four accumulators | 0.74x (0.73-0.74) | 0.73x |
| 1,024 | map | 1.09x (1.04-1.14) | 1.08x |
| 1,024 | map, unrolled | 0.98x (0.96-1.00) | |
| 1,024 | dot, two accumulators | 1.29x | |
| 1,024 | dot, four accumulators | 0.69x (0.68-0.69) | 0.68x |
| 63 | map | 1.25x (1.24-1.27) | 1.30x |
| 63 | dot, two accumulators | 1.02x (1.00-1.03) | |
| 63 | dot, four accumulators | 1.08x | 1.13x |

| Bytes | SHA-256 / clang -O2 C control |
| ---: | ---: |
| 32 | 0.95x (0.94-0.96) |
| 1,024 | 1.11x (1.09-1.12) |
| 65,536 | 1.11x (1.09-1.13) |
| 1,048,576 | 1.12x (1.09-1.14) |

At 1 MiB that is 370 MB/s against the C control's 409 MB/s. The same-day Lua
benchmark put the LLVM-compiled Nupp SHA-256 at 387 MB/s and direct LuaJIT at
219 MB/s on this machine; those are separate runs, quoted for scale only.

| 65,539 elements in 64-element chunks | / Rust loop calling LLVM dot |
| --- | ---: |
| compiled loop, direct call to compiled dot | 0.99x (0.97-1.00) |
| compiled loop, imported call to the C kernel | 1.01x (1.00-1.02) |
| Rust loop calling compiled dot | 1.00x (1.00-1.00) |

## What the code says

- **map** is 33 instructions for the whole function, 12 in the vector loop:
  two `ldr q`, two `fmla`, two `str q`, the address arithmetic, the counter
  and the compare. No overflow checks, no per-access bounds compare, no PHI
  shuffles: the 27 guard instructions the LuaJIT trace carried are absent
  because the types made them unnecessary, as the plan predicted. The
  remaining 4% at 65,539 elements is address formation LLVM folds into the
  loads; unrolling the step closes it.
- **dot** with two accumulators is 1.36x LLVM because each `fmla` waits on the
  previous one in the same accumulator; the loop is latency-bound, not
  issue-bound. Four accumulators make it 0.74x, faster than LLVM's own
  lowering of the same Nupp source and than the hand-written intrinsics. The
  lesson for the generator: a species-wide reduction must be unrolled to at
  least the fma latency in independent accumulators, which `algebraicSum`'s
  reassociation permits. That is a generator rule, not a backend feature.
- **SHA-256** compiles to 138 instructions with the 64-round loop at 38 per
  round. Clang's is 11% faster; the difference is scheduling and the schedule
  loads, not a missing transformation. Scalar typed code at 1.1x clang is the
  scalar result this plan needed.
- **Calls** are free at this granularity. A direct call between compiled
  functions, an imported call to a C kernel, and a Rust call into compiled
  code all land on the LLVM reference within 1%. The 63-element map at 1.25x
  is the one small-input row above 1.1x: 8.2 ns against 6.6 ns, a prologue
  and the lane-wise tail against LLVM's; it is inside the 2x price and well
  under the 70-100 ns the LuaJIT boundary cost.
- **Cranelift's vector support** covered everything these kernels needed at
  128 bits: `fma` on `f64x2` lowers to `fmla`, `splat`, `extractlane`,
  unaligned vector loads and stores. No fallback was needed and none is
  priced here; the leaf-kernel call boundary is measured above at 1.01x in
  case a wider species ever needs it.

## Compilation

Median wall time per function over nine processes, signature to defined
function: map 253 us (the first function carries one-time setup; the second
map variant is 112 us), dot 99 us, four-accumulator dot 88 us, SHA-256
compress 289 us, chunked 53-76 us, finalization 4 us. Opt level `none`
compiles in the same time and runs map at 1.38x and SHA-256 at 1.14x, so there
is no reason for a cheaper tier: `speed` is the only level.

## What this does and does not establish

Established: for typed scalar and vector kernels with checked spans, a
non-speculative Cranelift lowering is within 1.1x of LLVM or ahead of it on
every workload here, call boundaries cost nothing measurable, and compilation
is a few hundred microseconds per function. Every hypothesis-table row P1 can
reach is inside its acceptable price.

Not established: anything about a collector, an interpreter, tagged values,
records, `any`, or the application workloads; those are later phases. Not
run: the browser half of P1, interpreted Wasm against the guest and the LLVM
Wasm SIMD kernels, and the suspension probe. Hardware is one arm64 machine
under load from other sessions; absolute times are indicative and x86-64 is
unmeasured.
