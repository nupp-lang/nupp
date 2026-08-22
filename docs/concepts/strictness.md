---
order: 40
---

# Gradual typing

Nupp is a gradual superset of LuaJIT's Lua, so every valid LuaJIT program is
already a valid Nupp program. A file's extension says how strictly it is
checked, which puts that decision where the file is rather than in a setting
that governs everything at once.

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

Saved as `.nupp`, that file is held to the strict floor. Saved as `.g.nupp` it
is the same program, checked the same way, without that floor underneath it.

## File extensions

Four extensions divide the typed layer from plain Lua, and the strict floor
from the gradual one.

| Extension | Floor | Effect |
| --- | --- | --- |
| `.nupp` | strict | unknown variables and untyped exports are errors |
| `.g.nupp` | gradual | the same typed syntax, without that floor |
| `.d.nupp` | gradual | declares an interface somebody else implements |
| `.lua` | gradual | plain Lua syntax; recognized type comments are imported |

The toolchain requires, builds, and runs a `.lua` file unchanged. Nupp syntax is
still refused because the runtime file must remain Lua, but LuaCATS, EmmyLua,
and typed LuaDoc comments are always imported as gradual checker facts:

```lua
local function double(n: integer): integer
    return n * 2
end
```

```text [nupp check helpers.lua]
error: NUPP1006: a type annotation is not plain Lua
```

Write the same contract in a Lua file without changing its runtime syntax:

```lua
---@param n integer
---@return integer
local function double(n)
    return n * 2
end
```

Malformed or unsupported comment types recover locally to `any` and report a
`NUPP1008` warning. There is no setting that disables comment ingestion. See
[LuaCATS](../integrations/luacats.md) for migration and compatibility.

A `.d.nupp` file is gradual because it describes an interface somebody else
implements, where `any` is often the type the interface actually has:
`string.buffer`'s
`encode(v: any): string` does take any Lua value, and no annotation written
here changes what LuaJIT accepts.

::: deepdive
The floor lives in the file name rather than in a project setting or a pragma.
A project-wide setting has one value, so the unit of migration becomes the
whole project and nobody schedules that. A marker inside the file is invisible
where files are listed, reviewed, and searched, and is silently copied or
dropped when a file is duplicated or rewritten.

A manifest `strict` key is refused for the same reason, with an error naming
the extensions that replaced it. A manifest key and a file name can disagree,
and then the file lies to the person reading it.

See [NEP 2](../neps/0002-gradual-typing.md) for more information.
:::

## Strict floor rules

The strict floor adds two rules. An unknown variable is reported instead of
typing as `any`, and an exported declaration without an annotation is reported
too, so nothing untyped crosses a module boundary.

```nupp
module models

export function double(n)
    return n * factr
end
```

```text [nupp check models.nupp]
error: NUPP2105: unknown variable "factr"
error: NUPP2106: exported "double" needs a type annotation
```

That is the whole difference. The typed syntax, the checker, and the generated
Lua are identical either way, and the same file under `.g.nupp` reports
neither. See [Strict floor](../type-system/overview.md#strict-floor) for where
the two rules sit among everything the checker does to every file.

## Renaming is the migration

Write `.g.nupp` while a file is being typed and rename it to `.nupp` when it
holds the floor. The marker is not part of the module's name, so
`models.g.nupp` is the module `models`, `require("models")` finds it either
way, and nothing that requires the file changes when it moves. See
[Canonical names](modules.md#canonical-names) for how a module's name is
derived from its path.

## Running checks

`nupp check` holds each file to the floor its extension asks for, and checks
the whole project when it is given no files.

```bash
nupp check src/models.nupp
```

`--strict` holds every file to the strict floor whatever it is called, which is
how to see what a rename would cost before making it.

```bash
nupp check --strict
```

`nupp build --json` reports the same diagnostics alongside what the build
wrote, so one call says both what failed and what landed.

## Constructs that aren't erased

A `struct` lowers to FFI cdata with a fixed layout, and a C header imports as
checked declarations that load native symbols. Everything else is ordinary Lua
at run time: the types are gone, and what remains is what you would have
written by hand.

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

See [Structs](../type-system/records.md#structs) for the layout rules that
lowering follows.

::: seealso
- [type-system/overview.md](../type-system/overview.md) for what the checker
  infers before any annotation is written
- [syntax.md](syntax.md) for the typed layer the extensions turn on
- [c-interop.md](c-interop.md) for the declarations that survive erasure
- [diagnostics.md](../reference/diagnostics.md) for every code the checker
  reports
:::

## FAQ

### Does existing Lua need conversion?

A valid LuaJIT program remains valid Nupp source when it stays in a `.lua`
file. Rename a file to `.g.nupp` only when it needs [typed
syntax](syntax.md#level-1-typed-layer), then move it to `.nupp` when the strict
floor is useful. Required modules may mix these extensions in one project.

### Do file extensions change module identity?

The extension chooses the typed layer and strict floor; it does not become part
of the module name. `require("models")` continues to resolve `models.g.nupp`
after it becomes `models.nupp`. Its `module models` declaration does not
change, and declarations remain private or exported exactly as written. See
[modules.md](modules.md) for the rest of the module model.

### Do types exist at runtime?

Annotations, generics, interfaces, affine policies, and most other checked
constructs erase when source lowers to Lua. A `struct` remains FFI cdata
because its C layout is the feature, and [C declarations](c-interop.md) remain
runtime bindings because they load native symbols. Ordinary typed code acquires
no type registry or runtime checker.
