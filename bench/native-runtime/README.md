# Native network and HTTP benchmark

This is the public-boundary performance and bounded-resource fixture for the
Rust-native network and HTTP providers. It measures `nupp.io.net` streams and a
persistent `nupp.io.http.Client`; it does not compare those wrappers with raw
Tokio, Reqwest, or operating-system sockets.

The benchmark uses one loopback Node HTTP peer outside the measured request
intervals. Nine measured samples follow two warmups, and the reported value is
their median. Run the steady-state measurements with:

```sh
bench/native-runtime/run.sh
```

Run the slow-reader RSS probes with:

```sh
bench/native-runtime/resource.sh
```

The resource script polls the benchmark process during a complete load run and
reports its peak RSS, then samples the slow-reader processes after one, three,
and five seconds. `net-slow-reader` repeatedly writes the same 64 KiB value
through a stream whose public `sendHighWater` is 64 KiB while its peer reads
nothing.
`http-slow-reader` holds an unread 256 MiB response whose Node sender honors
transport backpressure. The processes are stopped after the final sample; a
plateau rather than the absolute RSS demonstrates bounded buffering.

Run on an otherwise quiet machine. Record the Nupp revision, operating system,
hardware, Rust version, benchmark output, and resource samples. Linux and
Windows are separate platform runs rather than results inferred from macOS.
