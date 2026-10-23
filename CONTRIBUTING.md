# Contributing to Nupp

Build Nupp from a source checkout when you want to change the compiler,
runtime, tooling, or documentation. To install a released binary for ordinary
project work, use the
[installation guide](https://nupp.dev/getting-started/installation/).

## Clone and build

Nupp is written in Nupp, so the first build starts from a release's compiler
image, fetched against a digest pinned in the tree. Building the real one takes
C, C++, and the exact Rust toolchain in `rust-toolchain.toml`: the VM runtime it
runs on is built from the checkout's own Rust sources, and that first compiler
and the pinned sources the build needs are fetched by the checkout itself.

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
Windows uses the `x86_64-pc-windows-gnu` Rust toolchain, linked by the MinGW
compiler pair the rest of the build uses. Install it with
`rustup toolchain install 1.98.0-x86_64-pc-windows-gnu --profile minimal`; the
build refuses a Rust host of another ABI rather than mixing objects.
`NUPP_RUST_WINDOWS_ABI=gnullvm` selects LLVM-MinGW instead.

Everything else is provisioned. Cargo resolves the Rust crates, including
networking and TLS, through the committed lockfile, and `scripts/toolchain`
builds the VM runtime from them; `bin/nupp` runs it for what is missing and
nothing more. See [Native runtime and support](https://nupp.dev/reference/native-runtime/)
for the facility mapping, retained non-Rust boundaries, and release matrix.

### LuaJIT

Nothing Nupp builds runs on LuaJIT. The pinned LuaJIT is the interpreter
LuaRocks runs on, for projects with [rock
dependencies](https://nupp.dev/learn/projects/build/#rock-dependencies).
`scripts/toolchain` fetches LuaJIT and LuaRocks by pinned revision, refuses any
archive whose SHA-256 is not the one written down, builds each with the compiler
pair, and caches the result beside the repository so every worktree shares one
build. Outside Windows, `bin/nupp` provisions it the first time a build installs
a rock; on Windows, LuaRocks is found on `PATH`.

### JSON

The performance JSON decoder is Nupp source whose `@aot` SIMD path the VM
lowers natively. It requires no simdjson package or JSON-specific native
dependency. The simdjson binding under `bench/serde-spike/simdjson-native` is
only a performance control.

### Offline and mirrored builds

Three settings, shared by everything `scripts/toolchain` fetches:

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
| LuaRocks | projects that declare rock dependencies | `bin/nupp`, through `scripts/toolchain luarocks`, on first use |

`nupp doc` needs nothing installed: its Markdown renderer (`pulldown-cmark`) is
part of the VM runtime, and fenced code is highlighted by Nupp's own lexer and a
few small language tables. See [self-contained binary](#self-contained-binary)
for what a stamped binary carries and how to build one.

## Building from a checkout

`bin/nupp` is the entry point and it builds on demand: it runs the VM compiler
installed under `.nupp/vm-cli`, and rebuilds it first when a compiler source is
newer than the installed generation. A rebuild reuses what earlier builds
lowered for every module nothing it read has changed. An edit to the compiler
is picked up by the next command rather than by the next person who remembers
to build.

```bash
./bin/nupp check    # rebuilds the compiler first if a source is newer
```

A failed rebuild leaves the previous generation selected and says so, with the
log in `.nupp/vm-cli/rebuild.log`; later commands do not try again until
another source changes. `scripts/vm-cli build` rebuilds explicitly.

### Shared toolchain cache

Downloaded sources and the toolchain components land beside the repository's
common Git directory, so every worktree shares them. Rust outputs default to
the worktree's `build/rust` and the worktree helper seeds that
content-validated cache from the originating checkout. `NUPP_TOOLCHAIN_DIR` moves the shared store; `NUPP_RUST_BUILD_DIR`
moves Rust outputs:

```bash
export NUPP_TOOLCHAIN_DIR=/var/cache/nupp/toolchain
```

The cache is keyed by the compiler pair's own version output, so switching
`NUPP_CC` from Clang to GCC builds beside the previous answer rather than over
it. `scripts/worktree BRANCH PATH [START_POINT]` seeds a new worktree with
content-validated compiler caches and the test runner's last suite timings;
generated outputs remain local to each worktree.

The runtime a binary target is stamped onto is the compiler's rather than the
project's, which is why it is cached with the rest rather than under each
project's output directory. Without that, every project building a binary would
compile the runtime from nothing.

### Build locking

Only one compiler rebuild runs in a checkout at a time, under a lock directory
holding the builder's pid. A command that finds it held waits, and then runs
what that build installed.

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

That writes `build/dist/nupp`, a single file: the compiler's image, with its
standard library and resources, stamped onto a VM runtime built for this machine
that links the native facilities the compiler reaches. See
[distribution](https://nupp.dev/reference/distribution/) for the runtime and
payload format. Building a `binary` target with it still needs a source
checkout, since the runtime it stamps is built from Nupp's Rust sources.

## Running checks

```bash
./bin/nupp check
./bin/nupp test
```

`check` type-checks the project configured in `nupp.lua`. `test` builds the
test runner, `build/nupp-test`, as a VM program and runs the suite on it.

Run the suites that cover what changed rather than all of them. Named groups
say what a set of suites is for, and are what the workflows ask for:

```bash
./bin/nupp test --list-groups
./bin/nupp test --group=docs
./bin/nupp test --lane=shared          # the ~100 suites that use Nupp workers
./bin/nupp test --lane=shell           # suites that use reusable process workers
./bin/nupp test --exclude-group=docs   # everything an earlier run did not cover
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

`nupp init --list` also shows the library template. See [Getting started](https://nupp.dev/getting-started/) for the
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
