# Named and plucked arguments

Status: implemented. See the Named and plucked arguments section of
`nupp reference language`.

## Decision

Nupp adds named call arguments and argument plucking. Together they let a
container fill a function's parameters without hiding that decomposition at the
call site:

```nupp
local record Vec3
    x: number
    y: number
    z: number
end

local function draw(x: number, y: number, color: string?): nil
end

draw((x, y) = position, color = "red")
```

`(name) = value` fills that parameter from the field of `value` the parameter
names. It is sugar for `name = value.name` and nothing else. `(a, b) = value`
fills several parameters from one operand. The generated Lua calls
`draw(position.x, position.y, "red")`.

Nothing is declared on the operand's type. A plucked name reaches any record
carrying a field of that name, including one the caller does not own, and the
callee decides which subset of the operand it reads.

## Named arguments

A named argument is `name = expression` inside parenthesized call arguments.
Named arguments must follow all positional arguments. They must appear in
parameter order; this keeps evaluation order identical in source and generated
Lua. Each parameter may be filled once. Unknown names, duplicates, and a named
argument overlapping the positional prefix are errors.

Omitted parameters continue to receive Lua's `nil`. When a later named
parameter follows an omitted optional parameter, generation inserts `nil` for
the gap.

Parameter names are retained on function types and are part of their static
call contract. This includes ordinary functions, function type annotations, C
declarations, constructors, methods, overload entries, and imported module
interfaces. A named call through a variable therefore behaves the same as a
direct call.

At runtime named arguments erase to ordinary positional arguments. They do not
allocate a table or require a dispatcher.

## Plucking

A pluck is a named binding whose value is a field read, so it opens the named
suffix exactly as `name = value` does and positional arguments cannot follow it.

Each name resolves against the operand's type rather than against the candidate
signature, because the field a name reads depends only on the operand. A name
that is not a field of the operand is an ordinary missing-field diagnostic at
that name, carrying the same spelling fix an ordinary field read would offer,
rather than a reason some overload was rejected. The resulting binding is then
checked like any other named argument, so a field whose type does not fit its
parameter is an ordinary rejected call.

A group's names are a set rather than a sequence. Every read is a field of one
path, so no order among them is observable and `(y, x)` binds exactly what
`(x, y)` does. Ordering is enforced between arguments, not inside a group.
Repeating a name within a group is an error, as is filling one parameter from
both a group and a later named argument.

An operand is required to be a stable value path: a local or other name followed
by zero or more ordinary dotted field accesses. This covers both `position` and
flattened embedded values such as `entity.transform.position`. Calls, safe
navigation, computed indexing, and other producing expressions are rejected by
the checker, which can say to bind them to a local first. That restriction is
what makes the reads unordered and what lets lowering evaluate each path once.

Plucking reads fields. It cannot project a write-only member, and it refuses
affine projected fields: silently splitting an owner would need partial-move
state on the container, so callers pass such a container explicitly until that
state exists.

Because a pluck fills parameters by name, there is exactly one arrangement to
consider. Nothing searches, and no arity is selected. A bounded type parameter
plucks through its bound without the bound declaring anything, since the read is
an ordinary field access.

## Lowering

Plucking is erased:

```nupp
update(
    delta,
    (x, y) = entity.body.position,
    (dx, dy) = entity.body.velocity
)
```

generates ordinary locals and a positional Lua call, conceptually:

```lua
local body = entity.body
local position = body.position
local velocity = body.velocity
update(delta, position.x, position.y, velocity.x, velocity.y)
```

Generated names are collision-free. Only reusable path nodes are bound; the
callee, projected leaves, and trailing arguments remain direct when they are
already evaluated once. An ordinary call that is itself a statement, return,
initializer, or assignment receives bindings directly. Safe call statements use
guards and returned safe calls use early returns. Calls in expression-valued
positions that cannot host those statements emit their projected leaves directly
instead. Plucking never introduces a function, closure, upvalue, argument table,
or runtime arity selection.

A safe call keeps the same final positional signature but places plucked
bindings inside its taken branch:

```nupp
maybeDraw?.((x, y) = entity.body.position)
```

conceptually generates:

```lua
local draw = maybeDraw
if draw ~= nil then
    local body = entity.body
    local position = body.position
    draw(position.x, position.y)
end
```

A safe call nested in another expression retains LuaJIT's native safe operator
and repeats a prefix when necessary, which keeps the native guard's argument
laziness without allocating an immediately invoked closure. Safe receiver and
safe method checks in statement lowering are staged separately, so a nil
receiver prevents method lookup and either check prevents argument evaluation.

Formatting puts spaces around `=`. The CST retains both constructs so LSP
positions, diagnostics, and source round-tripping remain exact.

## Deliberate constraints

- Named and plucked arguments are parenthesized-call syntax; Lua's string and
  table call sugar remains positional.
- Positional arguments never follow a named or plucked argument. A call keeps
  its several results only as the last argument, so it fills the remaining
  positional slots only when nothing is plucked after it.
- Named arguments appear in declaration order; a group's names need not.
- Plucked operands are names or dotted field paths; calls, safe navigation,
  computed indexing, and other producing expressions await temporary-aware
  lowering.
- Plucked fields are non-affine until the ownership model tracks partial moves
  of containers.
- Parameter names are part of the call contract. Plucking spends surface that
  named arguments already spent rather than any that was previously free.
- A pluck names the parameters it fills, so the call site states its own arity.
  Nothing is declared on the operand's type, and no ordering lives there.
