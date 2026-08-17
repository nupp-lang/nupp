# Checked AOT functions

Status: annotation and scalar-source SIMD prototype implemented; production
lowering remains planned; supersedes the `@kernel` and `@native` spellings

## Decision

Use `@aot` for the explicit contract that a Nupp function must compile as
one checked ahead-of-time unit:

```nupp
local span = require("nupp.span")

@aot
local function scaleAdd(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>,
    scale: float
): nil
    if output.count ~= input.count then
        error("length mismatch", 2)
    end

    for i = 1, output.count do
        output:set(i, input:get(i) * scale)
    end
end
```

`@aot` means the complete function is eligible for Nupp's checked AOT IR.
In an AOT-required build it must compile for every selected target or the
build reports why. In an AOT-disabled build the annotation is dormant and the
same ordinary Nupp body is emitted. It does not mean operating-system code,
imply a GPU, promise SIMD, or permit unsafe operations.

The initial backend is generated private C compiled by a pinned Clang. AOT IR
remains the safety boundary and the stable compiler architecture; C is a
deterministic backend representation. Direct machine-code emission is deferred
unless measured toolchain, latency, packaging, or specialization requirements
show that generated C cannot meet the release gates.

The earlier working names `@kernel` and `@native` are rejected for the public
annotation. `@kernel` suggests an operating-system kernel, GPU dispatch,
implicit parallelism, SIMD, and a separate language. `@native` conflates
compiler-generated code with FFI, handwritten C, and the output representation.
`@aot` names the execution choice users make: compile this ordinary Nupp body
during the build rather than depend on LuaJIT to compile it while it runs. The
term remains accurate if generated C is replaced by another AOT backend.

Internal documents may still call a benchmark workload or a foreign bulk
routine a native kernel. The compiler representation, commands, diagnostics,
and user-facing annotation use “AOT function” and “AOT IR.”

## Goal

Compile performance-critical Nupp functions to native machine code without
giving up Nupp's bounds, type, ownership, borrowing, aliasing, effect, and
suspension checks. A caller sees an ordinary typed Nupp function. The generated
wrapper validates and projects its arguments, crosses the Lua/native boundary
once, and translates modeled failures back to the source operation.

The feature provides a safe native boundary for:

- arithmetic over spans and reified structs;
- component-column, image, audio, geometry, matrix, codec, and checksum loops;
- scalar-source map loops that explicitly require SIMD lowering;
- small statically resolved helper graphs;
- scalar native work that does not benefit from SIMD.

The first implementation is intentionally a whole-function compiler. Region
outlining and transparent AOT compilation are later, separate optimizations.
They must not be prerequisites for an explicit `@aot` contract to be
understandable.

## Non-goals

- Do not embed C, C++, assembly, LLVM IR, or machine-code bytes in Nupp source.
- Do not maintain a private fork of LuaJIT.
- Do not treat `@aot` as `unsafe`; an unsafe operation remains unsafe and is
  initially rejected inside an AOT function.
- Do not promise SIMD merely because a function is AOT-compiled. A scalar lowering
  satisfies the contract.
- Do not promise automatic vectorization of every scalar loop. It is a backend
  optimization whose success must be inspectable.
- Do not add GPU execution, implicit threads, asynchronous launch, or a tensor
  runtime under this annotation.
- Do not admit arbitrary Lua calls, tables, strings, allocation, callbacks,
  coroutines, or dynamic dispatch in the first subset.
- Do not silently fall back per function when AOT compilation is required.
  Selecting an ordinary-only build is an explicit whole-build policy.
- Do not change numeric answers to obtain faster code. Relaxed floating-point
  behavior requires a separate explicit contract.
- Do not expose generated native code as a stable C ABI or object-file format.

## Contract, not another expression language

The body is ordinary Nupp. It uses the existing parser, name resolution, type
system, operators, loops, structs, spans, diagnostics, and source positions.
`@aot` adds a compilation and effect constraint after ordinary checking; it
does not reinterpret the body.

Removing `@aot` may change performance and generated artifacts, but not the
function's source-level result. Adding it may reject constructs the AOT
backend cannot represent, but may not make an otherwise invalid operation
valid. This is the same shape as `@jit`: an annotation can make an execution
property a checked requirement without inventing new expression semantics.

Eligibility is a versioned compatibility promise. Within a supported language
line, a source function accepted for a target remains accepted; the admitted
subset may widen but does not silently narrow. A backend regression is a build
error and compiler defect in AOT-required mode, never permission to fall
back just that function. The programmer can remove `@aot` or explicitly
select an ordinary-only build to choose ordinary execution.

### Build policy and portability

The build selects one policy before checking AOT eligibility:

- `aot=off` checks and emits every body as ordinary Nupp. It does not run the
  AOT subset checker, find a C compiler, generate C, or package native code.
- `aot=require` lowers every `@aot` body and fails if the source subset,
  target backend, compiler, SDK, or artifact validation is unavailable.
- `aot=emit-c` verifies AOT IR and emits private target C without running
  it. A platform build can hand that C to its vendor compiler.

There is deliberately no `auto` mode that quietly mixes successfully compiled
AOT functions with accidental ordinary fallbacks. A build artifact records one
policy. Disabling compilation changes performance and packaging only; the
ordinary body remains the semantic implementation and differential oracle.

Cross-compilation runs the same front end and IR verifier with the selected
target layout, then invokes the selected target C compiler/sysroot or exports C
for a vendor build. It never probes target CPU features by executing target
code. Consoles may use `require` with their SDK or `off` when AOT integration
has not been enabled for that platform.

The annotation applies to local and named functions with visible Nupp bodies.
It is rejected on constructors, inline interface requirements, bodyless
declarations, `cdef` functions, and arbitrary function-typed bindings in the
first release. A later declaration file may describe a previously compiled
AOT implementation, but that is a packaging contract rather than the source
feature.

At runtime the declaration still denotes a Lua-callable wrapper. Taking its
function value, storing it, comparing it, and calling it dynamically use that
wrapper. Statically resolved calls from one AOT function to another may use
a private direct convention without changing the public function value.

## Relationship to existing features

### `@jit`

`@jit` checks that a function avoids known LuaJIT trace-unsafe FFI boundaries.
`@aot` bypasses LuaJIT for the function body. They are mutually exclusive:
stacking them is an error because the two contracts name different compilers
for the same body.

The existing `nupp bc --check` command continues to answer LuaJIT traceability.
AOT functions receive separate IR and machine-code inspection commands.

### C interop and checked external kernels

`cdef`, `cheader`, and `countedBy(count)` describe code implemented outside
Nupp. Their implementation is trusted even when their pointer/count boundary is
checked. `@aot` instead compiles visible checked Nupp source. It needs no
duplicated C struct, header, handwritten wrapper, or foreign library declaration.

The checked native-kernel spike remains valuable evidence and a performance
baseline. Its `countedBy` wrapper proves the desired one-call ABI; its C and
DynASM bodies do not become the safety model for `@aot`.

### SIMD source model

The [portable-vector decision record](037-portable-vectors.md) compared boxed
ordinary vectors, explicit vectors confined to AOT, and scalar-source lane
parallelism. The initial surface is one ordinary scalar body with an optional
required setting:

```nupp
@aot(simd = true)
local function advance(...): nil
    for i = 1, count do
        -- ordinary scalar Nupp
    end
end
```

Bare `@aot` promises compilation but not SIMD. `simd = true` additionally says
the function has exactly one top-level numeric map loop whose iterations are
independent and which must receive a SIMD lowering. It takes no lane count. A
backend refusal is a build error, not permission to run that AOT body scalar.

No explicit vector or mask value type lands with this surface. The experiment
showed those values would create a second spelling and escape model for work the
Tecs-oriented slice expresses as an ordinary map loop. Cross-lane algorithms
remain deferred until they independently justify another language feature.

### Embedded C

Literal C is not a competing safe implementation. Nupp can validate its ABI
and inspect a Clang AST, but arbitrary C retains pointer provenance, undefined
behavior, preprocessor, promotion, cast, and toolchain-version hazards. A C
subset restricted enough to recover the guarantees below is a second spelling
of the AOT IR with worse diagnostics.

Use generated C as a private backend experiment and ordinary C dependencies as
an explicit foreign escape hatch. Do not add `native do` or
`native c function` as part of this feature.

## Admitted source model

### Values and storage

The first subset admits:

- `nil`, `boolean`, basic binary64 `number` operations, fixed C numeric storage
  types, and integers where their exact AOT semantics are specified;
- mutable local scalar bindings, multiple assignment, and immutable compile-time
  constants;
- reified Nupp structs containing admitted fields;
- `Span<T>`, `WriteSpan<T>`, and fixed variants over admitted elements;
- fixed C arrays whose layout is known for the selected target;
- compiler-internal vector and mask values produced only by a verified SIMD pass;
- private compiler status and multiple-result slots at the wrapper boundary.

It declines:

- `any`, `unknown`, unsupported `number` operations, `string`, `table`, ordinary
  records, threads, and userdata;
- GC-managed or dynamically sized fields;
- raw pointers, variable C arrays, cdata of unknown layout, and arbitrary FFI;
- owned, pinned, retained, or dynamically registered resources;
- closures, upvalues other than quotable immutable constants, and varargs;
- mutable globals or replaceable module fields.

"Declines" means a stable `@aot` diagnostic when compilation is required.
The ordinary body is still available only through the explicit ordinary build
policy; it never excuses one unsupported function inside a required build.

### Control flow

Admit structured conditionals, numeric loops, `while`, `repeat`, `break`,
`continue`, ordinary returns, and statically resolved calls within a bounded
AOT helper graph. `goto` waits until AOT IR source maps and cleanup edges
can represent every existing rule without a special case.

Recursion, protected calls, yields, suspension handling, unknown callbacks,
metamethod dispatch, and dynamic function calls are rejected initially. Bounded
recursion may be considered only after stack limits, failure behavior, and code
cache cycles are specified.

The function is non-suspending by construction. This is derived and exposed in
its function effects; the user need not stack `nosuspend` syntax around it.

### Calls

An AOT body may call:

- another statically resolved `@aot` function;
- a private AOT helper generated from an eligible visible Nupp body;
- a closed compiler-owned set of pure numeric and layout intrinsics;
- span operations whose semantics are lowered directly rather than dispatched
  through Lua.

It may not call arbitrary C merely because the C function is declared. Foreign
calls need target ABI, unwind, alias, retention, callback, and side-effect
analysis of their own. A later phase may admit a small leaf allowlist with
complete contracts, but no unknown symbol enters AOT IR.

Calling an ordinary visible Nupp helper does not silently clone it into the
AOT graph. Either mark it `@aot`, make it a compiler-recognized intrinsic,
or inline it through a future explicitly documented rule. This keeps code-size
growth and cross-module invalidation visible.

### Tecs 80% slice

The ordinary language facilities this slice should consume are planned in
[Independent foundations for AOT lowering](041-aot-independent-foundations.md).
They land and are accepted without `@aot`; this plan owns only their later
consumption by AOT verification and lowering.

The first Tecs-oriented slice is an archetype-range function, not a whole ECS
system. Query selection, scheduling, structural changes, events, dirty tracking,
and dispatch remain ordinary Nupp. One call receives dense component spans plus
an inclusive row range and performs all per-row work natively.

Its required source coverage is:

1. A readable exclusive span plus a bounds-checked mutable element reference
   tied to the writer. `WriteSpan.getMut` and `set` provide this without
   AOT-only syntax.
2. Reified component structs, field loads/stores, and a target layout witness
   covering size, alignment, field offsets, and field C types.
3. Inclusive ranged iteration and ordinary span slices, including empty ranges
   and nonzero underlying offsets.
4. `int32`/`uint32` component fields, conversions, comparisons, bit operations,
   and shifts with the ordinary LuaJIT semantics written into AOT IR.
5. Mutable initialized locals and simultaneous multiple assignment. The first
   structured IR may model verified mutable slots; production SSA construction
   must add dominance and phi verification before optimization.
6. Static helpers with multiple scalar results, lowered through compiler-owned
   result structs without a Lua transition between caller and helper.
7. The closed ordinary `math` surface commonly used by systems: min/max,
   roots, rounding, trigonometric and hyperbolic functions, `atan2`, exp/log,
   powers, remainder, and degree/radian conversion. Each is independently
   eligible; a transcendental call may inhibit SIMD and inspection must say so.

The current spike exercises all seven in ordinary Nupp source and generated C.
It also exposed two language/library prerequisites that belong below the AOT
pass: forwarding an exclusive parameter through a checked wrapper when no
derived borrow is live, and a checked mutable element borrow from `WriteSpan`.

One ABI integration feature remains: Track A of the independent foundations
must supply the canonical C description and typed ordinary-struct pointer
bridge. Ordinary structs remain anonymous LuaJIT ctypes; generated headers and
generated C share the one canonical named aggregate, while compiler-owned glue
may erase a physical pointer slot internally after source typing and layout
verification. The spike's ad hoc `void*` binding is evidence only. The AOT
pass must consume Track A rather than invent another struct name or bridge.

## Memory safety and ownership

### Spans are the public memory boundary

AOT functions do not accept a naked pointer/count pair from checked source.
A shared span projects a const pointer for the duration of the call. A writable
span projects a mutable pointer only under an exclusive borrow. The wrapper
applies the span's private offset, carries its count, and performs all required
width conversions before AOT entry.

Loads and stores retain Nupp's one-based span indexing. The AOT IR contains
the logical index, span length, access width, source site, and region identity.
It never treats a projected address as proof of a bound.

The checker or IR verifier must prove an access in range or emit a modeled
check. An unchecked access, pointer cast, integer-to-pointer conversion, or
unknown pointer arithmetic has no AOT IR opcode in the safe subset.

### Aliasing

`borrows` permits shared aliases. `exclusive` requires sole access to its
region. Sibling regions produced through `WriteSpan.splitAt` carry disjoint
partition paths, so they may be simultaneous exclusive parameters. The same
region twice, or a child with its ancestor, is rejected before code generation.

The IR preserves these facts explicitly. A backend may emit C `restrict`,
reorder memory operations, or eliminate loads only for regions Nupp proved
disjoint. Constness alone never implies non-aliasing.

AOT helpers receive the same region identities through their call edges.
Erasing a value through gradual or unsafe code prevents AOT compilation; it
never manufactures a stronger alias fact.

### Ownership and cleanup

The first subset accepts no live owner at AOT entry and creates none inside.
That excludes allocation and cleanup rather than trying to unwind AOT frames
through LuaJIT. A span borrowing an owner may enter because the wrapper keeps
the root and borrow live until the call returns.

Owned values, automatic destruction, `takes` parameters, affine closures, and
resource sets may be admitted later only after AOT IR models every normal,
error, and cancellation exit. `unsafe do` does not bypass this staging rule.

## Numeric semantics

AOT-lowered scalar operations owe the same specified result as their ordinary
Nupp counterparts. The AOT compiler must not inherit whatever overflow, shift,
NaN, contraction, denormal, or fast-math behavior a C compiler happens to use.

### AOT v1 preserves the current numeric tower

Fixed C storage types do not currently imply same-width expression arithmetic.
Loading a `float` cdata slot produces a Lua number containing the stored
binary32 value, ordinary operators compute with LuaJIT binary64 semantics, and
storing into a `float` slot narrows the final result. Local fixed-width
annotations do not turn those operators into binary32 or wrapping integer
operations. AOT IR must represent the same loads, conversions, binary64
intermediates, and stores explicitly.

This means the initial AOT subset must support basic `number` arithmetic; it
cannot decline `number` while claiming to compile an ordinary expression over
float struct fields. Start with binary64 `+`, `-`, `*`, `/`, comparisons, and
explicit store narrowing. Add remainder and each `math` operation only after
its LuaJIT result and failure behavior have a target-independent lowering or a
tested runtime call. Do not contract `a * b + c`, reassociate expressions, or
silently replace binary64 work with binary32 to gain more SIMD lanes.

The released `nupp.math.i32`, `nupp.math.u32`, and `nupp.math.f32` operations
remain the explicit ordinary semantics for wrapping 32-bit and per-operation
binary32 work. AOT IR recognizes their canonical intrinsic identities and may
lower them directly. Their Lua implementations remain the differential oracle.

For each admitted operation, the AOT IR states:

- signed or unsigned interpretation;
- result width and overflow behavior;
- comparison behavior;
- shift masking or rejection;
- conversion rounding and out-of-range behavior;
- floating NaN, infinity, signed-zero, and subnormal behavior;
- whether one fused rounding was explicitly requested.

Default floating expressions are not reassociated and `a * b + c` is not
contracted implicitly. That rule has a measured price. On an Apple M1,
the spike's Mandelbrot kernel runs 2.38x faster when Clang is allowed to
contract (60.9 ms to 25.6 ms), and the escape counts change: a checksum over
46.4 million iterations moves by roughly 37,000. Go makes the opposite choice
and fuses by default on arm64 while not fusing on amd64, so the same Go program
gives two different answers on two targets and is 2.38x faster on one of them.

Keeping contraction off is what makes an AOT function's result a property of the
source rather than of the target that happened to compile it, which is the whole
claim in this section. But the cost is large enough that `fma` as an explicit
operation, and a separately named opt-in contract for code that wants fusion,
are worth more than a footnote. `nupp.math.f32.fma` requests one fused binary32
operation. Reductions state their lane order. No backend uses `-ffast-math` or
an equivalent flag under the default contract.

Subset growth follows semantics rather than spelling convenience. `sqrt` may
enter through a closed intrinsic only after its ordinary result and target
rounding are specified. Stencil loads require affine bounds or explicit halo
facts plus verified region relationships. Reductions remain source-ordered by
default; a vector tree reduction needs a separately named fixed-tree or relaxed
contract because reassociation changes floating-point answers.

Nupp `integer` operations continue to widen exactly where ordinary checking and
LuaJIT do. Any operation whose ordinary semantics do not map cleanly to one
target operation waits for differential tests and a written exactness rule,
not a convenient host cast.

### Do not scope arithmetic semantics to structs

Structs remain storage and layout declarations. They are not numeric execution
contexts. None of these rules is acceptable:

- a fixed-width operator applies only when its operand was loaded from a struct;
- arithmetic inside a struct method differs from the same arithmetic in a free
  function;
- assigning a field to a local widens or changes its operator semantics;
- a scalar is wrapped in a one-field cdata struct to obtain FFI metamethods.

The first three make refactoring change answers. The fourth changes the C ABI,
creates boxed aggregate intermediates, cannot provide LuaJIT 2.1 bit-operator
metamethods, and sabotages both fallback and AOT optimization. A value's
numeric semantics must follow its static value type through parameters, locals,
returns, fields, arrays, and spans. Container origin and lexical location may
not participate.

For example, these must never differ merely because one field was named:

```nupp
local direct = particle.velocity * scale
local velocity = particle.velocity
local extracted = velocity * scale
```

If `direct` is binary32, `extracted` must be binary32 too. If both use ordinary
binary64 operators, assigning the field to a local must not opt into another
numeric mode.

Struct fields already provide the safe limited feature: `float`, `int32`, and
`uint32` specify storage layout and narrow when written. That is useful for C
interop and compact component columns, but it is not fixed-width expression
arithmetic and must not be presented as such.

### Checked refinements before AOT

The proposed [fixed-width refinement plan](045-fixed-width-refinements.md) makes
`float`, `int32`, and `uint32` honest unboxed value refinements without changing
operator semantics. Arithmetic still widens to `number`; an internal dataflow
fact records whether a reified load, conversion, intrinsic, literal, or checked
call actually established the refinement. Erased `as` does not create that
fact.

AOT consumes whichever numeric model has already shipped; it does not introduce
the refinement itself:

- without checked refinements, a scalar `float` annotation on a parameter does
  not prove a binary32 value and must use the ordinary binary64 ABI semantics;
  `int32` and `uint32` annotations likewise grant no range assumption;
- after checked refinements ship, every checked call to a refined parameter
  requires an established argument, so a private AOT ABI may carry C `float`,
  `int32_t`, or `uint32_t` without changing the AOT-disabled answer;
- reified struct, array, and span loads carry their established value types in
  either build;
- fixed-width intrinsics consume and produce establishment facts, allowing AOT
  to lower their explicitly requested semantics directly.

Do not repair a missing fact by rounding in the generated AOT wrapper. The
ordinary-only build has no corresponding wrapper conversion, so that would make
`@aot` change numeric semantics. The call is rejected before backend work or
the scalar uses its ordinary wider ABI, according to the released type model.

Do not add parallel `f32`, `i32`, or `u32` type names, promote ordinary
operators to fixed-width operations, or attach numeric behavior to a struct or
`@aot` context. A later proved-identical backend optimization may select a
native float operation for one binary64 operation over established binary32
inputs followed by a store, but only under the proof and differential gates in
the refinement plan.

## Errors and observable behavior

Generated native code does not raise or unwind through the LuaJIT FFI frame.
Potentially failing operations return a compact status and source-site ID to
the wrapper. The wrapper then raises the ordinary Nupp error with the modeled
message and source attribution.

This covers at least:

- span bounds and length preconditions;
- checked numeric conversion and arithmetic failures where Nupp defines one;
- explicit `error` with a closed compile-time string and level supported by the
  source map;
- backend-independent guards introduced by an admitted intrinsic.

Dynamic error values, arbitrary error levels, `pcall`, user metamethods, and
cleanup during unwinding remain outside the first subset.

The function preserves Nupp's observable guarantees by default. Inlining a
AOT helper may remove a frame only when the existing `frames` guarantee is
relaxed. Hoisting a check may move an error site only when `error-site` is
relaxed. AOT compilation itself does not silently grant either permission.

## AOT IR

The compiler lowers the checked body into a typed, source-independent,
static-single-assignment IR. It is deliberately smaller than Nupp and target
instruction sets. It contains:

- scalar, struct, vector, mask, pointer-capability, count, and status values;
- blocks, branches, phis, checked calls, and returns;
- typed arithmetic, comparison, conversion, and explicit numeric contracts;
- bounds-aware loads and stores with region identity and access width;
- struct field projections from target-validated layouts;
- vector operations when selected;
- source file, line, column, and semantic operation for every failure site;
- no Lua object, table, GC, coroutine, callback, arbitrary address, or
  exception instruction.

The IR verifier is part of the safety boundary. Before any backend sees a
function it validates:

- opcode and operand types;
- control-flow edges, dominance, and phis;
- every memory root, region, bound, alignment, and mutability;
- call signatures and helper graph limits;
- result initialization on every path;
- stack, block, value, instruction, and generated-code resource limits;
- target layout fingerprints and CPU feature requirements;
- source-site references and status ranges.

The serialized form is versioned, deterministic, bounded, and included in
build hashes. It is not a trusted instruction stream. Cache corruption or an
unknown version causes regeneration or a build failure, never execution.

Initial optimization is deliberately restrained:

- constant propagation and dead operation removal;
- redundant bounds and length check removal;
- loop-invariant movement only when error order remains permitted;
- common load elimination only under proven immutable or exclusive regions;
- bounded helper inlining under the `frames` contract;
- target-independent strength reduction with identical numeric behavior;
- compiler-internal vector compare/select and FMA fusion;
- no floating reassociation or speculative deoptimization.

## Backend decision

The safe language contract stops at verified AOT IR. Backend selection must
not change which source is admitted or which answer it produces.

### Generated C and Clang

An AOT experiment emits private C from AOT IR, compiles it with pinned flags,
and loads or links the resulting object. Users never write or edit this C. The
experiment benefits from Clang's optimizer, register allocator, auto-vectorizer,
debug information, and mature target coverage.

It must still validate:

- the exact Clang version and flags in the artifact key;
- generated prototypes, struct size, alignment, offsets, and calling convention;
- absence of fast-math and undefined signed-overflow assumptions;
- undefined symbols, relocations, constructors, TLS, writable globals, and
  unexpected sections in the resulting object;
- declared target features against the packaged artifact and runtime dispatch;
- diagnostics mapped back through generated line tables to Nupp source.

Generated C is a backend representation, not a new trust boundary. The emitter
must avoid undefined C expressions even where AOT IR has well-defined wrap
semantics.

The disadvantage is toolchain availability and cache reproducibility. A build
requiring a host Clang is not the final zero-setup experience unless Nupp ships
or prebuilds every required target artifact.

During the generated-C experiment, Clang is a conditional dependency only for
`aot=require`. `aot=off` does not probe for it, and `aot=emit-c` stops
before compilation. Production must either ship the supported toolchain,
integrate each target vendor compiler, validate prebuilt artifacts, or choose
direct emission. A required AOT function never falls back merely because a
compiler is absent.

#### Translation-unit batching

Generated C is compiled in batches rather than one translation unit per AOT
function. A Clang invocation on one admitted kernel is dominated by process
startup and by parsing the generated prelude of canonical aggregates, layout
witnesses, and intrinsic declarations; codegen for the function itself is small
beside it. Emitting one translation unit per function pays that fixed cost once
per function and buys nothing.

The batch unit is the module. That matches the granularity the rest of the
compiler already invalidates at, so editing one body recompiles one batch,
while a cold build spanning several modules still produces several translation
units and occupies several cores. One whole-build translation unit is rejected:
it makes every edit a full rebuild and serializes cold compilation onto one
core.

Batching is a latency and packaging decision only. It may not change which
source is admitted or which answer it produces, so:

- Functions sharing a translation unit must not become inlinable into one
  another merely by sharing it. Any function whose frame is observable is
  emitted with explicit inlining suppression. Cross-function inlining remains
  governed by the `frames` contract and the AOT call graph, never by batch
  membership.
- Static helpers, constants, and compiler-owned result structs are mangled from
  the same identities that key their artifacts, so co-tenancy cannot collide
  two distinct helpers or silently merge them.
- Batch membership and emission order are deterministic, derived from a stable
  sort of the batched identities. A rebuild batching the same functions produces
  a byte-identical translation unit and object.

Measure a precompiled prelude before assuming the batch boundary is the whole
answer. The prelude is compiler-generated and should be stable across generated
translation units, so precompiling it removes the same parsing cost without
making unrelated functions share a compilation. N0 records per-function,
per-module, and precompiled-prelude compile latency so the production choice
follows a measurement rather than this paragraph.

`aot=emit-c` emits the same batches. A vendor or console build integrating one
file per module is a far easier contract than one file per AOT function.

### Direct DynASM emission

DynASM provides instruction encoding, labels, relocation, and compact runtime
specialization. Nupp still owns instruction selection, liveness, scalar and
vector register allocation, spills, stack layout, ABI lowering, CPU dispatch,
source maps, and IR validation.

The x86 DynASM backend has substantial SSE, AVX, and AVX2 coverage. ARM64
currently lacks a general SIMD vocabulary, so production work extends its
instruction table for the admitted NEON subset and verifies each encoding
against an independent assembler. The existing `.long` spike is evidence, not
the production abstraction.

Direct emission removes the deployed C compiler dependency and permits cheap
runtime specialization. Its cost is building and maintaining the middle and
back end of a small compiler. Production builds pin or vendor DynASM and ship
its license; they do not fetch it while compiling a program.

### Backend review gate

Use one AOT IR corpus and retain direct-emission spikes as independent code
shape evidence where useful. Reconsider the generated-C decision only after
measuring:

- correctness and target parity;
- cold compile latency and cache hit latency;
- code size and steady-state throughput;
- diagnostic and source-map quality;
- cross-target and offline build requirements;
- executable-memory policy and packaging complexity;
- ongoing instruction and ABI maintenance.

It is valid to replace generated C later when the same verified AOT IR and
numeric contracts feed the replacement. It is not valid to expose
backend-specific source semantics and call that migration compatible.

## ABI and dispatch

### Lua wrapper

Every public AOT function has one generated Lua wrapper. Before entry it:

1. checks relationships not already proved at the call site;
2. projects span pointers with their private offsets and counts;
3. retains roots and borrow barriers for the call;
4. converts admitted scalars to the private target ABI;
5. selects or loads the native body;
6. performs one physical call;
7. translates status and results back to Nupp values.

No descriptor, callback, closure, or heap allocation occurs per element. A
zero-length call still enters the native body once unless the body is proved to
have no observable operation and removing the call preserves all guarantees.

Multiple results use a compiler-owned result struct or out storage. The wrapper
checks that every result is initialized before exposing it. Vector arguments
and results use private ABI slots rather than promising a platform vector ABI
to user code.

### AOT-to-AOT calls

Known AOT callees use a private direct convention and propagate status
without returning through Lua between calls. The compiled call graph records
callee fingerprints and CPU requirements. Unknown or dynamic callees are not
admitted.

Cross-module calls may consume semantic AOT IR from a module summary, but an
implementation-body edit should not invalidate unrelated dependants merely to
inline it. Direct linking and bounded cross-module inlining have separate cache
edges.

### CPU features

The host reports one immutable executable feature set per process. Generated
versions declare exact requirements. Selection checks both CPU and operating-
system state, particularly before AVX family instructions whose register state
must be enabled by the OS.

Start with:

- scalar AArch64 and x86-64;
- NEON 128 for explicit or selected vector IR;
- SSE2 128 on x86-64;
- AVX2 256 and FMA as later independent feature tiers.

One source artifact may contain or cache several versions. A target without an
implementation fails an AOT-required build; an explicitly ordinary-only
target emits the ordinary body for every AOT annotation.

## Artifacts, executable memory, and workers

AOT cache keys include:

- semantic AOT IR and version;
- target triple, data layout, ABI, and CPU feature tier;
- numeric-contract version;
- backend and pinned tool revision;
- optimization level and every behavior-affecting flag;
- direct callee fingerprints where applicable;
- translation-unit batch membership and order where a batched backend produced
  the artifact.

Cached data is never load-bearing. Validate it before mapping or linking, and
regenerate after corruption or version mismatch.

`aot=emit-c` carries the components that exist while the artifact is a text
file: the IR and its version, the numeric-contract version, the triple and
feature tier, the backend, and the compiler fingerprint. It records the key in
the build state and validates it by re-reading the artifact, so a deleted or
edited file is written again rather than believed.

The rest join the key as the thing they describe arrives. Data layout and ABI
are the triple's until a target selects them separately. Optimization level and
flags need a toolchain, which `require` introduces. Callee fingerprints need a
call that survives lowering; the subset inlines every one. Batch membership
needs a batched backend; a translation unit is one source. Adding a component
later invalidates every artifact, which costs a regeneration.

Direct code generation follows W^X: allocate writable memory, encode and
relocate, flush the instruction cache where required, then make it executable.
Hardened Apple hosts require `MAP_JIT` and the platform JIT write-protection
policy integrated with the Nupp host. The compiler may not silently weaken
W^X. A platform that cannot satisfy the policy cannot build or run the
corresponding `@aot` artifact.

Machine code and immutable metadata may be shared across worker states. Lua
wrappers, cdata boxes, roots, errors, and anchors remain state-local. Generated
code keeps no Lua heap pointer after return. Code retirement waits until no
thread can execute the body.

Hot reload invalidates a function's dispatch entry before installing a changed
version. An already-entered call may finish against its old immutable body; no
later call may enter it. Changed signatures, captured constants, layouts,
numeric contracts, or helper graphs are restart boundaries until migration is
explicitly designed.

## Inspection and diagnostics

AOT compilation must never be a silent performance story. Add:

```sh
./bin/nupp aot inspect FILE LINE COLUMN
./bin/nupp aot ir FILE FUNCTION
./bin/nupp aot code FILE FUNCTION --target=aarch64-neon
```

`inspect` reports the selected source function, admitted types and effects,
wrapper checks, direct callees, backend, target versions, code-cache state,
vectorization or scalarization, and the first reason compilation failed.

`ir` prints source-attributed checked AOT IR. `code` prints decoded machine
instructions beside source lines and feature requirements. Tests assert decoded
instructions, not byte substrings alone. These commands inspect rather than
benchmark, so their structural answer is deterministic.

Reserve a diagnostic family after the repository-wide code inventory. It must
cover at least:

- `@aot` on an invalid target or bodyless declaration;
- an unsupported value, operation, call, effect, capture, or control edge;
- a live ownership or suspension obligation at the native boundary;
- a target layout or ABI mismatch;
- an AOT call graph cycle or generation resource limit;
- an invalid, stale, corrupt, or over-limit AOT IR artifact;
- unavailable target backend or executable-memory policy;
- a backend failure with mapped Nupp source context;
- `@aot` combined with `@jit` or a conflicting future contract.

Every diagnostic explains whether the source can be rewritten, the annotation
removed, or the missing target support selected. No diagnostic suggests
`unsafe` as a way to bypass AOT eligibility.

## Delivery

### N0: Semantics and backend spike

Keep the surface test-only. Lower structured scalar span loops to a minimal
AOT IR and generated C/Clang. Cover multiple disjoint outputs, potentially
aliasing inputs, locals, branches, pure static helpers, and closed math
intrinsics. Add x86-64 execution on an actual x86 runner rather than
extrapolating from cross-compiled code.

Use the existing integration workload, an arithmetic-heavy register-resident
chain, a branch-heavy loop, a reduction, zero through seventeen elements, and
deliberate length and bounds failures.

#### N0 exit criteria

- Forced-scalar and optimized C match ordinary Nupp bit-for-bit for all values,
  failures, and loop lengths.
- Each complete workload makes one Lua/native transition and no allocation per
  iteration.
- AOT IR contains no unbounded address operation or unmodeled call.
- Decoded output contains the expected scalar or vector operations and no
  per-lane helper calls.
- The spike records compile time, warm cache time, code size, wrapper cost, and
  throughput.
- Optimized code shape is inspected and every discrepancy from the scalar
  oracle is explained before widening the admitted subset.

Nothing public lands if N0 cannot keep AOT IR independent of its backend.

### N1: Annotation and checker contract

Reserve `@aot` as a function annotation taking only the optional literal
`simd = true`. Implement target
validation, mutual exclusion with `@jit`, admitted types and effects, helper
graph checking, deterministic AOT IR, verification, diagnostics, formatting,
reference generation, documentation, semantic tokens, completion, hover,
module summaries, and incremental hashes.

At this slice the build may use only the selected development backend and an
explicit experimental target flag. There is still no fallback for an annotated
function.

#### N1 exit criteria

- The example function checks, builds, and runs without a handwritten C
  declaration, raw pointer, or duplicated struct.
- Every unsupported construct receives one source-local diagnostic before a
  backend runs.
- Removing `@aot` from accepted source preserves its ordinary Nupp answer.
- Equivalent functions produce byte-identical AOT IR and hashes.
- Module summaries never expose private ABI layouts as public type promises.

### N2: Spans, structs, and failures

Complete the safe memory boundary: shared and writable spans, fixed spans,
slices with nonzero offsets, sibling writable partitions, target-validated
struct layouts, multiple results, preconditions, bounds failures, and source-
attributed status returns.

#### N2 exit criteria

- Checked source cannot forge a pointer, count, region, layout, or mutable
  alias accepted by AOT IR.
- Every access is proved or checked, including zero length and the last valid
  and first invalid element.
- The wrapper keeps all roots and exclusive barriers live through the physical
  call and releases them on every modeled result.
- Generated code retains no pointer or Lua-owned value after return.
- Sanitizer and guard-page development tests agree with static verification;
  sanitizers remain corroboration rather than the safety claim.

### N3: Backend and target support

Productionize the selected backend on AArch64 and x86-64. Implement CPU feature
reporting, target versions, artifact validation, W^X, hardened Apple policy,
cache limits, worker sharing and retirement, hot reload invalidation, decoded
inspection, and offline packaging.

Keep the rejected backend as an oracle where its maintenance cost is small. If
generated C wins, pin the toolchain and solve offline availability. If direct
emission wins, independently verify admitted instruction encodings and ABI
sequences.

#### N3 exit criteria

- Supported targets build and run with no undeclared network or host-tool
  dependency.
- Feature selection never executes an instruction unavailable to the CPU or OS.
- Corrupt or incompatible cache entries never become executable.
- Concurrent compile, call, reload, and retirement tests execute no freed code
  and share no Lua state.
- Machine-code inspection explains every target version and AOT call edge.

### N4: AOT helper graphs and optimization

Add statically resolved AOT-to-AOT calls, bounded inlining, loop
optimization, alias-aware load elimination, and required scalar-source SIMD
lowering. Preserve observable guarantee checks for frames,
errors, and numeric transformations.

#### N4 exit criteria

- Direct AOT calls do not bounce through Lua and propagate modeled status
  correctly.
- Inlining and specialization have per-function and process limits.
- An implementation edit invalidates only the cache edges that consumed it.
- Inspection distinguishes scalar, opportunistically auto-vectorized, and
  required SIMD code.
- Optimization level zero remains a correct minimally transformed oracle.

### N5: Widen scalar-source SIMD

Keep vector and mask temporaries compiler-internal. Extend
`@aot(simd = true)` from straight-line map loops to verified mask stacks, lane
retirement, selected reductions, helpers, and inner loops. Each extension must
preserve scalar Nupp evaluation and pass the lane-IR verifier before emission.

The experimental C spike now proves the control-flow slice: it lowers nested
conditionals, pure-and-total short-circuit boolean expressions, data-dependent
inner `while` loops, and per-lane `break`/`continue`. It maintains distinct live
and currently-executing masks, materializes each branch mask before executing
the branch, and uses a horizontal `any` only for loop termination. Ordinary
Nupp, forced-scalar C, and four-lane binary64 C agree exactly, including scalar
tails. This is evidence for the production IR design, not completion of N5:
the implementation still has to move under `src/` and consume the complete
checked fact graph. Selected reductions, helper graphs, nested numeric loops,
and uniform inner loops remain open.

Do not add public explicit vectors alongside this surface. Reconsider them only
for a cross-lane workload that scalar map semantics cannot express and whose
benefit justifies a distinct language feature.

### N6: Carefully widen the subset

Consider fixed allocations, owned values, selected foreign leaf calls,
recursion, richer errors, and outlining separately. Each addition requires a
complete IR model for normal and failure exits, ownership and alias transport,
source attribution, backend parity, differential tests, and an independently
measured workload.

Do not add a construct merely because Clang or the host CPU can execute it. The
question is whether Nupp can preserve its contract across every backend and
target.

## Turning it on

The delivery stages above are about what the backend can do. This is about what
stands between that and a user writing `@aot`, running `nupp build`, and getting
native code -- written down after the backend landed under `src/`, because
several of these were only visible from there.

Two goals hide in "make it real", and the smaller one is the plumbing. A user
writing a natural kernel today meets *one `@aot` function per file*, or *a
uniform inner loop gets no lanes*, long before meeting *it is not wired into the
build*. Most of what makes the feature feel unfinished is the width of the
admitted subset, not the absence of a build step.

### The decision that gates the rest

What happens where the generated C cannot be compiled.

The emitter needs `__attribute__((vector_size))` and `__builtin_convertvector`.
GCC 9 and later and every Clang have both; **MSVC has neither**, so the Windows
job cannot run this backend as written at any effort. And `aot=require` is
defined to fail the build when the toolchain is missing, which sits against the
N3 exit criterion of no undeclared host-tool dependency.

Make it opt-in per project and honest about targets. Default `aot=off`; a
project that wants native code sets `require` and thereby accepts a Clang or GCC
dependency, pinned by version into the cache key. Windows is `off` or `emit-c`
until someone wants `clang-cl`. That is a supported-platform statement rather
than a disclaimer -- every native feature has one -- and it is the only answer
that does not either bundle a compiler or rewrite the backend.

The alternative that removes the toolchain entirely is direct machine-code
emission. That is a different project, and the backend review gate above is
where it would be argued.

### Link time, not run time

Compile the generated C into the project's own shared library during the build,
and have the generated binding load it. Do not map code at run time.

That choice is what makes a first release tractable: W^X, `MAP_JIT`, the
hardened Apple policy, executable-memory limits, worker code sharing and
retirement, and native hot-reload invalidation all exist only because code is
mapped at run time. None of them is needed by a shared library the loader
already brought in. They return if and when direct emission does.

The machinery is largely present: `kind = "c"` in
`src/nupp/compiler/build/deps.nupp` already discovers a compiler, captures its
version, compiles sources and produces a shared library into `outDir/lib/`.
Producing and loading a native library from a build is not new ground here. What
is new is doing it for compiler-generated C, keyed on the IR that produced it.

### Order

1. **Widen the subset.** Uniform inner loops, which today get no lanes at all
   rather than a scalar inner loop over lane bodies. More than one `@aot`
   function per file. The uniform multiple binding that produces a
   `helper_result` node no verifier rule covers. These are what a user meets
   first, and none of them is a design question.
2. **Feature tiers.** The gang shapes come in 16 and 32 bytes, so a tier takes
   the widest pair it has a register class for and x86-64 below AVX gets two
   lanes rather than none. What is still open is multiversioning: a build pins
   one tier, and dispatching between several at run time is a separate decision.
3. **`aot=emit-c` in `nupp build`.** Exercises policy selection, artifact
   naming, the cache key and its validation with no toolchain in play, so it
   cannot fail for a reason unrelated to the feature.
4. **The cache key and its validation**, before anything executable exists. A
   stale artifact that validates is the only failure in this whole feature that
   produces wrong answers rather than slow builds. While the artifact is a text
   file, getting it wrong costs a regenerated file.
5. **`aot=require`.** Compile, link, load, dispatch.

All five have landed. `require` discovers a toolchain, compiles the emitted C
into the project's shared library, and replaces each `@aot` function with the
generated wrapper where it was written, so a call reaches the compiled symbol
without naming anything new.

The substitution goes through the checker rather than around it. The wrapper is
Nupp -- ownership annotations, a range guard, one statement of `unsafe do` -- so
what a build splices in is checked exactly as if someone had written it, and the
module is hashed on the text that was compiled rather than the file on disk.

Mixed-width gang sizing is not on this path. It is a performance property and
has never blocked a correct answer.

It is a larger one than this plan assumed. `bench/kernel-subset-spike/mixedwidth.sh`
builds one loop three ways and reports each against its own forced-scalar body,
so the arithmetic differing between them does not confound the comparison:

```
 Kernel          Gang    Rounds   Over its own scalar body
 ──────────────  ──────  ───────  ────────────────────────
 mixedwidth      f64x4   yes      1.06x
 mixedwidth_f64  f64x4   no       2.46x
 mixedwidth_f32  f32x8   no       4.72x
```

The first two differ only in whether the gang has to round; the last two only in
the lane count. So of the 4.5x between the ends, the rounding is 2.3x of it and
the lane count 1.9x -- the larger half is the rounding, which the phrase "gang
sizing" does not name.

A loop that mixes explicit binary32 with one binary64 value therefore gets a
gang that costs about what it saves. That is not a wrong answer and not a
refusal, which is why nothing caught it: the arithmetic-intensity gate asks
about memory, and a body dominated by rounding passes it.

Mixed-width gangs recover the rounding half and not the lane half, which is the
correction to the sentence above them: carrying binary32 in binary32 lanes makes
the operation native, and it does not make room for more iterations. A binary64
value needs 64-bit lanes whatever else the loop holds, so four is what fits in 32
bytes.

That half is now taken. `mixed4` and `mixed2` replace the binary64 gangs and
carry each value at its own width, and the same three kernels now measure:

```
 Kernel          Gang     Before   After
 ──────────────  ───────  ──────   ─────
 mixedwidth      mixed4   1.06x    2.57x
 mixedwidth_f64  mixed4   2.46x    2.45x
 mixedwidth_f32  f32x8    4.72x    4.72x
```

The kernel that mixes widths now runs at what the same loop runs at with nothing
to round, which is the whole of what this was worth. The 1.9x still between it
and the all-binary32 kernel is the lane count, and reaching it wants either a
wider register file or one value spanning two registers.

### What the checks have to cover first

Everything about the lane lowering was measured on Apple arm64 until
`bench/kernel-subset-spike/crosscheck.sh` ran natively elsewhere, and the first
native run found a defect the local one could not: Apple Clang does not
implement `-Wpsabi`, so a 32-byte vector below AVX -- which has no register class
on x86-64 and no stable ABI at a function boundary -- was silent locally and an
error on Linux. A second local finding, a trap at `-march=x86-64-v3`, turned out
to be the emulator rather than the codegen, and only the native run could say
so.

Both directions of that are the point. Before `require` compiles anything for a
user, the differential has to run on every target tier that is claimed, natively,
and with the compiler the user will actually have -- which means adding GCC
beside Clang, since step 5 hands the generated C to whatever is installed.

## Verification matrix

Each compiler slice runs focused annotation, checking, generation, ownership,
span, struct-layout, C-interop, module-summary, incremental, formatter, LSP,
documentation, worker, hot-reload, build, package, and host tests as applicable;
then the full suite. Every compiler change runs `./bin/nupp fixpoint` and
requires a byte-identical second build.

Differential AOT tests cover:

- optimization levels zero and one;
- every executable target feature tier and scalar lowering;
- JIT enabled and disabled in the calling Lua state;
- zero, one, exact vector width, multiple widths, and every tail length;
- aligned and deliberately unaligned valid spans;
- slices with nonzero offsets and nested sibling writable partitions;
- minimum, maximum, overflow, shift, conversion, NaN, infinity, signed-zero,
  and subnormal inputs for every admitted numeric operation;
- first and last valid access and the first invalid access on either side;
- every structured exit and modeled failure;
- calls from Lua, AOT-to-AOT calls, and dynamic wrapper values;
- clean cache, warm cache, corrupt cache, cache pressure, and forced allocation
  or executable-memory failure;
- worker concurrency, hot reload, and code retirement.

Fuzz AOT IR before emission and independently validate instruction streams
where practical. A native crash, hang, unmodeled signal, or memory-sanitizer
failure is a compiler defect, never accepted behavior for checked source.

## Performance gates

Use alternating paired measurements, four or more warmups, at least fifteen
samples, and batches lasting long enough to dominate timer noise. Record cold
compilation separately from warm execution.

Measure:

- the existing integrate workload at 262,144 and 1,048,576 rows;
- an arithmetic-heavy chain;
- a reduction and a branch-heavy loop;
- the Tecs-shaped 28-byte strided field case;
- short counts from zero through twice the widest vector tier;
- one direct AOT helper graph;
- one error-free wrapper and one modeled failing call;
- cold compile, warm cache lookup, code size, and process cache growth;
- cold compile under per-function, per-module, and precompiled-prelude
  batching, plus the single-body rebuild each batching admits.

Before making `@aot` supported rather than experimental:

- large contiguous workloads must be within 1.10x of equivalent optimized
  C/Clang and no slower than the existing hand-emitted spike outside
  measurement noise;
- the generated Lua wrapper must be within 1.05x of the handwritten one-call
  `countedBy` wrapper on its existing performance matrix;
- each bulk call must make one Lua/native transition and allocate nothing per
  iteration;
- scalar AOT code must not regress against an equivalent traced LuaJIT loop
  without an inspection-visible reason;
- code with no `@aot` declaration must have no measurable startup, runtime,
  artifact-size, or dependency-selection regression;
- cold compilation and cache budgets must be fixed from N0 measurements before
  choosing the production backend.

Performance does not weaken the safety gates. A backend that is faster only by
changing numeric behavior, assuming unproved aliasing, eliding modeled errors,
or weakening W^X fails the design.

## Completion criteria

The first complete release has:

- the `@aot` spelling everywhere in the public language and tooling;
- ordinary Nupp source with no embedded C or raw machine code;
- one verified AOT IR independent of its production emitter;
- whole-function compilation or a source-local build diagnostic, never silent
  fallback;
- span- and ownership-preserving wrappers with one physical call;
- scalar AArch64 and x86-64 plus the SIMD tiers widened through N5;
- deterministic caching, target dispatch, W^X, worker safety, hot reload, and
  source-attributed inspection;
- differential correctness and performance gates on both supported
  architectures;
- documentation that “AOT” promises build-time compilation, not SIMD, parallelism,
  safety bypass, GPU execution, or a stable foreign ABI.
