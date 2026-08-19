# Ahead-of-time compilation

`@aot` marks a whole function to be compiled ahead of time rather than left to
LuaJIT. The compiler admits a small structural subset, lowers it to a verified
IR, and emits private C. Pure numeric and span bodies keep the small `kernel`
ABI. A body that constructs fresh Lua values uses the separate `lua-builder`
ABI. Where a kernel is one numeric map loop, the compiler may also rewrite that
loop to run several iterations at once. Nothing in the source names an ABI, a
lane, a mask, or a vector width.

[Build policy](#build-policy) selects what a build does with it: `off` by
default, `emit-c` to write the C beside the build, `require` to compile it into
the project's own shared library and call it. `nupp check` validates the target
and the structural subset, so `@aot` on something the backend could not compile
is an error rather than a surprise later, and a check never needs a C compiler.

Everything below is real output on the kernels committed under
`bench/kernel-subset-spike/`, and every claim it makes is executed on Linux,
macOS and Windows rather than argued from one of them, as
[Verification](#verification) records. The edges the backend has not reached are
in [Not built yet](#not-built-yet); those are edges, not unkept promises.

```nupp
@aot
local function clamp(value: number, low: number, high: number): number
    if value < low then return low end
    if value > high then return high end
    return value
end
```

## Annotation guarantees

Three things, in order of how much they matter.

The body compiles once, ahead of time, with a real optimizing compiler behind
it. LuaJIT is very good, but it is a tracing JIT: it compiles what it observes,
it gives up on shapes it cannot record, and a hot loop that aborts a trace runs
interpreted however hot it gets.

The body's numeric meaning is pinned. Ordinary Nupp arithmetic is binary64 and
is neither contracted nor reassociated, so an AOT function's answers are a
property of what was written rather than of the target that compiled it. Where
you want a relaxation you ask for it, per function, with `@relax`.

And a body that is one map loop over spans may be lowered lane-parallel. That
is the largest single win where it applies, and the compiler decides whether it
applies.

## Worked example

This is `bench/kernel-subset-spike/mandelbrot.nupp`, trimmed to its shape. It
is ordinary Nupp: spans, structs, a `while` loop with a `break`.

```nupp
local span = require("nupp.mem.span")

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
        local cx = points[i].re
        local cy = points[i].im
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

### Guards

That shape is not decoration: the length guard is what proves the two spans can
share one index, and the range guard is what lets the generated loop read its
bounds without re-checking them every element.

The backend does not compile either one. It matches them, reads the facts out of
them, and spends the facts on the loop, so each is written in one admitted form
rather than any equivalent condition. Within a spelling the wording is fixed:
comparisons join with `and` and compare counts with `==`, and the range guard is
matched against the exact form quoted in its diagnostic. Reordering the
comparisons or writing an equivalent inequality is refused, because a guard the
backend only approximately understood would not be a check.

### Asserting and refusing

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
inverse of the asserted spelling. The message is optional either way.

### Backend report

Ask what the backend made of it:

```bash
nupp aot bench/kernel-subset-spike/mandelbrot.nupp
```

```text
bench/kernel-subset-spike/mandelbrot.nupp: mandelbrot, kernel, 5.19 operations per byte (83 over 16), f64x4, 4 lanes
```

A file may hold as many `@aot` functions as you like, and they need not agree
about width. They come out as one C file: a shared struct is declared once, each
function brings its own bodies, and each gang's prelude appears once.

`nupp aot` names each function's `kernel` or `lua-builder` entry mode. JSON
inspection additionally reports the runtime ABI and digest-named registrar.

`--emit ir`, `--emit c` and `--emit binding` print the three artifacts.

### Running the kernel

Compiling and running it needs a C compiler and the spike's harness:

```bash
bench/kernel-subset-spike/mandelbrot.sh mandelbrot
```

```bash
MANDELBROT_WIDTH=1024 MANDELBROT_HEIGHT=768 MANDELBROT_ITERATIONS=256 \
    luajit bench/kernel-subset-spike/mandelbrot_main.lua
```

## Generated C

### Layouts, stated and checked

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
and this is where the claim is tested rather than assumed.

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
`p_points` is `const KsPoint *`. That is the alias matrix ownership already
proved, restated where the C compiler can use it, not something recovered from
the pointer types. And `(double)(v2_point->re)` is a physical load widening: a
`float` field is storage, so reading one gives an ordinary Nupp number. That is
the only place a width changes without the source asking.

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
what it had.

`live` and `exec` are two masks because they differ: a lane that hit `continue`
is not running the rest of this iteration but is still in the loop.

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
final group. A masked load still reads the addresses it masked off, and the last
element of a span may be the last byte of a page.

Two whole functions come out: `ks_mandelbrot`, and `ks_mandelbrot_forced_scalar`
carrying a pragma that refuses vectorization. The second is the oracle the first
is diffed against, and it must not share its lowering, including whatever the C
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

## Building ordinary Lua values

An admitted body that constructs or returns a Lua table or string is entered as
a registered Lua C closure instead of through FFI:

```nupp
@aot
local function rows(count: integer): {number}
    local result = table.new(count, 0)
    for index = 1, count do
        result[index] = index * 2
    end
    return result
end
```

With `aot = "off"`, that is unchanged ordinary Nupp. With `require`, the
resolved `table.new` becomes `lua_createtable`, writes to the fresh unpublished
table use the public raw-set API, and one native call returns the completed
ordinary Lua value. Table literals infer their array and hash capacities.

The shipped builder subset admits fresh table literals, exact
`table.new(arrayCapacity, hashCapacity)`, primitive number/boolean/string/nil
values, string arguments, nested fresh tables, numeric and string-key writes,
structured control flow, and final return. It rejects reads during construction,
mutation of argument or previously published tables, metatables, dynamic calls,
callbacks, userdata, cycles, and arbitrary Lua execution.

Pointer-free parsers may also return the native-endian tree representation
consumed by `nupp.data.valuebuilder.materializeTree`. An AOT builder lowers that
resolved call to one bounds-checked C traversal: source and arena blobs remain
rooted strings, tables are presized from authored child counts, raw writes keep
barriers correct, and source slices or validated backslash/Unicode recipes
become Lua-owned strings. The ordinary module implementation is the `aot=off`
oracle. This is a general codec/AST construction boundary; it does not expose
`lua_State`, stack indexes, or collector objects.

Streaming parsers can avoid that representation entirely. The resolved
`nupp.data.valuebuilder` stream API starts with `new(nullValue)`, opens arrays
or objects with an estimated capacity, adds keys and primitive values, closes
each container, and publishes exactly one root with `finish`. `string`, `key`,
and `numberSlice` take zero-based ranges of a rooted string, so generated code
copies or converts directly into the final Lua value without an intermediate
substring. `byte`, `word`, and `length` let the same AOT entry parse rooted byte
strings; `word` reads a native-endian uint32 at a zero-based word index.
`depth`, `kind`, and `count` expose only the current construction-frame metadata
needed by an iterative parser. The ordinary implementation is the `aot = "off"`
oracle.

`newSized(nullValue, maxDepth, stringCapacity)` replaces the default 1,024-frame
bound with authored frame storage and reserves a bound for transformed strings.
The first 16 frames stay inline; deeper streams lazily spill to dynamically
allocated, Lua-rooted storage. The byte storage is allocated lazily on the first
escaped string and reused; publication still performs exactly one copy into a
normal Lua string. `newByteScratch`, `scratchByte`, `setScratchByte`, and
`resetByteScratch` provide the same bounded storage to other codecs, while
`stringScratch` and `keyScratch` publish a checked initialized range directly.
`integerSlice` is the integer-token counterpart of `numberSlice`: short integers
are accumulated directly in native code, while longer tokens retain the checked
binary64 conversion fallback.

The stream handle cannot be returned,
reassigned, stored, or passed to ordinary calls; only the resolved builder
operations admit it. Generated code keeps unfinished tables and object keys on
the VM stack, checks stack growth at every opening, performs barriers through
raw-set calls, and uses no native heap storage that could leak across a Lua
allocation failure.

Every live constructed object stays in an absolute Lua stack slot across
allocating calls. Generated code uses the public Lua 5.1 API for allocation,
barriers, strings, stack checks, and errors; it does not address LuaJIT
collector objects. Dynamic capacities and array indexes are checked for
integral, nonnegative/positive C-API range before use. Strings are ordinary
Lua-owned strings, not shared-memory views.

Explicit SIMD also includes `MaskBits64`, constructed from two uint32 words by
`simd.maskBits64`. It supplies cross-word shifts, prefix XOR, bitwise combines,
population count, first-set and clear-first operations without introducing a
general boxed `uint64` into ordinary Nupp. SIMD vectors, masks, and these
64-bit mask aggregates may pass through statically resolved pure AOT helpers;
multiple helper results use a private native C result struct.

All builders in one generated C file share one digest-named registrar. The
generated module loads it with `package.loadlib`, validates the returned closure
table, and caches that table for the Lua state. Pure kernels retain their
existing FFI path and have no Lua pointer or GC authority.

## Benchmarks

Apple arm64, 1024×768 grid, 256 iterations, `clang -O3`. All three rows run the
same function on the same inputs and are checked to agree on every pixel, so
this measures how the body was compiled and nothing else.

```text
 Body                     ns/frame      MPix/s   Relative
 ───────────────────────  ───────────  ────────  ────────
 AOT, lane-parallel        10,465,198     75.15      30.4x
 AOT, forced scalar        21,268,854     36.98      15.0x
 LuaJIT                   318,066,750      2.47       1.0x
```

Reproduce with:

```bash
MANDELBROT_WIDTH=1024 MANDELBROT_HEIGHT=768 MANDELBROT_ITERATIONS=256 \
    MANDELBROT_QUIET=1 luajit bench/kernel-subset-spike/mandelbrot_main.lua
```

Read the two gaps separately, because they have different causes.

**Lane-parallel over scalar C is 2.0×** on four lanes. Not 4×: lanes diverge.
Every lane runs until the last one escapes, so a group costs its slowest member.

**Scalar C over LuaJIT is 15×**, and most of that is not arithmetic. Timing the
same recurrence in plain Lua with local variables instead of spans gives about
4.6 MPix/s, so roughly half the gap is the span and struct-field plumbing that
the AOT body compiles away and the interpreter cannot. The rest is codegen on a
loop with a data-dependent exit. The loop is traceable, and `nupp bc --check` on
this kernel is clean, so this is LuaJIT compiling it and still losing rather
than LuaJIT giving up.

**Lane-parallel over scalar C is 2.0×** on four lanes, which is worth checking
against what the algorithm allows rather than against the lane count.
`divergence.lua` in the spike measures that: at this cap the four-lane ceiling
is 1.22× the ideal work, so 2.0× against scalar is close to what four lanes can
be.

The same program written in explicit binary32 gets eight lanes for the same
registers:

```text
 Body                     MPix/s   Notes
 ───────────────────────  ───────  ─────────────────────────────
 AOT f32x8                 123.28  eight lanes, 32-byte gang
 AOT forced scalar          35.66  same width as the f64 scalar
 LuaJIT                      0.02  every rounding through an FFI store/load
```

That is a different program with different escape counts, and it is the source
that says so. The LuaJIT row collapses because explicit binary32 in ordinary
Nupp performs each rounding point through an FFI store and load, which is the
price of the source rather than an artifact of measuring it.

Eight lanes over four is 1.64×, not 2×, and that is the algorithm rather than
the lowering. A gang runs until its slowest lane retires, so widening it takes
that maximum over more pixels. Measured on this view the eight-lane ceiling is
1.68× at 256 iterations, falling to 1.58× at 4096 as escape counts spread
further apart, against measured ratios of 1.60× and 1.42×. The lowering runs at
90 to 95 percent of what the algorithm allows; the remainder is the per-pixel
gather and scatter, which costs the same however many lanes share it.

```bash
MANDELBROT_ITERATIONS=256 luajit bench/kernel-subset-spike/divergence.lua
```

The lesson generalises: a divergent loop is the case lane lowering is worst at,
and the width you get is not the speedup you get.

## Automatic vectorization

### Vectorization decisions

Lane lowering is attempted for every `@aot` body whose shape admits it. Two
decisions follow, both made from the loop itself.

**Whether it pays.** Lane lowering wins where a loop stays in registers and
loses where it streams memory: Mandelbrot runs about twice its scalar speed,
while a component update runs between a tenth and four fifths of its. Neither
layout nor element width moves that. What separates them is how much arithmetic
there is to amortize assembling and taking apart the vectors, so the estimate is
arithmetic operations per byte the body touches, with a threshold of 1.0.

**How wide.** Gangs come in two widths, and within a width a group costs the
same registers either way and only the lane count differs. Ordinary Nupp
arithmetic is binary64, so a loop written with operators gets four lanes. A loop
whose varying values are all 32-bit gets eight, which happens when the source
asked for binary32 or wrapping int32 through the released `nupp.math`
namespaces. The widest gang is tried first and refuses the moment any varying
value turns out to be binary64.

You can see both answers per kernel:

```bash
nupp aot bench/kernel-subset-spike/mandelbrot.nupp
```

```text
 Kernel              Ops/byte   Outcome
 ──────────────────  ─────────  ──────────────────────────
 mandelbrot.nupp          5.19  lowered to 4 lanes
 mandelbrot_f32.nupp      5.12  lowered to 8 lanes
 kernels.nupp             0.39  declined, too little arithmetic
 columns.nupp             0.17  declined, too little arithmetic
 tecsbits.nupp            0.43  lowered to 4 lanes, by request
 corrected.nupp           0.12  lowered to 8 lanes, by request
```

The last two are below the threshold and lowered anyway, because their source
says so.

### Admitted loop shape

Lane lowering needs a whole-function shape it can reason about: one top-level
numeric `for` loop over spans, indexed by the loop counter exactly. Inside the
body it handles rather more than that: nested conditionals as mask stacks,
short-circuit `and`/`or` where both sides are pure and total, a data-dependent
inner `while`, and per-lane `break` and `continue`.

Where it cannot, the body still compiles: it keeps its scalar loop, and the
refusal names the construct that stopped it. A loop that does not vectorize is a
performance property, not a wrong answer, so it is not a build error.

It is worth checking, though, for the same reason `nupp bc --check` is worth
running: nothing else notices when it stops happening. `nupp aot --check` exits
1 for a loop that wanted lanes and ran one iteration at a time, and names what
refused it:

```text
nupp: advance ran one iteration at a time
  src/particles.nupp:39:5: aot: a nested numeric loop is not lane-controlled yet
```

A loop that declined is not a failure, since being able to decline is the point,
so `@aot(lanes = false)` and a body below the intensity threshold both pass.

### Targets and feature tiers

A gang is 16 or 32 bytes. 32 is one AVX register on x86-64 and two NEON
registers on aarch64; 16 is one SSE2 register, which every x86-64 has. A target
takes the widest shapes that fit its register class and no wider. A 32-byte
vector on x86-64 without AVX compiles only by being split and has no stable ABI
at a function boundary.

```text
 Tier      Widest vector   Gangs             Default for
 ────────  ─────────────   ───────────────   ───────────
 baseline  16 bytes        mixed2, f32x4     x86-64, i686
 avx2      32 bytes        all four
 neon      32 bytes        all four          aarch64
```

A `mixed` gang carries each value at its own element width, binary64 in 64-bit
lanes and binary32 in 32-bit ones, so an explicit binary32 operation is a native
single-precision instruction rather than a wide one rounded back. `f32x8` and
`f32x4` carry everything 32-bit and hold twice the iterations, which is why they
are tried first and why a loop with any binary64 value cannot have them.

x86-64 defaults to `baseline`, so a loop written with ordinary operators gets
two lanes there and four at `avx2`. The conservative default is deliberate: a
binary built for AVX2 does not run on a machine without it, and a default that
assumed otherwise would produce artifacts that fail on hardware the triple says
they support. The tier is selected, never measured, because a build that probed
the machine in front of it would produce an artifact that only runs there.

Ask for a wider one per target in `nupp.lua`:

```lua
targets = {
   game = {kind = "modules", entries = {"game"}, aot = "require", aotFeatures = "avx2"},
}
```

or per invocation:

```bash
nupp aot --target x86_64-unknown-linux-gnu --features avx2 src/kernel.nupp
```

The tier is part of the artifact key, so changing it rebuilds rather than
reusing what the other tier produced.

Within a tier, the widest gang that admits the loop wins: a body with any
binary64 varying value takes the binary64 gang, and one whose values the source
established as `float` and `int32` takes the 32-bit gang and twice the lanes.

A target too narrow for even the 16-byte pair refuses rather than going quietly
scalar, and says what would give it a gang:

```text
nupp: mandelbrot ran one iteration at a time
  src/kernel.nupp:50:5: aot: the baseline feature tier has no 16-byte vector;
  select avx2 to run several iterations at once
```

### Influencing vectorization

Three levers, and no more than three. None of them lets you name a lane.

**`@aot(lanes = true)`** takes lane lowering whatever the intensity estimate
says. Use it when you have measured the loop and the estimate disagrees with the
measurement. It does not require the lowering to succeed.

**`@aot(lanes = false)`** declines lane lowering for a body that would otherwise
be lowered. Use it for a loop that is deliberately scalar, so a vectorization
check does not report it.

**`@relax("fp-contract")`** permits a multiply and an add to fuse into one
rounding. It is per function and travels with the IR rather than being a
build-wide flag, because it changes what the function answers and not only how
fast it gets there. On this kernel it is worth about 6%: 75.8 against 71.1
MPix/s lane-parallel, 36.9 against 35.0 forced scalar.
`bench/kernel-subset-spike/mandelbrot_exact.nupp` is the same source without it.

Removing `lanes = true` or `lanes = false` changes the compilation strategy and
never the answer. Removing `@relax` changes the answer.

### Mixing widths

A loop whose values are all binary32 gets eight lanes; one whose values are all
binary64 gets four. A loop that mixes them gets four, the usual mixture being
everything binary32 except one running total that needs binary64, and the
binary64 gang performs each explicit binary32 operation in its own lanes and
rounds the result once. That is bit-identical to the native single-precision
instruction, by the same argument the whole binary32 surface rests on.

It costs three instructions where an exact operation is one, so such a body
gains about 1.14× over scalar where a body in a gang that carries its element
exactly gains about 2×. `nupp aot` says when a body paid it, because the
operations-per-byte number counts operations and would otherwise imply a gain
this body does not get:

```text
mixedwidth.nupp: integrate, 5.67 operations per byte (136 over 24), f64x4, 4 lanes, rounding explicit fixed-width work
```

If you see that and want the other 0.9×, the answer is in the source: a running
total that can be binary32 makes the whole loop 32-bit and doubles the lanes.
Whether it can is a question about your algorithm, not about the backend.

**The fourth lever is the source itself**, and it is the strongest one. Writing
the arithmetic through `nupp.math.f32` doubles the lane count, because it tells
the backend the values are genuinely 32-bit rather than binary64 values that
happen to be small. That changes the program's meaning, giving different
roundings and different results, which is exactly why the compiler will not do
it for you.

### Vectorization limits

There is no vector type, no mask value, no shuffle, and no way to name a width.
That is deliberate and it is written down in
[NEP 32](../neps/0032-aot-block-kernels-and-simd.md):
an earlier design exposed `F32x8`, `I32x8` and mask values, and it was removed.
Scalar source already gets target-selected width, masks and divergent control
flow, exact scalar tails, one spelling that works with the backend off, and the
freedom to change gang shape later. An explicit vector type would mostly restate
a map loop while adding decisions about preferred versus fixed width, boxing
outside `@aot`, escape rules, and cross-target ABI.

The case for revisiting that is cross-lane meaning a scalar loop cannot express,
such as shuffles, transposes, prefix scans, fixed-tree reductions, gathers,
compress and expand, in several real kernels. A kernel that merely vectorizes
imperfectly is not the case.

## Numeric guarantees

| Written | Computed as | Notes |
| --- | --- | --- |
| `a + b` on numbers | binary64 | not contracted, not reassociated |
| a `float` field read | binary64 | the physical load widens |
| a `float` field write | binary32 | the physical store narrows |
| `nupp.math.f32.add(a, b)` | binary32, one rounding | exact, see below |
| `nupp.math.f32.min`/`max`/`fma` | binary32, corrected | a helper repairs NaN behavior |
| `nupp.math.i32.add(a, b)` | wrapping int32 | wraps in unsigned, comes back |

The binary32 operations lower to native single-precision instructions and this
is exact rather than a relaxation: a binary32 operation over binary32 operands
computed in binary64 and rounded once is bit-identical to the native
instruction, because 53 ≥ 2 × 24 + 2.

`min`, `max` and `fma` are not covered by that argument. A differential over
every interesting binary32 value found they disagree with `fminf`, `fmaxf` and
`fmaf` in exactly one respect each: `nupp.math.f32` canonicalizes every NaN
where the instruction propagates a payload, and `min`/`max` return that
canonical NaN where IEEE `minNum` returns the operand that is not NaN. Both are
repaired by a select, so they are admitted with a correction rather than left
out.

A width changes only at a conversion the IR writes down. An operator never
changes one, which is what keeps `float` a storage fact rather than an
arithmetic type.

## Verification

Generated C is a backend representation and not the safety boundary. Every span
access, region relationship, conversion and lane operation is verified in the IR
before anything is emitted, so a rewrite that produced something invalid is a
compiler bug caught before it becomes a miscompilation.

Two rules do most of the work. Every load, store and element reference indexes
the loop counter and nothing else, which is both the argument that an access is
in bounds and the license to run several iterations at once. And the alias
matrix is required complete rather than merely consistent: every pair of span
regions carries a fact, because a pair with no fact would be a `restrict` nobody
justified.

Above that sit the differentials, which is where correctness is actually
established. Ordinary Nupp, forced-scalar C and lane-parallel C are all built
from one source and must agree exactly rather than within a tolerance, because
the arithmetic is specified to be the same work in the same order:

```bash
bench/kernel-subset-spike/simd.sh                     # lane rewrite vs scalar
luajit bench/kernel-subset-spike/corrected_main.lua   # binary32 min/max/fma
luajit bench/kernel-subset-spike/tecsbits_main.lua    # bitwise lanes over entities
luajit bench/kernel-subset-spike/mixedwidth_main.lua  # binary32 rounded into binary64 lanes
luajit bench/kernel-subset-spike/mandelbrot_main.lua  # every pixel, three ways
```

Tails are exercised at every remainder for both gang widths, so a four-lane and
an eight-lane tail are both covered.

`bench/kernel-subset-spike/crosscheck.sh` runs the same agreement in C with no
LuaJIT in the process, over every committed kernel, at both gang widths and at
whatever feature tier is asked for. CI runs it on Linux and macOS at three tiers
and through both Clang and GCC, and on Windows, so the platform is checked
rather than reasoned about from the other two.

The build's own end of it is exercised the same way, by doing the thing rather
than asserting it: a project is built under `require` and its answers compared
against the same project built with `aot = "off"`, an output tree is copied
elsewhere and run from a third directory, a cross build's object is inspected to
confirm it is the other machine's, and a stamped binary is run from `/` to
confirm it finds the library it was given.

## Scalar switch initializers

The scalar subset admits a switch as the sole initializer of one local when:

- the selector lowers to `f64`, `i32`, or `u32`;
- every case is an integer-valued numeric constant;
- every arm is one scalar expression; and
- the checker has proved the switch exhaustive, either from its cases or an
  `else` arm.

It lowers to one selector `Let`, one result `Let`, an ordered scalar-IR `If`,
and branch `Assign` operations. For an established `int32` or `uint32`
selector, lowering annotates that ordinary `If` with its exact-width labels and
the C emitter writes native `switch`. The annotation is optional: scalar-IR
verification and lane rewriting may ignore it and retain the complete equality
chain. Nupp `integer` is normally binary64, so those selectors deliberately
remain equality branches rather than being converted. Strings, type patterns,
block arms, and early arm returns report the ordinary NUPP2903 subset boundary.

The C compiler chooses the physical native dispatch. Nupp does not force a jump
table or synthesize a C perfect hash.

```nupp
local span = require("nupp.mem.span")

local struct Code
    value: int32
end

@aot
local function classify(
    exclusive output: span.WriteSpan<Code>,
    borrows input: span.Span<Code>
): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #output do
        local code = input[i].value
        local result: int32 = switch code do
            case -2147483648 -> 10
            case 1, 2 -> 20
            else -> 30
        end
        output[i].value = result
    end
end
```

The scalar body of that kernel includes this C shape (temporary names are
abbreviated here):

```c
switch (code) {
case (-INT32_C(2147483647) - INT32_C(1)):
    result = INT32_C(10);
    break;
case INT32_C(1):
case INT32_C(2):
    result = INT32_C(20);
    break;
default:
    result = INT32_C(30);
    break;
}
```

## Diagnostics

| Code | Meaning |
| --- | --- |
| NUPP2901 | `@aot` stacked with `@jit`, promising one body to two compilers |
| NUPP2902 | `@aot` on something that is not a whole function |
| NUPP2903 | A construct in an `@aot` body with no AOT IR form |

A closure, interpolated string, vararg, `goto`, dynamic call or unsafe operation
inside an `@aot` body reports NUPP2903 at the construct. Fresh table
construction is admitted; unsupported table reads or mutations are refused by
the value-level AOT lowering with a source position.

## Build policy

A build selects one policy, and an artifact records the one it was built under.
There is deliberately no mode that quietly mixes compiled functions with
ordinary fallbacks. Disabling compilation is meant to change performance and
packaging, never an answer.

```lua
targets = {
   game = {kind = "modules", entries = {"game"}, outDir = "build/game", aot = "emit-c"},
}
```

```text
 Policy    What it does
 ────────  ────────────────────────────────────────────────────────
 off       Nothing. The default, so a project that has not asked
           for native code never needs a C compiler.
 emit-c    Verifies the IR and writes the C to <outDir>/aot/,
           without compiling it.
 require   Everything emit-c does, and then compiles it into
           <outDir>/lib/. Fails the build when it cannot.
```

`emit-c` adds an artifact; it does not replace one. The ordinary Lua body is
still emitted and is still what runs. A module with no `@aot` function produces
no artifact at all, and a project with no `@aot` function anywhere builds
successfully under `require` with no library. The policy says what to do with
compiled code, not that there must be some.

Under `require`, calls reach the compiled code. The build replaces each `@aot`
function with the generated wrapper where it was written, so every call in the
file and every importer gets the compiled body without naming anything new.
Kernel wrappers call FFI symbols. Builder wrappers call a cached registered Lua
C closure, so no generated FFI code fabricates or discovers a `lua_State *`.

### Accepting a C compiler

Selecting `require` is how a project takes on a C compiler as a dependency.
Nothing else in Nupp makes it one, which is why `off` is the default rather than
something cleverer.

The build looks for `NUPP_NATIVE_CC` first, then `clang`, `cc` and `gcc` in that
order. Clang leads because the emitter's contraction pragma is Clang's; GCC
compiles the same C correctly and declines to contract, which is slower and
never wrong. Naming a compiler that cannot build this C is an error rather than
a reason to look elsewhere, because a build that quietly used a different
compiler than it was told to would produce an artifact nobody could account for.

The generated C needs `__attribute__((vector_size))` and
`__builtin_convertvector`: GCC 9 and later, and every Clang. **MSVC has
neither.**

That is a statement about a compiler, not about a platform. Windows is an
ordinary target: Clang and MinGW GCC both run there, both have the two
extensions, and a Windows project with either needs nothing further. The same
`aot = "require"` builds a `.dll` beside the artifact and the same wrapper loads
it. CI runs the lane-versus-scalar differential on Windows for exactly this
reason, rather than reasoning about it from the other two platforms.

A project whose only compiler is MSVC selects `emit-c` and hands the C to it,
which is what `emit-c` is for.

### Building for another machine

`aotTarget` names the machine the compiled code is for, separately from where
the Lua runs:

```lua
targets = {
   handheld = {
      kind = "modules",
      entries = {"game"},
      aot = "emit-c",
      aotTarget = "x86_64-unknown-linux-gnu",
      aotFeatures = "avx2",
   },
}
```

The triple decides the gang widths, how a shared library is produced and what it
is called, so a Windows target gets a `.dll` and no `-lm` whether or not the
build is running on Windows. The feature tier is checked against that target's
architecture rather than against the set of all tiers, so asking aarch64 for
`avx2` is refused where it is written.

`emit-c` needs nothing installed for the target: it writes that target's C and
stops, which is the answer when the compiler for a platform is somebody else's.

`aot = "require"` cross-compiles too, and then it needs the target's headers and
libraries the way any cross build does. Give them through `aotCflags`, which is
appended after the fixed flags and is part of what the library is keyed on:

```lua
aotCflags = {"--sysroot=/opt/sysroots/linux-x86_64"},
```

Without one, the failure names the missing thing rather than leaving you with
the compiler's own message about a missing `math.h`.

The flags are fixed:

```text
-std=c11 -O3 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror
```

`-Werror` is deliberate. This is compiler-generated C, so a warning in it is a
defect in the backend rather than a style opinion about someone's source. The
warning that matters most is `-Wpsabi`, which is how a vector with no register
class announces itself. Silencing it would make the target model pointless.
`-ffp-contract=off` is the numeric contract's floor; a body that asked for
contraction carries its own pragma.

That pragma is Clang's. Under GCC, `@relax("fp-contract")` compiles correctly
and does not contract, so the body is as accurate as the unrelaxed one and
slower than the same body under Clang. Correct either way; a performance
difference worth knowing about before benchmarking across compilers.

Code is linked, never mapped at run time. A shared library the loader already
brought in needs no W^X policy, no `MAP_JIT`, no executable-memory budget and no
code retirement, all of which exist only because code is mapped at run time.
They return if and when direct machine-code emission does.

### Library dispatch

The wrapper is ordinary Nupp. `nupp aot --emit binding` prints it, and what the
build splices in is the same text minus the parts the source already has:

```nupp
cdef function ks_scale_layout_Sample_size(): uint64 from"build/native/lib/libnative_aot.dylib"
const ks_scale_SampleLayout = layoutof(Sample)
if ks_scale_SampleLayout.size ~= ks_scale_layout_Sample_size() then
    error("native struct layout size mismatch", 0)
end

cdef function ks_scale(exclusive samples: voidptr, borrows source: voidptr, ...) from"..."

local function scale(exclusive samples: span.WriteSpan<Sample>, ...): nil
    if first < 1 or last > #samples or first > last + 1 then
        error("native range out of bounds", 2)
    end
    local native_samples, native_samplesCount = samples:ref()
    ...
    unsafe do
        ks_scale(native_samples as voidptr, ..., native_samplesCount)
    end
end
```

Because it is Nupp rather than generated Lua, it goes through the checker like
anything else: the ownership annotations, the range guard and the
one-statement-wide `unsafe do` are all checked, not trusted. A substitution
cannot smuggle in something the language would refuse.

It is written where the declaration was, which is necessarily after the struct
it reifies, and under the same name with the same signature. The struct layout
is compared against what the compiled object reports before the module finishes
loading, so a C compiler that laid the struct out differently is a load error
rather than a silent misread.

The module is hashed on the text that was compiled rather than the file on disk,
so a rebuild never reuses an artifact built from a different body.

`nupp check` does none of this: it answers a question about the source as
written, and never needs a C compiler.

### Shipping an artifact

The wrapper names the library with a leading `@`, which means *beside the module
that loads me* rather than *at this path*:

```lua
__nuppLib("@lib/libgame_aot.dylib")
```

VM-aware builders resolve the same `@lib/` reference before passing the path and
registrar symbol to `package.loadlib`.

At load, that is resolved against the chunk the wrapper was compiled into,
walking up until it finds the directory. Whatever path the loader used to open
the module is a path that works from wherever the program was started, so a
sibling of it does too, which makes the output tree relocatable. A path decided
at build time could not be: absolute pins the program to one machine, relative
pins it to one directory.

The walk is why one spelling serves every layout. A module named `a.b.kernel`
sits two directories down and the same module inlined at the root of a bundle
sits at the top; the library is in one place either way.

A single-artifact target, meaning `bundle`, `binary` or `component`, gets a copy
of the library beside whatever it wrote, because that artifact is what someone
carries somewhere and the build directory is not going with it:

```text
 dist/
   app.lua
   lib/libgame_aot.dylib
```

Copy the output tree, move it, hand it to someone: it runs. Copy it without the
`lib/` directory and the load fails by name, saying what it looked for and
where, rather than with a missing symbol later on.

### Artifact cache key

Each artifact is recorded under a key covering everything that can change its
bytes: the verified IR, the version of the IR vocabulary, the numeric-contract
version, the target triple and feature tier, the backend, and the compiler's own
fingerprint. A rebuild that computes the same key leaves the file alone.

The key is over the IR rather than the source, so two sources that lower to one
program share one artifact and a comment edit is not a rebuild. The
numeric-contract version is separate from the IR version on purpose: two
compilers can agree about every field of a program and disagree about whether an
operator contracts, and an artifact built under one contract must not be reused
under another.

The key is evidence, never authority. A build compares it, then checks that the
file it describes is still on disk with the bytes it claims; a deleted or edited
artifact is written again rather than believed because a digest agreed. Losing
the record costs one rebuild and changes no answer.

The linked library gets its own key, over the artifact keys it was built from
plus the compiler that ran, the flags it ran with, and the linkage that was
asked for, rather than the IR and target again, which the artifact keys already
carry. Changing compilers relinks; rebuilding an unchanged project does not. The
C itself is deliberately not keyed on the toolchain, because the C is the same C
whoever compiles it.

The library is validated the same way and is just as disposable. Deleting it
costs one relink.

## Not built yet

Named so you can tell what you are looking at:

- **Relocatable `kind = "c"` dependencies.** An ordinary C dependency's library
  is still named with the path the build wrote, so it has the problem `@aot`
  code no longer has. The `@` mechanism is general and would fix it; nothing has
  been changed there yet.
- **Eight lanes with a binary64 value in the loop.** A binary64 value needs
  64-bit lanes, so four is what fits in 32 bytes. Reaching eight means either a
  wider register file or letting one value span two registers, which is a
  decision nobody has taken. Measured on
  `bench/kernel-subset-spike/mixedwidth.sh`, that is the remaining 1.9× between
  a mixed gang and an all-binary32 one.
- **Multiversioning.** A build pins one feature tier. Dispatching between
  several at run time, so one binary uses AVX2 where it is present and the
  baseline where it is not, is a separate decision nobody has taken.

## Next

- [Performance](performance.md): what the ordinary Lua backend does
- [LuaJIT trace checking](jit-trace-checking.md): the same category of
  performance property, for the JIT rather than the AOT path
- [Effect contracts](../concepts/effects.md): the purity `@aot` helpers rely on
- [Ownership](../type-system/ownership.md): where the alias facts come from
