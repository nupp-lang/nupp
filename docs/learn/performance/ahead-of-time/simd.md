---
order: 633
---

# AOT SIMD

AOT code runs in vector lanes through explicit `nupp.simd` operations. A loop written without them is a scalar loop.

```nupp
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function scale(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>, factor: float): nil
    assert(#output == #input, "length mismatch")
    if species = simd.species(array.float) then
        local cursor: uint32 = 0
        while cursor + species.lanes <= #input do
            species:store(output, cursor + 1, species:load(input, cursor + 1) * factor)
            cursor = cursor + species.lanes
        end
        if cursor < #input then
            local active = species:tail(#input - cursor)
            species:store(output, cursor + 1, species:load(input, cursor + 1, active) * factor, active)
        end
    else
        for i = 1, #input do output[i] = input[i] * factor end
    end
end
```

The full-vector guard makes the main loop's accesses safe without per-lane bounds checks. Only the final partial group uses a mask. The scalar branch runs when `simd.species` returns `nil`, including ordinary Lua execution with AOT off.

## Inspecting generated code

Use `nupp aot --emit llvm FILE` to inspect the LLVM IR and `nupp aot --emit asm --function NAME FILE` to inspect the selected machine code. Benchmark the complete exported function, including setup, tails, and reducer finalization, against its scalar form before committing to the vector one.

## Species, masks, and tails

`simd.species(array.float)` selects a preferred species for the target tier. Prefer it when source need not prescribe a logical lane count. `simd.species(array.float, 4)` asks for four lanes on every target; the backend may implement that value in multiple native registers. An asserted species is appropriate when the target is known to support vectors; a conditional species with a scalar continuation keeps the same source usable without them.

Vector comparisons produce masks. `mask:any()` tests for an active lane, `mask:first()` finds its first position, and `mask:select(yes, no)` chooses values lane by lane. `species:tail(remaining)` activates only lanes backed by remaining elements. Pass that mask to both a partial load and its store. Unmasked loads and stores need a dominating full-width bound. A bound on `#input` also covers `output` when the leading guards hold `output` no shorter, as `assert(#output == #input)` does in the example above.

```nupp
local cursor: uint32 = 0
if species = simd.species(array.uint32) then
    while cursor + species.lanes <= #values do
        local found = species:load(values, cursor + 1) <= 0xF
        if found:any() then return cursor + found:first() end
        cursor = cursor + species.lanes
    end
end
while cursor < #values do
    if values[cursor + 1] <= 0xF then return cursor + 1 end
    cursor = cursor + 1
end
return 0
```

An early-exit scan keeps its scalar continuation after the last full vector. For a divergent algorithm, keep a live mask, update only its active lanes with `select`, and continue while `live:any()`. The source states the control flow that runs in lanes; nothing else runs in lanes.

For a filter, count selected lanes before compressing them. The output cursor
advances by the count, not by the species width:

```nupp
local selected = value > threshold
local kept = selected:count()
local packed = value:compress(selected)
species:store(output, written + 1, packed, species:tail(kept))
written = written + kept
```

In a divergent loop, a mask is also the lifetime of unfinished lanes:

```nupp
while live:any() do
    local next = value * 0.5
    value = live:select(next, value)
    live = live & (value > 1.0)
end
```

## Interleaved records

Records of two to four elements stored one after another, like pixels or the bytes of a Base64 group, load a field to a vector with `species:loadPairs`, `loadTriples` or `loadQuads`. Each one reads the next `ways * lanes` elements and gives vector `j` elements `j`, `j + ways`, and so on. `storePairs`, `storeTriples` and `storeQuads` do the reverse. The results can only initialize locals:

```nupp
while at + 3 * species.lanes <= #rgb and out + 4 * species.lanes <= #rgba do
    local r, g, b = species:loadTriples(rgb, at + 1)
    species:storeQuads(rgba, out + 1, r, g, b, species:splat(255))
    at = at + 3 * species.lanes
    out = out + 4 * species.lanes
end
```

A guard for the whole run makes each access a single copy. On NEON that is `ld2`, `ld3` or `ld4` and `st2`, `st3` or `st4`. A run that crosses the end of the span reads zero past it and writes nothing there, one lane at a time. The same layout change written as rounds of `deinterleave` or a stride-three `swizzle` costs several shuffles, where the load instruction does it for free.

## Table lookups

`value:swizzle(indices)` reads lane `indices[i]` of `value` into lane `i`, and zero where the index is outside `1..lanes`. A small table is a vector, so a lookup is one swizzle. Up to three more vectors continue the run of lanes: an index in `lanes+1..2*lanes` reads the second, and so on through the fourth. A sixty-four-byte alphabet on a sixteen-lane byte species is four table vectors and one lookup:

```nupp
local t0 = species:load(alphabet, 1)
local t1 = species:load(alphabet, species.lanes + 1)
local t2 = species:load(alphabet, 2 * species.lanes + 1)
local t3 = species:load(alphabet, 3 * species.lanes + 1)
local symbols = t0:swizzle(sextets + 1, t1, t2, t3)
```

On NEON a byte lookup over one to four tables is a single table instruction. A wider species holds the same table in fewer vectors, and loads past its end read zero. An index a lane cannot hold, past 255 for bytes, is not reachable.

## Reductions

`simd.reducer` names the numerical contract. Scalar contributions remain scalar; vector contributions pass a matching mask inside one `do` region. Finalize once after that region.

```nupp
if species = simd.species(array.number) then
    local total = simd.reducer.pairwiseSum(0.0)
    do
        local cursor: uint32 = 0
        while cursor < #values do
            local active = species:tail(#values - cursor)
            total:add(species:load(values, cursor + 1, active), active)
            cursor = cursor + species.lanes
        end
    end
    return total:value()
end
local total = simd.reducer.pairwiseSum(0.0)
for i = 1, #values do total:add(values[i]) end
return total:value()
```

Ordered, pairwise, algebraic, compensated, exact integer, predicate, and extrema reducers have distinct contracts. Choose the contract before choosing a vector loop. Ordered and exact contracts preserve their specified operation order, ties, NaNs, signed zeros, and logical positions; algebraic reductions permit the documented reassociation. See [numeric semantics](numeric-semantics.md).

## Fields and column storage

A field load from a span of structs reads strided memory. If hot fields live in `nupp.mem.soa` column storage, an explicit load from a row view selects a contiguous column instead:

```nupp
local x = species:load(rows, cursor + 1, "x", active)
local velocity = species:load(rows, cursor + 1, "velocity", active)
species:store(rows, cursor + 1, "x", x + velocity * dt, active)
```

A writable row view supplies exclusive ownership; sibling column pointers retain their disjointness proof as `noalias` in the generated code. The row view's count bounds every column, including a slice. Whole-row vector values, dynamic field selection, and construction of a row view inside a native kernel remain unsupported. See [structure of arrays](../../runtime/data/structure-of-arrays.md).

## Targets and portability

Preferred species resolve per artifact tier. Fixed species keep their logical lane count while native legalization chooses the representation. Wasm SIMD128 and native CPU tiers use the same source-level vector and mask operations; GPU invocations are a separate execution model.

`aotFeatures` chooses the tiers an artifact ships and can raise its minimum when its source requires SIMD. A tier without usable vectors makes `simd.species` return `nil`; an asserted species is rejected. Windows x86-64 limits physical vector width to its frame-safe 16 bytes even when a wider tier is selected.
