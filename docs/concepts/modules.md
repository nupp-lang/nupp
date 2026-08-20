# Declared modules

A declared module is one real source file and one real Lua module. The first
declaration gives its canonical name, and `export` defines its public surface:

```nupp
module geom.shapes

local type Coordinate = number

export record Point
    x: Coordinate
    y: Coordinate
end

export const originName: string = "origin"

export function origin(): Point
    return new Point(x = 0, y = 0)
end
```

The file has its own private lexical scope. It does not create a global
`geom`, share locals with another file, or need a companion declaration file.
There is no final module-value `return`; the compiler creates and returns a
stable export table.

Legacy files that construct and return a table remain supported during
migration. They do not gain declared-module cycle behavior or qualified
namespace access.

An established table-shaped module can adopt a declared identity without a
large internal rewrite:

```nupp
module geom.shapes

local shapes = {}

record shapes.Point
    x: number
    y: number
end

function shapes.origin(): shapes.Point
    return new shapes.Point(x = 0, y = 0)
end

export = shapes
```

`export = value` is the migration form. The value is evaluated once and becomes
the module value itself, preserving table identity, mutable fields, and callable
metatables. It adds no loader, proxy, field copy, or wrapper to exported calls.
Prefer individual `export` declarations in new code: their compiler-created
stable table and written interfaces participate fully in grouped cycle checking,
while the migration form keeps ordinary Lua initialization and is gradual across
an active cycle.

::: rationale
A module is its own public declaration — no ambient table and no companion
declaration file repeats it. That constraint rejected most of the design space:
any option producing a second description of a module's surface was ruled out
however cheap it was to build, because the second copy is the one that goes
stale.

[NEP 7](../neps/0007-modules-and-lazy-loading.md) has the full record.
:::

## Canonical names

The declared name must equal the module name derived from the file's configured
source root. For example, `src/geom/shapes.nupp` declares
`module geom.shapes`. The `.g` marker in `shapes.g.nupp` is not part of the
name, and a final `/init` is erased.

Only that canonical name may be used by static imports. This prevents one file
from being initialized twice under different `package.loaded` keys. A
`.d.nupp` file describes an external interface and cannot declare a source
module.

Module segments use luacase: lowercase words run together, such as
`nupp.hotreload` and `nupp.workers.native`.

## Exports and privacy

Declarations are private unless marked `export`:

```nupp
module data.counter

local function clamp(value: integer): integer
    return math.max(0, value)
end

export type Count = uint32

export interface Reader
    read: function(self: Reader): Count
end

export function normalize(value: integer): integer
    return clamp(value)
end
```

Functions, records, interfaces, structs, type aliases, and constants can be
exported. An exported alias or interface exists only for checking. Records and
structs also export their runtime constructor value. Exported functions must
write their parameter and result types so a dependent never learns a public
contract by inspecting its body.

`global` is not allowed inside a declared module. Use `export` for its public
surface and `local` or `const` for private names. Exporting a nominal does not
change the visibility of members inside that declaration.

## Explicit imports

`require` stays the explicit, Lua-shaped import:

```nupp
module app.main

const shapes = require("geom.shapes")

export function makePoint(): shapes.Point
    return new shapes.Point(x = 1, y = 2)
end
```

A literal call through the unshadowed builtin is a static dependency and is
checked against the declared interface. A dynamic name or a locally shadowed
`require` keeps ordinary gradual Lua behavior.

Brace selection imports several values without repetitive field reads:

```nupp
const {origin, originName as label} = require("geom.shapes")
```

`as` changes the local binding name. The syntax is the same generic shallow
selection accepted by `local` and `const` for records and structural tables;
it is not a module-only destructuring form.

An erased type selection is available for declared modules:

```nupp
const {
    type Point as ShapePoint,
    origin as makeOrigin,
} = require("geom.shapes")
```

A statement containing only `type` selections emits no runtime `require`.
Selecting a record without `type` binds both its type and runtime declaration
value. An erased alias must be selected with `type`.

Binding patterns are shallow. They are not allowed in function parameter
declarations. Braces at a call site instead pluck named parameters from an
existing value:

```nupp
draw({x, y} = point, color = "blue")
```

## Qualified module paths

A registered package root lets an unshadowed dotted path name a declared
module directly:

```nupp
module app.read

export function read(pointer: voidptr, count: integer): nupp.mem.span.Span<uint8>
    return nupp.mem.span.fromCarray(pointer as uint8*, count)
end
```

The compiler resolves the longest registered module prefix. The remaining
segments must be exported members; a miss is diagnosed rather than falling
back to `any`. The facility is generic, so dependency roots such as
`tecs.world.query.each(...)` work the same way as `nupp`.

A lexical binding wins:

```nupp
local tecs = makeTestDouble()
tecs.world.query -- ordinary field access on the test double
```

Language intrinsics such as `nupp.pin`, `nupp.borrow`, `nupp.sizeof`, and
`nupp.types` keep their compiler meaning and are reserved against module or
export collisions.

Qualified access is lazy at the module boundary, not at every field access.
Each selected module becomes one hidden direct import in the containing Lua
chunk. Repeated source accesses reuse it:

```lua
local __nuppModule = require("nupp.mem.span")
return __nuppModule.fromCarray(pointer, count)
```

There is no per-call loader, proxy, metatable guard, or injected helper. A
module removed with dead code is not selected; a live reference loads once
when its containing module initializes, and Lua's `require` cache owns reuse.
Use an explicit dynamic `require` when runtime-first-use loading is genuinely
needed.

A qualified type path creates no runtime import when it is used only as a
type.

## Grouped checking and cycles

The compiler derives the static dependency graph and checks mutually dependent
modules as a group. This is generic project behavior, not a special standard
library mode and not a source keyword. Files keep separate lexical scopes,
generated chunks, caches, and Lua module identities.

Before checking bodies, the group publishes written exported type and function
signatures. Mutually referring exported types and functions therefore keep
their real types instead of degrading to `any`:

::: code-group

```nupp [a.nupp]
module a
const b = require("b")

export function fromA(value: integer): integer
    return b.fromB(value)
end
```

```nupp [b.nupp]
module b
const a = require("a")

export function fromB(value: integer): integer
    return value + 1
end

export function throughA(value: integer): integer
    return a.fromA(value)
end
```

:::

Runtime initialization is still eager. Each module publishes its stable export
table and hoisted function closures before loading dependencies. That makes the
cycle above safe: neither function is called until both modules finish loading.

A cycle is not safe when top-level evaluation immediately reads or calls an
export that the other module has not initialized. Moving that work behind an
exported function breaks the temporal dependency. Grouped checking makes names
available early; it does not invent results for cyclic top-level computation.

An initialization failure clears the partial `package.loaded` entry and
rethrows the original error rather than leaving a half-loaded module cached.

## Incremental checking

The project index first extracts parser-only headers: canonical name, raw
exports, written signatures, locations, and dependencies. The checker then
elaborates those headers into typed interfaces. Recursive requests inside an
active group see the already-published interface rather than an `any`
placeholder.

Changing a private function body rechecks that module without changing its
public interface. Changing an exported signature invalidates dependents. Each
module remains its own cache and build output even when several interfaces are
checked together.

## Legacy return-table compatibility

Existing Lua-shaped modules continue to work, but new Nupp modules should use
`module` and `export`. This form is retained for gradual migration and ordinary
Lua interoperability:

```nupp
local shapes = {}

record shapes.Point
    x: number
    y: number
end

function shapes.origin(): shapes.Point
    return new shapes.Point(x = 0, y = 0)
end

return shapes
```

Use `const shapes = require("geom.shapes")` to import one. Qualified namespace
paths intentionally resolve only declared modules, so migration is explicit
and cannot accidentally reinterpret an arbitrary Lua table as a package tree.

## Tooling

Formatting, semantic highlighting, definitions, rename, and completion
understand `module`, `export`, brace selection, and qualified paths. Completion
on a registered namespace lists child modules and exports. Definition on an
export reaches its declaration, and an exact module segment reaches the module
declaration.
