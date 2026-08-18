# Switch expressions

A switch selects one value from ordered cases. The selector is evaluated once,
only the selected arm runs, and the switch itself can appear wherever its
current placement rules admit an expression.

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

The selector is bound once, the result once, and the arms become an ordered
`if`/`elseif` chain. Nothing is wrapped in a function.
[Performance](tooling/performance.md#switch-dispatch) covers when a static
switch finishes in one table read instead.

The `do` after the selector is required. It gives the parser an unambiguous end
to any selector—including a call, table, string, parenthesized expression, or
multiline expression—without reserving `switch` as a keyword:

::: code-group
```nupp [Nupp]
local a = switch(value)                 -- ordinary call
local b = switch {value}                -- ordinary call sugar
local c = switch "value"                -- ordinary call sugar

local selected = switch (value) do      -- switch expression
    else -> value
end
```

```lua [Generated Lua]
local a = switch(value)
local b = switch {value}
local c = switch "value"

local __nuppT1 = (value)
local __nuppT2
if true then __nuppT2 = value
end
local selected = __nuppT2
```
:::

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

Cases are values rather than source spellings. `1`, `1.0`, and `1e0` are the
same case; `0` and `-0` are the same case. Repeating one is `NUPP2138`.
Operators, calls, indexing, table constructors, cdata literals, and non-finite
numbers are not static cases (`NUPP2137`). There is no Ruby-style `===` hook or
user-defined matching protocol.

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

The parentheses are load-bearing today: a bare `case READ ->` does not parse,
because the name and arrow are taken for the start of another expression.

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
only the local binding name. Destructuring is direct—there are no nested object
patterns—and a missing field or duplicate binding is `NUPP2137`.

Runtime identity follows `is`:

- primitives use `type()`;
- records use nominal metatable identity;
- structs use `ffi.istype`;
- refined interfaces use their declared runtime predicate.

An interface with no runtime identity cannot be tested (`NUPP3001`). Type cases
are ordered. A broad case can consume the type a later case needs, making the
later arm unreachable (`NUPP2139`).

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
suspension. The `return` stays an ordinary early return out of the function.

Every completing path through a block arm must reach one `yield`; a path may
instead `return` from the enclosing function. Falling through, or placing a
statement after a switch yield on the same path, is `NUPP2141`.

`yield` is contextual and line-sensitive. These remain ordinary Lua calls:

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

To return one of those forms from a switch, bind it and yield the name:

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

Open selectors such as `string`, `integer`, or `any` generally require `else`.
A missing alternative is `NUPP2140`. A value outside the selector type, a case
after the remaining type is empty, or an unnecessary `else` is `NUPP2139`.

## Evaluation and placement

The selector runs once. Cases are tested from top to bottom. Static cases lower
to equality comparisons and type cases lower to the same predicates as `is`.
The selected expression or block runs once; other arms do no work.

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

Write the switch as a preceding local when eager evaluation is intended. Lazy
placement awaits general expression normalization rather than silently changing
when the switch runs.

Switches may nest. An inner switch used as the outer selector finishes first,
and its result becomes the outer switch's single selector value. An inner
switch written in an arm remains lazy: it is lowered inside that arm and does
not evaluate unless the arm is selected.

Static cases with expression arms are supported by `comptime`. Comptime type
cases and block arms receive the targeted unsupported-construct diagnostic.
String cases, type cases, block arms, and early arm returns remain explicit AOT
subset boundaries. Regular Lua lowering supports the complete switch described
above.

The generated tabs above are the branch lowering every switch gets. When every
case and result is a compiler-known inert scalar and there are enough of them,
the chain is replaced by one table read instead; see
[Performance](tooling/performance.md#switch-dispatch) for those plans, the
record-identity sharing, and the AOT subset.

## Formatting

The formatter preserves two visible nesting boundaries:

::: code-group
```nupp [Nupp]
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

```lua [Generated Lua]
local __nuppT3 = value
local __nuppT4
if __nuppT3 == 1 then __nuppT4 = "one"
elseif __nuppT3 == 2 then
    log("two")
    local two = "two"
    __nuppT4 = two
else __nuppT4 = "other"
end
local result = __nuppT4
```
:::

The arm's operand is bound first because `yield "two"` would be an ordinary
call, as above.

Cases and `else` are one level inside the switch. Statements inside a block arm
are one level inside their case. An arm `end` aligns with its `case`; the final
`end` aligns with the surrounding statement. The selector-closing `do` stays on
the selector's final logical line, and formatting never separates contextual
`yield` from the first token of its operand.

## Diagnostics

- `NUPP2137`: invalid static case, field, or binding.
- `NUPP2138`: duplicate static value after normalization.
- `NUPP2139`: unreachable or selector-incompatible case.
- `NUPP2140`: non-exhaustive switch.
- `NUPP2141`: invalid block-arm completion or switch yield.
- `NUPP2142`: placement would change conditional evaluation.
- `NUPP3001`: a type case has no runtime identity.
