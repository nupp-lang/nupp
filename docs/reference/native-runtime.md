---
order: 710
title: Native runtime and support
---

# Native runtime and support

Nupp source and the Nupp compiler own language behavior. Rust owns the runtime
that executes a program and the native resources it reaches. A native build
does not translate a Nupp program into a Rust application: the compiler lowers
the program to a VM image, and the Nupp VM runtime (`native/crates/vm`) loads
and runs that image.

The boundary is deliberately narrow:

| Layer | Owner | Responsibilities |
| --- | --- | --- |
| language and compiler | Nupp | types, effects, ownership, suspension policy, facility selection, lowering to VM images |
| VM runtime | Rust, with a C dispatch core | image loading and verification, the interpreter, the heap and collector, tasks and scheduling, native C calls |
| native facilities | Rust | files, paths, clocks, UUIDs, URI, HTTP, TCP, UDP, path sockets, TLS, processes, compression |

Native resources cross into Nupp as plain values and handles. Nupp code never
receives a Rust reference, future, Tokio handle, or Reqwest response. Executor
threads never enter the VM: a network operation is a nonblocking poll of state
the shared Tokio executor moves on its own threads.

## Facility selection

Authors select APIs, not Cargo features. The compiler records the native
facilities a program's image reaches, and a [`binary`
target](../learn/projects/build.md) is stamped onto a VM runtime built with
those and no others. Every program runtime has the interpreter, native C calls,
files, paths, clocks, UUIDs and processes; the optional facilities are:

| Facility | Reached through | Rust implementation |
| --- | --- | --- |
| `compression` | compression | `flate2` |
| `net` | sockets and TLS | Tokio and `socket2`, with Rustls for TLS |
| `http` | the HTTP client and URI | Reqwest over Tokio and Rustls, and the `url` crate |
| `regex` | `nupp.text.regex` | the `regex` crate |
| `markdown` | Markdown rendering | `pulldown-cmark` |
| `c-headers` | reading C headers at compile time | the C declaration reader |

A program with vector code gets a runtime with its image compiled ahead of time
and linked in, carrying no code generator. The compiler's own runtime links
every facility.

The VM has no GPU provider yet, so a program using `nupp.gpu` finds no device
on it.

## Native implementations

The current implementation choices are:

- Tokio owns the shared asynchronous executor and the file, network, process,
  timer, and cancellation lanes built on it.
- Reqwest owns the HTTP client, connection pooling, streaming, proxy support,
  and content decoding. The selected build uses Rustls rather than a native TLS
  backend.
- Rustls owns TLS policy and protocol state. `ring` is the explicitly selected
  cryptography provider and system roots come through `rustls-native-certs`.
- libffi, through the `libffi` crate, performs native C calls and builds
  callback trampolines.
- Cranelift compiles VM bytecode to machine code.
- Rust standard APIs, `socket2`, `windows-sys`, and narrow `libc` calls cover
  files, sockets, process handles, and platform details not exposed by the
  standard library.

These libraries are implementation details. The Nupp modules define the public
contracts and may intentionally expose less than the underlying crate.

## Retained non-Rust boundary

Rust is the default language for repository-owned native mechanisms, not a
claim that every executable byte is Rust. Native builds still retain:

- `native/crates/vm/csrc/dispatch.c`, the VM's tail-call-threaded interpreter
  core and its helpers;
- libffi's C and assembly, built and linked through the `libffi-sys` crate;
- `ring`'s bounded C and assembly implementation under its Rust API;
- operating-system libraries and platform SDKs selected by Rust crates and the
  final linker.

The release notices describe the third-party source a binary carries.

## Release support matrix

The official release workflow builds the compiler on each platform's own
runner, as a VM program for that runner:

| Platform | Release archive |
| --- | --- |
| `x86_64-unknown-linux-gnu` | `nupp-linux-x86_64.tar.gz` |
| `aarch64-apple-darwin` | `nupp-macos-arm64.tar.gz` |
| `x86_64-pc-windows-gnu` | `nupp-windows-x86_64.tar.gz` |

The Windows build uses the GNU Rust toolchain named in
[`CONTRIBUTING.md`](https://github.com/nupp-lang/nupp/blob/main/CONTRIBUTING.md#requirements).
The release also publishes the stage-zero compiler image a source checkout
bootstraps from.

### Verification ownership

The compiler CI matrix runs the Nupp suite on Linux x86-64, macOS arm64, and
Windows x86-64. Release builders gate the Rust native artifacts on the runner
whose output they package, because a separate compiler workflow cannot be a
dependency of a tagged release, then verify the binary packaging fixpoint and
build, package, unpack and run the compiler. Those workflows are the platform
gates; their presence alone is not evidence that a particular commit completed
them. Manual release rehearsals do not hold Apple Developer ID credentials and
cannot exercise optional tag-only signing and notarization; the same workflow
still builds and verifies an unsigned macOS archive without them.

::: seealso
- [Distribution](distribution.md) for payloads and signing
- [Native modules](../learn/projects/native-modules.md) for extending and embedding the VM
- [Building projects](../learn/projects/build.md) for binary targets
:::
