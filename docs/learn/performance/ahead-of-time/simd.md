---
order: 633
---

# AOT SIMD

AOT code runs in vector lanes through explicit `nupp.simd` operations. A loop written without them is a scalar loop, whatever LLVM later makes of it.

```nupp
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function scale(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>, factor: float): nil
    assert(#output == #input, "length mismatch")
    local species = simd.species(array.float)
    for at, active in species:over(#input) do
        species:store(output, at, species:load(input, at, active) * factor, active)
    end
end
```

`simd.species(array.float)` is the species for the element, and there always is one: as wide as the target's vector registers where it has them, and one lane wide where it has none. `species:over(#input)` visits the span a chunk at a time, binding `at` to the chunk's one-based offset and `active` to its mask. Every chunk but the last is full, and a load or store under its mask is the unmasked access the loop's own bound proves, so the main loop pays no per-lane check; the last chunk's mask is the tail. Written this way the kernel is the whole algorithm. There is no second loop for the remainder and no scalar continuation, and the same source runs on a tier without vectors, and as ordinary Lua with AOT off, one lane at a time.

## Loops

Pass `active` to every load and store under `over`, and to every reducer contribution; the full chunks drop it and the tail keeps it. The offset `at` is a `uint32`, so index arithmetic on it stays at that width.

A kernel that wants to spell the loops out keeps the full-vector guard and the tail as separate statements. The guard `cursor + species.lanes <= #input` makes the main loop's accesses safe without per-lane bounds checks, and only the final partial group uses a mask:

```nupp:fragment
local cursor: uint32 = 0
while cursor + species.lanes <= #input do
    species:store(output, cursor + 1, species:load(input, cursor + 1) * factor)
    cursor = cursor + species.lanes
end
if cursor < #input then
    local active = species:tail(#input - cursor)
    species:store(output, cursor + 1, species:load(input, cursor + 1, active) * factor, active)
end
```

A kernel that wants a hand-written scalar loop where there are no vectors, because the one-lane species runs slower than plain Lua when AOT is off, asks `simd.vectors` instead. It answers the species where the running code has vector registers and nil where it does not, and the test against nil is decided per tier at compile time, so the vector branch is pruned where it cannot run:

```nupp:fragment
if species = simd.vectors(array.float) then
    for at, active in species:over(#input) do
        species:store(output, at, species:load(input, at, active) * factor, active)
    end
else
    for i = 1, #input do output[i] = input[i] * factor end
end
```

An early exit leaves the loop the way any loop is left. The first byte equal to `needle`, or zero:

```nupp:fragment
local species = simd.species(array.uint8)
for at, active in species:over(#text) do
    local hit = (species:load(text, at, active) == needle) & active
    if hit:any() then return at + hit:first() - 1 end
end
return 0
```

## Inspecting generated code

Use `nupp aot --emit llvm FILE` to inspect the LLVM IR and `nupp aot --emit asm --function NAME FILE` to inspect the selected machine code. Benchmark the complete exported function, including setup, tails, and reducer finalization, against its scalar form before committing to the vector one.

## Species, masks, and tails

`simd.species(array.float)` selects the preferred species for the target tier. Prefer it when source need not prescribe a logical lane count. `simd.species(array.float, 4)` asks for four lanes on every target; the backend may implement that value in multiple native registers. The lane count is decided when the function is lowered, once per artifact tier, and `species.lanes` reads it.

Vector comparisons produce masks. `mask:any()` tests for an active lane, `mask:first()` finds its first position, and `mask:select(yes, no)` chooses values lane by lane. `species:tail(remaining)` activates only lanes backed by remaining elements, which is the mask `over` binds for its last chunk. Pass that mask to both a partial load and its store. Unmasked loads and stores need a dominating full-width bound. A bound on `#input` also covers `output` when the leading guards hold `output` no shorter, as `assert(#output == #input)` does in the example above.

For a divergent algorithm, keep a live mask, update only its active lanes with `select`, and continue while `live:any()`. The source states the control flow that runs in lanes; nothing else runs in lanes.

For a filter, count selected lanes before compressing them. The output cursor
advances by the count, not by the species width:

```nupp:fragment
local selected = value > threshold
local kept = selected:count()
local packed = value:compress(selected)
species:store(output, written + 1, packed, species:tail(kept))
written = written + kept
```

In a divergent loop, a mask is also the lifetime of unfinished lanes:

```nupp:fragment
while live:any() do
    local next = value * 0.5
    value = live:select(next, value)
    live = live & (value > 1.0)
end
```

## Interleaved records

Records of two to four elements stored one after another, like pixels or the bytes of a Base64 group, load a field to a vector with `species:loadPairs`, `loadTriples` or `loadQuads`. Each one reads the next `ways * lanes` elements and gives vector `j` elements `j`, `j + ways`, and so on. `storePairs`, `storeTriples` and `storeQuads` do the reverse. The results can only initialize locals:

```nupp:fragment
while at + 3 * species.lanes <= #rgb and out + 4 * species.lanes <= #rgba do
    local r, g, b = species:loadTriples(rgb, at + 1)
    species:storeQuads(rgba, out + 1, r, g, b, species:splat(255))
    at = at + 3 * species.lanes
    out = out + 4 * species.lanes
end
```

A guard for the whole run makes each access a single copy. On NEON that is `ld2`, `ld3` or `ld4` and `st2`, `st3` or `st4`. A run that crosses the end of the span reads zero past it and writes nothing there, one lane at a time. The same layout change written as rounds of `deinterleave` or a stride-three `swizzle` costs several shuffles, where the load instruction does it for free.

## Wider lanes and the last lane

A byte kernel often needs more than a byte for its arithmetic. Grey from RGB weights three bytes and sums them in sixteen bits, and the sum wants every lane the byte register holds: on a 128-bit tier a `uint8` species has sixteen lanes where a `uint16` one has eight. `species:widen(array.uint16)` is the `uint16` species with the receiver's lane count, whatever the tier makes it, so the kernel never names a register width. Its vectors take two native registers, the way a `Fixed<N>` species past one register does, and `convert` moves lanes between the two species because their counts agree:

```nupp
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function grey(exclusive out: span.WriteSpan<uint8>, borrows rgb: span.Span<uint8>): integer
    local bytes = assert(simd.species(array.uint8))
    local wide = bytes:widen(array.uint16)
    local at: uint32 = 0
    local written: uint32 = 0
    while at + 3 * bytes.lanes <= #rgb and written + bytes.lanes <= #out do
        local r, g, b = bytes:loadTriples(rgb, at + 1)
        local sum = wide:convert(r) * 77 + wide:convert(g) * 150 + wide:convert(b) * 29
        bytes:store(out, written + 1, bytes:convert(sum >> 8))
        at = at + 3 * bytes.lanes
        written = written + bytes.lanes
    end
    if written < #out then
        local r, g, b = bytes:loadTriples(rgb, at + 1)
        local sum = wide:convert(r) * 77 + wide:convert(g) * 150 + wide:convert(b) * 29
        bytes:store(out, written + 1, bytes:convert(sum >> 8), bytes:tail(#out - written))
    end
    return #out
end
```

On NEON the loop is `ld3`, widening multiplies and multiply-accumulates, a shift and a narrowing store. `narrow` is the inverse: a widened species narrows back to the one it came from, and a preferred species narrows to one with half the lanes the narrower element's own register holds. The ladder is `uint8`, `uint16`, `uint32`, `uint64`, the same for signed integers, and `float` to `number`; a step is the next element of the same signedness, nothing is wider than 64 bits or narrower than 8, and a witness that is not the next step is refused where the function is lowered.

`convert` and `reinterpret` keep their rules across such a pair. A conversion needs the lane counts to agree, which `widen` guarantees; a reinterpretation also needs the element widths to agree, so between a species and its `widen` the word is `convert`, and between two species of one width either is:

```nupp:fragment
local floats = assert(simd.species(array.float))
local doubles = floats:widen(array.number)
local precise = doubles:convert(floats:load(input, at + 1))      -- fpext, lane for lane
local words = assert(simd.species(array.uint32)):reinterpret(floats:load(input, at + 1))
local rounded = floats:convert(precise)                           -- fptrunc, back to the same lanes
```

At the checker a widened species keeps the receiver's species identity, so `wide` above is a `simd.Species<uint16, simd.Preferred>`, the same type `simd.species(array.uint16)` has. They are different species once the function is lowered, one with the lane count of a `uint8` register and the other with its own, and a vector of one meets a vector of the other only through `convert`.

A lane index is decided where the function is lowered, so it may be the species' lane count or arithmetic on it, not only a literal: `sums:extract(species.lanes)` is the last lane of any species, and `species.lanes - 1` the one before it. A prefix scan carries its last lane into the next vector without a `Fixed<N>` species chosen for the sake of writing `extract(N)`:

```nupp
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function prefix(exclusive out: span.WriteSpan<uint32>, borrows input: span.Span<uint32>): integer
    assert(#out == #input, "one sum per input")
    local s = assert(simd.species(array.uint32))
    local carry = s:splat(0)
    local cursor: uint32 = 0
    while cursor + s.lanes <= #input do
        local sums = s:load(input, cursor + 1):orderedPrefixSum() + carry
        s:store(out, cursor + 1, sums)
        carry = s:splat(sums:extract(s.lanes))
        cursor = cursor + s.lanes
    end
    if cursor < #input then
        local rest = s:tail(#input - cursor)
        local sums = s:load(input, cursor + 1, rest):orderedPrefixSum() + carry
        s:store(out, cursor + 1, sums, rest)
    end
    return #input
end
```

An index past the lanes the tier gives the species is refused with its position, as a literal past them always was, and so is one no tier can fold, such as a parameter. `insert` and `align`'s offset take the same indices.

## Table lookups

`value:swizzle(indices)` reads lane `indices[i]` of `value` into lane `i`, and zero where the index is outside `1..lanes`. A small table is a vector, so a lookup is one swizzle. Up to three more vectors continue the run of lanes: an index in `lanes+1..2*lanes` reads the second, and so on through the fourth. A sixty-four-byte alphabet on a sixteen-lane byte species is four table vectors and one lookup:

```nupp:fragment
local t0 = species:load(alphabet, 1)
local t1 = species:load(alphabet, species.lanes + 1)
local t2 = species:load(alphabet, 2 * species.lanes + 1)
local t3 = species:load(alphabet, 3 * species.lanes + 1)
local symbols = t0:swizzle(sextets + 1, t1, t2, t3)
```

On NEON a byte lookup over one to four tables is a single table instruction. A wider species holds the same table in fewer vectors, and loads past its end read zero. An index a lane cannot hold, past 255 for bytes, is not reachable.

## Reductions

`simd.reducer` names the numerical contract. Contributions pass the chunk's mask, and the loop is the reducer's region; finalize once after it.

```nupp:fragment
local species = simd.species(array.number)
local total = simd.reducer.algebraicSum(0.0)
for at, active in species:over(#values) do
    total:add(species:load(values, at, active), active)
end
return total:value()
```

Written as separate loops, the vector contributions pass a matching mask inside one `do` region, and scalar contributions remain scalar.

Every reducer contributes through `add`, a dot product taking two values, and answers once through `value`; `simd.Reducer<T>` names that shared shape for code that only finishes a reduction. The algebraic contracts are the fast ones: they let the lanes accumulate in registers and reduce once at the end. The pairwise contracts keep the adjacent-pair tree of the whole sequence, which costs a small buffer of partial sums beside the loop, and the ordered ones fold one lane at a time. Reach for pairwise or ordered when the association is part of the answer, and for algebraic otherwise. An integer reducer names its element with an array witness, as a species does, because an `int32` and a `uint32` are the same Lua number: `simd.reducer.wrappingSum(array.int32, seed)`, `simd.reducer.integerArgMin(array.uint64)`. Ordered, pairwise, algebraic, compensated, exact integer, predicate, and extrema reducers have distinct contracts. Choose the contract before choosing a vector loop. Ordered and exact contracts preserve their specified operation order, ties, NaNs, signed zeros, and logical positions; algebraic reductions permit the documented reassociation. See [numeric semantics](numeric-semantics.md).

## Fields and column storage

A field load from a span of structs reads strided memory. If hot fields live in `nupp.mem.soa` column storage, an explicit load from a row view selects a contiguous column instead:

```nupp:fragment
local x = species:load(rows, cursor + 1, "x", active)
local velocity = species:load(rows, cursor + 1, "velocity", active)
species:store(rows, cursor + 1, "x", x + velocity * dt, active)
```

A writable row view supplies exclusive ownership; sibling column pointers retain their disjointness proof as `noalias` in the generated code. The row view's count bounds every column, including a slice. Whole-row vector values, dynamic field selection, and construction of a row view inside a native kernel remain unsupported. See [structure of arrays](../../runtime/data/structure-of-arrays.md).

## Targets and portability

Preferred species resolve per artifact tier. Fixed species keep their logical lane count while native legalization chooses the representation. Wasm SIMD128 and native CPU tiers use the same source-level vector and mask operations; GPU invocations are a separate execution model.

`aotFeatures` chooses the tiers an artifact ships and can raise its minimum when its source requires SIMD. On a tier without vector registers `simd.species` is one lane wide and `simd.vectors` is nil, where an assert of it is rejected at compile time. Windows x86-64 limits physical vector width to its frame-safe 16 bytes even when a wider tier is selected.
