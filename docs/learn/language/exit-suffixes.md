---
order: 80
---

# Exit suffixes

`or return`, `or break` and `or continue` leave on failure and yield a value
on success. Ordinary operands fail when their first result is nil or false;
direct [protected calls](#protected-calls) fail when they raise:

```nupp:fragment
local text = reader:read(4096) or return
```

They shorten the convention most of this language already follows: a call
returns a value first and an optional reason after it, and a caller that cannot
handle the failure passes it on. The line above means exactly this:

```nupp:fragment
local text, reason = reader:read(4096)
if text == nil then
    return text, reason
end
```

There are three exits and no more. `or else` is not one of them, because `??`
already supplies a fallback for nil and ordinary `or` already handles Lua
truthiness.

## Operands

The operand runs once. Its first result both decides and is the value: `nil` or
`false` takes the exit, anything else continues. The value is narrowed by the
same truthiness that selected it, so `string?` becomes `string` and `boolean`
becomes `true` — no second test is needed to use it.

An ordinary operand needs a fixed result count, results that are not a
correlated pack union, and a first result that can be both falsy and a value. Anything else is refused and keeps the explicit conditional:

```nupp:fragment
local always = nonOptional() or return  -- NUPP2149: never nil or false
```

No slot after the first may carry an owner, because the successful path
discards every one of them.

A safe call is admitted. The alternative safe navigation adds is the single nil
an absent receiver returns, so that arm takes the exit like any other falsy
first result — which means `obj?.read() or return` cannot tell an absent
receiver from a failed read. An explicit `if` over a safe call conflates them
the same way.

Only the first result is the expression's value, whatever the operand's width.
A binding list that takes two names from a suffix gets nil in the second, which
the `exit-suffix-binding` lint reports:

```nupp:fragment
local left, right = readPair() or return  -- right is always nil
```

A caller that wants the other results writes the conditional out.

## Failure forwarding

For an ordinary operand, `or return` returns the whole pack with its first
slot narrowed to the falsy part. That is what makes a wrapper type-check without inventing
values:

```nupp:fragment
function loadCount(store: Store): (integer?, Store.Problem?)
    local entry = store:fetch("count") or return

    return entry.value, nil
end
```

`store:fetch` returns `(Entry?, Store.Problem?)`, so the forwarded pack is
`(nil, Store.Problem?)`, which fits the declared results even though the
successful types differ. The policy never reads the reason's type: a string, a
record, a union, an integer code and `unknown` all behave the same here.

A `(boolean, E?)` helper forwards `(false, E?)`, not `(nil, E?)`, which is
why a boolean discriminator works as well as an optional one. The enclosing
signature judges the forwarded pack exactly as it judges a written `return`,
reporting `NUPP2002` when it does not fit.

## Protected calls

A direct `pcall` or `xpcall` operand tests the protected call's status and
produces the protected function's first result. A raise takes the exit;
`or return` forwards `nil, error`:

```nupp:fragment
function parsed(text: string): (Config?, unknown)
    local config = pcall(decode, text) or return
    return config, nil
end
```

A successful `nil` or `false` continues and remains the expression's value.
The status narrows the success/error alternatives, but does not remove nil or
false from the protected function's declared result type. Later successful
results are discarded and cannot carry owners. The protected function and its
arguments run once.

A raised value passes through unchanged, including a table or nil. `xpcall`
runs its handler before the stack unwinds; the handler's first result becomes
the failure value, with its declared type:

```nupp:fragment
function parsed(text: string): (Config?, string?)
    local config = xpcall(decode, tostring, text) or return
    return config, nil
end
```

`or break` and `or continue` likewise leave only when the protected call fails.
If an `xpcall` handler returns an owner, a loop exit cannot discard it;
`or return` needs a matching ownership annotation on the error result.
An explicit conditional is still needed to retain additional results, handle
failure locally, or narrow an `unknown` error to a more specific type. A local
function named `pcall` or `xpcall` follows the ordinary suffix rules.

## Loops and precedence

`or break` and `or continue` target the nearest enclosing loop and never cross a
function boundary; outside one they report the same way a written `break` or
`continue` does. A loop condition is lexically outside its own loop, so a suffix
written in one targets the loop around it. `or continue` in a `repeat`
condition is refused, because that condition is what `continue` jumps to.
Cleanup runs on every exit exactly as it does for the statements.

The suffix binds at the `or` tier, which is the loosest binary tier:

```nupp:fragment
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

A suffix is straight-line code — a branch and the exit — and introduces no
closure and no pack table. Comptime executes the same branch. A native AOT kernel does not admit the suffix and says so.
