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

Two guards, then one numeric `for` loop.

## Guards

The guards are not decoration: the length guard is what proves the two spans can
share one index, and the range guard is what lets the generated loop read its
bounds without re-checking them every element.

The backend does not compile either one. It matches them, reads the facts out of
them, and spends the facts on the loop, so each is written in one admitted form
rather than any equivalent condition. Within a form the wording is fixed:
comparisons join with `and` and compare counts with `==`, and the range guard is
matched against the exact text quoted in its diagnostic. Reordering the
comparisons or writing an equivalent inequality is refused, because a guard the
backend only approximately understood would not be a check.

Swapping the range guard's first two comparisons is one such equivalent
condition:

```nupp
assert(last <= #escapes and first >= 1 and first <= last + 1, "range out of bounds")
```

```text
bench/kernel-subset-spike/mandelbrot.nupp:44:12: aot: range guard must be `first >= 1 and last <= #output and first <= last + 1`
```

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
the guard. Its comparisons join with `or` and compare counts with `~=`, the
inverse of the asserted form. The message is optional either way.

## Backend report

Ask what the backend made of it:

```bash
nupp aot bench/kernel-subset-spike/mandelbrot.nupp
```

```text
bench/kernel-subset-spike/mandelbrot.nupp: mandelbrot, kernel, 5.19 operations per byte (83 over 16), mixed4, 4 lanes
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

Each symbol is headed by what it is: the compiled body, the forced-scalar oracle
it is [differentially tested](numeric-semantics.md#verification) against, the Lua wrapper and
registrar in front of a builder, a layout reporter, or a helper the C compiler
declined to inline. Symbols carry no tier suffix here, as a single-tier build's
do not; a [multiversion](build-and-artifacts.md#library-dispatch) build's do, and the tier is reported
once for the listing instead.

A file may hold any number of `@aot` functions, and they need not agree about
width. They come out as one C file: a shared struct is declared once, each
function brings its own bodies, and each gang's prelude appears once.

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

The tail loop is a direct transcription, and so is the whole body when lane
lowering declines:

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

The same loop, four iterations at a time. Vector types are C vector extensions,
so an elementwise operation is written as though it were scalar:

```c
typedef long long ks_m64x4 __attribute__((vector_size(32)));
typedef double ks_f64x4 __attribute__((vector_size(32)));

static inline ks_f64x4 ks_splat_f64x4(double v) { return (ks_f64x4){v, v, v, v}; }
static inline ks_f64x4 ks_sel_f64x4(ks_m64x4 m, ks_f64x4 a, ks_f64x4 b) {
    return (ks_f64x4)((m & (ks_m64x4)a) | (~m & (ks_m64x4)b));
}
```

```c
    size_t groups = (end > i) ? ((end - i) / 4) * 4 + i : i;
    for (; i < groups; i += 4) {
        ks_f64x4 v3_cx = ((ks_f64x4){p_points[i + 0].re, p_points[i + 1].re,
                                     p_points[i + 2].re, p_points[i + 3].re});
        ks_f64x4 v9_zx = ks_splat_f64x4(0.0);
        ks_m64x4 lm4_live = (v13_iteration < ks_splat_f64x4(((double)p_maxIterations)));
        while (ks_any(lm4_live)) {
            ks_m64x4 lm5_exec = lm4_live;
            ks_m64x4 lm6_if = (lm5_exec & ((v11_zxSquared + v12_zySquared) > ks_splat_f64x4(4.0)));
            v14_escaped = ks_sel_f64x4((lm6_if & lm5_exec), ks_splat_f64x4(1.0), v14_escaped);
            lm4_live &= ~((lm6_if & lm5_exec));
            lm5_exec &= ~((lm6_if & lm5_exec));
            v10_zy = (((ks_splat_f64x4(2.0) * v9_zx) * v10_zy) + v4_cy);
            v9_zx = ((v11_zxSquared - v12_zySquared) + v3_cx);
            v11_zxSquared = (v9_zx * v9_zx);
            v12_zySquared = (v10_zy * v10_zy);
            v13_iteration = ks_sel_f64x4(lm5_exec, (v13_iteration + ks_splat_f64x4(1.0)), v13_iteration);
            lm4_live &= (v13_iteration < ks_splat_f64x4(((double)p_maxIterations)));
        }
```

Read what happened to the source's control flow. The `if` became a mask. The
`break` became `lm4_live &= ~mask`, so the lane retires from the loop instead of
branching out of it, and the loop ends when `ks_any` says nothing is live. The
assignment to `iteration` became a select, so a lane that already escaped keeps
what it had. `live` and `exec` are two masks because they differ: a lane that
hit `continue` is not running the rest of this iteration but is still in the
loop.

The store writes consecutive elements one lane each, which Clang turns into an
interleaving store where the target has one:

```c
        {
            ks_f64x4 lanes = v13_iteration;
            p_escapes[i + 0].iterations = (int32_t)lanes[0];
            p_escapes[i + 1].iterations = (int32_t)lanes[1];
            p_escapes[i + 2].iterations = (int32_t)lanes[2];
            p_escapes[i + 3].iterations = (int32_t)lanes[3];
        }
    }
```

The remainder runs the scalar body one iteration at a time rather than a masked
final group, because a masked load still reads the addresses it masked off, and
the last element of a span may be the last byte of a page.

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
    unsafe do
        ks_mandelbrot(native_escapes as voidptr, native_points as voidptr,
            first, last, maxIterations, native_escapesCount)
    end
end
```

The range check and the length agreement are ordinary checked Nupp; `unsafe do`
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

::: deepdive
A loop that calls an entry does not lower lane-parallel, and says so:

```text
aot: a lane-parallel body cannot call a compiled entry
```

An entry takes one set of scalars and answers once. There is no per-lane form of
that, so the loop keeps its scalar shape rather than being given a meaning the
callee never agreed to. Declining is [not a
failure](vectorization.md#vectorization-decisions), but it is a decision worth seeing, which is
what `nupp aot --check` is for.

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
| AOT f32x8 | 213.06 | eight lanes, 32-byte gang |
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
bench/kernel-subset-spike/mandelbrot_f32.nupp: mandelbrot, kernel, 5.12 operations per byte (82 over 16), f32x8, 8 lanes
```

The LuaJIT row collapses because explicit binary32 in ordinary Nupp performs
each rounding point through an FFI store and load, which is the price of the
source rather than an artifact of measuring it.

Eight lanes over four is 1.66x, not 2x, and that is the algorithm rather than
the lowering. A gang runs until its slowest lane retires, so widening it takes
that maximum over more pixels. Measured on this view the eight-lane ceiling is
1.68x at 256 iterations, falling to 1.58x at 4096 as escape counts spread
further apart, against measured ratios of 1.66x and 1.48x. The lowering runs at
94 to 99 percent of what the algorithm allows, and the remainder is the
per-pixel gather and scatter, which costs the same however many lanes share it.

A divergent loop is the case lane lowering is worst at, and the width you get is
not the speedup you get.
