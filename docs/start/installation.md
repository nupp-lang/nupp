# Installation

Nupp is written in Nupp. A checkout carries a stage-0 compiler already lowered
to Lua, so building the real one takes a LuaJIT, an LPeg, and nothing else.

## Requirements

**LuaJIT 2.1.1784535649 or newer.** Generated Nupp is written in the LuaJIT 3.0
syntax that 2.1 backported, meaning `?.`, `??`, `?:`, the bit operators and
compound assignment, rather than in a lowering of it. That rolling version is
the first build carrying those extensions. `bin/nupp` reads `luajit -v` and says
which build is wanted, so an older interpreter fails with a sentence instead of
a syntax error on a line nobody wrote.

**LPeg 1.1.** The compiler reads its own doc comments and manifests with
`nupp.peg`, which resolves native LPeg, so the module is loaded before the first
build rather than by a later command:

```bash
luarocks install lpeg
```

Everything else is optional and buys one feature each:

| Component | Needed for | Installed by |
| --- | --- | --- |
| lua-cjson | --json output and the LSP server | luarocks install |
| `lunamark` | nupp doc | nupp doc |
| `Scintillua` | highlighting in generated sites | nupp doc |
| Rust toolchai | building the binary host stub | rustup |

That table is about a **checkout**. A stamped binary carries all three of the
first ones already, as [the binary](#self-contained-binary) describes, and
needs nothing installed to check, compile, run or document a project.

## From a checkout

```bash
git clone https://github.com/nupp-lang/nupp
cd nupp
./bin/nupp build
```

`bin/nupp` is the entry point and it builds on demand: it runs
`build/nupp/compiler` when that exists and no source is newer, and compiles the
compiler first when it does not. An edit to the compiler is picked up by the
next command rather than by the next person who remembers to build.

Git worktrees share the native Rust target in a repository cache derived from
Git's common directory, so each worktree does not rebuild the same
dependencies. Set
`NUPP_NATIVE_TARGET_DIR` to override that location; a relative value is resolved
from the checkout root. `scripts/worktree BRANCH PATH [START_POINT]` also seeds
the new worktree with content-validated compiler caches and the test runner's
last suite timings. Generated outputs remain local to each worktree.

The crates a build stages for a project are the compiler's rather than the
project's, both the native providers behind `nupp.io.files` and its siblings and
the executable a binary target is stamped into, so cargo keeps their target
directories in that same repository cache rather than under each project's
output directory. One directory per crate and feature set, because cargo names
what it uplifts after the crate: two feature sets sharing a directory overwrite
each other's library. `NUPP_NATIVE_CACHE_DIR` names the root. Without this,
every project that reached a native facility compiled that facility's
dependencies from nothing, which for the http provider means `reqwest`, `rustls`
and `tokio`.

Only one build runs in a tree at a time. A build removes the completion stamp
before it writes anything, so a second command starting in that window used to
see a tree that looked unbuilt and start its own build over the same files; now
it waits for the one already running and uses what that produces.

The one thing it cannot do is start from nothing, since compiling Nupp needs a
Nupp compiler. `bootstrap/nupp.lua` is that compiler, tracked in the
repository, and it is what a fresh clone uses for its first build.

## Optional libraries

Nothing to run: lunamark and Scintillua are declared in `nupp.lua` as
dependencies of the documentation target, so the command that needs them
installs them.

```bash
./bin/nupp doc
```

That installs both and their declared rocks into a project-local `.rocks` tree
that `bin/nupp` and `tests/run` put on the search path. A Nupp binary's feature
scan sees the LPeg and lua-utf8 calls in those bundled libraries and links both
native modules into its host. Their Lua files, including LPeg's official
`re.lua`, remain in the payload. Two checkouts can hold different rock versions
without either disturbing the other, and nothing lands in a global tree. See
[rock dependencies](../tooling/build.md#rock-dependencies) for declaring your
own.

`nupp doc` needs lunamark and stops with a message when it cannot install or
load it. Scintillua degrades instead: a fence in a language it cannot load
renders as escaped text without highlighting.

`lua-cjson` comes from wherever your LuaJIT already looks:

```bash
luarocks install lua-cjson
```

Every command's `--json` output and the language server read it.

## Putting `nupp` on PATH

Inside a checkout, run `./bin/nupp`. Everywhere else, either put the checkout's
`bin` on your path, or build a self-contained binary.

## Self-contained binary

```bash
./bin/nupp build --target dist
```

That writes `build/dist/nupp`, a single file carrying the compiler, its
standard library, and what it documents with, needing no LuaJIT installed
alongside:

| Carried | How | For |
| --- | --- | --- |
| `LuaJIT` | linked into the stub | running anything |
| lua-cjson | detected and linked | --json and the LSP |
| LPeg 1.1 | detected and linked | general PEG and direct LPeg patterns |
| LPeg `re.lua` | in the payload | runtime textual grammars |
| Nupp PEG matcher shell | emitted in the payload | typed matching, search, and replacement |
| `luautf8` | detected and linked | nupp doc's entities |
| `lunamark` | in the payload | nupp doc's markdown |
| Scintillua (45) | in the payload | highlighting fences |

The lexers are a chosen set rather than all hundred and sixty Scintillua ships.
They are the languages a technical document actually fences, listed at the top
of `nupp.lua`. A fence in something else renders as escaped text, which is what
it does with no Scintillua at all. See [distribution](../distribution.md) for
the stub-and-payload format, and [rock
dependencies](../tooling/build.md#carrying-a-rock-into-a-bundle) for carrying
your own.

## Checking that it works

```bash
./bin/nupp check
./bin/nupp test
```

`check` type-checks the project configured in `nupp.lua`. `test` builds and
runs the suite, which is plain LuaJIT with no framework behind it.

## Your first project

Two files:

```text
hello/
├── nupp.lua
└── src/
    └── app/
        └── main.nupp
```

`src/app/main.nupp`:

```nupp:playground
local function greetingFor(name: string): string
    return "Hello, " .. name .. "!"
end

print(greetingFor("Nupp"))
```

`nupp.lua`, the project manifest:

```lua
return {
   include = { "src" },

   build = {
      outDir = "build",
      default = "app",
      targets = {
         app = {
            kind = "modules",
            entries = { "app.main" },
         },
      },
   },
}
```

`include` names the roots where modules live, so `app.main` resolves to
`src/app/main.nupp`, and generated Lua keeps that path under `build/`.

Then, from the project root:

```bash
nupp check                  # type-check the project, writing nothing
nupp build                  # compile the default target
nupp run src/app/main.nupp  # compile and run one file
```

Check the whole project rather than the file you just edited. That is what lets
Nupp verify module boundaries, ownership contracts, and lint settings together.

[Build system](../tooling/build.md) documents every manifest key.

## Next

- [A tour of Nupp](tour.md): the whole language in one pass.
- [Reasons to use Nupp](why.md): what each feature is for.
