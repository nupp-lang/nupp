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

No libcurl, OpenSSL, zlib or wgpu wrapper is introduced. The production C knows
no Nupp values, signatures, heap layout, task objects or HTTP/TLS policy.
Thread workers receive copied bytes and descriptors and never call Nupp.
The loop owner alone calls `uv_run`, with `UV_RUN_ONCE` for waiting and
`UV_RUN_NOWAIT` for a nonblocking turn. It refuses recursive entry. Native file
queues hold at most 256 requests and 128 MiB of copied buffers; Nupp retains
its existing entry resource budget. Cancellation before native submission spends
the ticket; afterward it returns zero and must be collected or settled.
Active reads and writes hold a close-on-exec duplicate through the callback.
If Nupp closes a descriptor first, the close path captures any queued work
before the descriptor number can be reused.

`pollcalls.close` retires an opaque subscription, never an OS descriptor.
Nupp journals poller ownership separately from files and drains native requests
before closing watchers, then files. `uv_close` callbacks release handle storage
and owned compatibility descriptors. The bootstrap's final shutdown drains all
remaining native callbacks before unmapping the entry; the pinned shared library
remains linked throughout. If an adapter still owns a live handle, shutdown
refuses and the standalone process exits with the entry still mapped.

Current macOS `posix_spawn` process groups/reaping remain unchanged: a process
exit filter descriptor is watched through the shared libuv loop. This limited
compatibility path ends with the dedicated `uv_spawn` migration. Later process,
socket, DNS and curl adapters must reuse this owned loop and preserve Nupp's
normal completion/delivery boundary. No frozen VM, browser or Tokio caller is
migrated by this transport change.

Native adapters borrow `nupp_uv_loop()` from `reactor.h` on the owning thread;
they do not create or drive another loop. They must retire their native handles
and requests before final shutdown. Nupp uses `hostuv.nupp` and the existing six
pool imports, with `servicescope.pollOpen/pollClose` as the concrete poller owner.
`pollClose` returns zero only after withdrawal and close-callback drain, or a
negative error without consuming the journal owner. It never spends file jobs.
`nupp_io_cancel` returns one only for an unsubmitted, spent ticket; zero always
requires `take` plus `finish`, or `nupp_io_settle`. Settlement drives the owner
loop until that request's callback/cleanup, spends its ticket and transfers the
open result descriptor to its caller. Scope cleanup closes that descriptor.
Read settlement discards its copied bytes. Native jobs remain counted until
finish/settle even after their language waiter has canceled.

`scripts/core-bridge --test` builds using the C compiler and pinned libuv SDK.
Its tests reject malformed packets, calibrate executable-memory and AAPCS64
guards, and exercise queued cancellation, active-work draining, stale tickets
and independent completion queues. Full Nupp fixture acceptance is separate
from these native contract tests.
