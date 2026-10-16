//! The `nupp-vm` runner as a static archive for program binaries; see
//! `Cargo.toml`. `src/main.c` is the executable's entry: it defines an empty
//! `nupp_aot_table` that a program's object replaces.

#[allow(dead_code, unused_imports)]
#[path = "../../vm/src/main.rs"]
mod runner;

/// The runner's `main`, called by `src/main.c`. It reads its arguments from
/// the process as the binary does, and returns only when the runner does.
#[unsafe(no_mangle)]
pub extern "C" fn nupp_vm_program_main() -> i32 {
    runner::main();
    0
}
