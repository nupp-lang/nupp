# Copy-reduction benchmark, 2026-09-25

This is the first paired measurement of the direct Buffer paths. Both runs use
the same benchmark source, an independent benchmark process, the same Node
loopback peer, five measured samples after one warmup, and medians. The
baseline is unchanged `635de296`; the candidate is the uncommitted
copy-reduction changes on top of `2a4198f0`.

Machine: Apple M5 Pro, 48 GiB, arm64 macOS 26.6 (Darwin 25.6.0)

Toolchain: `rustc 1.98.0 (88d9e12ae 2026-08-18)`

Command: `bench/native-runtime/run.sh copy-reduction-compatible`

```text
path                         bytes    baseline MiB/s    candidate MiB/s    ratio
network string                  64              1.10               1.47     1.34x
network buffer                  64              0.61               1.53     2.51x
HTTP string                     64              1.18               1.18     1.00x
HTTP buffer                     64              1.15               1.26     1.10x
network string                1024             29.71              38.87     1.31x
network buffer                1024             10.77              14.15     1.31x
HTTP string                   1024             18.51              17.96     0.97x
HTTP buffer                   1024             18.55              20.69     1.12x
network string               65536            712.59             714.29     1.00x
network buffer               65536            473.64             714.28     1.51x
HTTP string                  65536            982.19            1016.55     1.03x
HTTP buffer                  65536            695.76            1016.55     1.46x
network string             1048576            936.81            1530.71     1.63x
network buffer             1048576            584.74            1680.44     2.87x
HTTP string                1048576           5424.15            5399.17     1.00x
HTTP buffer                1048576           1735.96            7385.96     4.25x
network string            16777216           1017.97            2101.68     2.06x
network buffer            16777216            613.96            2080.92     3.39x
HTTP string               16777216           7837.69            6947.21     0.89x
HTTP buffer               16777216           1875.06           13541.15     7.22x
network split             16777216            621.93            2137.75     3.44x
```

The 1 KiB socket Buffer path is faster than the old Buffer path but remains
slower than the string path. The string API therefore remains the small-value
fast path. Medium and large Buffer paths improve, and the unchanged HTTP string
control isolates the large HTTP gain to direct body reads.

`copy-allocation` stops the Lua collector while moving one 16 MiB payload. It
does not attribute Rust or host allocations. The HTTP Buffer path falls from
18,826.71 KiB to 617.99 KiB of Lua allocation. The socket Buffer path rises
from 1,009.10 KiB to 1,417.49 KiB despite its 3.39x throughput gain; its direct
path removes payload strings but still creates checked-view and scheduling
objects. That is recorded as remaining work rather than reported as an
allocation win.

The baseline's `readSpan` path rejects the benchmark's positive owned byte
span as empty, so it cannot supply a valid duration comparison. The candidate
path is retained for coverage but is not used in the baseline verdict.

The paired `copy-datagram` run exercises `receiveFrom` around the usual MTU.
The direct queue drain improved 1200-byte datagrams from 64.43 to 76.73 MiB/s,
1472-byte datagrams from 77.81 to 95.38 MiB/s, and 2048-byte datagrams from
104.17 to 125.15 MiB/s.

The paired `copy-process` run uses the benchmark executable itself as a
portable pipe peer. A duplex 4 MiB echo through `communicate` improved from
308.46 to 483.54 MiB/s (1.57x) after removing per-poll suffix strings. Reading
4 MiB directly into a reusable, initially empty Buffer improved from 207.55 to
253.49 MiB/s (1.22x) after the direct ABI path and bulk queue drain. The empty
Buffer and EOF cases are also correctness oracles, not just timing cases.

The paired `copy-tls` run uses a persistent rustls client and Node TLS echo
peer. A 4 MiB bidirectional Buffer/span exchange improved from 716.33 to
1,199.36 MiB/s (1.67x). The string control moved from 837.03 to 983.79 MiB/s
(1.18x). Besides the temporary plaintext allocation, FFI scratch, Lua string,
and partial-write suffix strings, this removes the encrypted transport's
scratch -> queue -> temporary Vec -> TLS inbound queue chain. The socket now
fills rustls's record destination synchronously, rustls writes ciphertext
straight into the network ownership queue, and rustls fills the caller's
plaintext destination. Each layer retains only storage it owns across calls.
