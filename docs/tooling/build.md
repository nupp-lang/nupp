# Project builds

Running `nupp build` without source arguments loads `nupp.lua` and compiles the
project's source set: every `.nupp` under the manifest's include roots, minus
the build output. Explicit source builds remain available as
`nupp build file.nupp`.

`entries` says where execution starts, and for a bundle which chunk becomes the
body. It does not say what exists. A build compiles what the project is written
in, the way a compiler compiles a source set, rather than walking `require`
edges out from an entry — because that walk answers three questions at once and
gets two of them wrong:

- a module nothing requires goes unchecked, so `nupp check` stops meaning "this
  project is well typed" and starts meaning "the part I could reach is";
- a module reached only through `require(name)`, where the name is computed, is
  absent from the build and therefore from any binary, and fails in front of a
  user with a filesystem search path that means nothing inside one file.

Removing unused code is a linker's job and should be invisible when it happens.
Measured on this compiler, the walk was removing one module out of seventy-one
and costing about sixteen kilobytes on a 1.6 MB binary.

`nupp tasks` lists the manifest's build targets, configured test action,
self-host/fixpoint action, and any named `tasks` entries, and marks the
default build target. `nupp tasks <name>` prints the effective target
configuration, including manifest-level defaults such as `outDir`. Both
forms accept `--format json` (or `--json`) for build-tool integration; text
is the default. Run `nupp help tasks` for the complete interface. A named
task also runs with `nupp task <name>` — see
[Tasks](../tooling/tasks.md) for the manifest shape.

`nupp clean` removes the output paths of every configured target;
`nupp clean --target <name>` limits removal to one target. `--dry-run` prints
the paths without changing them. Clean rejects absolute paths, parent
traversal, and the project root before removing anything.

The manifest is validated before builds, checks, tests, and task queries.
Validation covers dense string arrays, required target inputs, supported
dependency kinds, named target and dependency references, and dependency
cycles. Configuration errors name the invalid field before any build work
starts.

A `docs` target is checked more closely than the rest, because most of what it
configures is read by the documentation generator rather than by the build, and
a key nothing reads would otherwise take effect silently. Its keys and its
pages' keys are a closed set, and one that is not in it is refused by name:

```text
nupp: build.targets.site has no key "custmCss"; did you mean "customCss"?
```

A page's keys are checked the same way, and so are the keys of its
`heroActions` and `features` entries.

Elsewhere in the manifest an unrecognized key is still ignored.

The implementation lives under the internal `compiler.build.*` submodule namespace in
`src/compiler/build/`: `project` owns orchestration, `hash` owns cache digests, and
`process` owns argv-based subprocess execution.

```lua
return {
   include = { "src" },

   dependencies = {
      fast = {
         kind = "c",
         sources = { "native/fast.c" },
         includeDirs = { "native/include" },
         bindings = { header = "native/include/fast.h" },
      },

      codec = {
         kind = "cargo",
         manifest = "native/codec/Cargo.toml",
         library = "codec",
         bindings = {
            cbindgen = true,
            header = "build/generated/codec.h",
         },
      },
   },

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

   test = {
      build = "app",
      argv = { "luajit", "tests/run.lua" },
   },
}
```

Entries may be module names or `.nupp` paths. Generated Lua preserves module
paths beneath `outDir`; for example, `app.main` becomes
`build/app/main.lua`. Resource globs preserve paths relative to the nearest
include root. A resource table gives one source an explicit target-relative
destination when its runtime lookup is relative to another module:

```lua
resources = {
   {source = "src/public/schema.nupp", output = "app/data/schema.nupp"},
}
```

### Compiler-native features

Compiler-provided native APIs do not appear in `dependencies`. Their resolved
uses record effects while Nupp checks the target's complete source set, and the
build stages the matching providers automatically. For example,
[`nupp.regex.compile(...)`](../regex.md) records `native.regex` and builds the
compiler-owned Rust bridge into `build/lib/nupp_regex`; a target with no such
resolved use does not build or retain that library. The global `nupp` table
itself is always created by generated code.

The registry also recognizes native Lua modules such as `require("lpeg")`.
That produces `native.lpeg` for a feature-matched host without turning it into
a user-owned dependency. A local table named `nupp`, or a computed `require`,
does not claim a compiler feature: only the resolved global path and literal
module name do.

Detection is the default, not a requirement to configure every target. A
target may override one answer when it deliberately supplies or forbids a
provider: `true` forces inclusion, `false` forces removal, and an absent name
keeps the detected answer.

```lua
nativeFeatures = {
   cjson = true,
   lua_utf8 = false,
}
```

The registered module effects include `cjson` and `cjson.safe` (one shared
`cjson` provider), `lpeg`, and `lua-utf8`. Bundled LuaRock modules are checked
too, so Lunamark contributes LPeg and lua-utf8 even when application source
does not require either one directly. Forced removal is an expert escape hatch:
if reachable code still requires that provider, the resulting program fails at
runtime in the usual way.

A binary target may use `stub = "nupp"` to ask the source compiler to build its
own host with exactly the resolved host features. A path-valued `stub` remains
a prebuilt or third-party artifact and is never silently relinked.

Native artifacts are sidecars for modules targets and ordinary prebuilt stubs.
Ship the target's `lib` directory with a binary unless its selected stub links
the provider itself; a Lua payload cannot embed a shared library. A one-file
`bundle` target with a detected native feature is refused rather than silently
becoming a sidecar package.

### Documentation targets

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
      {
         path = "",
         title = "Project",
         source = "docs/index.md",
         layout = "home",
         heroTitle = "Project",
         heroText = "Project documentation.",
      },
      { path = "guide", title = "Guide", source = "docs/guide.md" },
   },
}
```

The generator takes the parser's lossless CST directly and does not invoke
the checker or Lua generator. Unchanged output files are left untouched.
Files in `public` are copied to the output root, which is useful for hero
images, stylesheets, and downloads referenced by handwritten pages.
`customCss` appends a project stylesheet after Nuppdoc's default theme, so a
site can override the documented `--nuppdoc-*` custom properties without
changing other documentation targets.
`logo` adds an image to the header brand; omit it to keep Nuppdoc's default
mark. A configured `heroImage` sits in the homepage's right column over the
theme's responsive accent glow.
Source files below `internal/`, source files beginning with `_`, files marked
`@!internal` (including descendants of a marked `init.nupp`), and methods or
members beginning with `_` are private by default; set
`includePrivate = true` to include them.
A module's page lists the modules nested under it and groups what it declares
into constructors, types, functions, and values. `constructorPattern` is the
Lua pattern a function's last name segment has to match to count as a
constructor, defaulting to `^new`; `""` leaves every function in Functions.
A Markdown link whose target names a module, a declaration, or a member —
`[](nupp.std.zone)` — is resolved to whatever documents it, in handwritten
pages and doc comments alike.
Handwritten pages and generated module pages share the navigation, breadcrumb,
outline, and collapsible side columns. Each page emits and links `llms.txt`;
the output root adds `llms-full.txt` and an LLM-oriented page index.
The header search opens with Ctrl-K or Command-K and searches handwritten page
titles and headings together with modules, declarations, and members.
Handwritten pages also accept JavaScript-free code tabs:
start with a `::: code-group` line, add fenced blocks whose language is followed
by a label such as `[Nupp]` or `[Generated Lua]`, then close the group with
`:::`. Use `nupp` for Nupp source so contextual keywords and reference links
receive the native Nupp highlighting; reserve `lua` for manifests and generated
or handwritten Lua. The getting-started guide contains a complete example.
Add `:line-numbers` after the language to number a block's lines, and
`:line-numbers=41` when the excerpt starts partway into a file. A label and
`:line-numbers` may appear in either order, inside a code group or on a lone
fence. The numbers sit in their own gutter, so selecting the block copies the
code without them.

## Cache and failure behavior

Build state is JSON in `outDir/.nupp-state.json`. Cache keys cover source
content, configuration, compiler artifacts, native tool versions, flags,
target settings, and dependency inputs. Generated files are rewritten only
when their content changes. A missing or malformed state file causes a cold
build.

The optimization level and the set of `--relax` guarantees are among those
keys. `nupp build -O2` reaches the configuration before it is hashed, so
changing either invalidates every artifact built with the old optimizer
contract rather than leaving a project half compiled under each. Switching
therefore costs a cold build, and cannot produce a mixture. `-O0` is the
default and performs no rewrite; see the
[optimization guide](optimization.md).

Warm builds reuse checked module records and generated Lua across processes.
A source edit checks and generates that module; dependents are only invalidated
when its exported interface fingerprint changes. Changes to project-wide type
declarations invalidate the project index, while body-only edits preserve it.
Deleting the state file, changing compiler/configuration inputs, or modifying
an emitted artifact safely falls back to the required cold work.

The checker and generator finish before module outputs are changed. Each file
is written through a sibling temporary file, state is saved after the
artifacts, and `.nupp-complete` is written last. `bin/nupp` only selects a
compiler build carrying that marker; otherwise it falls back to the tracked
bootstrap compiler.

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

Fetched Git trees live under `.nupp/deps` and require an explicit revision.
C builds emit a `.so`, `.dylib`, or `.dll` under `outDir/lib`. A configured
header is passed through `import-c`, and the resulting NUPP module is placed
under `outDir/generated` so it participates in normal module resolution.

## Rust dependencies

`kind = "cargo"` delegates package resolution and locking to Cargo. The
provider builds a `cdylib` into an isolated target directory and copies the
platform library into `outDir/lib`. `Cargo.lock` is enforced by default;
`locked = false` is available for newly created projects, and `offline = true`
passes Cargo's offline policy through. `target`, `profile`, and `features`
are part of the dependency cache key.

When `bindings.cbindgen` is enabled, the provider runs cbindgen in the crate
directory before passing its header through `import-c`.

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

A rock must be pinned by one of those three — a `version`, a `rockspec`, or a
`path` — and a manifest that pins none of them is refused before any build work
starts. Naming both a `version` and a `rockspec` that declares a different one
is refused too. A rock does not list `dependencies` of its own: LuaRocks
resolves what a rock needs, which is the reason to use it.

Rocks install into `.rocks` in the project root, a tree the project owns rather
than the one the user's account owns, so two checkouts can hold different
versions of a library without either able to break the other's build by
upgrading something. `tree` moves it, and `luaVersion` selects the tree's Lua
version, which defaults to `5.1` — LuaJIT is Lua 5.1, and a C rock compiled
against another 5.1 loads into a VM that cannot call it. The headers a C rock
compiles against are found from the running interpreter's own module path;
`luaDir`, or the `NUPP_LUA_DIR` environment variable, names them instead.
`server` adds a rocks server to fetch from, and `luarocks` names the executable.

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

A pinned rock already installed at the version asked for is left alone, so a
warm build reaches for nothing. A rock built from `path` is remade whenever its
sources change, which is what the fingerprint is for.

The tree is added to the search path of the build that installed it, so a
target's own dependencies are loadable the moment they are installed —
`nupp doc` installs its renderer and renders with it in one command. `nupp test`
puts the tested target's trees on `LUA_PATH` and `LUA_CPATH` for the test
command, ahead of what is already there and without replacing it. Anything else
that runs outside the build reads the tree the way LuaRocks trees are always
read.

Documentation targets take dependencies as well, and the renderer's are the
usual case:

```lua
docs = {
   kind = "docs",
   dependencies = { "lunamark", "scintillua" },
   sources = { "src" },
}
```

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
would have found it by in the tree — `lunamark/writer/html.lua` becomes
`lunamark.writer.html`, and a `foo/init.lua` becomes `foo`. So the same
`require` resolves in a checkout, in a bundle, and in a stamped binary, and the
program cannot tell which it is running in.

Named rather than swept, because a rock tree also holds test scripts,
command-line programs and documentation that nothing will ever ask for. A rock
with no `bundle` is installed and not carried, which is the right answer for
anything only the build itself uses.

A rock's **C** libraries cannot ride in a payload — a `.so` is not a Lua chunk —
so a binary that needs one needs a stub linked against it. Nupp's own stub links
the three its commands cannot run without; see
[distribution](../distribution.md#what-this-does-not-do).

## Self-hosting

This repository configures `selfHost` in `nupp.lua`. `nupp fixpoint` builds a
stage-1 compiler, invokes stage 1 to build stage 2, and compares the declared
artifacts byte for byte. The working compiler is updated only after a match.

`nupp fixpoint --update-bootstrap` additionally refreshes the tracked
`bootstrap/nupp.lua` bundle and declaration resources. Syntax changes must
update the bootstrap before they can rely on that syntax, and CI should always
exercise a build with no pre-existing `build` directory.
