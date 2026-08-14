# Independent foundations for native lowering

Status: planned; each track ships without `@native`

## Decision

Land four ordinary Nupp capabilities before making native function lowering a
production language feature:

1. compiler-owned C identities for reified structs;
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
  rides on function types, and there are no `noalloc` or `nothrow` checked
  regions.

The work below extends those surfaces. It does not replace them.

## Shared rules

- Native compilation, generated C, and the presence of a C compiler may not
  affect whether any example in this plan runs.
- New guarantees are positive proofs. Unknown code loses an optimization or is
  rejected from a checked region; it never receives an optimistic default.
- A compiler-private C tag is not a public foreign ABI, linker symbol, or
  serialization identity.
- Existing arithmetic operators keep their current meaning. Same-width
  arithmetic is requested through explicit ordinary functions.
- Bounds and disjointness come from spans and ownership. Do not expose
  `restrict`, `noalias`, unchecked stride construction, or a vectorization
  assertion in source.
- Each feature gets its own diagnostics, reference text, focused tests, and
  changelog entry. Native lowering consumes only released behavior, never an
  internal prototype shape.

## Track A: compiler-owned C identities for structs

### Goal

Give every reified ordinary struct a deterministic, target-aware description
that can be named in compiler-generated C and in compiler-generated LuaJIT FFI
declarations. Keep that name private and preserve Nupp's nominal type identity,
hot reload behavior, and layout checks.

This is the one hard prerequisite among the four tracks. The checked C spike
currently verifies every field and then erases typed span pointers to `void*`.
Production lowering must instead be able to emit and bind the actual private
aggregate type.

### Identity model

Introduce a canonical compiler record containing at least:

- the declaration's nominal identity, including its module identity;
- a semantic fingerprint of its fields and nested type graph;
- the selected target-layout key and layout schema version;
- size, alignment, field offsets, field sizes, and field C types;
- a deterministic private tag;
- the dependencies that must be declared before it by value.

The private tag is derived from the nominal identity, semantic fingerprint,
and compiler ABI schema. It is not derived from the source basename alone. Two
nominal structs with identical fields remain different types, while the same
declaration rebuilt byte-identically receives the same tag. A layout-changing
hot reload receives a new tag so old cdata and new cdata cannot be confused.

The tag may appear in generated files and diagnostics intended for compiler
developers. User source cannot name it, override it, export it as a stable ABI,
or depend on its exact spelling.

### C declaration rules

The target declaration emitter:

- emits fixed-width standard C types rather than target-dependent aliases;
- forward-declares pointer-only cycles;
- topologically orders aggregates embedded by value;
- rejects a by-value cycle before generation;
- preserves declared field order and explicit bit widths;
- represents fixed arrays and nested structs without flattening them;
- emits `_Static_assert` checks for size, alignment, and every field offset;
- fingerprints the calling-convention and target-layout inputs beside the
  declaration.

The first slice covers the reified field vocabulary the target-layout model can
already prove. A field shape that lacks a target model is declined with a
specific diagnostic; the emitter does not ask the build host and guess.

### Runtime reification

On the host runtime, ordinary structs move from an anonymous `ffi.typeof`
aggregate to a compiler-private named aggregate registered with `ffi.cdef`,
then obtain the same metatype behavior they have today. This must preserve:

- construction and field access;
- `is` tests and nominal distinction;
- pointer and fixed-array types;
- `sizeof`, `alignof`, `offsetof`, and `layoutof`;
- nested and self-pointer structs;
- module isolation, incremental builds, and hot reload.

Before selecting this representation, characterize LuaJIT's global C namespace
for repeated identical declarations, old/new layout coexistence, mutually
referential tags, and modules loaded in different orders. If named runtime
reification cannot preserve those properties, retain the anonymous runtime
ctype and let compiler-owned glue perform an explicitly verified pointer cast.
By-value native boundaries remain out until the runtime and generated C agree
on one named identity.

### Milestones

**A0 — canonical target ABI record**

- Factor one target-aware aggregate description out of `layoutof`, semantic
  reflection, and the existing target-layout implementation.
- Include its schema version in compiler and incremental cache keys.
- Make host and cross-target queries use the same field graph and differ only
  by the selected target model.

**A1 — private declaration emitter**

- Emit one deterministic C declaration graph for a selected struct and target.
- Add independent parser/compile fixtures that compare the emitted declaration
  against Nupp's target layout record.
- Validate with Clang for every supported target triple available in CI, but do
  not require Clang to check or run ordinary Nupp.

**A2 — host FFI identity**

- Bind private tags in generated Lua or retain anonymous ctypes behind a
  verified compiler-owned cast, based on the characterization above.
- Preserve nominal identity and hot reload in either implementation.
- Remove `void*` from the spike's typed span slots only after this milestone.

**A3 — compiler-owned signature use**

- Permit internal wrappers and generated declarations to use the private type.
- Keep ordinary user-written `cdef` behavior unchanged: external C aggregates
  remain explicitly declared `cdef struct` types.
- Add an inspection view that prints semantic and layout identities without
  promising the private tag as API.

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
- Clean, incremental, hot-reloaded, and reversed-module-order runs agree.
- Ordinary projects that never request a C declaration need no external
  compiler and preserve their existing runtime behavior.

## Track N: explicit fixed-width scalar arithmetic

### Goal

Add ordinary, portable operations whose names state the width and rounding
contract. They provide useful binary and buffer manipulation on their own and
give future scalar, SIMD, and native backends operations that can lower one for
one without changing the meaning of `+`, `*`, or a `float` annotation.

### Public surface

Begin with compiler-owned standard modules rather than new operators:

```nupp
local f32 = require("nupp.f32")
local i32 = require("nupp.i32")
local u32 = require("nupp.u32")

local speed: float = f32.mul(distance, inverseTime)
local flags: uint32 = u32.orBits(oldFlags, bit)
local mixed: uint32 = u32.rotateLeft(flags, 7)
```

The exact first surface is deliberately small:

- `f32`: `round`, `add`, `sub`, `mul`, `div`, `sqrt`, `min`, `max`, `fma`,
  `fromBits`, and `toBits`;
- `i32` and `u32`: wrapping `add`, `sub`, and `mul`; bitwise and/or/xor/not;
  left, logical-right, and arithmetic-right shifts where meaningful; rotates;
  signed or unsigned comparisons; and explicit cross-width conversions.

Every operation returns the declared fixed-width type. Normal operators used on
the result retain their existing LuaJIT semantics; a source expression requests
same-width arithmetic only by continuing to call the fixed-width operations.

Compiler recognition attaches to the immutable standard-library declaration
identity, not to a table/member spelling that user code could replace.

### Numeric contract

Write the contract before optimizing the implementation:

- `f32` arguments are converted to IEEE-754 binary32 before the operation and
  the result is rounded once to binary32, using round-to-nearest ties-to-even;
- `fma` is one fused operation, never an alias for `add(mul(a, b), c)`;
- signed zero, infinity, subnormals, and each operation's NaN behavior are
  specified; bit conversion preserves all bits, while arithmetic may use the
  documented canonical NaN policy;
- `i32` and `u32` arithmetic wraps modulo 2^32;
- shift counts are masked to five bits, matching the chosen ordinary contract;
- signed right shift is arithmetic and unsigned right shift is logical;
- conversions state truncation/rounding and reject or define every out-of-range,
  NaN, and infinity case.

Do not infer binary32 arithmetic merely because values came from `float`
storage. That would silently change existing programs and would make an
annotation alter results.

### Ordinary implementation

The fallback must be a real ordinary Nupp implementation. It may use audited
bit manipulation or a compiler-bundled helper, but it may not make one foreign
call per operation in the supported steady-state path. Characterize LuaJIT
scalar cdata coercion before deciding the representation.

If a boxed or scratch-cdata fallback is initially necessary for correctness,
make its allocation and JIT cost visible in benchmarks and keep it experimental
until an allocation-free fallback exists. Correct-but-pathological behavior is
not enough for an independently useful standard module.

### Milestones

**N0 — executable semantic oracle**

- Specify every first-slice operation in terms of result bits.
- Build a small independently compiled C oracle at strict floating settings and
  a software reference for cases where the host floating environment is not a
  sufficient oracle.
- Pin edge vectors before adding the public module.

**N1 — `i32` and `u32` modules**

- Land allocation-free wrapping, shifts, rotates, comparisons, and conversions.
- Use them in the existing bitset where they improve clarity without regressing
  its measured performance.

**N2 — `f32` module**

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
- The ordinary implementation has a benchmark budget before any native
  lowering exists.
- Existing arithmetic and casts remain byte-identical when the modules are not
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

The standard library validates the range, applies the private offset, and makes
the subregion assertion at one audited unsafe site. Public code cannot construct
the representation or assign a region path. The exact result spelling
(`Owned<WriteSpan<T>> borrows(self)` or an equivalent transported capability)
is selected by an ownership checker spike; the invariant above is the API.

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

The constructor accepts values through a sealed count-bearing span contract;
it does not accept arbitrary `{count: integer}` tables. It checks all counts
once, accepts the canonical empty range, and returns ordinary integer bounds.
It carries no pointer and grants no access by itself.

Ordinary span operations continue checking each access. A later optimizer may
use the range construction as a dominating bounds witness only after its IR
retains the exact span identities and control-flow dominance. No source-level
`unchecked` indexing follows from constructing a range.

If heterogeneous variadic span arguments cannot preserve ownership modes and
diagnostic sites cleanly, start with fixed arities used by real systems rather
than accepting a table that allocates in the hot path.

### S2: strided shared and writable spans

Add sealed private-representation `StridedSpan<T>` and
`StridedWriteSpan<T>` contracts with count, checked `get`/`getMut`/`set`,
slicing, sharing, commit, and pointer projection available only to trusted
foreign/native adapters. Stride is stored in bytes internally and may not be
zero or smaller than the addressed field.

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

A writable projection exclusively borrows its parent. The first version permits
one writable field projection from a parent at a time. Multiple simultaneous
writable projections require an explicit compiler-produced field partition
witness proving their byte ranges do not overlap; do not infer that from two
user-provided offsets.

The public API has no raw-stride constructor. Libraries needing interleaved
foreign data may add an audited unsafe constructor later, with alignment,
extent, overflow, provenance, and lifetime checked in one place.

### S3: usefulness and lowering gate

Before treating strided views as permanent surface, measure ordinary Nupp code
for:

- a Tecs component column with a 28-byte struct stride;
- interleaved vertex attributes;
- image rows with padding;
- a contiguous span expressed with stride equal to element size.

Keep the field projection if it materially improves safe source clarity even
without native lowering. If it exists only to feed one optimizer, keep it in
compiler IR instead of making it a public span type.

### Track S exit criteria

- No public operation exposes or accepts a pointer, byte offset, byte stride,
  region path, or no-alias claim.
- Shared/writable constness and ownership survive aliases, generic forwarding,
  module summaries, and suspension checks.
- Overflow in `offset + (count - 1) * stride + fieldSize` is checked before a
  view is constructed.
- Range and slice failures are attributed to the construction call, not a later
  native boundary.
- The existing span API remains source-compatible.

## Track E: allocation and raising guarantees

### Goal

Turn the existing `allocates` and `raises` effect facts into guarantees that
survive module and value boundaries and can be required by checked regions.
Do not introduce a parallel effect analysis or use documentation-only
`@raises` text as proof.

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

### E0: complete cross-module summaries

- Serialize normalized complete effect summaries into module interfaces and
  include them in incremental fingerprints.
- Resolve imported direct calls by definition identity and substitute
  parameter-rooted paths the same way as same-file calls.
- Preserve `top` for a missing, stale, gradual, computed, or otherwise unknown
  callee.
- Carry positive `noAllocate` and `noRaise` facts on resolved callable values,
  parallel to the existing `noYield` fact, without discarding the complete
  summary used by alias and mutation analysis.
- Make nominal methods, exported functions, bodyless declarations, and trusted
  `cdef` contracts follow one serialization schema.

Changing a public effect summary invalidates dependants even when the function's
parameter and result types are unchanged.

### E1: checked regions

Add checked regions analogous to `nosuspend do`:

```nupp
noalloc do
    updateExistingValues()
end

nothrow do
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

Do not add `noalloc function` or `nothrow function` type syntax in this phase.
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
- Model cleanup paths: a non-raising body is not `nothrow` if an automatic drop
  may raise, and a non-allocating body is not `noalloc` if cleanup may allocate.
- Preserve both facts through recursion by pessimistic fixed-point analysis.

### Tests and exit criteria

- Same-file and imported direct calls produce the same summaries and region
  diagnostics.
- A summary-only edit invalidates and rechecks every dependent module.
- Unknown callbacks, gradual calls, unresolved methods, and uncontracted C
  functions fail both checked regions.
- Tables, records, closures, strings requiring construction, cdata, owners,
  error paths, bounds failures, metamethods, and cleanup are each classified by
  focused tests.
- `@effects` cannot hide a visible body's allocation or raising behavior.
- Trusted bodyless and C declarations are clearly identified as trust
  boundaries in diagnostics and generated documentation.
- Normal code outside checked regions remains accepted; the feature adds a way
  to require a proof rather than imposing one globally.

## Sequencing

The tracks can be reviewed independently, but use this landing order:

1. **A0–A1**, because one canonical target ABI record prevents later C-facing
   features from inventing competing layout descriptions.
2. **N0–N2**, because numeric meaning must exist before any optimizer or SIMD
   backend recognizes the operations.
3. **S0–S1**, which are small ordinary span improvements and exercise the
   ownership facts native wrappers need.
4. **E0–E1**, reusing the existing effect engine and making cross-module helper
   guarantees real.
5. **A2–A3**, after named-ctype behavior and hot reload have been characterized.
6. **S2–S3**, after Track A can supply target-validated field layouts and the
   ordinary-use benchmark justifies a public strided type.
7. **N3 and E2**, adding compiler consumers and precision only after the public
   semantics are stable.

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

- one ordinary Tecs-shaped system uses the fixed-width numeric modules, a
  checked common range, writable slices, and a non-allocating/non-raising helper
  contract with native compilation disabled;
- the same source passes with JIT enabled and disabled;
- host and cross-target struct descriptions agree with independent C fixtures;
- effect summaries survive a clean build, incremental rebuild, module reload,
  and a declaration-only package;
- ownership tests cover every span capability through success, error,
  suspension, cleanup, and early return;
- `./bin/nupp test` and `./bin/nupp fixpoint` pass after every compiler milestone;
- no acceptance test refers to `@native`, generated native IR, SIMD assembly, or
  a native performance number.

Only after that baseline lands should the native-functions plan replace its
prototype-specific `void*`, numeric, span-range, or helper-effect logic with
these released facilities.
