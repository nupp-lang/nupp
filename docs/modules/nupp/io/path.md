`nupp.io.path` answers an immutable path value whose joining, normalizing and
splitting follow the platform's own rules. Reach for it when a program builds a
filesystem name or takes one apart, rather than when it reads the bytes behind
one.

```nupp:playground
const path = require("nupp.io.path")

local source = path.newPath("src", "app", "..", "main.nupp"):normalize()
assert(source:toString() == "src" .. path.separator() .. "main.nupp")
assert(source:fileName() == "main.nupp")
```

Every operation answers a new path, and two paths are equal when their native
text is. `tostring(path)` and `path:toString()` return that same text.

::: deepdive Paths live in a module of their own
Joining, normalizing and canonicalizing are the native library's, so a program
that reaches `nupp.io.path` carries that provider. A program that only wants a
byte buffer should not pay for it, and the split into a module is what keeps the
two apart. `nupp.io.uri` is separated from `nupp.io` for the same reason. See
[Compiler-native features](../../../guides/build.md#compiler-native-features)
for how a reached module selects the feature it needs.
:::

## Building a path

`path.newPath(first, parts...)` joins its components using the current platform's
rules. `join` appends more to a path already built, and both accept a string or
another path. `Path` has no public constructor; creation goes through `newPath`,
which interns recent paths in a bounded LRU cache.

```nupp
const path = require("nupp.io.path")

local native = path.newPath("out"):join("lib", "native")
assert(native:fileName() == "native")
```

`currentDirectory` and `separator` are functions on the module beside the
record, because neither builds a path out of components:

```nupp
const path = require("nupp.io.path")

local current, reason = path.currentDirectory()
assert(current, reason)
local log = current:join("var", "app.log"):withExtension("jsonl")
assert(log:extension() == "jsonl")
```

## Normalizing and resolving

`normalize` removes lexical `.` and `..` components without touching the
filesystem, so it answers even for a path that does not exist:

```nupp
const path = require("nupp.io.path")

assert(path.newPath("src", "app", "..", "main.nupp"):normalize():stem() == "main")
```

The four operations that consult the process or the filesystem can fail, and
each answers nil with a reason when it does.

- `absolute()` resolves the path against the process's working directory.
- `resolve(parts...)` makes it absolute, appends the parts, and normalizes.
- `canonicalize()` asks the filesystem for the real path, following every
  symbolic link, which requires the path to exist.
- `relativeTo(base)` expresses the path against another one, when both share a
  coordinate system.

```nupp
const path = require("nupp.io.path")

local real, reason = path.newPath("src"):canonicalize()
assert(real, reason)
assert(real:isAbsolute())
```

## Path components

`parent` answers another path or nil. `fileName`, `stem` and `extension` answer
the final component, that component without its extension, and the extension
without its dot:

```nupp
const path = require("nupp.io.path")

local source = path.newPath("src", "main.nupp")
assert(source:fileName() == "main.nupp")
assert(source:stem() == "main")
assert(source:extension() == "nupp")
assert(assert(source:parent()):toString() == "src")
```

`withFileName` and `withExtension` replace one component. Each takes one path
component and raises when handed text that is not one, so a separator smuggled
into a file name is reported where it was written rather than carried into the
path it would have produced:

```nupp
const path = require("nupp.io.path")

local report = path.newPath("out", "report.tmp"):withExtension("json")
assert(report:fileName() == "report.json")
```

`isAbsolute` and `isRelative` classify a path without accessing the filesystem.

::: seealso
- [files.md](files.md) for reading, writing and listing what a path names
- [uri.md](uri.md) for network and resource identity, which is URI text rather
  than a filesystem name
- [io.md](../io.md) for the byte buffers, readers and writers a file's contents
  move through
:::
