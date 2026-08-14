# Independent foundations for native lowering

Status: planned; each track ships without `@native`

## Decision

Land four ordinary Nupp capabilities before making native function lowering a
production language feature:

1. canonical C identities and header export for reified structs;
2. explicit fixed-width scalar arithmetic;
3. richer checked span views;
4. transported allocation and raising guarantees.

Each capability must be useful and testable with native compilation disabled.
The native compiler may consume it later, but native eligibility is not its
public meaning and is not an acceptance criterion for landing it.

This preserves the central invariant of the native design: an annotated body
is ordinary Nupp with the same result, memory behavior, failures, and effects.
These foundations make those ordinary semantics more precise; they do not
introduce a second expression language.

## Current baseline

Nupp already has more of this foundation than the prototype initially made
obvious:

- `struct` is reified, `layoutof` reports its host layout, and the compiler has
  target layout models and fingerprints. Ordinary structs are still emitted as
  anonymous LuaJIT ctypes and have no compiler-private C spelling suitable for
  a generated signature.
- `float`, `int32`, and `uint32` are valid reified storage types. Ordinary
  arithmetic does not promise one same-width operation: a loaded `float`
  becomes Lua's binary64 number, and fixed-width integer cdata follows LuaJIT's
  coercion rules.
- `Span.slice`, `WriteSpan.getMut`, `WriteSpan.splitAt`, and private
  offset-aware pointer projection already exist. A writable subspan, a common
  checked iteration range, and typed strided field views do not.
- `@effects` already infers and checks `allocates` and `raises`, in addition to
  `yields` and memory effects. The missing capability is not two new effect
  flags: complete summaries are file-local, only the non-suspending guarantee
  rides on function types, and there are no `noalloc` or `noraise` checked
  regions.

The work below extends those surfaces. It does not replace them.

## Shared rules

- Native compilation may not affect whether any ordinary example in this plan
  runs. `export-c` emits text without invoking a compiler; its independent
  acceptance fixture compiles that text because C interoperation is the feature.
- New guarantees are positive proofs. Unknown code loses an optimization or is
  rejected from a checked region; it never receives an optimistic default.
- One canonical emitter owns every published ordinary-struct C name and layout;
  user source never supplies a competing tag or declaration.
- Existing arithmetic operators keep their current meaning. Same-width
  arithmetic is requested through explicit ordinary functions.
- Bounds and disjointness come from spans and ownership. Do not expose
  `restrict`, `noalias`, unchecked stride construction, or a vectorization
  assertion in source.
- Each feature gets its own diagnostics, reference text, focused tests, and
  changelog entry. Native lowering consumes only released behavior, never an
  internal prototype shape.

## No transitional implementations

This plan lands one implementation of each capability. Resolve design questions
from existing behavior, source sketches, and permanent semantic tests before
implementation; do not commit a characterization path as a fallback, alternate
API, or experimental runtime.

In particular:

- ordinary structs remain anonymous LuaJIT ctypes; there is no temporary named
  runtime representation to remove later;
- fixed-width operations live only under the existing `nupp.math` namespace;
  there are no parallel `require("nupp.f32")` modules;
- per-call cdata boxes, per-call scratch allocation, and
  one-FFI-call-per-operation numeric fallbacks do not land;
- a public strided span lands only if ordinary non-native uses justify its final
  API before implementation;
- complete effect summaries remain file-local; only the stable positive facts
  a dependant actually observes cross a module boundary;
- `noalloc do` and `noraise do` are the only new checked-region spellings.
- no milestone implements a feature in `bench/kernel-subset-spike` and then
  reimplements it in the compiler or standard library. The existing spike may
  consume a released feature for validation, but it is not an implementation
  stage.

A throwaway measurement in an uncommitted temporary directory may answer a
feasibility question such as LuaJIT trace recording. It is deleted after the
answer and never becomes a public or internal implementation stage. The rule
above forbids shipped transitional surfaces, not measurement.

If the final implementation required by a track is not yet feasible, stop at
the preceding decision or semantic test work. Do not land an implementation
whose purpose is to be replaced by the next milestone.

## Track A: canonical C identities and header export

### Goal

Give every reified ordinary struct one deterministic, target-aware C
description, and expose it through an ordinary `nupp export-c` command. The
same declaration emitter may later serve native lowering, but its first
consumer is handwritten C interoperating with Nupp structs.

This is the one hard native prerequisite among the four tracks. It ships first
as an independent C-interoperation feature with no `@native` annotation and no
native-generated function body.

### Representation decision

Keep the existing anonymous LuaJIT ctype as the sole runtime representation of
an ordinary struct. Do not register compiler-generated named struct tags in
LuaJIT's process-global, permanent C namespace.

Generated headers and generated C use one canonical named aggregate. A typed
ordinary-struct pointer in a Nupp `cdef function` lowers through a
compiler-owned pointer ABI bridge; its generated LuaJIT declaration may erase
that physical pointer slot internally because every supported C ABI represents
object pointers compatibly. Source, checking, ownership, the emitted header,
and the external C definition remain typed. The erasure is compiler glue, not a
second user-facing declaration.

Ordinary structs do not cross a foreign boundary by value in this track.
Pointers, arrays, and checked spans are the one supported boundary. Supporting
by-value aggregates would require a different runtime ABI representation and
is omitted rather than implemented temporarily.

This decision adds zero named C tags per watch reload. It therefore introduces
no new consumption of LuaJIT's fixed ctype-id space beyond the anonymous
reification Nupp already performs. Header generation runs at build/tool time
and does not mutate the live VM's C namespace.

### Identity model

Introduce a canonical compiler record containing:

- the declaration's nominal identity, including its module identity;
- a semantic fingerprint of its fields and nested type graph;
- the selected target-layout key and layout schema version;
- size, alignment, field offsets, field sizes, and field C types;
- a deterministic module-qualified C tag and typedef name;
- the dependencies that must be declared before it by value.

The C name is derived from the package/module identity and exported declaration
identity, with collision-safe encoding. It remains stable across body-only
changes. The layout fingerprint is emitted separately, so a field change is an
explicit C ABI change without manufacturing a fresh runtime tag.

C source includes the generated header and uses the emitted typedef. Nupp
source continues naming the Nupp declaration. Neither side hand-copies or
overrides a struct layout.

### Ordinary consumer

Add one command:

```text
./bin/nupp export-c -o game.h src/game.nupp \
    game.Position game.Motion game.integrate
```

The hyphenated spelling deliberately mirrors the existing public `import-c`
command; the implementation file's `importc.nupp` name is not CLI syntax.

It emits an include-guarded header containing the selected exported structs,
their transitive by-value dependencies, canonical C names, layout fingerprint
constants, compile-time layout assertions, and typed prototypes for selected
`cdef function` declarations. The command reports a source diagnostic for a
selected declaration that cannot be represented for the configured target.

A `cdef function` may name a pointer or array of one of those ordinary structs
directly. The checker and generator map it to the same canonical C description;
the user does not repeat the declaration as `cdef struct`.

One canonical function-signature record owns parameter count and order, scalar
types, ordinary-struct pointer types, constness, ownership projection,
`countedBy` relationships, result type, calling convention, and symbol name.
The typed header prototype and the physically erased LuaJIT FFI declaration
are two renderings of that record. Neither rendering is parsed to reconstruct
the other.

Pointer erasure removes constness from LuaJIT's physical slot. It does not
remove constness from the header or Nupp type, and it is never permission to
pass a shared span to a mutable C parameter. The checker and generated span
wrapper enforce that distinction before the erased call.

### C declaration rules

The one header/declaration emitter:

- emits fixed-width standard C types rather than target-dependent aliases;
- forward-declares pointer-only cycles;
- topologically orders aggregates embedded by value;
- rejects a by-value cycle before generation;
- preserves declared field order and explicit bit widths;
- represents fixed arrays and nested structs without flattening them;
- emits `_Static_assert` checks for size, alignment, and every field offset;
- fingerprints the target-layout inputs beside the declaration.

The first slice covers the reified field vocabulary the target-layout model can
already prove. A field shape that lacks a target model is declined with a
specific diagnostic; the emitter does not ask the build host and guess.

### Milestones

**A0 — canonical target ABI record and name**

- Factor one target-aware aggregate description out of `layoutof`, semantic
  reflection, and the existing target-layout implementation.
- Include its schema version in compiler and incremental cache keys.
- Make host and cross-target queries use the same field graph and differ only
  by the selected target model.
- Pin the anonymous-runtime/named-header boundary in tests; no named-runtime
  implementation is built.

**A1 — `nupp export-c`**

- Emit the final deterministic C declaration graph and typed function
  prototypes for selected declarations and a target.
- Add independent parser/compile fixtures that compare the emitted declaration
  against Nupp's target layout record.
- Validate with Clang for every supported target triple available in CI, but do
  not require Clang to check or run ordinary Nupp.

**A2 — typed ordinary-struct pointer interoperation**

- Permit `cdef function` pointer/array parameters to name an ordinary struct
  whose canonical description can be emitted.
- Generate the one final pointer bridge while keeping ownership modes,
  `countedBy`, and span adaptation typed at source.
- Render its erased FFI declaration from the same canonical signature record as
  the header prototype.
- Keep ordinary user-written `cdef` behavior unchanged: external C aggregates
  remain explicitly declared `cdef struct` types.
- Make `nupp export-c` the only way to publish an ordinary Nupp struct layout to
  C; do not add annotations, inline C names, or a second header generator.

### Tests and exit criteria

- Same declaration, compiler version, and target produces byte-identical C.
- Different nominal declarations with the same fields do not share identity.
- A field type, order, width, nesting, or target-layout change changes the
  appropriate fingerprint.
- Host `ffi.sizeof`/`ffi.alignof`/`ffi.offsetof` agree with the canonical record.
- Cross-compiled static assertions pass for supported 32-bit and 64-bit
  targets.
- Pointer-recursive types compile; direct and mutual by-value cycles report at
  source.
- A fixture defines structs once in Nupp, exports the header, compiles a small C
  function against it, and calls that function through typed ordinary-struct
  pointers without a duplicate `cdef struct`.
- Changing parameter count, order, pointer/value shape, constness, count
  relation, or result type changes both renderings from the canonical record;
  a fixture compiles the typed prototype and exercises the erased wrapper.
- Clean, incremental, hot-reloaded, and reversed-module-order runs agree and
  register no generated named aggregate in the live LuaJIT C namespace.
- `./bin/nupp bc --check` accepts the generated pointer wrapper.
- Ordinary projects that never run `export-c` need no external compiler and
  preserve their existing runtime representation and behavior.

## Track N: explicit fixed-width scalar arithmetic

### Goal

Add ordinary, portable operations whose names state the width and rounding
contract. They provide useful binary and buffer manipulation on their own and
give future scalar, SIMD, and native backends operations that can lower one for
one without changing the meaning of `+`, `*`, or a `float` annotation.

### Public surface and representation

Use the existing auto-linked `nupp.math` namespace rather than adding modules
or operators:

```nupp
local speed: float = nupp.math.f32.mul(distance, inverseTime)
local flags: uint32 = nupp.math.u32.orBits(oldFlags, bit)
local mixed: uint32 = nupp.math.u32.rotateLeft(flags, 7)
```

The resolved prelude member identity is the intrinsic identity. Aliasing that
member preserves the identity; shadowing `nupp`, `math`, or a member produces
an ordinary call and receives no intrinsic treatment.

The ordinary result representation is decided now:

- `i32` is a Lua number in the canonical inclusive range -2^31 through
  2^31-1;
- `u32` is a Lua number in the canonical inclusive range 0 through 2^32-1;
- every `f32` operation returns a Lua number whose value is exactly
  representable as binary32.

The static result types remain `int32`, `uint32`, and `float`. The operations do
not return scalar cdata boxes. `u32` bit operations convert through LuaJIT's
signed `bit.*` representation internally and normalize negative results by
adding 2^32. Wrapping multiplication uses exact 16-bit partial products rather
than `a * b`, which can lose low product bits in binary64.

The `f32` property is an output guarantee, not an invariant of every value whose
static type is `float`. An ordinary local or expression may hold a wider Lua
number. Each `f32` operation rounds its inputs explicitly.

The exact first surface is deliberately small:

- `f32`: `round`, `add`, `sub`, `mul`, `div`, `sqrt`, `min`, `max`, `fma`,
  `fromBits`, and `toBits`;
- `i32` and `u32`: wrapping `add`, `sub`, and `mul`; bitwise and/or/xor/not;
  left, logical-right, and arithmetic-right shifts where meaningful; rotates;
  signed or unsigned comparisons; and explicit cross-width conversions.

Every operation returns the declared fixed-width type. Normal operators used on
the result retain their existing LuaJIT semantics; a source expression requests
same-width arithmetic only by continuing to call the fixed-width operations.

### Numeric contract

Write the contract before optimizing the implementation:

- each `f32` argument is rounded to IEEE-754 binary32 before the operation, and
  the result is rounded to binary32 using round-to-nearest ties-to-even;
- `fma` is one fused operation, never an alias for `add(mul(a, b), c)`;
- signed zero, infinity, subnormals, and each operation's NaN behavior are
  specified; `fromBits`/`toBits` preserve every non-NaN bit pattern and map all
  NaNs to one documented quiet NaN, with no second raw-payload API;
- `i32` and `u32` arithmetic wraps modulo 2^32;
- every 32-bit shift count is masked with `count & 31`;
- signed right shift is arithmetic and unsigned right shift is logical;
- conversions state truncation/rounding and reject or define every out-of-range,
  NaN, and infinity case.

Do not infer binary32 arithmetic merely because values came from `float`
storage. That would silently change existing programs and would make an
annotation alter results.

### Ordinary implementation

The final ordinary implementation uses one module-lifetime `float[1]` holder
and typed views of its four bytes, matching the allocation pattern already used
by scalar I/O in `src/nupp/compiler/stdlib.nupp`. Module initialization
allocates the holder once. Calls allocate nothing, create no scalar cdata box,
and make no foreign call.

Each rounding step stores to the holder and immediately loads the rounded value.
No holder contents remain live across a function call, callback, error edge, or
suspension point. A Lua state executes the store/load sequence without yielding;
separate Lua states have separate module storage. This is the reentrancy rule,
not a convention an implementation may relax.

For binary32 inputs, binary64 has enough precision to compute add, subtract,
multiply, divide, square root, and the exact multiply/add needed by the first
`fma` contract before one final binary32 rounding. The oracle must confirm the
result-bit claim, especially at subnormal, overflow, cancellation, and halfway
boundaries.

Inputs are not assumed to be binary32. A binary operation performs
`round32(round32(a) op round32(b))`: two input roundings plus one result
rounding. `fma` rounds three inputs and its one fused result. Benchmarks measure
that complete cost rather than an already-rounded-input shortcut.

The module-lifetime holder and its typed views are the final ordinary
implementation and remain load-bearing after compiler recognition. If that
exact path is not allocation-free and recordable by LuaJIT, land the integer
surface and leave `f32` absent; do not add a compiler primitive or a second
fallback to rescue it.

### Milestones

**N0 — representation and executable semantic oracle**

- Pin the number representations and normalization rules above in public
  semantic tests.
- Specify every first-slice operation in terms of result bits.
- Build a small independently compiled C oracle at strict floating settings and
  a software reference for cases where the host floating environment is not a
  sufficient oracle.
- Include inputs not representable as binary32, especially values on both sides
  of input-rounding halfway boundaries.
- Prove the final integer multiplication and module-holder binary32 algorithms
  against the oracle before adding public members.

**N1 — `nupp.math.i32` and `nupp.math.u32`**

- Land allocation-free wrapping, shifts, rotates, comparisons, and conversions.
- Use them in the existing bitset where they improve clarity without regressing
  its measured performance.

**N2 — `nupp.math.f32`**

- Land exact conversion, arithmetic, square root, min/max, bit conversion, and
  fused multiply-add.
- Keep transcendental functions out until their cross-platform result contract
  and implementation are separately justified.

**N3 — compiler intrinsic metadata**

- Mark the released standard functions with canonical operation identifiers.
- Teach constant folding and inspection to consume those identifiers where the
  exact semantics are implemented.
- Native and vector backends may consume the same identifiers later in separate
  changes.

### Tests and exit criteria

- Edge cases cover positive and negative zero, every infinity, representative
  quiet/signaling NaNs, subnormals, halfway rounding, integer extrema, every
  shift count around 0/31/32, and every conversion boundary.
- Property tests compare result bits against the independent oracle across
  random operands.
- JIT-on, JIT-off, optimized, unoptimized, and supported host architectures
  return the same bits.
- Calls allocate nothing in a hot loop after module initialization.
- `./bin/nupp bc --check` accepts representative integer and binary32 loops and
  reports no operation introduced by this surface that aborts trace recording.
- The ordinary implementation has a benchmark budget before any native
  lowering exists.
- Existing arithmetic and casts remain byte-identical when the namespaces are not
  used.

## Track S: richer checked span views

### Goal

Express writable subranges, one validated loop range over several spans, and
strided struct-field views without exposing pointers, offsets, strides, or
alias assertions. These APIs should simplify ordinary buffer, image, audio,
network, and ECS code even when every access remains a checked Lua operation.

### S0: writable slices

Add an inclusive writable slice corresponding to `Span.slice`:

```nupp
local middle = writable:slice(first, last)
middle:set(1, replacement)
span.commit(middle)
```

The result is an affine child writer borrowed from the parent. While it is
live, every exclusive use and commit of the parent is rejected. Dropping or
committing it releases that barrier. Empty slices use the same `first,
first - 1` convention as shared spans.

`FixedWriteSpan<T, N>` inherits the same operation and returns the same dynamic
child type. The static parent count still discharges literal range errors at
check time. There is no second fixed-span slicing function or dependent return
type.

The final method contract is:

```nupp
slice: function(
    exclusive self: WriteSpan<T>, first: integer, last: integer?
): Owned<WriteSpan<T>> borrows(self)
```

The standard library validates the range, applies the private offset, and makes
the subregion assertion at one audited unsafe site. Public code cannot construct
the representation or assign a region path.

Tests cover empty, nested, nonzero-offset, first/last element, automatic drop,
explicit commit, parent blocking, and interactions with `splitAt`, `shared`,
`getMut`, and `ref`.

### S1: a checked common iteration range

Add a small immutable range value produced only after validating inclusive
bounds against every supplied span count:

```nupp
local rows = span.range(first, last, output, transforms, motion)
for i = rows.first, rows.last do
    -- ordinary checked span operations
end
```

The constructor accepts `Span`, `WriteSpan`, `FixedSpan`, and
`FixedWriteSpan` through one sealed count-bearing span contract; it does not
accept arbitrary `{count: integer}` tables. Its final declaration uses a
borrowed typed vararg:

```nupp
function span.range(
    first: integer, last: integer, borrows ...: span.CountedSpan
): span.Range
```

Ownership modes on typed varargs are a required general language feature for
S1; Nupp does not have that spelling today. If that feature is not accepted,
skip S1. Do not substitute allocating tables, consuming plain varargs, or
`range2`/`range3` fixed-arity alternatives.

The typed-vararg feature resolves every argument at its call site against the
sealed contract and passes the original span value unchanged. `CountedSpan` is
a static constraint, not an existential runtime value: the call creates no
interface box, wrapper, table, or closure. A design that requires boxing does
not satisfy this prerequisite, so S1 is skipped rather than implemented that
way.

The constructor checks all dynamic counts once, accepts the canonical empty
range, and returns ordinary integer bounds. When all counts and bounds are
static, the checker discharges the validation at compile time. The range
carries no pointer and grants no access by itself.

Ordinary span operations continue checking each access. A later optimizer may
use the range construction as a dominating bounds witness only after its IR
retains the exact span identities and control-flow dominance. No source-level
`unchecked` indexing follows from constructing a range.

Compiler handling attaches to the resolved standard-library declaration
identity. Aliasing `span.range` keeps that identity; a user function shadowing
the name is an ordinary function and receives neither special typing nor a
bounds witness.

### S2 decision: whether strided spans are an ordinary feature

Make this decision from source sketches and the existing Tecs 28-byte-stride,
vertex, and padded-image measurements before implementing a public type. The
question is whether a strided view materially improves safe ordinary Nupp code
with native compilation disabled.

If the answer is no, omit S2 entirely and keep target field projections inside
future native IR. Do not land an experimental `StridedSpan`, unsafe stride
constructor, or provisional `span.field` API.

If the answer is yes, land the final surface below once.

### S2 implementation: strided shared and writable spans

Add sealed private-representation `StridedSpan<T>` and
`StridedWriteSpan<T>` contracts with count, checked `get`/`getMut`/`set`,
slicing, sharing, and commit. Fixed parents produce
`FixedStridedSpan<T, N>` or `FixedStridedWriteSpan<T, N>` through the same
projection operation. Stride is stored in bytes internally and may not be zero
or smaller than the addressed field.

The first safe constructor is a struct-field projection:

```nupp
local xs = span.field(transforms, "x")
local flags = span.field(writableStates, "flags")
```

`span.field` is a compiler-checked intrinsic like `offsetof`: the receiver's
element type must be a reified struct and the second argument must identify one
declared field. The checker resolves the result element type, records a semantic
field reference for rename/references tooling, and lowers the offset and stride
from the target-validated layout. It rejects bitfields and other fields that
cannot be addressed independently.

Special handling attaches to the resolved exported definition of `span.field`,
not its spelling. Aliasing the export preserves the identity; shadowing it
produces an ordinary call. This is the same identity rule as Track N.

A writable projection exclusively borrows its parent, so only one writable
field projection may be live from that parent. Code mutating several fields of
one struct uses the existing `WriteSpan.getMut` element reference instead of a
second field-partition API.

The public API has no raw-stride constructor or pointer projection. Foreign
interleaved storage is not admitted in this track.

### Track S exit criteria

- No new operation exposes or accepts a raw address, byte offset, byte stride,
  region path, or no-alias claim. Existing checked element references such as
  `WriteSpan.getMut(): T* borrows(self)` remain intentional.
- Shared/writable constness and ownership survive aliases, generic forwarding,
  module summaries, and suspension checks.
- Overflow in `offset + (count - 1) * stride + fieldSize` is checked before a
  view is constructed.
- Range and slice failures are attributed to the construction call, not a later
  native boundary.
- Fixed spans discharge static range checks and preserve their count refinement
  through field projections. Writable slices deliberately return the one
  dynamic child type.
- `./bin/nupp bc --check` accepts a representative writable-slice loop and,
  when those optional phases land, range and strided-view loops without boxing,
  closure construction, or trace aborts.
- The existing span API remains source-compatible.

## Track E: allocation and raising guarantees

### Goal

Turn the existing `allocates` and `raises` effect facts into guarantees that
survive direct module boundaries and can be required by checked regions. Do not
introduce a parallel effect analysis, serialize file-local alias paths, or use
documentation-only `@raises` text as proof.

### Semantics

`allocates = false` means the modeled call graph performs no Nupp/Lua-managed
allocation: no table, record, closure, coroutine, variable-size cdata, owned
resource, implicit boxing, or call whose allocation behavior is unknown.
Module initialization is outside a later function call's guarantee.

This is not automatically a whole-process hard-real-time guarantee. A trusted
foreign declaration may promise `allocates = false`, but Nupp cannot inspect
the implementation or the allocator inside the OS, VM, or driver. Documentation
must call that trust boundary out directly.

`raises = false` means no modeled path raises a catchable Nupp/Lua error. It
includes direct `error`/`assert`, calls whose raising behavior is true or
unknown, checked operations whose precondition is not proven, and invoked
metamethods with unknown behavior. Fatal process termination and unrecoverable
out-of-memory behavior are outside the language error model.

The facts are independent. A function may allocate without raising, raise
without a modeled allocation, or promise neither.

### E0: observed cross-module call guarantees

Keep complete effect summaries, including parameter-rooted read, write, shape,
escape, and return paths, file-local. Export only two positive facts for a
directly exported callable definition:

```text
noAllocate
noRaise
```

Store them in a `callGuarantees` sidecar, not the module result's existing
`effects` field, which already means requested native-library features. The
sidecar is also separate from the ordinary type/interface fingerprint.

An importing checker records an observation whenever a checked region or
optimization consults one of these facts for an exact exported definition. The
observation stores the consulted value, including absence; a rejected proof and
its cached diagnostic therefore depend on `absent` just as a successful proof
depends on `present`. The incremental dependency key contains the export
identity, guarantee name, and observed value. Consequently:

- a private body edit still invalidates only its own module;
- a body edit that leaves both exported facts unchanged invalidates no
  dependant;
- changing a fact does not recheck dependants that never observed it;
- every dependant that observed a different present-or-absent value is
  rechecked;
- when a callee gains a guarantee, a dependant previously rejected for its
  absence is rechecked and the cached diagnostic disappears.

Do not place these facts on `types.Func` in this phase, because doing so would
fold them into the normal interface identity and destroy that granularity.
Direct aliases whose exact exported definition remains known may preserve the
sidecar identity. Computed functions, gradual values, unknown methods, and
higher-order parameters remain unknown. Add function-type qualifiers only in a
future plan with a demonstrated callback requirement.

Visible bodies derive the bits from their existing complete inferred summary.
Bodyless and foreign declarations derive them from the existing trusted
`@effects` contract. A missing, stale, gradual, or otherwise unknown callee has
neither positive fact.

### E1: checked regions

Add checked regions analogous to `nosuspend do`:

```nupp
noalloc do
    updateExistingValues()
end

noraise do
    publishAlreadyValidatedState()
end
```

The checker rejects the first reachable operation whose inferred or declared
summary may allocate or raise, respectively. Nesting the regions requires both
guarantees. The regions emit no runtime guard and do not suppress errors or
redirect allocation.

Use dedicated diagnostics with the same call-chain presentation as suspension:
the primary site is the operation inside the region, related information walks
through known callees, and help names the unknown or positive effect that must
be removed or contracted.

Do not add `noalloc function` or `noraise function` type syntax in this phase.
Visible functions already receive inferred summaries, API declarations already
have checked `@effects`, and direct imported calls gain E0 transport. Add
higher-order function-type qualifiers only after a real callback API cannot be
expressed without them.

### E2: precision required by ordinary code

- Recognize allocation-free scalar cdata and standard numeric operations after
  Track N establishes their implementation.
- Distinguish construction that allocates from mutation of existing storage.
- Let a proven range precondition make a checked span access non-raising inside
  the dominated region; absent CFG proof it remains conservatively raising.
- Model cleanup paths: a non-raising body is not `noraise` if an automatic drop
  may raise, and a non-allocating body is not `noalloc` if cleanup may allocate.
- Preserve both facts through recursion by pessimistic fixed-point analysis.

### Tests and exit criteria

- Same-file and imported direct calls produce the same positive guarantees and
  region diagnostics.
- A private helper body edit rechecks one module.
- Changing an exported guarantee rechecks only dependants whose cached proof
  observed that exact fact; an unobserving dependant remains reusable.
- A callee gaining `noAllocate` or `noRaise` clears a dependant's cached
  checked-region error without a clean build.
- Unknown callbacks, gradual calls, unresolved methods, and uncontracted C
  functions fail both checked regions.
- Tables, records, closures, strings requiring construction, cdata, owners,
  error paths, bounds failures, metamethods, and cleanup are each classified by
  focused tests.
- `@effects` cannot hide a visible body's allocation or raising behavior.
- Trusted bodyless and C declarations are clearly identified as trust
  boundaries in diagnostics and generated documentation.
- `./bin/nupp bc --check` accepts representative checked-region hot loops; the
  regions emit no closure, protected call, or runtime guard.
- Normal code outside checked regions remains accepted; the feature adds a way
  to require a proof rather than imposing one globally.

## Sequencing

The tracks can be reviewed independently, but use this landing order:

1. **A0–A2**, completing the one ordinary C-header and typed-pointer path before
   any native consumer uses it.
2. **N0–N1**, fixing representation and landing the final allocation-free
   integer surface before any optimizer recognizes it.
3. **S0–S1**, which are small ordinary span improvements and exercise the
   ownership facts native wrappers need.
4. **E0–E1**, reusing the existing effect engine and making cross-module helper
   guarantees real without broadening interface invalidation.
5. **N2**, only when the final allocation-free, trace-recordable binary32 path
   passes N0's oracle; otherwise it remains absent.
6. **S2**, only if the pre-implementation ordinary-use decision is yes and
   Track A can supply the final target-validated field layout.
7. **N3 and E2**, adding compiler consumers and effect precision only after the
   public semantics are stable.

Parallel work is safe between Track N, S0/S1, and E0 as long as each changes its
own compiler schema version and rebases before integration. Track S2 depends on
Track A. No track depends on `@native`.

## Integration with native lowering

After all four tracks have passed their independent exit criteria, native
lowering may consume them in separate work:

- Track A supplies typed C declarations and layout assertions;
- Track N supplies exact scalar IR operations that a vectorizer may legally
  combine;
- Track S supplies checked bounds, offsets, strides, and ownership provenance;
- Track E admits closed helper graphs without inspecting every implementation
  in the caller's file.

Consumption is one-way. Removing or disabling native compilation leaves every
program using these features valid and semantically unchanged.

## Whole-plan acceptance

Before this plan is complete:

- one ordinary Tecs-shaped system uses the fixed-width numeric namespaces,
  writable slices, and a non-allocating/non-raising helper contract with native
  compilation disabled; it also uses the checked common range if S1 lands;
- the same source passes with JIT enabled and disabled;
- `nupp export-c` emits the only C declaration of its ordinary structs, and an
  independent C fixture compiles and interoperates through typed pointers;
- host and cross-target struct descriptions agree with that fixture;
- observed call guarantees survive a clean build, incremental rebuild, module
  reload, and a declaration-only package without invalidating unobserving
  dependants;
- ownership tests cover every span capability through success, error,
  suspension, cleanup, and early return;
- `./bin/nupp bc --check` accepts the header wrapper, numeric loop, span loop,
  and checked-effect loop;
- `./bin/nupp test` and `./bin/nupp fixpoint` pass after every compiler milestone;
- no acceptance test refers to `@native`, generated native IR, SIMD assembly, or
  a native performance number;
- no accepted feature has a deprecated alternate API, temporary runtime
  representation, or fallback scheduled for removal.

Only after that baseline lands should the native-functions plan replace its
prototype-specific layout, numeric, span-range, and helper-effect logic with
these released facilities. Track A's compiler-owned physical pointer erasure is
the final typed-pointer bridge, not prototype logic to replace again.
