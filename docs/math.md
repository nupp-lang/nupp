# Math helpers

`nupp.math` adds the scalar and two-dimensional operations missing from Lua's
built-in `math` table. It is pure generated Lua and adds no native dependency.

`lerp(from, to, t)` linearly interpolates without clamping `t`, so factors
outside `[0, 1]` extrapolate. It returns `from` exactly at zero and `to` exactly
at one. `wrapAngle(radians)` returns the equivalent angle in `[-π, π)`.
`deltaAngle(from, to)` returns the shortest signed rotation from one angle to
another.

```nupp:playground
assert(nupp.math.lerp(10, 20, 0.25) == 12.5)
local turn = nupp.math.deltaAngle(math.rad(350), math.rad(10))
assert(math.abs(math.deg(turn) - 20) < 0.000001)
```

## Fixed-width arithmetic

`float`, `int32`, and `uint32` are unboxed refinements of Lua numbers. They
widen to `number` without code, while entering one requires an exact literal,
a reified load, an explicit conversion, or another established fixed-width
value. The erased assertion `as` changes a static claim but does not establish
the value.

The establishing conversions are `nupp.math.f32.narrow(number)`,
`nupp.math.i32.wrap(integer)`, and `nupp.math.u32.wrap(integer)`. Ordinary
arithmetic keeps LuaJIT's numeric meaning and produces `number`; use the
`f32`, `i32`, or `u32` namespace when the operation's width is part of its
contract.

```nupp
local flags: uint32 = 0x12
local rotated = nupp.math.u32.rotateLeft(flags, 7)
local distance = nupp.math.f32.narrow(10 / 3)
local inverseTime = nupp.math.f32.narrow(60)
local speed = nupp.math.f32.mul(distance, inverseTime)
```

The integer namespaces wrap modulo 2^32. Shift counts are masked by 31, and the
operation states whether its interpretation is signed or unsigned. Calls use
Lua numbers in canonical ranges rather than allocating scalar cdata.

The binary32 namespace rounds every input and result to nearest, ties to even.
It preserves signed zero, subnormals, and infinities, canonicalizes NaNs, and
makes `fma` one fused operation. `fromBits` and `toBits` expose that canonical
bit contract. `f32.narrow` performs one binary32 store and load without changing
a NaN payload; `f32.round` retains the canonical-NaN contract.

Aliasing a standard member preserves its intrinsic identity. A local that merely
shadows the same spelling is an ordinary call and receives no fixed-width
intrinsic treatment.

The narrower `int8`, `int16`, `uint8`, and `uint16` names describe physical
storage rather than ordinary values. Their allowed positions and load behavior
are covered under [numbers](type-system/primitives.md#numbers).

`nupp.math.vec2` represents vectors as `(x, y)` number pairs rather than
allocated objects. Multiple return values make composition direct:

```nupp
local vec2 = nupp.math.vec2
local x, y = vec2.normalize(3, 4)
assert(x == 0.6 and y == 0.8)

x, y = vec2.rotate(x, y, math.pi / 2)
local projectedX, projectedY = vec2.project(x, y, 1, 0)
```

Arithmetic operations are `add`, `subtract`, `scale`, `dot`, and `cross`.
Measurement operations are `length`, `lengthSquared`, `distance`, and
`distanceSquared`. Motion and orientation operations are `normalize`, `lerp`,
`moveTowards`, `rotate`, `angle`, `angleBetween`, and `signedAngleBetween`.
`project` projects onto another vector; `reflect` reflects across a normal.

| Operation | Signature shape |
| --- | --- |
| `add`, `subtract` | (ax, ay, bx, by) -> x, y |
| `scale` | (x, y, factor) -> x, y |
| `dot`, `cross` | (ax, ay, bx, by) -> number |
| `length`, `lengthSquared` | (x, y) -> number |
| `distance`, `distanceSquared` | (ax, ay, bx, by) -> number |
| `normalize` | (x, y) -> x, y |
| `lerp` | (ax, ay, bx, by, t) -> x, y |
| `moveTowards` | (ax, ay, bx, by, maxDistance) -> x, y |
| `rotate` | (x, y, radians) -> x, y |
| `angle` | (x, y) -> radians |
| `angleBetween`, `signedAngleBetween` | (ax, ay, bx, by) -> radians |
| `project`, `reflect` | (x, y, axisX, axisY) -> x, y |

`normalize(0, 0)` and projection onto the zero vector return `(0, 0)`.
`moveTowards` snaps exactly to the destination when the remaining distance is
within the requested step, and a nonpositive step leaves the start unchanged.
Angle-between operations involving a zero vector return zero; reflection across
a zero normal returns the original vector. `lerp` is unclamped. Use squared
length/distance when only comparing magnitudes, to avoid an unnecessary square
root.

## Diagnostics

- **NUPP2011**: a `float`, `int32`, or `uint32` claim lacks an establishing
  literal, load, conversion, or fixed-width source.
- **NUPP2012**: a physical storage width is used where an ordinary value type is
  required.

See [the standard-library overview](stdlib.md) for selection and lazy-loading
rules.
