---
order: 634
---

# AOT numeric semantics

AOT arithmetic preserves the observable guarantees of ordinary Nupp unless the
source opts into a named relaxation. Verification checks the lowered IR before
any target-specific code is produced.

```nupp
@aot
local function add(left: float, right: float): float
    return nupp.math.f32.add(left, right)
end
```

| Written | Computed as | Notes |
| --- | --- | --- |
| `a + b` on numbers | binary64 | not contracted, not reassociated |
| a `float` field read | binary64 | the physical load widens |
| a `float` field write | binary32 | the physical store narrows |
| `nupp.math.f32.add(a, b)` | binary32, one rounding | exact, see below |
| `nupp.math.f32.min`/`max`/`fma` | binary32, corrected | a helper repairs NaN behavior |
| `nupp.math.i32.add(a, b)` | wrapping int32 | wraps in unsigned, comes back |
| `nupp.math.u32.add(a, b)` | wrapping uint32 | native unsigned modular arithmetic |
| `int32` `+`, `-`, `*` on established operands | wrapping int32 | what `nupp.math.i32.add` and its siblings answer, see below |
| `uint32` `+`, `-`, `*` on established operands | wrapping uint32 | what `nupp.math.u32.add` and its siblings answer |
| `int64` `+`, `-`, `*` in AOT | wrapping int64 | operates as uint64, then converts back |
| `uint64` `+`, `-`, `*` in AOT | wrapping uint64 | native unsigned modular arithmetic |
| 64-bit `/`, `%` in AOT | truncating integer division | LuaJIT's cdata answer for a zero divisor |
| 64-bit `^`, unary `-` in AOT | wrapping integer power, negation | as LuaJIT's cdata |
| a `number` stored into an integer field | truncated through int64 | the FFI store's rule, not `wrap` |

Numeric `for` loops evaluate their start and stop once, in source order, before
entering the loop. Assigning the visible loop variable does not change the next
iteration. CPU AOT preserves this behavior for the admitted implicit step of
one, including signed counter limits, `uint32` bounds and binary64 bounds.
Explicit steps remain a positioned refusal. A loop whose index is assigned
must use a separately proved cursor for span access. GPU counted loops retain
their [narrower signed-int32 contract](gpu.md). Loop entry also matches
the selected runtime. The pinned ARM64 LuaJIT uses dual numbers: a negative-zero
start becomes positive zero when the limit is exactly representable as `int32`;
other limits retain its sign. The pinned x86/x64 LuaJIT uses single numbers and
retains that sign. Same-host builds observe the local
LuaJIT mode, including custom dual-number x64 builds, and include it in the AOT
cache key. Native counted-loop artifacts check that mode before binding and
refuse to load into an incompatible LuaJIT; this does not silently fall back.

Ordinary `math.min` and `math.max` follow LuaJIT, which chooses the second
operand on ties or unordered comparisons. Variadic calls apply that rule from left to right.
The corrected `nupp.math.f32` operations have their own target-independent
contract below. `math.log(value, base)` honors its optional base. Under LuaJIT,
ordinary code and AOT both compute `log2(value) * (1 / log2(base))`, keeping
the two roundings apart as LuaJIT does; a quotient of natural logarithms
differs in the last bits and loses exact answers such as
`math.log(1e17, 0.1) == -17`.

`a % b` is Lua's floored modulo, `a - floor(a / b) * b`, computed operation for
operation and never contracted. It is not `fmod` moved into the divisor's sign:
the two differ on the sign of a zero result (`-5 % 5` is `+0`), on an infinite
divisor (Lua answers NaN), and wherever `a / b` rounds (`1 % 0.1`).

Ordinary floating-point arithmetic assumes round-to-nearest-even. Signed zero
and numeric NaN behavior are preserved. NaN signaling state, payload bits, and
floating-point exception flags are not observable guarantees. The bit-level
surface of `nupp.math.f32`, including its canonical NaN behavior, retains the
stronger guarantees described below.

Signed wrapping arithmetic operates on the two's-complement bits and wraps.
The integer instructions it lowers to claim no signed overflow, so an
overflowing `int32` or `int64` result is defined rather than undefined.

`+`, `-` and `*` between two operands established at one fixed width mean the
wrapping operation of that width, in an `@aot` body and in the ordinary code
around it alike: an `int32` accumulator plus an `int32` field read is the
`nupp.math.i32.add` of the two, a `uint32` cursor times a literal is the
`nupp.math.u32.mul`, and the checker annotates the operator so the retained
Lua body and the native lowering compute the same bits. One operand has to be
typed at the width and both established at it, so an erased `as int32` or a
plain `integer` beside one still answers `integer`, which an assignment to the
width then refuses. A `uint8` or `uint16` element read is typed `uint32` but is
established at `int32` as well, since it holds one; inside an `@aot` body an
`int32` beside it takes the signed reading, so `carry = carry + bytes[i]` on an
`int32` carry wraps as the signed add and needs no `wrap`. Division, `%`, `^`
and unary `-` keep today's rules and answer a number.

A comparison between a signed and an unsigned 32-bit integer answers by
mathematical value, as the two Lua numbers they are do: generated code widens
both before comparing, so `-1` stays below `5`. A binary32 value or a `number`
meeting a 32-bit integer compares in binary64, which holds both exactly.

A 64-bit integer is LuaJIT cdata, and LuaJIT compares and computes with cdata
by C's rules, so generated code does the same. The other operand converts to
the 64-bit type, to `uint64` if either side is one: `-1LL < 5ULL` is false,
`-1LL == 0xffffffffffffffffULL` is true, and `1LL < 1.5` compares 1 with 1.
A `number` converts as a store does, below. `/` and `%` are C's truncating
division, and where C has no answer LuaJIT has one: a zero divisor gives
`INT64_MIN` (2^63 for `uint64`), and so does `INT64_MIN / -1`, whose remainder
is 0. `^` is an integer power and unary `-` wraps.

A `number` stored into an integer field or span element converts as LuaJIT's
FFI store does, which is not `wrap`: it truncates toward zero through `int64`
and keeps the low bits, so storing `1.9` gives 1 and `-1.9` gives -1 at every
width, and `4294967303.5` stored into an `int32` gives 7. A `uint64`
destination takes the union of both 64-bit ranges, so a negative value keeps
its two's-complement pattern. `nupp.math.i32.wrap` and `u32.wrap` are LuaJIT's
`tobit` instead, and round to nearest. NaN, infinities and values outside
those ranges convert to target-dependent integers.

The binary32 operations lower to native single-precision instructions, and this
is exact rather than a relaxation: a binary32 operation over binary32 operands
computed in binary64 and rounded once is bit-identical to the native
instruction, because 53 ≥ 2 × 24 + 2.

`min`, `max` and `fma` are not covered by that argument. A differential over
every interesting binary32 value found they disagree with `fminf`, `fmaxf` and
`fmaf` in exactly one respect each: `nupp.math.f32` canonicalizes every NaN
where the instruction propagates a payload, and `min` and `max` return that
canonical NaN where IEEE `minNum` returns the operand that is not NaN. Both are
repaired by a select, so they are admitted with a correction rather than left
out.

`nupp.math.f32.exp` is instead defined by the scalar IR itself: clamp the input
to `[-104, 88]`, evaluate a degree-12 Taylor polynomial for `exp(x / 128)` in
Horner order with `fma`, then square seven times. The interpreter, native code,
Wasm, and SPIR-V execute that same binary32 sequence; WGPU translates the canonical
module for the selected native backend, and none asks a platform math library
to choose a result.

A width changes only at a conversion the IR writes down. An operator never
changes one, which is what keeps `float` a storage fact rather than an
arithmetic type:

::: code-group
```nupp:fragment [Nupp]
local wide = inputs[i].value
local doubled = wide + wide
local narrow = nupp.math.f32.add(nupp.math.f32.narrow(wide), nupp.math.f32.narrow(wide))
outputs[i].value = narrow + doubled
```

```llvm [LLVM IR]
%wide = fpext float %value to double
%doubled = fadd double %wide, %wide
%a = fptrunc double %wide to float
%b = fptrunc double %wide to float
%narrow = fadd float %a, %b
%promoted = fpext float %narrow to double
%sum = fadd double %promoted, %doubled
%stored = fptrunc double %sum to float
```
:::

Every cast there answers to something the source said: the load widens, the
store narrows, `narrow` asks for binary32 twice and gets one single-precision
add, and adding it back to a binary64 promotes it rather than narrowing the
other operand.

An entry conversion takes a binary64, so an `int32` or `uint32` reaching one --
a counted-loop index handed to `nupp.math.u32.wrap`, say -- is promoted to
binary64 first, and that promotion is written down like any other. It is exact
for every 32-bit integer and establishes nothing: the conversion it is an
argument to is what establishes. Nothing narrows on the way in, so an operand
the source never established is still refused.

`nupp.math.u32.fromI32`, `nupp.math.i32.fromU32` and `nupp.math.u32.toI32` are
the exceptions, and are the ones to reach for between the two views of the same
thirty-two bits. They take the width they convert from rather than a binary64,
so nothing is promoted and nothing comes back: the emitted cast reinterprets
the bits it was already given. Going through `wrap` instead means a round trip
out to binary64 for a pattern that never left thirty-two, which is both slower
and narrower -- a value at or above 2^31 does not survive it.

A bitwise operator needs neither. Established `uint32` operands keep their
unsigned range through `&`, `|`, `~`, `<<`, `>>`, and unary `~`; an exact
in-range literal can supply the other operand. The ordinary Lua and native
routes agree, including results with bit 31 set. Established signed or mixed
operands retain the signed `int32` result. Arithmetic right shift remains
signed. Nothing has to be wrapped back to the width it never left:

```nupp
local function choose(e: int32, f: int32, g: int32): int32
    return (e & f) ~ ((~e) & g)
end
```

An exact integer literal is admitted anywhere a fixed-width value is, including
a shift count, a helper argument and the bound a cursor is compared against.
That last one is why a counted loop compares in its own width rather than
converting to binary64 to meet its bound.

## Explicit SIMD conversions

The destination species selects the numeric type: `integers:convert(values)`
converts each lane; `integers:reinterpret(values)` preserves each lane's bits.
Both require equal logical lane counts. Reinterpretation also requires equal
element widths. Use `Fixed<N>` when changing element width: preferred species
of different element widths have different lane counts.

Numeric conversion follows LuaJIT FFI rules, not saturating conversion:

- Integer narrowing keeps the low bits; widening extends the source value.
- Float-to-integer truncates toward zero through `int64`, then narrows. Thus
  `4294967296` converted to an `int32` lane becomes `0`, not `2147483647`.
- Float-to-`uint64` accepts the union of the signed and unsigned 64-bit ranges;
  negative signed-range values retain their two's-complement representation.
- Integer-to-floating conversion goes through double, including the possible
  double rounding of a 64-bit integer converted to `float`.

NaN, infinities, and float inputs outside the conversion's supported range
produce unspecified target-dependent integer values, never undefined behavior.
Do not use those values as a portable overflow test. This does not promise the
same exceptional integer that a particular LuaJIT build happens to return.

Conversions lower to vector operations, with target-dependent instruction
counts; some targets must decompose 64-bit conversions. The generated code
guards floating inputs before any potentially undefined integer conversion.
Reinterpretation does no numeric work and preserves NaN payloads and signed
zero as bits.

## Reducer contributions

A `simd.reducer` takes scalar contributions and masked vector contributions in
any mix, and the contract sees them in program order: a masked vector
contribution is its active lanes in ascending lane order, and a scalar one is
one more value at the point it is written. Every masked contribution belongs to
one `do` block, the reducer's region; scalar contributions may precede the
region, follow it, or sit inside it between vector contributions. An ordinary
kernel therefore declares one reducer for its vector loop and its scalar
continuation together:

```nupp:fragment
local total = simd.reducer.orderedSum(0.0)
do
    while cursor + species.lanes <= #values do
        total:add(species:load(values, cursor + 1), species:mask(true))
        cursor = cursor + species.lanes
    end
end
while cursor < #values do
    total:add(values[cursor + 1])
    cursor = cursor + 1
end
return total:value()
```

What program order means is the contract's own: an ordered contract folds the
scalar into its running value where it is written; a pairwise contract takes it
as one more leaf of the adjacent-pair tree, after the leaves the vectors before
it contributed; a compensated sum carries its correction across both kinds; the
extrema compare it against the running extreme. The algebraic and exact
contracts, which permit reassociation or are exact, may hold the region's
vector contributions in a lane-wise accumulator and fold it in when the region
ends, so a scalar written inside such a region associates with the accumulated
lanes rather than between them -- an association the contract already admits.

A floating-point reducer accumulates in the element its constructor names.
`orderedSum(initial)` is binary64; `orderedSum(array.float, initial)` is
binary32 under every contract, rounding after every operation as
`nupp.math.f32` does: an ordered binary32 sum rounds after every lane, a
pairwise one at every node of the tree, a compensated one keeps its total and
its compensation in binary32, a dot rounds each product before adding it (or
fuses the two under the algebraic contract), and the extrema round nothing. The
initial value is rounded to the element. `value()` answers that element, so a
`float` kernel finishes in `float` without a conversion it did not write.

## Verification

The reducer corpus in `tests/simd/reducers.lua` runs through the same native and
Wasm harness as the explicit primitive corpus. Ordered and compensated folds
match ordinary Nupp, including signed zero. Pairwise folds also match an
independent level-by-level adjacent-pair tree, including unpaired leaves. The
seed is the first leaf: seven leaves combine as `block4 + (block2 + leaf1)`,
not `(block4 + block2) + leaf1`. Integer wrapping, bitwise, predicate, extremum,
and first-position contracts are exact. NaNs compare by the observable policy
above, not by unspecified payload bits. Explicit vector reducer probes
cover Fixed2 through Fixed64 and Preferred with two complete groups and every
tail, including positive-only holes and all-false masks. Authored reducers retain their
one-unconditional-contribution rule. Predicate reducers take their truth as a mask, and arg-position reducers expose
scalar contributions only. A mixed
corpus feeds one reducer the seed as a scalar, whole vectors inside a region
and the remaining elements as scalars, at two fixed widths, and compares it
against the same contributions made one at a time. Every floating contract runs
twice, over `number` and over the `float` witness, the latter against a
binary32 reference built from `nupp.math.f32`.

Algebraic checks use a different contract. For finite inputs whose intermediate
values neither overflow nor underflow, the corpus compares two rounded paths
with `gamma(4n + 4) = (4n + 4)u / (1 - (4n + 4)u)`, where `u` is `2^-24` for
binary32 and `2^-53` for binary64, and `n` counts the seed among the
contributions where it is one. The absolute envelope scales by the sum of
absolute contributing inputs for a sum, the sum of absolute contributing
products for a dot, and the absolute reference result for a product. One smallest subnormal accommodates
the final boundary. This is a comparison envelope, not a promise of one
association or one target's low bits.

Separate exceptional fixtures check NaN propagation, infinities, signed zeros,
empty seeds and first-index ties. Those fixtures select cases where association
cannot change the expected classification; a reassociation that overflows an
intermediate is not silently compared as a small finite rounding error.

The generated code is a backend representation and not the safety boundary. Every span
access, region relationship, conversion and lane operation is verified in the IR
before anything is emitted, so a rewrite that produced something invalid is a
compiler bug caught before it becomes a miscompilation.

Two rules do most of the work. Every load, store and element reference indexes
the loop counter and nothing else, which is both the argument that an access is
in bounds and the license to run several iterations at once. And the alias
matrix is required complete rather than merely consistent: every pair of span
regions carries a fact, because a pair with no fact would be a `restrict` nobody
justified.

Above that sit the differentials, which establish correctness. Explicit SIMD
primitives and algorithms run through native vector code and a forced-scalar
twin, alongside independent scalar expectations appropriate to each numerical
contract. Scalar code runs against ordinary Lua over boundary operands, built
once with `aot = "off"` and once with `require`, with the JIT off on the
reference side:

```bash
./bin/nupp test simdprimitivedifferentialtest
./bin/nupp test simdreducerdifferentialtest
./bin/nupp test aotdifferentialtest
```

Tails are exercised across supported fixed and preferred species.

The forced-scalar version of an explicit vector body is the same body left as
written and compiled with the optimizer off (`optnone`), which makes it an
independent executable answer. It carries the same floating-point flags as the
source, so its last bits agree with the specified operation order.

The unoptimized oracle is not a speed baseline. Compare complete optimized functions
when measuring performance, not the forced-scalar conformance route.

The exact reducer contracts are also executed at the one other tier that can
run them. `tests/wasm-aot/simd-project` reduces the same corpus at Wasm
`simd128` against the same Lua reducers, so bit identity for an ordered chain or
a logical-index tree is a claim about the contract rather than about NEON.

The SIMD conformance matrix runs the authored vector corpus on native targets
and Wasm `simd128`, with each native tier selected explicitly.

The build's own end of it is exercised the same way, by doing the thing rather
than asserting it: a project is built under `require` and its answers compared
against the same project built with `aot = "off"`, an output tree is copied
elsewhere and run from a third directory, a cross build's object is inspected to
confirm it is the other machine's, and a stamped binary is run from `/` to
confirm it finds the library it was given.

## Scalar switch expressions and do blocks

The scalar subset admits a
[switch](../../language/switch-expressions.md) in expression positions, including
initializers, assignments, arguments, return values, and loop conditions, when:

- the selector is `number`, `float`, `int32`, `uint32`, `boolean`, `string`, or statically known nil;
- every case is a static primitive value;
- each completing arm produces an admitted scalar value; and
- the checker has proved the switch exhaustive, either from its cases or an
  `else` arm; and
- no case carries a
  [`where` guard](../../language/switch-expressions.md#guarded-cases), which
  the native lowering refuses outright rather than commit to an arm whose
  predicate it never evaluated.

```nupp
local span = require("nupp.mem.span")

local struct Code
    value: int32
end

@aot
local function classify(
    exclusive output: span.WriteSpan<Code>,
    borrows input: span.Span<Code>
): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #output do
        local code = input[i].value
        local result: int32 = switch code do
            case -2147483648 -> 10
            case 1, 2 -> 20
            else -> 30
        end
        output[i].value = result
    end
end
```

It lowers to one selector `Let`, one result `Let`, an ordered scalar-IR `If`,
and branch `Assign` operations. An established `int32` or `uint32` selector
with integer cases in its range compares in its own width, one `icmp eq` per
case, and the code generator chooses the physical dispatch: a jump, a native
`switch`, or, in the map above, lane-wise selects. Nupp `integer` is normally
binary64, so those selectors deliberately remain binary64 equality branches
rather than being converted. String selectors use the existing Lua-string AOT interface: the
selector is evaluated once and rooted, then each case compares its byte length
and contents with the literal. Comparisons preserve embedded NUL bytes, do not
allocate case strings, and use byte equality rather than locale rules. Type
patterns still report the ordinary subset boundary.
Block arms use ordinary branches so that `break` still targets the authored
loop. The code generator chooses the physical native dispatch; Nupp does not
force a jump table or synthesize a perfect hash.

A [do expression](../../language/do-expressions.md) may contain locals, branches,
and supported loops. `yield` supplies its result and exits the nearest value
block, including through nested loops. `return` exits the AOT function, while
`break` and `continue` keep their authored loop targets.

```nupp
@aot
local function classify(value: number): number
    return do
        if value < 0 then return -1 end
        yield switch value do
            case 0 -> 0
            else -> do
                local doubled = value * 2
                yield doubled + 1
            end
        end
    end
end
```

Lowering preserves left-to-right operand evaluation and conditional execution
in boolean `and`/`or` and ternaries. A loop condition's statements execute on
every condition test, including the test reached by `continue`. These blocks
compile to native locals and control flow without closures. Explicit SIMD
algorithms express lane-local control flow with masks and `select`; Nupp does
not convert scalar loop conditions into masks. A condition block's own `break`
or `continue` still targets its enclosing loop. GPU profiles do not admit
statementful loop conditions.
