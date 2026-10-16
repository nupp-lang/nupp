//! Version lifetime (design, section 1). A compile returns a `Version`:
//! which body and convention it is for, the policy it was compiled under, its
//! code range and whether its stack maps were registered, its dependencies,
//! its recovery points and the feedback record it embeds addresses of.
//! Compiling, validating and publishing are separate steps: `install` checks
//! the record against the VM before any entry points at it, and refuses a
//! stale one, which leaves the generic entry (or the interpreter) in place.
//!
//! Nothing a version owns is freed before VM teardown: its code stays in the
//! JIT module (`Compiler::free`'s condition), its stack maps in `CODE_MAPS`,
//! and a feedback record its code counts into stays alive in `State::retired`
//! even after the function's feedback is reset. Retained bytes stay charged
//! to `Limits::code_bytes`, past which no more specialized versions compile.
use super::facts::Dependency;
use super::policy::{Convention, Policy};
use super::recovery::FrameState;

/// Machine code a compile produced.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CompiledCode {
    /// What callers enter: the boxed wrapper of a typed signature, else the
    /// function itself.
    pub entry: u64,
    /// The function's own code range.
    pub start: usize,
    pub len: usize,
    /// Stack-map entries, and whether they were registered in `CODE_MAPS`
    /// (they must be before anything can call the code).
    pub maps: usize,
    pub registered: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub enum VersionState {
    /// Compiled, not yet installed.
    Ready,
    /// The function's current entry for its convention.
    Installed,
    /// Replaced, settled away from, or invalidated: no new entries, but code
    /// that is running or holds its address may still use it.
    Retired,
    /// Install found it stale; it never became an entry.
    Refused(String),
}

#[derive(Clone, Debug)]
pub struct Version {
    pub id: u32,
    pub fid: u32,
    pub body: u64,
    pub convention: Convention,
    pub policy: Policy,
    pub code: CompiledCode,
    pub deps: Vec<Dependency>,
    pub sites: usize,
    pub recovery: Vec<FrameState>,
    /// The `FuncFeedback` record instrumented code counts into, or 0.
    pub feedback: usize,
    pub state: VersionState,
}

impl Version {
    /// What retaining it costs: its code and an estimate of its metadata.
    pub fn bytes(&self) -> usize {
        let recovery: usize = self.recovery.iter().map(|s| std::mem::size_of::<FrameState>() + s.recipes.len() * std::mem::size_of::<super::recovery::Recipe>()).sum();
        self.code.len + self.code.maps * 16 + std::mem::size_of::<Version>() + self.deps.len() * std::mem::size_of::<Dependency>() + recovery
    }
    pub fn generic(&self) -> bool { !self.policy.specializes() }
}

/// Why `install` refused a version.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum InstallError {
    /// Its stack maps were not registered before publication.
    NotRegistered,
    /// The function's body changed since it was planned.
    StaleBody,
    /// A dependency no longer holds (the epoch moved, a metatable died).
    StaleDependency(Dependency),
}
