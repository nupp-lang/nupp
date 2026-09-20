---
order: 631
---

# CPU AOT kernels

CPU AOT lowers verified numeric and span functions to C, then binds the
compiled entry at module load. Inspect the report before measuring a kernel so
the scalar and lane choices are explicit.

This is `bench/kernel-subset-spike/mandelbrot.nupp`, trimmed to its shape. It is
ordinary Nupp: [spans](nupp.mem.span),
[structs](../../language/types/records-and-structs.md), a `while` loop with a
`break`.

```nupp
local span = nupp.mem.span

local struct Point
    re: float
    im: float
end

local struct Escape
    iterations: int32
    escaped: uint32
end

@relax("fp-contract")
@aot
local function mandelbrot(
    exclusive escapes: span.WriteSpan<Escape>,
    borrows points: span.Span<Point>,
    first: integer,
    last: integer,
    maxIterations: int32
): nil
    assert(#escapes == #points, "length mismatch")
    assert(first >= 1 and last <= #escapes and first <= last + 1, "range out of bounds")

    @simd
    for i = first, last do
        local escape = escapes[i]
        local point = points[i]
        local cx = point.re
        local cy = point.im
        local zx = 0.0
        local zy = 0.0
        local zxSquared = 0.0
        local zySquared = 0.0
        local iteration = 0
        local escaped = 0
        while iteration < maxIterations do
            if zxSquared + zySquared > 4.0 then
                escaped = 1
                break
            end
            zy = 2.0 * zx * zy + cy
            zx = zxSquared - zySquared + cx
            zxSquared = zx * zx
            zySquared = zy * zy
            iteration = iteration + 1
        end
        escape.iterations = iteration
        escape.escaped = escaped
    end
end
```

Two guards, then one marked numeric `for` loop.

## Guards

The guards are not decoration: the length guard is what proves the two spans can
share one index, and the range guard is what lets the generated loop read its
bounds without re-checking them every element.

The backend does not compile them. It reads facts out of them and spends the
facts on the loop, so what it asks is whether the facts imply the bounds -- not
whether a guard used one particular source form. Each of these says what the range
guard above says, and each compiles to the same kernel, byte for byte:

```nupp
assert(last <= #escapes and first >= 1 and first <= last + 1, "range out of bounds")
assert(first > 0 and last <= #escapes and first - 1 <= last, "range out of bounds")
assert(1 <= first and #escapes >= last and last + 1 >= first, "range out of bounds")
assert(first >= 1 and last <= #points and first <= last + 1, "range out of bounds")
```

The last bounds `last` by the span the length guard proved equal rather than by
the output itself, which follows because it is a fact the backend holds and not
a name it matched.

There may be any number of guards, and one may say several things. What has to
hold is that every statement before the loop is a guard:

```nupp
assert(#escapes == #points and first >= 1, "length and lower bound")
assert(last <= #escapes, "upper bound")
assert(first <= last + 1, "an empty range is allowed")
```

### Guard expressions

A comparison of integer parameters, integer literals and span lengths, either
side offset by a literal. `<`, `<=`, `>`, `>=` and `==` all read. On the integers
`a < b` is `a <= b - 1`, which is the rewrite the whole thing rests on and the
reason a `number` parameter is not admitted as a bound.

Clauses join with `and` in an `assert` and with `or` in the refusing form below.
The other pairing states nothing: knowing `a or b` holds is not knowing either
does, so `assert(first == 1 or last == 2, "…")` is a clause the backend cannot
read.

A clause it cannot read is refused rather than skipped, because skipping it would
compile a wrapper that never checks it:

```text
bench/kernel-subset-spike/mandelbrot.nupp:43:12: aot: `first * 2 >= 1` cannot be read as a guard: a guard compares integer parameters, integer literals and span lengths, offset by a literal
```

### Proof obligations and runtime checks

The loop names the range and the guards name nothing: `for i = first, last` over
`escapes` is what obliges `1 <= first`, `last <= #escapes` and `first <= last +
1`, and a loop over the whole of a span obliges nothing. A bound the guards do
not imply says what was missing and what was read, rather than a form to copy:

```text
bench/kernel-subset-spike/mandelbrot.nupp:45:5: aot: the loop range is not proved: needed `last <= #escapes`, understood `#escapes <= #points` (42:12), `#points <= #escapes` (42:12), `1 <= first` (43:12), `first <= last + 1` (43:27)
```

Length agreements go the other way: they are read out of the facts rather than
required of them, so `#a == #b and #b == #escapes` proves both spans agree with
the output. A span no agreement covers is still admitted -- a matrix product
reads dimensions no equality can express -- and what replaces the proof is
per-access, where a span the body touches at the loop counter must be the output
or proved equal to it, while a cursor access carries its own bound check into
either backend.

The generated wrapper checks the relations the source wrote, once per call. That
is what makes reasoning about implication enough: a guard stronger than the loop
needs is carried rather than refused, and stays stronger.

```nupp
assert(first >= 2 and last <= #escapes and first <= last + 1, "range out of bounds")
```

compiles, and the wrapper it generates refuses `first == 1` exactly as this
source does. Moving a function from interpreted to native never widens the calls
it accepts.

## Asserting and refusing

A guard may state what must hold, as above, or state what must not happen. Both
reach the same kernel and emit the same C:

```nupp
if #escapes ~= #points then
    error("length mismatch", 2)
end
if first < 1 or last > #escapes or first > last + 1 then
    error("range out of bounds", 2)
end
```

Refusing is worth the extra lines when the caller should be blamed for the bad
argument: `error(message, 2)` reports at the call site, and `assert` reports at
the guard. The condition is read knowing it is false where the loop runs, which
is why its clauses join with `or` where the asserted form joins with `and`, and
why it compares counts with `~=` where the asserted form compares with `==`.
Messages and error levels must be literals: consuming the guard must not discard
an expression that would otherwise have been evaluated.

The branch has to be one that cannot fall through -- a single `error` call and no
`else` -- because that is what makes the condition's polarity below it known.

## Backend report

Ask what the backend made of it:

```bash
nupp aot bench/kernel-subset-spike/mandelbrot.nupp
```

```text
bench/kernel-subset-spike/mandelbrot.nupp: mandelbrot, kernel, Fixed<4>, 4 lanes
```

`nupp aot` names each function's `kernel` or `lua-builder` entry mode, and JSON
inspection additionally reports the runtime ABI and digest-named registrar.
`--emit ir`, `--emit c` and `--emit binding` print the three artifacts.

## Reading the instructions

The generated C is the second-to-last thing between a lowering decision and the
machine. `--emit asm` is the last one: it compiles that C with the flags a build
compiles this tier's translation unit with, and reports the instructions it
became, by symbol.

```bash
nupp aot --emit asm --features neon --function mandelbrot \
    bench/kernel-subset-spike/mandelbrot.nupp
```

Whether a contiguous load became one native load, whether a fixed-size
accumulator stayed in registers, whether unrolling changed the lane lowering:
these are questions about the emitted instructions, and nothing else in the tree
answers them. `--function` and `--features` make the question a repeatable
command for one body at one tier, and the per-symbol counts under each header
make two runs of it comparable rather than something to be re-read by eye. The
[CLI reference](../../../reference/cli.md#aot) says what the counts mean and where
they are deliberately coarse.

`--emit c --source-locations` includes `#line` directives for authored statements; assembly is
compiled with debug line tables and its JSON instructions carry `sourceFile`
and `sourceLine` when the native compiler retained a location. `generatedColumn`
is a generated C column; authored loop columns come from `loops`. Compare those
with the function's `loops` entries to follow a loop from IR into C and assembly.
Instructions' `loopIds` name every loop whose retained source range contains
the location, including enclosing loops; these are source attribution, not a
claim that the native optimizer retained the same control-flow structure.
Optimization may move, combine, or remove instructions, so absent locations are
left absent rather than assigned to the nearest loop. Ordinary builds do not
add these inspection directives or debug flags.

`nupp lsp artifacts --json FILE LINE COLUMN` also reports the enclosing
function's logical `aotSymbol`. Static archives qualify that symbol and
multiversion builds suffix it with the selected tier.

`build --remarks` reports each AOT loop's lowering outcome at its authored
position; `--remarks-out` retains the same notes in `build/remarks.json`.
Running `nupp aot` from a parent directory uses the nearest manifest above the
source file, so a benchmark's imports resolve in its own project.

Each symbol is headed by what it is: the compiled body, the forced-scalar oracle
it is [differentially tested](numeric-semantics.md#verification) against, the Lua wrapper and
registrar in front of a builder, a layout reporter, or a helper the C compiler
declined to inline. Symbols carry no tier suffix here, as a single-tier build's
do not; a [multiversion](build-and-artifacts.md#library-dispatch) build's do, and the tier is reported
once for the listing instead.

A file may hold any number of `@aot` functions, and they need not agree about
width. They come out as one C file: a shared struct is declared once, each
function brings its own bodies, and each region width's prelude appears once.

Inspection checks the source before lowering it, just as `nupp build` does. The
backend consumes the checker's resolved signatures, ownership modes, effects,
intrinsic identities, and struct layouts, so a local type or function alias has
exactly the same meaning as the declaration it names. Written type syntax is not
a second source of truth.

## Running the kernel

Compiling and running it needs a C compiler and the spike's harness:

```bash
bench/kernel-subset-spike/mandelbrot.sh mandelbrot
```

```bash
MANDELBROT_WIDTH=1024 MANDELBROT_HEIGHT=768 MANDELBROT_ITERATIONS=256 \
    luajit bench/kernel-subset-spike/mandelbrot_main.lua
```

## Generated C

### Struct layouts

Every reified struct becomes a C type, and the object exports what its own C
compiler decided about the layout:

```c
typedef struct {
    int32_t iterations;
    uint32_t escaped;
} KsEscape;

size_t ks_mandelbrot_layout_Escape_size(void) { return sizeof(KsEscape); }
size_t ks_mandelbrot_layout_Escape_offset_iterations(void) { return offsetof(KsEscape, iterations); }
size_t ks_mandelbrot_layout_Escape_size_iterations(void) { return sizeof(((KsEscape *)0)->iterations); }
```

Those exist so the generated wrapper can compare them against `layoutof` at
load, before anything is callable. Reifying a struct is a claim about memory,
and this is where the claim is tested rather than assumed. See
[reflection.md](../../language/reflection.md) for `layoutof`.

### Scalar body

The tail loop is a direct transcription, and so is the whole body of a loop
with no `@simd` mark:

```c
    for (; i < end; ++i) {
        KsEscape *v1_escape = (&p_escapes[i]);
        const KsPoint *v2_point = (&p_points[i]);
        double v3_cx = ((double)(v2_point->re));
        double v4_cy = ((double)(v2_point->im));
```

Two things worth reading closely. `p_escapes` is `KsEscape *restrict` and
`p_points` is `const KsPoint *`: that is the alias matrix
[ownership](../../runtime/ownership/index.md) already proved, restated where the C
compiler can use it, not something recovered from the pointer types. And
`(double)(v2_point->re)` is a physical load widening, because a `float` field is
storage, so reading one gives an ordinary Nupp number. That is the only place a
width changes without the source asking.

### Lane-parallel body

The same loop, four iterations at a time. The `@simd` mark is lowered onto the
same `simd.Species` operations [explicit SIMD](vectorization.md#explicit-simd)
exposes, so the C is the C explicit source would have produced: one species per
element type at the region's lane count, out of the `ks_simd.h` header the
prelude carries.

```c
#define KS_SIMD_WIDTH 32
```

```c
KS_EXP_ELEMENT(16, f32x4, float, int32_t, 4, 4, FLOAT)
KS_EXP_ELEMENT(32, f64x4, double, int64_t, 4, 8, FLOAT)
```

Each of those declares `ks_exp_<species>` and `ks_exp_mask_<species>` as C
vector extensions plus the operations over them, so an elementwise operation in
the body is written as though it were scalar (the conversions between species
are statement expressions, elided here):

```c
    uint32_t sr0_base1 = ((uint32_t)(nupp_wrap_u32(p_first) + UINT32_C(4294967295)));
    {
        while (/* base + lanes fits both spans, and base + lanes <= last */) {
            ks_exp_f64x4 v3_cx = /* converted from f32x4 */ ks_exp_field_load_at_f32x4(
                p_points + (size_t)sr0_base1, sizeof(KsPoint), offsetof(KsPoint, re));
            ks_exp_f64x4 v9_zx = ks_exp_splat_f64x4(0.0);
            ks_exp_mask_f64x4 sr0_live5 = (v13_iteration < ks_exp_splat_f64x4(((double)p_maxIterations)));
            while (ks_exp_any_f64x4(sr0_live5)) {
                ks_exp_mask_f64x4 sr0_exec6 = sr0_live5;
                ks_exp_mask_f64x4 sr0_if7 = (sr0_exec6 & ((v11_zxSquared + v12_zySquared) > ks_exp_splat_f64x4(4.0)));
                ks_exp_mask_f64x4 as1 = (sr0_live5 & (~(sr0_if7 & sr0_exec6)));
                sr0_live5 = as1;
                ks_exp_mask_f64x4 as2 = (sr0_exec6 & (~(sr0_if7 & sr0_exec6)));
                sr0_exec6 = as2;
                ks_exp_f64x4 as3 = (((ks_exp_splat_f64x4(2.0) * v9_zx) * v10_zy) + v4_cy);
                v10_zy = as3;
                ks_exp_f64x4 as4 = ((v11_zxSquared - v12_zySquared) + v3_cx);
                v9_zx = as4;
                ks_exp_f64x4 as7 = ks_exp_select_f64x4(sr0_exec6, (v13_iteration + ks_exp_splat_f64x4(1.0)), v13_iteration);
                v13_iteration = as7;
                ks_exp_mask_f64x4 as8 = (sr0_live5 & (v13_iteration < ks_exp_splat_f64x4(((double)p_maxIterations))));
                sr0_live5 = as8;
            }
```

Read what happened to the source's control flow. The `if` became a mask. The
`break` became `sr0_live5 & ~mask`, so the lane retires from the loop instead of
branching out of it, and the loop ends when `ks_exp_any_f64x4` says nothing is
live. The assignment to `iteration` became a select, so a lane that already
escaped keeps what it had. `live` and `exec` are two masks because they differ:
a lane that hit `continue` is not running the rest of this iteration but is
still in the loop.

Storing a field of consecutive structs is one strided store per field, under the
proof that the guard on the `while` gave it:

```c
            ks_exp_field_store_at_i32x4(p_escapes + (size_t)sr0_base1, sizeof(KsEscape),
                offsetof(KsEscape, iterations), /* the f64x4 -> i32x4 conversion */);
            uint32_t as5 = ((uint32_t)(sr0_base1 + UINT32_C(4)));
            sr0_base1 = as5;
        }
```

The remainder is a masked final group rather than a scalar tail. It is the same
body under `ks_exp_tail_f64x4`, and it reaches memory through the checked
`ks_exp_field_load_f32x4` and `ks_exp_field_store_i32x4` rather than the `_at_`
forms above, which copy only the elements that remain: a masked-off lane never
touches the address it masked off, and the last element of a span may be the
last byte of a page.

Two whole functions come out: `ks_mandelbrot`, and `ks_mandelbrot_forced_scalar`
carrying a pragma that refuses vectorization. The second is the oracle the first
is diffed against, so it must not share its lowering, including whatever the C
compiler would have done on its own.

### Wrapper

The generated Nupp module is what a caller sees. Ownership survives; the
pointers do not escape:

```nupp
local function mandelbrot(
    exclusive escapes: span.WriteSpan<Escape>,
    borrows points: span.Span<Point>,
    first: integer,
    last: integer,
    maxIterations: int32
): nil
    if first < 1 or last > #escapes or first > last + 1 then
        error("native range out of bounds", 2)
    end
    local native_escapes, native_escapesCount = escapes:ref()
    local native_points, native_pointsCount = points:ref()
    if native_pointsCount ~= native_escapesCount then
        error("native spans have incompatible lengths", 2)
    end
    @unsafe do
        ks_mandelbrot(native_escapes as voidptr, native_points as voidptr,
            first, last, maxIterations, native_escapesCount)
    end
end
```

The range check and the length agreement are ordinary checked Nupp; `@unsafe do`
holds the foreign call and nothing else.

### Calling another entry

One `@aot` declaration may call another in the same file. It is a call, not a
copy: the callee is compiled once, keeps its own contract and its own numeric
guarantees, and the caller reaches it through the symbol it already exports.

```nupp
@aot
local function scale(value: number, factor: number): number
    return value * factor
end

@aot
local function apply(
    exclusive out: span.WriteSpan<float>,
    borrows inp: span.Span<float>,
    factor: number
): nil
    assert(#out == #inp, "length mismatch")

    for i = 1, #out do
        out[i] = scale(inp[i], factor)
    end
end
```

```c [Generated C, private]
KS_API double ks_scale(double p_value, double p_factor) {
    return p_value * p_factor;
}

KS_API void ks_apply(float *restrict p_out, const float *p_inp,
                     double p_factor, size_t count) {
    for (size_t i = 0; i < count; i++) {
        p_out[i] = (float)(ks_scale(((double)p_inp[i]), p_factor));
    }
}
```

The callee's parameters and result have to be values this IR carries across a
call, and it returns exactly one of them. A span does not cross an entry
boundary this way: the callee would need the caller's bounds proof, which is the
caller's and not transportable.

::: deepdive Calls inside SIMD loops
A `@simd` loop that calls an entry cannot lower lane-parallel, and the build
fails saying so:

```text
aot: a lane-parallel body cannot call a compiled entry
```

An entry takes one set of scalars and answers once. There is no per-lane form of
that, so the loop is refused rather than given a meaning the callee never agreed
to; without the mark it keeps its scalar shape and calls the entry once per
iteration, which is [not a failure](vectorization.md#required-loops).

That is the cost of the call being real. An ordinary `local function` containing
one return expression is inlined instead and keeps the lanes. Choosing between
the two decides whether the callee is compiled once or copied into each caller.
:::

## Benchmarks

Apple arm64, 1024×768 grid, 256 iterations, `clang -O3`. All three rows run the
same function on the same inputs and are checked to agree on every pixel, so
this measures how the body was compiled and nothing else.

| Body | ns/frame | MPix/s | Relative |
| --- | --- | --- | --- |
| AOT, lane-parallel | 6,143,356 | 128.01 | 26.6x |
| AOT, forced scalar | 11,879,941 | 66.20 | 13.7x |
| LuaJIT | 163,140,569 | 4.82 | 1.0x |

Reproduce with:

```bash
MANDELBROT_WIDTH=1024 MANDELBROT_HEIGHT=768 MANDELBROT_ITERATIONS=256 \
    MANDELBROT_QUIET=1 luajit bench/kernel-subset-spike/mandelbrot_main.lua
```

Read the two gaps separately, because they have different causes.

**Scalar C over LuaJIT is 13.7x**, and most of that is not arithmetic. Timing
the same recurrence in plain Lua with local variables instead of spans gives
about 15.9 MPix/s, so roughly half the gap is the span and struct-field
plumbing that the AOT body compiles away and the interpreter cannot. The rest
is codegen on a loop with a data-dependent exit. The loop is traceable, and
`nupp bc --check` on this kernel is clean, so this is LuaJIT compiling it and
still losing rather than LuaJIT giving up. See
[jit-trace-checking.md](../jit-trace-checking.md) for that check.

**Lane-parallel over scalar C is 1.9x** on four lanes, not 4x, because lanes
diverge: every lane runs until the last one escapes, so a group costs its
slowest member. Measure that against what the algorithm allows rather than
against the lane count. `divergence.lua` in the spike does exactly that, and at
this cap the four-lane ceiling is 1.22x the ideal work, so 1.9x against scalar
is close to what four lanes can be.

```bash
MANDELBROT_ITERATIONS=256 luajit bench/kernel-subset-spike/divergence.lua
```

### Binary32 lane width

The same program written in explicit binary32 gets eight lanes for the same
registers:

| Body | MPix/s | Notes |
| --- | --- | --- |
| AOT f32x8 | 213.06 | eight lanes, 32-byte region |
| AOT forced scalar | 65.82 | same width as the f64 scalar |
| LuaJIT | 0.13 | every rounding through an FFI store and load |

That is a different program with different escape counts, and it is the source
that says so. `bench/kernel-subset-spike/mandelbrot_f32.nupp` is the same
recurrence written as prefix calls, which is what tells the backend the values
are genuinely 32-bit rather than binary64 values that happen to be small:

::: code-group
```nupp [mandelbrot.nupp]
zy = 2.0 * zx * zy + cy
zx = zxSquared - zySquared + cx
zxSquared = zx * zx
zySquared = zy * zy
iteration = iteration + 1
```

```nupp [mandelbrot_f32.nupp]
zy = nupp.math.f32.add(
    nupp.math.f32.mul(nupp.math.f32.mul(zx, 2.0), zy), cy)
zx = nupp.math.f32.add(nupp.math.f32.sub(zxSquared, zySquared), cx)
zxSquared = nupp.math.f32.mul(zx, zx)
zySquared = nupp.math.f32.mul(zy, zy)
iteration = nupp.math.i32.add(iteration, 1)
```
:::

```text
bench/kernel-subset-spike/mandelbrot_f32.nupp: mandelbrot, kernel, Fixed<8>, 8 lanes
```

The LuaJIT row collapses because explicit binary32 in ordinary Nupp performs
each rounding point through an FFI store and load, which is the price of the
source rather than an artifact of measuring it.

Eight lanes over four is 1.66x, not 2x, and that is the algorithm rather than
the lowering. A group runs until its slowest lane retires, so widening it takes
that maximum over more pixels. Measured on this view the eight-lane ceiling is
1.68x at 256 iterations, falling to 1.58x at 4096 as escape counts spread
further apart, against measured ratios of 1.66x and 1.48x. The lowering runs at
94 to 99 percent of what the algorithm allows, and the remainder is the
per-pixel gather and scatter, which costs the same however many lanes share it.

A divergent loop is the case lane lowering is worst at, and the width you get is
not the speedup you get.
