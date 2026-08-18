# Optimization

Nupp leaves ordinary hot-path optimization to LuaJIT; its own passes target
startup work and facts available only to the checker. A pass lands only with a
LuaJIT-enabled benchmark and a static proof that it preserves behavior. The
design catalog is
[`plans/014-optimizations.md`](../../plans/014-optimizations.md), and
[LuaJIT trace checking](jit-trace-checking.md) finds recorder blockers.

```bash
nupp build -O1
nupp run -O1 --remarks app.nupp
```

`-O1` turns the catalog on; `--remarks` reports what each pass rewrote, or
looked at and declined to rewrite.

## Levels

    nupp build -O1
    nupp run -O1 app.nupp

`-O0`, the default, rewrites nothing: its generated Lua is the language
semantics with types erased. `-O1` enables every current pass; `-O2` means the
same today and reserves room for a stronger tier later. The level is part of the
build key, so changing it triggers a cold build.

## Passes

| Code | Name | Level | Rewrite |
| --- | --- | --- | --- |
| `OPT-1` | `presize` | -O1 | Size an empty table for the writes about to follow |
| `OPT-2` | numeric-ipairs | -O1 | Use a numeric loop for a proved stable dense array |
| `OPT-3` | constant-fold | -O1 | Fold exact primitives, branches, dead loops, and immutable paths |
| `OPT-4` | static-callable | -O1 | Bind repeated immutable dotted callees at first use |
| `OPT-5` | concat-buffer | -O1 | Append to a string.buffer instead of rebuilding a string each pass |
| `OPT-6` | indexed-range | -O1 | Select proved direct access and scalar-replace indexed views |

Each pass is specified with its Nupp source and generated Lua in the
Performance guide; this page is the machinery around them.

## Benchmark details

Fresh local medians with LuaJIT enabled, measuring the generated-Lua shapes each
pass produces rather than checker time.

| Pass and scenario | Before | After | Change |
| --- | --- | --- | --- |
| OPT-1, 200,000 tables, four named fields | 0.0159s | 0.0053s | 3.02x faster |
| OPT-1, 200,000 tables, eight hash fields | 0.0262s | 0.0106s | 2.47x faster |
| OPT-1, 200,000 tables, four array slots | 0.0168s | 0.0024s | 7.06x faster |
| OPT-2, eight million visits, 4-element arrays | 0.0126s | 0.0087s | 1.44x faster |
| OPT-2, eight million visits, 32-element arrays | 0.0053s | 0.0050s | 1.06x faster |
| OPT-2, eight million visits, 256-element arrays | 0.0051s | 0.0047s | 1.07x faster |
| OPT-3, 20,000 primitive expressions, load and run | 0.0039s | 0.0024s | 1.64x faster |
| OPT-3, 20,000 nested paths, load only | 0.0095s | 0.0025s | 3.82x faster |
| OPT-3, 20,000 nested paths, load and run | 0.0099s | 0.0025s | 3.95x faster |
| OPT-4, 20,000 dotted calls, load only | 0.0027s | 0.0011s | 2.54x faster |
| OPT-4, 20,000 dotted calls, load and run | 0.0030s | 0.0012s | 2.53x faster |
| OPT-6, 8 million struct element updates | 0.01075s | 0.00735s | 1.46x faster |
| OPT-6, SoA projected update vs handwritten columns | 0.00296s | 0.00307s | 1.037x of direct |
| OPT-6, 500,000 slice constructions | 0.12183s | 0.00425s | 28.7x faster |

Primitive folding reduced its generated input by 32.1%, nested propagation by
60.8%, static callable binding by 63.6%; warmed results were 0.99x, 2.01x, and
1.06x. Hot results are workload- and trace-dependent, so the reliable constant
and callable wins are smaller source and cold startup.

    luajit bench/presize.lua
    luajit bench/numeric-ipairs.lua
    luajit bench/constant-folding.lua
    luajit bench/constant-propagation.lua
    luajit bench/static-callable.lua
    bench/span-range-lowering/run.sh

Three more decide whether a pass is worth writing at all:

    luajit bench/ffi-hoisting.lua
    luajit bench/concat.lua
    luajit bench/scratch-reuse.lua

`concat` argued for `OPT-5` and now guards it. The others argued against passes
that are therefore not here: caching a ctype is the interpreter's win alone,
though the clib symbol binding `ffi-hoisting` also measures is real and already
emitted, and hoisting a loop-local table or `ffi.new` out of its loop is slower
than letting allocation sinking handle it. All three exit non-zero if their
finding stops holding.

The `OPT-6` rows compare the pass disabled against enabled on an arm64 Apple
host after warmup, where the optimized trace matched handwritten direct FFI in
counted IR shape and timing. The benchmark adapts the position/velocity kernel,
the repository having no production hot loop written with a same-function
witness. The slice figures are evidence for narrow derived-view scalar
replacement, not general table escape analysis. The committed
[`span-range-lowering` results](../../bench/span-range-lowering/README.md) have
the full Span, heap, SoA, dirty-acquisition, and trace matrix, and
`bench/span-range-lowering/trace.sh` prints the opcode-category comparison.

## Inspecting and controlling passes

    nupp build -O1 --remarks
    nupp build -O1 -Zno-opt=OPT-2

`--remarks` reports both successful rewrites and declined proofs, including the
source location that stopped an analysis. Remarks never fail a build; they come
from `build` and `run`, and `check` does not optimize. `-Zno-opt=CODE` disables
one pass for miscompile bisection — the codes are stable, the `-Z` spelling is
an unstable debugging interface — and `-O0` disables every rewrite.

## Observable behavior

Passes preserve answers. One that trades a non-answer guarantee for speed must
explicitly check a named `--relax` or `@relax` permission; `OPT-6` requires
`frames`. The compiler fixpoint verifies that compiling the compiler at `-O1`
produces output byte-identical to compiling it at `-O0` while its guarantees are
held.

## Next

- [Comptime types](../type-system/type-level-computation.md): the `const` binder
  `OPT-3` reads.
- [Profiling](profiling.md): where the time actually goes, before deciding a
  pass would help.
