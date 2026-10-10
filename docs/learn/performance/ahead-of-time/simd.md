---
order: 633
---

# AOT SIMD

AOT code runs in vector lanes through explicit `nupp.simd` operations. A loop written without them is a scalar loop, whatever LLVM later makes of it. This page is the reference. See [simd-programming.md](simd-programming.md) for the model it assumes.

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

On NEON, a species that fills one register packs by table lookup: the mask's bits index a table of `tbl` shuffles, so a compress is a load and one `tbl1`, or two for sixteen byte lanes, with no branch and no stack buffer. Other targets pack lane by lane through a buffer one lane longer than the vector.

In a divergent loop, a mask is also the lifetime of unfinished lanes:

```nupp:fragment
while live:any() do
    local next = value * 0.5
    value = live:select(next, value)
    live = live & (value > 1.0)
end
```

## Lane arithmetic

The arithmetic operators are Lua's, lane by lane. `%` and `//` are the floor remainder and the floor quotient: the remainder takes the divisor's sign and the quotient rounds toward negative infinity, as `a - floor(a / b) * b` and `floor(a / b)` on a floating species and exactly on an integer one. An integer lane divided by zero answers zero rather than trapping, as `/` does. A scalar on the right splats, so `bytes % 16` and `values // 3` read as they would on one value.

`math.sqrt(v)`, `math.abs(v)`, `math.floor(v)` and `math.ceil(v)` take a floating vector directly and answer one, lane by lane, exactly as `species:map(math.sqrt, v)` does; `map` remains the spelling for the rest of the closed math set and for a helper of your own. The operand is a local of the species, as it is for `map`.

`v:fma(b, c)` is `v * b + c` with one rounding per lane on a floating species: `nupp.math.f32.fma`'s contract on `float`, the binary64 fused operation on `number`. On an integer species, `v:saturatingAdd(o)` and `v:saturatingSub(o)` clamp to the element's range instead of wrapping, `v:popcount()` counts the one bits of each lane, and `v:mulHigh(o)` answers the high half of the full-width product, signed or unsigned as the element is: `*` and `mulHigh` together are the whole product, and `mulHigh` alone is the fixed-point multiply a scaled reciprocal turns a division into. The right operand of each may be a scalar.

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

On NEON the loop is `ld3`, widening multiplies and multiply-accumulates, a shift and a narrowing store. This kernel keeps its loops spelled out rather than taking `over`: `loadTriples` reads three vectors of input for one of output, and the bound that proves a run of three is the loop's own `at + 3 * bytes.lanes <= #rgb`, which an iterator over the output count cannot state. `narrow` is the inverse: a widened species narrows back to the one it came from, and a preferred species narrows to one with half the lanes the narrower element's own register holds. The ladder is `uint8`, `uint16`, `uint32`, `uint64`, the same for signed integers, and `float` to `number`; a step is the next element of the same signedness, nothing is wider than 64 bits or narrower than 8, and a witness that is not the next step is refused where the function is lowered.

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
    local s = simd.species(array.uint32)
    local carry = s:splat(0)
    for at, active in s:over(#input) do
        local sums = s:load(input, at, active):orderedPrefixSum() + carry
        s:store(out, at, sums, active)
        carry = s:splat(sums:extract(s.lanes))
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

`simd.reducer` names the numerical contract. Contributions pass the chunk's mask, and the loop is the reducer's region; scalar contributions go in wherever they are written, before, inside or after it, and the two mix freely in one reducer. Finalize once after the region.

```nupp:fragment
local species = simd.species(array.number)
local total = simd.reducer.algebraicSum(0.0)
for at, active in species:over(#values) do
    total:add(species:load(values, at, active), active)
end
return total:value()
```

Written as separate loops, the vector contributions pass a matching mask inside one `do` region, and scalar contributions remain scalar.

A kernel with a vector loop and a scalar continuation needs one reducer, not two: whole vectors contribute inside the region and the remaining elements contribute as scalars after it, in program order.

```nupp:fragment
local low = simd.reducer.propagatingMin(array.float, math.huge)
local where = simd.reducer.propagatingArgMin(array.float)
local cursor: uint32 = 0
do
    while cursor + species.lanes <= #values do
        local v = species:load(values, cursor + 1)
        low:add(v, species:mask(true))
        where:add(v, species:mask(true))
        cursor = cursor + species.lanes
    end
end
while cursor < #values do
    low:add(values[cursor + 1])
    where:add(values[cursor + 1])
    cursor = cursor + 1
end
return low:value(), where:value()
```

Every reducer contributes through `add`, a dot product taking two values, and answers once through `value`; `simd.Reducer<T>` names that shared shape for code that only finishes a reduction. An integer reducer names its element with an array witness, as a species does, because an `int32` and a `uint32` are the same Lua number: `simd.reducer.wrappingSum(array.int32, seed)`, `simd.reducer.integerArgMin(array.uint64)`. A floating-point reducer may name its element the same way: `simd.reducer.pairwiseSum(array.float, 0.0)` accumulates in binary32 and answers a `float`, where `pairwiseSum(0.0)` is binary64. The arg extrema take vectors too, each lane at its logical position, and the predicate reducers `any`, `all` and `count` take a mask of the lanes they test. Ordered, pairwise, algebraic, compensated, exact integer, predicate, and extrema reducers have distinct contracts. Choose the contract before choosing a vector loop. Ordered and exact contracts preserve their specified operation order, ties, NaNs, signed zeros, and logical positions; algebraic reductions permit the documented reassociation. See [numeric semantics](numeric-semantics.md).

`simd.horizontal` reduces one vector to one value under the same names: the floating orders `orderedSum`, `pairwiseSum`, `algebraicSum` and their product and dot forms over `float` and `number` lanes, the NaN-policy extrema over every element, and the integer contracts `wrappingSum`, `wrappingProduct`, `andBits`, `orBits`, `xorBits`, `integerMin` and `integerMax` over integer lanes, wrapping in the lane's own width. An integer prefix-sum carry is `simd.horizontal.wrappingSum(partial)`.

## Fields and column storage

A field load from a span of structs reads strided memory. If hot fields live in `nupp.mem.soa` column storage, an explicit load from a row view selects a contiguous column instead:

```nupp:fragment
local x = species:load(rows, cursor + 1, "x", active)
local velocity = species:load(rows, cursor + 1, "velocity", active)
species:store(rows, cursor + 1, "x", x + velocity * dt, active)
```

A writable row view supplies exclusive ownership; sibling column pointers retain their disjointness proof as `noalias` in the generated code. The row view's count bounds every column, including a slice. Whole-row vector values, dynamic field selection, and construction of a row view inside a native kernel remain unsupported. See [structure of arrays](../../runtime/data/structure-of-arrays.md).

## Native-only entries

An `@aot` function may take and answer vectors and masks. Such a function is **native-only**: a register holds the value, Lua has nothing to hand through the parameter or receive from the result, so the function is reached from other `@aot` functions and nothing else. It is compiled once as its own native function, and a call to it from another entry, in the same module or another, is a native call to its symbol.

```nupp
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function twice(value: simd.Vector<float, simd.Preferred>): simd.Vector<float, simd.Preferred>
    return value + value
end

@aot
local function positive(value: simd.Vector<float, simd.Preferred>): simd.Mask<float, simd.Preferred>
    return value > 0.0
end

@aot
local function apply(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>): nil
    assert(#output == #input, "length mismatch")
    local species = simd.species(array.float)
    for at, active in species:over(#input) do
        local value = species:load(input, at, active)
        species:store(output, at, positive(value):select(twice(value), species:splat(0.0)), active)
    end
end

return {twice = twice, positive = positive, apply = apply}
```

`nupp aot` reports `twice` and `positive` as `explicit simd, native-only`. The build gives neither a Lua wrapper: the declaration lowers to a stub that refuses a call, the function is not listed in `__nuppAotCompiled`, and `--emit binding` shows the stub where the foreign declaration would be. The module's export table still names the function, and another module imports it as it imports anything, because the native call resolves through the export without reading a Lua value. Under `aot = "off"` the function is ordinary Nupp, one lane wide, and callable.

Every use the checker can see that Lua would execute is refused where it is written, for a target whose policy compiles: a call outside an `@aot` function, an argument, a return, a store into a table. The export member and the import binding are the two references admitted. A check of a target whose `aot` policy compiles refuses the call inside `fromLua` below; under `aot = "off"` it is an ordinary call.

```nupp
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function twice(value: simd.Vector<float, simd.Preferred>): simd.Vector<float, simd.Preferred>
    return value + value
end

local function fromLua(): simd.Vector<float, simd.Preferred>
    return twice(simd.species(array.float):splat(1.0))
end

return {twice = twice, fromLua = fromLua}
```

The parameters and the result are values of the callee's own species: `Preferred` means the same lane count to the caller and the callee, because every unit of one artifact is compiled per tier, and a `Fixed<N>` wider than a register is the `<N x T>` the code generator legalizes. What the call promises is value semantics and one tier on both sides, not a register. A species or a reducer is neither: a species is a compile-time fact and a reducer is a region, so an entry cannot take or answer one, and a vector or mask is admitted only by native CPU AOT.

## Native-only aggregates

A `struct` may hold vectors and masks. Such a struct is a **native-only aggregate**: a value, as the vectors in it are, that exists inside `@aot` functions and nowhere else. It is constructed with `new`, its fields are read, and it is passed to and answered by native entries, including nested in another such struct. There is no field store: a change is a new aggregate.

```nupp
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

local struct Pair
    re: simd.Vector<float, simd.Preferred>
    im: simd.Vector<float, simd.Preferred>
end

@aot
local function square(z: Pair): Pair
    return new Pair(z.re * z.re - z.im * z.im, z.re * z.im + z.im * z.re)
end

@aot
local function squares(exclusive out: span.WriteSpan<float>, borrows re: span.Span<float>, borrows im: span.Span<float>): nil
    assert(#out == #re, "length mismatch")
    assert(#im == #re, "length mismatch")
    local species = simd.species(array.float)
    for at, active in species:over(#re) do
        local w = square(new Pair(species:load(re, at, active), species:load(im, at, active)))
        species:store(out, at, w.re + w.im, active)
    end
end

return {square = square, squares = squares, Pair = Pair}
```

The code generator lays the aggregate out as a literal struct of its fields' register types, `{ <4 x float>, <4 x float> }` here, and an entry that takes or answers one is native-only like an entry that takes a vector. A field may be a vector, a mask, a `number`, `float`, `boolean`, or 32- or 64-bit integer, or another native-only aggregate; the narrow storage integers are refused, because the aggregate is never storage. `Preferred` species are admitted, since the layout belongs to the tier the function is compiled for.

A native-only aggregate is kept out of memory and out of Lua. A span or array of one is refused where the span is declared, naming the field that makes the struct native-only. A Lua construction is refused under a target whose policy compiles, as a Lua call of a native-only entry is. A field assignment is refused everywhere, so the one-lane Lua form and the native form never disagree about who sees a write:

```nupp:refused
local simd = require("nupp.simd")

local struct Pair
    re: simd.Vector<float, simd.Preferred>
    im: simd.Vector<float, simd.Preferred>
end

@aot
local function conjugate(z: Pair): Pair
    z.im = -z.im
    return z
end

return {conjugate = conjugate, Pair = Pair}
```

Under `aot = "off"` the struct lowers to a C struct of one lane per vector field, a `float` for a `Vector<float, S>` and a `bool` for a mask, and every operation on it is the ordinary one.

### Storage layout

A struct that a span or array holds has a memory layout, which must not change with the CPU tier, so only a `Fixed<N>` vector could ever be a storage field, and none is admitted yet. The contract such a field would be laid out by is stated in the compiler's target layout model, per target: a vector's alignment is its payload rounded up to a power of two, capped at what the target's allocator guarantees, 16 bytes on every 64-bit target and on Wasm and 8 on i686; a payload that is not a power of two pads to that alignment, so `Fixed<3>` of `float` occupies 16 bytes with 4 of padding; a payload past the cap aligns to the cap and pads to a multiple of it. Admitting storage fields waits on a full-width `Fixed<N>` form for ordinary Lua, where a vector is one lane today and a field of N lanes has no representation to read into or write from.

## Targets and portability

Preferred species resolve per artifact tier. Fixed species keep their logical lane count while native legalization chooses the representation. Wasm SIMD128 and native CPU tiers use the same source-level vector and mask operations; GPU invocations are a separate execution model.

`aotFeatures` chooses the tiers an artifact ships and can raise its minimum when its source requires SIMD. On a tier without vector registers `simd.species` is one lane wide and `simd.vectors` is nil, where an assert of it is rejected at compile time. Windows x86-64 limits physical vector width to its frame-safe 16 bytes even when a wider tier is selected.
