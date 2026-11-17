# Independent C startup transport proof

Observed on macOS ARM64, November 16, 2026. Source identities and nonblank C/header/assembly/build-glue counts are in `source.json`. This is an independently selectable transport; the frozen Rust transport remains active by default.

The real standalone core ran `cbridge guestffi ffiaggregates tasksreactor reactorfiles reactorpipes` through `tests/core/guests/run.lua`, with `NUPP_CORE_TRANSPORT=c`, four jobs and one shard. Both normal and spill modes, ordinary ABI/scratch guards, collect-at-every-allocation, interleaved collection, and the runner's cancellation/resource audits ran: **7,710 checks, zero failures, 209 seconds**. The preceding Rust-reference `guestffi ffiaggregates` run passed 2,568 checks.

`scripts/core-bridge --test` also passed with fail-fast replacements for Cargo, rustc, rustup and cargo-c. Native tests exercised malformed/truncated packets, extent/alignment/version refusals, W^X and ABI guard calibration, scratch canaries, queue cancellation, active-work settlement/draining and stale tickets. Building the C transport needs a C compiler and pthreads; producing the Nupp guest programs still uses the existing compiler toolchain.

The function-family audit and reasons for retained C are in `native/core-bridge/README.md`. Initial mapping/entry precedes Nupp execution; the copied-byte blocking OS worker needs a native thread entry until checked foreign-thread callbacks exist. Library-path construction and loader policy are in Nupp through direct FFI. No SDK wrappers or Nupp value/GC/task layouts are added to C.

The fixture shared library is built once, atomically, before parallel guest jobs start. An earlier run exposed per-job relinking races; the complete six-case run above passed after this correction. Unknown/empty explicit selections and unknown transport selectors now fail.

This receipt does not claim the future full inventory/acceptance runner, callback lifetime matrix, all five standalone-core target adapters, Rust source deletion, or the whole compiler building without Rust. Those remain separate delivery work.
