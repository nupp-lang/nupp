---
order: 710
title: Native runtime and support
---

# Native runtime and support

Nupp source and the Nupp compiler own language behavior. Rust owns native
resources, asynchronous work, and the production host around LuaJIT. A native
build therefore does not translate a Nupp program into a Rust application:
the compiler still emits Lua, C AOT code, or GPU shader code, and the selected
Rust substrate supplies the mechanisms that code reaches.

The boundary is deliberately narrow:

| Layer | Owner | Responsibilities |
| --- | --- | --- |
| language and compiler | Nupp | types, effects, ownership, suspension policy, feature selection, AOT analysis and emission |
| native provider | Rust | files, paths, clocks, UUIDs, URI, HTTP, TCP, UDP, path sockets, TLS, processes, and GPU resources |
| host | Rust | payload discovery, LuaJIT state lifetime, native preload registration, workers, components, embedding handles, and shutdown |
| VM and compatibility modules | C | LuaJIT and the retained LPeg module |
| generated AOT | C, platform object code, or shader code | compiler-admitted kernels and their bindings |

Rust resources cross into LuaJIT as fixed-width values and generational
handles. Nupp code never receives a Rust reference, future, WGPU object, Tokio
handle, or Reqwest response. Rust executor threads never enter LuaJIT; they
publish bounded completion records which the owning Lua lane consumes.

## Compiler-selected features

Authors select APIs, not Cargo features. The compiler records effects from the
reachable program and closes their dependencies. The build then asks
`scripts/toolchain` for an exact-feature provider and host. Default Cargo
features are disabled, so an HTTP-free program does not acquire Reqwest and a
GPU-free program does not acquire WGPU.

| Nupp facility | Rust provider feature | Host feature when linked into a stub |
| --- | --- | --- |
| clocks and timer suspension | `base` | base host |
| paths | `filesystem` | `native-files` |
| asynchronous files | `files` | `native-files` |
| UUID | `uuid` | provider archive |
| URI | `uri` | provider archive |
| HTTP client | `http` | provider archive |
| TCP, UDP, DNS, and Unix path sockets | `net` | `native-net` |
| TLS over a Rust-owned network stream | `tls` | `native-tls` |
| child processes and pipes | `process` | `native-process` |
| native GPU compute | `gpu` | provider archive |
| workers and shared immutable bytes | host-owned | `workers` |
| `nupp.peg`, raw `lpeg`, and `re` | retained LPeg | `lpeg` |

`tls` includes the Rust network implementation, and the compiler's HTTP effect
closure also selects URI handling. A standalone link may combine the Rust
application-host archive with one or more exact-feature provider or AOT
archives. Shared sidecar builds stage the same provider ABI in a dynamic
library instead.

The provider's ABI version 2 is an internal compiler/runtime boundary. It is
not an extension ABI for applications. The public C embedding API in
`host/include/nupp.h` has its own version and opaque types; its implementation
is Rust even though C and C++ applications call it.

## Native implementations

The current implementation choices are:

- WGPU owns GPU device discovery, resources, command submission, and backend
  selection. Native targets enable Metal on macOS, DX12 and Vulkan on Windows,
  and Vulkan and GLES on other Unix systems.
- Tokio owns the shared asynchronous executor and the file, network, process,
  timer, and cancellation lanes built on it. Nupp uses Tokio rather than a
  second Mio-based reactor.
- Reqwest owns the HTTP client, connection pooling, streaming, proxy support,
  and content decoding. The selected build uses Rustls rather than a native TLS
  backend.
- Rustls owns TLS policy and protocol state. `ring` is the explicitly selected
  cryptography provider and system roots come through `rustls-native-certs`.
- Rust standard APIs, `socket2`, `windows-sys`, and narrow `libc` calls cover
  files, sockets, process handles, and platform details not exposed by the
  standard library.

These libraries are implementation details. The Nupp modules define the public
contracts and may intentionally expose less than the underlying crate.

## Retained non-Rust boundary

Rust is the default language for repository-owned native mechanisms, not a
claim that every executable byte is Rust. Native builds still retain:

- pinned LuaJIT, its allocator, garbage collector, JIT, stack, and C API;
- LPeg 1.1 for `nupp.peg`, raw `lpeg` and `re` compatibility, and compiler
  documentation parsing;
- `native/crates/host/c/lua_shim.c` and `worker_shim.c`, which contain the
  protected LuaJIT stack, userdata, callback, and longjmp boundary while Rust
  owns every persistent host and worker resource;
- `ring`'s bounded C and assembly implementation under its Rust API;
- generated C AOT artifacts and the C compiler, archiver, and linker needed to
  consume them;
- operating-system libraries, GPU drivers, and platform SDKs selected by Rust
  crates and the final linker.

The release notices describe the exact third-party source carried by a host.
Software Vulkan used by CI is external test infrastructure, not the production
GPU ownership layer.

## Release support matrix

The official release workflow builds these compiler hosts and catalog stubs:

| Public target | Release archive | Compiler pack | Rust build ABI |
| --- | --- | --- | --- |
| `x86_64-unknown-linux-gnu` | `nupp-linux-x86_64.tar.gz` | bundled and separately published | native Linux GNU |
| `aarch64-apple-darwin` | `nupp-macos-arm64.tar.gz` | none; native source builds use local Xcode tools | native Apple Darwin |
| `x86_64-pc-windows-msvc` | `nupp-windows-x86_64.zip` | bundled and separately published | `x86_64-pc-windows-gnu` internally |

The Windows names describe two different contracts. Nupp-generated C and AOT
artifacts use the public `x86_64-pc-windows-msvc` target spelling and layout.
The Nupp host itself embeds a LuaJIT built by its GNU make and MinGW toolchain,
so its Rust objects must use
the ABI-compatible `x86_64-pc-windows-gnu` Rust host. A Windows source checkout
therefore needs the exact GNU Rust toolchain named in
[`installation.md`](../learn/getting-started/installation.md#requirements);
the toolchain driver refuses an MSVC-hosted Rust compiler instead of mixing the
two object ABIs.

The release workflow also publishes the browser runtime separately. Browser
Lua and WebGPU use their own portable host and do not turn the desktop host
matrix into a browser support promise.

### Verification ownership

The compiler CI matrix runs the Nupp suite on Linux x86-64, macOS arm64, and
Windows x86-64. Before that broad suite, each runner executes the Rust resource
stress and cancellation tests, crosses the aggregate C ABI, and links and runs
the production executable host, static application archive, and static and
dynamic embedding SDKs. Release builders repeat that artifact gate on the
runner whose output they package because a separate compiler workflow cannot
be a dependency of a tagged release. They then stamp, package, unpack, and run
the matching compiler hosts. Linux and Windows jobs also poison ambient native
compiler names and require their authenticated compiler packs to build and run
a standalone C FFI plus AOT fixture. Cross-target jobs stamp all three public
targets and execute each result on its matching runner.

Those workflows are the platform gates; their presence alone is not evidence
that a particular commit completed them. The Rust-host cutover is exercised on
the retained Linux, macOS, and Windows runners, including the executable host,
static application host, static and dynamic embedding SDKs, workers, appended
compiler payloads, unpacked release artifacts, and byte-identical compiler and
binary packaging fixpoints. The Windows gate also exercises the DirectX 12 WGPU
adapter rather than relying only on the cross-platform software adapter.

## Migration breaks

The Rust-native cutover intentionally did not preserve every old native API or
artifact:

- The legacy provider ABI and its C implementation were removed. The compiler
  and runtime now select the version-2 Rust provider only.
- The production C host under `host/c` was removed. The executable,
  application archive, embedding SDK, payload loader, and worker core are Rust.
  The C embedding header remains, so existing hosts migrate at the SDK boundary
  rather than by embedding Rust types.
- SDL GPU, SPIRV-Cross, MSL artifacts, and the SDL provider ABI were removed.
  Native GPU builds accept canonical SPIR-V and execute it through WGPU.
- Curl and ada were removed. URI behavior follows Rust's WHATWG `url` contract,
  and HTTP follows the documented Reqwest contract rather than curl parity.
- Libuv and mbedTLS were removed. Tokio owns network resources and Rustls owns
  ordinary TLS over those resources. DTLS, kTLS, the old public session-ID and
  ticket-key controls, and Windows named-pipe emulation of Unix path streams
  are not part of the retained contract.
- File and process resources moved behind Rust ownership. Cancellation and
  close semantics preserve the accepted Nupp state machines, but undocumented
  C handles and backend functions are not compatibility surfaces.

Code which used public Nupp modules should migrate to their current documented
contracts. Code which loaded a provider directly, relied on SDL or curl
behavior, or linked files from the deleted C host must move to the compiler-
selected provider or the public embedding SDK. There is no compatibility mode
which restores the old ownership model.

::: seealso
- [Distribution](distribution.md) for stubs, payloads, signing, and compiler packs
- [Embedding Nupp](../learn/projects/embedding.md) for the public C SDK
- [Building projects](../learn/projects/build.md) for standalone and sidecar native artifacts
- [Native GPU AOT](../learn/performance/ahead-of-time/gpu.md) for the WGPU contract
:::
