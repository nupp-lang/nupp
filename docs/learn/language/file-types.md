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
    return new Point(x = p.x * k, y = p.y * k)
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

```lua
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
write `any` where that is the type the interface actually has. LuaJIT's
`string.buffer` `encode(v: any): string` does take any Lua value, and no
annotation written here changes what LuaJIT accepts. A declaration file cannot
declare a source module.

## Constructs that aren't erased

A `struct` has a checked fixed layout. Native LuaJIT targets lower it to FFI
cdata, while portable targets may select the table-backed struct provider. A C
header imports as checked declarations that load native symbols. Everything
else is ordinary Lua at run time: the types are gone, and what remains is what
you would have written by hand.

::: code-group
```nupp [Nupp]
local struct Vec2
    x: float
    y: float
end
```

```lua [Generated Lua]
const __nuppMt_Vec2 = {__index = {}}
const Vec2 = ffi.metatype(ffi.typeof("struct { float x; float y; }"), __nuppMt_Vec2)
```
:::

See [Structs](types/records-and-structs.md#structs) for the layout rules that
lowering follows.

::: seealso
- [type-system/overview.md](types/index.md) for what the checker
  infers before any annotation is written
- [syntax.md](syntax.md) for the typed layer a `.nupp` file may use
- [c-interop.md](../runtime/c-interop/index.md) for the declarations that survive erasure
- [diagnostics.md](../../reference/diagnostics.md) for every code the checker
  reports
:::

## FAQ

### Does existing Lua need conversion?

No. A Lua file stays valid in a `.lua` file, and `.nupp` modules require it and
are required by it like any other module. Move a file to `.nupp` when it needs
[typed syntax](syntax.md#level-1-typed-layer); `nupp migrate` writes annotated
Lua to a `.nupp` destination.

### Do file extensions change module identity?

No. The extension is not part of the module name, so `require("models")`
resolves `models.nupp` or `models.lua` alike, and nothing that requires a file
changes when it moves from one to the other. See [Canonical
names](modules.md#canonical-names) for how a module's name is derived from its
path.

### Do types exist at runtime?

Annotations, generics, interfaces, affine policies, and most other checked
constructs erase when source lowers to Lua. A `struct` retains a runtime
representation because its checked layout is the feature, and [C
declarations](../runtime/c-interop/index.md) remain runtime bindings because
they load native symbols. Ordinary typed code acquires no type registry or
runtime checker.
