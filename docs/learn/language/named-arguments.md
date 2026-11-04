---
order: 60
---

# Named and plucked arguments

Inside a parenthesized call, `name = value` fills that parameter by name, and
`{name} = value` fills it from the field of `value` that the parameter names.
Both erase to ordinary positional Lua arguments, so neither costs anything at
run time.

```nupp:playground
local record Vec3
    x: number
    y: number
    z: number
end

local function draw(x: number, y: number, color: string?): nil
    print(x, y, color)
end

local function render(position: Vec3): nil
    draw({x, y} = position, color = "blue")
end
```

`{x, y} = position` means `x = position.x, y = position.y` and nothing more.

## Argument order

A named argument follows positional arguments and appears in parameter order.
An optional slot skipped before a later named argument is emitted as `nil`, so
the generated call is the positional one you would have written.

::: code-group
```nupp [Nupp]
local function draw(x: number, y: number, color: string?): nil
    print(x, y, color)
end

local function render(): nil
    draw(10, 20, color = "blue")
    draw(10, y = 20)
end
```

```lua [Generated Lua]
local function draw(x, y, color)
    print(x, y, color)
end

local function render()
    draw(10, 20, "blue")
    draw(10, 20)
end
```
:::

## Final function literals

A function literal may follow named or plucked arguments when it is the final
argument. It fills the final fixed parameter; skipped optional parameters are
passed as `nil`:

```nupp
local function invoke(name: string, option: string?, callback: function(string): nil): nil
    callback(name)
end

invoke(name = "load", function(name: string): nil
    print(name)
end)
```

The final argument must be a function literal or a short function. A variable
holding a function remains an ordinary positional argument. A variadic tail
has no final fixed parameter, so name its callback parameter explicitly or put
the function before the named arguments.

## Plucking reads a field

Nothing is declared on the operand's type. A plucked name reaches any record
carrying a field of that name, including one the caller does not own, which is
what lets a function take `x` and `y` from a value that was never designed
around it. Functions, methods, callable records, and constructors all accept
one, and a bounded type parameter plucks through its bound, because the read is
an ordinary field access.

```nupp
local record Vec3
    x: number
    y: number
    z: number
end

local record Sprite
    x: number
    y: number
    frame: integer
end

local function draw(x: number, y: number, color: string?): nil
    print(x, y, color)
end

local function render(position: Vec3, sprite: Sprite): nil
    draw({x, y} = position)
    draw({x, y} = sprite, color = "blue")
end
```

A name that is not a field of the operand is reported, carrying a fix when a
real field is close enough to be the one meant.

```nupp:refused
local record Sprite
    x: number
    y: number
    frame: integer
end

local function place(x: number, y: number, z: number): nil
    print(x, y, z)
end

local function render(sprite: Sprite): nil
    place({x, y, z} = sprite)
end
```

```text [nupp check render.nupp]
error: NUPP2004: no field "z" in Sprite
```

The binding a name does produce is checked like any other named argument, so a
field whose type does not fit its parameter is an ordinary rejected call rather
than a special case.

## Groups are unordered

Every read in a group is a field of one path, so no order among them is
observable and `{y, x}` binds exactly what `{x, y}` does. Ordering is enforced
between arguments, not inside a group.

```nupp
local record Vec3
    x: number
    y: number
    z: number
end

local function draw(x: number, y: number, color: string?): nil
    print(x, y, color)
end

local function render(position: Vec3): nil
    draw({y, x} = position, color = "blue")
end
```

## Operands are names or paths

A plucked operand is a name or a dotted field path, such as `entity.position`.
Bind a call, a computed index, or any other producing expression to a local
first. Each call evaluates its dotted paths and common prefixes a single time,
while the projected fields stay direct positional arguments. In a conditional
expression such as `enabled and draw({x, y} = entity.position)`, the path is
evaluated only when the call is reached. Plucking never introduces a closure or
an upvalue.

```nupp
local record Vec3
    x: number
    y: number
    z: number
end

local record Entity
    position: Vec3
end

local function draw(x: number, y: number, color: string?): nil
    print(x, y, color)
end

local function render(entity: Entity): nil
    draw({x, y} = entity.position, color = "blue")
end
```

## Binding patterns

The same braces select fields for `local` and `const` declarations. The source
may be any expression and is evaluated once. Its fields are read once from left
to right before any of the new locals enters scope.

```nupp
local record Point
    x: number
    y: number
end

local point = new Point(x = 1, y = 2)
local {x, y as vertical} = point
const {x as fixedX: number} = point
```

`as` names the local; it does not rename the source field. These are shallow
field reads rather than moves, so owned or borrowed fields cannot be extracted
through a pattern. Function parameters remain ordinary named declarations.

See [Explicit imports](modules.md#explicit-imports) for the same braces
applied to `require`.

## Rejected arrangements

A call is reported when its arguments cannot be arranged into the single
positional call they stand for.

```nupp:refused
local function draw(x: number, y: number, color: string?): nil
    print(x, y, color)
end

local function render(): nil
    draw(color = "blue", 10, 20)
end
```

```text [nupp check render.nupp]
error: NUPP2006: a positional argument cannot follow a named argument
```

The rest of the arrangements it reports:

- Named arguments follow parameter order, and no parameter is filled twice or
  named twice in one group.
- A named argument may not overlap a parameter the positional prefix already
  filled, and may not name a parameter the callee does not have.
- A plucked operand must be a name or a dotted field path.
- Named and plucked arguments require a statically known callable, so a call
  through a value typed `any` takes positional arguments only.

Plucking from an owned or borrowed operand is reported instead: an owned or
borrowed container cannot be plucked from. See [ownership.md](../runtime/ownership/index.md) for
what a capability permits.

::: seealso
- [diagnostics.md](../../reference/diagnostics.md) for the code behind every
  arrangement this page refuses
- [Type cases, binding, and
  destructuring](switch-expressions.md#type-cases-binding-and-destructuring)
  for the brace form a switch arm uses
- [records.md](types/records-and-structs.md) for the field declarations a pluck
  reads
:::
