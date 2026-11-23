# XML benchmarks

The bar for `serde.xml`'s typed codec is smithy-java's native XML codec. Both
sides are measured on smithy-java's serde-benchmark payloads, on the same Mac.

- `smithy/` records smithy-java's codec-only throughput at a pinned commit.
  Its README explains why the codec-only numbers are the bar. The results are
  in `baseline/smithy-java.json`.
- `model.nupp` mirrors the GetMetricData, WideTypes and CopyObject shapes as
  Nupp records and builds a codec for each case.
- `codec.nupp` times typed decode and encode of every case on the native core.
  It runs a calibration, then five samples of about half a second each, and
  writes the median, minimum and maximum ops/s as JSON.
- `compare.nupp` prints the Nupp-to-smithy ratio per case.
- `feeds.nupp` times a synthetic 1 MiB Torznab search response and an RSS 2.0
  feed, parsed with `namespaces = true` as a tree and through a typed codec.
  Its first numbers are the feed bar in `baseline/feeds.json`.

```sh
bench/xml/smithy/run.sh payloads /path/to/payloads   # fetches and checks digests
NUPP_RUNTIME=core ./bin/nupp run bench/xml/codec.nupp /path/to/payloads out.json
NUPP_RUNTIME=core ./bin/nupp run bench/xml/compare.nupp out.json
NUPP_RUNTIME=core ./bin/nupp run bench/xml/feeds.nupp
```

The payloads are Apache-2.0 files from smithy-java. They are fetched at the
baseline's commit and checked against the digests in `smithy/run.sh`. None of
them are kept in this repository.

Take a recorded measurement only when the machine is quiet: the one-minute
`sysctl -n vm.loadavg` should be under 8. Record the spread of the samples.
