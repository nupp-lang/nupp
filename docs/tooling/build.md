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

`nupp tasks` lists the manifest's build targets, configured test action, and
self-host/fixpoint action, and marks the default build target.
`nupp tasks <name>` prints the effective target configuration, including
manifest-level defaults such as `outDir`. Both forms accept `--format json`
(or `--json`) for build-tool integration; text is the default. Run
`nupp help tasks` for the complete interface.

`nupp clean` removes the output paths of every configured target;
`nupp clean --target <name>` limits removal to one target. `--dry-run` prints
the paths without changing them. Clean rejects absolute paths, parent
traversal, and the project root before removing anything.

The manifest is validated before builds, checks, tests, and task queries.
Validation covers dense string arrays, required target inputs, supported
dependency kinds, named target and dependency references, and dependency
cycles. Configuration errors name the invalid field before any build work
starts.

The implementation lives under the `nupp.build.*` submodule namespace in
`src/nupp/build/`: `project` owns orchestration, `hash` owns cache digests, and
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
include root.

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
Source files below `internal/`, source files beginning with `_`, and methods
or members beginning with `_` are private by default; set
`includePrivate = true` to include them.
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

The optimization level is one of those keys. `nupp build -O2` reaches the
configuration before it is hashed, so changing the level invalidates every
artifact built at the old one rather than leaving a project half compiled at
each. Switching levels therefore costs a cold build, and cannot produce a
mixture. `-O0` is the default and performs no rewrite; see the
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

## Self-hosting

This repository configures `selfHost` in `nupp.lua`. `nupp fixpoint` builds a
stage-1 compiler, invokes stage 1 to build stage 2, and compares the declared
artifacts byte for byte. The working compiler is updated only after a match.

`nupp fixpoint --update-bootstrap` additionally refreshes the tracked
`bootstrap/nupp.lua` bundle and declaration resources. Syntax changes must
update the bootstrap before they can rely on that syntax, and CI should always
exercise a build with no pre-existing `build` directory.
