# Nupp syntax

Nupp's grammar has two layers: LuaJIT's Lua dialect, and a typed layer written
on top of it. Both are implemented, and
[the ABNF grammar](../reference/grammar.md) is the normative definition.

```nupp:playground
local prices = {10, 20, 30}
local total = 0
for _, price in ipairs(prices) do
    total += price
end
```

Everything there is level 0, the untyped base. Level 1 is the annotations,
declarations, and contracts the checker reads.

## Level 0: untyped base

Level 0 is LuaJIT 3.0's dialect in full. See [the syntax-extension umbrella
issue](https://github.com/LuaJIT/LuaJIT/issues/1475) for the extensions LuaJIT
tracks. Nupp implements every one of them and takes nothing away.

### Bit and arithmetic operators

The bit operators are `&`, `|`, `~`, `<<`, `>>`, and the arithmetic right shift
`~>>`. Floor division is `//`.

```nupp
local flags = 0xf0
local mask = flags & 0xff
local high = mask ~>> 4
local half = mask // 2
```

Compound assignment covers `+=`, `-=`, `*=`, `/=`, `%=`, `//=`, `..=`, `&=`,
`|=`, `<<=`, `>>=`, `~>>=`, and `??=`.

```nupp
local total = 0
total += 1
total *= 2
total //= 3
```

### Customary operators

`!`, `&&`, `||`, and `!=` mean `not`, `and`, `or`, and `~=`. The ternary
`c ? a : b` chooses between two expressions.

```nupp
local loaded, failed = true, false
local ready = loaded && !failed
local mode = ready ? "run" : "wait"
```

Both forms of each operator compile, so the `customary-operator` lint reports
the customary one to keep a codebase on one of them. Suppress it per statement
with `@allow("customary-operator")`.

### Optional values

Safe navigation `?.` stops a member chain at the first `nil`, and `??`
supplies a fallback for one.

```nupp
local record Profile
    name: string
end

local record User
    profile: Profile?
    port: integer?
end

local function describe(user: User?): string
    local name = user?.profile?.name
    return `${name ?? "anonymous"}:${user?.port ?? 8080}`
end
```

`??=` assigns only when the target is `nil`, and is Nupp's own addition. The
other two are LuaJIT's.

```nupp
local function fill(user: User): nil
    user.port ??= 8080
end
```

### Bindings and control flow

`const` binds a name that cannot be reassigned, and `|params| -> expression`
writes a function as the expression it is.

```nupp
const LIMIT = 100
local double = |n| -> n * 2
```

`continue` skips the rest of one iteration.

```nupp
for _, x in ipairs({1, 2, 3}) do
    if x == 2 then
        continue
    end
    print(x)
end
```

### Numerals and named varargs

Underscores separate digits, the `LL`, `ULL`, and `i` suffixes make a cdata
number, and a named vararg parameter collects the call's extra arguments into a
table carrying their count as `n`.

```nupp
local big = 1_000_000
local wide = 1LL

local function count(...items)
    return items.n
end
```

### Interpolated strings

A backtick-quoted string interpolates each `${expr}` it holds through
`tostring`.

```nupp
local user = "ada"
local greeting = `hello ${user}, you have ${1 + 1} messages`
```

### Dedent blocks

`dedent` before a long string strips the indentation its lines share, so a
block of text can be indented with the code around it. An own-line closing
`]]` supplies the margin; an inline closing delimiter uses the longest
indentation every nonblank line has in common. Ordinary `[[...]]` strings stay
exact Lua strings.

```nupp
local function usage(): string
    return dedent [[
        nupp check [FILE...]
          --strict   hold every file to the strict floor
        ]]
end
```

```text [usage()]
nupp check [FILE...]
  --strict   hold every file to the strict floor
```

### Const tables

`const M.field = value` initializes an immutable field. Inside a fresh table
constructor, `const name = value` does the same for one named slot.

```nupp
local M = {}
const M.version = "1.0"
```

`const ...` before an outer field declaration applies immutability recursively
to the new table graph:

```nupp
local M = {}
const ... M.settings = {name = "nupp", nested = {count = 0}}
```

The checker rejects later writes through those paths. Plain `const M.field`
remains shallow: inner fields stay mutable unless they are themselves declared
`const`.

## Level 1: typed layer

Level 1 is what a `.nupp` or `.g.nupp` file adds, and a `.lua` file may not
use it. See [File extensions](strictness.md#file-extensions) for what each
extension turns on.

### Annotations and aliases

A name, parameter, or result takes a type after a colon. `type` names one,
including a union of other types or of string literals.

```nupp
local type Id = uint32
local type Color = "red" | "green" | "blue"

local function tint(id: Id, color: Color): string
    return `${id}:${color}`
end
```

### Declaration kinds

A `record` is a nominal Lua table with named fields.

```nupp
local record Point
    x: number
    y: number
end
```

A `struct` is the same declaration over FFI cdata with a fixed C layout.

```nupp
local struct Vec2
    x: float
    y: float
end
```

An `interface` is a contract that erases: a type satisfies it structurally, or
claims it with `is`.

```nupp
local interface Named
    name: string
end
```

See [records.md](../type-system/records.md) for the difference between the
first two, and [interfaces.md](../type-system/interfaces.md) for what
satisfying the third takes.

### Generics and predicates

Angle brackets after a declaration's name introduce type parameters, and a
`v is T` result declares that a function's `true` narrows its argument.

```nupp
local record Point
    x: number
    y: number
end

local function firstOr<T>(xs: {T}, fallback: T): T
    return xs[1] ?? fallback
end

local function isPoint(v: any): v is Point
    return type(v) == "table"
end
```

### C declarations

`cdef` declares a C type or function the FFI loads at run time.

```nupp
cdef struct timeval
    tv_sec: int64
    tv_usec: int64
end

cdef function usleep(usec: uint32): int32
```

### Ownership

A function returning `affine(T, cleanup)` hands back a value carrying a cleanup
obligation, and an ordinary local discharges it at the end of its scope.

```nupp
local record File
    closed: boolean
end

local function closeFile(takes file: File): nil
    file.closed = true
end

local function openFile(): affine(File, closeFile)
    return new File(closed = false)
end

local function readOnce(): nil
    local file = openFile()
    print(file.closed)
end
```

`unsafe do` is where an operation the checker cannot prove is written down.
See [ownership.md](ownership.md) for the obligations a scope carries, and
[Unsafe representation
boundaries](ownership.md#unsafe-representation-boundaries) for what the block
suspends.

### Assertions and tests

`as` asserts a type without checking it, and `is` tests one at run time. The
test is the only one of the two that emits code.

```nupp
local record Point
    x: number
    y: number
end

local function widen(v: any): number
    local n = v as number
    if v is Point then
        return v.x
    end
    return n
end
```

### Switch expressions

`switch selector do` dispatches in order and produces a value.

```nupp
local function label(status: integer): string
    return switch status do
        case 200 -> "ok"
        case 301, 302 -> "redirect"
        else -> "other"
    end
end
```

See [switch-expressions.md](switch-expressions.md) for arms, type binding,
destructuring, and block-arm `yield`.

### Type syntax

Types are built from a fixed set of forms.

| Form | Means |
| --- | --- |
| `T?` | T or nil |
| `T*` | pointer to T |
| `T*?` | pointer that may be NULL |
| `T[4]`, `T[?]` | C array, zero-based |
| `{T}` | Lua array, one-based |
| `{T, U}` | tuple |
| `{[K]: V}` | map |
| `{x: T, y: U}` | inline shape |
| `A \| B` | union |
| `const T` | read-only view |
| `function(A): B` | function type |
| `Box<T>` | generic application |
| `self` | the receiver, inside a declaration |

::: seealso
- [type-system/overview.md](../type-system/overview.md) for what the checker
  does with these forms
- [annotations.md](../reference/annotations.md) for the `@` annotations that
  decorate a declaration
- [grammar.md](../reference/grammar.md) for the normative production of every
  form on this page
:::

## Keywords are contextual

None of the level-1 introducers is reserved. `type`, `record`, `interface`,
`struct`, `const`, `cdef`, `from`, `unsafe`, `continue`, `module`, `export`,
`global`, `with`, `as`, `is`, `new`, `comptime`, `metamethod`, `takes`,
`borrows`, `exclusive`, `retains`, `releases`, `out`, `switch`, `case`, and
`yield` all keep their Lua meaning wherever a declaration cannot start.

```nupp
local switch = |n: integer| -> n + 1

local record = 5
print(type(record))
local with = "ok"
local called = switch(record)
```

The expression form is recognized only as `switch selector do ... end`. The
required `do` is the unambiguous boundary after an arbitrary selector, and it
keeps `switch(x)`, `switch {x}`, and `switch "x"` as ordinary Lua calls.

::: deepdive
Reserving these names is the smaller parser, and it makes `local record = 5` a
syntax error in a language whose first promise is that existing Lua compiles.
Position replaces reservation instead: an introducer introduces a declaration
only where one can start, and only when what follows it on the same line
agrees.

That costs one deliberate overlap, `local type Alias = 5`. Every other name is
recovered from where it appears. See [Plain Lua is valid
Nupp](#plain-lua-is-valid-nupp) for the overlap and how to write around it.
:::

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

### Required LuaJIT build

Generated Lua targets **LuaJIT 2.1.1784535649 or newer**, the first build
carrying the backported syntax extensions. `bin/nupp` checks `luajit -v` and
names the required build rather than letting a run fail on a line nobody wrote.

::: deepdive
Requiring a recent build buys shorter and faster output. A native `?.` is one
branch, where the equivalent lowering is a closure call, and the same holds for
the ternary, `??`, and compound assignment. Lowering them would have widened
the runtime floor to stock 5.1 at the price of making every program that used
them slower than the Lua somebody would have written by hand.

The floor is a build rather than a version because the extensions were
backported into 2.1 rather than released with 3.0. See
[installation.md](../getting-started/installation.md) for how to get one.
:::

### Pass-through syntax

Most of level 0 is written straight through, because LuaJIT 2.1 backported it:
the bit operators, the customary operators, `?:`, `?.`, `??`, compound
assignment, `continue`, `const`, short functions, and underscores and cdata
suffixes in numerals.

::: code-group
```nupp [Nupp]
local t = {x = 1}
local x = t?.x ?? 0
```

```lua [Generated Lua]
local t = {x = 1}
local x = t?.x ?? 0
```
:::

### Lowered syntax

Five level-0 constructs are lowered, because 2.1 did not take them, along with
the level-1 `is` test.

| Written | Generated |
| --- | --- |
| `a // b` | `math.floor((a) / (b))` |
| `a //= b` | `a = math.floor((a) / (b))` |
| `x ??= "set"` | `if x == nil then x = "set" end` |
| `function(...xs)` | `function(...) const xs = {n = select("#", ...), ...}` |
| `` `a is ${a}` `` | `("a is " .. tostring(a))` |
| `v is Point` | a `type()` comparison, with nil compared directly |

The rest of level 1 erases: annotations, `as`, generics, `unsafe do` (which
becomes `do`), and the `interface` and `type` declarations, which have no
runtime value at all. A `struct` and a `switch` are the other two constructs
with output of their own.

::: deepdive
Generated code never changes the line count. A cursor emits each token at its
source line and inserts newlines to catch up, never going back, so an
`@file.nupp` chunkname gives a correct traceback with no source map.

That is what constrains every lowering above to one line. `x ??= "set"`
becomes a complete `if` statement rather than a formatted block, and the named
vararg's table is built on the line its `function` keyword was on. A lowering
that needed two lines would cost either the line correspondence or a source
map, and every stack trace a reader ever sees is worth more than either.
:::

### Builtin functions

LuaJIT's `table.new` and `table.clear`, and Nupp's own `table.clone`, are
available directly in Nupp source. Each generated module binds a used builtin
once on its first line, so no source `require` is needed. Recognition follows
the prelude definition, so a local named `table` is left alone.

```nupp
local buffer = table.new(64, 0)
local copy = table.clone(buffer)
table.clear(buffer)
```

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

## FAQ

### Does running generated code need LuaJIT 3.0?

No. The syntax is LuaJIT 3.0's, but the output targets 2.1.1784535649 or newer,
which backported the extensions. See
[Required LuaJIT build](#required-luajit-build) for what the toolchain checks.

### Can a variable be named `record` or `switch`?

Yes. Every level-1 introducer is contextual, so `local record = 5` and
`switch(value)` keep their Lua meaning. The one exception is
`local type Alias = 5`, which needs a newline or a semicolon after `type` to
read as Lua.

### Does the typed layer change what a traceback points at?

No. Generated code never changes the line count, so a runtime error names the
line you wrote. See [Lowered syntax](#lowered-syntax) for the constructs that
still produce code, and [constructs that aren't erased](strictness.md#constructs-that-arent-erased)
for the two that leave a runtime trace.
