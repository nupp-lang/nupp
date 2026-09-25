# Native I/O benchmark

This is the public-boundary performance and bounded-resource fixture for the
Rust-native network, HTTP, TLS and process providers. It measures public Nupp
streams, clients, sessions and child pipes; it does not compare those wrappers
with raw Tokio, Reqwest, rustls or operating-system handles.

The benchmark uses loopback Node HTTP, TCP and TLS peers outside the measured
request intervals. Nine measured samples follow two warmups, and the reported
value is their median. Run the steady-state measurements with:

```sh
bench/native-runtime/run.sh
```

The ordinary run keeps the established string API cases. Compare those with
the direct `readSpan`, `readInto`, `writeSpan`, split-stream and HTTP body paths
at 64 B, 1 KiB, 64 KiB, 1 MiB and 16 MiB with:

```sh
bench/native-runtime/run.sh copy-reduction
```

Each line is the median of five samples after one warmup. The string and direct
cases run in the same executable against the same loopback peer; compare whole
revisions in independent processes when deciding whether a change is retained.

Older revisions without every direct API can run the compatible subset:

```sh
bench/native-runtime/run.sh copy-reduction-compatible
```

The narrower modes isolate allocation accounting and the datagram, process,
and TLS paths:

```sh
bench/native-runtime/run.sh copy-allocation
bench/native-runtime/run.sh copy-datagram
bench/native-runtime/run.sh copy-process
bench/native-runtime/run.sh copy-tls
```

`copy-allocation` reports Lua allocation deltas. Native allocation attribution
requires feature-gated counters in the relevant Rust provider; process-wide
allocator totals include LuaJIT and the host and are not treated as proof of a
specific provider allocation.

Run the bounded-resource RSS probes with:

```sh
bench/native-runtime/resource.sh
```

The resource script polls the benchmark process during a complete load run and
reports its peak RSS, then samples each adversarial process after one, three,
and five seconds. `net-slow-reader` repeatedly writes the same 64 KiB value
through a public Nupp TCP stream whose `sendHighWater` is 64 KiB while its peer
reads nothing. Once the platform and provider queues fill, the write waits for
room instead of retaining more copies. `net-slow-writer` reads through a public
Nupp TCP reader while a Node peer emits 1 KiB every 100 milliseconds, keeping the
connection active without allowing an eager receive buffer to accumulate.
`http-slow-reader` holds an unread 256 MiB response whose Node sender honors
transport backpressure.
`http-slow-writer` consumes a response produced in 1 KiB increments with a
delay between writes, keeping a native response open without presenting a body
that can be buffered eagerly. The processes are stopped after the final sample;
a plateau rather than the absolute RSS demonstrates bounded buffering. The RSS
plateau is the portable allocation signal: process-wide allocation counters
cannot attribute allocations among LuaJIT, the host, and the Rust provider.

The benchmark reports its native operating-system PID before beginning work.
This matters under Git Bash, where both `$!` and the MSYS C runtime's `_getpid`
identify the process within MSYS rather than by the stable Win32 PID expected by
system tools. On Windows one PowerShell harness launches and retains the native
process object, verifies that its ID matches the benchmark's
`GetCurrentProcessId` report, and reads `WorkingSet64` directly from that object.
It does not repeatedly start PowerShell or rediscover the child by PID while a
short benchmark is running. On Unix the shell owns the child, verifies its
reported `getpid()` PID, and reads RSS through `ps`. Both report KiB for the
benchmark process alone, and a mismatched PID or missing RSS sample fails the
run rather than producing an empty or zero observation.

Run on an otherwise quiet machine. Record the Nupp revision, operating system,
hardware, Rust version, benchmark output, and resource samples. Linux and
Windows are separate platform runs rather than results inferred from macOS.
