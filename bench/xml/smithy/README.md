# smithy-java XML baseline

The numbers the Nupp XML codec is measured against: smithy-java's native XML
codec (`codecs/xml-codec`, `SmithyXmlDeserializer` / `SmithyXmlSerializer`) at
commit `b14888c6977925248b9b0a90bb052062e684fed0`, run on this machine. Results
are in [`../baseline/smithy-java.json`](../baseline/smithy-java.json).

## The codec-only numbers are the bar

smithy-java's own serde benchmarks (`RestXmlDeserializeBenchmark`,
`RestXmlSerializeBenchmark`, `AwsQueryDeserializeBenchmark`) time whole
`ClientProtocol#deserializeResponse` and `#createRequest` calls. Those include
HTTP header, URI label and query binding, the status and content-type checks,
and for awsQuery a new `XmlCodec` built on every call to strip the
`<GetMetricDataResponse>`/`<GetMetricDataResult>` wrappers. A codec does none
of that, so those numbers are not like-for-like with one. They are recorded
(`protocol`) for reference only.

`CodecOnlyBenchmark` (`codec_only`) calls the codec directly on the same bytes
and the same codegen-generated shapes, with every codec built once at setup.
Its setup checks that the codec reaches exactly what the protocol does
(decoded body members serialize identically; encoded bodies are
byte-identical), and fails otherwise.

What it feeds each case:

- awsQuery decode: the whole response body, `<GetMetricDataResponse ...>`
  included, to an `XmlCodec` built with
  `wrapperElements([GetMetricDataResponse, GetMetricDataResult])` and
  `strictRootElement(false)`, the configuration `AwsQueryClientProtocol` uses.
  The codec skips the two wrappers itself (and ignores the trailing
  `<ResponseMetadata>`), so the strip is codec work and is measured; building
  the codec is not.
- restXml decode: the response body, to the codec `RestXmlClientProtocol`
  holds (`strictRootElement(false)`, no default namespace), via
  `deserializeShape(ByteBuffer.wrap(body), outputBuilder())`. Header-bound
  members (`responseHeader`, CopyObject's ten `x-amz-*` headers) are not set.
- restXml encode: the input's body members only (the members without an HTTP
  binding trait, as `HttpBindingSerializer`'s `StructBodyProxy` presents them)
  through `serializeToDataStream`, the leased-buffer path `createRequest`
  takes; the pooled buffer is released each iteration.
- `restXml_CopyObjectRequest_M` has no codec-only counterpart: every member of
  `CopyObjectRequest` is a header or label, so restXml sends no body and never
  calls the codec. `restXml_CopyObjectRequest_M_AllMembersAsBody` serializes
  the whole input (all 42 members, timestamps as date-time) as XML elements
  instead; it is ours, not upstream's.

Case names are upstream's. All exist at the pinned commit.

## Running

```sh
bench/xml/smithy/run.sh [--work DIR] bench        # writes bench/xml/baseline/smithy-java.json
bench/xml/smithy/run.sh [--work DIR] payloads DIR # fixtures only, digest-checked
```

The work directory defaults to `${XDG_CACHE_HOME:-$HOME/.cache}/nupp/smithy-java`;
`GRADLE_USER_HOME` defaults to `<work>/gradle-home`. Gradle runs on `JAVA_HOME`
(JDK 26 is fine) and provisions the JDK 25 toolchain the benchmarks need
through the foojay resolver, applied by an init script; the benchmarks run on
that JDK 25 unless `--java` names another. Builds and runs are `nice -n 19`,
one JMH at a time, one thread, and each recorded run waits for the one-minute
load average to drop under `MAX_LOAD` (8). JMH: throughput, 3 forks, 5 x 2 s
warmup, 5 x 5 s measurement, upstream's JVM flags
(`-Xms1g -Xmx1g -XX:+UseG1GC -XX:+AlwaysPreTouch`), forced GC, and upstream's
`OpsPerCpuSecondProfiler` for `ops_per_cpu_sec` (operations over process CPU
time, all threads).
The gate only holds the start of each run: the recorded runs started at a
one-minute load of 7.1 to 8.0 and ended at 7.1 to 9.8 on an 18-core machine
with other work going on, so treat differences under the reported spread as
noise.

## Fixtures

`payloads DIR` writes, for each case, what the Nupp harness needs:

| File | Contents |
|---|---|
| `<case>.xml` | decode input: the exact body bytes fed to the codec |
| `<case>.params.json` | the test case's `params`: decode's expected result, encode's input |
| `<case>.expected.xml` | encode output, byte-identical to the protocol's request body |
| `GetMetricDataResponseLarge.xml` | upstream's payload file, for reference |

Bodies come from the test cases' `body` text blocks in the model, not from the
payload file: `awsQuery_GetMetricDataResponse_L.xml` (56,873 bytes) is
`GetMetricDataResponseLarge.xml` (56,872 bytes) plus a final newline. CopyObject
responses have no `params`, so their `params.json` is `{}`; the expected values
are the body's element texts. Digests of every fixture are in `run.sh`.

## Upstream files

All under `benchmarks/serde-benchmarks/model/` at the pinned commit:

| Path | What |
|---|---|
| `operations/GetMetricData.smithy` | operation, `GetMetricDataOutput`, awsQuery test cases (bodies inline) |
| `structures/MetricDataQuery.smithy` | `MetricDataResult`, `MessageData`, `StatusCode`, lists |
| `structures/MetricData.smithy` | `Values` list, `StandardUnit` |
| `operations/WideTypes.smithy` | `WideTypesInput`/`Output`, `WideTypesMembers` mixin, test cases |
| `operations/CopyObject.smithy` | `CopyObjectRequest`, `CopyObjectOutput` (`@xmlName("CopyObjectResult")`), test cases |
| `AwsQueryDataPlane.smithy`, `AwsRestXmlDataPlane.smithy` | services (`@xmlNamespace`) |
| `resources/CloudWatchMetric.smithy`, `resources/S3Object.smithy`, `main.smithy` | resource bindings, suppressions |
| `payloads/GetMetricDataResponseLarge.xml` | the L body as a file |

The benchmark classes are under
`benchmarks/serde-benchmarks/src/jmh/java/software/amazon/smithy/java/benchmarks/serde/`.
