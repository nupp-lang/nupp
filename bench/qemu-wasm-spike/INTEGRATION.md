# LuaJIT browser integration proof

The spike runs Nupp's LuaJIT output in a browser with a working host bridge.
It reuses the existing browser effect handlers and worker pool. LuaJIT itself
is unmodified. This is an experimental alternative runtime, not a shipped
replacement for the current Wasm backend.

## Result

All enumerated compatibility checks passed on an Apple M5 Pro running macOS
26.6 and Chrome 152. The route works for this browser application, including
native LuaJIT features and existing Nupp browser services. Its startup and
memory costs make this an expensive experimental backend.

Three alternating pairs of fresh Chrome launches ran the same 120-frame Nupp
simulation, with 32,768 struct updates per frame, the same Canvas handler,
mouse/keyboard input, and audio activation. Medians across the three runs:

| Measurement | QEMU / LuaJIT | Existing Lua 5.1 / Wasm |
| --- | ---: | ---: |
| First rendered frame | 7,710 ms | 37.7 ms |
| Average frame rate | 51.9 FPS | 45.7 FPS |
| Warm frame rate, discard first 30 intervals | 60.0 FPS | 48.0 FPS |
| Median frame interval | 16.67 ms | 20.85 ms |
| 95th percentile frame interval | 35.32 ms | 21.47 ms |

That is about 14% higher overall frame rate and 25% higher warm frame rate for
this workload, with worse startup and early frame stalls. The CPU-only loop's
43–67× speedup does not become a corresponding game-frame-rate improvement.
The warm QEMU result reaches the fixture's approximately 60 Hz animation cadence.
These are exploratory localhost measurements, not remote download timings or
a statistically established speedup across applications.

The audited root application assets total approximately **53 MiB uncompressed**;
the configured shared Wasm memory is **2,300 MiB per VM**. The Lua 5.1 host Wasm
alone is 322,280 bytes; that is not its entire application download. Asset counts,
hashes, exact samples, and a rendered screenshot are retained in
[results/integration](results/integration/):

- [Paired frame measurements](results/integration/comparison/summary.json)
  and [rendered game](results/integration/comparison/game.png).
- [LuaJIT/FFI features](results/integration/features.json),
  [C modules and CPU AOT](results/integration/native.json),
  [browser services and persistence](results/integration/services.json),
  [WebGPU](results/integration/gpu.json),
  [worker conformance](results/integration/workers.json), and
  [failure/cancellation](results/integration/lifecycle.json).
- [Build/run provenance](results/integration/provenance.json) and
  [asset sizes](results/integration/size-inventory.json).

## Tested boundary

| Capability | Exercise |
| --- | --- |
| LuaJIT | Real traces and machine code, JIT on/off result equivalence |
| FFI | Arrays, pointers, exact int64, libc, varargs, a Linux shared library, C/Lua callbacks |
| Runtime libraries | `bit`, `string.buffer`, reserve/commit, buffer serialization |
| C modules and dynamic code | Real LPeg 1.1.0, LuaJIT helper modules, `loadstring`, bytecode dump/reload, yielding through `pcall` |
| CPU AOT | Nupp-generated C kernel cross-compiled for guest Linux and called through FFI, checked against an independent formula |
| Host memory | Binary native-pointer transfers, writable copyback, read-only/stale/size rejection, release on error |
| Browser services | Timers, monotonic/wall clocks, entropy, SHA-256/HMAC known answers, system metadata |
| Persistence | IndexedDB including embedded NUL and Unicode, read after destroying and restarting the VM |
| HTTP | 294,912-byte binary upload/response, ordinary Nupp readers/buffers, timeout and response-size errors |
| WebGPU | Nupp-generated WGSL, resident buffers, upload, compute, synchronization, native-span readback; 1,024 checked results |
| Workers | Two independent Linux/LuaJIT VMs; fan-out, copied records, empty returns, errors, queue bounds, cancellation and deadlines |
| Browser interaction | Nupp simulation, Canvas pixels, actual CDP mouse/keyboard events, AudioContext activation and offline audio samples |
| Lifecycle | Guest errors reach JS; a CPU-bound guest can be terminated; host deadlines reject; VM restart |

The GPU fixture compiles WGSL with the existing compiler and explicitly loads
its artifact through the existing resident-GPU protocol. This does not add
automatic QEMU packaging to the normal `@aot` build target. Audio output is
validated by context state and offline samples; the test makes no claim about
sound reaching physical speakers.

## Implementation

`prepare.py` cross-builds the pinned Linux x86-64 LuaJIT and a small C bridge
library. It also stages the existing browser provider sources under an isolated
`nupp.qemu.browser` namespace: production restricts their original identities
to the `lua51` dialect. Their implementations are reused, with explicit service
selection and native FFI storage. The clock binding is adapted separately.

The application is bundled as LuaJIT code and precompiled with the matching
host LuaJIT to portable LuaJIT bytecode. The guest loads that bytecode. All
runtime machine-code generation remains LuaJIT's own implementation.

The guest reserves 64 MiB of its 256 MiB emulated RAM for bounded JSON and binary
mailboxes. Linux uses the other 192 MiB. An FFI mapping of `/dev/mem` exposes
the reserved region; the host identifies it using a fresh per-boot token in
QEMU's existing shared Wasm memory. Serial notifications and acknowledgments
coordinate turns. Guest pointers never become browser pointers: transfers are
copied through checked leases presented to the existing browser handler ABI.

The parent JS context publishes its monotonic clock as atomic integer
microseconds in that region. Guest reads use a tiny C function, without
suspending. Timers and storage/network operations still use browser effects.
The worker pool remains the existing production pool; each lane's execution
adapter boots an independent guest.

Three failures found by the integration checks dictated this design:

1. The downloaded QEMU's 9p server stalled on application-side writes. 9p now
   supplies only initial configuration/application reads; effects use RAM.
2. LuaJIT `require` cannot yield. Modules initialize synchronously and exported
   entry functions perform asynchronous work afterward.
3. An asynchronous `now()` recursed through task deadline readiness checks.
   Updating a shared clock inside the emulation Worker could also stall with
   the guest. The atomic clock writer now lives outside that Worker.

## Run

From the repository root on the documented macOS build host:

```sh
python3 bench/qemu-wasm-spike/prepare.py
node bench/qemu-wasm-spike/transport-tests.mjs
node bench/qemu-wasm-spike/serve.mjs
```

Open `http://127.0.0.1:8097/integration.html`. The links select each fixture.
For an automated run, the browser runner exits nonzero for any failed check:

```sh
node bench/qemu-wasm-spike/run-browser.mjs 'http://127.0.0.1:8097/integration.html?mode=services'
node bench/qemu-wasm-spike/run-browser.mjs 'http://127.0.0.1:8097/integration.html?mode=native'
SPIKE_GPU=1 node bench/qemu-wasm-spike/run-browser.mjs 'http://127.0.0.1:8097/integration.html?mode=gpu'
node bench/qemu-wasm-spike/run-browser.mjs 'http://127.0.0.1:8097/integration.html?mode=workers'
node bench/qemu-wasm-spike/run-browser.mjs 'http://127.0.0.1:8097/integration.html?mode=lifecycle'
node bench/qemu-wasm-spike/run-browser.mjs 'http://127.0.0.1:8097/integration.html?mode=game'
```

The original `/` page retains the CPU/FFI feature suite. `SPIKE_GPU=1` enables
WebGPU in the dedicated headless Chrome test profile; unavailable WebGPU fails
the test rather than being silently skipped. The game runner generates real
input events. When running manually, click the button and press the right arrow.

For the identical-source Lua 5.1 comparison, build the existing Emscripten host
using Lua 5.1.5 and LPeg 1.1.0 source directories:

```sh
python3 bench/qemu-wasm-spike/prepare-portable.py /path/to/lua-5.1.5/src /path/to/lpeg-1.1.0
node bench/qemu-wasm-spike/run-browser.mjs 'http://127.0.0.1:8097/integration.html?mode=game&portable'
node bench/qemu-wasm-spike/compare.mjs http://127.0.0.1:8097/ build/qemu-wasm-spike/comparison
```

Both routes compile `project/src/nupp/qemu/game.g.nupp`: 120 simulation frames,
32,768 struct updates per frame, identical numerical checks and browser frame
handler. This is a small interactive workload, not a complete commercial game.
The automated runner sets a 1000×900 viewport so the actual input button stays
visible. Both comparison routes use headless Chrome with GPU disabled; the
separate WebGPU fixture enables and checks the real adapter.

## Scope and costs

The downloaded QEMU still reserves **2,300 MiB of shared Wasm memory per VM**.
That is a configured address-space/backing-store size, not measured resident
memory. A page with two worker lanes creates three such memories. Startup and
frame-rate measurements belong to the exact pinned build and tested desktop;
they do not establish mobile viability or a general speedup.

This validates the enumerated integrations, not every LuaJIT ABI, every native
library, or the whole Nupp standard library. Guest libraries must be built for
Linux x86-64. Guest OS networking is disabled; browser HTTP uses Fetch. Browser
security restrictions remain. The compiler itself has not been run inside the
guest, and the playground/normal export command do not select this backend.
Only Chrome on the recorded macOS machine has been tested.

The existing [license/provenance boundary](licenses.html) still applies. This
local spike does not complete the corresponding-source package for distributing
the downloaded QEMU/Linux/BusyBox/firmware binaries.
