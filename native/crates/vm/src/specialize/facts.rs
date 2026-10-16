//! Facts and assumptions (design, section 1). A specialized site records the
//! facts it uses, how each was established, what they depend on and what a
//! failed guard does. Feedback only selects candidates; a fact holds because
//! a guard proved it (or, later, the verifier's types did), never because a
//! site's feedback said so.
use std::collections::HashMap;

use super::policy::Convention;
use super::{Guard, Plan, SiteSpec};
use crate::effects::Effects;
use crate::interp::{Function, Op};

/// How a fact was established.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Proof {
    /// Proved by types before the run (none of today's specializations).
    Static,
    /// Proved by the guard of the site at `pc`.
    Guard { pc: usize },
}

/// What an assumption depends on, beyond the operand its guard reads.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Dependency {
    /// A record shape: permanent once proved for a value (contracts 2.5).
    Shape(u32),
    /// `Heap::proto_epoch` at planning: what shape descriptors and `__index`
    /// chains answered. Mutable; rechecked at every use.
    ProtoEpoch(u64),
    /// A metatable's identity, compared live (its free bumps the epoch).
    Metatable(u64),
    /// A callee closure's (or function value's) function id.
    Callee(u32),
    /// A callee's entry, loaded at every call: re-tiering and hot patches are
    /// seen at the next call.
    Entry(u32),
    /// `Heap::marking`, read at every store for the barrier.
    Marking,
}

/// What a failed guard does.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MissAction {
    /// Count the miss and take the generic helper in place (direct entries).
    Generic,
    /// Leave through a deopt exit at the operation's pc (heap-frame entries).
    Exit,
}

/// A fact the code after a guard may use.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FactKind {
    /// The register's value is a record of the shape.
    Shape(u32),
    /// `Heap::proto_epoch` still had this value.
    Epoch(u64),
}

impl FactKind {
    /// Permanent facts survive operations that may mutate or reenter; only a
    /// new value in the register (or the end of the block, or a frame
    /// transfer) ends them.
    pub fn permanent(self) -> bool { matches!(self, FactKind::Shape(_)) }
}

/// One specialized site's assumption.
#[derive(Clone, Debug, PartialEq)]
pub struct Assumption {
    pub pc: usize,
    /// Guard cases the site tries.
    pub cases: usize,
    pub deps: Vec<Dependency>,
    pub miss: MissAction,
    /// The fact the site leaves for later code: (register, fact).
    pub establishes: Option<(u8, FactKind)>,
}

/// The assumption a planned site stands for, or why the plan is malformed.
pub fn assumption(spec: &SiteSpec, pc: usize, op: &Op, epoch: u64, convention: Convention) -> Result<Assumption, String> {
    let miss = convention.miss();
    let (cases, deps, establishes) = match (spec, op) {
        (SiteSpec::Method(cases), Op::CallMethod(..)) => {
            let mut deps = vec![Dependency::ProtoEpoch(epoch)];
            for c in cases {
                match c.guard {
                    Guard::Shape(s) => deps.push(Dependency::Shape(s)),
                    Guard::Meta(m) => deps.push(Dependency::Metatable(m)),
                    Guard::RecordMeta { shape, meta, .. } => { deps.push(Dependency::Shape(shape)); deps.push(Dependency::Metatable(meta)); }
                }
                deps.push(Dependency::Entry(c.fid));
            }
            (cases.len(), deps, None)
        }
        (SiteSpec::Target { fid, .. }, Op::CallDyn(..)) => (1, vec![Dependency::Callee(*fid), Dependency::Entry(*fid)], None),
        (SiteSpec::Field(cases), Op::GetField(_, t, _)) => {
            let deps = cases.iter().map(|&(s, _)| Dependency::Shape(s)).collect();
            // Only a site that cannot fall through proves a shape for later code.
            let est = (miss == MissAction::Exit && cases.len() == 1).then(|| (*t, FactKind::Shape(cases[0].0)));
            (cases.len(), deps, est)
        }
        (SiteSpec::Store { shape, .. }, Op::SetField(t, _, _)) => {
            let est = (miss == MissAction::Exit).then(|| (*t, FactKind::Shape(*shape)));
            (1, vec![Dependency::Shape(*shape), Dependency::Marking], est)
        }
        (spec, op) => return Err(format!("pc {pc}: a {} specialization at {op:?}", spec.kind())),
    };
    if cases == 0 { return Err(format!("pc {pc}: a guard with no cases")); }
    // Calls are boundaries on the heap-frame path: nothing to exit from.
    if convention.frame() && matches!(spec, SiteSpec::Method(_) | SiteSpec::Target { .. }) {
        return Err(format!("pc {pc}: a {} specialization in a heap-frame entry", spec.kind()));
    }
    Ok(Assumption { pc, cases, deps, miss, establishes })
}

/// Checks a plan against the function it was made for before anything is
/// compiled: each site's operation and kind agree, its guards and
/// dependencies are named, its miss action fits the convention, the body is
/// the one planned, and a heap-frame exit has a live-value description.
pub fn validate(plan: &Plan, f: &Function, body: u64) -> Result<Vec<Assumption>, String> {
    if plan.body != body { return Err(format!("{}: planned for body {}, the function now has body {body}", f.name, plan.body)); }
    let live = plan.convention.frame().then(|| crate::verify::liveness(f).0);
    let mut out = Vec::new();
    let mut pcs: Vec<_> = plan.sites.keys().copied().collect();
    pcs.sort();
    for pc in pcs {
        let op = f.code.get(pc).ok_or_else(|| format!("{}: a site past the code at {pc}", f.name))?;
        if !plan.policy.allows(op) { return Err(format!("{}: pc {pc}: the policy does not specialize {op:?}", f.name)); }
        let a = assumption(&plan.sites[&pc], pc, op, plan.epoch, plan.convention)?;
        if a.deps.is_empty() { return Err(format!("{}: pc {pc}: an assumption with no dependency", f.name)); }
        if a.miss == MissAction::Exit && live.as_ref().is_none_or(|l| l.get(pc).is_none()) { return Err(format!("{}: pc {pc}: an exit with no live-value description", f.name)); }
        out.push(a);
    }
    Ok(out)
}

/// A use of a fact the lowering made, kept so a compile can be checked: the
/// guard that established it must dominate the use.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FactUse {
    pub reg: Option<u8>,
    pub established: usize,
    pub established_block: usize,
    pub used: usize,
    pub used_block: usize,
}

/// The facts the lowering holds at the current operation. Facts belong to a
/// value: a register's facts end when it is redefined. Facts are kept within
/// a basic block only: every block start clears them, as a join could bring
/// in a value no guard proved (propagation through joins is not built).
#[derive(Default)]
pub struct Facts {
    regs: HashMap<u8, (FactKind, Proof, usize)>,
    epoch: Option<(u64, Proof, usize)>,
    block: usize,
    pub uses: Vec<FactUse>,
}

impl Facts {
    pub fn block_start(&mut self, pc: usize) { self.regs.clear(); self.epoch = None; self.block = pc; }
    /// A new value in `reg`.
    pub fn define(&mut self, reg: u8) { if !self.regs.is_empty() { self.regs.remove(&reg); } }
    /// A frame transfer reloaded the frame: nothing proved before survives.
    pub fn transfer(&mut self) { self.regs.clear(); self.epoch = None; }
    /// After an operation with these effects: mutable facts end if it may
    /// mutate, reenter, allocate (weak entries) or transfer.
    pub fn after(&mut self, effects: Effects) {
        if self.regs.is_empty() && self.epoch.is_none() { return; }
        if effects.transfers() { return self.transfer(); }
        if effects.kills_mutable_facts() {
            self.epoch = None;
            self.regs.retain(|_, (k, _, _)| k.permanent());
        }
    }
    pub fn establish(&mut self, reg: u8, kind: FactKind, pc: usize) {
        match kind { FactKind::Epoch(e) => self.epoch = Some((e, Proof::Guard { pc }, self.block)), _ => { self.regs.insert(reg, (kind, Proof::Guard { pc }, self.block)); } }
    }
    /// The shape proved for `reg`, recording the use at `pc`.
    pub fn shape(&mut self, reg: u8, pc: usize) -> Option<u32> {
        let (kind, proof, block) = *self.regs.get(&reg)?;
        let FactKind::Shape(s) = kind else { return None };
        let established = match proof { Proof::Guard { pc } => pc, Proof::Static => block };
        self.uses.push(FactUse { reg: Some(reg), established, established_block: block, used: pc, used_block: self.block });
        Some(s)
    }
    /// Whether the epoch is known to still be `e` at `pc`, recording the use.
    pub fn epoch(&mut self, e: u64, pc: usize) -> bool {
        let Some((known, proof, block)) = self.epoch else { return false };
        if known != e { return false; }
        let established = match proof { Proof::Guard { pc } => pc, Proof::Static => block };
        self.uses.push(FactUse { reg: None, established, established_block: block, used: pc, used_block: self.block });
        true
    }
}

/// Every recorded use was established earlier in the same block, which
/// dominates it within straight-line code.
pub fn check_dominance(uses: &[FactUse]) -> Result<(), String> {
    for u in uses {
        if u.established_block != u.used_block || u.established >= u.used { return Err(format!("a fact used at {} was established at {} in another block or later", u.used, u.established)); }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::effects::{of_helper, of_op};

    #[test]
    fn effects_end_mutable_facts_and_definitions_end_all_of_a_register() {
        let mut f = Facts::default();
        f.block_start(0);
        f.establish(1, FactKind::Shape(7), 1);
        f.establish(0, FactKind::Epoch(3), 1);
        f.after(of_op(&Op::Move(2, 3)));
        assert_eq!(f.shape(1, 2), Some(7));
        assert!(f.epoch(3, 2), "a register move mutates nothing");
        f.after(of_op(&Op::SetField(4, 0, 5)));
        assert!(!f.epoch(3, 4), "a store may change what the epoch guarded");
        assert_eq!(f.shape(1, 4), Some(7), "a shape is permanent");
        f.establish(0, FactKind::Epoch(3), 5);
        f.after(of_helper("a helper nobody classified"));
        assert!(!f.epoch(3, 6), "an unknown helper is assumed to mutate and reenter");
        f.after(of_op(&Op::NewTable(6)));
        assert_eq!(f.shape(1, 7), Some(7));
        f.define(1);
        assert_eq!(f.shape(1, 8), None, "a new value in the register has no facts");
        f.establish(2, FactKind::Shape(9), 8);
        f.after(of_op(&Op::CallDyn(0, 0, 0)));
        assert_eq!(f.shape(2, 9), None, "a frame transfer reloads every register");
        f.establish(2, FactKind::Shape(9), 9);
        f.block_start(10);
        assert_eq!(f.shape(2, 10), None, "facts do not cross a join");
        assert!(check_dominance(&f.uses).is_ok());
    }

    #[test]
    fn a_use_outside_its_guards_block_fails_the_check() {
        let bad = [FactUse { reg: Some(1), established: 3, established_block: 0, used: 5, used_block: 4 }];
        assert!(check_dominance(&bad).is_err());
        let late = [FactUse { reg: Some(1), established: 6, established_block: 0, used: 5, used_block: 0 }];
        assert!(check_dominance(&late).is_err());
    }
}
