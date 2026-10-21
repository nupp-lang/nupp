# Contributing to Nupp

Build Nupp from a source checkout when you want to change the compiler,
runtime, tooling, or documentation. To install a released binary for ordinary
project work, use the
[installation guide](https://nupp.dev/getting-started/installation/).

## Clone and build

Nupp is written in Nupp, so the first build starts from the previous release's
compiler, lowered to one Lua file and fetched against a digest pinned in the
tree. Building the real one takes C, C++, and the exact Rust toolchain in
`rust-toolchain.toml`. The interpreter it runs on, the libraries it links and
that first compiler are fetched from pinned sources and built by the checkout
itself when the machine does not already have them.

```bash
git clone https://github.com/nupp-lang/nupp
cd nupp
./bin/nupp build
```

## Requirements

**A C and a C++ compiler**, either `clang` with `clang++` or `gcc` with `g++`,
plus the shell, `tar` and a downloader. `NUPP_CC` and `NUPP_CXX` name them; with
neither set, Unix probes `clang`, `cc` and `gcc` in that order. Windows probes
the MinGW `gcc` pair first because the provisioned dependencies use GNU make;
the corresponding C++ names are probed beside each C compiler.

**Rust 1.98.0 with Cargo**, selected exactly rather than by a minimum version.
Rustup reads the committed toolchain file automatically. `NUPP_RUSTC` and
`NUPP_CARGO` may name an equivalent toolchain explicitly; the build refuses a
different release so its content-addressed native artifacts remain reproducible.
Windows uses the `x86_64-pc-windows-gnu` Rust toolchain because LuaJIT and the
host's remaining protected C shims use the MinGW ABI. Install it with
`rustup toolchain install 1.98.0-x86_64-pc-windows-gnu --profile minimal`; the
build refuses the ABI-incompatible MSVC Rust host rather than mixing objects.

Everything else is provisioned. `scripts/toolchain` fetches LuaJIT and LuaRocks
by pinned revision, refuses any archive whose SHA-256 is not the
one written down, builds each with that compiler pair, and caches the result
beside the repository so every worktree shares one build. Cargo resolves the
Rust-native crates, including networking and TLS, through the committed
lockfile. The toolchain driver builds Nupp's Rust native providers, executable
host, and embedding libraries; `bin/nupp` runs it for what is missing and
nothing more. See [Native runtime and support](https://nupp.dev/reference/native-runtime/)
for the feature mapping, retained non-Rust boundaries, and release matrix.

### LuaJIT

**LuaJIT 2.1.1784535649 or newer.** Generated Nupp is written in the LuaJIT 3.0
syntax that 2.1 backported, meaning `?.`, `??`, `?:`, the bit operators and
compound assignment, rather than in a lowering of it. That rolling version is
the first build carrying those extensions.

`bin/nupp` reads `luajit -v` and uses what is on `PATH` when it is new enough.
When it is not, the pinned LuaJIT is built and its `bin` goes on `PATH` ahead of
the older one, so the comptime workers, the LSP relay and the test runner all
reach the same interpreter.

### JSON

The performance JSON decoder is Nupp source whose `@aot` SIMD path the VM
lowers natively. Portable compiler and browser targets select the vendored
pure-Lua codec instead. Neither route requires a C++ compiler, simdjson
package, or JSON-specific native dependency. The simdjson binding under
`bench/serde-spike/simdjson-native` is only a performance control.

### Offline and mirrored builds

Three settings, shared with the host build's own fetching:

| Setting | Effect |
| --- | --- |
| `NUPP_HOST_SOURCE_DIR` | a directory of already-downloaded pinned archives |
| `NUPP_HOST_SOURCE_BASE_URL` | a flat mirror to fetch archives from |
| `NUPP_HOST_OFFLINE` | refuse to reach the network |

A digest is checked whichever of these supplied the bytes, so a mirror that
served something else is refused rather than compiled. A pin may also name
mirrors of its own (`NAME_MIRRORS`), tried in order when the origin cannot be
reached, and held to the same digest. `NUPP_TOOLCHAIN_DIR` moves where the
built components land.

### Optional components

| Component | Needed for | Installed by |
| --- | --- | --- |
| LuaRocks | projects that declare rock dependencies | `scripts/toolchain luarocks` or your package manager |

`nupp doc` needs nothing installed: its Markdown renderer (`pulldown-cmark`) is
part of the VM runtime, and fenced code is highlighted by Nupp's own lexer and a
few small language tables. See [self-contained binary](#self-contained-binary)
for what a stamped binary carries and how to build one.

## Building from a checkout

`bin/nupp` is the entry point and it builds on demand: it runs
`build/nupp/tools/main.lua` when that exists and no source is newer, and compiles the
compiler first when it does not. An edit to the compiler is picked up by the
next command rather than by the next person who remembers to build.

```bash
./bin/nupp check    # builds the compiler first if a source is newer
```

### Shared toolchain cache

Downloaded sources and the classic toolchain components land beside the
repository's common Git directory, so every worktree shares LuaJIT.
Rust host and provider outputs default to the worktree's `build/rust` and
the worktree helper seeds that content-validated cache from the originating
checkout. `NUPP_TOOLCHAIN_DIR` moves the shared store; `NUPP_RUST_BUILD_DIR`
moves Rust outputs:

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

### Stage-zero compiler

The one thing a checkout cannot do is start from nothing, since compiling Nupp
needs a Nupp compiler. The one it starts from is the root CLI image of the
release named by `STAGE0_IMAGE_TAG` in `scripts/toolchain.pins`, published as an
asset of that release and fetched by `scripts/toolchain stage0-image` the first
time a checkout needs it. `bin/nupp` runs it on a runtime built from the
checkout's own sources to lower those sources into a VM compiler. The digest
beside the tag is what authenticates it, and it is reproducible from the tag:
`nupp fixpoint --emit-stage0` from that source gives the same bytes.

One copy serves every worktree on the machine. An offline builder supplies
`nupp-stage0-<tag>.image.gz` through `NUPP_HOST_SOURCE_DIR`, the way it supplies
every other pinned archive.

Because the compiler's own sources are lowered by that image, they may only use
language features it already understands, and the runtime must keep loading its
format. A feature reaches the sources a release later, once an image carrying it
is published and the pin moves to it.

## Putting `nupp` on PATH

Inside a checkout, run `./bin/nupp`. Everywhere else, either put the checkout's
`bin` on your path, or build a self-contained binary.

## Self-contained binary

```bash
./bin/nupp build --target dist
```

That writes `build/dist/nupp`, a single file carrying the compiler and its
standard library, needing no LuaJIT installed alongside:

| Carried | How | For |
| --- | --- | --- |
| `LuaJIT` | linked into the stub | running anything |
| Rust native provider | linked into the stub | filesystem, networking, TLS, clocks, payload checks, and child processes |
| Vendored JSON codec | in the payload | JSON, `--json`, and the LSP |

This LuaJIT-hosted binary has no Markdown renderer or regular-expression
engine: `nupp doc` and `nupp.text.regex` need the VM runtime, which carries
both. See [distribution](https://nupp.dev/reference/distribution/) for the
stub-and-payload format, and
[carrying a rock into a bundle](https://nupp.dev/learn/projects/build/#carrying-a-rock-into-a-bundle)
for carrying your own.

## Running checks

```bash
./bin/nupp check
./bin/nupp test
```

`check` type-checks the project configured in `nupp.lua`. `test` builds and
runs the suite, which is plain LuaJIT with no framework behind it.

Run the suites that cover what changed rather than all of them. Named groups
say what a set of suites is for, and are what the workflows ask for:

```bash
./bin/nupp test --list-groups
./bin/nupp test --group=docs
./bin/nupp test --lane=shared          # the ~100 suites that use Nupp workers
./bin/nupp test --lane=shell           # suites that use reusable process workers
./bin/nupp test --exclude-group=aot    # everything an earlier run did not cover
./bin/nupp test --list-suites          # what a selection would run, running none
```

`tests/groups.lua` defines the groups. A group member that names no suite is an
error rather than an empty run.

## What CI asks of a change

`required-ci` is the one status the trunk requires. It waits on every job in
`.github/workflows/compiler.yml` and passes only when each job the change
selected succeeded; a job that was not selected is skipped, and a job that was
selected and did not answer -- failed, or cancelled -- fails it. Its meaning
does not change when the jobs beneath it are renamed or reorganized.

The trunk ruleset requires that status and **nothing else**: no pull request, no
review, no merge queue. The worktree flow is unchanged except that the branch
goes up before the trunk does, so the commit has somewhere to be tested:

```bash
git push origin my-task-branch          # CI runs on this exact commit
# ... wait for required-ci ...
git push origin my-task-branch:main     # same SHA, already green
```

The second push is admitted because that commit already has a passing
`required-ci`. A commit nothing has tested is refused. That is the only
behaviour change, and it is the whole guarantee: what reaches `main` is a
revision that passed, not a revision near one that passed.

`--no-verify` skips the local formatting hook; nothing skips this. If the gate
ever wedges -- a workflow that cannot report `required-ci` at all -- set the
ruleset's `enforcement` to `disabled`, fix it, and set it back. Rulesets stay
editable by a repository admin whatever their bypass list says.

What a change selects is decided by `.github/scripts/classify-changes.lua` from
the paths it touches. It is deliberately conservative: a path no rule
classifies selects every job, and so does any change to `nupp.lua`,
`scripts/`, `.github/`, `Cargo.lock` or the Rust toolchain file.
`tests/cichangeclassifiertest.lua` asserts what representative files select, and
`.github/ci-coverage.json` records what each job and step covers -- the two are
held to the workflow itself on every run, before anything is provisioned.

Measurements live in `.github/workflows/measurements.yml`, not in the gate. A
benchmark harness that does not compile is a bug and fails there; a slower
number is not an answer about an unrelated change.

The nightly schedule runs the whole matrix whatever changed, as a backstop
against a gap in the classification. A failure there is a bug like any other.

## Your first project

The maintained application template creates the manifest, source tree, test,
and project tasks:

```bash
nupp init app hello
cd hello
nupp check
nupp test
nupp task start
```

`nupp init --list` also shows the library, browser, browser SIMD, and LÖVE
templates. See [Getting started](https://nupp.dev/getting-started/) for the
project loop and what each template contains.

## See also

- [build.md](https://nupp.dev/learn/projects/build/) for every manifest key,
  target kind, and cache
- [tour.md](https://nupp.dev/getting-started/tour/) for the language itself,
  one construct at a time
- [tooling.md](https://nupp.dev/learn/tooling/) for what the rest of the
  binary does
- [testing.md](https://nupp.dev/learn/projects/testing/) for configuring a
  suite of your own
