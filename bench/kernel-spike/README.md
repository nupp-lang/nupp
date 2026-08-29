# Checked native-kernel spike

This spike answers three separate questions instead of treating "native" and
"SIMD" as synonyms:

1. Does one FFI call over a whole column beat a traced LuaJIT loop?
2. Does Clang vectorize the friendly `{x, y}` array-of-structs layout?
3. Can DynASM deliberately emit the same NEON loop and specialize a less
   friendly runtime stride?

It is deliberately ARM64-only. DynASM supports ARM64 control flow, relocation,
and scalar floating-point instructions, but its ARM64 instruction table still
marks SIMD as TODO. Six fixed NEON instructions are consequently emitted as
`.long` values. This is useful evidence about implementation cost: using
DynASM does not by itself provide a portable SIMD abstraction.

## Build and run

Use the `dynasm` directory from an official LuaJIT v2.1 checkout:

```sh
git clone --depth 1 --branch v2.1 https://github.com/LuaJIT/LuaJIT.git /tmp/luajit
DYNASM_ROOT=/tmp/luajit/dynasm bench/kernel-spike/build.sh
luajit bench/kernel-spike/main.lua
./bin/nupp check bench/kernel-spike/checked.nupp
bench/kernel-spike/performance-gate.sh
```

This spike was tested with LuaJIT revision
`1edc3e52b67eaf6ce5f809be8e17d6862594b8bc`. DynASM is a build-time input;
the resulting library does not depend on it at runtime.

`KERNEL_COUNT`, `KERNEL_PASSES`, and `KERNEL_SAMPLES` control the benchmark.
The default is 262,144 rows, enough passes to process at least four million rows,
and the median of five samples after four warmups. Counts zero through
seventeen are checked separately so every SIMD-tail length and the zero case
execute before timing. The generated mapping is also searched for all six
expected NEON instruction words.

The generated code uses W^X memory: it maps writable, asks DynASM to encode,
flushes the instruction cache, and then changes the mapping to read/execute.
That works for the ordinary macOS command-line host used by this spike. A
production hardened Apple host needs the platform's `MAP_JIT` and JIT-write
policy integrated with the existing LuaJIT host.

## Compared paths

- A traced LuaJIT loop over FFI arrays.
- Native scalar C with vectorization and interleaving explicitly disabled.
- The same scalar-looking C loop with Clang's optimizer enabled.
- A DynASM loop containing deliberate four-wide NEON `ld2`, `fmla`, and `st2`.
- A runtime-specialized DynASM scalar loop with `Transform2D`'s 28-byte stride
  and field offset embedded as instruction immediates.

Every path receives identical initialized data and is checked before timing.
This is a mechanism spike, not a stable benchmark or proposed public API.

## What worked

On an Apple ARM64 development machine, one representative 262,144-row run
measured 0.330 ms for LuaJIT, 0.151 ms for scalar native C, 0.091 ms for
Clang's vectorized C, and 0.092 ms for the four-wide DynASM kernel. That is
roughly 3.6x over the LuaJIT loop for the cache-friendly case and shows that
the generated instructions are genuinely competitive with an optimizing C
compiler there. Kernel generation took tens of microseconds and emitted 112
bytes of integrate code.

Nupp now puts a bounds-carrying checked boundary around the call.
`countedBy(count)` turns each physical borrowed pointer/count declaration into a logical
`WriteSpan<Position>`, `Span<Velocity>`, and `float` wrapper, checks equal
logical lengths, projects adjusted pointers, and performs one physical call.
The raw binding is hidden in generated Lua.

## What did not

The result is not a general SIMD facility. ARM64 DynASM cannot spell these
vector instructions, so raw opcodes are architecture-specific and fragile.
At 1,048,576 rows, a longer run measured 0.634 ms for Clang and 0.641 ms for
DynASM. Results varied in both directions between runs because the loop was
largely measuring memory traffic; hand-emitted code did not open another large
speed tier. For Tecs' 28-byte `Transform2D` stride, the runtime-specialized
DynASM loop remained scalar. It removed dynamic stride and offset work but was
only about three percent faster than scalar C in that large run.

Nupp can recursively partition one writable token into sibling regions, but it
still does not prove arbitrary independently obtained ranges disjoint, dispatch
by CPU feature, or validate a generated instruction stream. DynASM alone
supplies none of those remaining pieces.

DynASM is from LuaJIT and is MIT licensed. Its source is not vendored here;
`DYNASM_ROOT` makes the exact toolchain input explicit.

`performance-gate.sh` performs two clean optimized Nupp builds. Each run
alternates generated/handwritten order, warms four times, takes 15 paired
samples with at least 100 ms per batch, enforces a 1.05 median ratio at 262,144
and 1,048,576 rows, and caps the zero-count added median at 50 ns per call.
