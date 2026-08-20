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

::: rationale
A plucked operand is restricted to a name or a dotted path because that is what
earns the two properties above it: reads can be unordered only when none can
observe another's effects, and each path can be evaluated once only because it is
re-evaluable. The cost of the feature is that parameter names become part of the
call contract, so renaming one is a source-compatibility question — the same
bargain Python and Swift make.
:::

## Bind fields into locals

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

## Named arguments come last

A named argument follows every positional one and appears in parameter order. An
optional slot skipped before a later named argument is emitted as `nil`, so the
generated call is the positional one you would have written.

```nupp
local function draw(x: number, y: number, color: string?): nil
    print(x, y, color)
end

local function render(): nil
    draw(10, 20, color = "blue")
    draw(10, y = 20)
end
```

## Plucking reads a field, not a contract

Nothing is declared on the operand's type. A plucked name reaches any record
carrying a field of that name, including one the caller does not own, which is
what lets a function take `x` and `y` from a value that was never designed
around it.

A name that is not a field of the operand is **NUPP2004**. The binding it
produces is then checked like any other named argument, so a field whose type
does not fit its parameter is an ordinary rejected call rather than a special
case.

## Groups are sets, not sequences

Every read in a group is a field of one path, so no order among them is
observable and `{y, x}` binds exactly what `{x, y}` does. Ordering is enforced
between arguments, not inside a group.

## Operands are names or paths

A plucked operand is a name or a dotted field path, such as `entity.position`.
Bind a call, a computed index, or any other producing expression to a local
first. That restriction is what lets the reads be unordered and evaluated once:
a statement-level call evaluates each dotted path and common prefix a single
time, while the projected fields stay direct positional arguments.

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

Plucking never introduces a closure or an upvalue.
