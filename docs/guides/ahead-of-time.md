---
order: 630
---

# Ahead-of-time compilation

`@aot` compiles a top-level local function ahead of time rather than leaving it
to LuaJIT. The local declaration gives the loader the binding it replaces with
the compiled entry. The compiler admits a small structural subset, lowers it to
a verified IR, and emits private C:

```nupp
@aot
local function clamp(value: number, low: number, high: number): number
    if value < low then return low end
    if value > high then return high end
    return value
end
```

`nupp check` validates the target and the structural subset, so `@aot` on
something the backend could not compile is an error rather than a surprise
later, and a check never needs a C compiler. [Build policy](#build-policy)
selects what a build does with the result: `off` by default, `emit-c` to write
the C beside the build, and `require` to compile it into the project's own
shared library and call it. Lua 5.1 applications have corresponding
[`emit-wasm` and `require-wasm`](wasm-aot.md) policies for pointer kernels and
Lua-building entries.

Pure numeric and span bodies keep the small `kernel` ABI, and a body that
constructs fresh Lua values uses the separate `lua-builder` ABI. Nothing in the
source names an ABI, a lane, a mask, or a vector width.

## Const-specialized families

An `@aot` function may use scalar `const` binders when checked direct calls close
their carrier parameters:

```nupp
@aot(lanes = false)
local function doubled<const N: integer>(value: number, count: N): number
    local answer = value
    for _ = 1, count as integer do answer = answer * 2.0 end
    return answer
end

local result = doubled(5.0, 3)
```

The build collects closed applications across the module graph, emits a private
native body per admitted body class, and removes the carrier from that private
ABI. Constant folding and bounded unrolling run before lane selection. Checked
same- and cross-module calls use the private entry; the public function value
dispatches tuples that were included in the deliverable and reports an unmatched
tuple instead of silently falling back from an AOT-required build.

One module may emit eight logical const body classes before target tiers multiply
them into physical entries. Calls with the same semantic key deduplicate, and
keys with the same proven body and ABI coalesce. Exceeding the cap is a build
error for a required AOT family and names its demanding call sites. With AOT
off, the generic Lua body remains available; at `-O1` and above it may still be
specialized by [`OPT-8`](performance.md#opt-8-const-monomorphization).

## Annotation guarantees

`@aot` promises three things, in order of how much they matter.

The body compiles once, ahead of time, with an optimizing compiler behind it.
LuaJIT is a tracing JIT: it compiles what it observes, it gives up on shapes it
cannot record, and a hot loop that aborts a trace runs interpreted however hot
it gets.

The body's numeric meaning is pinned. Ordinary binary64 Nupp arithmetic is
neither contracted nor reassociated, so an AOT function's answers are a
property of what was written rather than of the target that compiled it.
Explicit wrapping integer operations may be reassociated because their modular
answer does not depend on grouping. Ask for a relaxation per function with
[`@relax`](../reference/annotations.md#relaxing-observable-guarantees).

And a body that is one map loop over spans may be lowered lane-parallel. That is
the largest single win where it applies, and the compiler decides whether it
applies.

::: deepdive
The annotation is a contract over ordinary Nupp rather than a restricted
sublanguage: the body uses the same parser, type system, operators, and
diagnostics, so removing the annotation changes performance and artifacts but
never the source-level result. There is no silent per-function fallback, because
a contract that degrades quietly is a comment.

See [NEP 9](../neps/0009-ahead-of-time-compilation.md) for more information.
:::

## Worked example

This is `bench/kernel-subset-spike/mandelbrot.nupp`, trimmed to its shape. It is
ordinary Nupp: [spans](nupp.mem.span), [structs](../type-system/records.md), a
`while` loop with a `break`.

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

### Guards

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
inverse of the asserted form. The message is optional either way.

### Backend report

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

### Reading the instructions

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
[CLI reference](../reference/cli.md#aot) says what the counts mean and where
they are deliberately coarse.

Each symbol is headed by what it is: the compiled body, the forced-scalar oracle
it is [differentially tested](#verification) against, the Lua wrapper and
registrar in front of a builder, a layout reporter, or a helper the C compiler
declined to inline. Symbols carry no tier suffix here, as a single-tier build's
do not; a [multiversion](#library-dispatch) build's do, and the tier is reported
once for the listing instead.

A file may hold any number of `@aot` functions, and they need not agree about
width. They come out as one C file: a shared struct is declared once, each
function brings its own bodies, and each gang's prelude appears once.

Inspection checks the source before lowering it, just as `nupp build` does. The
backend consumes the checker's resolved signatures, ownership modes, effects,
intrinsic identities, and struct layouts, so a local type or function alias has
exactly the same meaning as the declaration it names. Written type syntax is not
a second source of truth.

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
[reflection.md](../concepts/reflection.md) for `layoutof`.

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
[ownership](../concepts/ownership.md) already proved, restated where the C
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
failure](#vectorization-decisions), but it is a decision worth seeing, which is
what `nupp aot --check` is for.

That is the cost of the call being real. A helper — an ordinary `local function`
that is one return expression — is inlined instead and keeps the lanes, so the
choice between the two is a choice about whether the callee is compiled once or
copied into each caller.
:::

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

### Builder subset

The shipped builder subset admits fresh table literals, exact
`table.new(arrayCapacity, hashCapacity)`, primitive number, boolean, string and
`nil` values, string arguments, nested fresh tables, numeric and string-key
writes, numeric reads from those fresh tables, rooted-string length, byte and
substring operations, concatenation, structured control flow, and a final
return:

```nupp
@aot
local function summary(name: string, count: integer): {string: any}
    return {
        name = name,
        count = count,
        limits = {low = 0, high = count},
        ok = count > 0,
    }
end
```

An append-only local such as `answer = answer .. piece` is recognized from the
ordinary source and lowered to the Lua C API's buffered-string operations. It
does not require `nupp.data.valuebuilder` calls or a second AOT-only body.

It rejects reads from arguments or published tables, mutation of either,
metatables, dynamic calls, callbacks, userdata, cycles, and arbitrary Lua
execution. A table that arrived from outside is refused at the parameter rather
than at its first access:

```nupp
@aot
local function extend(target: {number}, count: integer): {number}
    for index = 1, count do
        target[index] = index
    end
    return target
end
```

```text
src/rows.nupp:2:31: aot: parameter type {number} is not admitted
```

Every live constructed object stays in an absolute Lua stack slot across
allocating calls. Generated code uses the public Lua 5.1 API for allocation,
barriers, strings, stack checks, and errors, and does not address LuaJIT
collector objects. Dynamic capacities and array indexes are checked for
integral, nonnegative C-API range before use, and strings are ordinary
Lua-owned strings rather than shared-memory views.

### Tree materialization

Pointer-free parsers may return the native-endian tree representation consumed
by `nupp.data.valuebuilder.materializeTree`. An AOT builder lowers that resolved
call to one bounds-checked C traversal: source and arena blobs remain rooted
strings, tables are presized from authored child counts, raw writes keep
barriers correct, and source slices or validated backslash and Unicode recipes
become Lua-owned strings.

```nupp
local valuebuilder = require("nupp.data.valuebuilder")

--- @raises when the blobs do not describe a well-formed tree
@aot
local function decode(nodes: string, links: string, source: string, null: any): any
    return valuebuilder.materializeTree(nodes, links, source, 1, null)
end
```

This is a general codec and AST construction boundary. It does not expose
`lua_State`, stack indexes, or collector objects, and the ordinary module
implementation is the `aot = "off"` oracle.

### Streaming construction

Streaming parsers can avoid that representation entirely. The resolved
`nupp.data.valuebuilder` stream API starts with `new(nullValue)`, opens arrays
or objects with an estimated capacity, adds keys and primitive values, closes
each container, and publishes exactly one root with `finish`.

```nupp
local valuebuilder = require("nupp.data.valuebuilder")

--- Reads `source` as fixed-width integer fields and returns them as an array.
@aot
local function decodeFields(
    source: string,
    count: uint32,
    width: uint32,
    nullValue: any
): any
    local builder = valuebuilder.new(nullValue)
    valuebuilder.openArray(builder, count)
    local cursor: uint32 = 0
    local length = valuebuilder.length(source)
    while cursor < length do
        valuebuilder.integerSlice(builder, source, cursor, width)
        cursor = nupp.math.u32.add(cursor, width)
    end
    valuebuilder.close(builder)

    return valuebuilder.finish(builder)
end
```

Every capacity, offset and length is a `uint32`, and so is the arithmetic that
advances the cursor. An ordinary binary64 number reaching one of these is
refused rather than promoted, because the offsets address the parser's own bytes
and a fractional one is not an offset.

`string`, `key`, and `numberSlice` take zero-based ranges of a rooted string, so
generated code copies or converts directly into the final Lua value without an
intermediate substring. `byte`, `word`, and `length` let the same AOT entry
parse rooted byte strings, where `word` reads a native-endian uint32 at a
zero-based word index. `depth`, `kind`, and `count` expose only the current
construction-frame metadata an iterative parser needs.

The stream handle cannot be returned, reassigned, stored, or passed to ordinary
calls; only the resolved builder operations admit it. Generated code keeps
unfinished tables and object keys on the VM stack, checks stack growth at every
opening, performs barriers through raw-set calls, and uses no native heap
storage that could leak across a Lua allocation failure.

### Bounded scratch storage

`newSized(nullValue, maxDepth, stringCapacity)` replaces the default 1,024-frame
bound with authored frame storage and reserves a bound for transformed strings.
The first 16 frames stay inline, and deeper streams lazily spill to dynamically
allocated, Lua-rooted storage. The byte storage is allocated lazily on the first
escaped string and reused; publication still performs exactly one copy into a
normal Lua string.

`newByteScratch`, `scratchByte`, `setScratchByte`, and `resetByteScratch` give
the same bounded storage to other codecs, while `stringScratch` and `keyScratch`
publish a checked initialized range directly. A string assembled byte by byte
and published once looks like this:

```nupp
local valuebuilder = require("nupp.data.valuebuilder")

--- Uppercases each ASCII letter of `source` and publishes it as one string.
@aot
local function shout(source: string, capacity: uint32, nullValue: any): any
    local depth: uint32 = 4
    local builder = valuebuilder.newSized(nullValue, depth, capacity)
    local scratch = valuebuilder.newByteScratch(capacity)
    local length = valuebuilder.length(source)
    local index: uint32 = 0
    local zero: uint32 = 0
    while index < length do
        local byte = valuebuilder.byte(source, index)
        if byte >= 97 and byte <= 122 then
            byte = nupp.math.u32.sub(byte, 32)
        end
        valuebuilder.setScratchByte(scratch, index, byte)
        index = nupp.math.u32.add(index, 1)
    end
    valuebuilder.stringScratch(builder, scratch, zero, length)

    return valuebuilder.finish(builder)
end
```

`integerSlice` is the integer-token counterpart of `numberSlice`: short integers
accumulate directly in native code, and longer tokens retain the checked
binary64 conversion fallback.

### Registrar and loading

Every builder in one generated C file shares one digest-named registrar. For
the default shared-library linkage, the generated module resolves its sidecar,
opens that registrar with `package.loadlib`, validates the returned closure
table, and caches that table for the Lua state:

```nupp
local ks_summary_builderRegistrar = "ks_register_c70bc70bcb1fafb2"
-- ...
local open, why = loadlib(path, ks_summary_builderRegistrar)
if not open then error("cannot register AOT builder: " .. tostring(why), 0) end
registered = open()
if type(registered) ~= "table" or type(registered["summary"]) ~= "function" then
    error("malformed AOT builder registration", 0)
end
modules[cacheKey] = registered
```

`nupp aot --emit binding` prints the whole thing, including the walk that finds
the library beside the module. Pure kernels retain their existing FFI path and
have no Lua pointer or GC authority.

With `aotLinkage = "static"` on a component target, the component never opens a
library at runtime. The embedding host links the archive and calls its registrar
with the host-owned `lua_State` before loading the component. The generated
module reads the registered table instead:

```nupp [Generated static binding, private]
local modules = rawget(_G, "__nuppAotBuilderModules")
local registered = modules and modules["ks_register_<component>_<digest>"]
if type(registered) ~= "table" then
    error("AOT builder archive is not registered", 0)
end
```

Lua source cannot call this registrar through `ffi.C`: the registrar needs a
`lua_State *`, which belongs to the embedding host. See
[Static AOT components](build.md#static-aot-components) for the build choice
and [Embedding Nupp](embedding.md#static-aot-components) for the host handoff.

## Benchmarks

Apple arm64, 1024×768 grid, 256 iterations, `clang -O3`. All three rows run the
same function on the same inputs and are checked to agree on every pixel, so
this measures how the body was compiled and nothing else.

| Body | ns/frame | MPix/s | Relative |
| --- | --- | --- | --- |
| AOT, lane-parallel | 10,465,198 | 75.15 | 30.4x |
| AOT, forced scalar | 21,268,854 | 36.98 | 15.0x |
| LuaJIT | 318,066,750 | 2.47 | 1.0x |

Reproduce with:

```bash
MANDELBROT_WIDTH=1024 MANDELBROT_HEIGHT=768 MANDELBROT_ITERATIONS=256 \
    MANDELBROT_QUIET=1 luajit bench/kernel-subset-spike/mandelbrot_main.lua
```

Read the two gaps separately, because they have different causes.

**Scalar C over LuaJIT is 15x**, and most of that is not arithmetic. Timing the
same recurrence in plain Lua with local variables instead of spans gives about
4.6 MPix/s, so roughly half the gap is the span and struct-field plumbing that
the AOT body compiles away and the interpreter cannot. The rest is codegen on a
loop with a data-dependent exit. The loop is traceable, and `nupp bc --check` on
this kernel is clean, so this is LuaJIT compiling it and still losing rather
than LuaJIT giving up. See
[jit-trace-checking.md](jit-trace-checking.md) for that check.

**Lane-parallel over scalar C is 2.0x** on four lanes, not 4x, because lanes
diverge: every lane runs until the last one escapes, so a group costs its
slowest member. Measure that against what the algorithm allows rather than
against the lane count. `divergence.lua` in the spike does exactly that, and at
this cap the four-lane ceiling is 1.22x the ideal work, so 2.0x against scalar
is close to what four lanes can be.

```bash
MANDELBROT_ITERATIONS=256 luajit bench/kernel-subset-spike/divergence.lua
```

### Binary32 lane width

The same program written in explicit binary32 gets eight lanes for the same
registers:

| Body | MPix/s | Notes |
| --- | --- | --- |
| AOT f32x8 | 123.28 | eight lanes, 32-byte gang |
| AOT forced scalar | 35.66 | same width as the f64 scalar |
| LuaJIT | 0.02 | every rounding through an FFI store and load |

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

Eight lanes over four is 1.64x, not 2x, and that is the algorithm rather than
the lowering. A gang runs until its slowest lane retires, so widening it takes
that maximum over more pixels. Measured on this view the eight-lane ceiling is
1.68x at 256 iterations, falling to 1.58x at 4096 as escape counts spread
further apart, against measured ratios of 1.60x and 1.42x. The lowering runs at
90 to 95 percent of what the algorithm allows, and the remainder is the
per-pixel gather and scatter, which costs the same however many lanes share it.

A divergent loop is the case lane lowering is worst at, and the width you get is
not the speedup you get.

## Automatic vectorization

### Vectorization decisions

Lane lowering is attempted for every `@aot` body whose shape admits it. Two
decisions follow, both made from the loop itself.

**Whether it pays.** Lane lowering wins where a loop stays in registers and
loses where it streams memory: Mandelbrot runs about twice its scalar speed,
while a component update over fields in consecutive structs runs between a
tenth and four fifths of its. Shrinking the struct or the physical width does
not move that result. Projecting the hot fields from `nupp.mem.soa` column
storage does: contiguous loads recover parity with scalar, although a streaming
body still has too little work to gain from lanes. The estimate is arithmetic
operations per byte the body touches, with a threshold of 1.0.

**How wide.** Gangs come in 16-, 32-, and 64-byte shapes. Ordinary Nupp
arithmetic is binary64, so a loop written with operators gets two lanes at the
x86-64 baseline, four at AVX2, and eight at AVX-512. A loop whose varying values
are all 32-bit gets four lanes at baseline and eight at every wider tier. At
equal lane counts the narrower shape is tried first, so an all-32-bit loop does
not pay for 64-byte values it does not use.

`nupp aot` reports both answers per kernel:

```bash
nupp aot bench/kernel-subset-spike/mandelbrot.nupp
```

Over the committed kernels the answers are:

| Kernel | Ops/byte | Outcome |
| --- | --- | --- |
| `mandelbrot.nupp` | 5.19 | lowered to 4 lanes |
| `mandelbrot_f32.nupp` | 5.12 | lowered to 8 lanes |
| `kernels.nupp` | 0.39 | declined, too little arithmetic |
| `columns.nupp` | 0.17 | declined, too little arithmetic |
| `tecsbits.nupp` | 0.43 | lowered to 4 lanes, by request |
| `corrected.nupp` | 0.12 | lowered to 8 lanes, by request |

The last two are below the threshold and lowered anyway, because their source
says so.

### Admitted loop shape

Lane lowering needs a whole-function shape it can reason about: one top-level
numeric `for` loop over spans, indexed by the loop counter exactly. Inside the
body it handles rather more than that: nested conditionals as mask stacks,
short-circuit `and` and `or` where both sides are pure and total, a
data-dependent inner `while`, and per-lane `break` and `continue`. This
`normalize` uses three of those and is admitted whole:

```nupp
@aot
local function normalize(
    exclusive outputs: span.WriteSpan<Sample>,
    borrows inputs: span.Span<Sample>,
    first: integer,
    last: integer
): nil
    assert(#outputs == #inputs, "length mismatch")
    assert(first >= 1 and last <= #outputs and first <= last + 1, "range out of bounds")

    for i = first, last do
        local value = inputs[i].value   -- the counter, and nothing else
        if value < 0.0 then             -- a mask, not a branch
            value = 0.0 - value
        end
        while value > 1.0 do            -- data-dependent, per lane
            value = value * 0.5
        end
        outputs[i].value = value
    end
end
```

```text
src/normalize.nupp: normalize, kernel, 1.12 operations per byte (9 over 8), mixed4, 4 lanes
```

A nested numeric loop whose ascending bounds are integer literals is expanded
before lane lowering when it has at most four iterations and contains no
`break` or `continue`. Expansion shares a 96-node growth budget across the
entry; a larger, dynamic, exiting, or over-budget loop keeps its scalar nested
shape. The JSON report counts expanded loops and iterations under
`optimization`.

That `optimization` object also reports `beforeNodes`, `afterNodes`, `folds`,
`propagatedConstants`, `specializedHelperCalls`, `unrolledLoops`,
`unrolledIterations`, `removedStatements`, and `iterations`. Its
`ruleApplications` array contains `{id, count}` entries for every rule and
pseudo-rule that actually applied -- the fold catalog plus
`propagate.local-constant` and `specialize.helper-constant` -- sorted by
stable rule ID; rules with a zero count are omitted. The aggregate fields are
derived from the same ledger, so summing the array double-counts against
them: `propagatedConstants` and `specializedHelperCalls` repeat the two
pseudo-rule counts, and `folds` adds statement-level branch selection to the
remaining entries.

Where it cannot, the body still compiles: it keeps its scalar loop, and the
refusal names the construct that stopped it. A loop that does not vectorize is a
performance property rather than a wrong answer, so it is not a build error.

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
For a low-intensity loop that reads or writes fields across consecutive
structs, the report also suggests projecting the hot fields from
`nupp.mem.soa` column storage so those accesses become contiguous.

### Targets and feature tiers

A gang is 16, 32, or 64 bytes, which are one SSE2, AVX, or AVX-512 register on
x86-64. A target takes the widest shapes that fit its register class and no
wider. A wider vector still compiles by being split, but has no stable ABI at a
function boundary, and Clang reports that through `-Wpsabi` even at a `static
inline` helper's call site.

| Tier | Widest vector | Gangs | Default for |
| --- | --- | --- | --- |
| `baseline` | 16 bytes | `mixed2`, `f32x4` | x86-64, i686 |
| `avx2` | 32 bytes | `mixed2`/`4`, `f32x4`/`8` | |
| `avx512f` | 64 bytes | `mixed2`/`4`/`8`, `f32x4`/`8` | |
| `neon` | 32 bytes | `mixed2`/`4`, `f32x4`/`8` | aarch64 |

`f32x8` and `f32x4` carry everything 32-bit and hold twice the iterations, which
is why they are tried first and why a loop with any binary64 value cannot have
them. A `mixed` gang is the alternative, described under
[Mixing widths](#mixing-widths).

x86-64 project builds carry `baseline`, `avx2` and `avx512f` translation units
in one library. Their exported symbols carry the tier name, and the generated
wrapper asks a baseline C entry what the destination supports once at load,
then binds each function to the widest entry no wider than that answer. Mapping
the other entries does not execute them. A machine without AVX therefore gets
the two-lane baseline body, while one with AVX2 gets four lanes from the same
artifact.

`aotFeatures` is a ceiling. Use it to omit tiers a project does not want to
ship; every tier below it still travels, so `avx2` retains its baseline
fallback:

```lua
targets = {
   game = {kind = "modules", entries = {"game"}, aot = "require", aotFeatures = "avx2"},
}
```

The standalone inspection command still selects one exact tier:

```bash
nupp aot --target x86_64-unknown-linux-gnu --features avx2 src/kernel.nupp
```

Each `(source, tier)` C file has its own artifact key. Changing the ceiling adds
or removes those files rather than reusing one tier's output as another's.

Within a tier, the gang with the most lanes that admits the loop wins. At
AVX-512 a mixed body and an all-32-bit body both get eight lanes, but the latter
takes the 32-byte `f32x8` shape instead of the 64-byte `mixed8` one.

A target too narrow for even the 16-byte pair refuses rather than going quietly
scalar, and says what would give it a gang:

```text
nupp: mandelbrot ran one iteration at a time
  src/kernel.nupp:50:5: aot: the baseline feature tier has no 16-byte vector;
  select avx2 to run several iterations at once
```

::: deepdive
x86-64 defaults to `baseline`, so a loop written with ordinary operators gets
two lanes there and four at `avx2`. The conservative default is deliberate: a
binary built for AVX2 does not run on a machine without it, and a default that
assumed otherwise would produce artifacts that fail on hardware the triple says
they support. The tier is selected and never measured, because a build that
probed the machine in front of it would produce an artifact that only runs
there.
:::

### Influencing vectorization

There are three levers, and none of them lets you name a lane.

**`@aot(lanes = true)`** takes lane lowering whatever the intensity estimate
says. Use it when you have measured the loop and the estimate disagrees with the
measurement. It does not require the lowering to succeed.
`bench/kernel-subset-spike/lanedemo.nupp` is a component update at 0.29
operations per byte, well under the threshold, lowered because its source asks:

```nupp
@aot(lanes = true)
local function advance(
    exclusive particles: span.WriteSpan<Particle>,
    borrows source: span.Span<Particle>,
    dt: float
): nil
```

```text
bench/kernel-subset-spike/lanedemo.nupp: advance, kernel, 0.29 operations per byte (7 over 24), mixed4, 4 lanes
```

**`@aot(lanes = false)`** declines lane lowering for a body that would otherwise
be lowered. Use it for a loop that is deliberately scalar, so a vectorization
check does not report it. The `normalize` from
[Admitted loop shape](#admitted-loop-shape) took four lanes on its own; with the
line below it declines them, and `nupp aot --check` stays quiet about it:

```nupp
@aot(lanes = false)
local function normalize(
    exclusive outputs: span.WriteSpan<Sample>,
    borrows inputs: span.Span<Sample>,
    first: integer,
    last: integer
): nil
```

```text
src/normalize.nupp: normalize, kernel, 1.12 operations per byte (9 over 8), none, declined by `@aot(lanes = false)`
```

**`@relax("fp-contract")`** permits a multiply and an add to fuse into one
rounding. It is per function and travels with the IR rather than being a
build-wide flag, because it changes what the function answers and not only how
fast it gets there:

```nupp
@relax("fp-contract")
@aot
local function mandelbrot(
    exclusive escapes: span.WriteSpan<Escape>,
    borrows points: span.Span<Point>,
    first: integer,
    last: integer,
    maxIterations: int32
): nil
```

That one line is the entire difference from
`bench/kernel-subset-spike/mandelbrot_exact.nupp`, which is otherwise the same
source, and it reaches the C as the pragma the compiler needs:

```c
__attribute__((noinline))
KS_API void ks_mandelbrot(KsEscape *restrict p_escapes, /* ... */) {
#if defined(__clang__)
#pragma clang fp contract(fast)
#endif
```

`nupp aot --emit c` on the two files differs by exactly that, once in each
emitted body. On this kernel it is worth about 6 percent: 75.8 against 71.1
MPix/s lane-parallel, 36.9 against 35.0 forced scalar.

Removing `lanes = true` or `lanes = false` changes the compilation strategy and
never the answer. Removing `@relax` changes the answer.

### Mixing widths

A mixed gang carries each value at its own element width, so an explicit
binary32 operation is a native single-precision instruction rather than a wide
one rounded back: binary32 operations use `f32xN`, binary64 operations use
`f64xN`, and masks convert immediately after a comparison and immediately before
a select. Baseline and AVX2 still limit a mixed loop to two or four lanes
because `f64x8` has no register class there. AVX-512 admits `mixed8`, so one
binary64 running total no longer halves the lane count:

```bash
nupp aot --target x86_64-unknown-linux-gnu --features avx512f \
    bench/kernel-subset-spike/mixedwidth.nupp
```

```text
bench/kernel-subset-spike/mixedwidth.nupp: integrate, kernel, 5.67 operations per byte (136 over 24), mixed8, 8 lanes
```

The 64-byte shape is AVX-512-only. Compiling the same source for AVX2 reports
`mixed4`, and the x86-64 baseline reports `mixed2`; selecting a tier never
promises instructions the target did not name.

The fourth lever is the source itself, and it is the strongest one. On the
baseline and AVX2 tiers, writing the arithmetic through [](nupp.math.f32)
doubles the lane count, because it tells the backend the values are genuinely
32-bit rather than binary64 values that happen to be small. AVX-512 carries
eight of either, using the narrower shape when every value is 32-bit. That
source choice changes the program's meaning, giving different roundings and
different results, which is exactly why the compiler will not make it for you.

`mixedwidth.nupp` carries one binary64 running total and one binary64 step
counter. `mixedwidth_f32.nupp` is the same loop with both narrowed, so nothing
in it is wider than a 32-bit lane:

::: code-group
```nupp [mixedwidth.nupp]
local travelled = 0.0
local step = 0
-- ...
travelled = travelled + math.sqrt(...)
step = step + 1
```

```nupp [mixedwidth_f32.nupp]
local travelled = nupp.math.f32.narrow(0.0)
local step: int32 = 0
-- ...
travelled = nupp.math.f32.add(travelled, nupp.math.f32.sqrt(...))
step = nupp.math.i32.add(step, 1)
```
:::

At AVX2 the first reports `mixed4` and the second `f32x8`, from the same
arithmetic count over the same bytes:

```text
bench/kernel-subset-spike/mixedwidth.nupp: integrate, kernel, 5.67 operations per byte (136 over 24), mixed4, 4 lanes
bench/kernel-subset-spike/mixedwidth_f32.nupp: integrate, kernel, 5.67 operations per byte (136 over 24), f32x8, 8 lanes
```

### Vectorization limits

Ordinary Nupp has no vector type, no mask value, no shuffle, and no way to name
a width. An earlier design exposed `F32x8`, `I32x8` and boxed mask values, and
it was built, measured, and removed. Scalar source already gets target-selected
width, masks and divergent control flow, exact scalar tails, one source form
that works with the backend off, and the freedom to change gang shape later.

What replaced the boxed design is [explicit SIMD](#explicit-simd), whose values
exist only inside an `@aot` body and cannot escape it. See
[NEP 11](../neps/0011-simd.md) for more information.

::: deepdive
A boxed vector type would mostly restate a map loop, while adding decisions
about preferred versus fixed width, boxing outside `@aot`, escape rules, and
cross-target ABI. What a scalar loop genuinely cannot express is cross-lane
meaning: shuffles, transposes, prefix scans, fixed-tree reductions, gathers,
compress and expand. That is the case the non-escaping vocabulary answers, and a
kernel that merely vectorizes imperfectly is not it.
:::

## Explicit SIMD

An algorithm whose register is itself a data structure imports `nupp.simd`
inside an `@aot` body. `preferredU8()` selects the artifact tier's packed byte
species, 16 bytes for the x86-64 baseline and AArch64 NEON and 32 for AVX2:

```nupp
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot(lanes = false)
local function countQuotes(borrows source: span.Span<uint8>): uint32
    local species = simd.preferredU8()
    local cursor: integer = 0
    local found: uint32 = 0
    while cursor < #source do
        local bytes = species:load(source, cursor)
        local tail = species:tail(#source - cursor)
        local matches = bytes:equal(34)
        local valid = matches:andBits(tail)
        found = nupp.math.u32.add(found, valid:count())
        cursor = cursor + species.lanes
    end
    return found
end
```

Nothing in that source names a width. `species.lanes` is what the tier chose,
loads are span-checked, inactive tail lanes are zero, and `bits()` maps the
first logical lane to bit zero. The values and masks cannot leave the kernel:
they have no boxed Lua representation, so calling `preferredU8` under
`aot = "off"` is a named checking error, while importing the module without
constructing a species stays ordinary Lua.

`simd.tableU8x16` embeds one immutable 16-byte lookup table in the generated
code, and `lookup16` reads every lane through it, producing zero for indexes
outside 0 to 15 as the native table instructions do. `simd.paddedStringU8` views
a rooted string as complete blocks plus one zero-padded final block, which
`loadFull` and `loadTail` read.

### Mask aggregates

`simd.maskBits64` builds a `MaskBits64` from two uint32 words. It supplies
cross-word shifts, prefix XOR, bitwise combines, a carrying add, population
count, first-set and clear-first operations, without introducing a general
boxed `uint64` into ordinary Nupp:

```nupp
local function drain(bits: simd.MaskBits64): (uint32, uint32)
    return bits:firstSet(), bits:clearFirst():count()
end
```

SIMD vectors, masks, and these 64-bit mask aggregates may pass through
statically resolved pure AOT helpers, and multiple helper results use a private
native C result struct.

`add` is the one operation here that is arithmetic rather than bitwise, and it
is present for one reason: run parity over a block is stated as an addition.
Adding a run's start bit to the run propagates a carry to the first bit past its
end, which is how a scanner separates an odd run of escapes from an even one
without walking the runs. It carries between the two words, as the shifts do.

::: deepdive
The two `uint32` halves are deliberate. A general 64-bit integer would have to
answer for its LuaJIT representation and its exactness rules everywhere in
ordinary Nupp, where all this needs is a predicate bitmap that scanners can
combine, carry prefix state across, and drain without boxing cdata.

A receiver has to be a bound local or another method call in the same chain,
which is why the examples name their aggregates before operating on them.
:::

## Numeric guarantees

| Written | Computed as | Notes |
| --- | --- | --- |
| `a + b` on numbers | binary64 | not contracted, not reassociated |
| a `float` field read | binary64 | the physical load widens |
| a `float` field write | binary32 | the physical store narrows |
| `nupp.math.f32.add(a, b)` | binary32, one rounding | exact, see below |
| `nupp.math.f32.min`/`max`/`fma` | binary32, corrected | a helper repairs NaN behavior |
| `nupp.math.i32.add(a, b)` | wrapping int32 | wraps in unsigned, comes back |
| `nupp.math.u32.add(a, b)` | wrapping uint32 | native unsigned modular arithmetic |
| `int64` `+`, `-`, `*` in AOT | wrapping int64 | operates as uint64, then converts back |
| `uint64` `+`, `-`, `*` in AOT | wrapping uint64 | native unsigned modular arithmetic |

Ordinary floating-point arithmetic assumes round-to-nearest-even. Signed zero
and numeric NaN behavior are preserved. NaN signaling state, payload bits, and
floating-point exception flags are not observable guarantees. The bit-level
surface of `nupp.math.f32`, including its canonical NaN behavior, retains the
stronger guarantees described below.

Signed wrapping arithmetic is performed in the corresponding unsigned C type.
For int32 and int64 the modular result is converted back to the signed type;
generated native code relies on GCC 9 and Clang's documented modular
unsigned-to-signed conversion behavior.

A comparison whose operands mix these widths answers by mathematical value.
C's usual arithmetic conversions would instead decide it in unsigned
arithmetic -- converting `-1` above `5` -- so generated code widens an
`int32`/`uint32` pairing into `int64`, routes a signed operand against
`uint64` through a sign-checked helper, and meets a binary32 operand and an
integer in binary64. The interpreter, the constant folder, and generated
native code therefore agree on every mixed comparison; a 64-bit operand
beyond 2^53 meeting `number` keeps binary64's exactness boundary, because
the comparison itself is performed in binary64 there.

The binary32 operations lower to native single-precision instructions, and this
is exact rather than a relaxation: a binary32 operation over binary32 operands
computed in binary64 and rounded once is bit-identical to the native
instruction, because 53 ≥ 2 × 24 + 2.

`min`, `max` and `fma` are not covered by that argument. A differential over
every interesting binary32 value found they disagree with `fminf`, `fmaxf` and
`fmaf` in exactly one respect each: `nupp.math.f32` canonicalizes every NaN
where the instruction propagates a payload, and `min` and `max` return that
canonical NaN where IEEE `minNum` returns the operand that is not NaN. Both are
repaired by a select, so they are admitted with a correction rather than left
out.

`nupp.math.f32.exp` is instead defined by the scalar IR itself: clamp the input
to `[-104, 88]`, evaluate a degree-12 Taylor polynomial for `exp(x / 128)` in
Horner order with `fma`, then square seven times. The interpreter, native C,
SPIR-V, and derived Metal shader execute that same binary32 sequence; none asks
a platform math library to choose a result.

A width changes only at a conversion the IR writes down. An operator never
changes one, which is what keeps `float` a storage fact rather than an
arithmetic type:

::: code-group
```nupp [Nupp]
local wide = inputs[i].value
local doubled = wide + wide
local narrow = nupp.math.f32.add(nupp.math.f32.narrow(wide), nupp.math.f32.narrow(wide))
outputs[i].value = narrow + doubled
```

```c [Generated C]
double v1_wide = ((double)((&p_inputs[i])->value));
double v2_doubled = (v1_wide + v1_wide);
float v3_narrow = ((float)((float)(v1_wide)) + (float)((float)(v1_wide)));
float as1 = (float)((((double)v3_narrow) + v2_doubled));
((&p_outputs[i])->value) = as1;
```
:::

Every cast there answers to something the source said: the load widens, the
store narrows, `narrow` asks for binary32 twice and gets one single-precision
add, and adding it back to a binary64 promotes it rather than narrowing the
other operand.

An entry conversion takes a binary64, so an `int32` or `uint32` reaching one --
a counted-loop index handed to `nupp.math.u32.wrap`, say -- is promoted to
binary64 first, and that promotion is written down like any other. It is exact
for every 32-bit integer and establishes nothing: the conversion it is an
argument to is what establishes. Nothing narrows on the way in, so an operand
the source never established is still refused.

`nupp.math.u32.fromI32`, `nupp.math.i32.fromU32` and `nupp.math.u32.toI32` are
the exceptions, and are the ones to reach for between the two views of the same
thirty-two bits. They take the width they convert from rather than a binary64,
so nothing is promoted and nothing comes back: the emitted cast reinterprets
the bits it was already given. Going through `wrap` instead means a round trip
out to binary64 for a pattern that never left thirty-two, which is both slower
and narrower -- a value at or above 2^31 does not survive it.

A bitwise operator needs neither. Its operands normalize to thirty-two bits and
its result comes back signed, so where both operands already carry a width the
result is an established `int32` and flows straight into the next fixed-width
operation. Nothing has to be wrapped back to the width it never left:

```nupp
local function choose(e: int32, f: int32, g: int32): int32
    return (e & f) ~ ((~e) & g)
end
```

An exact integer literal is admitted anywhere a fixed-width value is, including
a shift count, a helper argument and the bound a cursor is compared against.
That last one is why a counted loop compares in its own width rather than
converting to binary64 to meet its bound.

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
luajit bench/kernel-subset-spike/mixedwidth_main.lua  # binary32 and binary64 in one gang
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

The scalar subset admits a
[switch](../concepts/switch-expressions.md) as the sole initializer of one local
when:

- the selector lowers to `f64`, `i32`, or `u32`;
- every case is an integer-valued numeric constant;
- every arm is one scalar expression; and
- the checker has proved the switch exhaustive, either from its cases or an
  `else` arm.

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

It lowers to one selector `Let`, one result `Let`, an ordered scalar-IR `If`,
and branch `Assign` operations. For an established `int32` or `uint32` selector,
lowering annotates that ordinary `If` with its exact-width labels and the C
emitter writes a native `switch` (temporary names are abbreviated here):

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

The annotation is optional: scalar-IR verification and lane rewriting may ignore
it and retain the complete equality chain. Nupp `integer` is normally binary64,
so those selectors deliberately remain equality branches rather than being
converted. Strings, type patterns, block arms, and early arm returns report the
ordinary subset boundary. The C compiler chooses the physical native
dispatch, and Nupp neither forces a jump table nor synthesizes a C perfect hash.

## Build policy

A build selects one policy, and an artifact records the one it was built under:

```lua
targets = {
   game = {kind = "modules", entries = {"game"}, outDir = "build/game", aot = "emit-c"},
}
```

- `off` does nothing. It is the default, so a project that has not asked for
  native code never needs a C compiler.
- `emit-c` verifies the IR and writes the C to `<outDir>/aot/`, without
  compiling it.
- `require` does everything `emit-c` does, then compiles the result into
  `<outDir>/lib/`, and fails the build when it cannot.
- `emit-wasm` compiles admitted entries into content-addressed Wasm side modules
  while retaining their ordinary Lua bodies.
- `require-wasm` packages those modules and replaces the Lua bodies with calls
  through the Lua-in-Wasm binding.

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

::: deepdive
There is deliberately no mode that quietly mixes compiled functions with
ordinary fallbacks. Disabling compilation is meant to change performance and
packaging, never an answer, and a policy that silently fell back per function
would make a benchmark unattributable and a numeric contract unenforceable.
:::

### Accepting a C compiler

Selecting `require` is how a project takes on a C compiler as a dependency.
Nothing else in Nupp makes it one, which is why `off` is the default.

The build looks for `NUPP_NATIVE_CC` first, then `clang`, `cc` and `gcc` in that
order:

```bash
NUPP_NATIVE_CC=/usr/bin/clang-18 nupp build
```

Clang leads because the emitter's contraction pragma is Clang's; GCC compiles
the same C correctly and declines to contract, which is slower and never
wrong. Naming a compiler that cannot build this C is an error rather than
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

The triple decides the available tiers, how a shared library is produced and
what it is called, so a Windows target gets a `.dll` and no `-lm` whether or not
the build is running on Windows. A ceiling is checked against that target's
architecture, so asking aarch64 for `avx2` is refused where it is written.

`emit-c` needs nothing installed for the target: it writes one C file per
`(source, tier)`, the baseline feature detector where selection is needed, and
`aot/units.json`. The manifest names every unit's tier and required instruction
flag, which is the handoff when the compiler for a platform is somebody else's.

`aot = "require"` cross-compiles too, and then it needs the target's headers and
libraries the way any cross build does. Give them through `aotCflags`, which is
appended after the fixed flags and is part of what the library is keyed on:

```lua
aotCflags = {"--sysroot=/opt/sysroots/linux-x86_64"},
```

The build owns CPU instruction and LTO flags when it carries several tiers.
`aotCflags` therefore refuses `-march`, `-mcpu`, AVX/SSE/FMA switches, `/arch:`
and `-flto`; any of those could put optional instructions in the baseline
fallback or optimize across the object boundary.

Without one, the failure names the missing thing rather than leaving you with
the compiler's own message about a missing `math.h`.

The flags are fixed:

```text
-std=c11 -O3 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror
```

`-Werror` is deliberate. This is compiler-generated C, so a warning in it is a
defect in the backend rather than a style opinion about someone's source. The
warning that matters most is `-Wpsabi`, which is how a vector with no register
class announces itself, and silencing it would make the target model pointless.
`-ffp-contract=off` is the numeric contract's floor; a body that asked for
contraction carries its own pragma.

That pragma is Clang's. Under GCC, `@relax("fp-contract")` compiles correctly
and does not contract, so the body is as accurate as the unrelaxed one and
slower than the same body under Clang. It is correct either way, and the
difference is worth knowing about before benchmarking across compilers.

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
so a rebuild never reuses an artifact built from a different body. `nupp check`
does none of this: it answers a question about the source as written, and never
needs a C compiler.

### Shipping a shared artifact

This section describes the default `aotLinkage = "shared"` route. A static
component ships its archive to the host build rather than carrying a `lib/`
sidecar; see [Static AOT components](build.md#static-aot-components).

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
sibling of it does too, which makes the output tree relocatable. The walk is
also why one form serves every layout: a module named `a.b.kernel` sits two
directories down and the same module inlined at the root of a bundle sits at the
top, and the library is in one place either way.

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
where, rather than with a missing symbol later on. See
[distribution.md](../reference/distribution.md) for the artifact kinds.

::: deepdive
A path decided at build time could not be relocatable: an absolute path pins the
program to one machine, and a relative one pins it to one directory. Resolving
against the loaded chunk is the only form that survives being copied, because
the loader has already proved that path works from wherever the program started.
:::

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

The linked library gets its own key, over every tier's artifact key and compile
flags plus the detector, compiler, and final linkage. Each translation unit is
compiled to an object under its own tier flag, then those objects are linked
without a higher-tier flag. Changing compilers relinks; rebuilding an unchanged
project does not. The C itself is deliberately not keyed on the toolchain,
because the C is the same C whoever compiles it. The library is validated the same
way and is just as disposable, so deleting it costs one relink.

## Limits

Named so you can tell what you are looking at:

- **Relocatable `kind = "c"` dependencies.** An ordinary C dependency's library
  is still named with the path the build wrote, so it has the problem `@aot`
  code no longer has. The `@` mechanism is general and would fix it; nothing has
  been changed there yet.

## FAQ

### Does `@aot` change what a function answers?

Only through `@relax`. Removing `@aot`, or building the same source under
`aot = "off"`, changes performance and artifacts and never the result, which is
what the differentials in [Verification](#verification) check. `@relax` is the
one annotation that changes the answer, and it says so per function.

### Why did my loop compile but run one iteration at a time?

Either the shape is outside what lane lowering admits, or the loop does too
little arithmetic per byte it touches to pay for assembling the vectors.
`nupp aot --check` exits 1 for the first case and names the construct; see
[Admitted loop shape](#admitted-loop-shape).

### Does a project need a C compiler?

Only under `aot = "require"`, `emit-wasm`, or `require-wasm`. `off` is the
default and `nupp check` never compiles C, so validating `@aot` source needs no
toolchain at all. See [Accepting a C compiler](#accepting-a-c-compiler) and
[Wasm AOT applications](wasm-aot.md).

::: seealso
- [jit-trace-checking.md](jit-trace-checking.md) for deciding whether LuaJIT
  can compile the loop you were about to annotate
- [performance.md](performance.md) for the rewrites applied to ordinary Nupp
- [](nupp.mem.span) for the span types a kernel takes
- [NEP 9](../neps/0009-ahead-of-time-compilation.md) and
  [NEP 11](../neps/0011-simd.md) for the design records
:::
