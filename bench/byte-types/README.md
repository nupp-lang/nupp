# Byte buffer migration measurements

These runs compare compiler self-builds and AOT text emission while replacing
public LuaJIT buffers with `io.Buffer`. The baseline is `6d245946f`.

```sh
./bin/nupp build --target compiler --output build/byte-measure/compiler --json
./bin/nupp aot --emit ir --function advance bench/span-range-lowering/aot.nupp
./bin/nupp aot --emit llvm --function advance bench/span-range-lowering/aot.nupp
```

Use a fresh output directory for each self-build. Build the compiler that runs
the measurement first, so a launcher rebuild is excluded. Preserve a baseline
checkout and run the two checkouts serially on the same machine.

## Recorded runs

The machine was an Apple arm64 host running LuaJIT. The JSON beside this page
retains commands, durations, compiler phase timings, output sizes, and hashes.
These are individual observations, not confidence intervals.

| Implementation | Self-build wall seconds | Notes |
| --- | ---: | --- |
| Original buffer | 38.63 | Initial baseline |
| Checked FFI buffer | 56.02 | Rejected as the compiler's text builder |
| Native-backed public buffer | 58.18 | Append costs improved; facade remained |
| Cached private text builder | 54.83 | Fresh compiler using the final lowering |
| Preserved baseline, later | 49.49 | Build phases only; launcher bootstrap excluded |
| Cached private text builder, later | 53.18 | About 7% slower than the later baseline |

The initial baseline's lower time did not reproduce in the later baseline.
There is no whole-compiler speedup claim. A final interleaved run compiled the same 465 modules with the preserved
baseline compiler and the migrated compiler. Baseline wall times were 44.02
and 48.41 seconds; migrated times were 42.65 and 38.53 seconds. Child CPU times
were 48.93/58.09 and 50.38/48.03 seconds. Both runs fell back to serial checking
after the same recursive worker check. These observations do not establish a
whole-compiler regression or speedup. An experimental variant omitting native
builder cleanup did not improve either measure consistently, so explicit
cleanup stays.

For the later runs, three AOT IR emissions took 1.79–1.99 seconds on the
baseline and 1.80–1.86 seconds after migration. LLVM emissions took 1.73–1.84
seconds and 1.84–1.88 seconds respectively. Every IR output was 1,402 bytes
with SHA-256 `e36325a9ced64792c49105cdba8a8dd7e0b1b147a5e0a8955f7c7d3e41ced86c`;
every LLVM output was 5,260 bytes with SHA-256
`511521f2aaf4734250d4dc22561dbf74401a6c65c8d21596f310757f7afe01cb`.

## Private implementation

A paired 100,000-append loop produced identical 2,488,895-byte strings. The
initial FFI buffer took about 7.3 ms against the native buffer's 1.6 ms. The
native-backed public buffer reduced that to roughly 2.4–3.3 ms, alongside
2.3–3.1 ms for the native buffer during that later run. A separate short-builder
loop took roughly 18 ms through the private factory against 21–22 ms through
the original factory for 100,000 results.

The compiler therefore keeps a private native storage implementation behind
`io.Buffer`, with a cached lazy binding for generated text builders. The lazy
binding avoids initialization cycles; caching keeps repeated `require` calls
out of hot loops. Fixed argument reads avoid LuaJIT's unrecordable vararg loop.
Other hosts use the checked buffer implementation. Public buffers retain the
same ownership and reservation-lease contracts in either implementation.
