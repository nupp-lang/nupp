# Native CRC with ISA-L

`bytes.checksum` reaches `nupp.runtime.core.crccodec` through the built-in
checksum catalog. That module is Nupp over checked FFI to the C adapter in
`native/crc/crc.c`, which calls ISA-L, and the VM and the native core run the
same binding. The library is the logical `nuppcrc`, which the compiler binds to
the shared library `NUPP_CRC_LIBRARY` names, or else, in a source checkout,
to the one `scripts/c-library-paths` builds the first time a program binds it. VM persistence links the static archive for its
CRC-32 frames. No Nupp CRC arithmetic was added, and no Rust CRC code remains.

`scripts/toolchain isal` builds a digest-pinned CRC-only subset of ISA-L
2.32.1 using upstream's CMake source lists, assembly, runtime CPU dispatch,
and portable C fallback. It installs matching public upstream CRC headers,
`nuppcrc.h`, shared and static libraries, upstream/contributor BSD notices, and the
existing hash-checked artifact identity. Cache keys include the C adapter,
build files, compiler/SDK, assembler version, flags and upstream source digest.
An x86 build needs NASM 2.14.01 or later. ARM builds use the C compiler's
assembler. Cross compilation is refused without an explicit target adapter.
The retained GNU Windows VM and MSVC C consumers have separate cache targets.

The static archive contains the upstream implementations and adapter; the VM
links it for persistence. Checksums load the shared library, and a packaged
program carries it as a sidecar beside its other bound libraries. The C
bundle can be consumed with just a C compiler; it contains no Rust. Release
archives already copy `notices`, including the ISA-L license.

## State contract

| ID | Algorithm | Raw init | Final XOR | ISA-L entry |
|---|---|---|---|---|
| 1 | CRC32/ISO-HDLC | ffffffff | ffffffff | crc32_gzip_refl |
| 2 | CRC32/iSCSI | ffffffff | ffffffff | crc32_iscsi |
| 3 | CRC64/ECMA-182 | 0 | 0 | crc64_ecma_norm |
| 4 | CRC64/NVME | ffffffffffffffff | ffffffffffffffff | crc64_rocksoft_refl |

The two-word ABI keeps the raw register separate from the final XOR result.
ISA-L gzip and Rocksoft take and return finalized values, so the adapter
complements them at both ends. Normal ECMA also needs complements at both
ends to match ECMA-182's zero init and zero final XOR. iSCSI takes the raw
register. Empty input bypasses upstream calls, preserves raw state, and
refreshes the non-consuming snapshot. Calls are bounded to `INT_MAX` before
narrowing for iSCSI. Null nonempty input, invalid IDs/reset values, null state,
and lengths above `PTRDIFF_MAX` fail without changing either word.

The Rust checksum crate, `crc-fast` and the VM's direct `crc32fast` calls are
removed. `crc32fast` remains transitive through flate2, which Reqwest's
decompression still pulls in, and the Cranelift object crate.

## Checks

`sh .github/scripts/test-crc-isal.sh` provisions the C bundle, verifies offline
warm reuse, packages its matching headers/libraries/notices, and builds/runs a
standalone C consumer. It checks independent catalogue vectors and a bitwise
test reference against random raw seeds, chunk boundaries, empty updates,
snapshots/resume, offsets, alignments, tails, zeros, and rejected calls.
Forced portable and hardware paths use the same adapter. Hardware tests check
CPU support first. A test with a reduced signed-length limit exercises bounded
chunking without a multi-gigabyte allocation. A short C benchmark covers 16 B,
4 KiB and 1 MiB buffers; these timings exclude Nupp/VM overhead.

The five-target pinned-C workflow blocks Cargo, rustc, rustup and cargo-c
while checking this path. Each platform must pass on its own; baseline C
vectors alone prove neither SIMD nor platform acceptance. The Nupp hash-stream
tests check actual public routing, including state transfer.

## Other ISA-L functions

One additional function has a real caller to investigate: [`isal_adler32`](https://github.com/intel/isa-l/blob/v2.32.1/include/igzip_lib.h)
could replace the byte-at-a-time public `AdlerState.update` loop in
`src/nupp/checksum/internal/builtin.nupp`. Upstream documents runtime CPU
selection and supplies SSE/AVX2, NEON and portable implementations. Measure
it against the already-pinned zlib's `adler32` on actual Nupp span/stream
calls before choosing either. Adler-32 has not been migrated, benchmarked,
or added to this CRC-only bundle.

Use no other ISA-L functions for now. Its [function overview](https://github.com/intel/isa-l/blob/v2.32.1/doc/functions.md)
lists erasure coding, RAID parity, memory checks and Deflate/inflate. Nupp has
no current erasure-coding or RAID caller. Its [memory functions](https://github.com/intel/isa-l/blob/v2.32.1/include/mem_routines.h)
detect all-zero buffers; no current hot caller establishes
a need for them. CRC combine is an upstream example rather than a required
public checksum operation. Compression is a possible later measured comparison,
but does not justify replacing already-pinned zlib or changing its framing,
flush and streaming contracts. OpenSSL remains the chosen crypto/TLS provider.
ISA-L crypto is a separate project and outside this change.

Primary sources: [CRC API](https://github.com/intel/isa-l/blob/v2.32.1/include/crc.h),
[CRC64 API](https://github.com/intel/isa-l/blob/v2.32.1/include/crc64.h),
[source lists](https://github.com/intel/isa-l/blob/v2.32.1/cmake/crc.cmake),
[ARM runtime dispatch](https://github.com/intel/isa-l/blob/v2.32.1/crc/aarch64/crc_aarch64_dispatcher.c),
[x86 runtime dispatch](https://github.com/intel/isa-l/blob/v2.32.1/crc/crc_multibinary.asm),
[build requirements](https://github.com/intel/isa-l/blob/v2.32.1/README.md).
