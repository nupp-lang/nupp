---
order: 40
redirects: learn/language/gradual-typing
---

# File types

A file's extension says what it holds: Nupp source, an interface somebody else
implements, or plain Lua the toolchain runs unchanged. One project mixes all
three, and a module's name never includes the extension.

```nupp
module models

export record Point
    x: number
    y: number
end

export function scale(p: Point, k: number): Point
    return Point(x = p.x * k, y = p.y * k)
end
```

## File extensions

| Extension | Holds |
| --- | --- |
| `.nupp` | Nupp source; unknown variables and untyped exports are errors |
| `.d.nupp` | declarations for an interface somebody else implements |
| `.lua` | plain Lua syntax; recognized type comments are imported |

## Unknown variables and untyped exports

Every `.nupp` file is held to two rules beyond ordinary checking. An unknown
variable is reported instead of typing as `any`, and an exported declaration
without an annotation is reported too, so nothing untyped crosses a module
boundary.

```nupp:fragment
module models

export function double(n)
    return n * factr
end
```

```text [nupp check models.nupp]
error: NUPP2106: an exported function must write its public result type
error: NUPP2106: an exported function must write every public parameter type
error: NUPP2105: unknown variable "factr"
```

Inside the file nothing more is asked. An unannotated local takes the type its
initializer settles and an unannotated parameter is `any`, as
[Inference](types/index.md#inference) describes.

## Plain Lua files

The toolchain requires, builds, and runs a `.lua` file unchanged. Nupp syntax is
refused there because the runtime file must remain Lua:

```lua:refused
local function double(n: integer): integer
    return n * 2
end
```

```text [nupp check helpers.lua]
error: NUPP1006: a type annotation is not plain Lua
```

LuaCATS, EmmyLua, and typed LuaDoc comments are always imported as checker
facts, so a Lua file can state the same contract without changing its runtime
syntax:

```lua
---@param n integer
---@return integer
local function double(n)
    return n * 2
end
```

Malformed or unsupported comment types recover locally to `any` and report a
`NUPP1008` warning. An unknown name in a `.lua` file is not reported, since it
may be a global the program sets at run time. See
[LuaCATS](../projects/integrations/luacats.md) for the comment forms and how
`nupp migrate` turns them into Nupp.

## Declaration files

A `.d.nupp` file describes an interface somebody else implements, and may
write `any` where that is the type the interface actually has. The
`string.buffer` `encode(v: any): string` does take any value, and no annotation written here
changes what the implementation accepts. A declaration file cannot
declare a source module.

## Constructs that aren't erased

A `struct` has a checked fixed C layout, and the program keeps that layout at
run time. A C header imports as checked declarations that load native symbols.
Annotations, generics, interfaces, affine policies, and `as` leave nothing in
the compiled program.

```nupp
local struct Vec2
    x: float
    y: float
end
```

See [Structs](types/records-and-structs.md#structs) for the layout rules.
