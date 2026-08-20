---
title: Gradual typing and the strictness floor
status: Implemented
created: 2026-08-19
---

## Summary

Nupp is a superset of LuaJIT's Lua: every valid LuaJIT program is already a
valid Nupp program. How strictly a file is checked is decided by what it is
named, not by a project setting or a pragma. The extension is not part of the
module's name, so tightening a file is a rename and nothing that requires it
changes.

::: seealso
- [strictness.md](../concepts/strictness.md) for the floor as a reader meets it
- [overview.md](../type-system/overview.md) for the type system it sits under
:::

## Goals

- Let an existing codebase adopt Nupp without a conversion step, a
  configuration file, or a flag day.
- Make a file's strictness visible from the file, without opening it.
- Keep one checker and one code generator: a gradual and a strict file differ in
  what is *reported*, not in what is understood or emitted.

## Non-goals

- Soundness. The type system has deliberate holes and they are written down.
- A second dialect with different semantics.
- Inferring strictness from content.

## Motivation

Two failures stop gradual type systems from being adopted, and they pull in
opposite directions.

A project-wide setting has one value, so turning it on means fixing every file
at once. Nobody schedules that, so it stays off, and while it is off nothing
enforces the parts already finished.

Strictness declared inside the file, by a `--!strict` comment or a pragma, is
invisible in a directory listing, in a review diff that does not include the top
of the file, and in a code search. It is copied by accident when a file is
duplicated and dropped by accident when one is rewritten.

A file name is the one property every tool already shows, and a file is the
smallest thing a person edits, reviews, and moves.

## Overview and specification

### Syntax

There is none. The declaration is the file's extension:

- `.lua`: plain Lua, and the typed layer is refused in it.
- `.g.nupp`: typed syntax with no floor beneath it.
- `.d.nupp`: declares an interface something else implements.
- `.nupp`: typed syntax, held to the strict floor.

### Worked example

The same file under two names is the same program, checked the same way, with
and without the floor beneath it:

::: code-group
```nupp [models.g.nupp]
local function scale(point, factor)
    return {x = point.x * factor, y = point.y * factor}
end
```

```nupp [models.nupp]
local function scale(point: Point, factor: number): Point
    return new Point {x = point.x * factor, y = point.y * factor}
end
```
:::

Both are the module `models`, and `require("models")` finds either.

### Floor rules

An unknown variable is an error rather than a global read, and an exported
declaration needs an annotation. Keeping the difference that small is what makes
the cost of a rename predictable before making it.

### Lowering

Annotations, generics, interfaces, and affine policies erase. The generated Lua
for the strict file above is the generated Lua for the gradual one:

```lua
local function scale(point, factor)
   return setmetatable({x = point.x * factor, y = point.y * factor}, Point)
end
```

Two constructs survive, because their runtime representation is the reason
someone wrote them. A `struct` becomes FFI cdata with a fixed layout:

::: code-group
```nupp [Nupp]
local struct Vec2
    x: float
    y: float
end
```

```lua [Generated Lua]
local Vec2 = ffi.metatype(ffi.typeof("struct { float x; float y; }"), Vec2_mt)
```
:::

A `cdef` declaration is the other, and it stays a runtime binding because it
loads a native symbol. Nothing acquires a type registry or a runtime checker.

### Annotations in `.lua` are refused

An annotation written into a `.lua` file reports `NUPP1006`. The extension has
already settled that the file is Lua, so the annotation would govern nothing,
and a construct that silently governs nothing is worse than one that is refused.

## Risks and assumptions

- **This assumes renaming is cheap**, which holds because version control tracks
  renames and module identity is unaffected. A build system keyed on paths would
  break the migration story.
- **A project can sit in `.g.nupp` forever.** `nupp check --strict` reports what
  a rename would cost, but it is a report and not a ratchet.
- **Four extensions is a surface to learn.** The bet is that each is guessable
  and a reader meets at most two in an ordinary project.
- **"Types erase" is a useful lie**, and `struct` is exactly where a reader is
  most likely to assume erasure and be wrong about memory.

## Alternatives considered

**A project-wide setting**, as `tsconfig`'s `strict` does. One value for a whole
project makes the unit of migration the project, and puts the answer to "is this
file checked?" in a file the reader does not have open.

**A pragma inside the file**, as Luau's `--!strict` does. This gets the
granularity right and was the closest competitor. Rejected because the marker is
invisible where files are listed, reviewed, and searched, and because it can be
silently lost or copied.

**A separate strict dialect.** The superset property is why an existing codebase
can start at all, and a dialect that changes what a program means loses it on
the first file.

**Inferring the floor from content**, treating a fully annotated file as strict.
It makes the floor a consequence rather than a decision, so adding one untyped
local silently demotes a module and no diff shows it.

**Soundness.** Every hole buys compatibility with idiomatic Lua, and closing
them would reject programs that are correct and common.
