# Startup follow-up

Branch-only experiment; no production backend or playground changes.

The useful change is a reusable Linux snapshot captured immediately before
LuaJIT starts. A fresh launch restores the kernel and guest files, supplies
new application code, configuration, browser entropy and wall-clock time,
then starts the unchanged LuaJIT executable. It does not clone a running game
or move game initialization outside the timer.

## Measurements

The comparison uses the same 64 MiB guest and interactive game as
[PERFORMANCE.md](PERFORMANCE.md), with the diagnostic kernel whose embedded
filesystem was removed. Each variant has three cold/cache pairs in alternating
order, using fresh Chrome processes. Every run checks the simulation checksum,
120 rendered frames, mouse and keyboard input, Canvas output, and audio.

| Variant | Cold asset bodies | Modeled 10 Mbps first frame | Cached first frame |
| --- | ---: | ---: | ---: |
| Current loader, smaller kernel | 5.87 MB | 6.75 s | 1.19 s |
| Parallel loading | 5.87 MB | 6.47 s | 1.15 s |
| Parallel + HTTP-compressed CPIO | 5.80 MB | 6.30 s | 1.07 s |
| Pre-LuaJIT snapshot | 5.79 MB | 5.52 s | 0.27 s |
| Snapshot + bundled worker | 5.79 MB | 5.41 s | 0.27 s |
| Same bundled snapshot, Brotli 11 | **5.19 MB** | **4.88 s** | **0.28 s** |

Values are medians; MB is decimal. The first five rows use Brotli quality 9
and alternating variant order. Quality 11 is a separate three-pair follow-up
over the identical snapshot. Its cold runs range from 4.86 to 4.89 seconds.
Warm rendering remains approximately 60 FPS. This is an improvement for this
fixture: about 28% lower modeled cold startup and 77% lower cached startup,
with 12% fewer transferred bytes. The current-loader result is close to the
previous 6.64-second measurement, now with three repetitions and corrected
driver timing.

Including page loading, the modeled median from navigation to first frame
falls from **7.13 s to 5.25 s**. The stronger-compression cached median from
navigation is **0.29 s**. The earlier first-frame metric is retained for a
consistent comparison; the broader metric is not hidden.

The corrected cached baseline spends a median 1,008 ms booting Linux, versus
about 2 ms instantiating the emulator Wasm. The snapshot reaches the guest-ready
marker about 93 ms after launch, then spends another roughly 180 ms starting
the LuaJIT bridge, loading the application and reaching its first frame. Wasm
instantiation is not the bottleneck here.

`firstFrameMs` retains the earlier experiment's definition: from calling
`startGuest` to the first rendered frame. It excludes the initial HTML and
page-module loading. `navigationToFirstFrameMs` includes that earlier loading
and is retained separately in the results. Neither includes launching the
Chrome application itself. The link model shares 1,250,000 body bytes/second
across requests and delays each response by 80 ms; it is not a TCP/WAN simulator.
Payload totals include the page assets even when their loading precedes the
`firstFrameMs` timer. All cached visits transfer zero measured asset-body bytes.

The earlier cached figures included an intermittent roughly 500 ms delay
before the worker's first instruction. Bundling the worker did not remove it.
Attaching the Chrome driver before navigating, instead of during page startup,
removed that delay in the follow-up. The original and corrected measurements
are both retained. The old 1–2 second figure should not all be attributed to
VM startup.

These are exploratory desktop-Chrome measurements, not confidence intervals
or results for Safari, Firefox, mobile devices, or the playground compiler.

## What changed

- `serial` preserves the previous asset-loading dependencies.
- `parallel` fetches the guest image, application, emulator Wasm, BIOS and
  kernel concurrently. It still boots Linux every time.
- `parallel-raw` also sends the uncompressed CPIO through HTTP Brotli, so the
  browser handles decompression instead of making Linux inflate a gzip image
  inside the emulator.
- `snapshot` restores the pre-LuaJIT state. It replaces kernel, BIOS and initrd
  downloads with the state file; the application remains a separate asset.
- `snapshot-bundled` additionally packages the same v86 JavaScript and worker
  into a single classic-worker asset, removing one dependent request.

The first snapshot contained stale boot data in Linux's free pages and cost
10,181,273 bytes with Brotli quality 9. The capture helper now temporarily
allocates and zeros free pages, leaving 1 MiB available, then releases them
before saving. It touches memory through Linux's allocator, not by guessing
which physical pages are safe to erase. This work happens when preparing the
reusable image, not on each browser visit.

The final state is 17,770,320 bytes before encoding and 5,243,187 bytes at
Brotli quality 9. It uses v86's ordinary save/restore API. Its contents are tied
to the pinned emulator, kernel, guest files and 64 MiB configuration; production
packaging needs a versioned image and matching asset URLs. Restoring also
requires a temporary decoded state buffer in JavaScript, in addition to the
guest's Wasm memory. This is not a reduction of resident-memory requirements.

Precompressing that same state at Brotli quality 11 reduces its body to
4,696,996 bytes. Compression is done before serving, so it is not in the browser
startup path. The complete quality-11 closure is measured separately.

The snapshot gate runs before host data arrives and before the LuaJIT process
exists. After restore it writes fresh app/config files, injects 32 browser
random bytes, forces Linux to reseed its random generator, and sets wall time.
The reseed uses the `RNDADDENTROPY` and `RNDRESEEDCRNG` operations defined by
[Linux's random driver](https://github.com/torvalds/linux/blob/v6.8/drivers/char/random.c#L1372-L1427).
Four independent restores check fresh app/config values, distinct entropy and
nonblocking `getrandom` output, current time, FFI, `bit`, `string.buffer` and
JIT availability. The native-module fixture also checks LPeg, Nupp-generated
C through FFI, dynamic compilation, bytecode reload, coroutine yielding and
retained allocations. Cancellation, failures and deadlines are checked separately.

## Remaining cost

The snapshot avoids booting Linux, but still carries a Linux runtime. The
remaining cold-load cost is predominantly transferring that image. Even at an
ideal 10 Mbps, the measured 5.19 MB of bodies alone takes 4.15 seconds. A kernel
built from source for this guest, with unnecessary subsystems removed, is the
next size experiment; this probe does not estimate or claim that saving.

Keeping an already running VM would avoid subsequent VM launches entirely,
but that is a different lifecycle from these fresh-process cached visits.
This experiment does not implement a retained playground VM, compiler snapshot,
automatic snapshot invalidation/fallback, or production deployment.

## Reproduce

First prepare the spike, its 64 MiB runtime profile and diagnostic kernel as in
[PERFORMANCE.md](PERFORMANCE.md). Then:

```sh
/opt/homebrew/bin/python3 bench/v86-spike/prepare-startup.py
node bench/v86-spike/build-snapshot.mjs
STARTUP_PROBE=1 node bench/v86-spike/delivery-server.mjs 8105
# In another terminal:
STARTUP_PROBE=1 DELIVERY_RATE=1250000 DELIVERY_DELAY_MS=80 node bench/v86-spike/delivery-server.mjs 8106
```

Run sequentially, not alongside other benchmarks:

```sh
SPIKE_NAVIGATE_AFTER_ATTACH=1 DELIVERY_VARIANTS=serial,parallel,parallel-raw,snapshot,snapshot-bundled DELIVERY_PAIRS=3 DELIVERY_OUTPUT=build/v86-spike/startup/controlled-local node bench/v86-spike/probe-delivery.mjs http://127.0.0.1:8105 local
SPIKE_NAVIGATE_AFTER_ATTACH=1 DELIVERY_VARIANTS=serial,parallel,parallel-raw,snapshot,snapshot-bundled DELIVERY_PAIRS=3 DELIVERY_OUTPUT=build/v86-spike/startup/controlled-10mbps node bench/v86-spike/probe-delivery.mjs http://127.0.0.1:8106 10mbps
SPIKE_NAVIGATE_AFTER_ATTACH=1 node bench/qemu-wasm-spike/run-browser.mjs http://127.0.0.1:8105/snapshot-bundled/check-startup.html build/v86-spike/startup/snapshot-check.json
SPIKE_NAVIGATE_AFTER_ATTACH=1 node bench/qemu-wasm-spike/run-browser.mjs 'http://127.0.0.1:8105/snapshot-bundled/integration.html?mode=lifecycle' build/v86-spike/startup/snapshot-lifecycle.json
node bench/v86-spike/record-startup.mjs controlled-local controlled-10mbps
```

For the stronger precompression candidate, serve only the bundled snapshot
with quality 11, then run the same cold/cache probe:

```sh
STARTUP_PROBE=1 DELIVERY_VARIANTS=snapshot-bundled DELIVERY_BROTLI_QUALITY=11 DELIVERY_RATE=1250000 DELIVERY_DELAY_MS=80 node bench/v86-spike/delivery-server.mjs 8107
SPIKE_NAVIGATE_AFTER_ATTACH=1 DELIVERY_VARIANTS=snapshot-bundled DELIVERY_PAIRS=3 DELIVERY_OUTPUT=build/v86-spike/startup/quality11-10mbps node bench/v86-spike/probe-delivery.mjs http://127.0.0.1:8107 quality11
node bench/v86-spike/record-startup.mjs controlled-local controlled-10mbps quality11-10mbps
```

Measurements, assertions and exact source/artifact hashes are retained under
[results/startup](results/startup). Generated VM images stay in ignored `build/`.
