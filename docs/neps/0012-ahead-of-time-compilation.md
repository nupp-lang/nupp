---
title: Ahead-of-time compilation
status: Implemented
created: 2026-08-19
---

## Summary

An annotation states that a function must compile as one checked ahead-of-time
unit. The body is ordinary Nupp — same parser, name resolution, type system,
operators, diagnostics, and source positions — and the annotation adds a
compilation and effect constraint after ordinary checking rather than
reinterpreting anything. Checked views lower to pointer arithmetic where a range
witness proves them, a second calling convention lets an admitted function build
a Lua value graph natively, and an advisory analysis finds candidates without
adding anything to the source.

[Ahead-of-time compilation](../guides/ahead-of-time.md) documents the surface.

## Goals

- Give a function a checked guarantee that it compiles ahead of time, or a build
  error saying why not.
- Introduce no second expression language.
- Keep the safety boundary in Nupp's own IR rather than in a backend.
- Make checked views cost what handwritten unchecked FFI costs, in the loops
  where that matters.

## Non-goals

- Operating-system code, GPUs, or permitted unsafe operations.
- Silent fallback. A backend regression is a build error and a compiler defect.
- A generic metamethod optimization, or an unchecked public view API.
- Arbitrary table operations, metatables, dynamic calls, callbacks, coroutines,
  userdata, or general Lua execution inside an annotated function.
- Predicting a speedup.

## Motivation

### The failure to avoid is a second language

The obvious way to build this is a restricted sublanguage with its own
semantics — the shape most "compile this part natively" features take. That
gives two languages to learn, two diagnostic surfaces, and a boundary at which
ordinary-looking code changes meaning.

Stating it as a *contract over ordinary Nupp* means the body is the same program
either way. Removing the annotation may change performance and artifacts, not
the source-level result. Adding it may reject constructs the backend cannot
represent, and may not make an otherwise invalid operation valid.

### The foundations had to be worth landing on their own

Four capabilities landed first — canonical C identities and header export for
reified structs, explicit fixed-width scalar arithmetic, richer checked span
views, and transported allocation and raising guarantees — each required to be
useful and testable with the backend disabled. A capability justified only by an
unlanded consumer is designed against a guess.

### A checked view that costs more than a pointer does not get used

The argument for checked spans is that the safe route should be the only route.
That holds only if it is also the fast route; otherwise the hot loop is written
with raw pointers and the guarantee applies to the code that did not need it.

The proof already exists at the range, not at the access: a range witness
validates every participating view once, so every access in the loop it
dominates is already proved in bounds.

### The kernel ABI stops where the useful work ends

A native kernel filling a span returns nothing a program can hand to ordinary
Lua code. A parser or decoder whose output *is* a Lua value graph must either
return through a span and rebuild in Lua — paying the cost the native path
existed to remove — or be excluded. Letting the body call the VM directly
reintroduces unchecked stack discipline and unverifiable rooting.

### Eligibility cannot be determined by reading

Whether a body lowers depends on the admitted subset, the selected target, and
the backend. So the functions most worth annotating are the hardest to identify,
and the practical result is that the feature gets used on whatever someone
thought of.

## Overview and specification

### Syntax

```nupp
@aot
local function scaleAdd(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>,
    scale: float
): nil
    for i = 1, output.count do
        output[i] = input[i] * scale
    end
end
```

```nupp
#view                -- length
view[index]          -- read
view[index] = value  -- write
view[index].field    -- direct indexed field projection
indexed.range(first, last, ...)
```

```sh
nupp build --aot=off       # emit every body as ordinary Nupp
nupp build --aot=require   # lower every @aot body, or fail saying why
nupp build --aot=emit-c    # verify the IR and write private C
nupp aot --suggest         # advisory candidates
```

### Usage

The annotation is a contract, not a request. A range witness validates once and
the loop reads and writes through operators:

```nupp
const rows = indexed.range(first, last, output, input)
for index = rows.first, rows.last do
    output[index].x = input[index].x + 1
end
```

An admitted function may build and return a fresh Lua value graph:

```nupp
@aot
local function parseRow(borrows bytes: span.Span<uint8>): {string: any}
    local out = {}
    out.name = bytes:text(1, 8)
    out.count = decodeCount(bytes)

    return out
end
```

Anything observing or mutating pre-existing managed state is outside the subset:

```nupp
@aot
local function bad(t: {string: any}): nil
    t.seen = true            -- rejected: not a value this function created
end
```

### Lowering

The body lowers to verified IR and then to private generated C, with a checked
wrapper calling it through the FFI:

```c
/* generated, private */
void nupp__scaleAdd(float *output, const float *input,
                    uint64_t count, float scale) {
    for (uint64_t i = 0; i < count; i++) {
        output[i] = input[i] * scale;
    }
}
```

```lua
local __lib = ffi.load("@lib/libapp_aot.so")
local function scaleAdd(output, input, scale)
   __lib.nupp__scaleAdd(output.__base + output.__offset,
                        input.__base + input.__offset, output.count, scale)
end
```

With the backend off the annotation is dormant and the same ordinary body is
emitted:

```lua
local function scaleAdd(output, input, scale)
   for i = 1, output.count do output[i] = input[i] * scale end
end
```

Without a range witness each view access carries its own bounds check; inside a
loop the witness dominates, the accesses lower to ordinary pointer arithmetic:

```lua
local __out = output.__base + output.__offset - 1
local __in = input.__base + input.__offset - 1
for index = rows.first, rows.last do
   __out[index].x = __in[index].x + 1
end
```

A non-escaping view root is compiler-owned scalars rather than an allocated
wrapper — a runtime fat pointer, not a compile-time fiction:

```text
contiguous view = anchor + typed base + offset + count + capability
SoA row view    = slab anchor + columns/layout + offset + count + capability
```

A function constructing managed values lowers to a Lua C function built through
a verified construction IR, with no VM state pointer or stack index in the
source:

```c
static int nupp__parseRow(lua_State *L) {
    const uint8_t *bytes = nupp_span_base(L, 1);
    lua_createtable(L, 0, 2);              /* fresh, rooted on the stack */
    lua_pushlstring(L, (const char *)bytes, 8);
    lua_setfield(L, -2, "name");
    lua_pushinteger(L, nupp__decodeCount(bytes));
    lua_setfield(L, -2, "count");

    return 1;                              /* the completed graph */
}
```

Where a target has feature tiers, one library carries one translation unit per
tier, distinguished by symbol suffix. A shared library is mapped rather than
run, so loading a tier the machine cannot execute is not a hazard — what would
fault is a call, and selection prevents it.

Within a supported language line, a source function accepted for a target
remains accepted. The admitted subset may widen and does not silently narrow.

Without that promise the annotation would be a request rather than a contract,
and a compiler upgrade could quietly turn a compiled function into an
interpreted one.

Generated private C compiled by a pinned toolchain is the initial backend. The
IR remains the safety boundary and the stable architecture. Direct machine-code
emission is deferred unless measured toolchain, latency, packaging, or
specialization requirements show generated C cannot meet the release gates.

### No transitional implementations

One implementation of each capability, with design questions resolved from
existing behaviour and permanent semantic tests *before* implementation — no
characterization path committed as a fallback, alternate API, or experimental
runtime.

Concretely: no temporary named runtime representation for structs to remove
later; no parallel fixed-width modules; no per-call boxes, per-call scratch
allocation, or one-call-per-operation numeric fallbacks; no public strided span
unless ordinary uses justify its final API first; and nothing implemented in a
benchmark spike and then reimplemented in the compiler.

This keeps a staged feature from accumulating two of everything, where the
temporary half outlives the reason for it.

### Only sealed types get the trusted view descriptor

An arbitrary length or index implementation does not establish that its length
bounds its indexes, that an access is pure, or that an indexed field denotes
stable storage. Ordinary metamethods keep ordinary dispatch.

Contiguous and columnar storage share one checked descriptor and differ in their
physical adapter, which is what lets the source surface be
representation-independent without making the two view types interchangeable.
Columnar storage was a landing condition rather than follow-up work — the change
did not land unless its direct field loops stayed within the handwritten FFI
ceiling and allocated no row proxies — which kept the descriptor from being
shaped around the easy case.

### Checked object-graph construction

The admitted subset is primitives, fresh table literals and capacity-hinted
construction, raw-equivalent writes to fresh tables, strings copied from proved
ranges of rooted inputs, structured control flow, admitted pure helpers, and
returning the completed graph.

The boundary is stated as what it *is* rather than as a list of exclusions: a
constructor for a value graph the function itself creates. Which convention a
function gets follows from what it consumes and produces, not from a second
annotation.

### The advisor answers three questions separately

**Not built.** Eligibility — can this body lower to verified IR for the selected
target? That is a proof. Static opportunity — does the admitted body have a
bulk-loop, fixed-width, lane, or span property making a native comparison
worthwhile? A deterministic cost-model judgement. Observed importance — did a
supplied profile see it consuming time or aborting traces? Evidence from one
workload.

None predicts a speedup, and a combined score would imply a claim no input
supports. The advisor adds no annotation, compiles nothing, changes no generated
Lua, and does not participate in whether source checks.

## Risks and assumptions

- **A pinned C toolchain is a build dependency**, so reproducibility depends on
  a compiler outside the language.
- **The compatibility promise is hard to keep.** "May widen, does not narrow"
  constrains every future change to the admitted subset, including changes made
  for correctness.
- **No fallback means a backend defect breaks builds**, which is deliberate and
  means a defect is felt as a hard failure rather than a slowdown.
- **The ordinary-semantics invariant is easy to erode.** Every extension will be
  tempted to admit a construct by giving it a slightly different meaning inside
  an annotated body, and one exception ends the property.
- **Sealed-type-only is a real asymmetry**, with no mechanism for a user type to
  prove the same properties.
- **Scalar replacement makes escape analysis load-bearing for cost.** A view
  that unexpectedly escapes silently materializes.
- **The recognised-by-identity subset is brittle to refactoring**, and an
  equivalent hand-written spelling is not admitted.
- **Rooting correctness is proved, not tested.** A defect there is a
  collector-visible memory error rather than a wrong answer.
- **Advice becomes an obligation.** An editor hint saying a function is eligible
  reads as a recommendation.

## Alternatives considered

**A restricted sublanguage with its own semantics.** Two languages, two
diagnostic surfaces, and a boundary where ordinary-looking code changes meaning.

**Silent per-function fallback.** The annotation is a contract, and a contract
that degrades quietly is a comment.

**Direct machine-code emission** rather than generated C. Deferred rather than
rejected: the IR is the architecture, and the backend can change if measured
toolchain, latency, packaging, or specialization requirements demand it.

**Landing the foundations as part of the feature.** Each had to be useful with
the backend disabled, or it would have been designed against an unlanded
consumer.

**Transitional implementations** to unblock staging. The temporary half reliably
outlives its reason.

**One library per feature tier.** A library is a thing that travels, and
per-tier libraries multiply naming, resolution, and packaging everywhere, to
avoid a symbol suffix.

**Keeping per-access bounds checks** and relying on the JIT to hoist them. The
check depends on values the trace compiler cannot always prove invariant, where
the range witness establishes the fact exactly.

**A generic metamethod-based optimization.** None of the required properties
follow from having the metamethods.

**An unchecked public view API** for hot code. It is the shorter unchecked route
the span design exists to eliminate.

**Inferring bounds from user-written conditionals.** A much larger analysis, for
the same result an explicit auditable witness gives.

**Returning through a span and rebuilding in Lua.** It pays the cost the native
path existed to remove, on the output side.

**Exposing the VM's C API inside the body.** Unchecked stack discipline,
unverifiable rooting, and a second language in a body meant to be ordinary Nupp.

**Admitting general Lua operations** so the subset is less surprising. That is a
native implementation of the VM, a different project with a different risk
profile.

**A single advisor score.** It implies a prediction none of the inputs supports.

**Automatically applying the annotation** to eligible functions. It is a
contract that makes a build fail, and nothing should add one without a person
deciding.
