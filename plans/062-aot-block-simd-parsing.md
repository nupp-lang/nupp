# AOT block kernels, scoped SIMD, and native JSON parsing

Status: implemented — native AVX2 performance verification remains a release gate

## Decision

Land this work as one plan with independent, reviewable stages:

1. generalize `@aot` from map-shaped span loops into useful block kernels;
2. expose a small, non-escaping SIMD vocabulary only inside `@aot`;
3. use it to build a structural JSON tape and validate UTF-8 by blocks;
4. parse that tape into caller-owned native arenas before materializing Lua
   values;
5. add further SIMD operations only when profiles of that parser require them.

Do not land a broad SIMD library first, and do not combine every stage into one
patch. The JSON implementation is the acceptance workload for the new
capabilities, but it remains entirely under `bench/simd-json`. Deleting that
directory must remove the experiment without removing or invalidating any
compiler feature.

This reopens only the deliberately deferred case in the portable-vector
decision record: algorithms whose register is a data structure and whose
meaning depends on cross-lane masks. It does not revive boxed vector values,
ordinary-Lua fallback values, inferred AOT outlining, fixed architecture widths
in source, or a second spelling for scalar map loops.

That choice has one deliberate build-policy consequence. A function that uses
explicit SIMD is not executable under `aot=off`; that build reports a dedicated
diagnostic. `aot=require` produces the runnable wrapper and `aot=emit-c`
produces the vendor-build input. All other `@aot` functions retain today's
dormant ordinary-body behavior under `aot=off`. Do not hide this exception: it
is the cost of having non-boxed values with no Lua runtime representation.

Ordinary parsing, name resolution, and type checking still run under
`aot=off`. The resolved identity of an explicit-SIMD intrinsic is therefore
enough to report this policy diagnostic. Doing so does not run AOT eligibility,
construct AOT IR, inspect a target backend, or otherwise weaken
`038-aot-functions.md`'s rule that the AOT subset checker is off under that
policy.

## Required outcome

An AOT function can safely process target-width byte blocks, carry scalar state
between them, extract lane masks, and write variable amounts of output into
bounded spans. The compiler selects packed 16-byte baseline x86-64 and AArch64
NEON blocks and 32-byte AVX2 blocks when that tier is built. A forced-scalar
implementation defines the exact result of every operation.

The JSON experiment uses those facilities to:

- identify structural characters and string boundaries without producing one
  classification byte per source byte;
- validate UTF-8 in the same block pass, including state across blocks;
- parse strings, numbers, literals, arrays, and objects in native code into
  bounded caller-owned storage;
- return a root node or a source-attributed capacity or syntax failure;
- materialize ordinary Lua values only after parsing is complete; and
- report structural indexing, native parsing, Lua materialization, and
  end-to-end performance separately against the current experiment and
  `lua-cjson`.

The project may stop after any stage whose measurements fail its gate. Earlier
AOT improvements remain supported and useful to codecs, checksums, binary
formats, text search, and image kernels.

## Why the current decoder is slow

The current `bench/simd-json` classifier crosses the native boundary once and
classifies JSON syntax and UTF-8 lead classes together. Its gang nevertheless
carries each byte in a 32-bit lane, so it examines only four bytes at baseline
x86-64 and eight at AVX2 or in the current two-register NEON gang.

More importantly, classification is a small share of the decoder. The parser
then returns to Lua and:

- reads one classification byte and often one source byte for each input byte;
- recursively calls through arrays and objects;
- allocates result tables, temporary string-part tables, and substrings while
  syntax is still being recognized;
- validates UTF-8 through scalar per-byte state;
- uses `source:sub` and `tonumber` to convert numbers; and
- repeatedly performs dynamic table and string operations that are outside the
  admitted AOT subset.

There is not yet a committed benchmark report establishing a stable decoder to
`lua-cjson` ratio or a stable classifier share. Preliminary runs agree only on
the direction: recursive Lua parsing dominates, and the ratios move materially
with JIT warmup and machine state. J0 records the reproducible baseline before
this plan uses a number as a gate. The source structure is already enough to
show that making the existing classifier wider cannot remove recursive parsing,
substring conversion, or allocation. Moving parsing, not merely more
classification, through one native boundary is the purpose of this plan.

## Relationship to existing plans

`037-portable-vectors.md` remains the governing decision for ordinary code.
Scalar-source lane lowering is still the preferred expression of independent
map work. Public boxed vectors and vector values that escape into Lua remain
rejected.

This plan revises its narrower conclusion that explicit AOT-only vectors should
not land. JSON indexing supplies the missing independently compelling workload:
quote parity, escape carry, structural masks, UTF-8 continuation masks, and
set-bit enumeration cannot be written as independent scalar iterations. The
revision is limited to verified values whose lifetime is wholly inside an AOT
call.

`038-aot-functions.md` continues to own the whole-function compilation
contract, AOT IR safety boundary, generated-C backend, wrappers, artifacts, and
target tiers. This plan widens its admitted source and IR; it does not add
another native compiler.

`041-aot-independent-foundations.md` remains complete. This plan consumes its
fixed-width arithmetic, checked spans, target layouts, and effect facts. It
does not retrofit SIMD into those ordinary-language foundations.

`059-multiversioning.md` remains optional. A single-tier build resolves the
preferred species for that tier at build time. A multiversioned build compiles
the same source separately for each carried tier and binds the selected symbol
at load, so vector width never becomes a runtime branch inside a kernel.

## Current AOT baseline

The implemented lane path is intentionally map-shaped:

- an AOT entry returns `nil`;
- readable and writable spans have matching counts;
- guards precede exactly one top-level numeric loop;
- a span access uses the active loop index exactly;
- mutable lane state is local to one map iteration; and
- admitted helper calls are small, statically resolved, and pure.

Its private lane IR already represents elementwise arithmetic, comparisons,
masks, masked selection, consecutive narrow span loads and stores, and divergent
per-lane control flow. It does not expose vectors or masks to source and does
not provide cross-lane shift, mask extraction, compression, permutation, or
reductions.

That shape is correct for transforming one input row into one output row. It
cannot express a parser that consumes an independently sized input, appends a
variable number of structural offsets or nodes, carries quote and UTF-8 state
between blocks, or returns counts and status.

## Public source model

### AOT-only values

Add `nupp.simd` as a compiler-owned module whose vector-producing operations
are legal only while checking a visible `@aot` body or a statically resolved
AOT helper:

```nupp
local simd = require("nupp.simd")

@aot
local function index(
    borrows source: span.Span<uint8>,
    exclusive tape: span.WriteSpan<uint32>
): (uint32, uint32, uint32)
    local bytes = simd.preferred<uint8>()
    -- block loop omitted
    return written, errorCode, errorByte
end
```

The initial vocabulary contains three conceptual types:

- `Species<T>`: a compile-time-selected operation set and lane count for the
  artifact tier;
- `Vector<T>`: one immutable packed vector value; and
- `Mask<T>`: one immutable predicate bit per vector lane.

These are compiler-known types rather than reified LuaJIT ctypes. Source may
bind, copy, compare, combine, and pass them to statically resolved AOT helpers.
It may not return them through a Lua-callable wrapper, store them in tables,
records, ordinary structs, spans, `any`, or `unknown`, capture them, retain them
after the call, or pass them to an unknown function.

There is no boxed representation, C ABI promise, metamethod implementation, or
one-FFI-call-per-operation fallback. Removing `@aot` from a function that uses
these values is a checking error. This is acceptable because the surface names
an operation available only within the already explicit compilation boundary;
it does not change the ordinary meaning of an existing scalar body.

This is a narrow exception to `038-aot-functions.md`'s rule that disabling AOT
changes only performance and artifacts. The exception is attached to resolved
explicit-SIMD intrinsic identities, not to `@aot` in general. Importing the
module without using those identities changes nothing. Inspection and build
diagnostics must name the exact operation that makes `aot=off` unavailable.

Before J2 lands, review this exception as a language decision. If preserving a
runnable `aot=off` body is non-negotiable, stop after J1. Do not solve it by
quietly adding boxed vectors or one foreign call per vector operation; a future
proposal would instead need a complete scalar ordinary lowering and its own
cost and width semantics.

### Width and target selection

Source requests a preferred species by lane element type, never `U8x16`,
`U8x32`, SSE, AVX, or NEON. For the first byte surface:

- x86-64 baseline selects 16 packed `uint8` lanes;
- x86-64 AVX2 selects 32 packed `uint8` lanes; and
- AArch64 NEON selects 16 packed `uint8` lanes.

The exact width is a property of the compiled tier and appears in inspection
output and artifact keys. A source constant may use `species.lanes` to advance
a block loop, but vector width does not enter nominal type identity or a public
ABI.

The existing scalar-source lane lowering may continue to use wider internal
gangs composed of multiple registers where profitable. Explicit species model
one target register in the first release because cross-register shuffles and
mask ordering would otherwise become part of the API before a workload needs
them.

### Initial operations

Ship only the operations exercised by the structural indexer and its semantic
tests:

- `simd.preferred<uint8>()` and a compile-time lane count;
- full and masked-tail unaligned loads from `Span<uint8>`;
- equality and unsigned range comparison;
- vector and mask `and`, `or`, `xor`, and `not`;
- masked selection;
- mask `any`, `all`, `count`, and `bits`;
- scalar `u32` population count, count-trailing-zeros, and count-leading-zeros;
  and
- explicit construction of a valid-tail mask.

`mask:bits()` returns a `uint32` whose bit zero is the first logical lane. Bits
for inactive tail lanes are always zero. Counting zeros on zero needs a stated
result or a checked precondition; the structural loop normally calls it only
after `bits ~= 0`.

All names are semantic and portable. The surface exposes neither an instruction
mnemonic nor a guarantee that one source operation becomes exactly one machine
instruction.

### Tail and memory rules

A full load requires the complete vector range to lie inside the source span.
A tail load receives or derives a mask from the remaining element count and may
read only active elements. Generated code must never perform a convenient
overread, including when the final byte is next to an unmapped page.

Vectors contain values, not memory views. Span ownership, offset, count,
mutability, and region identity remain the only memory authority. A vector
operation cannot create a pointer, strengthen aliasing facts, or bypass a span
check.

### Scalar oracle

Every operation has a compiler-owned forced-scalar lowering with the same lane
order, integer width, tail behavior, and failure behavior. It is not a public
Lua vector implementation. It exists so all tiers can be differentially tested
and so `nupp aot` inspection can distinguish semantic correctness from a target
code-generation failure.

The scalar oracle uses fixed-size AOT IR values or scalar lanes, performs no
allocation, and never calls through Lua per lane.

## General AOT block-kernel foundations

Land these before or with the first SIMD consumer. None is JSON-specific.

### General structured control flow

Admit ordinary block loops whose trip count is derived from input length,
including a final partial block. Permit mutable scalar state, phis, nested
conditionals, bounded inner loops, `break`, `continue`, and early status returns
under the existing AOT IR verifier.

Do not require a single map loop or equal span counts for bare `@aot`. Keep the
existing independence proof and lane transform as an optimization for loops
that retain the map shape.

### Bounds-proven dynamic span access

Admit dynamic indices and bounded ranges when dominance proves them inside the
span, rather than requiring the active loop index exactly. A block load records
its first logical index, access width, valid-lane mask, source site, and region.
Scalar string, number, and tape parsing uses the same bounds facts.

No unchecked pointer arithmetic enters source or AOT IR. If a range proof is
not available, emit the existing modeled check or decline the body.

### Variable-rate bounded output

Support an append cursor over a writable span: an ordinary mutable `uint32`
count plus proved `count < output.count` before each write. A dedicated public
`AppendSpan` is not required initially; add one only if ordinary non-AOT uses
justify its ownership and failure surface.

The optimizer may recognize this checked pattern and remove redundant bounds
work. It must preserve the first failing source position and must not assume
that input and output counts match.

### Results and helper state

Admit fixed-width scalar and small multiple results at the top-level AOT
wrapper, not only `nil`. The private ABI returns results through explicit slots
and translates no native exception through FFI.

The JSON stages need at least a written count, error/status code, and one-based
error byte. A direct AOT helper may additionally return updated block carry
state without crossing through Lua.

### Physical binary64 and arena structs

Admit reified arena structs containing `number` as a physical IEEE-754
binary64 field under the existing numeric contract. The parser needs to store a
parsed number without turning it into a string or a Lua object. Generated C
must use the canonical target layout and may not contract or apply fast-math.

Admit fixed-width tagged node and stack-frame structs, their checked span
loads/stores, and statically resolved stateful AOT helpers. No field may contain
a Lua reference, owned value, pointer-shaped escape, or cleanup obligation.

## Structural indexing

The first explicit-SIMD consumer reads one byte vector per iteration and forms
masks for quotes, backslashes, braces, brackets, colon, comma, whitespace,
control bytes, UTF-8 continuation bytes, and UTF-8 lead classes.

It then performs ordinary `uint32` bitset work:

- quote state uses unescaped-quote prefix parity carried across blocks;
- backslash runs carry their odd/even escape state across a block boundary;
- syntax under an active string mask is removed;
- structural positions are enumerated with trailing-zero count and
  `bits = bits & (bits - 1)`; and
- offsets are appended to a caller-owned `WriteSpan<uint32>`.

The tape stores source offsets for structurals and string boundaries, plus only
the compact metadata the parser demonstrably needs. It does not store one byte
of flags per input byte. Capacity failure reports how much output was available
and the source position being processed; it never reallocates internally.

Quote prefix parity can initially be implemented as specified scalar bitset
arithmetic over `mask:bits()`. Add a semantic `prefixParity` operation only if
the generated code or profile shows that this is material and both target
families have sound lowerings.

## SIMD UTF-8 validation

UTF-8 validation remains fused with structural indexing, but validation now
operates on whole masks rather than recording a class for the scalar decoder.
For each block it derives masks for continuation bytes and two-, three-, and
four-byte leads, shifts the required-continuation masks into their expected
positions, and carries up to three expected continuation bits across the block
boundary.

Separate comparisons enforce the non-regular boundary rules:

- `E0` requires the next byte to be at least `A0`;
- `ED` requires the next byte to be at most `9F`;
- `F0` requires the next byte to be at least `90`; and
- `F4` requires the next byte to be at most `8F`.

It also rejects `C0`, `C1`, bytes above `F4`, unexpected continuations, missing
continuations, and an incomplete sequence at end of input. The first invalid
byte must match the scalar oracle. Inputs with invalid bytes outside strings
remain invalid JSON; validation is not conditional on quote state.

This algorithm needs lane masks, bit shifts, and block carry. It does not by
itself justify arbitrary byte permutation, table lookup, or compression.

## Native arena parser

### Representation

The parser receives the source bytes, structural tape, and caller-owned writable
spans for at least:

- nodes;
- child or member indices;
- decoded string bytes; and
- an explicit container stack.

A node is a tagged reified struct. Its payload holds a boolean, binary64 number,
source string slice, decoded-string arena slice, or child range. Object members
refer to key and value nodes or to a compact member record. Exact field packing
is selected after a target-layout fixture proves it on x86-64 and AArch64; the
public Nupp declaration, generated C, and Lua materializer consume the same
canonical layout.

Strings without escapes refer to an offset and length in the retained source.
Strings with escapes are decoded once into the caller-owned byte arena. The
native arena contains no Lua string, table, function, userdata, or GC pointer.

### Parsing model

Use an iterative parser with an explicit bounded stack. It consumes structural
positions for coarse navigation and consults source bytes for literals, string
contents, escapes, and numbers. It implements the full existing experiment's
grammar, including surrogate pairs and stable rejection positions.

Parse numbers directly into binary64 without allocating a substring or calling
Lua `tonumber`. The conversion algorithm needs a separately tested exactness
contract for accepted decimal syntax, overflow, underflow, signed zero, and
rounding. Reuse a small proven implementation if its license and semantics fit;
otherwise implement against a generated oracle corpus before optimizing it.

All capacity is explicit. The parser does not guess and reallocate inside AOT.
The Lua wrapper may size buffers from input length for the experiment or retry
after a capacity result. A result distinguishes syntax, UTF-8, nesting, node,
member, string, and tape-capacity failures and carries the relevant source byte
or required capacity.

### Lua materialization

Keep materialization in ordinary Nupp/Lua for the first version. It traverses
validated nodes, creates tables and strings, and maps the null tag to
`json.null`. Benchmark this phase separately because it may become the dominant
remaining cost.

Do not initially call the Lua C API from generated AOT code. That would couple
the AOT backend to LuaJIT stack discipline, allocation failure, longjmp,
barriers, and rooting, and would erase the clean no-Lua-pointer safety boundary.
If materialization dominates after native parsing lands, make the next choice
from measured alternatives: lazy arena-backed values, schema-specific decoding,
or a separately designed checked Lua API bridge.

## Deferred SIMD vocabulary

Do not preemptively expose the broader API described and rejected in
`037-portable-vectors.md`. The following operations remain absent until a
profile points to a named source location and a portable semantic operation:

- byte shuffle or table lookup;
- lane alignment across adjacent blocks;
- prefix parity as a primitive;
- compress-store or vector-to-packed-index conversion;
- arbitrary permutation;
- widening, narrowing, and saturating conversion; and
- horizontal numeric reductions beyond mask counts.

AVX2 and NEON do not share one simple general compress instruction. Enumerating
set bits may be faster and is substantially easier to specify. A later operation
lands only with a scalar oracle, both target lowerings or an accepted target
fallback, generated-code inspection, and a measured improvement in the JSON
indexer or another committed workload.

## Performance gates

J0 commits the benchmark inputs, raw samples, platform and toolchain identity,
warmup count, and summary used by every later comparison. Use alternating
paired measurements, at least four warmups and fifteen measured samples, and
batches long enough to dominate timer resolution. Report medians, geometric
means across payload families, paired ratios, and a 95 percent confidence
interval. A result clears a threshold only when the confidence interval clears
it, not when a single median does.

The following are the default minimums. J0 may tighten them before
implementation begins if the recorded noise floor or baseline makes a stronger
gate reasonable. Weakening one after J0 requires an explicit plan amendment
rather than an interpretation of “materially.”

- **J2 structural indexing:** at least 1.5 times the current fused byte
  classifier's throughput on the large-payload geometric mean on native AVX2
  and NEON, while performing structural tape construction and full UTF-8
  validation. End-to-end decoding may regress by no more than five percent on
  any committed payload family.
- **J3 native parsing:** at least 2.0 times the current decoder's end-to-end
  throughput on the large-payload geometric mean and at least 1.25 times on
  every large committed family, on both native architecture families. Median
  latency for short request-sized documents may regress by no more than ten
  percent.
- **J4 operation growth:** each additional public SIMD operation must improve
  its affected stage by at least ten percent and end-to-end throughput by at
  least five percent on a named committed payload family. It may regress no
  other family or optimized target tier by more than two percent.

Keep `lua-cjson` in every report as the external reference, but do not turn its
current result into a safety exception or an undocumented moving gate. Passing
J3 is enough to retain JSON as a compiler acceptance workload. Proposing a
public JSON library remains a separate decision with thresholds written from
the completed component measurements.

## Delivery stages

### J0 — Freeze the baseline and semantic corpus

- Record the current classifier, decoder, and `lua-cjson` results with platform,
  compiler, target tier, payload hash, payload size, and sample distribution.
- Split measurements into classification, recursive Lua parsing, and
  end-to-end decode without changing the current implementation.
- Expand valid and invalid corpora for every UTF-8 boundary, escape, number,
  nesting, and truncation case before changing the parser.
- Add guarded-page fixtures for final vector loads and exact-capacity fixtures
  for every output arena.

Gate: the current behavior is reproducible, failures report stable byte
positions, the benchmark report is committed, and the confidence intervals are
narrow enough to distinguish every numeric threshold above.

### J1 — General AOT block kernels

- Generalize returns, structured loops, scalar carry, dynamic bounds-proven
  span access, independently sized spans, append cursors, and physical
  binary64 arena fields.
- Extend AOT IR, verification, versioning, inspection, generated C, wrappers,
  source maps, resource limits, and differential tests together.
- Add non-JSON fixtures such as delimiter indexing and bounded byte copying so
  every compiler feature has an independent consumer.

Gate: scalar AOT block kernels pass on x86-64 and AArch64, perform one native
call, allocate nothing internally, reject every unproved access, and remain
useful with `bench/simd-json` deleted.

### J2 — Minimal scoped SIMD and structural indexer

- Ratify and document the explicit-SIMD `aot=off` exception before adding a
  public intrinsic identity.
- Add the AOT-only types and initial operations above with a forced-scalar
  oracle.
- Lower packed byte vectors and mask extraction for baseline x86-64, AVX2, and
  NEON; inspect emitted C and final instructions.
- Replace the byte-flag classifier with a structural tape and fused SIMD UTF-8
  validator in `bench/simd-json`.
- Update `037-portable-vectors.md` to record this narrow exception when the
  implementation passes its gate, not before.

Gate: every exposed operation is used by the committed indexer; all target
tiers agree with the scalar oracle for every tail and first-width mask pattern;
loads are packed bytes rather than widened 32-bit carriers; and the indexer
clears the J2 performance gate. If it does not, keep J1 and remove the SIMD
surface and new indexer.

Implementation result (2026-08-17): the AArch64 NEON large-payload geometric
mean is 1.591x the fused byte classifier with a paired bootstrap 95 percent
interval of 1.550x to 1.673x. The indexer also constructs the compact tape and
validates UTF-8. Native AVX2 timing remains a release/CI gate on an x86-64 host;
cross-target C and IR inspection alone do not claim that half of the gate.

### J3 — Native structural parser and arenas

- Define target-validated node, member, and frame layouts.
- Implement iterative grammar, strings, escapes, UTF-8 result propagation,
  literals, exact number conversion, capacity status, and nesting limits in
  AOT helpers.
- Keep arena allocation and final value materialization in the Lua wrapper.
- Replace the recursive Lua parser only inside the detachable experiment.

Gate: native parsing eliminates byte-at-a-time Lua work, agrees with the oracle
corpus and differential fuzzer, and clears the J3 performance gate. Report
materialization separately even if it becomes the largest component.

Implementation result (2026-08-17): the AArch64 NEON large-payload geometric
mean is 2.127x the retained decoder with a paired bootstrap 95 percent interval
of 2.101x to 2.146x. Every large family clears 1.25x; the lowest interval is
1.407x for escaped strings. The short-document adaptive path retains 0.987x
throughput with a 0.964x lower bound. The 1,024-check suite includes direct arena
decoding, bit-identical numeric comparisons, one-short node/link/frame arenas,
and deterministic generated and mutated documents. Native AVX2 timing remains
a release/CI gate on an x86-64 host.

### J4 — Profile-driven SIMD extensions

- Profile J3 with representative payload families.
- Add at most the semantic operations that remove measured indexer or UTF-8
  bottlenecks.
- Repeat target parity, scalar differential, instruction inspection, and API
  review for each addition.

Gate: no operation lands solely because one architecture has an attractive
instruction. Each must clear the J4 performance gate on every target where it
claims an optimized lowering.

Implementation result (2026-08-17): no additional SIMD operation landed. The
component report puts escaped-string cost in Lua materialization and numeric
cost in scalar grammar/conversion; neither identifies a portable vector
operation that clears the J4 end-to-end gate.

### J5 — Decide the experiment

Compare the finished experiment with `lua-cjson` on correctness, parse-only and
end-to-end throughput, short-input overhead, memory overhead, artifact size,
and build latency. Then choose one explicit outcome:

- retain it as a benchmark and compiler acceptance workload;
- propose a separately reviewed public JSON library;
- retain only the native arena/index APIs for other consumers; or
- delete `bench/simd-json` while keeping the compiler capabilities that passed
  their own gates.

No public `nupp.json` replacement is implied by this plan.

Decision (2026-08-17): retain the detachable JSON implementation as a benchmark
and compiler acceptance workload. Do not propose it as `nupp.json`; `lua-cjson`
remains substantially faster on several families, and the experiment's purpose
is to validate useful AOT and scoped-SIMD machinery rather than acquire a public
JSON compatibility commitment.

## Verification matrix

Compiler verification covers checker, lowering, AOT IR construction and
verification, serialization versioning, generated C, wrapper ABI, target
layout, cache keys, inspection, formatter, LSP hover and diagnostics,
incremental rebuilds, and documentation. Every compiler stage runs focused
tests, `./bin/nupp test`, and `./bin/nupp fixpoint` before integration.

SIMD differential tests cover:

- forced scalar, x86-64 baseline, x86-64 AVX2, and AArch64 NEON;
- zero bytes, one byte, exact width, every tail length, and multiple blocks;
- aligned, unaligned, sliced, and guarded-page-ending inputs;
- every mask pattern for the first supported width and randomized patterns
  thereafter;
- quote and escape runs crossing every block boundary; and
- UTF-8 sequences and invalidity crossing every block boundary.

JSON verification covers:

- the existing valid and invalid corpus against the retained Lua implementation
  and `lua-cjson` where their documented semantics agree;
- generated valid documents and mutation-based invalid documents;
- every string escape and surrogate boundary;
- decimal halfway, exponent, overflow, underflow, and signed-zero cases;
- empty, shallow, deeply nested, and nesting-limit documents;
- exact and one-short capacity for each arena;
- first-error byte stability; and
- memory-sanitizer and undefined-behavior-sanitizer runs of generated native
  fixtures where supported.

Generated-code checks require packed loads, target-width comparisons, compact
mask extraction, no per-lane function calls, no tail overread, and no
architecture tier instruction in a baseline artifact. Performance tests use
alternating paired runs, warmups, enough samples to bound variance, and payloads
covering ASCII strings, Unicode strings, escaped strings, numeric arrays, flat
objects, nested values, and short request-sized documents.

## Inspection and diagnostics

`nupp aot` inspection must show:

- the resolved species width and target tier;
- whether each vector operation used a target lowering or forced-scalar form;
- full versus tail loads and the bounds fact authorizing them;
- mask extraction and cross-block carry state;
- output capacity checks and modeled status exits; and
- the first unsupported AOT or SIMD construct with its source position.

Diagnostics distinguish an illegal escape, unsupported element type,
unavailable target lowering, unsafe tail load, unproved dynamic span access,
output-capacity path, and ordinary construct outside the AOT subset. They do not
suggest adding `@aot` to arbitrary code merely to make vector syntax legal.

## Risks and controls

**API fossilization.** The first JSON algorithm could accidentally define a
general SIMD library. Keep the surface AOT-only, semantic, non-escaping, and
limited to operations exercised by committed code. Defer all convenience APIs.

**Target-shaped semantics.** AVX2 and NEON have different mask and permutation
facilities. Specify logical lane order and scalar behavior first, then lower
each target. Decline an operation whose behavior cannot be made identical.

**Unsafe tails or arenas.** Wide overreads and cursor mistakes can turn checked
source into native memory corruption. Carry bounds, masks, regions, and
capacities through verified IR; exercise guard pages and sanitizers.

**Compiler complexity.** General control flow, phis, results, and stateful
helpers broaden more of AOT than vectors do. Land them separately with
non-JSON fixtures, explicit IR limits, and fixpoint verification.

**Materialization ceiling.** A fully native parser may still lose to
`lua-cjson` while Lua constructs the same tables and strings. Measure the phase
and report the ceiling; do not smuggle Lua C API calls into this plan.

**Benchmark overfitting.** One synthetic 0.14 MB document does not represent
JSON use. Keep a versioned payload corpus, record short-input overhead, and
require improvements across distinct content families and both architecture
families.

**Artifact growth.** Packed SIMD helpers and optional target tiers increase
generated code. Reuse one module translation unit and existing tier artifact
keys; measure code size and cold compilation separately from throughput.

## Completion criteria

This plan is complete when:

- general block kernels, bounded variable-rate output, scalar results, and
  arena structs are supported independently of JSON;
- the scoped SIMD API has exact scalar semantics, verified non-escape rules,
  packed target lowerings, inspection, and cross-target differential tests;
- the JSON experiment indexes and validates by blocks, parses into native
  caller-owned arenas, and materializes from those arenas;
- correctness, error positions, tail safety, capacity behavior, component
  timings, memory cost, artifact cost, and end-to-end performance are recorded;
- the portable-vector decision record reflects the implemented narrow AOT-only
  exception while continuing to reject ordinary boxed vectors; and
- deleting `bench/simd-json` leaves a coherent, documented, tested set of AOT
  capabilities with at least one non-JSON fixture for each.

Completion does not require making JSON a standard library, exposing a full
portable-vector API, adding the Lua C API to AOT, or beating `lua-cjson` at any
cost. A failed JSON experiment is an acceptable result when its measurements
are recorded and every retained compiler feature passed an independent gate.
