---
title: C-only toolchain
status: Implemented
created: 2026-08-21
---

## Summary

Nupp's two Rust crates — the native provider in `runtime/native` and the binary
host in `host` — are reimplemented in C behind the C ABI they already export,
and Cargo is removed from the tree. A fresh checkout then builds with one
compiler pair, `clang`/`clang++` or `gcc`/`g++`, plus a shell, a downloader and
an archiver. LuaJIT, LPeg and simdjson are provisioned by Nupp from pinned,
hash-verified sources rather than expected on the machine. `NUPP_CC` and
`NUPP_CXX` name the toolchain everywhere.

## Goals

- A machine with no Rust, no LuaJIT, no LPeg and no simdjson runs `nupp check`,
  `nupp build` and `nupp build --target dist` from a clean checkout.
- One toolchain configuration, `NUPP_CC` and `NUPP_CXX`, covers the native
  provider, the host, the JSON bridge and AOT output.
- Every phase lands independently, with the tree building and testing on both
  sides of it.
- The C ABI the FFI bindings and the embedding header already describe does not
  move, so the Lua side of the runtime is unchanged by the port.
- Release binaries stay dependency-free for the people who run them.

## Non-goals

- Removing C++. simdjson is C++17 and stays that way; what is bounded is where
  C++ appears, which is the JSON bridge and nothing else.
- Rewriting the compiler. It is Nupp compiled to Lua and run on LuaJIT before
  this proposal and after it.
- Changing what AOT emits. It emits C already.
- Portability beyond the platforms Nupp supports today. Standard C does not
  cover processes, paths or event polling, and this does not pretend otherwise.
- Writing an HTTP or TLS implementation.

## Motivation

Rust is the largest thing Nupp asks for and the one least related to what Nupp
is. The compiler is Nupp; the runtime the compiler targets is LuaJIT; the code
AOT emits is C; the interpreter, the parser generator and the JSON parser are C
and C++. Rust appears in exactly two places, and both of them exist to be
called through a C ABI from LuaJIT's FFI. The ABI is the interface, so the
implementation language is an implementation detail — one that currently costs
every contributor a second toolchain, every CI job a rustup step and a Cargo
cache, and every embedder a Rust static library in their link line.

The setup promise is the other half. "Install Rust, LuaJIT 2.1 recent enough for
the backported syntax, LPeg against that LuaJIT, and a C++ compiler" is four
answers that can each be wrong, and the LuaJIT one is wrong quietly: an older
interpreter loads generated code and fails at a line nobody wrote. Nupp already
knows how to fetch, pin and build C dependencies — that is what the `c`
dependency provider does for projects — so the same machinery can provision its
own prerequisites and reduce the promise to a compiler pair.

Doing this as a rewrite would mean one flag day where nothing is testable.
Doing it behind the existing ABI means the C implementation and the Rust one are
interchangeable at every point, so each feature ports, runs its existing suite,
and lands.

## Overview and specification

### Target architecture

After the port the tree contains no Rust and four kinds of native code:

- `runtime/native/`, C, built as a shared library for development and as
  objects for feature-selected static links. Exports the `nupp*` functions the
  FFI bindings declare.
- `host/`, C, the binary stub and the embedding library. Exports the ABI in
  `host/include/nupp.h`.
- `runtime/json/`, C++17 over simdjson, behind a C header. Unchanged in
  language, rebuilt by the same driver as everything else.
- Generated AOT output, C, compiled with `NUPP_CC`.

Supported toolchain pairs are `clang` with `clang++`, and `gcc` with `g++`.
Mixing across pairs is not supported and is not detected.

### Toolchain configuration

`NUPP_CC` names the C compiler and `NUPP_CXX` the C++ compiler, for the native
provider, the host, the JSON bridge, AOT output, and every pinned dependency
the bootstrap driver builds. Neither is required: the driver probes `clang`,
`cc`, `gcc` and the corresponding C++ names in that order.

`NUPP_NATIVE_CC` and `NUPP_JSON_CC` continue to work as aliases for `NUPP_CC`
and `NUPP_CXX` respectively, so an existing script and an existing CI job keep
building. They are documented as compatibility aliases from this proposal
onward and are removed no earlier than the release after the port lands.

### Bootstrap toolchain

A build driver provisions, from sources pinned by revision and verified against
a digest:

1. LuaJIT.
2. LPeg, against that LuaJIT.
3. simdjson and `runtime/json/json.cpp`, with `NUPP_CXX`.
4. The subset of the C native provider stage zero needs, which is `files`.
5. `bootstrap/nupp.lua`, run on the staged LuaJIT.

Every artifact is cached under the repository cache scheme already used for
native builds, so the second run is a cache hit and a worktree shares the
first run's work. The offline and archive overrides that exist for dependency
fetching apply here too: a machine with the archives already present builds
without a network.

The driver is the only way Nupp builds its own native prerequisites. `bin/nupp`
calls it instead of reaching for `cargo` and instead of requiring `luajit` on
`PATH`.

This is not new capability. CI already builds pinned LuaJIT and LPeg. What the
driver adds is that the build is atomic, cached, offline-capable, and the same
on a contributor's machine as in CI.

### Native provider port

The C provider is written against the ABI the Rust one exports, and the two run
in parity while the port proceeds: the development library is built from
whichever implementation has the feature, and a feature is not removed from the
Rust side until the C side passes that feature's suite.

Ported in this order, because it is the order that unblocks:

1. `files`, which stage zero reaches while listing its own sources. With it in
   C, bootstrapping the compiler no longer needs Rust.
2. `path`, `uri`, UUID and SHA-256 — pure computation over bytes, no platform
   surface, and the easiest place to establish the parity harness.
3. Process spawning, pipes and polling.
4. HTTP, which is [its own section](#http-on-libcurl).

Platform code is split explicitly into `platform_posix.c` and
`platform_windows.c` with a shared header. There is no attempt to express
processes, path semantics or readiness polling in portable C with `#ifdef`
blocks threaded through one file; the two implementations are two files and the
shared code is what genuinely does not vary.

The Rust provider is deleted when every feature has an equivalent C
implementation and passing tests, not before.

### Host port

The C host does what the Rust one does:

- Locates its own executable, finds the appended payload, verifies its digest,
  and loads it.
- Starts LuaJIT and registers the native features the build selected.
- Implements the embedding ABI in `host/include/nupp.h` unchanged.
- Links feature-selected static builds rather than one universal binary, so a
  program that uses no HTTP does not carry libcurl.
- Provides worker states and bounded byte channels.

The Rust host stays the default until the C host passes the payload, embedding,
worker and distribution suites. The default then swaps, and Cargo is removed
from the tree in the same change that removes the last crate.

### HTTP on libcurl

Tokio and reqwest are replaced by libcurl's socket-based multi interface, which
exists for exactly this: an application that owns its event loop and wants
concurrent transfers. One reactor belongs to one Nupp runtime or host, not to
the process — a global singleton would make two embedded runtimes in one
process share cancellation and limits, which is not what either asked for.

The reactor owns a `CURLM` handle. curl's socket and timer callbacks register
descriptors and deadlines with the host scheduler's event loop, and curl
readiness becomes a Nupp suspension wakeup. Native callbacks stay Lua-free:
they enqueue into bounded buffers and hand back readiness tokens, and the Lua
side is what turns those into values. DNS is configured asynchronously, because
a synchronous resolver stalls a scheduler frame for however long the network
takes to answer.

TLS is pinned libcurl over pinned mbedTLS, built by the bootstrap driver. That
keeps the one-compiler promise honest at the cost of owning a security-update
cadence and a CA-root policy, both of which are written down as part of the
pin. The alternatives are in [Alternatives considered](#alternatives-considered).

### Landing order

Each phase leaves the tree building and tested:

1. Bootstrap driver, with Cargo still present and still used.
2. Native provider, feature by feature, in parity with Rust.
3. Host.
4. HTTP.
5. Cargo removal, `NUPP_NATIVE_CC` and `NUPP_JSON_CC` demoted to documented
   aliases.

### Exit criteria

A machine with no Rust, LuaJIT, LPeg or simdjson installed, holding a fresh
checkout and one compiler pair, runs:

```sh
./bin/nupp check
./bin/nupp build
./bin/nupp build --target dist
```

CI verifies compiler bootstrap cold and cached; GCC and Clang builds including
GCC AOT; JSON, LSP, docs and binary packaging; HTTP cancellation, streaming,
limits, DNS, proxy and shared-reactor behaviour; embedding and workers; and the
existing fixpoint and reproducibility guarantees.

## Risks and assumptions

- **C is a worse language for this code than Rust.** The provider parses
  untrusted paths and URIs and manages process lifetimes, which is where use
  after free and buffer arithmetic live. The bet is that the ABI boundary is
  narrow, the suites are the ones the Rust implementation already passes, and
  sanitiser builds in CI cover what review does not. If that bet is wrong it
  shows up as memory-safety bugs in exactly the features listed above.
- **Pinned libcurl and mbedTLS mean owning security updates.** A CVE in either
  is Nupp's to ship. The mitigation is that the pin is a single file and the
  update is a digest change, not that the risk is small.
- **Self-provisioning LuaJIT moves a failure from setup to build.** A machine
  whose compiler cannot build LuaJIT now fails inside Nupp's build rather than
  in the user's package manager, and the error has to say so.
- **Windows is the thinnest platform here.** The Rust provider gets process
  handling, path semantics and overlapped I/O from crates. `platform_windows.c`
  gets them from being written, and the Windows CI job is what says whether it
  was written correctly.
- **This assumes the ABI is complete.** Where the Rust implementation leaks
  behaviour the header does not describe, a C reimplementation that matches the
  header will still differ. Parity running is the defense.

## Alternatives considered

**Keep Rust.** Nothing is broken; the cost is a second toolchain for two
libraries that exist to be called through a C ABI. Rejected because the setup
promise is the point, and "install Rust to build a Lua compiler" is the largest
thing standing in it.

**Rewrite in one change.** Smaller total diff, one review. Rejected because
nothing is testable until all of it is, and the failure mode of a flag day is
discovering the process-polling semantics were subtly wrong after the Rust
implementation is already deleted.

**Remove C++ as well, by replacing simdjson.** Would make the promise "one C
compiler" rather than "one compiler pair". Rejected: simdjson is the reason
JSON is fast, and a hand-written replacement trades a real property for a
cosmetic one.

**System libcurl and system TLS.** Much less to maintain, and the platform ships
security updates. Rejected as the default because it breaks the setup promise —
the build now depends on a library and a version that a fresh machine may not
have — though it remains the sensible choice for a distribution packaging Nupp,
and the build accepts it.

**Implement HTTP and TLS directly.** Rejected without much thought. Neither is a
thing to write in order to avoid a dependency.

**Vendor Rust output as prebuilt objects.** Would remove the Rust toolchain
requirement without a port, by checking in compiled artifacts. Rejected: it
makes the tree unbuildable from source on any platform nobody prebuilt for, and
moves the toolchain requirement onto whoever cuts a release rather than
removing it.

## 2026-08-22: the URI parser is ada, and C++ moves to C++20

The URI facility was reimplemented by hand rather than taken from a library,
because the two obvious candidates did not fit: curl's URL API has no
representation for an opaque path, so `mailto:`, `urn:` and `data:` -- all three
of them documented on [](nupp.io.uri) -- could not be expressed at all.

[ada](https://github.com/ada-url/ada) is the WHATWG parser Node.js uses, ships a
C API, and implements the model this library documents. Checked against the
table recorded from the implementation being replaced, it agrees on every one of
seventeen URIs and eleven components each, refuses the same six malformed
inputs, and answers identically to every derivation, concatenation, resolution
and rerooting. So the hand-written parser is gone and 1123 lines of the most
specification-sensitive code in the tree went with it.

What ada does not answer is *why* a URI is invalid, which a caller validating
text from outside the program shows to a person. Three faults are worth telling
apart -- no scheme, an empty host where the scheme requires one, an unclosed
IPv6 bracket -- and those are classified here, on the failure path only.

The cost is the C++ standard. Ada 4 needs C++20 for `std::endian`, where
simdjson needed C++17, so the floor stated above moves with it. GCC 10 and Clang
10 are the first releases that carry it, both from 2020, and the supported
compiler pairs are otherwise unchanged.

## 2026-08-22: libuv owns the platform layer

The first C provider put process, filesystem and threading primitives behind
`platform_posix.c` and `platform_windows.c`. That kept platform branches out of
the shared facilities, but it left 3234 lines whose least exercised half was
also the most difficult half: Windows process inheritance, overlapped pipes and
directory traversal. The split made the risk visible without reducing it.

[libuv](https://libuv.org/) already owns that portability boundary for Node.js.
It supplies the process and pipe lifecycle, filesystem calls, a bounded event
loop, a thread pool and the few mutex, condition and thread primitives the HTTP
reactor needs. Replacing the two platform files with it removes more code than
the dependency adds to Nupp's tree, and puts the Windows behavior behind a
library exercised on Windows outside this project rather than an implementation
written here and judged only by this project's CI.

This does not make libuv Nupp's general scheduler and does not move HTTP onto
it. The process loop is pumped by the existing process seam, filesystem work is
submitted through the existing lane, and libcurl still owns HTTP. The choice is
the portability layer, not a new runtime architecture.

The source is pinned and digest-verified like the other bootstrap dependencies.
Building its explicit per-platform source list avoids adding CMake or autoconf
to the setup promise; the cost is that a libuv update must compare that list
with libuv's own build files. Keeping the handwritten layer was rejected because
its line count and platform risk were already the reason to seek a portability
library. Higher-level event and HTTP libraries were rejected because they do
not cover files and child processes, or would replace libcurl as well and turn a
platform change into a transport change.
