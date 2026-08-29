# Nupp against Terra

Four numeric kernels, four implementations, one process.

- **Nupp `@aot`** — `src/kernels.nupp` built by the `terra-bench` target, which
  compiles each `@aot` entry to private C and calls it.
- **Nupp on LuaJIT** — the same source built by `terra-bench-scalar`, which
  leaves the same text to LuaJIT.
- **[Terra](https://terralang.org)** — `terra/kernels.t`, the same four kernels
  in Terra, compiled by Terra's own LLVM pipeline.
- **C** — `native/control.c`, built at `-O3`. The number a reader already has an
  intuition for, and what every ratio here is a ratio against.

```sh
./run.sh              # build all four, run the differential tests
./run.sh --bench      # and then measure
./run.sh --bench 25   # over twenty-five paired samples
```

`fetch.sh` downloads the pinned Terra release into `vendor/` the first time it
is needed; nothing else in this repository builds against Terra, so it is not a
`scripts/toolchain` component. `--json` before the sample count keeps the raw
per-sample rates, the bootstrap intervals and the toolchain identity, and
`NUPP_TERRA_BENCH_OUTPUT` writes that report to a file.

## Why these four kernels

They are chosen to disagree with each other. A single kernel would have reported
one of them as though it were the language.

| kernel | shape | what it is sensitive to |
| --- | --- | --- |
| `mandelbrot` | register-resident arithmetic behind a data-dependent branch | how well the inner loop was compiled |
| `advance` | one Euler step over 32-byte structs | memory bandwidth, barely anything else |
| `sumSquares` | a floating-point reduction | nothing may reassociate it, so all four should tie |
| `mix` | four xorshift rounds per element | integer throughput, freely vectorizable |

## Running Terra in the same process

Terra normally JIT-compiles into its own interpreter, and this benchmark does
not run there. Terra's release embeds Lua bytecode only its own LuaJIT can load
— `require("terra")` into the repository's LuaJIT fails in `strict.lua` before
anything else happens — and measuring the two Nupp routes needs the
repository's LuaJIT. The two cannot share an interpreter.

`terralib.saveobj` settles it. The kernels are compiled by exactly the pipeline
a JIT-compiled Terra function gets (`optimize` is `saveobj`'s sixth argument and
its default; passing `false` instead drops `saxpy` from 85 lines of vectorized
arm64 to 36 scalar ones) and are then reached over the same LuaJIT FFI boundary
as the C control. What separates the Terra column from the C column is therefore
the code generator, not the call — and the benchmark prices that boundary rather
than asserting it, in the single-element row below.

## Protocol

The one `bench/sha256` and `bench/simd-json` use. Implementations alternate
within a sample, so a machine that drifts drifts through all of them equally.
Call counts are calibrated per implementation to about fifty milliseconds a
sample, because the four here are two orders of magnitude apart at the extremes
and one element budget cannot serve them; a sample is therefore a throughput,
and the reported ratio is a bootstrap over the paired ratios of throughput.
Every implementation must agree on a size before any of them is timed.

Two things this harness had to get right that are worth repeating.

**Each implementation gets several copies of its input, cycled through by the
timing loop.** One buffer called over and over is not what a caller does, and it
is not what LuaJIT measures either: everything the Nupp source derives from its
argument is loop-invariant then, and the recorder hoists the whole call out of
the loop. The single-element `sumSquares` row read as 0.2 ns and three times the
speed of C, which is less than one call costs. The copies hold identical bytes
and differ only in address, so every call does exactly the same work; what they
deny the recorder is the proof that it already has the answer.

**`mandelbrot`'s pixels are in raster order.** An earlier draft walked the same
region of the plane in a scrambled order. It sampled the same mixture of fast
and slow pixels, so it looked equivalent, and it was not. A lane-parallel body
runs a group of four until the last of them escapes, so scattering neighbours
costs it the whole of what lanes are for — and Nupp is the only one of the three
compiled implementations that vectorizes this kernel at all. The scrambled order
was quietly measuring one implementation's optimization against data chosen to
defeat it. Scrambled, `@aot` reports 1.05x on the larger size; in raster order,
on the same machine and the same build, it reports 1.79x.

## Results

Apple arm64 (M5 Pro), Apple clang 21, Terra 1.2.2, LuaJIT 2.1.1785763465,
fifteen paired samples. Committed at `results/arm64-macos.json` with the
per-sample rates and the bootstrap intervals.

Throughput, and the ratio against the colocated C control:

| kernel | elements | Nupp `@aot` | Nupp on LuaJIT | Terra | C |
| --- | ---: | ---: | ---: | ---: | ---: |
| `mandelbrot` | 1 024 | 66.6 (**1.374x**) | 18.4 (0.379x) | 48.2 (0.995x) | 48.3 Mpixel/s |
| `mandelbrot` | 262 144 | 78.2 (**1.785x**) | 19.3 (0.446x) | 43.3 (0.989x) | 43.8 Mpixel/s |
| `advance` | 1 024 | 1524 (0.998x) | 1194 (0.780x) | 1514 (0.990x) | 1528 Melement/s |
| `advance` | 262 144 | 1510 (1.000x) | 1199 (0.793x) | 1504 (0.995x) | 1511 Melement/s |
| `sumSquares` | 1 024 | 2372 (0.995x) | 1686 (0.707x) | 2379 (1.000x) | 2381 Melement/s |
| `sumSquares` | 262 144 | 2013 (1.001x) | 1671 (0.831x) | 2006 (0.999x) | 2009 Melement/s |
| `mix` | 1 024 | 2649 (1.000x) | 746 (0.282x) | 2659 (1.005x) | 2646 Melement/s |
| `mix` | 262 144 | 2671 (1.006x) | 753 (0.284x) | 2654 (1.000x) | 2654 Melement/s |
| **geometric mean against C** | | **1.119x** | **0.515x** | **0.997x** | 1.000x |

Every interval is tight. The widest on any compiled route is `sumSquares` at
1 024, where `@aot` is 0.995x with a 95% bootstrap interval of [0.993, 1.001];
`mandelbrot`'s two are [1.367, 1.376] and [1.783, 1.793]. A second independent
run of the whole table agrees with this one to within 3.8% on its worst row and
within about 1% on every headline number.

### Nupp `@aot` matches C and Terra, and beats them where it vectorizes

On three of the four kernels the three compiled routes are the same number:
every ratio between 0.989x and 1.006x, which is where two `-O3` transcriptions
of one loop belong. That is the result the benchmark was built to check, and
`sumSquares` is the strongest form of it — a floating-point accumulator is a
dependency chain, no implementation here may split it across lanes, and none
does, so 0.995x and 1.000x are three compilers agreeing about arithmetic they
were all forbidden to reorder.

`mandelbrot` is the exception, and it goes Nupp's way: 1.37x at 1 024 pixels and
1.79x at 262 144. `nupp aot` reports the reason without being asked —

```text
src/kernels.nupp: mandelbrot, kernel, 4.50 operations per byte (72 over 16), mixed4, 4 lanes
```

— and disassembling the other two confirms the other half of it. Neither clang
nor Terra vectorizes `tbMandelbrot`: the loop exits on a data-dependent
condition, which is not a shape either auto-vectorizer will take. Nupp's backend
turns the `if` into a mask and the `break` into a lane retiring from the loop,
so it runs four pixels at a time on a loop LLVM leaves scalar. Nothing in the
source asks for this, and the same source on LuaJIT is 0.45x.

The gap widens with size, and not because of the call: a 1 024-pixel
`mandelbrot` call runs about 15 microseconds, so the boundary priced below is a
hundredth of a percent of it. It is the same mechanism as the raster-order
finding above. These sizes are square grids over one region of the plane, so
1 024 pixels is 32x32 and 262 144 is 512x512, and neighbours in the larger grid
are sixteen times closer together. Closer neighbours escape on more nearly the
same iteration, a group of four retires more nearly together, and the lanes
waste less. Lane lowering is worth more on the finer grid because that is where
the coherence it depends on actually is.

### What the compiled entry costs to call

The single-element `sumSquares` row leaves almost nothing in the call but the
call:

| implementation | ns/call at one element |
| --- | ---: |
| Nupp `@aot` | 4.2 |
| Nupp on LuaJIT | 4.0 |
| Terra | 2.3 |
| C | 2.2 |

Entering a compiled Nupp entry costs about 1.9 ns more than a bare LuaJIT FFI
call to the same work — the generated binding and the span arguments. That is
half a percent of the 1 024-element rows at worst and invisible at 262 144,
which is what makes those rows readable as measurements of the loop. It is also why `@aot` is
*slower* than plain LuaJIT on a one-element call: at that size the compiled
route pays for a boundary the interpreted one does not cross.

### Nupp on LuaJIT is worth between a quarter and all of C

0.282x to 0.831x, and the spread is not noise — it is how much of each kernel is
memory. `mix` is integer arithmetic on cache-resident data and the interpreter
has nowhere to hide: 0.28x. `sumSquares` over 262 144 doubles spends much more
of its time waiting on memory, and the interpreter waits exactly as long as the
compiled code does: 0.83x. `advance` sits between them at 0.78x.

The reading is that the LuaJIT route's cost is real work per element, so it
disappears as soon as something else is the bottleneck. Where a kernel is
bandwidth-bound, `@aot` buys nearly nothing over plain Nupp, and this benchmark
would rather say so than average it away.

### Terra is C

0.989x to 1.005x across eight rows, geometric mean 0.997x. Both are LLVM given
the same loops, so this is the control on the control: a column that came out
anywhere else would have meant the harness was measuring the boundary or the
data rather than the code.

One real difference is left in rather than papered over. Terra has no
`restrict`. Nupp's `exclusive` spans carry the alias proof into the generated C
and `native/control.c` writes it by hand, so on `advance` and `mix` — the two
kernels whose output could in principle alias their input — Terra is compiling a
weaker promise than the other two. It does not appear to cost it anything here.

## Two things the Nupp compiler got wrong

Both were found writing these kernels, and both are fixed. They are recorded
here because what a benchmark turns up on its way to a number is worth as much
as the number, and because the shape of this directory still shows one of them.

**A kernel that read only a span's length emitted C that would not compile.**

```nupp
@aot
local function lengthOnly(borrows values: span.Span<number>): number
    return #values
end
```

`nupp check` was clean and `nupp aot` reported an admitted kernel. `nupp build`
failed, because the length lowers to a separate `count_values` parameter,
nothing then read `p_values`, and generated C is compiled `-Werror`. The build
error named a line of C the author never wrote. The emitter now marks a span
pointer the finished IR never dereferences `KS_UNUSED` — read off the final IR
rather than recorded during lowering, because the optimizer runs in between and
may be what removed the last read. It says the parameter *may* go unread rather
than that it does, so a pointer the IR still uses and the emitter drops is
caught by the same `-Werror` as before.

This benchmark wanted exactly that function, to price its own call boundary.
The single-element `sumSquares` row is what it did instead, and it stays: real
work through the real ABI is a better boundary price than a kernel that does
nothing.

**An index nothing proved in range crashed the compiler instead of being
refused.**

```nupp
for i = 1, 1 do
    total = values[i]
end
```

The loop bound is not `#values`, so nothing relates the index to the span.
Refusing it is right; the way it refused was not — `luajit: unbounded load
index` and a stack traceback into `compiler/aot/compile.lua`, with no source
position in it. The IR verifier had caught it, and the verifier raises rather
than reports, because reaching one of its rules is supposed to mean a compiler
bug rather than a bad program.

Looking for the hole turned up a second one beside it. The load checked that
the counted loop bounded the span it read, the store checked nothing at all,
and neither noticed a loop whose bound was not a span count in the first place.
So `for i = 1, #other do out[i] = other[i] end` — a store through a span the
loop does not count, which is a real soundness refusal — reached the verifier
too, as `invalid store root`. One shared proof now serves both, and all four
shapes are refused against the line that wrote them:

```text
uncounted.nupp:7:17: aot: the loop's bound is not a span count, so nothing proves values is that long; count the loop with for i = 1, #values
crosswrite.nupp:9:9: aot: the loop counts other, so nothing proves out is that long; guard it with assert(#other == #out)
```

## What the differential tests cover

`tests/run.lua` runs all four over sixteen sizes and requires them to agree
exactly, not to a tolerance. None of these kernels is specified loosely: Nupp's
arithmetic is binary64, neither contracted nor reassociated; the C control is
built `-ffp-contract=off`; and Terra is asked for no relaxation either. So the
same program over the same bytes has one answer and all four produce it — 260
checks, including the `%a` bit patterns of every `float` `advance` writes.

The sizes are chosen around the edges of the lane-lowered loops rather than for
being round — 0, 1, 2, 3, 4, 5, 7, 8, 9, 16, 17, 63, 64, 65, 1 000, 1 024. A
kernel that lowers four lanes at a time has a vector body and a scalar tail, and
a length that is a multiple of four never runs the tail. Each kernel is then
required to write something non-trivial at a real size, because four
implementations agreeing on nothing is not agreement.

## One thing the source had to say twice

`mix` is written with its four xorshift rounds unrolled. Written as a loop —

```nupp
for _ = 1, 4 do
    state = state ~ (state << 13)
    ...
end
```

— it compiles, and `nupp aot` declines to lower it lane-parallel:

```text
src/kernels.nupp: mix, kernel, 6.00 operations per byte (48 over 8), none, ran one iteration at a time
```

Lane lowering takes a body that is one top-level numeric map loop, and a nested
loop inside the body is not that shape. Unrolled, the same arithmetic reports
`mixed4, 4 lanes`, which is how it is written here. Clang and Terra
unroll their own four-round loops without being asked, so all three
implementations here are written unrolled and the comparison is of one program;
the constraint is Nupp's and it is recorded here rather than hidden in a ratio.
