# Native CRC with ISA-L

`bytes.checksum` reaches `nupp.vm.crc.update` through the built-in checksum
catalog. The native VM bridge now calls the C adapter in
`native/crates/checksum/csrc/crc.c`, which calls ISA-L. VM persistence uses
the same CRC-32 path. No Nupp CRC arithmetic was added.

`scripts/toolchain isal` builds a digest-pinned CRC-only subset of ISA-L
2.32.1 using upstream's CMake source lists, assembly, runtime CPU dispatch,
and portable C fallback. It installs matching public upstream CRC headers,
`nupp_crc.h`, shared and static libraries, the upstream BSD notice, and the
existing hash-checked artifact identity. Cache keys include the C adapter,
build files, compiler/SDK, assembler version, flags and upstream source digest.
An x86 build needs NASM 2.14.01 or later. ARM builds use the C compiler's
assembler. Cross compilation is refused without an explicit target adapter.
The retained GNU Windows VM and MSVC C consumers have separate cache targets.

The static archive contains the upstream implementations and adapter. Native
VMs and packaged programs link those bytes, so no CRC shared sidecar or Rust
tool is needed to run them. The shared C bundle can also be consumed with
just a C compiler; it contains no Rust. Release archives already copy
`host/notices`, including the ISA-L license. The frozen VM itself still needs
Rust to build: removing its compiler/runtime, Markdown, networking, compression
and other Rust consumers is separate work. This change does not claim a
Rust-free compiler setup or whole-program build.

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

Native `crc-fast` calls and VM's direct `crc32fast` calls are removed.
`crc-fast` remains only for the retained browser/Wasm runtime, whose C build
and dispatch contract have not migrated. `crc32fast` remains transitive through
flate2 and the Cranelift object crate. These entries must stay in the workspace
lockfile until their actual consumers migrate.

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
vectors alone prove neither SIMD nor platform acceptance. The retained Rust
bridge tests and Nupp hash-stream tests check actual public routing, including
state transfer and persistence.

## Other ISA-L functions

Use no more ISA-L functions for now. Its [function overview](https://github.com/intel/isa-l/blob/v2.32.1/doc/functions.md)
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
