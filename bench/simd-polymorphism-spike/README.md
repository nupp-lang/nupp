# Width-polymorphic SIMD spike

This spike tests the useful core of Thermite's technique without adding Rust,
LLVM, ISPC, or a production language feature to Nupp:

- describe an operation once against a portable vector algebra;
- instantiate scalar, NEON, SSE2, and AVX2 implementations from it;
- select the best host implementation once at the whole-span boundary; and
- run every ragged tail through the same one-lane scalar expression.

The first operations are Tecs-shaped bitset predicates. `overlaps` reduces
`left & right` with `any`, while `contains_all` reduces `right & ~left` and
negates the result. Both read contiguous `uint32_t` words, which makes this a
clean test of the execution model without conflating it with the 28-byte stride
of `Transform2D`.

## Build and run

From the repository root:

```sh
bench/simd-polymorphism-spike/build.sh
luajit bench/simd-polymorphism-spike/main.lua
./bin/nupp check bench/simd-polymorphism-spike/checked.nupp
```

`SIMD_SPIKE_WORDS` controls approximately how many words each benchmark row
examines. The default is sixteen million. Counts from zero through 65 are
checked before timing, which covers every NEON, SSE2, and AVX2 tail length and
places a decisive bit in the final scalar or vector group.

## What is generated

[`generate.lua`](generate.lua) constructs two expression graphs from `input`,
bitwise `and`/`not`, and an `any` reduction. Backend renderers instantiate those
graphs as:

- one-lane scalar C, with Clang vectorization disabled;
- four-lane AArch64 NEON;
- four-lane x86-64 SSE2; and
- eight-lane x86-64 AVX2.

A process-wide atomic caches host selection. AArch64 selects mandatory NEON;
x86-64 checks AVX2 once and otherwise uses its SSE2 baseline. Public calls take
only pointers and a word count, so no width-dependent value crosses the ABI.
The x86 build explicitly fixes the translation-unit baseline at `x86-64`, so
compiler defaults cannot leak newer instructions into the SSE2 path. The
generated source lives under the ignored `build` directory.

This is the Thermite-shaped invariant worth testing: width and ISA belong to a
specialization of the operation, not to the values its caller sees.

## Representative result

One longer run on the ARM64 development host, with `SIMD_SPIKE_WORDS=64000000`,
selected the four-lane NEON backend and measured the exhaustive `overlaps` case
as follows. These are mechanism-spike numbers, not a performance contract.

| Words per call | LuaJIT | Native scalar | Polymorphic NEON |
| ---: | ---: | ---: | ---: |
| 1 | 7.8 ns | 2.2 ns | 2.7 ns |
| 8 | 18.6 ns | 7.9 ns | 4.8 ns |
| 64 | 105.6 ns | 52.5 ns | 11.2 ns |
| 2,048 | 2,552.9 ns | 1,256.1 ns | 324.7 ns |

The important result is the shape rather than a single ratio. Dispatch and the
scalar tail make a one-word call slightly slower than calling scalar C
directly. By eight words the same generated plan is faster than both scalar C
and traced LuaJIT. At 64 words it is about 4.7 times faster than scalar C and
9.4 times faster than the LuaJIT loop. The large row remains useful, but memory
traffic increasingly determines its result.

## What it does not prove

This is not a Nupp SIMD API. It has only two reductions over `uint32` inputs,
and Clang still supplies instruction encoding, register allocation, and object
generation. The symbolic graph is build-time Lua rather than a sealed Nupp
materializer.

The benchmark deliberately includes one-, eight-, and 64-word calls as well as
a 2,048-word field. Real archetype signature bitsets are often short enough
that an FFI call can cost more than vector execution saves. The large row shows
throughput; the short rows decide whether this belongs behind every Tecs bitset
operation.

The next positive experiment would make the same IR a sealed comptime provider
and add a mapping operation with `f32` inputs, stores, uniform parameters, and
`select`. A negative result on the short bitset rows would not invalidate that
experiment: whole component columns amortize their boundary very differently.
