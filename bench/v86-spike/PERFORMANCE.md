# Compiler performance and delivery follow-up

Branch-only measurements. No production compiler, runtime, or playground changes.
The compiler can complete the larger corpus in a 128 MiB guest after selecting
native bit operations. For this compiler workload, disabling LuaJIT's JIT is
faster still. The game runtime retains its JIT.

## Compiler findings

The original timeout was inside the first `browser-platform.nupp` compilation,
not simply the cumulative cost of repeating the test three times. The 128 MiB
scalar-bit probe eventually received a Linux OOM kill. That negative result is
retained in `results/performance/compiler-phases.json`.

The bundle detects LuaJIT's `bit` module, but its `nupp.runtime.bitops` facade
still selects the scalar provider in this portable build. Compiler hashing
therefore executes bit-by-bit arithmetic. A native-host diagnostic attributed
3,321 ms to 104 SHA-256 calls; selecting the native facade reduced those calls
to 74 ms in the corresponding diagnostic. These sampled host runs explain the
candidate; they are not the browser comparison.

The experiment sets `package.loaded["nupp.runtime.bitops"] = require("bit")`
before loading the unchanged compiler bundle. The follow-up compares ordinary
LuaJIT JIT-on and JIT-off execution with that same selection. This is adapter
configuration, not a LuaJIT patch. Production integration should select the
provider through the supported service setup.

The browser comparison uses two alternating fresh-Chrome runs per backend and
three rounds per retained compiler session. Each round checks typed source,
compiles both dialect cases, hovers, compiles the standard-library platform and
WebGPU examples, and checks the JSON request path. All generated code and
diagnostics match the native oracle and the current Lua 5.1 Wasm host; hash
known answers pass. The host-only forbidden-module tracking check is omitted,
as in the earlier memory probe. The same source is repeated in the warm rounds;
this is not an editing stress test or a full compiler suite.

| Backend | Boot + bundle load | First corpus requests | First platform compile | Repeated platform compile |
| --- | ---: | ---: | ---: | ---: |
| Existing Lua 5.1 / Wasm | 74 ms | 28.02 s | 23.41 s | 2.25 ms |
| v86 / LuaJIT, native bit, JIT on | 1.35 s | 22.02 s | 18.53 s | 62.0 ms |
| v86 / LuaJIT, native bit, JIT off | 1.33 s | 9.15 s | 6.27 s | 16.1 ms |

Request timings exclude guest boot, bundle loading, and serial progress
messages. Lua 5.1 requests include its existing JSON ABI. v86 uses the parent
browser's clock, refreshed between execution slices; very short timings are
coarse, and a reported zero does not mean a free operation. Phase diagnostics
are inclusive and nested, so their totals must not be added together. The
table uses unprofiled runs. Two pairs are exploratory evidence, not a confidence
interval or a claim about every program.

Retaining the environment avoids checking the imported declarations again.
JIT compilation overhead hurts this branch-heavy compiler corpus, including
its short repeated requests. Turning it off does not turn off FFI, native
`bit`, or the other LuaJIT libraries. This choice is independent of the game
runtime, where JIT-generated code remains enabled.

## Delivery findings

The 10,068,480-byte pinned kernel contains a second filesystem inside its ELF
image: 6,261,511 compressed bytes, a 15,133,184-byte CPIO archive, and 453 entries.
It includes Fortran/C++ libraries, a text browser, tcpdump, an editor, and v86
test programs. Nupp's own separate initramfs already supplies its guest tools
and libraries.

`probe-kernel.py` makes a diagnostic candidate with an empty embedded archive.
It preserves all ELF addresses, sizes, and the original bzImage extent, using
gzip filename padding to preserve safe in-place decompression. It is **not a
source-built minimal kernel**. The resulting file is still 10,068,480 bytes
before HTTP encoding, but its Brotli body is only 3,819,183 bytes. A product
should build a kernel from source with an empty `CONFIG_INITRAMFS_SOURCE`.

The measured game asset closure uses the 64 MiB application guest. Every visit
runs the same simulation, input, audio, and Canvas assertions. HTTP compression
alone helps the emulator core much more than the already compressed original
kernel. Compression plus the empty embedded archive cuts transferred bodies
by approximately 60%:

| Game delivery | Cold body bytes | Local first frame | Modeled 10 Mbps first frame |
| --- | ---: | ---: | ---: |
| Original, no HTTP encoding | 14,625,003 | 1.34 s | 14.09 s |
| Original, Brotli when smaller | 12,108,927 | 1.37 s | 12.00 s |
| Empty embedded filesystem, Brotli when smaller | 5,868,658 | 1.21 s | 6.64 s |

The separate compiler fixture's corresponding asset inventory is 7,355,499
encoded bytes. This is an inventory, not a network capture or the complete
playground frontend. It includes its own compiler-bearing initramfs. These
experiment profiles have separate URL trees: loading both cold can transfer
both sets. Sharing identical asset URLs and splitting the common guest image
from its compiler overlay could remove duplication, but is not implemented or
counted as a further saving here.

Local figures are medians of two alternating pairs. The rate model is one
illustrative pair: a shared 1,250,000-byte/second body budget and 80 ms delay
before each response. This is a localhost server model, not a measured WAN or
a full TCP network simulator. Counts include completed HTTP bodies and exclude
protocol headers. The emulator core is unchanged.

With immutable HTTP caching, a fresh Chrome process reusing the same disk
cache fetches zero bytes of those assets. This still boots a fresh VM: the
local cached visits take roughly 1.7–1.9 seconds to first frame. Caching removes
the transfer, not VM startup. The original no-store server transfers everything
again. No warmed VM snapshot or prechecked compiler image is used.

## Implication

There are concrete improvements available without rewriting LuaJIT: native bit
provider selection, JIT-off for the compiler VM, session reuse, HTTP compression
and caching, and removing the unrelated filesystem. The larger compiler corpus
now passes at 128 MiB. Cold imports still take seconds; the existing Lua 5.1
backend remains much faster for warm editor requests. This supports continuing
the backend experiment, not retiring the portable backend yet.

The next compiler experiment would cache or precompute the checked library
declarations, with invalidation and semantic equivalence tests. The next
delivery implementation would reproduce the smaller kernel from source. Neither
is implemented or included in these numbers. Safari, Firefox, mobile, arbitrary
native libraries, and complete playground integration remain outside this probe.

## Reproduction

First prepare the original spike, its 128 MiB compiler profile and 64 MiB
runtime-only profile as described in [README.md](README.md). Then:

```sh
./scripts/prelude-image
/opt/homebrew/bin/python3 bench/v86-spike/prepare-memory.py 128
/opt/homebrew/bin/python3 bench/v86-spike/prepare-memory.py 64 --runtime-only
/opt/homebrew/bin/python3 bench/v86-spike/prepare-performance.py
LJ_PROBE=$(./scripts/toolchain luajit)/bin/luajit
"$LJ_PROBE" bench/v86-spike/compiler-native-probe.lua build/v86-spike/performance/native-profile.json
"$LJ_PROBE" bench/v86-spike/compiler-native-probe.lua build/v86-spike/performance/native-bit-profile.json native-bit
/opt/homebrew/bin/python3 bench/v86-spike/probe-kernel.py
/opt/homebrew/bin/python3 bench/v86-spike/prepare-performance.py
DIGEST_PROBE=$(shasum -a 256 build/playground/nupp-compiler.lua | cut -d ' ' -f 1)
EMSDK_PYTHON=/opt/homebrew/bin/python3 ./editors/playground/tools/build-wasm-host.sh "$DIGEST_PROBE" build/v86-spike/performance/web/nupp-playground.mjs /private/tmp/nupp-portable-compiler/lua-5.1.5/src
```

Serve in separate terminals:

```sh
node bench/qemu-wasm-spike/serve.mjs build/v86-spike/performance/web 8102
node bench/v86-spike/delivery-server.mjs 8103
DELIVERY_RATE=1250000 DELIVERY_DELAY_MS=80 node bench/v86-spike/delivery-server.mjs 8105
```

Run sequentially to avoid competing benchmark workloads:

```sh
COMPILER_PAIRS=2 node bench/v86-spike/probe-compiler.mjs
DELIVERY_PAIRS=2 node bench/v86-spike/probe-delivery.mjs http://127.0.0.1:8103 local
DELIVERY_PAIRS=1 node bench/v86-spike/probe-delivery.mjs http://127.0.0.1:8105 10mbps
node bench/v86-spike/inventory-delivery.mjs
```

The standalone phase and native-bit diagnostic URLs are
`integration.html?mode=compiler&phases` and
`integration.html?mode=compiler&phases&native-bit` on port 8102. The former is
expected to fail with guest OOM. Retained measurements, methods, exact hashes,
and the source revision are under [results/performance](results/performance).
