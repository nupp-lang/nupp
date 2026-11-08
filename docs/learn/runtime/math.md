# Math extensions

The `math` table includes scalar helpers, fixed-width operations, and
two-dimensional vector operations.

```nupp
assert(math.lerp(10, 20, 0.25) == 12.5)
local turn = math.dtangle(math.rad(350), math.rad(10))
assert(math.abs(math.deg(turn) - 20) < 0.000001)
```

## Scalar operations

`lerp(from, to, t)` interpolates linearly without clamping `t`, so
factors outside `[0, 1]` extrapolate. It returns `from` exactly at zero
and `to` exactly at one, because it returns the endpoints without computing them.

`wrapangle(radians)` returns the equivalent angle in `[-π, π)`, and
`dtangle(from, to)` returns the shortest signed rotation from one
angle to another.

## Fixed-width arithmetic

`float`, `int32`, and `uint32` are unboxed refinements of Lua numbers. They
widen to `number` without code, while entering one requires an exact literal, a
reified load, an explicit conversion, or another established fixed-width value.
The erased assertion `as` changes a static claim but does not establish the
value.

```nupp
local flags: uint32 = 0x12
local rotated = math.u32.rotateleft(flags, 7)
```

### Establishing a fixed-width value

The establishing conversions are `math.f32.narrow(number)`,
`math.i32.wrap(integer)`, and `math.u32.wrap(integer)`. Ordinary
arithmetic keeps LuaJIT's numeric meaning, so no refinement survives it. Use the
`f32`, `i32`, or `u32` namespace when the operation's width is part of its
contract:

```nupp
local distance = math.f32.narrow(10 / 3)
local rate = math.f32.narrow(60)
local speed = math.f32.mul(distance, rate)
```

What does survive is being whole. `int32` and `uint32` widen to `integer`, so
ordinary arithmetic over them gives an `integer`. That is what lets a `uint32`
cursor index a view as `cursor + 1`. `float` widens to `number` and its
arithmetic gives one.

Aliasing a standard member preserves its intrinsic identity. A local that
merely reuses the name is an ordinary call and receives no fixed-width
intrinsic treatment.

### Integer namespaces

`i32` and `u32` wrap modulo 2^32. Calls use Lua numbers in canonical ranges
rather than allocating scalar cdata, and a shift is Lua's own operator, which
is logical on a `uint32`:

```nupp
local all: uint32 = math.u32.wrap(-1)
assert(all >> 24 == 255)
```

`u32` and `u64` also carry rotations, `popcount`, `trailingzeros` and
`leadingzeros`. `u64.prefixxor` computes inclusive prefix parity over all
sixty-four bits.

### Binary32 namespace

`f32` rounds every input and result to nearest, ties to even. It preserves
signed zero, subnormals, and infinities, canonicalizes NaNs, and makes `fma` one
fused operation. `frombits` and `tobits` expose that canonical bit contract.
`f32.narrow` performs one binary32 store and load without changing a NaN
payload, and `f32.round` retains the canonical-NaN contract.

### Narrower storage names

The `int8`, `int16`, `uint8`, and `uint16` names describe physical storage
rather than ordinary values. See
[Numbers](../language/types/primitives.md#numbers) for the positions
they are allowed in and how a load behaves.

## Two-dimensional vectors

`math.vec2` represents a vector as an `(x, y)` number pair rather than an
allocated object, so multiple return values compose directly:

```nupp
local vec2 = math.vec2

local x, y = vec2.normalize(3, 4)
assert(x == 0.6 and y == 0.8)

x, y = vec2.rotate(x, y, math.pi / 2)
local projectedX, projectedY = vec2.project(x, y, 1, 0)
```

| Operation | Signature shape |
| --- | --- |
| `add`, `sub` | (ax, ay, bx, by) -> x, y |
| `scale` | (x, y, factor) -> x, y |
| `dot`, `cross` | (ax, ay, bx, by) -> number |
| `len`, `lengthsquared` | (x, y) -> number |
| `dist`, `distancesquared` | (ax, ay, bx, by) -> number |
| `normalize` | (x, y) -> x, y |
| `lerp` | (ax, ay, bx, by, t) -> x, y |
| `movetowards` | (ax, ay, bx, by, maxDistance) -> x, y |
| `rotate` | (x, y, radians) -> x, y |
| `angle` | (x, y) -> radians |
| `anglebetween`, `signedanglebetween` | (ax, ay, bx, by) -> radians |
| `project`, `reflect` | (x, y, axisX, axisY) -> x, y |

A zero vector has no direction, so the operations that would need one
return a defined value rather than a NaN: `normalize(0, 0)` and
projection onto the zero vector return `(0, 0)`, an angle involving a
zero vector is zero, and reflection across a zero normal returns the
original vector.

`movetowards` snaps exactly to the destination when the remaining distance is
within the requested step, and a nonpositive step leaves the start unchanged.
`lerp` is unclamped, like the scalar one. Compare squared lengths and distances
where only the ordering matters, to avoid a square root that cannot change it.
