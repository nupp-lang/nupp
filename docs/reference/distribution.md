---
order: 700
title: Distribution
---

# Stubs and payloads

A distributed program is a stub with a payload appended to it. The stub is an
executable embedding LuaJIT that knows how to find a payload, and the payload is
one Lua chunk carrying everything the program needs.

```text
[ stub executable ][ payload chunk ][ trailer ]
```

Making a binary is copying a stub, appending a payload, and writing a trailer
that says where the payload starts. Nothing in that is specific to Nupp's own
compiler: an engine or framework can publish a host that opens a window or owns
an event loop, and [`nupp build`](../guides/build.md) stamps programs into it
without knowing what it is.

## Container

The payload is appended to the stub file, followed by a fixed trailer. An
unsigned file ends at the trailer. A signed Mach-O carries Apple's
code-signature blob after it, with any zero alignment padding in between, and
the stub finds that boundary through `LC_CODE_SIGNATURE`.

| Region | Contents | Present |
| --- | --- | --- |
| stub executable | an ordinary ELF, Mach-O, or PE image | always |
| payload | one Lua chunk | once stamped |
| trailer | 48 fixed bytes | once stamped |
| Mach-O signature | Apple's code-signature blob | signed macOS only |

The payload and trailer stay covered by the signature because the packager
extends `__LINKEDIT` over them before the native signer runs. See [Signing for
macOS](#signing-for-macos) for the order that makes that work.

::: deepdive
An appended chunk rather than a platform section: an ELF section, a Mach-O
section and a PE resource are three formats and three writers, and the payload
contract needs nothing any of them supplies.

The format is specified before its consumers because it stops being revisable
the moment somebody publishes a stub built against it, in a repository nobody
here controls. The first two consumers are both Nupp's own, the trivial test
host and the compiler itself, and the [packaging fixpoint](#packaging-fixpoint)
is the last gate before a third party is invited to publish one.
:::

### Trailer

48 bytes, little-endian, at the end of an unsigned file. For a signed Mach-O it
is immediately before the zero alignment padding and code-signature offset named
by `LC_CODE_SIGNATURE`. A stub checks only those format-defined boundaries; it
does not search arbitrary executable bytes for the magic.

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 8 | magic, the ASCII bytes `NUPPLOAD` |
| 8 | 4 | format version, currently 1 |
| 12 | 4 | reserved, zero |
| 16 | 8 | payload offset from the start of the file |
| 24 | 8 | payload length in bytes |
| 32 | 8 | first 8 bytes of the payload's SHA-256 |
| 40 | 8 | trailer length, currently 48 |

The magic is last-resort identification, not a search key: a stub that finds no
magic has no payload and says so, and one that finds a version it does not know
refuses rather than guessing. Reserved bytes are zero and are checked to be
zero, so a later version can use them and an older stub will refuse rather than
misread.

The truncated digest is a corruption check, not a security boundary. A stub that
wanted integrity guarantees would need a signature over the payload, and
appending one is a version-2 question.

### Compiler host ABI

The container format version answers whether a stub can locate a payload. The
compiler host ABI answers whether that host can run what the compiler put in the
payload. It is currently `1` and is published to the payload as
`__nuppHost.hostAbi`, beside a `hostFeatures` set.

The ABI changes when an older compiler-owned host cannot correctly run a new
payload: incompatible preload registration, bootstrap capability records,
worker startup protocol, or generated-runtime requirements. Adding a compatible
optional host feature does not change it. A trailer change changes the container
format version, and changes the host ABI too only when it also changes the
payload/host runtime contract. Target C layout ABI is separate from both.

A compiler compares a catalog stub's host ABI before stamping it. The payload
repeats the comparison before user code runs, checks its required host features,
and removes unselected native preloads. That exposure mask depends only on the
target's selected features, so selecting a universal catalog stub does not
change payload bytes or make unused modules observable.

## Payload

One Lua chunk, exactly as `nupp build` with a `bundle` target produces it. Its
shape:

```lua
package.preload["some.module"] = function(...) --[[ compiled module ]] end
-- ...one per module in the program...
package.preload["nupp.embedded"] = function()
    return {["/some/resource.txt"] = [==[ ... ]==]}
end
-- the entry module's code, last, as the chunk's own body
```

The chunk is plain Lua and runs under a compatible `luajit` when that runtime
also supplies every native feature the target resolved. A target with no native
effects needs no stub; [](nupp.peg), for example, resolves native LPeg and
therefore needs a feature-matched host or an LPeg module on LuaJIT's module
path.

"Plain" has a floor. Generated Nupp is written in the LuaJIT 3.0 syntax that 2.1
backported, meaning `?.`, `??`, `?:`, the bit operators and compound assignment,
rather than in a lowering of it, so a payload needs LuaJIT 2.1.1784535649 or
newer. A stub is therefore not free to embed whichever LuaJIT its build system
had lying around: `host/build.rs` pins one by revision and digest, and the pin
is a requirement rather than a preference.

### Resources and rock modules

Resources ride in `package.preload["nupp.embedded"]` as a table of path to
content. That is the same mechanism the compiler uses to carry its own standard
library declarations, so a program's resources and the compiler's behave
identically and are read through one lookup.

Rock modules ride in `package.preload` too, under the names `require` would have
found them by in the tree they came from, so `require("lunamark")` resolves in a
checkout, in a bundle, and in a stamped binary, and the program cannot tell
which it is running in. A target names what it carries with the `bundle` globs
on its [rock dependencies](../guides/build.md#rock-dependencies); a rock tree
also holds test scripts, command-line programs and lexers nobody asked for, and
a payload that swept the tree would carry all of it.

### Determinism

Modules and resources are emitted in sorted order, and nothing records a
timestamp, a path from the building machine, or a build counter. Two builds of
one tree produce byte-identical payloads, which is what the [packaging
fixpoint](#packaging-fixpoint) below rests on.

## Stub requirements

A stub does six things, in this order.

1. Locate its own executable. Not `arg[0]`, which is whatever the caller typed:
   `/proc/self/exe`, `_NSGetExecutablePath`, `GetModuleFileNameW`.
2. Read the last 48 bytes. No magic, or a version it does not know: report that
   plainly and exit non-zero. Do not fall back to guessing.
3. Verify the payload's length and truncated digest.
4. Load the payload as a Lua chunk, named so tracebacks are readable.
5. Set `arg` from the command line, dropping nothing the program should see.
6. Run it. The program's exit status is the process's.

A stub with no payload is a plain interpreter: it runs the file named as its
first argument. That is what makes a stub testable before anything is stamped
into it, and what makes `nupp` itself usable during development.

Everything else a stub does is its own business. A game engine's stub may open a
window and own an event loop before step 6; Nupp's own does none of that.

## Host source acquisition

The compiler-owned host builds its pinned LuaJIT, simdjson, LPeg and luautf8
sources rather than committing generated native artifacts or source archives.
An ordinary cold build downloads the exact upstream archives and verifies their
SHA-256 digests before extraction. An extracted source tree or archive already
in the toolchain cache is reused before any download.

Package managers, offline builders and CI caches may put the same canonically
named archives in another directory and point the build at it:

```sh
NUPP_HOST_SOURCE_DIR=/opt/nupp-sources \
NUPP_HOST_OFFLINE=1 \
./scripts/toolchain host json,lpeg,native-files,native-process,workers
```

`NUPP_HOST_SOURCE_DIR` may be relative to `host/`, though an absolute path is
usually clearer. It contains archives named after their extracted directories:

```text
LuaJIT-1edc3e52b67eaf6ce5f809be8e17d6862594b8bc.tar.gz
simdjson-4.6.4.tar.gz
lpeg-1.1.0.tar.gz
luautf8-0.2.1.tar.gz
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

## Cross-target stub acquisition

A binary target with `stub = "nupp"` and `platforms` stamps verified prebuilt
compiler hosts instead of invoking a target linker. The initial catalog is
local-only: `NUPP_STUB_CATALOG` may name an immutable JSON catalog and
`NUPP_STUB_DIR` names the directory containing its artifacts. Embedded release
catalogs use the same shape.

Every stub is checked for host ABI, required host features, byte length,
SHA-256, executable format and target architecture. Accepted bytes are cached
under `.nupp/stubs/<catalogRelease>/<hostAbi>/<platform>/<sha256>/`; changing a
catalog or override digest therefore forces a restamp. A cache or directory
miss is an error and does not invoke `curl` or another system downloader.

Cross-target POSIX results include a deterministic `.tar` containing the raw
binary at mode `0755`, so a Windows build host cannot erase the executable bit.
PE results need no mode operation. Cross-stamped macOS binaries are unsigned
development artifacts, and an ad-hoc signature on macOS makes one locally
executable:

```bash
codesign --force --sign - <binary>
```

Release CI uses a Developer ID identity and notarizes the final stamped bytes.

## Third-party notices

The compiler-owned stub links LuaJIT and, where the features are on, simdjson,
LPeg, and luautf8. Simdjson is Apache-2.0, and the other three are MIT. A
stamped binary is a distribution of them, so their notices ship in
[`host/NOTICE.md`](https://github.com/nupp-lang/nupp/blob/main/host/NOTICE.md)
and `host/notices/`, which carry the notice files as they arrive in the pinned
sources, byte for byte. Hand them over with the binary the way a release archive
carries a README.

The sources are fetched at build time rather than committed, so nothing else in
the tree carries those notices. `host/build.rs` compares each committed copy
against the archive it has just verified by digest and fails the build when
they differ, because a notice that has drifted from what was distributed is a
false statement rather than a stale file.

## Signing for macOS

The catalog stub arrives ad-hoc signed from its linker, and appending after that
signature produces trailing bytes Apple's signer refuses. The packager takes the
signature off, appends, and leaves the result for a native signer.

### Packager steps

1. Validate and remove the final `LC_CODE_SIGNATURE` command and blob.
2. Append the payload and trailer.
3. Extend `__LINKEDIT` through the trailer.
4. Leave explicit cross-target output unsigned for a native signer.

`codesign` then appends a new signature blob in the ordinary Apple-supported
layout. The host reads the trailer just before that blob, including the small
zero padding `codesign` may insert for alignment. Strict signature verification
therefore covers the payload instead of tolerating it as unsealed trailing data.

A source-built current-macOS target is ad-hoc signed automatically with a fixed
identifier and no timestamp so it runs immediately and remains deterministic.
Explicit cross-target output is the same unsigned bytes regardless of compiler
host. Windows developer artifacts remain unsigned unless a release policy
supplies Authenticode; ELF needs no signing step.

### Release credentials

Tagged release CI requires these GitHub Actions secrets:

- `APPLE_CERTIFICATE`: the base64-encoded Developer ID Application `.p12`;
- `APPLE_CERTIFICATE_PASSWORD` and `APPLE_SIGNING_IDENTITY`;
- `APPLE_ID`, `APPLE_APP_PASSWORD` and `APPLE_TEAM_ID` for `notarytool`.

The job refuses a tag when any credential is absent, verifies the final code
signature, waits for notarization, and assesses the executable before release
assets are created. Windows release binaries are intentionally unsigned; the
archive says so rather than implying Authenticode was applied.

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

It is the acceptance test for everything above. It fails if the payload is not
deterministic, if the trailer does not round-trip, if the emitter's idea of
where a payload starts disagrees with the stub's, or if signing is not
reproducible. It passes, and it is the last gate before a third party is allowed
to publish a stub, because after that the format cannot move.

::: deepdive
Two things the fixpoint caught, both of which would otherwise have been found by
somebody else.

A bundle was carrying every `.lua` under the output directory, which is also
where native dependencies build, and a dependency tree can contain example
scripts that are not valid preload modules. A bundle now carries what the build
compiled and nothing else.

The stub could not provide JSON until the native opener was linked and
registered in `package.preload`, because the compiler uses JSON before it does
most work.
:::

## Limits

A distributed binary is deliberately none of these things.

- **It does not replace the bootstrap.** `bootstrap/nupp.lua` exists so a source
  checkout can build a compiler; a distributed binary is what comes out the
  other end. Different problems that are easy to conflate.
- **It does not absorb arbitrary native dependencies.** Self-contained means the
  program needs no LuaJIT and no engine installed. A project with its own C or
  provider library still ships that library beside the binary, unless it is linked
  into a stub built for the purpose.

  Nupp's compiler payload detects three native modules, and its compiler-owned
  host links exactly those features: simdjson, which backs the compiler's JSON
  runtime; LPeg, which backs direct LPeg patterns and every
  general `nupp.peg` matcher; and `luautf8`, which Lunamark's entity table uses.
  The official `re.lua` module remains ordinary Lua in the payload. Another
  payload selects whatever its own code and bundled dependencies need; the
  format has no opinion.
- **It does not make Nupp a C project either.** The host is a component, built by
  the same machinery that already builds a project's other native dependencies.

::: seealso
- [build.md](../guides/build.md#rock-dependencies) for the targets and rock
  globs a payload is assembled from
- [embedding.md](../guides/embedding.md) for running Nupp inside a host you own
  rather than one the packager stamps
- [NEP 8](../neps/0008-c-interop-and-embedding.md) for the design record behind
  the C boundary a stub sits on
:::
