# Nupp syntax

Nupp's grammar has two layers. Level 0 is LuaJIT's Lua dialect, including every
LuaJIT 3.0 syntax extension. Level 1 is the typed layer on top. Both are
implemented, and the normative definition is
[the ABNF grammar](../grammar.md).

```nupp
local prices = {10, 20, 30}
local total = 0
for _, price in ipairs(prices) do
    total += price
end
```

## Level 0: the untyped base

This is LuaJIT 3.0's dialect
([the syntax-extension umbrella
issue](https://github.com/LuaJIT/LuaJIT/issues/1475)), in full:

```nupp
local mask = flags & 0xff -- bit operators: & | ~ << >> ~>>
local ok = a && b || !c -- customary operators: ! && || !=
local label = big ? "yes" : "no" -- ternary conditional
local name = user?.profile?.name -- safe navigation
local port = configured ?? 8080 -- nil-coalescing
count += 1 -- compound assignment
local half = total // 2 -- floor division
for _, x in ipairs(xs) do
    if skip(x) then
        continue
    end -- continue
end
const LIMIT = 100 -- immutable binding
local double = |n| -> n * 2 -- short functions
local big = 1_000_000 -- underscores in numerals
local wide = 1LL -- cdata number literal suffixes
local function sum(...items) -- named varargs
    return items.n
end
```

Nupp adds four things here and takes nothing away: interpolated strings
(`` `a is ${a}` ``), `dedent [[...]]` text blocks, `??=`, and type annotations
on short-function parameters. A `dedent` long string strips shared incidental
indentation; an own-line closing `]]` supplies that margin, while an inline
closing delimiter uses the common indentation of its content. Ordinary
`[[...]]` strings remain exact Lua strings.

### Const tables

`const M.field = value` initializes an immutable field. Inside a fresh table
constructor, `const name = value` does the same for one named slot.

`const ...` before an outer field declaration applies immutability recursively
to the new table graph:

```nupp
local M = {}
const ... M.settings = {name = "nupp", nested = {count = 0}}
return M
```

The checker rejects later writes through those paths. Plain `const M.field`
remains shallow: inner fields stay mutable unless they are themselves declared
`const`.

## Level 1: the typed layer

```nupp
local type Id = uint32 -- alias
local type Shape = Circle | Square -- union
local type Color = "red" | "green" -- closed set of strings
local record Point
    x: number
    y: number
end -- nominal table
local struct Vec2
    x: float
    y: float
end -- FFI cdata
local interface Named
    name: string
end -- erased contract

local function firstOr<T>(xs: {T}, d: T): T
end -- generics
local function isPoint(v: any): v is Point
end -- predicate

cdef struct timeval
    tv_sec: int64
end -- C declarations
cdef function usleep(usec: uint32): int32

local function open(path: string): affine(File, closeFile)
end

do
    local f = open("x")
end -- lexical owner scope
unsafe do
end -- unproved operations
local n = value as integer -- unchecked assertion
if v is Point then
end -- checked test

local label = switch status do -- value-producing ordered dispatch
    case 200 -> "ok"
    case 301, 302 -> "redirect"
    else -> "other"
end
```

Type syntax:

| Form | Means |
| --- | --- |
| T? | T or nil |
| T* | pointer to T |
| T*? | pointer that may be NULL |
| T[4] / T[?] | C array, zero-based |
| {T} | Lua array, one-based |
| {T, U} | tuple |
| {[K]: V} | map |
| {x: T, y: U} | inline shape |
| `A` | B | union |
| const T | read-only view |
| function(A): B | function type |
| `Box<T>` | generic application |
| `self` | the receiver, inside a declaration |

## Keywords are contextual

None of the level-1 introducers is reserved. `type`, `record`, `interface`,
`struct`, `const`, `cdef`, `from`, `unsafe`, `continue`, `global`, `with`, `as`,
`is`, `metamethod`, `takes`, `borrows`, `exclusive`, `retains`, `releases`,
`out`, `switch`, `case`, and `yield` all keep their Lua meaning wherever a
declaration cannot start:

```nupp
local record = 5 -- a variable named record
print(type(record)) -- the ordinary type() function
local with = "ok" -- a variable named with
local called = switch(value) -- the ordinary Lua function named switch
```

The expression form is recognized only as `switch selector do ... end`. The
required `do` is the unambiguous boundary after an arbitrary selector; it also
keeps `switch(x)`, `switch {x}`, and `switch "x"` as ordinary Lua calls. See
[switch expressions](../switch-expressions.md) for cases, type binding,
destructuring, block-arm `yield`, and placement rules.

That is what lets existing Lua keep compiling.

## Compatibility with Lua and LuaJIT

### Plain Lua is valid Nupp

Every valid LuaJIT program is a valid Nupp program. The compiler's test suite
pins this against a large body of real-world Lua: it must parse with no errors,
round-trip byte for byte, and check with no diagnostics.

There is exactly one deliberate overlap. Lua reads

```lua
local type Alias = 5
```

as the two adjacent statements `local type` and `Alias = 5`, while Nupp reads
it as a type alias. Put a newline or a semicolon after `type` to select the Lua
meaning:

```lua
local type
Alias = 5
```

One more thing changes without breaking: `a || b` now parses, as `a or b`,
where Lua 5.1 rejected it. It raises the `customary-operator` lint, which is a
house-style judgement a project can turn off.

### Generated code requirements

Generated Lua targets **LuaJIT 2.1.1784535649 or newer**, the first build
carrying the backported syntax extensions. `bin/nupp` checks `luajit -v` and
names the required build rather than letting a run fail on a line nobody wrote.

Most level-0 syntax is written straight through, because 2.1 backported it. A
native `?.` is one branch where the equivalent lowering would be a closure
call, so passing it through is both shorter and faster:

| Written | Generated |
| --- | --- |
| a & b | a & b |
| a >> 1 | a >> 1 |
| a > b ? "x" : "y" | a > b ? "x" : "y" |
| x ?? "fallback" | x ?? "fallback" |
| t?.x | t?.x |
| a += 1 | a += 1 |
|  | v | -> v + 1 |  | v | -> (v) |
| `continue` | continue |
| const X = 1 | const X = 1 |
| 1_000  /  1LL | 1_000  /  1LL |

Four constructs are lowered, because 2.1 did not take them:

| Written | Generated |
| --- | --- |
| a // b | math.floor((a) / (b)) |
| a //= b | a = math.floor((a) / (b)) |
| x ??= "set" | if x == nil then x = "set" end |
| `function(...xs)` | function(...) const xs = {n = select("#", ...), ...} |
| `a is ${a}` | ("a is " .. tostring(a)) |

Everything in level 1 erases: annotations, `as`, generics, `unsafe do` (which
becomes `do`), and the `interface` and `type` declarations, which have no
runtime value at all.

Generated code never changes the line count. A cursor only inserts newlines
forward, so a traceback points at the line you wrote with no source map.

LuaJIT's `table.new` and `table.clear`, and Nupp's own `table.clone`, are
available directly in Nupp source. Each generated module binds a used builtin
once on its first line; no source `require` is needed. Recognition follows the
prelude definition, so a local named `table` is left alone.

`table.clone` copies one level: the keys the table holds directly, plus its
metatable. A value that is itself a table stays shared, and `__index` is not
consulted, so the copy holds what `next` would have walked and inherits the
rest the same way the original did.

### Stock Lua 5.1

Generated code does not run on stock Lua 5.1 in general. Three things stop it:

- any passed-through extension is a 5.1 parse error, as is the `goto` that
  automatic cleanup lowering emits;
- `require("ffi")` is injected for any struct, `cdef`, `ffi.*` call, `carray`,
  or `cheader`;
- `require("table.new")` or `require("table.clear")` is injected when its
  builtin is used, and `table.clone` injects its own definition; presizing also
  uses the `table.new` binding.

A file that uses none of those, and whose typed layer erases cleanly, does
generate plain 5.1 Lua. There is no flag that guarantees it.

## Next

- [Type system](../type-system/overview.md) covers what the annotations mean.
- [The grammar](../grammar.md) for the normative ABNF.
- [Declarations and modules](../modules.md) for visibility and module rules.
