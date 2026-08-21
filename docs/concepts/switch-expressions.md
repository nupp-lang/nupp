---
order: 80
---

# Switch expressions

A switch selects one value from ordered cases, evaluating its selector once and
running only the arm that matches. It lowers to two generated locals and an
ordered `if`/`elseif` chain, and nothing is wrapped in a function.

::: code-group
```nupp [Nupp]
local label = switch status do
    case 200 -> "ok"
    case 301, 302, 307, 308 -> "redirect"
    case 400, 404 -> "client error"
    else -> "other"
end
```

```lua [Generated Lua]
local __nuppT1 = status
local __nuppT2
if __nuppT1 == 200 then __nuppT2 = "ok"
elseif __nuppT1 == 301 or __nuppT1 == 302 or __nuppT1 == 307 or __nuppT1 == 308 then __nuppT2 = "redirect"
elseif __nuppT1 == 400 or __nuppT1 == 404 then __nuppT2 = "client error"
else __nuppT2 = "other"
end
local label = __nuppT2
```
:::

See [performance.md](../guides/performance.md#switch-dispatch) for when a static
switch finishes in one table read instead of that chain.

## Static cases

Static cases use primitive Lua equality. An allowed value is:

- `nil`, `true`, or `false`;
- a string literal;
- a finite Lua number literal, optionally preceded by `-`;
- parentheses around an allowed value; or
- a name whose checked type is one exact scalar value.

Several values may share an arm:

::: code-group
```nupp [Nupp]
local kind = switch byte do
    case 9, 10, 13, 32 -> "space"
    case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57 -> "digit"
    else -> "other"
end
```

```lua [Generated Lua]
local __nuppT3 = byte
local __nuppT4
if __nuppT3 == 9 or __nuppT3 == 10 or __nuppT3 == 13 or __nuppT3 == 32 then __nuppT4 = "space"
elseif __nuppT3 == 48 or __nuppT3 == 49 or __nuppT3 == 50 or __nuppT3 == 51 or __nuppT3 == 52
    or __nuppT3 == 53 or __nuppT3 == 54 or __nuppT3 == 55 or __nuppT3 == 56 or __nuppT3 == 57 then __nuppT4 = "digit"
else __nuppT4 = "other"
end
local kind = __nuppT4
```
:::

Values sharing an arm become an `or` chain against the one selector local.

Cases are values rather than source forms. `1`, `1.0`, and `1e0` are the same
case, and `0` and `-0` are the same case, because a case denotes the finite
binary64 value LuaJIT compares at run time. That rule is local to switch cases
and does not widen the literal-type or const-generic domains described in
[unions.md](../type-system/unions.md#literal-unions-are-enums). Operators,
calls, indexing, table constructors, cdata literals, and non-finite numbers are
not static cases.

An exact const name is useful when the name communicates more than its value:

::: code-group
```nupp [Nupp]
const READ: "read" = "read"
const WRITE: "write" = "write"

local access = switch mode do
    case (READ) -> "reader"
    case (WRITE) -> "writer"
end
```

```lua [Generated Lua]
const READ = "read"
const WRITE = "write"

local __nuppT5 = mode
local __nuppT6
if __nuppT5 == (READ) then __nuppT6 = "reader"
elseif __nuppT5 == (WRITE) then __nuppT6 = "writer"
end
local access = __nuppT6
```
:::

The parentheses are required today: a bare `case READ ->` does not parse,
because the name and arrow are taken for the start of a short function.

## Type cases, binding, and destructuring

`case is T` performs the same test as `value is T`. It narrows the selector for
that arm. `as name` binds the narrowed whole value, and a brace list binds
direct fields:

::: code-group
```nupp [Nupp]
local description = switch shape do
    case is Circle as circle {radius} ->
        `circle ${circle.name}, radius ${radius}`

    case is Rectangle {width, height as h} ->
        `rectangle ${width} x ${h}`

    else -> "unknown"
end
```

```lua [Generated Lua]
local __nuppT1 = shape
local __nuppT2
if (getmetatable(__nuppT1)?.__index == Circle) then
    local circle = __nuppT1
    local radius = __nuppT1.radius
    __nuppT2 = ("circle " .. tostring(circle.name) .. ", radius " .. tostring(radius))
elseif (getmetatable(__nuppT1)?.__index == Rectangle) then
    local width = __nuppT1.width
    local h = __nuppT1.height
    __nuppT2 = ("rectangle " .. tostring(width) .. " x " .. tostring(h))
else __nuppT2 = "unknown"
end
local description = __nuppT2
```
:::

Each binding is a plain local read off the one selector local, so a computed
selector is never evaluated twice. The `?.` guard appears because this selector
admits `nil`; a selector proved to be entirely records drops it.

All pattern bindings are const and scoped to their arm. `field as alias` changes
only the local binding name. Destructuring is direct, with no nested object
patterns, and a missing field or duplicate binding is reported. A binding
shares the selector's ownership identity rather than creating a second
obligation, so no arm can move an affine selector by matching on it.

Runtime identity follows `is`:

- primitives use `type()`;
- records use nominal metatable identity;
- structs use `ffi.istype`;
- refined interfaces use their declared runtime predicate.

An interface with no runtime identity cannot be tested. Type cases are ordered.
A broad case can consume the type a later case needs, and the later arm is then
reported as unreachable. See
[narrowing.md](../type-system/narrowing.md#switch-arm-narrowing) for the facts
an arm may rely on.

## Expression and block arms

An expression arm produces its expression directly:

::: code-group
```nupp [Nupp]
local path = switch mode do
    case "read" -> inputPath
    case "write" -> outputPath
    else -> defaultPath
end
```

```lua [Generated Lua]
local __nuppT1 = mode
local __nuppT2
if __nuppT1 == "read" then __nuppT2 = inputPath
elseif __nuppT1 == "write" then __nuppT2 = outputPath
else __nuppT2 = defaultPath
end
local path = __nuppT2
```
:::

Use `-> do` when an arm needs statements. `yield value` supplies the switch
result. It is not coroutine suspension. `return` still exits the enclosing
function immediately:

::: code-group
```nupp [Nupp]
local value = switch token do
    case is NumberToken {text} -> do
        local parsed = tonumber(text)
        if parsed == nil then
            return nil, "invalid number"
        end
        yield parsed
    end

    else -> 0
end
```

```lua [Generated Lua]
local __nuppT3 = token
local __nuppT4
if (getmetatable(__nuppT3)?.__index == NumberToken) then
    local text = __nuppT3.text
    local parsed = tonumber(text)
    if parsed == nil then
        return nil, "invalid number"
    end
    __nuppT4 = parsed
else __nuppT4 = 0
end
local value = __nuppT4
```
:::

`yield` is an assignment to the result local, not a call and not a coroutine
suspension. See [suspension.md](suspension.md) for the construct that does park
a coroutine.

Every completing path through a block arm must reach one `yield`; a path may
instead `return` from the enclosing function. Falling through, or placing a
statement after a switch yield on the same path, is reported.

::: deepdive
Giving `return` the switch-result meaning would have been the smaller grammar,
and it was rejected. An arm is ordinary code, and code that reads as an early
exit has to be one. `yield` carries the result instead, targeting the nearest
enclosing arm and never crossing a function boundary.
:::

### Contextual `yield`

`yield` is line-sensitive. These remain ordinary Lua calls:

::: code-group
```nupp [Nupp]
yield(value)
yield {value}
yield "value"
```

```lua [Generated Lua]
yield(value)
yield {value}
yield "value"
```
:::

To supply one of those forms as an arm result, bind it and yield the name:

::: code-group
```nupp [Nupp]
local answer = {value}
yield answer
```

```lua [Generated Lua]
local answer = {value}
__nuppT4 = answer
```
:::

## Exhaustiveness and reachability

Every switch must be total. An `else` arm proves totality. It may be omitted
when the checker can prove that ordered cases consume the entire selector type.
Finite literal unions, `nil`, and both boolean values are enumerable:

::: code-group
```nupp [Nupp]
local type Mode = "read" | "write"

local access = switch mode do
    case "read" -> "reader"
    case "write" -> "writer"
end
```

```lua [Generated Lua]
local __nuppT5 = mode
local __nuppT6
if __nuppT5 == "read" then __nuppT6 = "reader"
elseif __nuppT5 == "write" then __nuppT6 = "writer"
end
local access = __nuppT6
```
:::

A proved-total switch emits no `else`. Totality is the checker's guarantee, so
nothing is generated to defend it at runtime.

Type cases can likewise consume a closed union:

::: code-group
```nupp [Nupp]
local area = switch shape do
    case is Circle {radius} -> math.pi * radius * radius
    case is Rectangle {width, height} -> width * height
    case nil -> 0
end
```

```lua [Generated Lua]
local __nuppT3 = shape
local __nuppT4
if (getmetatable(__nuppT3)?.__index == Circle) then
    local radius = __nuppT3.radius
    __nuppT4 = math.pi * radius * radius
elseif (getmetatable(__nuppT3)?.__index == Rectangle) then
    local width = __nuppT3.width
    local height = __nuppT3.height
    __nuppT4 = width * height
elseif __nuppT3 == nil then __nuppT4 = 0
end
local area = __nuppT4
```
:::

An open selector such as `string`, `integer`, or `any` requires `else` unless
the arms already cover its type. A missing alternative is reported, and so is a
value outside the selector type, a case after the remaining type is empty, or an
unnecessary `else`. See
[unions.md](../type-system/unions.md#exhaustiveness) for the union shapes that
are enumerable.

A union declared with `nupp.types.nonExhaustive()` among its alternatives
requires `else` however many cases are written, because the member that call
adds is one no case can name:

```nupp
local type Status = "ok" | "error" | nupp.types.nonExhaustive()

local label = switch status do
    case "ok" -> "fine"
    case "error" -> "broken"
    else -> "unrecognized"
end
```

The `else` there is never reported as unnecessary. See [Unions that may
grow](../type-system/unions.md#unions-that-may-grow) for what the member means
to a caller.

## Evaluation and placement

The selector runs once. Cases are tested from top to bottom. Static cases lower
to equality comparisons and type cases lower to the same predicates as `is`.
The selected expression or block runs once; other arms do no work.

Switches may nest. An inner switch used as the outer selector finishes first,
and its result becomes the outer switch's single selector value. An inner switch
written in an arm stays lazy: it is lowered inside that arm and does not
evaluate unless the arm is selected.

### Conditionally evaluated positions

The initial placement model accepts switches lifted from local declarations,
assignments, returns, and call statements when eager left-to-right evaluation
can be preserved. It rejects a switch in conditionally evaluated work:

::: code-group
```nupp [Nupp]
local selected = ready and switch code do
    case 200 -> "ok"
    else -> "other"
end
```

```text [Diagnostic]
error: NUPP2142: a switch in this conditionally evaluated position is not
supported yet
 3 |     local selected = ready and switch code do
   |                                ^~~~~~
help: move the switch to a local before this expression
```
:::

Write the switch as a preceding local when eager evaluation is intended.

::: deepdive
Lowering a conditionally evaluated position through an immediately invoked
function would lift the restriction today. It breaks the no-closure invariant
exactly where it matters, because a switch inside `and` or `or` is usually
inside an expression inside a loop, and it makes the construct's cost depend on
where it was written.

The general answer is one normalization layer that turns a checked expression
and its continuation into lexical control flow while preserving evaluation
order, conditional evaluation, multi-result rules, scopes, ownership, and
cleanup. Conditional evaluation is the hard part: a naive statement prefix runs
the setup unconditionally, so normalization has to put the setup inside the
branch that reaches it.

```lua
local value = cached
if value == nil then
    local __subject = source
    if getmetatable(__subject).__index == File then
        value = readFile(__subject.path)
    else
        value = nil
    end
end
```

Solving that once serves every statement-shaped construct that wants an
expression position, rather than one set of ordering rules, each with its own
bugs, per construct.
:::

### Comptime and ahead-of-time subsets

Static cases with expression arms are supported by `comptime`. Comptime type
cases and block arms receive the targeted unsupported-construct diagnostic.
String cases, type cases, block arms, and early arm returns remain explicit
ahead-of-time subset boundaries. Ordinary Lua lowering supports the complete
switch described above. See
[ahead-of-time.md](../guides/ahead-of-time.md#scalar-switch-initializers) for
what the native backend accepts.

::: deepdive
An ahead-of-time switch whose selector has an established `int32` or `uint32`
representation lowers to a native C `switch`, leaving the C compiler to choose
branches, a search tree, bit tests, or a jump table. The backend gets there by
annotating the `If` that lowering already emits with the normalized integer
labels, rather than by adding a scalar-IR switch op. Lowering already produces
exactly the shape a native switch needs, so the emitter reads a fact instead of
reconstructing one, and a new op would have needed cases at seven `op == "if"`
sites plus verification, text, emission, and intensity analysis. Dropping the
annotation is always safe, which is what makes the lane path desugar before
rewriting.
:::

## Formatting

The formatter preserves two visible nesting boundaries: cases sit one level
inside the switch, and statements in a block arm sit one level inside their
case.

```nupp
local result = switch value do
    case 1 -> "one"
    case 2 -> do
        log("two")
        local two = "two"
        yield two
    end
    else -> "other"
end
```

An arm `end` aligns with its `case`; the final `end` aligns with the surrounding
statement. The selector-closing `do` stays on the selector's final logical line,
and formatting never separates contextual `yield` from the first token of its
operand. See [fmt.md](../guides/fmt.md#formatting-rules) for the rest of the
formatter's rules.

::: deepdive
Switch indentation is language surface here, not presentation. A formatter that
moved cases back to the containing statement's indentation would make the
construct read as something it is not, so the boundaries above are fixed rather
than offered as a style option. That constrains the formatter permanently, which
is the cost of having the shape carry meaning.
:::

## FAQ

### Can a case carry a guard condition?

No. A case is a static scalar or a type test, and a condition that depends on
anything beyond the selector belongs in the arm body or in an `if`. See [Static
cases](#static-cases) for the values a case accepts.

### Does an arm allocate a closure?

No. The arrow is shared vocabulary with short functions, and a switch lowers to
branches, generated locals, and merge labels. See
[performance.md](../guides/performance.md#switch-dispatch) for what that buys in
a hot loop.

### When does a switch beat an `if` chain?

When one subject is tested the same way by every branch and every path produces
one value. A switch states the facts an `if` chain leaves both the reader and
the compiler to recover, which is also what lets the backend replace the ordered
chain with a table read.

::: seealso
- [performance.md](../guides/performance.md#switch-dispatch) for the table-read
  plans and the conditions that keep ordered branches
- [narrowing.md](../type-system/narrowing.md#switch-arm-narrowing) for what a
  type case proves inside its arm
- [unions.md](../type-system/unions.md#exhaustiveness) for the union shapes a
  switch covers without `else`
- [ownership.md](../type-system/ownership.md#ownership-in-switch-patterns) for
  what a pattern binding does to an affine selector
:::
