---
order: 80
---

# Switch expressions

A switch selects one value from ordered cases, evaluating its selector once and
running only the arm that matches. Nothing is wrapped in a function. The
examples below use local selectors.

```nupp:fragment
local label = switch status do
    case 200 -> "ok"
    case 301, 302, 307, 308 -> "redirect"
    case 400, 404 -> "client error"
    else -> "other"
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

```nupp:fragment
local kind = switch byte do
    case 9, 10, 13, 32 -> "space"
    case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57 -> "digit"
    else -> "other"
end
```

Cases are values rather than source forms. `1`, `1.0`, and `1e0` are the same
case, and `0` and `-0` are the same case, because a case denotes the finite
binary64 value compared at run time. That rule is local to switch cases
and does not widen the literal-type or const-generic domains described in
[unions.md](types/unions.md#literal-unions-are-enums). Operators,
calls, indexing, table constructors, cdata literals, and non-finite numbers are
not static cases.

An exact const name is useful when the name communicates more than its value:

```nupp:fragment
const READ: "read" = "read"
const WRITE: "write" = "write"

local access = switch mode do
    case (READ) -> "reader"
    case (WRITE) -> "writer"
end
```

The parentheses are required today: a bare `case READ ->` does not parse,
because the name and arrow are taken for the start of a short function.

## Type cases, binding, and destructuring

`case is T` performs the same test as `value is T`. It narrows the selector for
that arm. `as name` binds the narrowed whole value, and a brace list binds
direct fields:

```nupp:fragment
local description = switch shape do
    case is Circle as circle {radius} ->
        `circle ${circle.name}, radius ${radius}`

    case is Rectangle {width, height as h} ->
        `rectangle ${width} x ${h}`

    else -> "unknown"
end
```

Each binding is read off the one selector value, so a computed selector is
never evaluated twice.

All pattern bindings are const and scoped to their arm. `field as alias` changes
only the local binding name. Destructuring is direct, with no nested object
patterns, and a missing field or duplicate binding is reported. A binding
shares the selector's ownership identity rather than creating a second
obligation, so no arm can move an affine selector by matching on it.

Runtime identity follows `is`:

- primitives use `type()`;
- records use their nominal record shape;
- structs use their struct type's identity;
- refined interfaces use their declared runtime predicate.

An interface with no runtime identity cannot be tested. Type cases are ordered.
A broad case can consume the type a later case needs, and the later arm is then
reported as unreachable. See
[narrowing.md](types/narrowing.md#switch-arm-narrowing) for the facts
an arm may rely on.

## Guarded cases

`where predicate` narrows an arm with a condition its pattern cannot state. The
arm runs only when its pattern matches and the guard holds; when the guard is
false the value falls through to the arms below it. The guard is checked in the
arm's own scope, so it reads the bindings a type case introduced and sees the
selector already narrowed by the pattern:

```nupp:fragment
local reading = switch sample do
    case is Measurement as m where m.celsius > 100 -> "boiling"
    case is Measurement as m -> `${m.celsius} degrees`
    else -> "no sample"
end
```

The word is `where` rather than `and` because case values are read as ordinary
expressions, and `and` is an expression operator: `case "foo" and ready -> ...`
would parse as the single value `"foo" and ready` and quietly match the operand
to its right. `where` cannot continue an expression, so it ends the pattern
unambiguously.

## Expression and block arms

An expression arm produces its expression directly:

```nupp:fragment
local path = switch mode do
    case "read" -> inputPath
    case "write" -> outputPath
    else -> defaultPath
end
```

Use a [do expression](do-expressions.md) after `->` when an arm needs statements.
`yield value` supplies the switch result. It is not coroutine suspension. `return` still exits the enclosing
function immediately:

```nupp:fragment
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

`yield` stores the result and exits the do expression. It does not suspend. See
[suspension.md](../runtime/concurrency/suspension.md) for the construct that parks
a coroutine.

Every completing path through a block arm must reach one `yield`; a path may
instead `return` from the enclosing function. Falling through, or placing a
statement after a yield on the same path, is reported.

::: deepdive
Giving `return` the switch-result meaning would have been the smaller grammar,
and it was rejected. An arm is ordinary code, and code that reads as an early
exit has to be one. `yield` carries the result instead, targeting the nearest
enclosing do expression and never crossing a function boundary.
:::

### Contextual `yield`

`yield` is line-sensitive. These remain ordinary Lua calls:

```nupp:fragment
yield(value)
yield {value}
yield "value"
```

To supply one of those forms as an arm result, bind it and yield the name:

```nupp:fragment
local answer = {value}
yield answer
```

## Exhaustiveness and reachability

Every switch must be total. An `else` arm proves totality. It may be omitted
when the checker can prove that ordered cases consume the entire selector type.
Finite literal unions, `nil`, and both boolean values are enumerable:

```nupp:fragment
local type Mode = "read" | "write"

local access = switch mode do
    case "read" -> "reader"
    case "write" -> "writer"
end
```

Totality is the checker's guarantee, so nothing defends it at run time.

Type cases can likewise consume a closed union:

```nupp:fragment
local area = switch shape do
    case is Circle {radius} -> math.pi * radius * radius
    case is Rectangle {width, height} -> width * height
    case nil -> 0
end
```

A guarded arm proves nothing about coverage, because it may decline any value it
matches. It subtracts nothing from the residue the remaining arms must handle,
so a switch whose only arm for a value is guarded still needs `else`, and a
guarded arm never makes a later arm unreachable. A value repeated after an
*unguarded* arm is still a duplicate, since that arm did consume it.

An open selector such as `string`, `integer`, or `any` requires `else` unless
the arms already cover its type. A missing alternative is reported, and so is a
value outside the selector type, a case after the remaining type is empty, or an
unnecessary `else`. See
[unions.md](types/unions.md#exhaustiveness) for the union shapes that
are enumerable.

A union declared with `nupp.types.nonExhaustive()` among its alternatives
requires `else` however many cases are written, because the member that call
adds is one no case can name:

```nupp:fragment
local type Status = "ok" | "error" | nupp.types.nonExhaustive()

local label = switch status do
    case "ok" -> "fine"
    case "error" -> "broken"
    else -> "unrecognized"
end
```

The `else` there is never reported as unnecessary. See [Unions that may
grow](types/unions.md#unions-that-may-grow) for what the member means
to a caller.

## Evaluation and placement

The selector runs once. Cases are tested from top to bottom. Static cases are
equality comparisons and type cases are the same predicates as `is`.
The selected expression or block runs once; other arms do no work.

Switches may nest. An inner switch used as the outer selector finishes first,
and its result becomes the outer switch's single selector value. An inner switch
written in an arm stays lazy: it does not evaluate unless the arm is selected.

### Conditionally evaluated positions

Switches preserve conditional evaluation in `and`, `or`, `??`, ternary arms,
and safe-navigation work. Only the selected branch runs:

```nupp:fragment
local selected = ready and switch code do
    case 200 -> "ok"
    else -> "other"
end
```

### Comptime and ahead-of-time subsets

Static cases with expression arms, including do expressions, are supported by
`comptime`. Comptime type cases receive the unsupported-construct diagnostic.
Native AOT supports numeric, boolean, and string switches in expression positions,
including block arms and early function returns. Type cases remain outside its
current scalar subset. The VM supports the complete switch described above. See
[numeric-semantics.md](../performance/ahead-of-time/numeric-semantics.md#scalar-switch-expressions-and-do-blocks)
for
what the native backend accepts.

## Formatting

The formatter preserves two visible nesting boundaries: cases sit one level
inside the switch, and statements in a block arm sit one level inside their
case.

```nupp:fragment
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
operand. See [fmt.md](../tooling/formatter.md#formatting-rules) for the rest of the
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

Yes, written `case V where predicate`. The pattern itself stays a static scalar
or a type test, and the guard is the condition that pattern cannot state. A
guarded arm proves nothing about coverage, so the switch still needs whatever
`else` it needed without the guard. See [Guarded cases](#guarded-cases).

### Does an arm allocate a closure?

No. The arrow is shared vocabulary with short functions, and a switch is
branches, not a function.

### When does a switch beat an `if` chain?

When one subject is tested the same way by every branch and every path produces
one value. A switch states the facts an `if` chain leaves both the reader and
the compiler to recover, and the checker holds it to them: every value covered,
no arm unreachable.

::: seealso
- [narrowing.md](types/narrowing.md#switch-arm-narrowing) for what a
  type case proves inside its arm
- [unions.md](types/unions.md#exhaustiveness) for the union shapes a
  switch covers without `else`
- [ownership.md](../runtime/ownership/borrowing.md#ownership-in-switch-patterns) for
  what a pattern binding does to an affine selector
:::
