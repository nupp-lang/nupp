# Declarations and modules

A typed declaration says where it lives, using the spelling Lua already has for
saying where a definition lives. There is no fourth rule to learn and no
default to remember.

| form | value side (plain Lua) | type side |
| --- | --- | --- |
| local record R | file-local | file-local |
| record M.R | a member of M | a member of M |
| global record R | a _G global | a project global |

The parallel is exact: `record M.Point` is to `record` what `function M.f` is
to `function`. A dot puts the thing on a table; `local` keeps it in the file;
neither makes it global.

## Module forms

```nupp
local models = {}

-- Private to this file. Nothing outside can name it.
local type UserId = uint32

-- A member of models, reached elsewhere as models.User.
record models.User
    id: UserId
    name: string
end

-- Visible project-wide with no import at all. Rare, and deliberately loud.
global type AppId = uint64

return models
```

A declaration that names none of the three is refused:

```nupp
record Loose -- NUPP2119: declaration "Loose" has no visibility;
    id: uint32 --   write it as models.Loose, or mark it local or global
end
```

Plain Lua would have made `Loose` a global. Rather than reuse that silence for
a different meaning, Nupp asks. This is the one place the language declines
to inherit a Lua default, because the cost of guessing wrong is a name that
means one thing here and another thing elsewhere.

## Naming a member from another file

A member is reached through the module it was attached to, so every name in a
file shows where it came from:

```nupp
local shapes = require("geom.shapes")

local p: shapes.Point = new shapes.Point(x = 3, y = 4)
```

A module path also names a type directly, without a runtime `require`:

```nupp
local p: geom.shapes.Point
```

The module itself is a value like any other, so it has to be required before its
name means anything. A file's basename is not in scope elsewhere:

```nupp
local doubled = mathutil.double(21) -- `mathutil` is just an unknown name
local mathutil = require("mathutil") -- this is what puts it in scope
```

An unknown name is `any`, as it is anywhere else, so the first line would
otherwise say nothing at all until it ran. Because a project file is named
after it, the checker knows better, and says so once per name:

```
error: NUPP2120: "mathutil" names a project module; require("mathutil") to use it
```

A build refuses it. The program does not work, because `mathutil` is `nil` when
it runs, and a compiler that can see why should not hand you a binary that fails
later. An editor reports the same thing as a warning: a file you are typing into
is half-written by definition, and the `require` is usually the next thing you
add.

This is the one diagnostic where a name being merely unknown is not the end of
it, so it is not `@allow`-able advice. If a project genuinely has an
undeclared global sharing a file's basename, the file or the global has to be
renamed.

Only a `global` is reachable without saying where it came from. There is no
project-wide search for an unqualified name, so adding a `Point`, or a
`mathutil.nupp`, to one corner of a project cannot change what a name means in
another.

## Returned module tables

A module's type is whatever the file returned. Nothing is merged in behind it. A
declaration that carries a runtime value puts itself on its table, which is an
ordinary assignment in the generated Lua:

```nupp
record shapes.Point -->  shapes.Point = {} shapes.Point.__index = shapes.Point
    x: number
    y: number
end
```

`type` and `interface` have no runtime value and emit nothing; they still name a
member on the type side. Records and structs are values too, which is what lets
a dependent construct one:

```nupp
local p = new shapes.Point(x = 1, y = 2) -->  setmetatable({x = 1, y = 2}, shapes.Point)
```

Which local is the module is read off the `return` statement, so wrapping it
still works:

```nupp
return setmetatable(shapes, {}) -- shapes is still the module
```

One table deep, so the name a declaration binds under and the field it is
assigned to stay the same thing. `record m.sub.Deep` is refused. A record body
is where types nest, and it reaches through the table its owner sits on:

```nupp
local m = {}

record m.Shapes
    record Point
        x: number
    end

    type Id = uint32
end

local p: m.Shapes.Point = new m.Shapes.Point(x = 1)
```

Attaching to any other table is not an export. It is a perfectly good way to
group types privately:

```nupp
local shapes = {}
local internal = {}

record internal.Scratch -- file-private, despite the dot
    used: integer
end

return shapes
```

## Naming itself

Inside its own body a declaration answers to its simple name, so a recursive
field does not repeat the table it sits on:

```nupp
record shapes.Path
    points: {shapes.Point}
    cutFrom: Path? -- Path, not shapes.Path

    function count(self): integer
        return #self.points
    end
end
```

The binding lives and dies with the body. Outside it, the member is
`shapes.Path` like any other.

## Methods

Prefer implementing a record's methods inline, as `Path.count` above. Inline
methods keep behavior beside the fields and contracts it relies on, declare
`self` first, and are still emitted as ordinary `shapes.Path` methods. Use a
separate qualified method only when adapting a type outside its declaration.

## Conventions

None of this is enforced, and there is no naming lint, but it is what the
compiler's own sources and the generated documentation assume.

Use camelCase for functions, methods, locals, parameters, and fields. Use
PascalCase for nominal types: `User`, `HttpClient`, `ReadBuffer`. Names imported
from C keep the spelling of the C API, because those identify ABI symbols; a
camelCase local holding the module
(`local miniApi = require("native.mini")`) marks the boundary without
disguising the foreign name.

Module names are luacase: all lowercase, run together, with no separator of any
kind and in particular no underscore. `nupp.resources`, `nupp.io.processtypes`,
`nupp.resources.native`. A module name is a filesystem path before it is an
identifier, which is what stops it being spelled like every other name here.
Case does not survive that round trip: a case-insensitive filesystem resolves
`nupp.io.processTypes` to `processtypes.nupp` and a case-sensitive one does not,
so a mixed-case module name is a `require` that works on the machine it was
written on and fails on the next one. An underscore does survive, but it
competes with the dot — in a name like `nupp.resource_set` two separators divide
one name at two strengths, and nothing says which of them is the namespace. Lua
settled this before we arrived: `string`, `table`, `coroutine`, `os`.

Where a name wants two words, run them together while they still read as one
thing (`processtypes`), or make the second word a submodule when it really is
one (`resources.native`). If neither reads, the length is the symptom rather
than the problem: the module is holding two subjects and wants splitting, or it
is named for how it is built instead of what it is for.

For a module, keep helpers and internal aliases `local`, attach the exported
records, structs, functions, and values to the module table, and return that
table once at the end. Reserve `global` for a contract that genuinely belongs
to the whole project.

Annotate exported parameters and returns; let obvious locals infer. That keeps
public contracts stable without making bodies noisy.

Leading underscores mark privacy to the documentation generator: members
beginning with `_`, source files beginning with `_`, and anything under a
module named `internal` are omitted unless the docs target opts into private
output. A hidden member is left out of the rendered declaration as well as the
member table. Metamethods are exempt, since `__index` names the operation
rather than claiming privacy.

## Mutual recursion across files

Type resolution runs over declarations, not over loaded modules: a declaration
is nameable as soon as its header is parsed, before any body is checked. Two
modules may therefore refer to each other's types freely. The runtime `require`
is a separate matter and follows ordinary Lua rules, so a genuine load-time
cycle, meaning two modules constructing each other's records while loading, is
still a genuine cycle, and is reported as one.

This is also what keeps rebuilds cheap: a file's interface is derived from its
declaration headers, so editing a function body cannot change it, and
dependents are not rechecked.

## Declaration files

A `.d.nupp` file describes an interface it does not own and returns no table of
its own, so there is nothing for a declaration to attach to. A bare declaration
there *is* the interface being described, and is allowed:

```nupp
-- string.buffer, described rather than defined
record Buffer
    put: function(b: Buffer, ...: any): Buffer
end

local new: function(size: integer?): Buffer

return {new = new}
```

In a declaration file `local` is not privacy either; it marks the bindings the
described module exports. See the documentation section of the README.

## Annotation definitions

An annotation definition is registered project-wide under its own name, since
applications spell an unqualified `@name` and there is no table to reach it
through. It is the other exemption from NUPP2119. See
[annotations.md](annotations.md).

## Worked example

`src/geom/shapes.nupp`:

```nupp
local shapes = {}

--- A point in the plane.
record shapes.Point
    x: number
    y: number
end

--- A closed path, which may name the shape it was cut from.
record shapes.Path
    points: {shapes.Point}
    cutFrom: Path?

    function count(self): integer
        return #self.points
    end
end

type shapes.Drawable = shapes.Point | shapes.Path

local type Scratch = {integer} -- private to this file

function shapes.origin(): shapes.Point
    return new shapes.Point(x = 0, y = 0)
end

return shapes
```

`src/app/main.nupp`:

```nupp
local shapes = require("geom.shapes")

local p: shapes.Point = new shapes.Point(x = 1, y = 2)
local path: shapes.Path = new shapes.Path(points = {p}, cutFrom = nil)
local d: shapes.Drawable = p

print(path:count(), shapes.origin().x, d is shapes.Point)
```

## Diagnostics

- **NUPP2119**: a declaration names no visibility and no table to attach to.
  Write `local`, `global`, or a qualified name. Also raised when a modifier sits
  beside a qualified name, which says where it lives twice.
- **NUPP2101**: unknown type name. An unqualified name that is a member of some
  module reports this rather than resolving: name the module.
- **NUPP2102** / **NUPP2104**: two project globals share a type or value name.
  Globals are one flat namespace, so one of them has to become a member.
- **NUPP2120**: a project module is used without being required. An error in a
  build, a warning in an editor. Given once per name, and it replaces NUPP2105
  for that name.
- **NUPP2105** (strict files): unknown variable, for names no project file
  answers to. Reported in a `.nupp` file, and in any file under `--strict`.
- **NUPP1006**: the typed layer written in a `.lua` file, which is plain Lua.

NUPP2119, NUPP2101 and NUPP2120 carry machine-applicable fixes, which the LSP
server offers as quick fixes. Each way out a message names is its own fix rather
than a choice made for the author: NUPP2119 offers `local`, `global`, and, where
the file returns a table, attaching to it; NUPP2101 offers the qualified
spelling through each module exporting that name, adding the `require` in the
same edit when the file has none; NUPP2120 offers one require per candidate
module. A fix that would bind over a name already in scope is not offered at
all.