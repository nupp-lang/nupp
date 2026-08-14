# Checked native-C subset spike

This spike tests ordinary Nupp as the source language for a verified native IR
that emits private scalar C. Clang, rather than a hand-written intrinsic
backend, chooses unrolling, vector width, instruction selection, register
allocation, and tail handling.

`@kernel` remains a test-only custom annotation. The production design calls
the compilation contract `@native`.

## Build and run

```sh
bench/kernel-subset-spike/build.sh
luajit bench/kernel-subset-spike/test.lua
luajit bench/kernel-subset-spike/main.lua
```

The build writes ignored native IR, generated C, a checked `countedBy` binding,
the compiled library, and the ordinary Lua lowering under `build/`.

## Implemented subset

One annotated map function may currently use:

- any number of `exclusive WriteSpan<float>` outputs;
- one or more shared `Span<float>` inputs, which may alias each other;
- erased `float` uniforms represented as binary64 at the native ABI;
- a complete equal-count guard and one one-based loop;
- numeric and boolean locals without mutation or shadowing;
- `+`, `-`, `*`, `/`, comparisons, boolean `and`/`or`/`not`, and unary minus;
- structured `if`/`elseif`/`else`, scoped `do`, `break`, and `continue`;
- any number of stores to writable spans at the active loop index;
- pure, statically resolved helpers whose bodies are one return expression; and
- `math.sqrt`, `abs`, `floor`, `ceil`, `min`, and `max` as closed intrinsics.

Unsupported syntax is a source-local hard error. There is no silent Lua
fallback for an annotation the native compiler accepted.

The example uses two writable outputs, two potentially aliasing inputs, a local
value, a static clamp helper, `math.min`, `math.max`, `math.sqrt`, and a branch.
It therefore exercises the structured statement IR rather than recognizing one
fixed expression tree.

## Safety and semantics

Every span receives a region identity. The verified alias matrix requires every
pair containing a writable span to be disjoint and records shared input pairs
as potentially aliasing. Generated C marks each writable pointer `restrict` and
never restricts a shared input.

Loads explicitly widen `float` storage to binary64, ordinary Nupp arithmetic is
performed in binary64, and stores narrow once to `float`. The math min/max
helpers reproduce LuaJIT's ordered-argument behavior for equal values, signed
zero, and NaN rather than substituting C `fmin`/`fmax` semantics.

Correctness compares result bits across ordinary Nupp, a raw LuaJIT loop, C with
vectorization forcibly disabled, and optimized generated C. Inputs include
deterministic random mantissas, signed zero, subnormals, infinities, and NaNs.

## Generated paths

The same verified statement IR emits two functions:

- a forced-scalar C oracle with Clang vectorization and interleaving disabled;
- an ordinary scalar C loop compiled with optimization enabled.

The checked binding calls the optimized function. No explicit NEON, SSE, or AVX
tree is generated. Inspection of the optimized object answers whether Clang
vectorized a particular source loop.

## Remaining boundary

This is still a map-loop prototype, not a production compiler pass. It does not
yet admit outer structured control flow, mutated locals, arbitrary numeric loop
bounds, fixed C arrays, reified structs, multiple return values, status-return
errors inside the loop, helper statement bodies, several annotated functions in
one unit, or native-to-native module calls.

Those features now extend a statement IR and C emitter rather than requiring
new target-specific SIMD backends. Fixed arrays and reified structs still need
checked layout metadata; errors need explicit status and source-site values;
multiple results need compiler-owned result structs. Allocation, Lua tables,
strings, dynamic calls, closures, metamethods, coroutines, and arbitrary FFI
remain outside the direct native subset.

For this experiment, using the annotation makes Clang a conditional build
dependency. Programs without native functions do not require or probe Clang.
