---
order: 79
---

# Do expressions

A `do` expression runs statements and produces one value. `yield value` ends
its execution and supplies that value:

```nupp
local enabled = do
    if ready then
        yield true
    else
        yield false
    end
end
```

Use a ternary for a simple choice: `ready ? true : false`. Use a `do` expression
when computing the result needs local variables, loops, or early exits.

```nupp
local value = cached ?? do
    local response = fetch()
    validate(response)
    yield response.value
end
```

The block above runs only when `cached` is nil. Blocks also stay conditional in
`and`, `or`, ternary arms, safe calls, and switch arms. Other operands retain
their evaluation order. A block produces exactly one result, including when
the yielded expression is a call returning several values.

## Scope and exits

Locals belong to the expression's scope. The result type combines the types of
its yields. Every path that reaches the expression's end must yield a value;
falling through is `NUPP2141`.

`yield` exits the nearest enclosing **do expression**, including from a nested
loop or ordinary `do` statement. A nested do expression has its own result.
`return` exits the enclosing function. `break` and `continue` retain their
ordinary loop targets, and an [exit suffix](exit-suffixes.md) inside a do
expression takes the same targets the written statements would. Cleanup runs when any of these exits leaves its region.
A nested function cannot yield to a surrounding expression.

```nupp
local selected = do
    for _, candidate in ipairs(candidates) do
        if candidate.ready then
            yield candidate
        end
    end
    yield nil
end
```

`yield` is contextual and its operand must start on the same line. Existing
calls named `yield` remain calls: `yield(value)`, `yield {value}`, and
`yield "value"`. To yield a parenthesized expression, table literal, or string
literal, bind it to a local first, then yield that name.

## Switch arms and execution

A [switch](switch-expressions.md) arm written `-> do ... end` uses this same
expression. There is no separate switch-block result mechanism.

LuaJIT and portable Lua lowering use scoped locals, branches, and loop exits;
the expression itself introduces no function or closure. Do expressions also
work during `comptime` evaluation and native AOT compilation. In AOT, the
statements and result must fit the backend's existing supported types and
operations. This includes nested blocks, early function returns, and ordinary
loop exits; a block does not create a separate function boundary.

See [AOT expression blocks](../performance/ahead-of-time/numeric-semantics.md#scalar-switch-expressions-and-do-blocks)
for the native subset.
