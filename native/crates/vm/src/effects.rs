//! What an operation or a runtime helper may do, described once (JIT
//! specialization design, section 1, "Operation effects"). The heap-frame
//! driver asks it which operations transfer a frame (`frame::boundary`), and
//! the typed tier asks it which facts survive an operation.
//!
//! Absent from the transfer class does not mean pure: anything not listed
//! below as known is `UNKNOWN`, which may allocate (and so collect, which can
//! clear weak entries), mutate state compiled code assumed, raise, and run
//! Nupp code. An optimization that needs an operation to be harmless must
//! find it classified here, never infer it from a missing entry.
use crate::interp::Op;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Effects(pub u8);

impl Effects {
    /// Nothing an assumption could observe.
    pub const NONE: Effects = Effects(0);
    /// May allocate, so may run the collector (which may clear weak entries
    /// and so bump `Heap::proto_epoch`).
    pub const ALLOCATES: Effects = Effects(1);
    /// May write state compiled code assumed: a table, a metatable, a
    /// shape's methods.
    pub const MUTATES: Effects = Effects(2);
    /// May raise.
    pub const THROWS: Effects = Effects(4);
    /// May run Nupp code: a call, a metamethod, a callback.
    pub const REENTERS: Effects = Effects(8);
    /// Changes frame ownership, enters arbitrary Nupp code from the driver,
    /// or suspends: a heap-frame boundary.
    pub const TRANSFERS: Effects = Effects(16);
    /// What an unclassified operation or helper is assumed to do.
    pub const UNKNOWN: Effects = Effects(1 | 2 | 4 | 8);

    pub const fn union(self, other: Effects) -> Effects { Effects(self.0 | other.0) }
    pub const fn has(self, other: Effects) -> bool { self.0 & other.0 == other.0 }
    pub const fn transfers(self) -> bool { self.0 & 16 != 0 }
    /// Whether facts about mutable state (what an epoch-guarded lookup
    /// answered) die across it. Permanent facts (a record's shape) survive.
    pub const fn kills_mutable_facts(self) -> bool { self.0 & (1 | 2 | 8 | 16) != 0 }
}

/// The effects of one operation.
pub fn of_op(op: &Op) -> Effects {
    match op {
        // The heap-frame boundaries: the classification `frame::boundary`
        // had as its own list, kept exactly.
        Op::Call(..) | Op::CallT(..) | Op::CallDyn(..) | Op::CallK(..) | Op::CallMethod(..) | Op::PCall(..)
        | Op::Ret(..) | Op::RetN(..) | Op::RetNil | Op::FRet(..) | Op::Park(..) | Op::Checkpoint
        | Op::AffineEnter | Op::AffineMark(..) | Op::CleanupLive(..) | Op::Defer(..) | Op::DeferMethod(..)
        | Op::Disarm(..) | Op::DisarmAt(..) | Op::RearmAt(..) | Op::Unwind(..) | Op::VarargN(..) | Op::VarargTable(..)
        | Op::Require(..) | Op::RequireV(..) => Effects::UNKNOWN.union(Effects::TRANSFERS),
        // Native storage reads and writes left to the driver on that path.
        Op::StorageLen(..) | Op::FLoad(..) | Op::FStore(..) | Op::VLoad(..) | Op::VStore(..) | Op::VLoadM(..) | Op::VStoreM(..) => Effects::THROWS.union(Effects::TRANSFERS),
        // Register moves, constants, typed arithmetic and control flow.
        Op::K(..) | Op::Move(..) | Op::Nil(..) | Op::Jmp(..) | Op::JmpIf(..) | Op::JmpIfNot(..) | Op::JmpIfIZero(..)
        | Op::IJmpIfUle(..) | Op::IJmpIfUlt(..) | Op::Switch(..) | Op::Not(..) | Op::Truthy(..) | Op::BoolFromI(..)
        | Op::IK(..) | Op::IAdd(..) | Op::ISub(..) | Op::IAddK(..) | Op::IAnd(..) | Op::IOr(..) | Op::IXor(..) | Op::INot(..)
        | Op::IShl(..) | Op::IShrU(..) | Op::IMaskU32(..) | Op::IBswap32(..) | Op::IMov(..)
        | Op::ICmpSLt(..) | Op::ICmpSLe(..) | Op::ICmpEq(..) | Op::ICmpNe(..) | Op::ICmpLt(..) | Op::ICmpLe(..)
        | Op::FK(..) | Op::FMov(..) | Op::FAdd(..) | Op::FSub(..) | Op::FMul(..) | Op::FDiv(..) | Op::FNeg(..) | Op::FMod(..) | Op::FFma(..)
        | Op::FCmpEq(..) | Op::FCmpNe(..) | Op::FCmpLe(..) | Op::FCmpLt(..) | Op::IToF(..) | Op::FToI(..) | Op::FBox(..)
        | Op::VMov(..) | Op::VAdd(..) | Op::VMul(..) | Op::VFma(..) | Op::VSplat(..) | Op::VLane(..)
        | Op::LoopFact(..) | Op::GetUpval(..) => Effects::NONE,
        // Reads of a cell or a slot by offset: no Nupp code, no allocation.
        Op::GetCell(..) => Effects::THROWS,
        // Allocation alone.
        Op::NewTable(..) | Op::NewTableN(..) | Op::NewRecord(..) | Op::NewClosure(..) | Op::NewCell(..) | Op::NewBuffer(..) | Op::NewBytes(..)
        | Op::IBox(..) | Op::UBox(..) => Effects::ALLOCATES.union(Effects::THROWS),
        _ => Effects::UNKNOWN,
    }
}

/// The effects of a typed-tier helper, by its name in `compiled::helper_table`.
/// Helpers not listed are `UNKNOWN`.
pub fn of_helper(name: &str) -> Effects {
    match name {
        // Feedback recording and the collector's insertion barrier.
        "j_spec_note_receiver" | "j_spec_barrier" | "j_field_caches" | "j_slot_hash" | "j_last_nres" | "j_frame_poll" | "j_frame_context" | "j_frame_refresh" => Effects::NONE,
        // Counting a miss or an exit may plan and compile a version, which
        // allocates; it never writes program state or runs Nupp code.
        "j_spec_miss" | "j_spec_deopt" | "j_spec_tier_up" => Effects::ALLOCATES,
        "j_new_table" | "j_new_table_sized" | "j_new_record" | "j_new_cell" | "j_new_closure" | "j_ibox" | "j_ubox" | "j_new_buffer" | "j_new_bytes" => Effects::ALLOCATES.union(Effects::THROWS),
        "j_frame_step" | "j_frame_call" | "j_frame_ret" | "j_frame_finish" => Effects::UNKNOWN.union(Effects::TRANSFERS),
        _ => Effects::UNKNOWN,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `frame::boundary`'s own list before it moved here.
    fn old_boundary(op: &Op) -> bool {
        matches!(op, Op::Call(..) | Op::CallT(..) | Op::CallDyn(..) | Op::CallK(..) | Op::StorageLen(..) | Op::FLoad(..) | Op::FStore(..) | Op::VLoad(..) | Op::VStore(..) | Op::VLoadM(..) | Op::VStoreM(..) | Op::CallMethod(..) | Op::PCall(..) | Op::Ret(..) | Op::RetN(..) | Op::RetNil | Op::FRet(..) | Op::Park(..) | Op::Checkpoint | Op::AffineEnter | Op::AffineMark(..) | Op::CleanupLive(..) | Op::Defer(..) | Op::DeferMethod(..) | Op::Disarm(..) | Op::DisarmAt(..) | Op::RearmAt(..) | Op::Unwind(..) | Op::VarargN(..) | Op::VarargTable(..) | Op::Require(..) | Op::RequireV(..))
    }

    #[test]
    fn the_transfer_class_is_the_old_boundary_list() {
        let ops = [
            Op::Call(0, 0, 0), Op::CallT(0, 0, 0, 0), Op::CallDyn(0, 0, 0), Op::CallK(0, 0, 0, 0, 0), Op::StorageLen(0, 0), Op::FLoad(0, 0, 0), Op::FStore(0, 0, 0),
            Op::VLoad(0, 0, 0, 0), Op::VStore(0, 0, 0, 0), Op::VLoadM(0, 0, 0, 0, 0), Op::VStoreM(0, 0, 0, 0, 0), Op::CallMethod(0, 0, 0), Op::PCall(0, 0),
            Op::Ret(0), Op::RetN(0, 0), Op::RetNil, Op::FRet(0), Op::Park(0), Op::Checkpoint, Op::AffineEnter, Op::AffineMark(0, 0), Op::CleanupLive(0, 0),
            Op::Defer(0, 0), Op::DeferMethod(0, 0), Op::Disarm(0), Op::DisarmAt(0), Op::RearmAt(0, 0, 0), Op::Unwind(0), Op::VarargN(0, 0), Op::VarargTable(0),
            Op::Require(0, 0), Op::RequireV(0, 0),
            Op::GetField(0, 0, 0), Op::SetField(0, 0, 0), Op::GetSlot(0, 0, 0, 0), Op::SetSlot(0, 0, 0, 0), Op::Add(0, 0, 0), Op::Move(0, 0), Op::K(0, 0),
            Op::NewTable(0), Op::Concat(0, 0, 0), Op::GetIdx(0, 0, 0), Op::SetIdx(0, 0, 0), Op::Len(0, 0), Op::Eq(0, 0, 0), Op::SetMethod(0, 0, 0), Op::Raise(0),
        ];
        for op in &ops { assert_eq!(of_op(op).transfers(), old_boundary(op), "{op:?}"); }
    }

    #[test]
    fn unclassified_helpers_and_operations_are_unknown() {
        assert_eq!(of_helper("j_call_dyn"), Effects::UNKNOWN);
        assert_eq!(of_helper("something new"), Effects::UNKNOWN);
        assert_eq!(of_op(&Op::GetField(0, 0, 0)), Effects::UNKNOWN);
        assert!(!of_op(&Op::GetField(0, 0, 0)).transfers(), "a field read is not a boundary, and not pure either");
        assert!(of_op(&Op::GetField(0, 0, 0)).kills_mutable_facts());
        assert!(!of_op(&Op::Move(0, 1)).kills_mutable_facts());
        assert!(of_op(&Op::NewTable(0)).kills_mutable_facts(), "allocation may clear weak entries");
    }
}
