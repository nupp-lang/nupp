---
order: 500
title: Build system
---

# Project builds

A Nupp project is a `nupp.lua` manifest naming where source lives, what the
project depends on, and which targets it produces. `nupp build` compiles the
whole source set into the outputs those targets describe.

```lua
return {
   include = { "src" },
   build = {
      default = "app",
      targets = {
         app = { kind = "modules", entries = { "app.main" } },
      },
   },
}
```

## Source sets

Running `nupp build` without source arguments loads `nupp.lua` and compiles the
project's source set: every `.nupp` under the manifest's include roots, minus
the build output. Explicit source builds remain available as
`nupp build file.nupp`.

`entries` says where execution starts, and for a bundle which chunk becomes the
body. It does not say what exists. A build compiles what the project is written
in, the way a compiler compiles a source set, rather than walking `require`
edges out from an entry.

::: deepdive
The walk answers three questions at once and gets two of them wrong:

- a module nothing requires goes unchecked, so `nupp check` stops meaning "this
  project is well typed" and starts meaning "the part I could reach is";
- a module reached only through `require(name)`, where the name is computed, is
  absent from the build and therefore from any binary, and fails in front of a
  user with a filesystem search path that means nothing inside one file.

Removing unused code is a linker's job and should be invisible when it happens.
Measured on this compiler, the walk was removing one module out of seventy-one
and costing about sixteen kilobytes on a 1.6 MB binary.
:::

## Targets and outputs

A target names its kind, where execution starts, and the inputs it needs:

```lua
build = {
   outDir = "build",
   default = "app",
   targets = {
      app = {
         kind = "modules",
         description = "Build the application",
         entries = { "app.main" },
         resources = { "src/app/*.d.nupp" },
         dependencies = { "fast", "codec" },
      },
   },
},
```

Entries may be module names or `.nupp` paths. Generated Lua preserves module
paths beneath `outDir`, so `app.main` becomes `build/app/main.lua`.

### Dialect selection

Every target resolves one source-lowering dialect. `luajit` is the default;
`lua51` may be selected on the build table, inherited by its targets, or
overridden by one target:

```lua
build = {
   dialect = "lua51",
   targets = {
      portable = { entries = { "lib.main" } },
      native = { entries = { "app.main" }, dialect = "luajit" },
   },
}
```

`nupp build --dialect lua51` and `nupp check --dialect lua51` override the
selected target for that invocation and also work with explicitly named source
files. The resolved value appears in build and check JSON and in `nupp tasks`.
It is part of the cache key, so artifacts and checks from different dialects
cannot satisfy one another.

The `lua51` checker also requires a complete lowering or selected backend seam
for every reached construct and standard facility. See
[portable-libraries.md](portable-libraries.md) for dual targets, checked
backends, provider dependencies, and the runtime test matrix.

A target's `dependencies` are names, declared once at the top level of the
manifest and shared by every target that lists them:

```lua
dependencies = {
   fast = {
      kind = "c",
      sources = { "native/fast.c" },
      bindings = { header = "native/include/fast.h" },
   },
   codec = {
      kind = "cargo",
      manifest = "native/codec/Cargo.toml",
      library = "codec",
   },
},
```

Each kind has its own keys: see [C dependencies](#c-dependencies), [Rust
dependencies](#rust-dependencies), and [rock
dependencies](#rock-dependencies). The `test` action names the target to build
first and the command to run:

```lua
test = {
   build = "app",
   argv = { "luajit", "tests/run.lua" },
},
```

See [testing.md](testing.md) for what that command is handed and how its
results are reported.

### Resource destinations

Resource globs preserve paths relative to the nearest include root. A resource
table gives one source an explicit target-relative destination when its runtime
lookup is relative to another module:

```lua
resources = {
   {source = "src/public/schema.nupp", output = "app/data/schema.nupp"},
}
```

## Manifest validation

The manifest is validated before builds, checks, tests, and task queries.
Validation covers dense string arrays, required target inputs, supported
dependency kinds, named target and dependency references, and dependency
cycles. A target's `dialect` is `"luajit"` or `"lua51"`. Configuration errors
name the invalid field before any build work starts.

Every table in the manifest takes a closed set of keys, and one that is not in
it is refused by name, with the nearest spelling when there is one:

```text
nupp: build.targets.site has no key "custmCss"; did you mean "customCss"?
```

The sets cover the top level, the build section, every target, a docs target's
pages, `test`, `tasks`, `selfHost`, `fmt`, and each dependency. A dependency is checked against the
keys its own kind reads, since what a C build takes and what a rock takes have
almost nothing in common. Keys beginning with `_` are the build's own, folded
in from a command's options; a manifest has no reason to write one.

::: deepdive
A key nothing reads would otherwise take effect silently, which is the one way
a configuration file can lie to the person who wrote it: `custmCss` rendered a
site with the default theme and exited cleanly. Refusing the whole manifest
costs one error message on a typo and removes a class of bug whose only symptom
is that a setting appears not to work.
:::

## Listing targets

`nupp tasks` lists the manifest's build targets, configured test action,
self-host and fixpoint action, and any named `tasks` entries, and marks the
default build target. `nupp tasks <name>` prints the effective target
configuration, including manifest-level defaults such as `outDir`. Both forms
accept `--format json`, or `--json`, for build-tool integration; text is the
default.

```bash
nupp tasks
nupp tasks app --json
nupp task docs-serve
```

A named task also runs with `nupp task <name>`. See [tasks.md](tasks.md) for
the manifest shape a task takes.

## Removing build output

`nupp clean` removes the output paths of every configured target;
`nupp clean --target <name>` limits removal to one target. `--dry-run` prints
the paths without changing them. Clean rejects absolute paths, parent
traversal, and the project root before removing anything.

A multi-platform binary also accepts
`nupp clean --target <name> --platform <triple>`; `--platform all` and an
omitted platform remove all platform outputs owned by that target. A platform
option without a target is refused.

## Compiler-native features

Compiler-provided native APIs do not appear in `dependencies`. Their resolved
uses record effects while Nupp checks the target's complete source set, and the
build stages the matching providers automatically. For example, [](nupp.io.path)
records `native.path` and builds the compiler-owned Rust bridge into
`build/lib/nupp_native` with that feature compiled in; a target with no resolved
native use does not build or retain the library at all. The global [`nupp`
standard-library namespace](../concepts/standard-library.md) itself is always
created by generated code.

Nested members use the same exact resolution. `nupp.data.sha256(...)` selects
SHA-256, while an alias such as `local data = nupp.data` followed by
`data.sha256(...)` selects the same feature without also selecting UUID, JSON,
or UTF-8. Path, URI, UUID and SHA-256 share `build/lib/nupp_native`, built once
with the union of only their selected Cargo features. Pure facilities such as
buffers, checksums and `nupp.math` emit their Lua adapters but stage no native
artifact. At `-O1` and above the build recomputes these effects from the
post-folding tree, so a use found only in a constant-dead branch or loop is
removed with that code.

The registry also recognizes compiler-provided modules. `require("lpeg")`
selects native LPeg 1.1, while `require("re")` selects the bundled official Lua
frontend and implies LPeg. Every `nupp.peg` matcher also selects LPeg: Nupp may
emit a faster kernel for a recognized static graph, but the typed matcher shell
and general lowering share the same native feature. A local table named `nupp`,
or a computed `require`, does not claim a compiler feature: only the resolved
global path and literal module name do.

### Feature overrides

Detection is the default, not a requirement to configure every target. A
target may override one answer when it deliberately supplies or forbids a
provider: `true` forces inclusion, `false` forces removal, and an absent name
keeps the detected answer.

```lua
nativeFeatures = {
   json = true,
   lpeg = true,
   lua_utf8 = false,
   sha256 = true,
}
```

The forceable binary feature names are `json`, `lpeg`, `lua_utf8`, `path`,
`uri`, `uuid`, `files`, `process`, `workers`, `http`, and `sha256`. The
registered module effects include `jsonNative`, native `lpeg`, the Lua `re`
module that requires it, and `lua-utf8`. Bundled LuaRock modules are checked
too, so Lunamark contributes LPeg and lua-utf8 even when application source
does not require either one directly. Forced removal is an expert escape hatch:
if reachable code still requires that provider, the resulting program fails at
runtime in the usual way.

### Platform builds

A binary target may use `stub = "nupp"` to ask the source compiler to build its
own host with exactly the resolved host features. A path-valued `stub` remains
a prebuilt or third-party artifact and is never silently relinked. The same
compiler-owned target can name catalog platforms:

```lua
platforms = {
   "x86_64-unknown-linux-gnu",
   "aarch64-apple-darwin",
   "x86_64-pc-windows-msvc",
}
```

Build one with `nupp build --target app --platform <triple>` or all in manifest
order with `--platform all`. A multi-platform default output is
`<outDir>/<target>/<platform>/<target><executableSuffix>`; `platformOutputs`
may map configured triples to custom raw paths. POSIX platforms also own a
deterministic `.tar` which records mode `0755`.

An explicit macOS result is unsigned and build JSON reports
`distributionReady = false` with a signing notice. Sign it on macOS with
`codesign --force --sign - <binary>` for local execution; the release workflow
uses Developer ID signing and notarization instead.

Platform selection sets `layoutTarget` for that build and separates its cache
and completion state. The selected compiler-owned catalog stub satisfies every
resolved feature that has a host implementation, so files and process do not
stage a current-machine sidecar beside a foreign executable. Sidecar-only
features such as path, URI, UUID, HTTP and SHA-256 are refused until the catalog
has a provider artifact for that platform.

### Native artifacts

Native artifacts are sidecars for modules targets and ordinary prebuilt stubs.
Ship the target's `lib` directory with a binary unless its selected stub links
the provider itself; a Lua payload cannot embed a shared library. A one-file
`bundle` target with a detected native feature is refused rather than silently
becoming a sidecar package. See
[distribution.md](../reference/distribution.md#limits) for what a stamped
binary can and cannot carry.

## Documentation targets

A `kind = "docs"` target runs the parse-only documentation generator through
the same `nupp build --target` interface:

```lua
docs = {
   kind = "docs",
   sources = { "src" },
   format = "both", -- site, markdown, or both
   outDir = "build/docs",
   title = "Project API",
   includePrivate = false,
   github = "https://github.com/example/project",
   logo = "images/project.svg",
   public = "docs/public",
   customCss = "docs/site.css",
   constructorPattern = "^new",
   pages = {
      { glob = "docs/**.md" },
   },
}
```

The keys the target itself reads:

| Key | Effect |
| --- | --- |
| `sources` | Roots the API reference is read from |
| `format` | `site`, `markdown`, `json`, or `both` |
| `outDir` | Where the rendered output is written |
| `title` | The site's own title |
| `name` | Brand name beside the logo, when it differs from `title` |
| `description` | One line for the home page and the `llms.txt` index |
| `github` | Repository link in the header |
| `logo` | Image for the header brand, replacing the default mark |
| `favicon` | Icon linked from every page |
| `public` | Directory copied to the output root, for images and downloads |
| `customCss` | Stylesheet appended after the default theme |
| `lexers` | Directory of project Scintillua lexers, searched before the bundled ones |
| `includePrivate` | Renders the declarations privacy rules hide |
| `constructorPattern` | Lua pattern a constructor's last name segment matches |
| `pages` | Handwritten pages: a `glob` over a tree, a `directory`, or one `source` at one `path` |
| `diagnostics` | The generated diagnostic index, and the page it is appended to |
| `stdlib` | The generated LuaJIT standard library page |
| `dependencies` | Rocks to install before rendering, `lunamark` among them |

The appended `customCss` overrides the documented `--nuppdoc-*` custom
properties without changing other documentation targets. A page entry also
takes `redirects` for the routes it used to answer at, and `layout = "home"`
for a landing page, whose hero and feature showcase are written in the page's
own Markdown. See [doc.md](doc.md) for doc comments, page syntax, privacy
rules, and what each output format writes.

### Page trees

A page entry may name a `glob` instead of a `path` and a `source`. It then
stands for every Markdown file the pattern matches, each published where it
sits: `docs/guides/build.md` answers at `guides/build`, and an `index.md` names
the directory holding it rather than a route ending in `index`. `base` is the
directory routes are named from, defaulting to the fixed part the pattern opens
with, and `exclude` drops files the tree holds and the site does not publish.

```lua
{ glob = "docs/**.md", exclude = { "docs/style.md" } }
```

What a path cannot say, the page says in a frontmatter block of `key: value`
lines between `---` fences:

| Field | Effect |
| --- | --- |
| `order` | Where the page sits in the navigation |
| `title` | What navigation calls it, when its heading is not what to call it |
| `redirects` | Routes it used to answer at, separated by commas |
| `layout` | The layout it renders under, `home` being the one that differs |

Sections of the sidebar are the first segment of a route, in the order their
first page appears, so one `order` per page settles both the order of the
sections and the order inside them. A page that names none follows the pages
that do, in the order the directory lists them. A page that names no `title`
and carries no heading is titled by the module it documents, which is what a
module overview wants and how it stays correct when the module is renamed.

A page whose route a `directory` entry already publishes is left to that entry,
and so is the file the `diagnostics` index opens with. Sweeping a tree does not
publish either one twice.

### Page directories

A page entry may name a `directory` instead of a `source`. The entry then
stands for every `.md` file under that directory, published at `path` followed
by the file name without its extension, plus an index generated at `path`
itself. A document is published by existing, so nothing has to be added to the
manifest when one is written.

```lua
{ path = "neps", title = "NEPs", directory = "docs/neps" }
```

Each document may open with a frontmatter block of `key: value` lines between
`---` fences. `title` names the document, falling back to its first heading and
then to its file name. Every other field is rendered under the heading, so a
`status:` line appears on the page and in the generated index without being
written into the prose. A value may be quoted, and the quotes are dropped.

A file name beginning with digits and a hyphen, such as `0001-process.md`,
carries that number as the document's identity. The number is shown without its
padding and prefixed with the entry's `title` made singular, so a collection
titled `NEPs` titles its first document `NEP 1`.

`index.md` is the collection's own page rather than a document in it. Its prose
opens the index and the table of documents is generated below it. Links between
documents are written as ordinary relative Markdown links and are resolved to
routes like links in any other handwritten page.

Only the index appears in the navigation; its documents are reached from it. A
collection may therefore sit inside an existing section, so
`path = "reference/neps"` puts one under Reference without filling that
section's sidebar with every document it holds.

## Cache and failure behavior

Build state is JSON in `outDir/.nupp-state.json`. Cache keys cover source
content, configuration, compiler artifacts, native tool versions, flags,
target settings, and dependency inputs. Generated files are rewritten only
when their content changes. A missing or malformed state file causes a cold
build.

Warm builds reuse checked module records and generated Lua across processes. A
source edit checks and generates that module; dependents are only invalidated
when its exported interface fingerprint changes. Changes to project-wide type
declarations invalidate the project index, while body-only edits preserve it.
Deleting the state file, changing compiler or configuration inputs, or
modifying an emitted artifact safely falls back to the required cold work.

The optimization level and the set of `--relax` guarantees are among those
keys. `nupp build -O2` reaches the configuration before it is hashed, so
changing either invalidates every artifact built with the old optimizer
contract rather than leaving a project half compiled under each. Switching
therefore costs a cold build, and cannot produce a mixture. `-O0` is the
default and performs no rewrite; see the [performance
guide](performance.md#optimization-passes) for what the levels above it do.

### Compiler identity

"Changing the compiler" means changing the part of it that computes the answer
being reused, not changing any part of it. Module artifacts are keyed on what
compiling a module reaches; parsed headers on the parser; formatting verdicts
on the formatter; comptime type blueprints on the checker. Each is the digest
of that module and everything it requires, read off the compiler's own tree, so
a new command, a language-server change, or an edit to a diagnostic's prose
leaves all four reusable. Anything that cannot be read that way, such as a
compiler that is one bundled file or a `require` naming a computed module,
falls back to the digest of the whole compiler, which invalidates more than it
has to and never less.

### Shared content caches

Two of these stores hold answers about content rather than about a project: a
file's header and its formatting verdict are the same answers wherever the file
is. `NUPP_CACHE_DIR` names one directory for them, which is what a run making
many small projects wants, the test suite being one that makes a project per
case, so the second project starts from what the first worked out.

```bash
NUPP_CACHE_DIR=/tmp/nupp-cache nupp check
```

The build state is not moved by it: its records are keyed by module name, so
two projects sharing them would read each other's modules.

### Write ordering

The checker and generator finish before module outputs are changed. Each file
is written through a sibling temporary file, state is saved after the
artifacts, and `.nupp-complete` is written last. `bin/nupp` only selects a
compiler build carrying that marker; otherwise it falls back to the tracked
bootstrap compiler.

## Build progress and timing

A build run from a terminal names the module it is working on, on one line it
rewrites in place, and finishes with how long it took, where that time went,
and which modules cost the most of it:

```text
built compiler in 18.9s: 164 compiled, 0 reused
  check 16.1s  generate 952ms
  slowest
    nupp.compiler.gen            1.9s
    nupp.mem.heap                699ms
    nupp.compiler.check.calls    664ms
```

Time is accounted as a timeline: one activity is current at any moment, so
switching closes the one before it and the activities add up to the run rather
than overlapping it. They are `scan`, which is deciding what can be reused,
`check`, `generate`, `write`, `persist`, `dependencies`, `native`, `bundle`,
and `other` for what is left over. A warm build that compiles nothing still
reports `check`: deciding a module can be reused consults the exported call
guarantees of the modules it depends on, and answering that is a check.

Per-module numbers are exclusive. A module's check reaches its imports through
the query graph, so the time those take is charged to them rather than to
whichever module reached them first. Otherwise the slowest module would be
whichever one the build happened to start with.

Nothing is written unless standard error is a terminal, so a build driven by a
script is as quiet as it has always been. `--progress=always` reports anyway,
`-q` reports nothing, and `NUPP_PROGRESS` says the same thing with `always`,
`never` or `auto` for the builds nothing passes a flag to, including the rebuild
`bin/nupp` runs before every other command. `nupp build --json` carries the same
numbers in a `timing` object rather than writing a report.

## C dependencies

`kind = "c"` supports local sources, `pkgConfig`, compiler and linker flags,
include directories, and exact-revision Git sources:

```lua
zstd = {
   kind = "c",
   source = {
      git = "https://github.com/facebook/zstd.git",
      rev = "<full commit id>",
   },
   path = "lib",
   sources = { "*.c" },
   bindings = { header = "zstd.h" },
}
```

`pkgConfig` may be one package name or an array when a native library uses
several installed APIs, such as `{ "simdjson", "luajit" }`. The packages are
resolved together so their compiler and linker flags reach the same build.

Fetched Git trees live under `.nupp/deps` and require an explicit revision.
C builds emit a `.so`, `.dylib`, or `.dll` under `outDir/lib`. A configured
header is passed through `import-c`, and the resulting Nupp module is placed
under `outDir/generated` so it participates in normal module resolution.
`sources` and `headers` are path globs: `*` and `?` stay inside one component,
while `**/` matches zero or more directories. `pkg-config` output honors shell
quotes and backslash escapes, but is never expanded or executed by a shell.

### Header-only C dependencies

An API made entirely from `static inline` functions and function-like macros has
no native symbol for LuaJIT to load. Opt its binding into a generated bridge; no
empty `.c` source is required:

```lua
image = {
   kind = "c",
   includeDirs = { "native" },
   headers = { "native/**/*.h" },
   cflags = { "-std=c11", "-Wall", "-Werror" },
   cppflags = { "-DIMAGE_FAST=1" },
   bindings = {
      header = "native/image.h",
      bridge = true,
      macros = {
         IMAGE_CLAMP = {
            parameters = { "int32", "int32", "int32" },
            result = "int32",
         },
         IMAGE_IGNORE = {
            parameters = { "int32" },
         },
      },
   },
}
```

The binding keys have separate jobs:

| Key | Effect |
| --- | --- |
| `header` | Header to preprocess and import; required for generated bindings |
| `library` | Override the library name or path written into generated `cdef` declarations |
| `out` | Override the generated Nupp module path |
| `bridge` | Wrap eligible named `static inline` definitions from `header` |
| `macros` | Wrap only the listed function-like macros using explicit signatures |

Each macro recipe requires a dense `parameters` array. `result` is optional;
omit it for a void wrapper. The accepted value forms are `boolean`, `float`,
`number`, `integer`, `int8` through `int64`, and `uint8` through `uint64`.
Recipes do not accept pointer forms, varargs, or arbitrary C declarator text.
`bridge` controls inline discovery; a `macros` table can request macro wrappers
independently.

The header above is then consumed under the dependency name:

```nupp
local image = require("image")

local tripled = image.image_triple(14)
local clamped = image.IMAGE_CLAMP(20, 2, 8)
image.IMAGE_IGNORE(clamped)
print(tripled) -- 42
```

For the default `outDir`, a macOS build writes:

```text
build/generated/image.nupp
build/generated/image_bridge.c
build/lib/libimage.dylib
```

Linux uses `libimage.so`; Windows uses the platform DLL name. The generated
binding names that library `@lib/libimage.dylib`: a leading `@` is resolved
against the module that loads it rather than handed to the platform loader, so a
copied or moved output tree still finds it. A `kind = "bundle"`, `"binary"` or
`"component"` target is one file someone carries somewhere, so the build puts a
copy of the library beside the artifact, the way it already does for compiled
`@aot` code. A `bindings.library` override, a `load` naming a library already
installed, and a `pkgConfig` package are written through unchanged, since none
of them are part of what the build ships.

The generated translation unit includes the original header and exports only
deterministic private wrapper symbols. It is compiled with the dependency's
`cc`, `includeDirs`, `cflags`, `cppflags`, package flags, and linker inputs,
then installed into the same shared library as any ordinary `sources`. A
dependency containing only bridge wrappers still produces the library.

The dependency cache includes the header, source and bridge bytes, macro
recipes, compiler identity, flags, package flags, child dependencies, and
manifest configuration. A changed header or recipe regenerates both the module
and bridge. The binding's named header is tracked automatically; list its local
include closure under `headers` as above so a transitive header edit also
invalidates the native artifact. Disabling `bridge` and removing `macros`
produces no bridge source, compiler invocation, or bridge-only library.

Macro arity and type recipes are validated before a generated binding is
installed. The C compilation then validates the original macro expansion and
inline bodies under the selected flags. Either failure stops the dependency
build; compiler-failed generated source remains inspectable, but no successful
target may consume it. See [Calling C
safely](../concepts/c-interop.md#header-only-functions) for a complete header,
standalone bridge emission, inspection output, ownership refinements, and the
supported boundary.

## Rust dependencies

`kind = "cargo"` delegates package resolution and locking to Cargo. The
provider builds a `cdylib` into an isolated target directory and copies the
platform library into `outDir/lib`. `Cargo.lock` is enforced by default;
`locked = false` is available for newly created projects, and `offline = true`
passes Cargo's offline policy through. `target`, `profile`, and `features`
are part of the dependency cache key.

When `bindings.cbindgen` is enabled, the provider runs cbindgen in the crate
directory before passing its header through `import-c`. `command` can override
the `cbindgen` executable, for example when a project pins a wrapper around a
particular cbindgen release.

The header describes the ABI, not ownership. A Rust `Box<T>` becomes a raw
pointer in cbindgen output, so name its policy explicitly when the caller owns
it. `returns` maps a constructor to its cleanup function and `takes` marks the
parameter positions that cleanup consumes:

```lua
bindings = {
   cbindgen = true,
   ownership = {
      returns = { codec_create = "codec_destroy" },
      takes = { codec_destroy = { 1 } },
   },
}
```

The generated binding represents `codec_create` as
`affine(Codec*, codec_destroy)`. This changes checking and lexical cleanup, not
the C ABI. An ownership mapping also asserts the returned pointer is non-null:
that is correct for `Box<T>`, but not for a nullable factory. See
[ownership.md](../type-system/ownership.md#c-interop) for what the checker then
enforces at the boundary.

The copy in `outDir/lib` is named the way a C dependency's library is, so a
generated binding says `@lib/libtiny_rust.dylib` and a copied or moved output
tree still finds it. A single-artifact target carries it beside the artifact for
the same reason.

## Rock dependencies

`kind = "luarocks"` installs a Lua library with LuaRocks. Nothing is built and
nothing is generated: what the provider produces is a populated tree and the
two search-path entries that reach it.

```lua
dependencies = {
   -- From the LuaRocks server, at the version named here.
   lunamark = { kind = "luarocks", version = "0.6.0-1" },
   -- From a rockspec in the project, for a library upstream does not publish.
   scintillua = {
      kind = "luarocks",
      rockspec = "rocks/scintillua-6.7-1.rockspec",
   },
   -- From sources that ship with the project: `luarocks make`, no fetch.
   tinyrock = {
      kind = "luarocks",
      rock = "tinyrock",
      path = "vendor/tinyrock",
      rockspec = "vendor/tinyrock/tinyrock-1.0-1.rockspec",
   },
}
```

A rock must be pinned by one of those three, a `version`, a `rockspec`, or a
`path`, and a manifest that pins none of them is refused before any build work
starts. Naming both a `version` and a `rockspec` that declares a different one
is refused too. A rock does not list `dependencies` of its own: LuaRocks
resolves what a rock needs, which is the reason to use it.

| Field | Meaning |
| --- | --- |
| `rock` | The rock's name, when it differs from the dependency's |
| `version` | The exact version to install |
| `rockspec` | A rockspec in the project to install from |
| `path` | A directory to build in place with `luarocks make` |
| `bundle` | Globs naming what a bundle or binary carries |
| `tree` | Where to install, `.rocks` by default |
| `luaVersion` | The tree's Lua version, `5.1` by default |
| `luaDir` | Where the Lua headers and libraries live |
| `server` | An additional rocks server to fetch from |
| `luarocks` | The LuaRocks executable, `luarocks` by default |

Rocks install into `.rocks` in the project root, a tree the project owns rather
than the one the user's account owns, so two checkouts can hold different
versions of a library without either able to break the other's build by
upgrading something. LuaJIT is Lua 5.1, and a C rock compiled against another
5.1 loads into a VM that cannot call it, which is what `luaVersion` pins. The
headers a C rock compiles against are found from the running interpreter's own
module path; `luaDir`, or the `NUPP_LUA_DIR` environment variable, names them
instead.

A pinned rock already installed at the version asked for is left alone, so a
warm build reaches for nothing. A rock built from `path` is remade whenever its
sources change, which is what the fingerprint is for.

The tree is added to the search path of the build that installed it, so a
target's own dependencies are loadable the moment they are installed, and
`nupp doc` installs its renderer and renders with it in one command. `nupp test`
puts the tested target's trees on `LUA_PATH` and `LUA_CPATH` for the test
command, ahead of what is already there and without replacing it. Anything else
that runs outside the build reads the tree the way LuaRocks trees are always
read.

An installed rock may also carry typed module declarations in its versioned
`nupp/` directory. See [luarocks.md](luarocks.md) for authoring, packing,
testing, and publishing that layout.

### Carrying a rock into a bundle

A bundle and a binary are one file, and one file cannot bring a rock tree along.
`bundle` names what goes in with it, as globs over the tree the rock installs
into:

```lua
lunamark = {
   kind = "luarocks",
   version = "0.6.0-1",
   bundle = { "lunamark.lua", "lunamark/**.lua", "cosmo.lua", "cosmo/**.lua",
      "re.lua" },
}
```

Each selected file becomes a `package.preload` entry under the name `require`
would have found it by in the tree, so `lunamark/writer/html.lua` becomes
`lunamark.writer.html`, and a `foo/init.lua` becomes `foo`. The same `require`
therefore resolves in a checkout, in a bundle, and in a stamped binary, and the
program cannot tell which it is running in.

Named rather than swept, because a rock tree also holds test scripts,
command-line programs and documentation that nothing will ever ask for. A rock
with no `bundle` is installed and not carried, which is the right answer for
anything only the build itself uses.

A rock's C libraries cannot ride in a payload, because a `.so` is not a Lua
chunk, so a binary that needs one needs a stub linked against it. Nupp's own
stub links the three its commands cannot run without; see
[distribution.md](../reference/distribution.md#limits) for that boundary.

## Self-hosting

This repository configures `selfHost` in `nupp.lua`. `nupp fixpoint` builds a
stage-1 compiler, invokes stage 1 to build stage 2, and compares the declared
artifacts byte for byte. The working compiler is updated only after a match.

`nupp fixpoint --update-bootstrap` additionally refreshes the tracked
`bootstrap/nupp.lua` bundle and declaration resources. Syntax changes must
update the bootstrap before they can rely on that syntax, and CI should always
exercise a build with no pre-existing `build` directory.

The build system's own implementation lives under the internal
`nupp.compiler.build.*` namespace in `src/nupp/compiler/build/`: `project` owns
orchestration, `hash` owns cache digests, and `process` owns argv-based
subprocess execution.

## FAQ

### Why does the build compile a module nothing requires?

Because the source set is what a project is written in, and a module left out
of the build is a module nothing checked. See [Source sets](#source-sets) for
what the alternative costs.

### Why did one edit rebuild the whole project?

An edit to an exported type declaration invalidates the project index, where an
edit to a function body invalidates one module. `nupp check --json` reports
`timing.compiledModules` and `timing.slowest`, so a run says how much it redid
rather than leaving that to be inferred from how long it took.

### Can a one-file bundle carry a native library?

No. A `.so` is not a Lua chunk, so a bundle with a detected native feature is
refused rather than becoming a sidecar package, and a binary that needs a
native provider needs a stub linked against it. See
[distribution.md](../reference/distribution.md#limits) for the whole boundary.

::: seealso
- [cli.md](../reference/cli.md#build) for every flag `nupp build` takes
- [tasks.md](tasks.md) for named tasks and the environment they run in
- [distribution.md](../reference/distribution.md) for how a stamped binary is
  put together
:::
