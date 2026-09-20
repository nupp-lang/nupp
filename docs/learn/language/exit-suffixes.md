---
order: 80
---

# Exit suffixes

`or return`, `or break` and `or continue` are contextual suffixes that leave
when an expression's first result is falsy, and yield that result when it is
not:

```nupp
local text = files.read(path) or return
```

They shorten the convention most of this language already follows: a call
answers a value first and an optional reason after it, and a caller that cannot
handle the failure passes it on. The line above means exactly this:

```nupp
local text, reason = files.read(path)
if text == nil then
    return text, reason
end
```

There are three exits and no more. `or else` is not one of them, because `??`
already supplies a fallback for nil and ordinary `or` already handles Lua
truthiness.

## What the operand must look like

The operand runs once. Its first result both decides and is the value: `nil` or
`false` takes the exit, anything else continues. The value is narrowed by the
same truthiness that selected it, so `string?` becomes `string` and `boolean`
becomes `true` — no second test is needed to use it.

The checker admits an operand whose result count is fixed, whose results are
not a correlated pack union, and whose first result can be both falsy and a
value. Anything else reports `NUPP2146` and keeps the explicit conditional:

```nupp
local always = nonOptional() or return  -- NUPP2146: never nil or false
```

No slot after the first may carry an owner, because the successful path
discards every one of them.

A safe call is admitted. The alternative safe navigation adds is the single nil
an absent receiver answers with, so that arm takes the exit like any other falsy
first result — which means `obj?.read() or return` cannot tell an absent
receiver from a failed read. An explicit `if` over a safe call conflates them
the same way.

Only the first result is the expression's value, whatever the operand's width.
A binding list that takes two names from a suffix gets nil in the second, which
the `exit-suffix-binding` lint reports:

```nupp
local left, right = readPair() or return  -- right is always nil
```

A caller that wants the other results writes the conditional out.

## What `or return` forwards

`or return` returns the operand's whole pack, with its first slot narrowed to
the falsy part. That is what makes a wrapper type-check without inventing
values:

```nupp
function loadCount(store: Store): (integer?, Store.Problem?)
    local entry = store:fetch("count") or return

    return entry.value, nil
end
```

`store:fetch` answers `(Entry?, Store.Problem?)`, so the forwarded pack is
`(nil, Store.Problem?)`, which fits the declared results even though the
successful types differ. The policy never reads the reason's type: a string, a
record, a union, an integer code and `unknown` all behave the same here.

A `(boolean, E?)` helper forwards `(false, E?)`, not `(nil, E?)`, which is
why a boolean discriminator works as well as an optional one. The enclosing
signature judges the forwarded pack exactly as it judges a written `return`,
reporting `NUPP2002` when it does not fit.

## Protected calls

`pcall` and `xpcall` have the layout backwards: the boolean comes first and the
protected function's results follow it. A direct call to either is refused as an
operand, naming the pair that answers the conventional order instead:

```nupp
const util = require("nupp.util")

function parsed(text: string): (Config?, unknown)
    local config = util.pcallse(decode, text) or return

    return config, nil
end
```

[`pcallse`](nupp.util) passes the raised value
through as `unknown`, so a function propagating it declares its reason
`unknown` and narrows at the edge that reports the error. `nupp.util.xpcallse`
takes a handler instead, which runs before the stack unwinds — so it can still
collect a traceback — and whatever it returns is the reason.

Neither wrapper stringifies, and neither can tell a protected function that
succeeded returning nil from one that raised. Where that matters, the explicit
`local ok, value = pcall(f)` is still the form to write.

## Loops, precedence and spelling

`or break` and `or continue` target the nearest enclosing loop and never cross a
function boundary; outside one they report the same way a written `break` or
`continue` does. A loop condition is lexically outside its own loop, so a suffix
written in one targets the loop around it. `or continue` in a `repeat`
condition is refused, because that condition is what `continue` jumps to.
Cleanup runs on every exit exactly as it does for the statements.

The suffix binds at the `or` tier, which is the loosest binary tier:

```nupp
local total = base + amount() or return          -- (base + amount()) or return
local ready = enabled and check() or return      -- the whole conjunction
local chosen = (mode ? first() : second()) or return
```

Without those last parentheses the ternary's own associativity is in charge and
the suffix belongs to `second()` alone.

The exit word begins on the same line as its `or`, takes no operand, and does
not chain. `||` is accepted wherever `or` is, subject to the usual
`customary-operator` lint.

`continue` remains an ordinary name everywhere else. Only the exact `or
continue` pair reads it as the exit word, so a program that holds a variable
named `continue` and writes `a or continue` now means the suffix.

## Lowering

The compiler lowers a suffix to straight-line statements — one local per result
slot, a branch, and the exit — and introduces no closure and no pack table.
Generated LuaJIT and portable Lua 5.1 agree, and comptime executes the same
branch. A native AOT kernel does not admit the suffix and says so.
