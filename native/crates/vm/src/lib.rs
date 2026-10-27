//! The Nupp runtime (plan: `nupp-runtime.md`, contracts: `nupp-runtime-contracts.md`).
//!
//! Module map, in dependency order: `value` (the 64-bit word), `heap`
//! (objects, shapes, the allocator and the collector), `interp` (tasks,
//! frames, opcodes), `builtins` (the library), `verify` (the image checks
//! and the liveness pass), `image` (the loader) and `host` (the parking
//! surface).
pub mod value;
pub mod numeric;
pub mod os_glue;
#[macro_use]
pub mod opcodes;
mod storage;
mod foreign;
pub mod simd;
mod native_simd;
mod dominance;
mod simd_reduce;
#[cfg(feature = "jit")]
mod simd_jit;
mod simd_exec;
#[cfg(feature = "allocation-metrics")]
mod allocation_metrics;
pub mod heap;
mod heap_trace;
pub mod interp;
pub mod metamethods;
pub mod builtins;
mod clock;
mod datetime;
pub mod fileio;
pub mod nfiles;
#[cfg(feature = "compression")]
pub mod ncompression;
#[cfg(feature = "net")]
pub mod nnet;
#[cfg(feature = "http")]
pub mod nhttp;
#[cfg(feature = "regex")]
mod nregex;
#[cfg(feature = "markdown")]
mod nmarkdown;

// A runtime built without a facility still names its builtins, so an image
// that reaches one loads; the call says which facility this runtime lacks.
#[cfg(not(feature = "compression"))]
pub mod ncompression {
    #[derive(Default)]
    pub struct Streams;
    pub fn call(it: &mut crate::interp::Interp, _: &str, _: &[crate::value::Value]) -> crate::builtins::Outs {
        it.err("this runtime was built without compression")
    }
}
#[cfg(not(feature = "net"))]
pub mod nnet {
    #[derive(Default)]
    pub struct Resources;
    pub fn call(it: &mut crate::interp::Interp, _: &str, _: &[crate::value::Value]) -> crate::builtins::Outs {
        it.err("this runtime was built without networking")
    }
}
#[cfg(not(feature = "http"))]
pub mod nhttp {
    #[derive(Default)]
    pub struct Transfers;
    pub fn call(it: &mut crate::interp::Interp, _: &str, _: &[crate::value::Value]) -> crate::builtins::Outs {
        it.err("this runtime was built without HTTP")
    }
    pub fn parse_uri(it: &mut crate::interp::Interp, _: &[crate::value::Value]) -> crate::builtins::Outs {
        it.err("this runtime was built without HTTP")
    }
}
#[cfg(not(feature = "regex"))]
mod nregex {
    pub fn call(it: &mut crate::interp::Interp, _: &str, _: &[crate::value::Value]) -> crate::builtins::Outs {
        it.err("this runtime was built without regular expressions")
    }
    pub fn install(_: &mut crate::interp::Interp) {}
}
#[cfg(not(feature = "markdown"))]
mod nmarkdown {
    pub fn call(it: &mut crate::interp::Interp, _: &str, _: &[crate::value::Value]) -> crate::builtins::Outs {
        it.err("this runtime was built without Markdown")
    }
}
pub mod utf8lib;
mod temporary;
mod process;
mod stdio;
pub mod verify;
pub mod image;
pub mod graph;
pub mod image_modules;
pub mod hotpatch;
pub mod payload;
pub mod host;
pub mod declaration;
pub mod extension;
pub mod embed;
pub mod threaded;
#[cfg(feature = "native-runtime")]
mod dispatch;
#[cfg(feature = "jit")]
pub mod jit;
#[cfg(feature = "aot")]
pub mod jit_glue;
#[cfg(feature = "aot")]
pub mod native_glue;
#[cfg(feature = "aot")]
pub mod native_jit;

#[cfg(feature = "compiled-runtime")]
pub mod compiled;

pub mod persist;
pub mod snapshot;

pub mod scheduler;

mod frame;

pub mod effects;

mod cleanup;

mod task_api;

pub mod workers;
pub mod supervision;

mod channels;
pub mod sharing;
mod worker_context;

mod coroutines;

mod strbuf;

#[cfg(feature = "c-headers")]
pub mod cdecl;

#[cfg(feature = "jit")]
pub mod specialize;
