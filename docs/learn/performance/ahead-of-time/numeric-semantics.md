---
order: 634
---

# AOT numeric semantics

AOT arithmetic preserves the observable guarantees of ordinary Nupp unless the
source opts into a named relaxation. Verification checks the lowered IR before
any target-specific code is produced.

```nupp
@aot(vectorize = false)
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
| `int64` `+`, `-`, `*` in AOT | wrapping int64 | operates as uint64, then converts back |
| `uint64` `+`, `-`, `*` in AOT | wrapping uint64 | native unsigned modular arithmetic |

Ordinary floating-point arithmetic assumes round-to-nearest-even. Signed zero
and numeric NaN behavior are preserved. NaN signaling state, payload bits, and
floating-point exception flags are not observable guarantees. The bit-level
surface of `nupp.math.f32`, including its canonical NaN behavior, retains the
stronger guarantees described below.

Signed wrapping arithmetic is performed in the corresponding unsigned C type.
For int32 and int64 the modular result is converted back to the signed type;
generated native code relies on GCC 9 and Clang's documented modular
unsigned-to-signed conversion behavior.

A comparison whose operands mix these widths answers by mathematical value.
C's usual arithmetic conversions would instead decide it in unsigned
arithmetic -- converting `-1` above `5` -- so generated code widens an
`int32`/`uint32` pairing into `int64`, routes a signed operand against
`uint64` through a sign-checked helper, and meets a binary32 operand and an
integer in binary64. The interpreter, the constant folder, and generated
native code therefore agree on every mixed comparison; a 64-bit operand
beyond 2^53 meeting `number` keeps binary64's exactness boundary, because
the comparison itself is performed in binary64 there.

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
Horner order with `fma`, then square seven times. The interpreter, native C, and
SPIR-V execute that same binary32 sequence; WGPU translates the canonical
module for the selected native backend, and none asks a platform math library
to choose a result.

A width changes only at a conversion the IR writes down. An operator never
changes one, which is what keeps `float` a storage fact rather than an
arithmetic type:

::: code-group
```nupp [Nupp]
local wide = inputs[i].value
local doubled = wide + wide
local narrow = nupp.math.f32.add(nupp.math.f32.narrow(wide), nupp.math.f32.narrow(wide))
outputs[i].value = narrow + doubled
```

```c [Generated C]
double v1_wide = ((double)((&p_inputs[i])->value));
double v2_doubled = (v1_wide + v1_wide);
float v3_narrow = ((float)((float)(v1_wide)) + (float)((float)(v1_wide)));
float as1 = (float)((((double)v3_narrow) + v2_doubled));
((&p_outputs[i])->value) = as1;
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

A bitwise operator needs neither. Its operands normalize to thirty-two bits and
its result comes back signed, so where both operands already carry a width the
result is an established `int32` and flows straight into the next fixed-width
operation. Nothing has to be wrapped back to the width it never left:

```nupp
local function choose(e: int32, f: int32, g: int32): int32
    return (e & f) ~ ((~e) & g)
end
```

An exact integer literal is admitted anywhere a fixed-width value is, including
a shift count, a helper argument and the bound a cursor is compared against.
That last one is why a counted loop compares in its own width rather than
converting to binary64 to meet its bound.

## Verification

Generated C is a backend representation and not the safety boundary. Every span
access, region relationship, conversion and lane operation is verified in the IR
before anything is emitted, so a rewrite that produced something invalid is a
compiler bug caught before it becomes a miscompilation.

Two rules do most of the work. Every load, store and element reference indexes
the loop counter and nothing else, which is both the argument that an access is
in bounds and the license to run several iterations at once. And the alias
matrix is required complete rather than merely consistent: every pair of span
regions carries a fact, because a pair with no fact would be a `restrict` nobody
justified.

Above that sit the differentials, which is where correctness is actually
established. Ordinary Nupp, forced-scalar C and lane-parallel C are all built
from one source and must agree exactly rather than within a tolerance, because
the arithmetic is specified to be the same work in the same order:

```bash
bench/kernel-subset-spike/simd.sh                     # lane rewrite vs scalar
luajit bench/kernel-subset-spike/corrected_main.lua   # binary32 min/max/fma
luajit bench/kernel-subset-spike/tecsbits_main.lua    # bitwise lanes over entities
luajit bench/kernel-subset-spike/mixedwidth_main.lua  # binary32 and binary64 in one gang
luajit bench/kernel-subset-spike/mandelbrot_main.lua  # every pixel, three ways
```

Tails are exercised at every remainder for both gang widths, so a four-lane and
an eight-lane tail are both covered.

`bench/kernel-subset-spike/crosscheck.sh` runs the same agreement in C with no
LuaJIT in the process, over every committed kernel, at both gang widths and at
whatever feature tier is asked for. CI runs it on Linux and macOS at three tiers
and through both Clang and GCC, and on Windows, so the platform is checked
rather than reasoned about from the other two.

The build's own end of it is exercised the same way, by doing the thing rather
than asserting it: a project is built under `require` and its answers compared
against the same project built with `aot = "off"`, an output tree is copied
elsewhere and run from a third directory, a cross build's object is inspected to
confirm it is the other machine's, and a stamped binary is run from `/` to
confirm it finds the library it was given.

## Scalar switch initializers

The scalar subset admits a
[switch](../../language/switch-expressions.md) as the sole initializer of one local
when:

- the selector lowers to `f64`, `i32`, or `u32`;
- every case is an integer-valued numeric constant;
- every arm is one scalar expression; and
- the checker has proved the switch exhaustive, either from its cases or an
  `else` arm.

```nupp
local span = nupp.mem.span

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
and branch `Assign` operations. For an established `int32` or `uint32` selector,
lowering annotates that ordinary `If` with its exact-width labels and the C
emitter writes a native `switch` (temporary names are abbreviated here):

```c
switch (code) {
case (-INT32_C(2147483647) - INT32_C(1)):
    result = INT32_C(10);
    break;
case INT32_C(1):
case INT32_C(2):
    result = INT32_C(20);
    break;
default:
    result = INT32_C(30);
    break;
}
```

The annotation is optional: scalar-IR verification and lane rewriting may ignore
it and retain the complete equality chain. Nupp `integer` is normally binary64,
so those selectors deliberately remain equality branches rather than being
converted. Strings, type patterns, block arms, and early arm returns report the
ordinary subset boundary. The C compiler chooses the physical native
dispatch, and Nupp neither forces a jump table nor synthesizes a C perfect hash.
