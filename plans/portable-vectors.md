# Portable SIMD vectors

Status: competing scope for `@native`, not selected

## Decision to make

Decide whether Nupp should expose ordinary portable vector values and compile
the functions that use them transparently, or initially confine unboxed vector
values to the explicit [`@native`](native-functions.md) function boundary.

The proposal is deliberately stronger than a vector-shaped library over FFI.
A vector operation has a complete scalar meaning in ordinary generated Lua,
while the compiler may lower a whole eligible function or outlined region to
native SIMD code. The program does not acquire a different meaning when that
lowering succeeds, and no annotation is required to make vectors legal.

This is the Java Vector API model applied beside LuaJIT rather than inside it:

```text
Nupp source
    |-- ordinary lowering --> LuaJIT plus boxed vector fallback
    `-- vector lowering ----> checked vector IR --> native code
```

The explicit `@native` design starts from a required whole-function native
boundary and may permit vector operations inside it. This design starts from
first-class vector values and discovers the largest native unit that preserves
their ordinary semantics. They share native IR and emitters, but make different
promises about fallback, boxing, and whether the boundary is written or
inferred. Those promises should not both become public before the comparison in
this plan has been measured.

## Goal

Let ordinary Nupp express portable data-parallel computation with explicit
vectors, masks, loads, stores, shuffles, and reductions. On supported x86-64
and AArch64 CPUs, a sequence of those operations should reliably become a
small corresponding sequence of SSE/AVX or NEON instructions. On every other
supported target it must still run correctly through a scalar implementation.

A representative loop should need no marker:

```nupp
local simd = require("nupp.simd")
local span = require("nupp.span")

local function scaleAdd(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>,
    scale: float
): nil
    if output.count ~= input.count then
        error("length mismatch", 2)
    end

    local species = simd.preferred<float>()
    local covered = species:loopBound(output.count)
    local first = 1
    while first <= covered do
        local value = species:load(input, first)
        species:store(output, first, value * scale)
        first = first + species.lanes
    end

    local mask = species:indexInRange(first, output.count)
    if mask:any() then
        local value = species:load(input, first, mask)
        species:store(output, first, value * scale, mask)
    end
end
```

The compiler may replace this function with one checked native call. If it
does not, the same source executes the same loads, operations, mask, and stores
through the Lua fallback.

## Non-goals

- Do not improve LuaJIT's own trace IR, register allocator, or machine-code
  backends, and do not maintain a Nupp fork of LuaJIT.
- Do not promise that scalar loops are automatically vectorized. Explicit
  vector operations are the portable performance contract.
- Do not make every ordinary Nupp construct native-compilable. Unsupported
  constructs stay in Lua and may bound an outlined native region.
- Do not expose architecture registers, instruction mnemonics, or raw opcodes
  through the portable API.
- Do not make a vector an aliasing view over memory. Spans are views; vectors
  are values loaded from and later stored to them.
- Do not promise SVE's scalable-vector semantics in the first implementation.
  AArch64 begins with fixed 128-bit NEON.
- Do not add GPU vectors, GPU kernels, or a tensor system under this name.
- Do not silently enable reassociation, reciprocal approximations, contraction,
  or other relaxed floating-point rewrites.
- Do not use one FFI call per vector operation. That is a correct fallback
  experiment, not an acceptable optimized implementation.

## Why this competes with an explicit-only native boundary

Both designs need checked memory boundaries, a portable numeric IR, target
lowering, CPU dispatch, executable-memory policy, and performance gates. Their
difference is where the language draws the native boundary:

| Question | Portable vectors | Explicit `@native` |
| --- | --- | --- |
| What is public? | vector and mask values | a required whole-function contract |
| What changes semantics? | nothing; native lowering is optional | nothing; the annotation adds a compilation requirement |
| What happens when lowering fails? | execute the scalar fallback | report that the native function cannot compile |
| May a vector escape? | yes, boxed at a boundary | normally no |
| May ordinary Lua work surround it? | yes, with outlining or fallback | no, unless outside the call |
| Where is the native boundary? | inferred function or region | written function boundary |
| Main advantage | Java-like ordinary language model | simple, explicit performance boundary |
| Main cost | boxing, outlining, and fallback complexity | an annotation and smaller admitted subset |

`@native` makes performance failures easier to diagnose because the user chose
one all-native unit. Portable vectors make the annotation optional: there is
one ordinary language, and native compilation can be an implementation strategy.

The transparent vector design wins only if it can retain `@native`'s essential
performance property: one native transition around a useful amount of work,
with intermediate vectors never materialized. If a common expression becomes
four FFI calls and three cdata temporaries, the design has failed even though
its answer is correct.

## Value model

### Vectors are immutable snapshots

A vector contains lane values. Loading takes a snapshot of memory; storing
writes the current lanes back. Later mutation of the source memory does not
change the vector, and computing a new vector does not change memory until a
store:

```nupp
local before = species:load(values, offset)
values:set(offset + 1, 0.0)
local after = species:load(values, offset)
-- before and after are independent values.
```

Vectors are unrestricted, trivially copyable values. They carry no owner,
borrow, pointer provenance, or cleanup obligation. A vector element type may
not itself be owned, borrowed, pinned, retained, GC-managed, or pointer-shaped.

The first element set is `float`, `int32`, `uint32`, `int64`, and `uint64`.
`boolean` lives in masks rather than data vectors. Smaller integer lanes and
`number` wait until conversion, overflow, and fallback representation are
specified. `number` is particularly unattractive because its Lua scalar
representation does not state a C lane width.

### Species, not host width in type identity

The preferred vector width is a runtime CPU fact. A portable build may choose
256-bit AVX2 on one x86-64 machine, 128-bit SSE on another, and 128-bit NEON on
AArch64. Nupp must not resolve the build host's preferred width into a const
generic and make it part of a public type fingerprint.

Use a Java-shaped species model for preferred vectors. The provisional public
types are:

```nupp
sealed interface simd.Species<T>
    readonly lanes: integer
    readonly bits: integer
end

sealed interface simd.Vector<T>
    readonly species: simd.Species<T>
end

sealed interface simd.Mask<T>
    readonly species: simd.Species<T>
    readonly lanes: integer
end
```

`simd.preferred<T>()` returns one process-stable species selected from CPU
features. Every operation requiring two vectors or a vector and mask requires
equal species. The checker proves equality when all operands derive from one
species binding; the fallback checks it otherwise. Native specialization makes
the species a compile-time constant inside each generated version and removes
the check.

Exact-width values remain useful for file formats, C ABI work, testing, and
algorithms whose lane count is part of their meaning. Reserve, but do not add
in the first slice:

```nupp
simd.FixedVector<T, const N: integer>
simd.FixedMask<T, const N: integer>
```

A fixed vector still has value semantics and may lower to several registers or
a scalar sequence when `N` is wider than the target. It is not the preferred
loop abstraction. Conversion between preferred and fixed vectors is explicit.

### Construction and adoption of existing values

Existing values enter a vector through a copy:

```nupp
local broadcast = species:splat(scale)
local lanes = species:fromLanes(x, y, z, w)
local loaded = species:load(values, offset)
```

`fromLanes` checks its runtime arity against the species in the fallback and is
normally useful with an exact-width species. A scalar combined with a vector
of the same element type broadcasts implicitly:

```nupp
local result = vector * scale
```

Conversions between signedness, integer and floating point, or lane element
widths are explicit. Reinterpreting bits is distinct from numeric conversion.

There is no zero-copy `adopt(pointer)` operation. A register cannot remain an
alias to memory, and giving the fallback a different aliasing rule would make
optimization observable. Compatible structs and fixed arrays may receive
checked load/store conveniences, but they still copy the bits into or out of a
vector value.

### Boxing and escape

In native code a vector is an unboxed register or spill slot. In ordinary Lua
it is an opaque immutable cdata value containing a species identifier and lane
storage. A mask has the same dual representation. Through AVX2 the private box
has capacity for 32 lane bytes plus its tag; wider or scalable targets owe a
new representation decision rather than silently truncating into it. Compiler-
owned operators and metatype hooks preserve vector equality after a value has
flowed through gradual Lua.

Vectors may cross functions, be returned, enter a table, or flow through
`any`. Those operations box an unboxed value or retain an already boxed one.
Unboxing occurs when an eligible native region consumes it. Box identity is
not observable: equality compares lane type, species, and lane values rather
than cdata address.

The optimizer may remove boxing only if these properties remain true:

- lane reads and equality answer identically;
- NaN lanes retain the language's chosen comparison behavior;
- signed zero and bit reinterpretation retain their bits;
- an error is attributed to the same source operation unless the existing
  `error-site` guarantee was relaxed;
- keeping or removing the box does not change an observable finalizer, because
  vector boxes have none.

Boxing is allowed semantically but should be visible in performance tooling.
`nupp check --performance` can report a vector crossing a hot-looking dynamic
boundary, without making an ordinary correct program fail.

## Operations

### First portable surface

- zero, splat, lane-list construction, and species queries;
- contiguous aligned or unaligned load and store;
- masked load and store with inactive load lanes defined as zero;
- `+`, `-`, `*`, `/`, unary negation, `min`, `max`, and explicit `fma` for
  floating lanes;
- integer arithmetic and bit operations with the existing C-lane overflow
  behavior;
- elementwise equality and ordered comparison producing masks;
- mask `and`, `or`, `xor`, `not`, `any`, `all`, and population count;
- `select(mask, yes, no)`;
- lane extraction with a checked runtime index and constant-index fast path;
- `reduceAdd`, `reduceMin`, and `reduceMax` with a specified lane order;
- bit reinterpretation and explicit numeric conversion where lane counts and
  total widths permit it;
- `loopBound` and `indexInRange` for a scalar tail or one masked final step.

Gather, scatter, compress, expand, arbitrary permutation, saturating arithmetic,
transcendental functions, and approximate operations wait for measured use
cases and target parity. Each new operation owes a scalar definition before it
receives a machine instruction.

### Floating-point contract

The default vector operators preserve the corresponding lane operation and do
not reassociate expressions. `fma(a, b, c)` explicitly requests one fused
rounding; `a * b + c` does not silently contract. Reductions use increasing
lane order in the fallback and native implementation even when a tree would be
faster.

If relaxed vector arithmetic is later justified, add a distinct numeric
contract rather than smuggling it under the existing `@relax` guarantees,
which currently concern identity, loading, errors, frames, GC timing, and table
order. The contract must separately name reassociation, contraction, reciprocal
approximation, NaN choice, and signed-zero behavior.

### Bounds and tails

Every public load or store is span-based and bounds checked. Like `Span.get`,
its `first` argument is one-based; vector lanes are one-based when extracted.
An unmasked access requires `first >= 1` and
`first + lanes - 1 <= count`. A masked access requires
`1 <= first <= count + 1` and every active lane's corresponding span index to
be in range. `count + 1` is therefore valid only for an all-inactive mask.
`loopBound(count)` returns the greatest multiple of the species lane count no
larger than `count`. The native wrapper hoists checks when it can prove the loop
shape; otherwise the generated body returns a small status identifying the
source operation and Lua raises the ordinary error after the call.

Loads borrow a `Span<T>`. Stores require exclusive access to a
`WriteSpan<T>`. Passing sibling write regions remains valid through the
existing partition provenance. A native region receives projected pointers
only after all checks and retains them only for the call.

## Two execution modes, one meaning

### Lua fallback

`nupp.simd` supplies the complete reference implementation. It uses opaque FFI
cdata boxes and scalar lane operations, never raw Lua tables as public vector
values. The box is a compiler/runtime primitive even though its public surface
is typed as sealed interfaces; user code cannot implement another vector by
matching the fields. It is allowed to be slower, but it must work with the JIT
disabled and on a target with no supported SIMD instructions.

The fallback is load-bearing:

- it defines semantics before a native backend exists;
- it runs cold functions for which native compilation is not worthwhile;
- it handles vectors that cross a dynamic Lua boundary;
- it is the differential oracle for every native test;
- it lets an unsupported operation remain correct instead of disappearing
  from the language on one CPU.

No performance claim is made for a chain of fallback vector operations. The
documentation must say that reliable SIMD requires a successfully compiled
function or region, and tooling must say whether that happened.

### Native versions

The Nupp compiler recognizes the sealed vector operations by resolved identity,
not by a replaceable module field spelling. It lowers an eligible function to
a source-independent vector IR while continuing to emit its Lua version.

Generated Lua installs one cached dispatcher:

```text
scaleAdd
    |-- scaleAdd$avx2
    |-- scaleAdd$sse2
    |-- scaleAdd$neon
    `-- scaleAdd$lua
```

The first call selects a version from process CPU features and caches it. Each
native version covers a whole function or outlined loop and crosses the
Lua/native boundary once. Scalar parameters pass directly; spans project
checked pointers and counts; vector arguments and results use private ABI
slots so their public representation is not an ABI promise.

Native-to-native calls use a private direct convention when both definitions
are known. Otherwise the call ends the region, boxes live vectors, and resumes
through Lua. A first release may reject the whole native candidate rather than
outline around such a call.

### Native eligibility

The first compiler accepts complete functions containing:

- numeric and boolean locals;
- species, vectors, and masks;
- spans and reified structs containing supported scalar fields;
- counted loops, conditionals, structured exits, and closed guard failures
  that the compiler can report by source-site status;
- calls to a closed set of pure numeric intrinsics;
- statically resolved vector helpers whose bodies are also eligible.

The first compiler declines functions reaching:

- ordinary records, Lua tables, strings, or `any` in the candidate body;
- allocation, finalization, ownership transfer, or dynamic resource sets;
- dynamic dispatch, unknown callbacks, metamethod calls, or replaceable
  module bindings;
- I/O, logging, `require`, arbitrary FFI, or mutable globals;
- closures, varargs, protected calls, dynamically constructed errors, or
  suspension;
- an operation the selected target cannot scalarize correctly.

Declining is not a type error. The Lua version runs and tooling records the
reason. This differs intentionally from explicit `@native`.

After full-function compilation works, region outlining may admit a Lua prefix
and suffix around one eligible loop. It must preserve evaluation order, error
sites, borrows, cleanup, suspension rules, and source line attribution. No
outline is emitted when those proofs are incomplete.

## Compiler architecture

### Vector IR

The IR is typed, in static single assignment form, and deliberately smaller
than either Nupp or a target instruction set. It contains:

- scalar, vector, mask, pointer, count, and status values;
- blocks, branches, phis, calls to eligible helpers, and returns;
- vector construction, load, store, arithmetic, comparison, selection,
  conversion, shuffle, extraction, and reduction;
- explicit element type, species, mask, alignment knowledge, and source site;
- explicit checked-memory facts and no-alias region identities;
- no Lua object, table, string, GC, coroutine, or exception operation.

The checked IR serializer is versioned and included in module and build hashes.
The native service validates every opcode, type, block edge, register class,
memory access, and resource limit before allocating executable memory. The
serialized form is not a trusted instruction stream.

Initial optimization is restrained:

- constant and splat propagation;
- removal of redundant species and bounds checks;
- dead vector operation removal;
- common load elimination only under proven immutable or exclusive regions;
- helper inlining under a code-size limit;
- fusion of compare plus select and explicit FMA;
- no floating reassociation.

### DynASM backend

DynASM is a suitable final emitter, not the vector compiler. Nupp still owns
IR validation, instruction selection, liveness, vector and scalar register
allocation, spills, stack layout, ABI lowering, CPU dispatch, and source maps.

The x86 DynASM backend already has substantial SSE, AVX, and AVX2 vocabulary.
Its ARM64 backend currently marks SIMD instructions as unfinished. Extend the
ARM64 instruction table for the admitted NEON subset and test each encoding
against an independent assembler. Do not ship a general backend made of
unchecked `.long` words. The existing kernel spike may retain raw words as
evidence, not as the production abstraction.

Production builds pin or vendor the DynASM revision and ship its license; they
do not fetch an assembler while compiling or running a program. The vector IR
remains emitter-neutral so an invisible C/Clang AOT experiment can use the same
corpus and serve as an independent performance and code-generation oracle.

Begin with linear-scan register allocation. Vector live ranges receive target
vector registers; masks use vector registers for SSE/NEON and the appropriate
representation for later targets. Spills use aligned private stack slots.
Every generated function follows the platform ABI, preserves required
registers, checks stack alignment, and returns errors as status values rather
than unwinding through LuaJIT FFI.

### CPU dispatch

The native host reports one immutable feature set per process. Selection is by
required feature set, not architecture name alone:

- AArch64 baseline: scalar and NEON 128;
- x86-64 baseline: scalar and SSE2 128;
- x86-64 optional: AVX2 256, with `vzeroupper` at required boundaries;
- later features: FMA and other independently gated operations.

Do not select AVX, AVX2, or AVX-512 from CPUID bits without the corresponding
OS extended-state support. Cache selection by vector-IR fingerprint, target,
feature set, and numeric-contract version. Tests can force each lower feature
tier without lying about a feature the process cannot execute.

SVE and AVX-512 wait. Their scalable widths and predicate registers should not
distort the first API before the fixed-width design has evidence.

### Executable memory and workers

The code cache follows W^X: write, relocate, flush the instruction cache where
required, then execute. Hardened Apple hosts need `MAP_JIT` and the platform JIT
write-protection policy integrated with the Nupp host. A failure to obtain
executable memory selects the Lua fallback unless a future explicit native
contract requires compilation.

Generated code contains no pointer into a Lua heap object after its call ends.
Machine code and immutable metadata may be process-shared; Lua dispatch
closures and boxed constants remain state-local. Workers must not share cdata
or Lua anchors merely because they share a native body. Code-cache retirement
waits until no thread can execute the body.

A generated Lua artifact continues to run on a compatible stock LuaJIT. When
the Nupp native service is absent it selects the boxed fallback. Native vector
compilation is an acceleration supplied by the Nupp host, not a new undeclared
runtime dependency of every emitted Lua module.

### Errors, debugging, and inspection

A native body cannot throw through an arbitrary FFI frame. Checks return a
status plus source-site identifier; the wrapper raises the same Nupp error at
the boundary. Operations with possible user code or cleanup are not admitted
until a stronger unwind design exists.

Add inspection before optimization becomes invisible:

```sh
./bin/nupp vector inspect FILE LINE COLUMN
./bin/nupp vector ir FILE FUNCTION
./bin/nupp vector code FILE FUNCTION --target=aarch64-neon
```

The first reports whether a function compiled, which region was selected, its
species versions, boxing boundaries, and the first decline reason. IR and code
output retain source lines. Machine-code inspection must not require timing a
benchmark, and tests search decoded instructions rather than byte strings
alone.

Hot reload fingerprints the semantic vector body and invalidates its native
versions before installing the new Lua function. A stale dispatcher may finish
an already-entered call but may not receive a later one.

## Tooling and static semantics

The checker owns vector operators instead of trusting user-installed
metamethods. Completion and hover show lane type and species provenance. A
species mismatch reports both origins. A masked access explains whether its
mask and vector came from different species rather than falling back to an
unhelpful nominal mismatch.

Reflection exposes vector and mask semantics, not the private fallback cdata
layout or target register width. Module summaries include vector types,
resolved intrinsic identities, helper eligibility, and IR fingerprints without
copying machine code into dependants.

`nupp bc --check` continues to describe LuaJIT trace limitations in the Lua
fallback. Native-vector inspection is separate because its answer comes from
the Nupp native compiler, not LuaJIT bytecode.

Reserve one diagnostic family only after the repository-wide code inventory.
It must cover at least:

- unsupported vector element type;
- mismatched species or mask width;
- out-of-range fixed lane index;
- invalid conversion or bit reinterpretation;
- a vector intrinsic reached through a replaceable or gradual binding;
- native compilation declined, as performance information rather than an
  ordinary type error;
- native compilation required by a future contract and unavailable;
- invalid or over-limit serialized vector IR.

## Overuse and performance guidance

Portable vectors can be used where they are slower. That is not a semantic
error. Likely losing cases include:

- constructing or returning one vector per Lua call;
- storing every temporary in a table or `any`;
- operating on fewer elements than one or two full vectors;
- repeated gather-like scalar lane extraction;
- branch-heavy work with little arithmetic;
- memory-bound passes that could have been fused;
- choosing a fixed width wider than the target and forcing spills or
  scalarization.

The preferred shape is still one ordinary function containing a complete bulk
operation. The difference from `@native` is that the compiler discovers and
reports that unit rather than making it part of the program's validity.

Performance diagnostics must be factual. Report an observed box, fallback,
unsupported operation, native transition, or scalarized instruction. Do not
warn merely because a function is small or a branch looks unpredictable.

## Delivery

### V0: Semantic and mechanism spike

Build a test-only surface for `float` vectors with one fixed 128-bit species.
Implement its scalar cdata fallback and lower one complete span loop through a
minimal vector IR to the existing ARM64 spike machinery. Add an x86-64 SSE
version if an x86 runner is available; do not infer its result from ARM64.

The spike must answer:

1. Can the compiler recognize a chain of ordinary vector operations without
   using replaceable names or per-operation FFI calls?
2. Can one generated wrapper project spans, call one native body, and reproduce
   the fallback's errors and tail behavior?
3. Can vector arguments remain in registers across at least ten dependent
   operations without accidental boxes?
4. Can a vector value escape, run through the fallback, and re-enter a later
   native function with identical lanes and bits?
5. Can a failed native compilation select the fallback without changing an
   error, borrow lifetime, or visible call count?

Use the existing integrate workload plus arithmetic-heavy, branch/mask-heavy,
short-input, and deliberately boxing cases. Retain counts zero through at least
twice the widest tested lane count so every tail executes.

#### V0 exit criteria

- Differential tests pass for ordinary values, NaNs, infinities, both zeros,
  integer boundaries once admitted, every mask, and every tail length.
- Optimized execution makes exactly one Lua/native transition for a complete
  loop and no allocation per iteration.
- Decoded native output contains the expected vector loads, arithmetic, and
  stores and no scalar call per lane.
- The fallback works with JIT disabled and native compilation forced off.
- The experiment records compile time, code size, warm-call cost, and boxing
  cost rather than only steady-state throughput.

Nothing public lands if V0 cannot meet these criteria.

### V1: Public fallback semantics

Add `nupp.simd` with sealed `Species<T>`, `Vector<T>`, and `Mask<T>`, preferred
and fixed-128 species, the initial operation set, and complete scalar
semantics. Keep native compilation experimental behind a build flag during
this slice.

Implement checker-owned intrinsic identity, vector operators, species
provenance, span borrow rules, documentation, reference generation, formatting,
reflection, LSP, module summaries, incremental invalidation, and stable
diagnostics. The private cdata layout is versioned runtime detail.

#### V1 exit criteria

- Every public operation has a target-independent scalar definition and
  differential corpus.
- Vectors work in locals, parameters, results, tables, generics, module
  exports, `any`, and with the JIT disabled.
- Loads and stores cannot bypass span bounds, offsets, constness, exclusivity,
  or ownership.
- Preferred species is process-stable and never enters a public type
  fingerprint.
- There is no public pointer, mutable lane storage, finalizer, or observable
  box identity.

### V2: Whole-function native compilation

Lower eligible complete functions to validated vector IR. Add scalar-native,
NEON 128, and SSE2 128 backends; CPU dispatch; one-call wrappers; status-based
errors; code caching; source maps; and inspection commands.

Extend DynASM ARM64 with only the instruction families V2 admits. Verify every
encoding against Clang or another independent assembler and execute randomized
instruction tests. Use the existing DynASM x86 vocabulary where it is complete,
but apply the same independent checks.

#### V2 exit criteria

- A supported function reliably selects native SIMD on AArch64 and x86-64;
  forcing scalar-native and Lua fallback preserves every answer.
- Unsupported functions explain one stable decline reason and run through Lua.
- Native bodies make no Lua API calls, allocate no Lua or native heap object,
  retain no span pointer after return, and unwind no exception through FFI.
- Concurrent workers compile, call, invalidate, and retire code without sharing
  Lua-owned values or executing freed memory.
- Hardened Apple execution either follows the platform JIT policy or clearly
  selects fallback; it never weakens W^X silently.

### V3: Preferred widths and specialization

Add AVX2 256, independent FMA dispatch, and per-species specialization. The
same public `Vector<float>` source runs at the selected width. Add explicit
fixed-width vectors only after preferred vectors prove that their erased width
does not damage checking or tooling.

Native helper calls specialize transitively under bounded code growth. Cache
keys include CPU features and numeric semantics. Cross-module summaries expose
enough semantic IR to compile a caller without making every implementation
edit invalidate unrelated dependants.

#### V3 exit criteria

- One portable artifact selects SSE2 or AVX2 correctly on different x86-64
  hosts and NEON on AArch64 without changing type identity.
- Feature forcing can select only executable lower tiers; OS state is checked
  before AVX use.
- Preferred-width loops preserve tails and errors at every supported width.
- The AVX2 version clears upper state at required boundaries and instruction
  inspection verifies it.
- Specialization has explicit per-function and process cache limits.

### V4: Mixed-function outlining

Outline eligible vector loops from otherwise ordinary functions. Box live
vectors at region boundaries and preserve Lua prefix/suffix evaluation order.
Admit a construct only after its error, ownership, cleanup, suspension, and hot
reload behavior is proved.

Do not build general deoptimization in this phase. A region either enters with
all guards satisfied and returns normally or reports one modeled status. Any
operation needing arbitrary Lua execution stays outside it.

#### V4 exit criteria

- Outlining preserves source-visible call order and error sites across a corpus
  containing Lua work before and after the vector loop.
- Every live owner and borrow has the same lexical end in fallback and outlined
  execution.
- An outlined region makes one native transition, and inspection names every
  box at its boundary.
- When proof is incomplete the whole source uses fallback; no speculative
  outline changes behavior.

### V5: Operation growth

Consider gathers, scatters, richer permutations, compress/expand, saturating
arithmetic, half-width types, vector math, SVE, and AVX-512 one at a time. Each
addition requires:

- one portable scalar definition;
- target support or an explicit scalarization rule;
- differential and encoding tests;
- a workload showing why the operation belongs in the public surface;
- inspection that says when it scalarized;
- an updated numeric-semantics section where results can differ.

## Verification matrix

Every landed slice runs focused compiler, generation, standard-library,
ownership, span, C-interop, module-summary, incremental, formatter, LSP,
documentation, worker, hot-reload, and host tests as applicable; then the full
suite. Compiler changes run `./bin/nupp fixpoint` and require a byte-identical
second build.

Native differential tests cover:

- Lua fallback, scalar-native, and every executable SIMD tier;
- JIT on and off;
- optimization levels zero and one;
- zero, shorter-than-width, exact-width, multiple-width, and tail counts;
- aligned and deliberately unaligned valid addresses;
- sliced spans with nonzero offsets and sibling writable partitions;
- all mask bit patterns for the first width;
- NaNs, infinities, signed zeros, subnormals, integer extrema, and overflow;
- errors at the first and last invalid lane;
- boxing through locals, calls, returns, tables, and `any`;
- module reload, worker concurrency, code-cache pressure, and forced native
  allocation failure.

Fuzz vector IR before emission and validate generated instruction streams in a
separate decoder where practical. A native crash is a compiler defect, never an
accepted consequence of an unsupported source operation.

## Performance gates

Use paired, alternating measurements with warmups and enough repetitions per
sample to dominate timer noise. Report medians and distributions for:

- the existing integrate workload at 262,144 and 1,048,576 rows;
- an arithmetic-heavy chain that remains register-resident;
- a mask-heavy filter without allocation;
- short counts from zero through twice the maximum lanes;
- one deliberate vector escape and re-entry;
- one function declined to fallback;
- cold native compilation and warm cache lookup.

Before making native lowering the default:

- complete-loop SIMD must be within 1.10x of equivalent optimized C/Clang on
  both supported architectures and no slower than the existing hand-emitted
  spike outside measurement noise;
- a warm generated wrapper must be within 1.05x of a handwritten one-call FFI
  wrapper on the existing large workloads;
- there must be zero per-iteration allocation and one native transition;
- disabled native compilation must impose no measurable regression on code
  that does not import or use `nupp.simd`;
- cold compilation time and code-cache growth must have explicit budgets set
  from V0 measurements rather than invented in advance.

The fallback is not expected to beat a scalar LuaJIT loop. Its gate is
correctness and bounded allocation. Tooling must prevent its accidental use
from masquerading as successful SIMD.

## Decision gate against explicit-only `@native`

Run one implementation spike, one public-API review, and the performance matrix
before selecting a language direction. Prefer portable vectors when all of the
following hold:

- the ordinary fallback makes vector values genuinely usable outside native
  regions rather than nominally legal but operationally incomplete;
- full-function inference is predictable on representative code and decline
  reasons are understandable;
- boxing and outlining rules preserve existing errors, ownership, and hot
  reload without general deoptimization;
- generated SIMD meets the same one-call and throughput gates as an explicit
  native function;
- preferred species stays out of public type identity and module fingerprints;
- implementation cost is concentrated in reusable IR/backend work rather than
  a growing imitation of LuaJIT.

Prefer explicit-only `@native` when any of these instead proves true:

- reliable performance needs restrictions that are surprising in an ordinary
  function but clear at an annotated boundary;
- common vector programs fall back or box without an obvious source-level
  reason;
- preserving arbitrary Lua semantics around inferred regions requires
  deoptimization machinery comparable to changing LuaJIT;
- the scalar fallback is too allocation-heavy to be an honest general API;
- species-erased values make diagnostics, generics, or cross-module calls
  materially worse than fixed native-local vectors;
- explicit native functions fuse work or control code size substantially better.

Do not decide from the existing NEON result alone. It proves that one generated
native loop can match Clang, not that transparent native-region discovery,
boxing, fallback, and portable species can carry the Java-like language model.

If portable vectors win, `@native` remains a checked performance contract: it
requires compilation and turns a transparent-lowering decline into a
diagnostic, but does not enable syntax, change results, grant relaxed
arithmetic, or create another sublanguage.

If explicit-only `@native` wins, retain the scalar vector model only if it is
independently useful; otherwise keep vector values native-local and say so
plainly. Do not ship two almost-identical APIs whose difference is whether an
optimizer happened to see them.
