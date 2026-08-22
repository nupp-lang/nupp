---
order: 10
---

# Installation

Nupp is written in Nupp. A checkout carries a stage-0 compiler already lowered
to Lua, and building the real one takes a C and a C++ compiler. The interpreter
it runs on and the libraries it links are fetched from pinned sources and built
by the checkout itself when the machine does not already have them.

```bash
git clone https://github.com/nupp-lang/nupp
cd nupp
./bin/nupp build
```

## Requirements

**A C and a C++ compiler**, either `clang` with `clang++` or `gcc` with `g++`,
plus the shell, `tar` and a downloader. The C++ half must understand C++20,
which Clang 10 and GCC 10 were the first to do. `NUPP_CC` and `NUPP_CXX` name them; with
neither set, Unix probes `clang`, `cc` and `gcc` in that order. Windows probes
the MinGW `gcc` pair first because the provisioned dependencies use GNU make;
the corresponding C++ names are probed beside each C compiler.

Everything else is provisioned. `scripts/toolchain` fetches LuaJIT, LPeg,
luautf8, simdjson, ada, libcurl and mbedTLS by pinned revision, refuses any archive
whose SHA-256 is not the one written down, builds each with that compiler pair,
and caches the result beside the repository so every worktree shares one build.
It also builds what Nupp itself is made of: the native providers and the binary
host, both C. `bin/nupp` runs it for what is missing and nothing more.

### LuaJIT

**LuaJIT 2.1.1784535649 or newer.** Generated Nupp is written in the LuaJIT 3.0
syntax that 2.1 backported, meaning `?.`, `??`, `?:`, the bit operators and
compound assignment, rather than in a lowering of it. That rolling version is
the first build carrying those extensions.

`bin/nupp` reads `luajit -v` and uses what is on `PATH` when it is new enough.
When it is not, the pinned LuaJIT is built and its `bin` goes on `PATH` ahead of
the older one, so the comptime workers, the LSP relay and the test runner all
reach the same interpreter.

### simdjson

**simdjson 4.6.4.** The JSON runtime links whatever `pkg-config` reports for
`simdjson` and `luajit`; where it reports neither, the pinned simdjson is built
and linked instead. `NUPP_JSON_SIMDJSON_ROOT` with `NUPP_JSON_LUAJIT_ROOT` names
an installation that neither pkg-config nor the driver can discover, and wins
over both.

### LPeg

**LPeg 1.1.** The compiler reads its own doc comments and manifests with
`nupp.peg`, which resolves native LPeg. A checkout gets it with the other rocks
`nupp doc` installs; `scripts/toolchain lpeg` builds the pinned one for a host
binary to link.

### Offline and mirrored builds

Three settings, shared with the host build's own fetching:

| Setting | Effect |
| --- | --- |
| `NUPP_HOST_SOURCE_DIR` | a directory of already-downloaded pinned archives |
| `NUPP_HOST_SOURCE_BASE_URL` | a flat mirror to fetch archives from |
| `NUPP_HOST_OFFLINE` | refuse to reach the network |

A digest is checked whichever of these supplied the bytes, so a mirror that
served something else is refused rather than compiled. `NUPP_TOOLCHAIN_DIR`
moves where the built components land.

### Optional components

| Component | Needed for | Installed by |
| --- | --- | --- |
| `lunamark` | `nupp doc` | `nupp doc` |
| `Scintillua` | highlighting in generated sites | `nupp doc` |
| LuaRocks | installing those two | your package manager |

That table is about a checkout. A stamped binary carries what it needs already
and needs nothing installed to check, compile, run or document a project. See
[self-contained binary](#self-contained-binary) for what it carries and how to
build one.

## Building from a checkout

`bin/nupp` is the entry point and it builds on demand: it runs
`build/nupp/compiler` when that exists and no source is newer, and compiles the
compiler first when it does not. An edit to the compiler is picked up by the
next command rather than by the next person who remembers to build.

```bash
./bin/nupp check    # builds the compiler first if a source is newer
```

### Shared toolchain cache

Everything `scripts/toolchain` builds lands beside the repository's common Git
directory, so every worktree of a checkout shares one build of LuaJIT, one
libcurl, and one of each provider and host feature set. `NUPP_TOOLCHAIN_DIR`
moves it:

```bash
export NUPP_TOOLCHAIN_DIR=/var/cache/nupp/toolchain
```

The cache is keyed by the compiler pair's own version output, so switching
`NUPP_CC` from Clang to GCC builds beside the previous answer rather than over
it. `scripts/worktree BRANCH PATH [START_POINT]` seeds a new worktree with
content-validated compiler caches and the test runner's last suite timings;
generated outputs remain local to each worktree.

The native code a build stages for a project is the compiler's rather than the
project's -- both the providers behind [](nupp.io.files) and its siblings, and
the executable a binary target is stamped into -- which is why it is cached with
the rest rather than under each project's output directory. Without that, every
project reaching a native facility would compile that facility from nothing.

### Build locking

Only one build runs in a tree at a time. A build removes the completion stamp
before it writes anything, so a second command starting inside that window sees
a tree that looks unbuilt; rather than starting its own build over the same
files, it waits for the one already running and uses what that produces.

### Bootstrap compiler

The one thing a checkout cannot do is start from nothing, since compiling Nupp
needs a Nupp compiler. `bootstrap/nupp.lua` is that compiler, tracked in the
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
[rock dependencies](../guides/build.md#rock-dependencies) for declaring your
own.

`nupp doc` needs lunamark and stops with a message when it cannot install or
load it. Scintillua degrades instead: a fence in a language it cannot load
renders as escaped text without highlighting.

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
| simdjson | detected and linked | JSON, `--json`, and the LSP |
| LPeg 1.1 | detected and linked | general PEG and direct LPeg patterns |
| LPeg `re.lua` | in the payload | runtime textual grammars |
| Nupp PEG matcher shell | emitted in the payload | typed matching, search, and replacement |
| `luautf8` | detected and linked | `nupp doc`'s entities |
| `lunamark` | in the payload | `nupp doc`'s markdown |
| Scintillua (45) | in the payload | highlighting fences |

The lexers are a chosen set rather than all hundred and sixty Scintillua ships.
They are the languages a technical document actually fences, listed at the top
of `nupp.lua`. A fence in something else renders as escaped text, which is what
it does with no Scintillua at all. See
[distribution](../reference/distribution.md) for the stub-and-payload format,
and [carrying a rock into a
bundle](../guides/build.md#carrying-a-rock-into-a-bundle) for carrying your own.

## Running checks

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

Check the whole project rather than the file you edited. That is what lets
Nupp verify module boundaries, ownership contracts, and lint settings together.

::: seealso
- [build.md](../guides/build.md) for every manifest key, target kind, and cache
- [tour.md](tour.md) for the language itself, one construct at a time
- [tooling.md](tooling.md) for what the rest of the binary does
- [testing.md](../guides/testing.md) for configuring a suite of your own
:::
