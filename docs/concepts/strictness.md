# Gradual typing

Nupp is a gradual superset of LuaJIT's Lua, so every valid LuaJIT program is
already a valid Nupp program. What a file is named says how strictly it is
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

## Four extensions

| Extension | Floor | Effect |
| --- | --- | --- |
| `.nupp` | strict | unknown variables and untyped exports are errors |
| `.g.nupp` | gradual | the same typed syntax, without that floor |
| `.d.nupp` | gradual | declares an interface somebody else implements |
| `.lua` | gradual | plain Lua, and the typed layer is refused in it |

A `.lua` file is required, built and run unchanged. Writing an annotation there
is `NUPP1006` rather than a silently ignored comment, because the extension has
already settled that the file is Lua and an annotation written into it would
govern nothing.

## Strict adds two rules

An unknown variable is an error rather than a global read. An exported
declaration needs an annotation, so nothing untyped crosses a module boundary.

That is the whole difference. The typed syntax, the checker, and the generated
Lua are identical either way.

## Renaming is the migration

Write `.g.nupp` while a file is being typed and rename it to `.nupp` when it
holds the floor. The marker is not part of the module's name, so `models.g.nupp`
is the module `models`, `require("models")` finds it either way, and nothing
that requires the file changes when it moves.

```bash
nupp check --strict
```

That holds every file to the strict floor whatever it is called, which is how to
see what a rename would cost before making it.

## Erasure has two exceptions

A `struct` lowers to FFI cdata with a fixed layout, and a C header imports as
checked declarations. Everything else is ordinary Lua at run time: the types are
gone, and what remains is what you would have written by hand.

## FAQ

### Does existing Lua need conversion?

A valid LuaJIT program remains valid Nupp source when it stays in a `.lua` file.
Rename a file to `.g.nupp` only when it needs [typed
syntax](../type-system/overview.md), then move it to `.nupp` when the strict
floor is useful. Required modules may mix these extensions in one project.

### Do file extensions change module identity?

The extension chooses the typed layer and strict floor; it does not become part
of the module name. `require("models")` continues to resolve `models.g.nupp`
after it becomes `models.nupp`. Its `module models` declaration does not change,
and declarations remain private or exported exactly as written.

### Do types exist at runtime?

Annotations, generics, interfaces, affine policies, and most other checked
constructs erase when source lowers to Lua. A `struct` remains FFI cdata because
its C layout is the feature, and [C declarations](../c-interop.md) remain
runtime bindings because they load native symbols. Ordinary typed code acquires
no type registry or runtime checker.

## Diagnostics

- **NUPP1006**: the typed layer appears in a `.lua` file, which is plain Lua.
- **NUPP2105**: an unknown variable, in a strict file only.
- **NUPP2106**: an exported declaration needs a type annotation.

## Next

- [Declarations and modules](../modules.md): what `local`, `global` and a
  qualified name each say about where a declaration lives.
- [Type system](../type-system/overview.md): what the annotations mean once a
  file is being checked.
