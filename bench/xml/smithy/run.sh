#!/usr/bin/env bash
# Records smithy-java's XML codec baseline for the Nupp XML benchmarks.
#
#   run.sh [--work DIR] [--java JAVA] bench [OUT.json]   both JMH runs (default)
#   run.sh [--work DIR] [--java JAVA] payloads OUTDIR    only the case fixtures
#   run.sh [--work DIR] [--java JAVA] summarize [OUT.json] refold the last bench results
#
# smithy-java is fetched at a pinned commit into the work directory (default
# ${XDG_CACHE_HOME:-$HOME/.cache}/nupp/smithy-java); nothing from it is kept in
# this repository. Every upstream file the cases read, and every fixture the
# payloads command writes, is checked against the SHA-256 digests below.
#
# smithy-java's benchmarks build with a JDK 25 toolchain. Gradle itself runs on
# JAVA_HOME (any JDK it supports; 26 works) and provisions JDK 25 into
# GRADLE_USER_HOME through the foojay resolver when no JDK 25 is installed. The
# benchmarks then run on that JDK 25 unless --java names another `java`.
#
# Every build and benchmark runs under `nice -n 19`, single-threaded, one at a
# time. Before each recorded JMH run the script waits for the one-minute load
# average to fall under MAX_LOAD (default 8), polling every POLL_SECONDS.

set -euo pipefail

SMITHY_JAVA_REPO=https://github.com/smithy-lang/smithy-java.git
SMITHY_JAVA_COMMIT=b14888c6977925248b9b0a90bb052062e684fed0
FOOJAY_RESOLVER=org.gradle.toolchains:foojay-resolver:1.0.0
JDK_FEATURE=25

MAX_LOAD=${MAX_LOAD:-8}
POLL_SECONDS=${POLL_SECONDS:-180}

# JMH settings for the recorded runs. Upstream's serde-benchmarks task runs
# SampleTime mode, one fork, 5 warmup and 10 measurement iterations; these
# keep its iteration lengths, JVM flags, forced GC and CPU profiler, and use
# throughput mode with three forks so each case reports ops/s with a spread.
JMH_FORKS=${JMH_FORKS:-3}
JMH_WARMUPS=${JMH_WARMUPS:-5}
JMH_WARMUP_TIME=${JMH_WARMUP_TIME:-2s}
JMH_ITERATIONS=${JMH_ITERATIONS:-5}
JMH_ITERATION_TIME=${JMH_ITERATION_TIME:-5s}
JMH_JVM_ARGS="-Xms1g -Xmx1g -XX:+UseG1GC -XX:+AlwaysPreTouch"
CPU_PROFILER=software.amazon.smithy.java.benchmarks.OpsPerCpuSecondProfiler

MODULE=benchmarks/serde-benchmarks
MODEL=$MODULE/model
SERDE_PACKAGE_DIR=$MODULE/src/jmh/java/software/amazon/smithy/java/benchmarks/serde

# Upstream files the cases are built from, at SMITHY_JAVA_COMMIT.
UPSTREAM_DIGESTS="\
df29e95b9f269577ddada99dbfd8e7c07a32bcf073be048c1c955507323475b9  $MODEL/operations/GetMetricData.smithy
ba3de324bd284828a7ea802ba297e8f751016ff56e88ccdbf9d2b7552d99001d  $MODEL/operations/WideTypes.smithy
6c2a46b4d17bea57eb5309d6540d0ecacdb8aace4f8429744977bc3d52182bb9  $MODEL/operations/CopyObject.smithy
b8b7b346a37cb4fda3baf65c0000b3d7c11509878ca6b35a67e94a6fe722524b  $MODEL/structures/MetricData.smithy
fa84b811db69627132a422c2b8db65d100488e78138ca880da4dee69721fc2be  $MODEL/structures/MetricDataQuery.smithy
2dd280157e4e8c5c681e1e000d2e18783bd4f394f3aff026cafc56d832ce6090  $MODEL/resources/CloudWatchMetric.smithy
d8f29b16af9e4cc9907f625648a51e5686141725152b5c8d07197e97a87a68f2  $MODEL/resources/S3Object.smithy
e2f26f9a19b9dffe69cfaf515729e3b48fccd1bd5bfeb39dac2407a6079ad3d0  $MODEL/AwsQueryDataPlane.smithy
ecabfc51e96acdf3793b696e437f5704b0b772a9d5f2e0df88c6aaa3badfc9f7  $MODEL/AwsRestXmlDataPlane.smithy
c9502b482ce2e61a54bebefe9c4cdb4aa8a93903818a9c9a9c1a75d0a8cb40df  $MODEL/main.smithy
85ab8137af0898d7051def12c30eab6de597af201d4d5ddbf0bff0360bf8d6bb  $MODEL/payloads/GetMetricDataResponseLarge.xml
"

# Fixtures `payloads` writes (decode inputs, params, encode outputs).
FIXTURE_DIGESTS="\
85ab8137af0898d7051def12c30eab6de597af201d4d5ddbf0bff0360bf8d6bb  GetMetricDataResponseLarge.xml
3be0acf9db24941751b68a87e4ccbecba5da9882b92533b6a6ba1e977f978e97  awsQuery_GetMetricDataResponse_L.params.json
0f2bd18a5b4e12da2ea0576d6adcb569fcbc0c7da2e3f5011de92e95d02ac29e  awsQuery_GetMetricDataResponse_L.xml
222e1117e6070332a0af74bda112e5e982c96ff60c63fc6610da673c555f7727  awsQuery_GetMetricDataResponse_OutOfOrder.params.json
b7f1667d0e66caafc61046618f8297738160f75658671b3a505cbba17ed4dcef  awsQuery_GetMetricDataResponse_OutOfOrder.xml
ca3d163bab055381827226140568f3bef7eaac187cebd76878e0b63e9e442356  restXml_CopyObjectOutput_M.params.json
2633423fbc8721702ef90299bb397c8c96bd4751200b53962af1cbd3b98c8b7f  restXml_CopyObjectOutput_M.xml
ca3d163bab055381827226140568f3bef7eaac187cebd76878e0b63e9e442356  restXml_CopyObjectOutput_OutOfOrder.params.json
124454dd476439e3c890a133c25706df2e217838bd4d87ef8b818eb2eaf92a8b  restXml_CopyObjectOutput_OutOfOrder.xml
e5df15ce855681d6b871fc1c783bc7b4d501acae3a9c6122712758a6c96139b5  restXml_CopyObjectRequest_M_AllMembersAsBody.expected.xml
4eb414a1443d4253aa7e246da1f375794373df9d1b1923ed5229a082c5479d12  restXml_CopyObjectRequest_M_AllMembersAsBody.params.json
723027039d4ba597bee2a0b41f5ede413d3ca0597000dec6ab5ac724dec45a36  restXml_WideTypesRequest_L.expected.xml
219eca169e9d98c48f18a8cb2ff7f93c3cae9091b672af124f381ed709f5284d  restXml_WideTypesRequest_L.params.json
79250f5e0e3c238416d978e89ea11b371b00792318dc2c655afd55d7c836afc4  restXml_WideTypesRequest_M.expected.xml
fc2163ff858156420a3f05561a2f8ee51f5b406a2c3c7b8330dd3fadf0ff02b9  restXml_WideTypesRequest_M.params.json
3eeb2b252b2e1928ed50da736365bfe8daf1bb355f39332af0150b4212cf6eb3  restXml_WideTypesRequest_S.expected.xml
ad475bd5781cbcd8df6ffdec2387582de39bd1a03c80c0851bc818154b70287a  restXml_WideTypesRequest_S.params.json
186b8eec92879d82d01b77ed5254816aef10ae0621744c1157606f24668aface  restXml_WideTypesResponse_L.params.json
3a757e98d31896db08a0f12dfb6fc377edd75df38d27400253f9754fa9449379  restXml_WideTypesResponse_L.xml
36dbfdc28f0b455e3b7c4b02e2dddbdc069da03d3b36b70ae8240caa2f91f07c  restXml_WideTypesResponse_M.params.json
5b5293319098c84371f6ef6848491b1770d45b4d6a79274b79e16532ace1c76a  restXml_WideTypesResponse_M.xml
8c837d02874e9782dc8334a04a9effc3f9a84fe7ea12f30c999565133e1dc5ed  restXml_WideTypesResponse_S.params.json
df9550724431b164194fe238b2cd2d417f976e4e1164f9af6b9fc8ee18652660  restXml_WideTypesResponse_S.xml
"

# Protocol-level cases: upstream benchmark class and the test cases run on it.
PROTOCOL_RUNS="\
AwsQueryDeserializeBenchmark awsQuery_GetMetricDataResponse_L,awsQuery_GetMetricDataResponse_OutOfOrder
RestXmlDeserializeBenchmark restXml_WideTypesResponse_S,restXml_WideTypesResponse_M,restXml_WideTypesResponse_L,restXml_CopyObjectOutput_M,restXml_CopyObjectOutput_OutOfOrder
RestXmlSerializeBenchmark restXml_WideTypesRequest_S,restXml_WideTypesRequest_M,restXml_WideTypesRequest_L,restXml_CopyObjectRequest_M
"

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
work=${XDG_CACHE_HOME:-$HOME/.cache}/nupp/smithy-java
java_bin=

usage() {
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case $1 in
    --work) work=$2; shift 2 ;;
    --java) java_bin=$2; shift 2 ;;
    -h|--help) usage ;;
    *) break ;;
  esac
done

command=${1:-bench}
[ $# -gt 0 ] && shift

src=$work/src
export GRADLE_USER_HOME=${GRADLE_USER_HOME:-$work/gradle-home}

log() { printf '[run.sh] %s\n' "$*" >&2; }

fetch() {
  mkdir -p "$work"
  if [ ! -d "$src/.git" ]; then
    git init -q "$src"
    git -C "$src" remote add origin "$SMITHY_JAVA_REPO"
  fi
  if [ "$(git -C "$src" rev-parse -q --verify HEAD 2>/dev/null || true)" != "$SMITHY_JAVA_COMMIT" ]; then
    log "fetching smithy-java $SMITHY_JAVA_COMMIT"
    git -C "$src" fetch -q --depth 1 origin "$SMITHY_JAVA_COMMIT"
    git -C "$src" checkout -q --detach FETCH_HEAD
  fi
  # Drop anything a previous run left in the tree except the build output.
  git -C "$src" checkout -q -- .
  log "checking upstream digests"
  (cd "$src" && printf '%s' "$UPSTREAM_DIGESTS" | shasum -a 256 -c --quiet -) ||
    { log "upstream file digest mismatch"; exit 1; }
}

build() {
  cp "$here/CodecOnlyBenchmark.java" "$src/$SERDE_PACKAGE_DIR/CodecOnlyBenchmark.java"
  cat > "$work/foojay.init.gradle" <<EOF
initscript {
    repositories { gradlePluginPortal() }
    dependencies { classpath "$FOOJAY_RESOLVER" }
}
beforeSettings { settings ->
    settings.pluginManager.apply(org.gradle.toolchains.foojay.FoojayToolchainsConventionPlugin)
}
EOF
  log "building the JMH jar"
  (cd "$src" && nice -n 19 ./gradlew -q --init-script "$work/foojay.init.gradle" --max-workers=4 \
    ":${MODULE//\//:}:jmhJar")
  jar=$(ls "$src/$MODULE"/build/libs/*-jmh.jar | head -n 1)
  [ -n "$java_bin" ] || java_bin=$(find_jdk)
  log "benchmark JVM: $java_bin"
}

# The JDK 25 Gradle provisioned, or JAVA_HOME's if that is 25.
find_jdk() {
  local candidate
  for candidate in "${JAVA_HOME:-/nonexistent}/bin/java" "$GRADLE_USER_HOME"/jdks/*/*/Contents/Home/bin/java \
    "$GRADLE_USER_HOME"/jdks/*/Contents/Home/bin/java "$GRADLE_USER_HOME"/jdks/*/bin/java; do
    [ -x "$candidate" ] || continue
    if "$candidate" -XshowSettings:properties -version 2>&1 | grep -q "java.specification.version = $JDK_FEATURE\$"; then
      echo "$candidate"
      return
    fi
  done
  log "no JDK $JDK_FEATURE found; pass --java"
  exit 1
}

payloads() {
  local out=$1
  mkdir -p "$out"
  out=$(cd "$out" && pwd)
  log "writing fixtures to $out"
  nice -n 19 "$java_bin" -cp "$jar" software.amazon.smithy.java.benchmarks.serde.CodecOnlyBenchmark "$out"
  cp "$src/$MODEL/payloads/GetMetricDataResponseLarge.xml" "$out/"
  if [ -n "$FIXTURE_DIGESTS" ]; then
    (cd "$out" && printf '%s' "$FIXTURE_DIGESTS" | shasum -a 256 -c --quiet -) ||
      { log "fixture digest mismatch"; exit 1; }
  else
    log "no fixture digests recorded yet; these are the current ones:"
    (cd "$out" && shasum -a 256 *) >&2
  fi
}

load1() { sysctl -n vm.loadavg | awk '{print $2}'; }

wait_for_quiet() {
  while awk -v l="$(load1)" -v m="$MAX_LOAD" 'BEGIN { exit !(l >= m) }'; do
    log "load $(load1) >= $MAX_LOAD; waiting ${POLL_SECONDS}s"
    sleep "$POLL_SECONDS"
  done
}

# jmh NAME INCLUDE RESULT [JMH ARGS...]: one recorded run, with its load averages.
jmh() {
  local name=$1 include=$2 result=$3
  shift 3
  wait_for_quiet
  local start end
  start=$(sysctl -n vm.loadavg)
  log "JMH $name (load $start)"
  nice -n 19 "$java_bin" -jar "$jar" "$include" "$@" \
    -bm thrpt -tu s -t 1 -f "$JMH_FORKS" -wi "$JMH_WARMUPS" -w "$JMH_WARMUP_TIME" \
    -i "$JMH_ITERATIONS" -r "$JMH_ITERATION_TIME" -gc true -jvmArgs "$JMH_JVM_ARGS" \
    -prof "$CPU_PROFILER" -rf json -rff "$result" >&2
  end=$(sysctl -n vm.loadavg)
  jq --arg name "$name" --arg start "$start" --arg end "$end" \
    '{run: $name, load_average_start: $start, load_average_end: $end, results: .}' "$result" > "$result.tmp"
  mv "$result.tmp" "$result"
}

bench() {
  local out=${1:-$repo/bench/xml/baseline/smithy-java.json}
  local results=$work/results
  rm -rf "$results"
  mkdir -p "$results"
  payloads "$results/payloads"

  local class cases
  printf '%s' "$PROTOCOL_RUNS" | while read -r class cases; do
    jmh "protocol:$class" "\\.$class\\." "$results/protocol-$class.json" -p "testCaseId=$cases"
  done
  jmh "codec" '\.CodecOnlyBenchmark\.' "$results/codec.json"
  summarize "$out"
}

# summarize OUT: folds the last run's JMH results in the work directory into OUT.
summarize() {
  local out=$1 results=$work/results
  describe_files "$results"
  local jvm
  jvm=$("$java_bin" -XshowSettings:properties -version 2>&1 |
    awk -F' = ' '/java.vm.vendor =|java.runtime.version =|java.vm.name =/ { gsub(/^ +/, "", $1); print $1 "=" $2 }')
  jq -n \
    --arg commit "$SMITHY_JAVA_COMMIT" \
    --arg model "$(sysctl -n hw.model)" \
    --arg chip "$(sysctl -n machdep.cpu.brand_string)" \
    --arg cpus "$(sysctl -n hw.ncpu)" \
    --arg os "$(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))" \
    --arg jvm "$jvm" \
    --arg profiler "$CPU_PROFILER" \
    --slurpfile codec "$results/codec.json" \
    --slurpfile query "$results/protocol-AwsQueryDeserializeBenchmark.json" \
    --slurpfile xmlDecode "$results/protocol-RestXmlDeserializeBenchmark.json" \
    --slurpfile xmlEncode "$results/protocol-RestXmlSerializeBenchmark.json" \
    --slurpfile payloads "$results/payloads.jsonl" \
    --slurpfile upstream "$results/upstream.jsonl" \
    "$SUMMARY" > "$out"
  log "wrote $out"
}

# One JSON line per fixture and per upstream file: name, size and digest.
describe_files() {
  local results=$1 f
  for f in "$results"/payloads/*; do
    jq -cn --arg file "$(basename "$f")" --argjson bytes "$(wc -c < "$f" | tr -d ' ')" \
      --arg sha256 "$(shasum -a 256 "$f" | cut -d' ' -f1)" '{file: $file, bytes: $bytes, sha256: $sha256}'
  done > "$results/payloads.jsonl"
  printf '%s' "$UPSTREAM_DIGESTS" | while read -r digest path; do
    jq -cn --arg path "$path" --argjson bytes "$(wc -c < "$src/$path" | tr -d ' ')" --arg sha256 "$digest" \
      '{path: $path, bytes: $bytes, sha256: $sha256}'
  done > "$results/upstream.jsonl"
}

# Folds the four JMH result files into the baseline document.
SUMMARY='
def num: if type == "number" then . else null end;
def cases($kind):
  .results[] | {
    case: (.params.testCaseId),
    benchmark: (.benchmark | sub("^software\\.amazon\\.smithy\\.java\\.benchmarks\\.serde\\."; "")),
    kind: $kind,
    ops_per_sec: {
      score: .primaryMetric.score,
      error: (.primaryMetric.scoreError | num),
      confidence_99_9: .primaryMetric.scoreConfidence,
      min_iteration: ([.primaryMetric.rawData[][]] | min),
      max_iteration: ([.primaryMetric.rawData[][]] | max),
      iterations: ([.primaryMetric.rawData[][]] | length)
    },
    ops_per_cpu_sec: (.secondaryMetrics.ops_per_cpu_sec // null | if . == null then null else {
      score: .score,
      error: (.scoreError | num),
      note: "operations / process CPU time (all threads: benchmark, JIT, GC, JMH), totalled over every fork and measurement iteration, so it is one value with no error"
    } end)
  };
{
  smithy_java: {repository: "https://github.com/smithy-lang/smithy-java", commit: $commit},
  machine: {model: $model, chip: $chip, logical_cpus: ($cpus | tonumber), os: $os},
  jvm: (($jvm | split("\n") | map(select(length > 0) | split("=") | {(.[0]): (.[1:] | join("="))}) | add) + {path: $codec[0].results[0].jvm}),
  jmh: ($codec[0].results[0] | {
    version: .jmhVersion, mode, time_unit: "s", threads, forks,
    warmup_iterations: .warmupIterations, warmup_time: .warmupTime,
    measurement_iterations: .measurementIterations, measurement_time: .measurementTime,
    force_gc: true, jvm_args: .jvmArgs, profiler: $profiler,
    priority: "nice -n 19"
  }),
  runs: [($query[0], $xmlDecode[0], $xmlEncode[0], $codec[0]) | {run, load_average_start: (.load_average_start | [scan("[0-9.]+") | tonumber]), load_average_end: (.load_average_end | [scan("[0-9.]+") | tonumber]), load_average_note: "sysctl vm.loadavg: 1, 5 and 15 minute averages"}],
  codec_only: [$codec[0] | cases("codec_only")],
  protocol: [($query[0], $xmlDecode[0], $xmlEncode[0]) | cases("protocol")],
  not_applicable: [{
    case: "restXml_CopyObjectRequest_M",
    kind: "codec_only",
    reason: "every CopyObjectRequest member is an HTTP header or label, so restXml sends no body and never calls the XML codec; restXml_CopyObjectRequest_M_AllMembersAsBody serializes the whole input as XML elements instead"
  }],
  payloads: $payloads,
  upstream_files: $upstream
}'

fetch
build
case $command in
  payloads) [ $# -eq 1 ] || usage; payloads "$1" ;;
  bench) bench "$@" ;;
  summarize) summarize "${1:-$repo/bench/xml/baseline/smithy-java.json}" ;;
  *) usage ;;
esac
