# C startup transport

This is the native core's only startup transport, not a second runtime. It
replaced the ARM64 Rust bridge, which has been deleted. The core guest and unit
runners build it with `scripts/core-bridge`; every ABI, scratch, normal and
spill check runs against it. Unsupported hosts fail explicitly.

## Function and caller audit

| Former Rust function family | Disposition and caller |
| --- | --- |
| `main::{header,input,execute,run,main}` | `main.c` reads the versioned opaque packet, maps its initial regions and enters Nupp. These operations precede any running Nupp code. |
| `platform::{supported,page_size,rounded,map_pages,unmap_pages}` and `Mapping::{new,copy,executable,drop}`, `flush` | Only initial mappings, W^X and instruction-cache synchronization remain in `main.c`. Subsequent guest memory uses Nupp's direct OS declarations, not exported C mapping helpers. |
| `library::{for_artifact,ArtifactOrigin::drop,open,imports}` | C publishes immutable startup directory metadata plus the OS `dlopen`, `dlsym`, `dlclose` addresses and an empty symbol table. `guestforeign.nupp` constructs artifact-relative paths and owns symbol resolution. It preserves the retired Rust transport's anchoring. |
| `pool::{failed,last,retried,perform,wake_pipe,work,started,pool_start}` | `uv.c` replaces the owned pthread pool with `uv_fs_open/read/write`. A native callback records a result and signals the coalescing wake pipe. Managed Nupp callback entry is unavailable here; no worker or callback enters Nupp. |
| `pool::{pool_submit,pool_take,pool_finish,pool_settle,pool_cancel}` | The same six imports serve `compiler/vm/nativeos.nupp`. Nupp owns resource journals, deadlines, cancellation and draining. Native tickets and copied buffers stay live through `uv_fs_req_cleanup` and collection; successful `uv_cancel` still requires its callback. |
| readiness callbacks | `reactor.h` is the internal shared-loop boundary: opaque subscriptions multiplex one `uv_poll_t` per descriptor on one thread-owned loop. Nupp keeps delivery and scheduler policy. These callbacks only queue readiness; Nupp's checked FFI cannot currently supply this raw callback entry. |
| Rust `#[cfg(test)]` guards and fixtures | `guard.c`, `tests/core/bridgecontracts.c` and `bridgeabi.S` are test-only. The Rust-only shared-memory fault guards were never selected by a runner and were deleted with the crate. |

The macOS ARM64 build links the libcurl transport and the selected SDK ICU
stub at a macOS 11.0 deployment floor. Linux ARM64 builds the C bridge with
libuv. HTTP and URI adapter support is limited to the macOS ARM64 core.
The native callbacks work on copied bytes and descriptors. Nupp owns the
managed task and HTTP policy.

`scripts/core-bridge --test` uses the same pinned native libraries as the
bridge. Its tests reject malformed packets, calibrate executable-memory and AAPCS64
guards, and exercise queued cancellation, active-work draining, stale tickets
and independent completion queues. Full Nupp fixture acceptance is separate
from these native contract tests.
