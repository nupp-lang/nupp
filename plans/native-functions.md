# Checked native functions

Status: planned; supersedes the `@kernel` spelling

## Decision

Use `@native` for the explicit contract that a Nupp function must compile as
one checked native unit:

```nupp
local span = require("nupp.span")

@native
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

`@native` means the complete function is lowered through Nupp's checked native
IR and compiled for every selected build target. If it cannot be compiled, the
build reports why. It does not mean operating-system code, imply a GPU, promise
SIMD, or permit unsafe operations.

The initial backend is generated private C compiled by a pinned Clang. Native
IR remains the safety boundary and the stable compiler architecture; C is a
deterministic backend representation. Direct machine-code emission is deferred
unless measured toolchain, latency, packaging, or specialization requirements
show that generated C cannot meet the release gates.

The earlier working name `@kernel` is rejected for the public annotation. In
numeric computing, a kernel is a small bulk operation, but the word also
suggests an operating-system kernel, GPU dispatch, implicit parallelism, SIMD,
and a separate language. None is the defining promise. “Native” names the one
observable contract: this function is compiled by Nupp's native backend rather
than emitted as an ordinary Lua function.

Internal documents may still call a benchmark workload or a foreign bulk
routine a native kernel. The compiler representation, commands, diagnostics,
and user-facing annotation use “native function” and “native IR.”

## Goal

Compile performance-critical Nupp functions to native machine code without
giving up Nupp's bounds, type, ownership, borrowing, aliasing, effect, and
suspension checks. A caller sees an ordinary typed Nupp function. The generated
wrapper validates and projects its arguments, crosses the Lua/native boundary
once, and translates modeled failures back to the source operation.

The feature provides a safe native boundary for:

- arithmetic over spans and reified structs;
- component-column, image, audio, geometry, matrix, codec, and checksum loops;
- explicit portable vector and mask operations if that design is selected;
- small statically resolved helper graphs;
- scalar native work that does not benefit from SIMD.

The first implementation is intentionally a whole-function compiler. Region
outlining and transparent native compilation are later, separate optimizations.
They must not be prerequisites for an explicit `@native` contract to be
understandable.

## Non-goals

- Do not embed C, C++, assembly, LLVM IR, or machine-code bytes in Nupp source.
- Do not maintain a private fork of LuaJIT.
- Do not treat `@native` as `unsafe`; an unsafe operation remains unsafe and is
  initially rejected inside a native function.
- Do not promise SIMD merely because a function is native. A scalar lowering
  satisfies the contract.
- Do not promise automatic vectorization of every scalar loop. It is a backend
  optimization whose success must be inspectable.
- Do not add GPU execution, implicit threads, asynchronous launch, or a tensor
  runtime under this annotation.
- Do not admit arbitrary Lua calls, tables, strings, allocation, callbacks,
  coroutines, or dynamic dispatch in the first subset.
- Do not silently fall back to Lua when an annotated function cannot compile.
- Do not change numeric answers to obtain faster code. Relaxed floating-point
  behavior requires a separate explicit contract.
- Do not expose generated native code as a stable C ABI or object-file format.

## Contract, not another expression language

The body is ordinary Nupp. It uses the existing parser, name resolution, type
system, operators, loops, structs, spans, diagnostics, and source positions.
`@native` adds a compilation and effect constraint after ordinary checking; it
does not reinterpret the body.

Removing `@native` may change performance and generated artifacts, but not the
function's source-level result. Adding it may reject constructs the native
backend cannot represent, but may not make an otherwise invalid operation
valid. This is the same shape as `@jit`: an annotation can make an execution
property a checked requirement without inventing new expression semantics.

Eligibility is a versioned compatibility promise. Within a supported language
line, a source function accepted for a target remains accepted; the admitted
subset may widen but does not silently narrow. A backend regression is a build
error and compiler defect, never permission to run the ordinary Lua lowering.
The programmer can remove `@native` to select ordinary execution explicitly.

The annotation applies to local and named functions with visible Nupp bodies.
It is rejected on constructors, inline interface requirements, bodyless
declarations, `cdef` functions, and arbitrary function-typed bindings in the
first release. A later declaration file may describe a previously compiled
native implementation, but that is a packaging contract rather than the source
feature.

At runtime the declaration still denotes a Lua-callable wrapper. Taking its
function value, storing it, comparing it, and calling it dynamically use that
wrapper. Statically resolved calls from one native function to another may use
a private direct convention without changing the public function value.

## Relationship to existing features

### `@jit`

`@jit` checks that a function avoids known LuaJIT trace-unsafe FFI boundaries.
`@native` bypasses LuaJIT for the function body. They are mutually exclusive:
stacking them is an error because the two contracts name different compilers
for the same body.

The existing `nupp bc --check` command continues to answer LuaJIT traceability.
Native functions receive separate IR and machine-code inspection commands.

### C interop and checked external kernels

`cdef`, `cheader`, and `countedBy(count)` describe code implemented outside
Nupp. Their implementation is trusted even when their pointer/count boundary is
checked. `@native` instead compiles visible checked Nupp source. It needs no
duplicated C struct, header, handwritten wrapper, or foreign library declaration.

The checked native-kernel spike remains valuable evidence and a performance
baseline. Its `countedBy` wrapper proves the desired one-call ABI; its C and
DynASM bodies do not become the safety model for `@native`.

### Portable vectors

The [portable-vector plan](portable-vectors.md) asks whether vectors and masks
should have complete boxed Lua semantics and trigger transparent native
compilation in otherwise ordinary functions. `@native` asks a narrower question:
where can Nupp promise one complete native compilation unit?

They can share vector types, native IR, target lowering, dispatch, caches, and
inspection. The public choices remain distinct:

1. Vector values work everywhere, while `@native` optionally turns fallback
   into a compile-time error for one function.
2. Vector values begin inside `@native`, avoiding boxed escape until the
   ordinary-value model proves worthwhile.
3. Scalar `@native` lands without public explicit vectors and initially relies
   on backend auto-vectorization.

The first mechanism spike must compare all three. Do not make `@native` mean
“SIMD function”; doing so would exclude useful scalar native work and make the
annotation's name dishonest.

### Embedded C

Literal C is not a competing safe implementation. Nupp can validate its ABI
and inspect a Clang AST, but arbitrary C retains pointer provenance, undefined
behavior, preprocessor, promotion, cast, and toolchain-version hazards. A C
subset restricted enough to recover the guarantees below is a second spelling
of the native IR with worse diagnostics.

Use generated C as a private backend experiment and ordinary C dependencies as
an explicit foreign escape hatch. Do not add `native do` or
`native c function` as part of this feature.

## Admitted source model

### Values and storage

The first subset admits:

- `nil`, `boolean`, fixed C numeric types, and integers where their exact
  native semantics are specified;
- local scalar bindings and immutable compile-time constants;
- reified Nupp structs containing admitted fields;
- `Span<T>`, `WriteSpan<T>`, and fixed variants over admitted elements;
- fixed C arrays whose layout is known for the selected target;
- vector, mask, and species values if the portable-vector surface is selected;
- private compiler status and multiple-result slots at the wrapper boundary.

It declines:

- `any`, `unknown`, Lua `number` until its exact native contract is selected,
  `string`, `table`, ordinary records, threads, and userdata;
- GC-managed or dynamically sized fields;
- raw pointers, variable C arrays, cdata of unknown layout, and arbitrary FFI;
- owned, pinned, retained, or dynamically registered resources;
- closures, upvalues other than quotable immutable constants, and varargs;
- mutable globals or replaceable module fields.

“Declines” means a stable `@native` diagnostic because compilation is required.
There is no hidden Lua version used to excuse an unsupported value.

### Control flow

Admit structured conditionals, numeric loops, `while`, `repeat`, `break`,
`continue`, ordinary returns, and statically resolved calls within a bounded
native helper graph. `goto` waits until native IR source maps and cleanup edges
can represent every existing rule without a special case.

Recursion, protected calls, yields, suspension handling, unknown callbacks,
metamethod dispatch, and dynamic function calls are rejected initially. Bounded
recursion may be considered only after stack limits, failure behavior, and code
cache cycles are specified.

The function is non-suspending by construction. This is derived and exposed in
its function effects; the user need not stack `nosuspend` syntax around it.

### Calls

A native body may call:

- another statically resolved `@native` function;
- a private native helper generated from an eligible visible Nupp body;
- a closed compiler-owned set of pure numeric and layout intrinsics;
- span operations whose semantics are lowered directly rather than dispatched
  through Lua.

It may not call arbitrary C merely because the C function is declared. Foreign
calls need target ABI, unwind, alias, retention, callback, and side-effect
analysis of their own. A later phase may admit a small leaf allowlist with
complete contracts, but no unknown symbol enters native IR.

Calling an ordinary visible Nupp helper does not silently clone it into the
native graph. Either mark it `@native`, make it a compiler-recognized intrinsic,
or inline it through a future explicitly documented rule. This keeps code-size
growth and cross-module invalidation visible.

## Memory safety and ownership

### Spans are the public memory boundary

Native functions do not accept a naked pointer/count pair from checked source.
A shared span projects a const pointer for the duration of the call. A writable
span projects a mutable pointer only under an exclusive borrow. The wrapper
applies the span's private offset, carries its count, and performs all required
width conversions before native entry.

Loads and stores retain Nupp's one-based span indexing. The native IR contains
the logical index, span length, access width, source site, and region identity.
It never treats a projected address as proof of a bound.

The checker or IR verifier must prove an access in range or emit a modeled
check. An unchecked access, pointer cast, integer-to-pointer conversion, or
unknown pointer arithmetic has no native IR opcode in the safe subset.

### Aliasing

`borrows` permits shared aliases. `exclusive` requires sole access to its
region. Sibling regions produced through `WriteSpan.splitAt` carry disjoint
partition paths, so they may be simultaneous exclusive parameters. The same
region twice, or a child with its ancestor, is rejected before code generation.

The IR preserves these facts explicitly. A backend may emit C `restrict`,
reorder memory operations, or eliminate loads only for regions Nupp proved
disjoint. Constness alone never implies non-aliasing.

Native helpers receive the same region identities through their call edges.
Erasing a value through gradual or unsafe code prevents native compilation; it
never manufactures a stronger alias fact.

### Ownership and cleanup

The first subset accepts no live owner at native entry and creates none inside.
That excludes allocation and cleanup rather than trying to unwind native frames
through LuaJIT. A span borrowing an owner may enter because the wrapper keeps
the root and borrow live until the call returns.

Owned values, automatic destruction, `takes` parameters, affine closures, and
resource sets may be admitted later only after native IR models every normal,
error, and cancellation exit. `unsafe do` does not bypass this staging rule.

## Numeric semantics

Native scalar operations owe the same specified result as their ordinary Nupp
counterparts. The native compiler must not inherit whatever overflow, shift,
NaN, contraction, denormal, or fast-math behavior a C compiler happens to use.

Fixed C storage types do not imply same-width expression arithmetic. In
ordinary Nupp today, loading a `float` cdata slot widens to Lua's binary64
`number`, local type annotations erase, and storing into a `float` slot narrows
the final result. Native IR must represent those conversions and binary64
intermediates explicitly. Treating every operation between `float`-typed
values as binary32 changes answers and violates the annotation invariant. A
future binary32-per-operation intrinsic or relaxed numeric mode must have
ordinary Nupp semantics of its own; `@native` cannot introduce it implicitly.

The first release starts with fixed C storage types because their widths are
explicit. For each admitted operator, the native IR states:

- signed or unsigned interpretation;
- result width and overflow behavior;
- comparison behavior;
- shift masking or rejection;
- conversion rounding and out-of-range behavior;
- floating NaN, infinity, signed-zero, and subnormal behavior;
- whether one fused rounding was explicitly requested.

Default floating expressions are not reassociated and `a * b + c` is not
contracted implicitly. An explicit future `fma` intrinsic requests a fused
operation. Reductions state their lane order. No backend uses `-ffast-math` or
an equivalent flag under the default contract.

Subset growth follows semantics rather than spelling convenience. `sqrt` may
enter through a closed intrinsic only after its ordinary result and target
rounding are specified. Stencil loads require affine bounds or explicit halo
facts plus verified region relationships. Reductions remain source-ordered by
default; a vector tree reduction needs a separately named fixed-tree or relaxed
contract because reassociation changes floating-point answers.

Lua `number` and Nupp `integer` wait where ordinary LuaJIT semantics do not map
cleanly to one target operation. Admitting them requires differential tests and
a written exactness rule, not a convenient host cast.

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
native helper may remove a frame only when the existing `frames` guarantee is
relaxed. Hoisting a check may move an error site only when `error-site` is
relaxed. Native compilation itself does not silently grant either permission.

## Native IR

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
- explicit vector compare/select and FMA fusion;
- no floating reassociation or speculative deoptimization.

## Backend decision

The safe language contract stops at verified native IR. Backend selection must
not change which source is admitted or which answer it produces.

### Generated C and Clang

An AOT experiment emits private C from native IR, compiles it with pinned flags,
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
must avoid undefined C expressions even where native IR has well-defined wrap
semantics.

The disadvantage is toolchain availability and cache reproducibility. A build
requiring a host Clang is not the final zero-setup experience unless Nupp ships
or prebuilds every required target artifact.

During the generated-C experiment, Clang is a conditional dependency: a build
graph containing `@native` requires the pinned supported Clang, while a program
without `@native` does not probe for Clang and gains no native artifact or
startup cost. Production must either ship that toolchain, validate prebuilt
artifacts for every selected target, or choose direct emission. An annotated
function never falls back merely because Clang is absent.

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

Use one native IR corpus and retain direct-emission spikes as independent code
shape evidence where useful. Reconsider the generated-C decision only after
measuring:

- correctness and target parity;
- cold compile latency and cache hit latency;
- code size and steady-state throughput;
- diagnostic and source-map quality;
- cross-target and offline build requirements;
- executable-memory policy and packaging complexity;
- ongoing instruction and ABI maintenance.

It is valid to replace generated C later when the same verified native IR and
numeric contracts feed the replacement. It is not valid to expose
backend-specific source semantics and call that migration compatible.

## ABI and dispatch

### Lua wrapper

Every public native function has one generated Lua wrapper. Before entry it:

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

### Native-to-native calls

Known native callees use a private direct convention and propagate status
without returning through Lua between calls. The compiled call graph records
callee fingerprints and CPU requirements. Unknown or dynamic callees are not
admitted.

Cross-module calls may consume semantic native IR from a module summary, but an
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
implementation fails an `@native` build; it does not silently select Lua.

## Artifacts, executable memory, and workers

Native cache keys include:

- semantic native IR and version;
- target triple, data layout, ABI, and CPU feature tier;
- numeric-contract version;
- backend and pinned tool revision;
- optimization level and every behavior-affecting flag;
- direct callee fingerprints where applicable.

Cached data is never load-bearing. Validate it before mapping or linking, and
regenerate after corruption or version mismatch.

Direct code generation follows W^X: allocate writable memory, encode and
relocate, flush the instruction cache where required, then make it executable.
Hardened Apple hosts require `MAP_JIT` and the platform JIT write-protection
policy integrated with the Nupp host. The compiler may not silently weaken
W^X. A platform that cannot satisfy the policy cannot build or run the
corresponding `@native` artifact.

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

Native compilation must never be a silent performance story. Add:

```sh
./bin/nupp native inspect FILE LINE COLUMN
./bin/nupp native ir FILE FUNCTION
./bin/nupp native code FILE FUNCTION --target=aarch64-neon
```

`inspect` reports the selected source function, admitted types and effects,
wrapper checks, direct callees, backend, target versions, code-cache state,
vectorization or scalarization, and the first reason compilation failed.

`ir` prints source-attributed checked native IR. `code` prints decoded machine
instructions beside source lines and feature requirements. Tests assert decoded
instructions, not byte substrings alone. These commands inspect rather than
benchmark, so their structural answer is deterministic.

Reserve a diagnostic family after the repository-wide code inventory. It must
cover at least:

- `@native` on an invalid target or bodyless declaration;
- an unsupported value, operation, call, effect, capture, or control edge;
- a live ownership or suspension obligation at the native boundary;
- a target layout or ABI mismatch;
- a native call graph cycle or generation resource limit;
- an invalid, stale, corrupt, or over-limit native IR artifact;
- unavailable target backend or executable-memory policy;
- a backend failure with mapped Nupp source context;
- `@native` combined with `@jit` or a conflicting future contract.

Every diagnostic explains whether the source can be rewritten, the annotation
removed, or the missing target support selected. No diagnostic suggests
`unsafe` as a way to bypass native eligibility.

## Delivery

### N0: Semantics and backend spike

Keep the surface test-only. Lower structured scalar span loops to a minimal
native IR and generated C/Clang. Cover multiple disjoint outputs, potentially
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
- Native IR contains no unbounded address operation or unmodeled call.
- Decoded output contains the expected scalar or vector operations and no
  per-lane helper calls.
- The spike records compile time, warm cache time, code size, wrapper cost, and
  throughput.
- Optimized code shape is inspected and every discrepancy from the scalar
  oracle is explained before widening the admitted subset.

Nothing public lands if N0 cannot keep native IR independent of its backend.

### N1: Annotation and checker contract

Reserve `@native` as a no-argument function annotation. Implement target
validation, mutual exclusion with `@jit`, admitted types and effects, helper
graph checking, deterministic native IR, verification, diagnostics, formatting,
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
- Removing `@native` from accepted source preserves its ordinary Nupp answer.
- Equivalent functions produce byte-identical native IR and hashes.
- Module summaries never expose private ABI layouts as public type promises.

### N2: Spans, structs, and failures

Complete the safe memory boundary: shared and writable spans, fixed spans,
slices with nonzero offsets, sibling writable partitions, target-validated
struct layouts, multiple results, preconditions, bounds failures, and source-
attributed status returns.

#### N2 exit criteria

- Checked source cannot forge a pointer, count, region, layout, or mutable
  alias accepted by native IR.
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
- Machine-code inspection explains every target version and native call edge.

### N4: Native helper graphs and optimization

Add statically resolved native-to-native calls, bounded inlining, loop
optimization, alias-aware load elimination, and target auto-vectorization or
explicit vector lowering. Preserve observable guarantee checks for frames,
errors, and numeric transformations.

#### N4 exit criteria

- Direct native calls do not bounce through Lua and propagate modeled status
  correctly.
- Inlining and specialization have per-function and process limits.
- An implementation edit invalidates only the cache edges that consumed it.
- Inspection distinguishes scalar, auto-vectorized, and explicit-vector code.
- Optimization level zero remains a correct minimally transformed oracle.

### N5: Decide portable vector scope

Use the shared implementation to run the decision gate in
[portable-vectors.md](portable-vectors.md). Compare vectors confined to
`@native`, vectors with boxed ordinary semantics, and scalar source relying on
auto-vectorization.

If boxed portable vectors win, `@native` remains the explicit compilation
contract: it turns a transparent-lowering decline into a diagnostic. If they do
not, keep vector temporaries native-only and say so plainly. Do not ship two
lookalike vector APIs whose difference is accidental boxing.

### N6: Carefully widen the subset

Consider fixed allocations, owned values, selected foreign leaf calls,
recursion, richer errors, and outlining separately. Each addition requires a
complete IR model for normal and failure exits, ownership and alias transport,
source attribution, backend parity, differential tests, and an independently
measured workload.

Do not add a construct merely because Clang or the host CPU can execute it. The
question is whether Nupp can preserve its contract across every backend and
target.

## Verification matrix

Each compiler slice runs focused annotation, checking, generation, ownership,
span, struct-layout, C-interop, module-summary, incremental, formatter, LSP,
documentation, worker, hot-reload, build, package, and host tests as applicable;
then the full suite. Every compiler change runs `./bin/nupp fixpoint` and
requires a byte-identical second build.

Differential native tests cover:

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
- calls from Lua, native-to-native calls, and dynamic wrapper values;
- clean cache, warm cache, corrupt cache, cache pressure, and forced allocation
  or executable-memory failure;
- worker concurrency, hot reload, and code retirement.

Fuzz native IR before emission and independently validate instruction streams
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
- one direct native helper graph;
- one error-free wrapper and one modeled failing call;
- cold compile, warm cache lookup, code size, and process cache growth.

Before making `@native` supported rather than experimental:

- large contiguous workloads must be within 1.10x of equivalent optimized
  C/Clang and no slower than the existing hand-emitted spike outside
  measurement noise;
- the generated Lua wrapper must be within 1.05x of the handwritten one-call
  `countedBy` wrapper on its existing performance matrix;
- each bulk call must make one Lua/native transition and allocate nothing per
  iteration;
- scalar-native code must not regress against an equivalent traced LuaJIT loop
  without an inspection-visible reason;
- code with no `@native` declaration must have no measurable startup, runtime,
  artifact-size, or dependency-selection regression;
- cold compilation and cache budgets must be fixed from N0 measurements before
  choosing the production backend.

Performance does not weaken the safety gates. A backend that is faster only by
changing numeric behavior, assuming unproved aliasing, eliding modeled errors,
or weakening W^X fails the design.

## Completion criteria

The first complete release has:

- the `@native` spelling everywhere in the public language and tooling;
- ordinary Nupp source with no embedded C or raw machine code;
- one verified native IR independent of its production emitter;
- whole-function compilation or a source-local build diagnostic, never silent
  fallback;
- span- and ownership-preserving wrappers with one physical call;
- scalar AArch64 and x86-64 plus the vector tiers selected by the N5 decision;
- deterministic caching, target dispatch, W^X, worker safety, hot reload, and
  source-attributed inspection;
- differential correctness and performance gates on both supported
  architectures;
- documentation that “native” promises compilation, not SIMD, parallelism,
  safety bypass, GPU execution, or a stable foreign ABI.
