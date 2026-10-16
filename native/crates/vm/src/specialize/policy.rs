//! Tier policy (design, section 1): what a compile does, kept apart from the
//! entry convention it targets. Direct and heap-frame entries are calling
//! conventions, not optimization levels; both policies below lower bytecode
//! through the one Cranelift lowering in `jit.rs`.
use crate::interp::Op;

/// The calling convention a version is compiled for.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum Convention {
    /// C ABI, native nesting, `Interp::entries`; a guard miss takes the
    /// generic helper in place.
    #[default]
    Direct,
    /// A heap frame and a resume pc, `Interp::frame_entries`; a guard miss
    /// leaves through a deopt exit.
    Frame,
}

impl Convention {
    pub fn of(frame: bool) -> Convention { if frame { Convention::Frame } else { Convention::Direct } }
    pub fn frame(self) -> bool { self == Convention::Frame }
    /// The index of this convention's `Versions` in a function's record.
    pub fn index(self) -> usize { self as usize }
    /// What a failed guard does on this convention.
    pub fn miss(self) -> super::facts::MissAction { if self.frame() { super::facts::MissAction::Exit } else { super::facts::MissAction::Generic } }
}

/// What one compile does, independent of its convention.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub struct Policy {
    /// Feedback hooks in generic code: method calls and field stores record
    /// in the helper they call, field reads where their cache missed.
    pub instrument: bool,
    /// Calls an instrumented direct entry counts before it asks for a
    /// specialized version; 0 when something else decides (the heap-frame
    /// driver, the lazy tier's interpreter feedback).
    pub tier_calls: u32,
    /// The specializations this compile may emit.
    pub method: bool,
    pub target: bool,
    pub field: bool,
    pub store: bool,
}

impl Policy {
    /// The generic version, instrumented when specialization is on.
    pub fn generic(instrument: bool, tier_calls: u32) -> Policy { Policy { instrument, tier_calls, ..Policy::default() } }
    /// A specialized version for `convention`. Calls are boundaries on the
    /// heap-frame path, so only field sites specialize there.
    pub fn specialized(convention: Convention) -> Policy {
        let direct = !convention.frame();
        // `JIT_SPEC_KINDS=method,target,field,store` narrows them, for bisection.
        let kinds = std::env::var("JIT_SPEC_KINDS").ok();
        let on = |k: &str| kinds.as_deref().is_none_or(|s| s.split(',').any(|x| x == k));
        Policy { instrument: false, tier_calls: 0, method: direct && on("method"), target: direct && on("target"), field: on("field"), store: on("store") }
    }
    /// Whether this policy specializes `op`.
    pub fn allows(&self, op: &Op) -> bool {
        match op {
            Op::CallMethod(..) => self.method,
            Op::CallDyn(..) => self.target,
            Op::GetField(..) => self.field,
            Op::SetField(..) => self.store,
            _ => false,
        }
    }
    pub fn specializes(&self) -> bool { self.method || self.target || self.field || self.store }
}
