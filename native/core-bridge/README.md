# C startup transport

This is an independently testable replacement for the ARM64 Rust transport,
not a second runtime. The existing Rust path remains the reference until the
coordinated runtime switch. `NUPP_CORE_TRANSPORT=c` selects this transport in
the core guest runner; every ordinary ABI, scratch, normal and spill check
still runs. Unsupported hosts fail explicitly.

## Function and caller audit

| Existing Rust function family | Disposition and caller |
| --- | --- |
| `main::{header,input,execute,run,main}` | `main.c` reads the versioned opaque packet, maps its initial regions and enters Nupp. These operations precede any running Nupp code. |
| `platform::{supported,page_size,rounded,map_pages,unmap_pages}` and `Mapping::{new,copy,executable,drop}`, `flush` | Only initial mappings, W^X and instruction-cache synchronization remain in `main.c`. Subsequent guest memory uses Nupp's direct OS declarations, not exported C mapping helpers. |
| `library::{for_artifact,ArtifactOrigin::drop,open,imports}` | C publishes immutable startup directory metadata plus the OS `dlopen`, `dlsym`, `dlclose` addresses and an empty symbol table. `guestforeign.nupp` constructs artifact-relative paths and owns symbol resolution. It preserves the frozen Rust transport's anchoring until that transport is retired. |
| `pool::{failed,last,retried,perform,wake_pipe,work,started,pool_start}` | `io.c` supplies a raw pthread entry and copied-buffer OS work. Foreign threads cannot enter managed Nupp today, so this primitive cannot yet be written as a Nupp callback. It handles only `open`, `read`, `write`, their errno values, and a readiness pipe. |
| `pool::{pool_submit,pool_take,pool_finish,pool_settle,pool_cancel}` | The same six import positions serve `compiler/vm/nativeos.nupp`. Nupp's `guestreactor.nupp`, `servicescope.nupp` and reactor own admission, deadlines, resource accounting, cancellation and draining. C tickets identify outstanding copied OS jobs and never expose managed pointers. Remove this primitive when checked foreign-thread entry can replace it. |
| Rust `#[cfg(test)]` guards and fixtures | `guard.c`, `tests/core/bridge-contracts.c` and `bridge-abi-aarch64.S` are test-only. Rust-only specialized shared-memory guards remain on the reference path until their corresponding migration acceptance runs. |

No libcurl, OpenSSL, zlib or wgpu wrapper is introduced. The production C knows
no Nupp values, signatures, heap layout, task objects or HTTP/TLS policy.
Thread workers receive copied bytes and descriptors and never call Nupp.

`scripts/core-bridge --test` builds using only the C compiler and pthreads.
Its tests reject malformed packets, calibrate executable-memory and AAPCS64
guards, and exercise queued cancellation, active-work draining, stale tickets
and independent completion queues. Full Nupp fixture acceptance is separate
from these native contract tests.
