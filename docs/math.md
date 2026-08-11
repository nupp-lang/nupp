# Math helpers

`nupp.math` adds the scalar and two-dimensional operations missing from Lua's
built-in `math` table. It is pure generated Lua and adds no native dependency.

`lerp(from, to, t)` linearly interpolates without clamping `t`, so factors
outside `[0, 1]` extrapolate. It returns `from` exactly at zero and `to` exactly
at one. `wrapAngle(radians)` returns the equivalent angle in `[-π, π)`.
`deltaAngle(from, to)` returns the shortest signed rotation from one angle to
another.

```nupp
assert(nupp.math.lerp(10, 20, 0.25) == 12.5)
local turn = nupp.math.deltaAngle(math.rad(350), math.rad(10))
assert(math.abs(math.deg(turn) - 20) < 0.000001)
```

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

```
 Operation                         Signature shape
 ────────────────────────────────  ─────────────────────────────────────
 add, subtract                     (ax, ay, bx, by) -> x, y
 scale                             (x, y, factor) -> x, y
 dot, cross                        (ax, ay, bx, by) -> number
 length, lengthSquared             (x, y) -> number
 distance, distanceSquared         (ax, ay, bx, by) -> number
 normalize                         (x, y) -> x, y
 lerp                              (ax, ay, bx, by, t) -> x, y
 moveTowards                       (ax, ay, bx, by, maxDistance) -> x, y
 rotate                            (x, y, radians) -> x, y
 angle                             (x, y) -> radians
 angleBetween, signedAngleBetween  (ax, ay, bx, by) -> radians
 project, reflect                  (x, y, axisX, axisY) -> x, y
```

`normalize(0, 0)` and projection onto the zero vector return `(0, 0)`.
`moveTowards` snaps exactly to the destination when the remaining distance is
within the requested step, and a nonpositive step leaves the start unchanged.
Angle-between operations involving a zero vector return zero; reflection across
a zero normal returns the original vector. `lerp` is unclamped. Use squared
length/distance when only comparing magnitudes, to avoid an unnecessary square
root.

See [the standard-library overview](stdlib.md) for selection and lazy-loading
rules.
