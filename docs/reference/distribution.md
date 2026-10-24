---
order: 700
title: Distribution
---

# Runtimes and payloads

A distributed program is the VM runtime with a payload appended to it. The
runtime is the executable that knows how to find a payload, and the payload is
the program's image: everything the program needs, lowered from its sources.

```text
[ VM runtime ][ program payload ][ trailer ]
```

Making a binary is building the runtime, appending a payload, and writing a
trailer that says where the payload starts. [`nupp build`](../learn/projects/build.md)
does all three for a `binary` target, for the machine it runs on.

## Container

The payload is appended to the runtime file, followed by a fixed trailer. An
unsigned file ends at the trailer. A signed Mach-O carries Apple's
code-signature blob after it, with any zero alignment padding in between, and
the runtime finds that boundary through `LC_CODE_SIGNATURE`.

| Region | Contents | Present |
| --- | --- | --- |
| runtime | an ordinary ELF, Mach-O, or PE image | always |
| payload | the entry module's name and the program image | once stamped |
| trailer | 48 fixed bytes | once stamped |
| Mach-O signature | Apple's code-signature blob | signed macOS only |

The payload and trailer stay covered by the signature because the packager
extends `__LINKEDIT` over them before the native signer runs. See [Signing for
macOS](#signing-for-macos) for the order that makes that work.

::: deepdive
An appended payload rather than a platform section: an ELF section, a Mach-O
section and a PE resource are three formats and three writers, and the payload
contract needs nothing any of them supplies.
:::

### Trailer

48 bytes, little-endian, at the end of an unsigned file. For a signed Mach-O it
is immediately before the zero alignment padding and code-signature offset named
by `LC_CODE_SIGNATURE`. The runtime checks only those format-defined boundaries;
it does not search arbitrary executable bytes for the magic.

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 8 | magic, the ASCII bytes `NUPPLOAD` |
| 8 | 4 | format version, currently 1 |
| 12 | 4 | flags; bit 1 is set when the payload is a VM program |
| 16 | 8 | payload offset from the start of the file |
| 24 | 8 | payload length in bytes |
| 32 | 8 | the payload's XXH64 under seed zero, little-endian |
| 40 | 8 | trailer length, currently 48 |

The magic is last-resort identification, not a search key: a runtime that finds
no magic has no payload, and one that finds a version it does not know refuses
rather than guessing. Bits the flags field does not define are zero and are
checked to be zero, so a later version can use them and an older runtime will
refuse rather than misread.

Bit 1 says the payload is a VM program, and every binary Nupp builds sets it.
Bit 0 marked the LuaJIT bytecode payloads of earlier releases; the VM runtime
refuses a payload without bit 1, saying it carries a LuaJIT payload this
runtime does not run.

The digest is a corruption check, not a security boundary: the file is
unsigned, and anyone who can rewrite the payload can rewrite the trailer beside
it. What it catches is a truncated download or a damaged file, and the
runtime's message says so. A runtime that wanted a guarantee against tampering
would need a signature over the payload, which is a separate field and a
separate question.

Which is why it is XXH64 rather than a cryptographic digest. The check runs on
every invocation over the whole payload, and the compiler's own binary carries
megabytes of one: at SHA-256 that is milliseconds added to every command,
against a tool whose design goal is that an unchanged project answers in about
the time it takes to start. XXH64 answers the same question in well under a
millisecond.

`src/nupp/tools/build/package.nupp` writes the trailer and
`native/crates/vm/src/payload.rs` reads it. They are one contract with two
spellings, and the input is read little-endian in both.

## Payload

The entry module's name on the first line, then the image the VM's lowering
wrote for the entry and everything the build carries. The runtime loads the
image, runs the entry module's body on a task with the program's arguments as
`arg` and the executable as `arg[0]`, and the program's exit status is the
process's.

### Resources and rock modules

A target's resources ride in the image as the `nupp.embedded` module, a table of
path to content. That is the same mechanism the compiler uses to carry its own
standard library declarations, so a program's resources and the compiler's
behave identically and are read through one lookup.

Rock modules ride in the image too, under the names `require` would have found
them by in the tree they came from, so `require("pl.stringx")` resolves in a
checkout and in a stamped binary alike. A target names what it carries with the
`bundle` globs on its [rock dependencies](../learn/projects/build.md#rock-dependencies);
a rock tree also holds test scripts, command-line programs and data nobody asked
for, and a payload that swept the tree would carry all of it.

### Determinism

Modules and resources are carried in sorted order, and nothing records a
timestamp, a path from the building machine, or a build counter. Two builds of
one tree produce byte-identical payloads, which is what the [packaging
fixpoint](#packaging-fixpoint) below rests on.

The runtime is reproducible to the same standard across checkouts, directories,
locales, time zones, umasks and users. Rust records the source paths of its
dependencies and standard library in panic locations, and those sit under the
building user's `CARGO_HOME` and rustup directory, so `scripts/toolchain`
remaps them for every crate it builds: the registry to `/cargo`, a vendor
directory to `/vendor`, and rustup's copy of the standard library back to the
`/rustc/<commit>` path the Rust release itself records. Where those directories
are is therefore not part of the build. An ambient `RUSTFLAGS` replaces the
remapping, as it replaces any `build.rustflags` in Cargo, and is already part of
the artifact key.

## The runtime

`scripts/toolchain vm-runtime FACILITIES` builds the runtime a binary is
stamped onto, linking only the optional native facilities the program's image
reaches: compression, networking, HTTP, regular expressions, Markdown, and C
header parsing. A program with vector code is built differently, with
`scripts/toolchain vm-program FACILITIES PAYLOAD`: its image is compiled ahead
of time into a runtime that carries no code generator and runs only that image.
Either way the runtime is built from the compiler's Rust sources, which is why
building a binary needs a Nupp source checkout.

A runtime with nothing appended is the VM's own runner, which runs the image its
command line names. A runtime with a payload is that program, and reads none of
its arguments as runner controls. It finds the payload in this order:

1. Locate its own executable, not `arg[0]`, which is whatever the caller typed.
2. Read the trailer. No magic means no payload. A version it does not know,
   unknown flags, or a payload without the VM program bit is refused, plainly.
3. Verify the payload's bounds and digest.
4. Read the entry module's name and load the image.
5. Set `arg` from the command line, dropping nothing the program should see.
6. Run it. The program's exit status is the process's.

## Host source acquisition

The toolchain builds pinned LuaJIT and LuaRocks sources, which LuaRocks needs
to install rock dependencies, rather than committing generated native artifacts
or source archives. An ordinary cold build downloads the exact upstream files
and verifies their SHA-256 digests before extraction or compilation. A verified
source already in the toolchain cache is reused before any download. The pinned
stage-zero image is fetched and verified the same way.

Package managers, offline builders and CI caches may put the same canonically
named archives in another directory and point the build at it:

```sh
NUPP_HOST_SOURCE_DIR=/opt/nupp-sources \
NUPP_HOST_OFFLINE=1 \
./scripts/toolchain luajit luarocks
```

`NUPP_HOST_SOURCE_DIR` may be relative to the command's working directory,
though an absolute path is usually clearer. It contains archives named after
their extracted directories:

```text
LuaJIT-1edc3e52b67eaf6ce5f809be8e17d6862594b8bc.tar.gz
luarocks-3.13.0.tar.gz
```

Every supplied archive is checked against the same committed digest as a
download; pointing elsewhere changes where bytes come from, never which bytes
the build accepts.

`NUPP_HOST_SOURCE_BASE_URL` replaces the upstream locations with one flat mirror
whose final path component is the canonical archive name. It is consulted only
after the output cache and source directory miss. `NUPP_HOST_OFFLINE` accepts
`1`, `true`, `yes` or `on` to forbid that last network fallback, and the
corresponding false values to allow it. An offline miss names the archive and
the source-directory setting needed to supply it.

Cargo dependencies use the committed `Cargo.lock` and Cargo checksums rather
than the archive list above. Provision an offline source tree once, then name it
for the Rust builds:

```sh
./scripts/toolchain rust-vendor /opt/nupp-rust-sources
NUPP_RUST_VENDOR_DIR=/opt/nupp-rust-sources \
NUPP_HOST_OFFLINE=1 \
./scripts/toolchain vm-runtime http,net
```

An offline Rust build without `NUPP_RUST_VENDOR_DIR` fails before Cargo runs.

## Third-party notices

A stamped binary is a distribution of what its runtime links, so the notices
ship in
[`host/NOTICE.md`](https://github.com/nupp-lang/nupp/blob/main/host/NOTICE.md)
and `host/notices/`. The generated Rust notice covers every third-party package
in `Cargo.lock`, so one committed notice set is valid for every facility and
target. Hand the directory over with the binary the way a release archive
carries a README.

The LuaJIT source is fetched at build time rather than committed, so nothing
else in the tree carries its notice. `scripts/toolchain` compares the committed
copy against the source it has just verified by digest and fails the build when
they differ. `scripts/rust-dependency-notices --write` refreshes the Cargo
aggregate; the test suite refuses a lockfile whose third-party package inventory
is not represented there.

## Signing for macOS

The runtime arrives ad-hoc signed from its linker, and appending after that
signature produces trailing bytes Apple's signer refuses. The packager takes the
signature off, appends, and signs again.

### Packager steps

1. Validate and remove the final `LC_CODE_SIGNATURE` command and blob.
2. Append the payload and trailer.
3. Extend `__LINKEDIT` through the trailer.
4. Sign the result ad hoc, with a fixed identifier and no timestamp.

`codesign` appends a new signature blob in the ordinary Apple-supported layout.
The runtime reads the trailer just before that blob, including the small zero
padding `codesign` may insert for alignment. Strict signature verification
therefore covers the payload instead of tolerating it as unsealed trailing data.
The ad-hoc signature lets the binary run where it was built and keeps two builds
of one tree byte-identical. Windows binaries remain unsigned unless a release
policy supplies Authenticode; ELF needs no signing step.

### Optional release credentials

Each release platform builds its own compiler on its own runner. Tagged release
CI can re-sign the macOS one with a Developer ID using these GitHub Actions
secrets:

- `APPLE_CERTIFICATE`: the base64-encoded Developer ID Application `.p12`;
- `APPLE_CERTIFICATE_PASSWORD` and `APPLE_SIGNING_IDENTITY`;
- `APPLE_ID`, `APPLE_APP_PASSWORD` and `APPLE_TEAM_ID` for `notarytool`.

With none of them configured, the job publishes a macOS archive that is not
Developer ID signed and records that fact in its `SIGNING.txt`. With all six
configured, it verifies the final code signature, waits for notarization, and
assesses the executable before release assets are created. A partial credential
set is an error rather than a silent fallback. Windows release binaries are
intentionally unsigned; their archive likewise says so rather than implying
Authenticode was applied.

## Packaging fixpoint

The compiler proves it can compile itself, byte for byte, on every change. The
packager proves the same thing about itself: a Nupp binary, run, stamps out a
Nupp binary identical to itself.

```bash
nupp fixpoint --binary
```

That stamps the target named by `selfHost.binary`, then has the binary that came
out stamp another, and compares them. Stage one is kept beside the output so
stage two writes where stage one did, and the comparison is of two files made
the same way rather than of one file and a memory of another.

It fails if the payload is not deterministic, if the trailer does not
round-trip, if the packager's idea of where a payload starts disagrees with the
runtime's, or if signing is not reproducible.

## Versions

Every number below versions something another process, another build, or
another release reads back. Each is checked on read, and nothing is migrated
before 1.0: a reader that finds a version it does not know refuses, naming the
version it found and the one it reads, rather than guessing.

Two policies cover them. A document another process reads -- a manifest, a
report -- carries an integer `schemaVersion` (or the older `schema`) and is
bumped whenever its shape changes. A binary contract -- an ABI, the payload
trailer -- is versioned apart from any document, because it versions the bytes
two programs exchange rather than what one of them wrote. Payloads and runtimes
are rebuilt with the toolchain that reads them.

| Format | Version | Rule | Declared in |
| --- | --- | --- | --- |
| Native provider ABI | 2 | exact major | `native/include/nupp_native.h` `NUPP_NATIVE_ABI_VERSION` |
| Payload trailer | 1 | exact | `native/crates/vm/src/payload.rs` `FORMAT_VERSION` |
| Documentation model | 3 | read by consumers | `src/nupp/tools/doc/init.nupp` `schemaVersion` |
| Coverage report | 1 | exact | `src/nupp/tools/coverage.nupp` `SCHEMA_VERSION` |
| Test report | 1 | exact, for `--rerun` | `src/nupp/tools/cli/test.nupp` `schemaVersion` |
| Bench record | 5 | an older record is an inconclusive baseline | `src/nupp/bench/init.nupp` `SCHEMA` |
| GPU cost records | 1 | read by consumers | `native/crates/gpu/src/costs.rs` `schemaVersion` |

To bump one, change the constant and this row together; a test holds the two to
the same number. A major ABI bump is two-phase when stage zero reads it: a
release whose reader accepts both versions ships first, the stage-zero pin moves
to it, and only then does the writer bump.

Caches are not in this table. Every cache is keyed on the compiler that wrote
it, so a mismatch is a miss and costs a cold rebuild, never an error; see [Cache
and failure behavior](../learn/projects/build.md#cache-and-failure-behavior).
`nupp --json` output is not either: its version is the compiler's, and
`--schema` is its contract.

## Limits

A distributed binary is deliberately none of these things.

- **It does not replace the stage-zero compiler.** The `nupp-stage0-<tag>.image.gz`
  asset beside it exists so a source checkout can build a compiler; a
  distributed binary is what comes out the other end. Different problems that
  are easy to conflate.
- **It is for one platform.** A binary is built for the machine building it.
  There is no cross-platform stamping: each platform's binary is built on that
  platform, as each release platform's compiler is built on its own runner.
- **Stamping does not absorb arbitrary native dependencies.** A binary still
  ships project C and Rust dependency libraries beside it.
- **C dependencies still need a C compiler.** A project C dependency built from
  sources needs a C compiler on the machine; prebuilt target-indexed C archives
  remain usable without one.
- **It does not make Nupp a C project either.** The runtime and its native
  facilities are Rust; the complete ownership and support matrix is in [Native
  runtime and support](native-runtime.md).

::: seealso
- [build.md](../learn/projects/build.md#rock-dependencies) for the targets and rock
  globs a payload is assembled from
- [native-modules.md](../learn/projects/native-modules.md#embedding-the-vm) for
  running Nupp inside a Rust application you own
- [native-runtime.md](native-runtime.md) for the exact Rust/native boundary
:::
