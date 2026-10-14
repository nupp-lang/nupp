//! The Nupp runtime (plan: `nupp-runtime.md`, contracts: `nupp-runtime-contracts.md`).
//!
//! Module map, in dependency order: `value` (the 64-bit word), `heap`
//! (objects, shapes, the allocator and the collector), `interp` (tasks,
//! frames, opcodes), `builtins` (the library), `verify` (the image checks
//! and the liveness pass), `image` (the loader) and `host` (the parking
//! surface).
pub mod value;
pub mod numeric;
mod storage;
pub mod simd;
mod native_simd;
mod simd_reduce;
#[cfg(feature = "jit")]
mod simd_jit;
mod simd_exec;
pub mod heap;
pub mod interp;
pub mod builtins;
mod clock;
pub mod fileio;
pub mod verify;
pub mod image;
pub mod host;
pub mod threaded;
#[cfg(feature = "jit")]
pub mod jit;

#[cfg(feature = "compiled-runtime")]
pub mod compiled;

pub mod persist;

pub mod scheduler;

mod frame;

mod cleanup;

mod task_api;

pub mod workers;

mod channels;

mod coroutines;

#[cfg(feature = "c-headers")]
pub mod cdecl;
