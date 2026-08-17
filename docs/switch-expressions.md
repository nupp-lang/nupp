# Switch expressions

A switch selects one value from ordered cases. The selector is evaluated once,
only the selected arm runs, and the switch itself can appear wherever its
current placement rules admit an expression.

```nupp
local label = switch status do
    case 200 -> "ok"
    case 301, 302, 307, 308 -> "redirect"
    case 400, 404 -> "client error"
    else -> "other"
end
```

The `do` after the selector is required. It gives the parser an unambiguous end
to any selector—including a call, table, string, parenthesized expression, or
multiline expression—without reserving `switch` as a keyword:

```nupp
local a = switch(value)                 -- ordinary call
local b = switch {value}                -- ordinary call sugar
local c = switch "value"                -- ordinary call sugar

local selected = switch (value) do      -- switch expression
    else -> value
end
```

## Static cases

Static cases use primitive Lua equality. An allowed value is:

- `nil`, `true`, or `false`;
- a string literal;
- a finite Lua number literal, optionally preceded by `-`;
- parentheses around an allowed value; or
- a name whose checked type is one exact scalar value.

Several values may share an arm:

```nupp
local kind = switch byte do
    case 9, 10, 13, 32 -> "space"
    case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57 -> "digit"
    else -> "other"
end
```

Cases are values rather than source spellings. `1`, `1.0`, and `1e0` are the
same case; `0` and `-0` are the same case. Repeating one is `NUPP2138`.
Operators, calls, indexing, table constructors, cdata literals, and non-finite
numbers are not static cases (`NUPP2137`). There is no Ruby-style `===` hook or
user-defined matching protocol.

An exact const name is useful when the name communicates more than its value:

```nupp
const READ: "read" = "read"
const WRITE: "write" = "write"

local access = switch mode do
    case READ -> "reader"
    case WRITE -> "writer"
end
```

## Type cases, binding, and destructuring

`case is T` performs the same test as `value is T`. It narrows the selector for
that arm. `as name` binds the narrowed whole value, and a brace list binds
direct fields:

```nupp
local description = switch shape do
    case is Circle as circle {radius} ->
        `circle ${circle.name}, radius ${radius}`

    case is Rectangle {width, height as h} ->
        `rectangle ${width} x ${h}`

    else -> "unknown"
end
```

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

```nupp
local path = switch mode do
    case "read" -> inputPath
    case "write" -> outputPath
    else -> defaultPath
end
```

Use `-> do` when an arm needs statements. `yield value` supplies the switch
result. It is not coroutine suspension. `return` still exits the enclosing
function immediately:

```nupp
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

Every completing path through a block arm must reach one `yield`; a path may
instead `return` from the enclosing function. Falling through, or placing a
statement after a switch yield on the same path, is `NUPP2141`.

`yield` is contextual and line-sensitive. These remain ordinary Lua calls:

```nupp
yield(value)
yield {value}
yield "value"
```

To return one of those forms from a switch, bind it and yield the name:

```nupp
local answer = {value}
yield answer
```

## Exhaustiveness and reachability

Every switch must be total. An `else` arm proves totality. It may be omitted
when the checker can prove that ordered cases consume the entire selector type.
Finite literal unions, `nil`, and both boolean values are enumerable:

```nupp
local type Mode = "read" | "write"

local access = switch mode do
    case "read" -> "reader"
    case "write" -> "writer"
end
```

Type cases can likewise consume a closed union:

```nupp
local area = switch shape do
    case is Circle {radius} -> math.pi * radius * radius
    case is Rectangle {width, height} -> width * height
    case nil -> 0
end
```

Open selectors such as `string`, `integer`, or `any` generally require `else`.
A missing alternative is `NUPP2140`. A value outside the selector type, a case
after the remaining type is empty, or an unnecessary `else` is `NUPP2139`.

## Evaluation, lowering, and performance

The selector runs once. Cases are tested from top to bottom. Static cases lower
to equality comparisons and type cases lower to the same predicates as `is`.
The selected expression or block runs once; other arms do no work.

The universal lowering uses lexical selector/result locals and an
`if`/`elseif` chain. It does not wrap the switch in an immediately invoked
function. Consequently, writing a switch in a hot loop does not add
function-construction bytecode that would abort and blacklist LuaJIT traces.
Type-case bindings also reuse the one selector local, so a computed selector is
never repeated for `is` or field loads.

Some static switches can finish the decision with one compiler-owned table
read. This is deliberately narrower than “every arm is an expression.” Every
case and result, including `else`, must be one compiler-known inert scalar. A
dynamic expression still runs only after its case is selected and therefore
keeps the lexical branch lowering:

```nupp
-- Branches: formatStatus must run only for the selected arm.
local shown = switch status do
    case 200 -> formatStatus(status)
    case 301 -> "redirect"
    else -> "other"
end
```

A sufficiently large eligible map may use a dense integer array or a table
keyed by sparse integers or strings:

```nupp
-- Five labels in a span of five are eligible for a dense array.
local category = switch byte do
    case 9 -> "tab"
    case 10 -> "newline"
    case 11 -> "vertical tab"
    case 12 -> "form feed"
    case 13 -> "return"
    else -> "other"
end

-- Sixteen labels spread over a much wider span are eligible for a sparse map.
local retry = switch status do
    case 408 -> true
    case 409 -> true
    case 421 -> true
    case 423 -> true
    case 425 -> true
    case 426 -> true
    case 428 -> true
    case 429 -> true
    case 500 -> true
    case 501 -> true
    case 502 -> true
    case 503 -> true
    case 504 -> true
    case 505 -> true
    case 506 -> true
    case 507 -> true
    else -> false
end

-- Eight strings meet the string-map floor. This map needs a nil sentinel.
local keyword = switch word do
    case "and" -> "operator"
    case "break" -> "statement"
    case "do" -> "block"
    case "else" -> nil
    case "end" -> "block"
    case "false" -> "literal"
    case "for" -> "loop"
    case "function" -> "declaration"
    else -> "name"
end
```

The table is allocated once in generated module setup, never at the switch
site. A missing key is already `nil`, so integer maps perform no range guard and
holes need no placeholder. An arm which itself produces `nil` is the exceptional
case: generated data uses a private sentinel to distinguish that hit from a
miss. The sentinel is omitted from every map without a nil result.

Coverage builds always retain ordered branches because each authored case needs
one instrumentable condition. The optimizer also keeps branches for small maps,
block arms, destructuring, contextual `yield`, early `return`, refinements, and
any result whose evaluation can be observed. Exact thresholds are measured
implementation details rather than language promises.

Record cases use nominal metatable identity. When checking proves that the
remaining selector is entirely records, lowering reads `__index` without a
safe-navigation guard and may share that identity read across a leading run of
record cases. An optional, gradual, primitive, refined, or otherwise open
selector keeps the guarded or authored-order predicate.

The initial placement model accepts switches lifted from local declarations,
assignments, returns, and call statements when eager left-to-right evaluation
can be preserved. It rejects a switch in conditionally evaluated work:

```nupp
-- NUPP2142: the right side runs only when ready is truthy.
local selected = ready and switch code do
    case 200 -> "ok"
    else -> "other"
end
```

Write the switch as a preceding local when eager evaluation is intended. Lazy
placement awaits general expression normalization rather than silently changing
when the switch runs.

Static cases with expression arms are supported by `comptime`. Comptime type
cases and block arms receive the targeted unsupported-construct diagnostic. The
AOT scalar subset admits a switch that initializes one scalar local, uses
integer-valued numeric cases, has expression arms, and is checker-proven
exhaustive (with or without `else`). An established `int32` or `uint32` selector
is emitted as native C `switch`; an ordinary binary64 selector retains equality
branches because converting it would change semantics. The C compiler decides
whether native code becomes branches, a tree, bit tests, or a jump table.
String cases, type cases, block arms, and early arm returns remain explicit AOT
subset boundaries. Regular Lua lowering supports the complete switch described
above.

There is no per-dispatch C helper, function table, BDD, MTBDD, perfect hash, or
LuaJIT VM extension. Stock LuaJIT cannot jump from a computed case ordinal to an
arbitrary lexical arm, so a lookup is used only when it is the end of the
decision rather than the start of a second dispatch.

## Formatting

The formatter preserves two visible nesting boundaries:

```nupp
local result = switch value do
    case 1 -> "one"
    case 2 -> do
        log("two")
        yield "two"
    end
    else -> "other"
end
```

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
