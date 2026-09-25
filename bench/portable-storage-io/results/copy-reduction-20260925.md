# Scalar and ByteView copy-reduction benchmark, 2026-09-25

Both runs use LuaJIT 2.1 on the Apple M5 Pro described in the native-runtime
copy-reduction record. The baseline is unchanged `635de296`; the candidate is
the uncommitted copy-reduction changes on top of `2a4198f0`.

Command: `bench/portable-storage-io/run.sh`

The repeated scalar-reader case reads 1024 `uint32` values from one 4 KiB
backing value per operation. Its nine-sample median fell from 20.313 ms to
1.382 ms for 100 operations, a 14.70x improvement. With JIT disabled and the
collector stopped, ten operations fell from 2,275.504 KiB to 202.500 KiB of
uncollected Lua growth. The number of unavoidable four-byte physical decode
copies is unchanged; the removed cost is repeated copying of the unread tail.

The scalar writer did not show a material win: 10,000 `uint32` writes had a
0.396 ms baseline median and a 0.405 ms candidate median. Ten writes still
materialize 40 bytes of encoded strings. Adding pointer codecs to every native
and portable representation provider is not justified by this result, so the
conditional scalar-writer change is deliberately dropped.

Ten thousand eager six-byte `ByteView:view` slices had stable medians of 0.057
ms baseline and 0.058 ms candidate. A 4 KiB ByteView UTF-8 walk also stayed
flat at 0.241 ms versus 0.238 ms for 100 walks. The current eager child string
does not retain the parent's large backing. A lazy representation would add
caching and backing-retention policy without a measured duration problem, so
the conditional zero-copy ByteView change is deliberately dropped.
