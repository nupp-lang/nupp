# QEMU-Wasm / LuaJIT spike

**The compatibility route works:** an unmodified LuaJIT runs Nupp's existing
`luajit` output in Chrome, generates x86-64 machine code, loads a guest C shared
library, and passes the FFI, `bit`, and `string.buffer` checks. This experiment
adds no production backend or playground changes.

The execution path is:

```text
Nupp source → generated Lua → Linux x86-64 LuaJIT → QEMU-Wasm → Chrome
```

LuaJIT is cross-compiled from the revision in `assets.lock.json`, which matches
Nupp's toolchain pin at the time of the experiment. QEMU itself is a downloaded,
prebuilt Wasm executable from the pinned upstream demo image. This spike does
not rebuild QEMU or compile LuaJIT directly to Wasm.

## Run it

The tested build host is macOS arm64, with Apple clang, Python 3.9+, Node 22+,
Google Chrome, and Emscripten's LLVM tools installed through Homebrew. The build
uses Apple clang for its Linux x86-64 target and LLVM's `lld` and `llvm-ar`;
it does not invoke `emcc`. Set `LLVM_TOOLS` to override
`/opt/homebrew/opt/emscripten/libexec/llvm/bin`.

From the repository root:

```sh
python3 bench/qemu-wasm-spike/prepare.py
node bench/qemu-wasm-spike/serve.mjs
```

Open <http://127.0.0.1:8097/> in Chrome, or in another terminal run:

```sh
node bench/qemu-wasm-spike/run-browser.mjs \
  http://127.0.0.1:8097/ build/qemu-wasm-spike/compatibility.json
python3 bench/qemu-wasm-spike/native-baseline.py
```

Preparation downloads checksum-pinned dependencies into the ignored
`build/qemu-wasm-spike` directory, builds Linux LuaJIT and the FFI test library,
compiles the Nupp workload, and packs a minimal initramfs. Subsequent preparation
reuses verified downloads. No Linux VM, Docker, npm install, or root filesystem
disk image is required. Paths containing spaces are not supported by this
experimental cross-build wrapper.

The local server supplies the COOP/COEP headers required for shared Wasm memory.
The browser runner uses its own temporary Chrome profile, verifies every expected
check and the guest exit status, saves JSON, and exits nonzero on failure. Allow
about a minute: most of that time is the intentionally slow JIT-disabled test.
`CHROME` overrides the browser executable; `SPIKE_TIMEOUT_MS` defaults to 240000.
The native comparison writes `build/qemu-wasm-spike/native.txt` and requires the
same LuaJIT revision as the guest.

## What passed

- LuaJIT trace creation, including a nonempty machine-code buffer.
- FFI arrays, pointers, exact 64-bit integers, libc calls, and C varargs.
- `ffi.load` of a separately compiled Linux x86-64 `.so`, plus C-to-Lua callbacks.
- `bit.band`, `bit.rol`, and `bit.bxor`.
- `string.buffer` put/get with embedded NUL, reserve/commit, and serialization.
- Actual Nupp compilation of an FFI-backed `Particle` struct, with identical
  results for one million updates with the JIT both enabled and disabled.

This covers selected operations, not every FFI ABI or LuaJIT feature. FFI calls
guest libraries; it does not directly call host macOS libraries, JavaScript, or
arbitrary Wasm exports. Rendering, audio, input, a host bridge, the complete Nupp
stdlib, and running the Nupp compiler inside the browser were not tested.

## Recorded measurements

See [results/browser.json](results/browser.json) and
[results/native.txt](results/native.txt) for the samples and compatibility output.
The measurements below are from an Apple M5 Pro, Chrome 152, and LuaJIT
2.1.1785763465. Both runtimes execute the same generated Lua workload.

| Median per 1,000,000 updates | First run | Clean rebuild run |
| --- | ---: | ---: |
| Native LuaJIT, JIT enabled | 0.513 ms | 0.501 ms |
| QEMU-Wasm guest, JIT enabled | 9.555 ms | 14.800 ms |
| Native LuaJIT, JIT disabled | 48.309 ms | 41.731 ms |
| QEMU-Wasm guest, JIT disabled | 5,341.645 ms | 7,945.788 ms |
| Guest ready after page initialization | 6.623 s | 9.304 s |

The enabled JIT was approximately **19–30× slower than native** for this loop,
while remaining over 500× faster than interpreting it inside this QEMU build.
The variation between runs is another reason not to generalize these timings.
The first run's retained samples are in [results/initial-timing.json](results/initial-timing.json);
[results/environment.json](results/environment.json) records the hardware and source pin.
The final run passed all 11 checks with zero captured browser errors and fetched
54,537,277 bytes of resource bodies (52.0 MiB,
excluding the small initial HTML document).

The timing experiment uses five warmups followed by five samples in one process
for each JIT setting. The workload repeatedly adds `0.5` to one struct field;
LuaJIT can optimize that loop heavily. These are exploratory measurements,
not a general game benchmark, a paired multi-process comparison, or a confidence
interval. Native arm64 and emulated x86-64 also differ in architecture.

The Wasm binary imports shared memory with minimum and maximum both 36,800 pages:
**2,411,724,800 bytes (2,300 MiB)**, while QEMU's guest RAM is set to 256 MiB.
The larger figure is the required Wasm address space, not a measured resident
memory footprint. Lowering the guest RAM argument does not remove that import
requirement. Reducing it requires a different QEMU build.

The approximately 52 MiB payload is measured without HTTP compression. The
upstream demo's large rootfs disk is not fetched by this page. Startup was measured
with a fresh browser profile against localhost; it excludes Internet latency.
Other browsers and mobile devices have not been tested.

## Guest setup and distribution boundary

The guest contains a minimal BusyBox init, musl, LuaJIT, and test files. Linux
starts `/init` directly, with networking disabled. Fresh browser Web Crypto
bytes are appended in a per-boot initramfs overlay and credited to the guest
entropy pool before LuaJIT starts. Without this, LuaJIT can wait for Linux's
random generator to initialize. LuaJIT itself is not patched.

The default QEMU CPU works. `-cpu max` caused this prebuilt kernel to panic;
the experiment retains the default. An early 9p filesystem route also rejected
`chmod`; the final experiment uses the initramfs for its guest files.

All downloaded assets are pinned by URL and SHA-256 in `assets.lock.json`.
The QEMU binary comes from
[qemu-wasm-demo-images](https://github.com/ktock/qemu-wasm-demo-images/tree/b7c549b5e6f4c376f76483a03e983214421434ad),
using the [QEMU-Wasm](https://github.com/ktock/qemu-wasm) project. Pinning the
binary bytes does not establish its exact corresponding source/build provenance.

This is a local engineering spike, not a redistribution-ready runtime package.
Before publishing an export, resolve source and notice requirements for the
specific QEMU, Linux, BusyBox, firmware, and runtime binaries. The generated
[license page](licenses.html) records this boundary and includes the LuaJIT and
xterm-pty notices. No third-party binaries are committed in this directory.

The result supports preserving existing LuaJIT functionality through emulation.
The current memory requirement, payload, startup, and measured execution cost
make this build a poor default for browser games; a smaller QEMU build and a
representative game with a browser bridge would be the next separate experiment.
