//! Recoverable state (design, section 1): one description of a single heap
//! frame at a pc, and the recipes that write every live value into it. The
//! boundary spills, backedge polls and deopt exits of heap-frame entries all
//! emit their stores from it (`jit.rs`, `spill_state!`). GC stack maps stay
//! Cranelift's physical-location metadata; this is the logical description,
//! and the two must agree on which values are references.
use crate::interp::{Function, HDR};
use crate::verify::RegSet;

/// A register class of the frame (5.1): its window and representation.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Class {
    /// A NaN-boxed value word: numbers, references, booleans, nil.
    Value,
    /// A typed `i64`.
    Int,
    /// A typed `f64`.
    Float,
    /// A two-lane `f64` vector: two words.
    Vector,
}

/// Write one live register into the frame. Every recipe today stores the
/// register as it is held; a representation the frame lacks would add a
/// recipe that computes (boxing an unboxed float, allocating an exact
/// integer), which must run with every live reference already rooted.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Recipe {
    pub class: Class,
    pub reg: u8,
    /// Offset from the frame's start, in words.
    pub word: usize,
}

/// Why a frame is written back.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Point {
    /// A boundary operation, stepped by the interpreter.
    Boundary,
    /// A backedge poll that may yield the turn.
    Poll,
    /// A guard that failed: the interpreter runs the operation generically.
    Exit,
}

/// One frame at one pc: the function and body it belongs to, the resume pc,
/// whether that pc is before the operation (so recovery cannot replay one of
/// its effects), and a recipe per live register. The closure (header word
/// 2), varargs below the header, cleanups and protected calls are already the
/// frame's and the task's, so no recipe is needed for them.
#[derive(Clone, Debug, PartialEq)]
pub struct FrameState {
    pub fid: u32,
    pub body: u64,
    pub pc: usize,
    pub point: Point,
    pub before_op: bool,
    pub recipes: Vec<Recipe>,
}

impl FrameState {
    /// The frame of `f` at `pc` with `live` (one set per class) live.
    pub fn at(f: &Function, fid: u32, body: u64, pc: usize, point: Point, live: &[RegSet; 4]) -> FrameState {
        let mut recipes = Vec::new();
        for (class, set, off, stride) in [(Class::Value, &live[0], HDR, 1), (Class::Int, &live[1], f.off_i(), 1), (Class::Float, &live[2], f.off_f(), 1), (Class::Vector, &live[3], f.off_v(), 2)] {
            let count = match class { Class::Value => f.nregs as usize + 1, Class::Int => f.nireg as usize, Class::Float => f.nfreg as usize, Class::Vector => f.nvreg as usize };
            for reg in 0..count { if set.contains(reg as u8) { recipes.push(Recipe { class, reg: reg as u8, word: off + stride * reg }); } }
        }
        // Every point a heap-frame entry writes back is before its operation:
        // a boundary is stepped from its own pc, a poll precedes the
        // backedge, an exit precedes every effect of the guarded operation.
        FrameState { fid, body, pc, point, before_op: true, recipes }
    }
    pub fn classes(&self) -> impl Iterator<Item = Class> + '_ { self.recipes.iter().map(|r| r.class) }
}
