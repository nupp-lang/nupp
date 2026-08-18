# Lua-value construction in AOT functions

Status: V1a, the core V2 subset, the V4 tree recipe, and V5 stream fusion implemented;
V1b, general `nupp.io` V3 strings, and V6 remain proposed — follows
`plans/038-aot-functions.md` and `plans/062-aot-block-simd-parsing.md`

The implemented slice selects and fingerprints the VM-aware ABI, emits one
digest-named registrar per generated translation unit, caches its closure table,
and verifies rooted construction of presized arrays, maps, nested fresh tables,
numbers, booleans, nil, string literals, and rooted string arguments. Dynamic
capacities and indexes are checked with source sites. A general pointer-free tree
recipe admits rooted source slices, validated backslash/Unicode transforms, presized
containers, and opaque rooted null replacements. A bounded stream builder now lets
iterative parsers consume rooted strings and construct final Lua values directly; the
detachable SIMD JSON decoder uses it without node/link/frame arenas or a second tree
walk. Pure kernels retain their existing FFI ABI. General `nupp.io` string lowering,
the full host matrix, and the final support decision remain open stages.

## Decision

Add a second, VM-aware calling convention to `@aot`. A function that only consumes
and produces native scalars, structs, and spans keeps the existing FFI kernel ABI. An
admitted function that constructs fresh Lua tables or strings lowers to a Lua C
function and builds its result through a verified Lua-construction IR.

Keep the source as ordinary Nupp. Do not expose `lua_State *`, raw `lua_*` calls, GC
pointers, stack indexes, or a second embedded language. The compiler recognizes a
small set of ordinary operations by resolved identity and proves that every
Lua-managed value is created, rooted, populated, and returned safely.

The initial source subset includes:

- primitive nil, boolean, number, integer, and string values;
- fresh table literals and resolved `table.new(arrayCapacity, hashCapacity)` calls;
- raw-equivalent writes to fresh array and map tables;
- strings copied from proved ranges of rooted string or byte-span inputs;
- a checked lowering of a strictly local `nupp.io.Buffer`/`ScalarWriter` path for
  strings whose output differs from the input;
- structured control flow and pure AOT helpers already admitted by AOT; and
- returning the completed Lua value graph.

Do not make arbitrary table operations, metatables, dynamic calls, callbacks,
coroutines, userdata, or general Lua execution legal inside AOT. This is a checked
object-graph constructor, not a native implementation of the whole Lua VM.

Use the SIMD JSON experiment as the acceptance workload after independent fixtures
land. Its native parser should construct ordinary Lua values without returning node,
link, or frame arenas to a Lua materializer. The JSON directory remains detachable;
deleting it must leave a coherent value-construction facility useful to codecs,
database bindings, AST builders, generated bindings, and filesystem or protocol
scanners.

## Required outcome

The plan is complete only when all of the following are true:

- existing scalar, span, block, and SIMD AOT kernels retain their current private C
  ABI and no-Lua-pointer safety boundary;
- the compiler selects a separate Lua C-function ABI for an admitted value-building
  body and records that choice in inspection and artifact identity;
- one Lua call enters the native body and returns the completed ordinary Lua value;
- fresh arrays and objects are allocated with proved or authored array and hash
  capacities;
- every live table and intermediate string remains rooted across every allocating VM
  operation without relying on LuaJIT's current nonmoving collector;
- the backend uses public Lua 5.1-compatible C API operations rather than LuaJIT
  `GCtab`, `GCstr`, allocator, barrier, or stack internals;
- ordinary strings incur at most one required copy into Lua-owned storage after their
  final bytes are known;
- native source pointers remain valid because their owning Lua arguments stay rooted
  for the complete use interval;
- writes use correct VM barriers and cannot accidentally invoke a metatable;
- allocation failure, syntax failure, source errors, and capacity failure unwind or
  return without leaking native storage or exposing a partial result;
- `aot=off` runs the unchanged ordinary body with the same answers;
- `aot=require` either builds the complete VM-aware body or reports a source-local
  diagnostic, never silently returns to the Lua materializer;
- `aot=emit-c` emits deterministic vendor-build input with an explicit runtime ABI
  dependency;
- dynamically loaded, statically linked, embedded, worker, and hot-reload builds use
  the same checked registration contract; and
- the independent construction benchmarks approach a handwritten Lua C module closely
  enough that compiler lowering, rather than the bridge architecture, is no longer the
  bottleneck.

Shared-memory slices are not ordinary Lua strings and are not an outcome of this plan.
A separate lazy document API may expose borrowed byte views, but `string` results from
this builder remain normal GC-owned strings with normal Lua identity and lifetime.

## Why

Plan 062 moved structural indexing, UTF-8 validation, and complete JSON grammar into
native code, then deliberately stopped at pointer-free arenas. Its retained Lua
materializer still performs one or more FFI reads per node, recursively walks links,
allocates every table and string, decodes escapes through temporary substring tables,
and writes every result from Lua.

The implemented AArch64 benchmark shows the resulting division clearly. Native
parsing is fast for the string-heavy payloads, while Lua materialization becomes the
dominant stage, especially for escaped strings. The remaining boundary is
architectural rather than a missing SIMD operation: widening byte classification
cannot remove Lua table allocation, string creation, or per-node FFI traffic.

`lua-cjson` does not pay that boundary. It parses in C and calls the Lua C API to
create the final tables and strings during the same native call. Nupp can use the same
class of runtime facility without giving source code unchecked access to the VM. A
verified construction IR keeps rooting, barriers, stack bounds, ownership, and
supported operations inside the compiler's safety boundary.

This is broader than JSON. Native code frequently computes a dynamic collection that
must become an ordinary Lua value: database rows, decoded messages, syntax trees,
directory entries, image metadata, and generated foreign bindings all have this
shape. Returning an FFI arena forces every consumer either to accept a foreign data
model or to repeat the same slow materialization step.

## Relationship to existing plans

`038-aot-functions.md` remains the owner of the `@aot` contract, checked subset,
generated-C backend, target artifacts, and build policies. This plan adds one verified
IR effect and one calling convention. It does not create another compiler or alter
the meaning of pure kernels.

Plan 038's current AOT IR explicitly contains no Lua object or GC operation, and its
design requires modeled native failures to return status rather than unwind through
an FFI frame. Preserve both rules for the kernel ABI. Do not mistake the second rule
for reusable implementation: shipped kernels currently raise their admitted
precondition and range failures in the Lua wrapper before FFI entry, and the native
ABI does not yet exercise a general status result. V1a and V2 therefore establish and
test the builder failure path as new work. The VM-aware ABI is invoked as a Lua C
function, so its checked calls occur on a VM-owned C frame where Lua allocation and
protected errors are valid.

`062-aot-block-simd-parsing.md` explicitly deferred Lua C API materialization pending
measurement and required a separately designed checked bridge if materialization
dominated. This plan is that bridge. It consumes the implemented block-kernel, parser,
arena-layout, and scoped-SIMD foundations without revising their historical design.

`054-embedding-nupp.md` owns the public host/runtime boundary. A VM-aware AOT artifact
registers private Lua C functions in an attached state, but does not make those
symbols part of the stable embedding SDK. Managed host handles and component loading
remain unchanged.

`047-lua-ownership-capabilities.md` remains authoritative when a constructed value
contains or transfers an affine capability. The first builder subset rejects such
values. Its one sealed exception is a compiler-proved local `nupp.io.Buffer` and
`ScalarWriter` used only as the ordinary fallback spelling of a transformed string;
their drops remain in the ownership graph even when lowering replaces their runtime
representation. Later result support must root and transfer the exact existing
capability rather than treating a Lua stack slot as proof of language ownership.

`053-c-interop.md` remains about user-declared foreign APIs. Lua-construction
operations are compiler/runtime intrinsics and do not expose the Lua C headers as a
general `cdef` surface.

## Current boundary

Today the generated Lua binding for an AOT function:

1. checks relationships and projects spans;
2. loads a generated native library through LuaJIT FFI;
3. calls an exported C function with scalars and pointers;
4. receives scalars or a compiler-owned result struct; and
5. raises currently admitted relationship, precondition, and range failures from the
   Lua wrapper before native entry.

Plan 038 reserves compact native status reporting for failures that cannot be hoisted,
but the current ABI has no exercised general status field. The builder path cannot
copy a battle-tested status mechanism from the kernel path. It must independently
test wrapper rejection, a modeled failure raised from a registered C closure, Lua
allocation failure, protected-call behavior, and source attribution before table
construction lands.

That C function has no `lua_State *`. Passing the address of input bytes through FFI
does not grant authority to allocate a Lua table, create a GC string, or run a write
barrier. Calling back into Lua once per value would restore exactly the transition
cost this work is meant to remove.

The VM-aware path instead exports a function with the Lua C-function convention:

```c
int nupp_aot_build_value(lua_State *L);
```

It reads checked arguments from the VM stack, keeps live construction values on that
stack, and returns the number of results. A generated Lua wrapper may remain around
the C closure for source-level relationships that are cheaper or clearer to check in
Lua, but it performs one call into the native body and never interprets a node tape.

## Source model

### Automatic ABI classification

Do not require a second annotation spelling. `@aot` remains the source contract. Once
the checker has admitted a body, lowering classifies it as one of:

```text
kernel       native scalars, structs, spans, and native results
lua-builder  constructs or returns ordinary Lua-managed values
```

The classification follows resolved operations and result representation, not names
or syntax alone. It is deterministic, appears in `nupp aot`, and participates in the
artifact fingerprint.

A body cannot straddle the ABIs accidentally. A pure kernel may be called by a
builder body through the existing private AOT-to-AOT convention. A kernel cannot call
a builder body because it has no VM state. Recursion involving a builder and dynamic
dispatch remain outside the first subset.

`@aot(lanes = true)` on a builder body reports that lane lowering applies to an
independent numeric loop, not to an allocation-capable value constructor. Explicit
SIMD helpers may still run before construction or between construction operations,
but no Lua API call may appear inside a loop claimed as an independent map lane.

### Ordinary fallback semantics

Every admitted operation must already have ordinary Nupp behavior:

```nupp
@aot
local function rows(count: integer): {any}
    local result = table.new(count, 0)
    for index = 1, count do
        result[index] = index
    end
    return result
end
```

With `aot=off`, this is the original table allocation and loop. With AOT required, the
resolved `table.new` becomes `lua_createtable` and each proved fresh-array write
becomes a raw indexed set. No AOT-only builder value exists at runtime, so this plan
does not introduce the explicit-SIMD exception where disabling AOT makes the body
unexecutable.

Table literals with statically known fields receive inferred capacities. Dynamic
capacities use the already documented LuaJIT `table.new(narray, nhash)` identity.
Lowering checks nonnegative integral counts and the C API's `int` range before
allocation. It does not infer a speculative capacity from profile data.

### Fresh-table discipline

Initial table lowering is limited to tables created in the current builder body.
Before a table escapes, every use must be one of:

- an indexed write with a proved positive integer index;
- a map write with a nonnil, non-NaN primitive key;
- insertion into another fresh builder table;
- a dense-prefix length query the verifier can answer from its own cursor fact; or
- the final return.

Reads, deletion, `pairs`, `next`, sorting, metatable installation, equality that
observes identity, storage in an opaque value, and calls to unknown functions are not
admitted initially. Assignments to argument tables or arbitrary existing tables are
also rejected. These rules make raw C API writes equivalent to the ordinary source:
the new table has no metatable and no user code can observe it between creation and
publication.

The first version constructs trees and acyclic shared subgraphs. Self-reference and
general cycles require a separate liveness and publication review. JSON needs neither.

### Primitive values and null

Nil, booleans, binary64 numbers, fixed-width integers representable under the existing
numeric contracts, and rooted strings may be inserted. Conversion follows Plan 038's
numeric rules; the builder does not silently coerce a `uint64` that Lua cannot
represent exactly into binary64.

Lua nil deletes a map key and cannot represent JSON null inside an array. The JSON
consumer passes or captures the same `json.null` value used by the ordinary decoder.
General builder lowering does not invent a second null sentinel.

Records, interfaces, functions, threads, user-visible userdata, cdata, and affine
result values are not construction primitives in the first stage. Each needs a
representation and lifetime decision rather than an unchecked
`lua_pushlightuserdata` escape hatch. Compiler-owned rooted scratch userdata is an
implementation detail and can never be published as a result.

### Strings

A string input remains rooted as an argument for every use of its byte pointer. A
proved `string.sub` over that input lowers to one `lua_pushlstring` of the selected
range. The result is an ordinary Lua string and therefore performs the one unavoidable
copy into VM-owned storage.

For transformed strings, lower an exact, strictly local subset of the existing
`nupp.io` identities rather than adding a public builder type. The admitted source
shape creates `nupp.io.newBuffer(integer)`, opens
`nupp.io.newScalarWriter(buffer)`, appends through `writeBytes` and `writeUint8`,
obtains the final `buffer:getString()`, and discharges both affine values. The complete
use graph must be statically visible; a buffer or writer passed to an unknown call,
stored, returned, viewed, read before finishing, or used through another interface is
not admitted.

This gives `aot=off` the existing checked growable-buffer behavior. Builder IR replaces
the proved local pair with:

- reserve a bounded output length;
- append a proved input range;
- append one byte or one encoded Unicode scalar;
- finish exactly once as a Lua string; and
- discard the unpublished builder on a modeled source failure.

At native entry, compute or prove the maximum simultaneously live transformed-string
capacity. On the first transformed string, allocate a Lua userdata scratch region of
that bound, keep it rooted, and reuse it after each finished string has been copied by
`lua_pushlstring`. A body that never begins transformed output allocates no scratch.
JSON may use the source byte count as the bound because decoding escapes never
produces more bytes than the complete input. A general source whose bound is
unavailable or exceeds the configured limit is rejected rather than falling back to
`malloc`.

The scratch contains bytes only, owns no external resource, and needs no finalizer.
If its allocation raises, no native cleanup is live. If final string allocation
raises, the scratch remains rooted and is reclaimed with the C frame. Do not retain
`malloc` storage across an allocating Lua C API call.

There is no substring view, shared backing store, or private LuaJIT string allocation.
Escaped JSON strings necessarily have different bytes; unescaped strings still copy
once because normal Lua strings own their storage.

## Lua-construction IR

Extend AOT IR with a separately tagged construction effect. Conceptually it includes:

```text
lua.argument_string(index) -> RootedString
lua.new_table(arrayCapacity, hashCapacity) -> LuaTable
lua.nil | lua.boolean | lua.number | lua.integer -> LuaValue
lua.string_slice(rootedString, offset, count) -> LuaString
lua.bytes_begin(capacity) -> ByteBuilder
lua.bytes_append_* / lua.bytes_finish -> LuaString
lua.raw_set_index(table, index, value)
lua.raw_set_key(table, key, value)
lua.publish(table) -> LuaValue
lua.return(values...)
lua.fail(site, status)
```

`LuaTable`, `LuaString`, `LuaValue`, `RootedString`, and `ByteBuilder` are verifier
types, not source types or C structs. They cannot be cast to an address, stored in a
span or native struct, returned through the kernel ABI, serialized as a raw pointer,
or compared with native memory.

The IR is ordered and effectful. Ordinary scalar optimization may compute capacities,
indexes, offsets, and numeric values, but it may not reorder Lua allocation, string
creation, publication, or writes across an observable failure. Dead unpublished
construction may be removed only when doing so cannot remove an allocation failure or
change an authored error order under the function's optimization contracts.

### Verifier obligations

Before C emission, the AOT verifier proves at least:

- every VM operation occurs only in a function classified `lua-builder`;
- every table and string handle is defined once and dominated by its creation;
- every live handle has a rooted stack representation across allocating calls;
- every stack effect is known on every control-flow edge and merge;
- maximum stack growth is bounded and checked before entry or before a dynamic burst;
- every table write targets a fresh, unpublished table and uses an admitted key;
- capacities, source ranges, and byte-builder writes are nonnegative and in range;
- no borrowed input pointer survives its rooted owner's lifetime;
- every byte builder is finished or abandoned exactly once;
- no native cleanup obligation is live across a Lua error that may longjmp;
- no Lua handle crosses into a pure kernel helper;
- every return publishes only initialized values; and
- instruction, allocation, nesting, stack, output-byte, and generated-code limits are
  enforced before backend emission.

Control-flow joins carry logical rooted handles, not guessed C stack indexes. The
backend assigns physical stack slots after verification and may spill scalar native
state normally. It must never keep a Lua object solely in an unrooted C pointer or
assume that LuaJIT will never move it.

## Runtime ABI and loading

### Public API subset, private artifact ABI

Generated code uses a pinned subset of the public Lua 5.1 C API supplied with Nupp's
supported LuaJIT runtime. The initial list is limited to stack checks and indexing,
argument reads, primitive pushes, `lua_createtable`, `lua_rawset`, `lua_rawseti`,
`lua_newuserdata`, `lua_pushlstring`, and protected error reporting. Scratch userdata
is compiler-owned and never exposed to source.

Do not include or address LuaJIT's private object layouts. Public API use preserves
write barriers, string interning, allocation accounting, GC rooting, and compatibility
across supported LuaJIT builds. Artifact keys include the target, runtime ABI family,
Nupp runtime version, construction-IR version, and any required LuaJIT link identity.

The API subset may also exist in another Lua 5.1-compatible runtime, but the first
support and performance promise is Nupp's shipped LuaJIT. Cross-runtime portability is
not inferred from matching function names.

### Module registration

Keep translation-unit batching at the Nupp module boundary. A batch containing one or
more builder functions emits:

- the private C implementations;
- one digest-named registration entry point; and
- a table mapping compiler identities to Lua C closures.

Dynamic builds load that entry point as a Lua C module and receive the closures. The
generated Lua binding caches the registered table just as the existing binding caches
an FFI library. Static and embedded builds call the same registrar against the target
state through the component/runtime resolver described by Plan 054.

Do not ask FFI to discover `lua_State *`, pass a fabricated state pointer, or invoke a
Lua callback for every constructed value. Windows import libraries, Unix symbol
resolution, macOS dynamic lookup, stripped executables, and static linking each get an
explicit build fixture before the ABI is called supported.

### Wrapper and dispatch

The generated Lua wrapper retains source-level argument relationships, feature-tier
selection, lazy artifact loading, and ordinary error framing. Its one call target is a
registered Lua C closure rather than an FFI symbol.

When a builder calls pure AOT helpers, they are linked in the same artifact or through
the existing private AOT call graph. Optional multiversioning selects one compatible
closure or one internal helper tier at load time; it does not put a feature branch
around every construction operation.

Workers register the artifact independently in each state. A Lua object created in
one worker never crosses to another through the native artifact. Hot reload gives a
new module generation new closures and keeps the old image resident while any old
closure remains reachable, following the existing native-image lifetime rule.

## Errors, GC, and cleanup

The Lua C-function ABI may allocate and may raise on its VM-owned C frame. That is
different from unwinding through the existing FFI call and is the reason for a
separate ABI.

Use these rules:

1. Every partial Lua graph remains reachable only from the current C stack until the
   final result is returned or stored into another rooted construction value.
2. Lua resets the call stack on a protected error; the collector may then reclaim the
   unpublished graph.
3. Generated C holds no unowned native heap allocation, open handle, borrowed affine
   capability, or required cleanup action across a Lua API call that can raise.
4. Modeled parser or capacity failures restore the expected stack shape before
   returning or raising the source-attributed Nupp error.
5. Allocation failure uses the runtime's ordinary failure path and is never converted
   into a misleading syntax or capacity status.
6. `lua_checkstack` failure is handled before writes that require the additional
   slots.
7. C code uses exact stack indexes assigned by the backend and validates their merge
   shapes in tests; handwritten negative fixtures deliberately corrupt each shape and
   must be rejected before execution.

No finalizer is required for fresh tables or ordinary strings. A future builder
operation that creates userdata or transfers native ownership needs its own plan and
must integrate with the language's affine cleanup model.

## JSON acceptance workload

Retain the current structural indexer and UTF-8 validator. Replace only the arena-to-
Lua half in measured stages.

First, give the native parser a construction-oriented output containing final
container child counts, primitive values, and string recipes. Have a builder AOT body
consume that validated representation and construct Lua values entirely on its Lua C
frame. This isolates the new ABI and gives exact `lua_createtable` capacities without
changing grammar recognition at the same time.

Then profile whether the construction representation still pays for itself. If a
second native pass or arena traffic is material, fuse parsing and construction while
retaining the structural tape needed by indexing. A fused parser may delay opening a
container until its count is known, consume a compact count side table, or accept a
measured capacity estimate; it may not call a private LuaJIT table-resize routine.

The finished ordinary decoder should:

- allocate the final arrays and objects with array/hash capacities;
- store the configured `json.null` sentinel rather than nil;
- convert each number once before insertion;
- copy an unescaped source slice directly into one Lua string;
- decode an escaped string natively and create one final Lua string;
- perform no Lua-side recursive walk and no per-node FFI read;
- discard every partial graph on invalid input; and
- preserve the existing accepted grammar, duplicate-key behavior, numeric results,
  UTF-8 policy, nesting bound, and first-error attribution.

The benchmark continues to report indexing, parsing/construction, end-to-end decode,
short-input routing, memory, and `lua-cjson`. Remove node/link/frame arena allocation
from the ordinary decode path only after the builder path passes differential and
performance gates. Keep the arena API available to tests or lazy consumers only if a
named non-materializing use remains.

## Delivery stages

### V0 — Freeze construction and runtime baselines

- Record the existing SIMD JSON component and end-to-end results, including raw
  samples and runtime/toolchain identity.
- Add independent workloads for flat arrays, flat maps, nested mixed values, raw
  strings, escaped strings, and numeric rows.
- Implement a small handwritten Lua C module as the performance and stack-discipline
  oracle for those workloads.
- Record allocations, peak memory, object counts where available, code size, cold
  build time, module-load time, and warm call time.

Gate: the handwritten oracle and Lua implementation agree exactly, benchmark
confidence intervals can distinguish the later thresholds, and every supported host
can load an ordinary handwritten C module through the intended registration route.

### V1a — Dynamic registrar and VM-aware entry spike

This is the critical path and is expected to be the largest single implementation
cost in the plan. Nupp currently has no compiler-backend use of `lua_State`, Lua C
closures, or Lua C-module registration. Treat V1a and V1b as a new backend axis, not
loader plumbing to compress beneath the V2 verifier work. Construction IR does not
begin until both stages pass.

- Emit and load a digest-named Lua C-module registrar beside existing FFI artifacts.
- Generate a primitive-only C-function fixture with no table construction.
- Define the builder failure convention independently of Plan 038's unexercised native
  status design: wrapper precondition failures stay in Lua, while a modeled failure
  reached inside the C closure pushes the compiler-owned source-attributed error and
  raises through that VM-owned C frame.
- Verify successful return, protected failure, stack restoration, and source frames on
  the primary dynamic host before adding construction operations.

Gate: one checked Lua call enters and returns from the native closure; `pcall` catches
the native modeled failure with the expected Nupp message and source site; malformed
registration and stack shapes fail deterministically; and no Lua or GC operation has
entered the existing kernel IR or ABI.

### V1b — Artifact and loading matrix

- Add artifact fingerprints for runtime ABI, entry mode, target, and registration
  identity.
- Preserve dynamic, static, embedded, worker, cache, and `emit-c` policies.
- Prove Windows import libraries, Unix symbol resolution, macOS dynamic lookup,
  stripped executables, and static registration through explicit build fixtures.
- Record cold build, link, registration, and cached-load cost separately so later
  construction benchmarks cannot hide the backend's deployment cost.

Gate: one checked Lua call enters and returns from the native closure on every
supported platform; stale, mismatched, missing, or incorrectly linked artifacts fail
at load with a stable diagnostic; pure AOT artifacts are byte-identical to their
pre-plan form.

### V2 — Construction IR and fresh tables

- Add verifier types and operations for rooted primitive values, fresh tables,
  capacity, raw array/map writes, publication, and return.
- Lower table literals, exact `table.new`, and writes to compiler-proved fresh tables.
- Add stack assignment, stack checks, barriers through public API calls, resource
  limits, serialization, inspection, and negative IR fuzzing.
- Exercise the feature with non-JSON row and tree builders.

Gate: differential tests cover every control-flow merge, zero and maximum capacities,
duplicate keys, dense arrays, nesting limits, forced GC between every construction
operation, allocation failure injection, and protected errors. The generated builder
clears the V2 performance gate below.

### V3 — Strings and modeled failures

- Lower rooted input slices to one final Lua string copy.
- Lower the exact local `nupp.io.Buffer`/`ScalarWriter` subset to one rooted,
  bounded, reusable scratch userdata.
- Preserve error sites and ensure every temporary is GC-owned or cleanup-free across
  allocating calls.
- Cover ASCII, embedded NUL, arbitrary bytes, valid UTF-8, escape expansion,
  contraction, surrogate pairs, empty strings, and maximum configured output.

Gate: raw and transformed strings agree byte-for-byte with the ordinary path, survive
forced collection, leak no native storage under injected failures, perform one final
Lua string creation, and clear the V3 performance gate.

### V4 — Build JSON values from validated parser output

Implemented on Apple arm64/NEON through the general
`nupp.value_builder.materializeTree` recipe. The old recursive arena materializer
remains only as an explicit benchmark/oracle path; ordinary large-document decode
uses two bulk blob copies and one VM-aware construction call. The committed paired
result clears every V4 performance threshold.

- Add final container counts and string recipes to a detachable construction-oriented
  representation under `bench/simd-json`.
- Consume it from a VM-aware AOT function and remove recursive Lua materialization
  from the experimental decode path.
- Move remaining hard-number conversion and escaped-string decoding into the native
  path so each value is converted once.
- Preserve the adaptive short-document comparison until measurements replace it.

Gate: the existing 1,024-case corpus, generated differential cases, invalid mutations,
capacity failures, nesting cases, numeric bit comparisons, and error positions all
agree; the path clears the V4 performance gate.

### V5 — Profile and decide representation fusion

Implemented on Apple arm64/NEON. The production JSON route retains the SIMD
structural tape, copies it once into a rooted string, and parses directly into the
final Lua graph through the general value-stream builder. Node, link, and frame
arenas remain only in the named comparison path. Number spellings go through the
final `strtod` conversion once rather than first running the old exact-binary64
classification pass.

The committed 15-sample Apple arm64/NEON result clears the gate. Fused/tree-builder
geometric-mean throughput is 1.468x (95% bootstrap CI 1.459–1.479x); the weakest
large family is still 1.150x and numbers reach 2.830x. Fused/arena is 2.592x and
fused/legacy is 5.627x. The production route therefore keeps fusion.

- Profile indexing, construction-representation production, builder consumption,
  allocations, C API calls, and final GC pressure by payload family.
- Fuse parsing and value construction only if the retained representation exceeds the
  threshold below.
- Retain a construction tape or arena only for a measured lazy, validation, or reuse
  case; otherwise remove it from ordinary decode.
- Record AVX2 and NEON results independently.

Gate: the selected path is the smallest architecture that clears the end-to-end gate.
A failed fusion experiment is removed without reverting the general builder ABI or
construction IR.

### V6 — Decide support and broader values

Choose explicitly among:

- support VM-aware AOT construction and retain JSON as its acceptance benchmark;
- retain the compiler capability but remove the JSON value-building experiment;
- keep only the registration ABI while revising the source subset; or
- remove the VM-aware path if it cannot approach handwritten C API construction.

Records, cdata, userdata, metatables, cycles, mutation of existing values, callbacks,
and affine transfers require separate evidence and review. They do not enter merely
because primitive tables and strings succeed.

## Performance gates

Use alternating paired measurements, at least four warmups and fifteen measured
samples, batches long enough to dominate timer resolution, and paired bootstrap 95
percent confidence intervals. A threshold passes only when the complete confidence
interval clears it. Record cold compilation and loading separately from warm
throughput.

- **V2 fresh tables:** the generated AOT builder must reach at least 90 percent of the
  handwritten Lua C module's throughput on the large flat-array and flat-map geometric
  mean. It must perform one Lua-to-native call, allocate exactly the required Lua
  result graph aside from documented VM growth, and make no FFI call or Lua callback
  per value.
- **V3 strings:** raw slices must reach at least 90 percent and transformed strings at
  least 85 percent of the handwritten C module on their respective large-payload
  geometric means. The generated path may create no temporary Lua string per decoded
  chunk or escape.
- **V4 JSON:** the large-payload geometric mean must improve by at least 1.75 times over
  the implemented Plan 062 arena decoder, every large family by at least 1.20 times,
  and escaped strings by at least 3.0 times. Median short-document throughput may
  regress by no more than ten percent from the faster retained route.
- **V5 fusion:** fuse parser and construction only if the construction representation
  consumes at least ten percent of end-to-end time and fusion improves end-to-end
  throughput by at least five percent on a named family without regressing another
  family by more than two percent.

Keep `lua-cjson` as the external reference and report the ratio for every payload.
Do not make equality with `lua-cjson` a compiler safety gate: its parser, number
conversion, and representation choices differ from the construction bridge itself.
A public Nupp JSON proposal must set its own end-to-end requirements after V5.

No performance result excuses private GC access, missing barriers, unbounded stack
growth, changed numeric results, unsafe source pointers, or leaked temporary storage.

## Verification matrix

Compiler tests cover checking, resolved-identity admission, ABI classification, AOT IR
construction and verification, serialization versions, deterministic C emission,
registration, binding generation, cache invalidation, target dispatch, `aot=off`,
`aot=require`, `aot=emit-c`, inspection, formatter stability, LSP diagnostics,
incremental rebuilds, and fixpoint.

Runtime tests cover:

- x86-64 and AArch64 supported LuaJIT builds;
- dynamic modules, statically linked artifacts, embedded states, and worker states;
- empty, exact, excessive, negative, and overflowing capacities;
- arrays, maps, nested trees, duplicate keys, and shared acyclic children;
- every primitive value and numeric boundary;
- empty strings, embedded NUL, arbitrary bytes, Unicode, and transformed strings;
- forced full collection after every possible allocating operation;
- stack growth and stack exhaustion at every nesting depth;
- injected allocation failure and protected error at every construction operation;
- normal return, every early failure edge, and wrapper-level argument rejection;
- stale artifacts, wrong runtime ABI, wrong target, missing registration symbols, and
  duplicate module loading; and
- sanitizer runs for generated C fixtures where the platform supports them.

Negative verifier tests attempt to forge or escape every construction handle, retain
an input pointer after its root dies, mutate an argument table, invoke a metatable,
cross a Lua handle into a kernel helper, leave a byte builder unfinished, merge
incompatible stack shapes, publish an uninitialized value, exceed each resource bound,
and retain native cleanup across a raising API operation.

JSON repeats Plan 062's valid/invalid corpus, differential fuzzing, number bit tests,
UTF-8 and escape boundaries, deep nesting, truncation, duplicate members, and stable
error-byte checks. It additionally forces GC during construction and verifies that no
partial graph becomes reachable after failure.

## Inspection and diagnostics

`nupp aot` reports for every function:

- `kernel` or `lua-builder` entry mode and the source operation that selected it;
- the runtime ABI and registration artifact identity;
- inferred and dynamic table capacities with their proof source;
- construction allocations, raw writes, publication points, and maximum VM stack;
- rooted string ranges and whether a string is copied raw or transformed;
- calls to pure AOT helpers and their target tiers;
- modeled failure sites and native-cleanup restrictions; and
- the first unsupported Lua-managed operation with a source position.

Diagnostics distinguish unsupported mutation of an existing table, possible metatable
dispatch, unproved capacity or source range, construction-handle escape, incompatible
stack merge, unsupported value representation, native cleanup across allocation,
kernel-to-builder call, unavailable runtime ABI, and failed artifact registration.

Do not recommend `@aot` merely because a function creates a table. The AOT candidate
advisor from Plan 058 may recommend this path only after profile evidence attributes
material time to a construction loop and inspection confirms that the body fits the
supported subset.

## Documentation

Update documentation with each shipped stage rather than publishing the complete
proposed surface when V1a first lands:

- `docs/tooling/aot.md` documents `kernel` versus `lua-builder` inspection, the
  admitted source subset, build-mode behavior, failure boundary, runtime dependency,
  and unsupported operations.
- `docs/tooling/optimization.md` explains capacity-aware `table.new` lowering and how
  to confirm it through `nupp aot`; it does not imply that every table allocation is
  an AOT candidate.
- `docs/io.md` records that a strictly local `Buffer`/`ScalarWriter` chain may be
  representation-lowered while preserving its ordinary behavior and affine drops.
- `docs/embedding.md` and `docs/distribution.md` describe dynamic registration,
  statically linked registrars, runtime ABI fingerprints, worker-state registration,
  and artifact deployment once V1b supports those paths.
- `src/nupp/compiler/reference.nupp` remains the language-reference source of truth.
  Update it so both `./bin/nupp reference language` and
  `./bin/nupp reference language --format skill` describe the shipped subset and its
  diagnostics.
- `bench/simd-json/README.md` records the retained representation, component timings,
  memory cost, and whether V5 fused parsing with construction.

Documentation examples run under `aot=off` and `aot=require`, and every named
diagnostic has an `explain` entry and stable docs anchor before its stage is complete.

## Risks and controls

**Turning AOT into a second Lua implementation.** Restrict the first surface to fresh
object-graph construction. Reject arbitrary reads, metatables, callbacks, dynamic
calls, coroutines, and userdata rather than reproducing VM semantics in C.

**GC unsafety.** Model Lua values as rooted verifier handles and lower exclusively
through public API barriers. Force collection and allocation failure between every
operation. Never store a bare GC pointer as native state.

**Longjmp leaks.** Keep native temporaries cleanup-free across allocating API calls or
move them into GC-owned objects first. The verifier rejects a live cleanup obligation
at a possibly raising operation.

**Runtime lock-in.** This plan deliberately optimizes Nupp's LuaJIT runtime, but uses a
pinned public C API subset and explicit artifact fingerprint rather than private
layouts. Other runtimes need an implemented backend, not an assumed compatibility
claim.

**Source semantic drift.** Raw writes are admitted only on fresh unpublished tables,
where no metatable or observer can distinguish them. `aot=off` differential tests
remain mandatory.

**String overpromising.** Ordinary Lua strings still allocate and copy. Document the
one-copy goal and keep zero-copy borrowed strings in a separate lazy-document design.

**JSON overfitting.** Land row/tree builders and string workloads before modifying
JSON. Every retained compiler feature must have a non-JSON test and benchmark.

**New backend and artifact axis.** A Lua C module has different code generation,
failure, link, registration, and load requirements from an FFI library, especially on
Windows and static hosts. V1a and V1b are the plan's largest expected cost and prove
every supported path before construction IR lands. Do not schedule V2 concurrently
on an assumed registrar ABI or waive a host mode to make the bridge appear complete.

**Partial graphs on failure.** Keep all unpublished values rooted only on the current
VM stack and exercise protected failure at every operation. Never place a partial
result in a registry global as a construction shortcut.

## Rejected alternatives

### Interpret a construction tape in Lua

Presized tables and sequential tape reads improve the current materializer, but Lua
still performs an FFI read and dynamic insertion for each value. It is a useful
staging baseline, not the final bridge.

### Call Lua callbacks from an FFI kernel

One callback per allocation or insertion multiplies native/VM transitions and
complicates yielding and errors. It loses the performance reason for the feature.

### Pass `lua_State *` through ordinary FFI

The current wrapper has no supported state handle, and fabricating or discovering one
couples checked code to private LuaJIT internals. A registered Lua C closure is the
supported VM entry convention.

### Expose raw Lua C API calls in Nupp

Stack indexes, longjmp, barriers, and rooting are too easy to misuse and would make
generated C safety depend on handwritten foreign discipline. Keep them behind verified
construction operations.

### Use LuaJIT private object layouts for zero-copy strings

This would pin artifacts to collector internals, bypass allocation accounting and
barriers, and still fail for transformed bytes. Public `lua_pushlstring` is the normal
string boundary.

### Replace the existing AOT ABI

Numeric and memory kernels benefit from having no VM state, allocation, or GC effects.
Keep their smaller verifier and faster FFI boundary intact.

### Make JSON a standard library as part of this work

JSON is an acceptance workload. Public API, compatibility, security, numeric policy,
and long-term performance support require a later decision based on completed results.

## Completion criteria

This plan is complete when:

- VM-aware AOT entry, registration, artifact identity, wrappers, and all build modes
  work on supported targets without changing pure AOT artifacts;
- verified construction IR safely creates presized tables, primitive values, raw and
  transformed strings, and nested acyclic graphs through the public Lua C API;
- ordinary source and `aot=off` retain the same behavior;
- GC, stack, error, cleanup, worker, embedding, hot-reload, and sanitizer tests pass;
- independent builders clear the handwritten-C performance gates;
- the detachable JSON experiment constructs ordinary Lua results without a recursive
  Lua materializer and records component, end-to-end, memory, and external-reference
  results on NEON and AVX2;
- every retained compiler capability has a non-JSON fixture and remains coherent if
  `bench/simd-json` is deleted; and
- AOT, optimization, IO, embedding, distribution, benchmark, generated language
  reference, and reference-skill documentation describe exactly the stages that
  shipped; and
- the project explicitly decides whether to support the builder ABI and whether JSON
  remains only an acceptance benchmark.

Completion does not require general Lua execution in AOT, zero-copy ordinary strings,
userdata or metatable construction, cycles, callbacks, mutation of existing tables,
affine-value transfer, a public JSON module, or replacing LuaJIT.
