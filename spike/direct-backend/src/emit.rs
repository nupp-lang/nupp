//! Machine IR plus allocations to AArch64 code. The prologue saves only the
//! callee-saved registers the allocator actually used; blocks that are a bare
//! jump with no edits are forwarded away; branches to the next block fall
//! through.

use crate::asm::{self, Asm, Label, FP, LR, SP};
use crate::mir::{Func, Op};
use regalloc2::{Allocation, Block, Edit, Function, InstOrEdit, MachineEnv, Output, PReg, PRegSet, RegClass};

/// Scratch registers the emitter may use inside one machine-IR instruction.
/// Neither is allocatable; x17 and v31 are the allocator's move scratch.
const XS: u32 = 16;
const VS: u32 = 30;

/// With `partitioned`, used by functions that call out: doubles live in the
/// Float class over v0-v14 (d8-d14 survive a call) and vectors in the Vector
/// class over v16-v29 (nothing survives a call). Without it, every vector
/// register is one Float class, which leaf kernels want.
pub fn machine_env_for(partitioned: bool) -> MachineEnv {
    if !partitioned {
        return machine_env();
    }
    let mut int_pref = PRegSet::empty();
    let mut int_non = PRegSet::empty();
    let (mut f_pref, mut f_non, mut v_pref) = (PRegSet::empty(), PRegSet::empty(), PRegSet::empty());
    for r in 0..16 {
        int_pref.add(PReg::new(r, RegClass::Int));
    }
    for r in 19..29 {
        int_non.add(PReg::new(r, RegClass::Int));
    }
    for r in 0..8 {
        f_pref.add(PReg::new(r, RegClass::Float));
    }
    if std::env::var("NUPP_SPIKE_NO_D8").is_err() {
        for r in 8..15 {
            f_non.add(PReg::new(r, RegClass::Float));
        }
    }
    for r in 16..30 {
        v_pref.add(PReg::new(r, RegClass::Vector));
    }
    MachineEnv {
        preferred_regs_by_class: [int_pref, f_pref, v_pref],
        non_preferred_regs_by_class: [int_non, f_non, PRegSet::empty()],
        scratch_by_class: [
            Some(PReg::new(17, RegClass::Int)),
            Some(PReg::new(15, RegClass::Float)),
            Some(PReg::new(31, RegClass::Vector)),
        ],
        fixed_stack_slots: vec![],
    }
}

pub fn machine_env() -> MachineEnv {
    let mut int_pref = PRegSet::empty();
    let mut int_non = PRegSet::empty();
    let mut f_pref = PRegSet::empty();
    let mut f_non = PRegSet::empty();
    for r in 0..16 {
        int_pref.add(PReg::new(r, RegClass::Int));
    }
    for r in 19..29 {
        int_non.add(PReg::new(r, RegClass::Int));
    }
    for r in (0..8).chain(16..30) {
        f_pref.add(PReg::new(r, RegClass::Float));
    }
    for r in 8..16 {
        f_non.add(PReg::new(r, RegClass::Float));
    }
    MachineEnv {
        preferred_regs_by_class: [int_pref, f_pref, PRegSet::empty()],
        non_preferred_regs_by_class: [int_non, f_non, PRegSet::empty()],
        scratch_by_class: [Some(PReg::new(17, RegClass::Int)), Some(PReg::new(31, RegClass::Float)), None],
        fixed_stack_slots: vec![],
    }
}

/// NZCV flags under which `cond` is false: what a conditional compare sets
/// when its own condition already failed.
fn false_flags(cond: u32) -> u32 {
    use crate::asm::cond::*;
    match cond {
        NE | GT => 0b0100,
        LO | LS => 0b0010,
        GE => 0b1000,
        _ => 0,
    }
}

pub struct Stats {
    pub words: usize,
    pub spill_slots: usize,
    pub moves: usize,
    pub saved: usize,
}

/// What an unwinder needs to walk one generated frame: the prologue is
/// `stp x29, x30, [sp, #-16]!; mov x29, sp; sub sp, sp, #frame` and then the
/// callee-saved stores, so after `prologue_end` the CFA is `x29 + 16` and each
/// saved register sits at a fixed CFA offset.
pub struct Frame {
    pub prologue_end: u32,
    /// DWARF register number and CFA-relative offset of each saved register.
    pub saved: Vec<(u16, i32)>,
}

pub struct Emitted {
    pub layout: asm::Layout,
    pub stats: Stats,
    pub frame: Frame,
}

fn reg(a: Allocation) -> u32 {
    a.as_reg().expect("operand in a register").hw_enc() as u32
}

pub fn emit(func: &Func, out: &Output) -> (Vec<u8>, Stats) {
    let e = emit_image(func, out);
    (e.layout.bytes, e.stats)
}

pub fn emit_image(func: &Func, out: &Output) -> Emitted {
    // Callee-saved registers the allocation touched.
    let mut saved_x = std::collections::BTreeSet::new();
    let mut saved_d = std::collections::BTreeSet::new();
    let mut note = |a: &Allocation| {
        if let Some(p) = a.as_reg() {
            let n = p.hw_enc() as u32;
            match p.class() {
                RegClass::Int if (19..29).contains(&n) => {
                    saved_x.insert(n);
                }
                RegClass::Float if (8..16).contains(&n) => {
                    saved_d.insert(n);
                }
                _ => {}
            }
        }
    };
    out.allocs.iter().for_each(&mut note);
    let mut moves = 0;
    for (_, Edit::Move { from, to }) in &out.edits {
        note(from);
        note(to);
        moves += 1;
    }
    let saved: Vec<(u32, bool)> =
        saved_x.iter().map(|r| (*r, false)).chain(saved_d.iter().map(|r| (*r, true))).collect();
    let spill_bytes = (out.num_spillslots * 8 + 15) & !15;
    let locals_base = spill_bytes;
    let locals_bytes = ((func.locals as usize) + 15) & !15;
    let save_base = spill_bytes + locals_bytes;
    let save_bytes = (saved.len() * 8 + 15) & !15;
    let frame = (spill_bytes + locals_bytes + save_bytes) as u32;

    let mut a = Asm::new();
    let prologue = |a: &mut Asm| {
        a.emit(asm::stp_x_pre(FP, LR, SP, -16));
        a.emit(asm::mov_from_sp(FP));
        if frame > 0 {
            a.emit(asm::sub_sp(frame));
        }
        for (k, (r, d)) in saved.iter().enumerate() {
            let off = (save_base + k * 8) as u32;
            a.emit(if *d { asm::str_d_imm(*r, SP, off) } else { asm::str_x_imm(*r, SP, off) });
        }
    };
    let epilogue = |a: &mut Asm| {
        for (k, (r, d)) in saved.iter().enumerate() {
            let off = (save_base + k * 8) as u32;
            a.emit(if *d { asm::ldr_d_imm(*r, SP, off) } else { asm::ldr_x_imm(*r, SP, off) });
        }
        if frame > 0 {
            a.emit(asm::add_sp(frame));
        }
        a.emit(asm::ldp_x_post(FP, LR, SP, 16));
        a.emit(asm::ret());
    };
    let slot = |a: Allocation| (a.as_stack().unwrap().index() * 8) as u32;

    // Which blocks are a bare jump with no edits: forward their label.
    let nblocks = func.num_blocks();
    let mut forward: Vec<Option<usize>> = vec![None; nblocks];
    for b in 0..nblocks {
        let block = Block::new(b);
        let items: Vec<_> = out.block_insts_and_edits(func, block).collect();
        if b != 0 && items.len() == 1 {
            if let InstOrEdit::Inst(i) = items[0] {
                let inst = &func.insts[i.index()];
                // With no edits in the block, any arguments are already in
                // place: the jump is pure control and can be forwarded.
                if matches!(inst.op, Op::Jump) {
                    forward[b] = Some(inst.succs[0].index());
                }
            }
        }
    }
    let resolve = |mut b: usize| {
        while let Some(n) = forward[b] {
            b = n;
        }
        b
    };
    let labels: Vec<Label> = (0..nblocks).map(|_| a.label()).collect();
    let emitted: Vec<usize> = (0..nblocks).filter(|b| forward[*b].is_none()).collect();

    prologue(&mut a);
    let prologue_end = a.here() as u32;
    // x29 = CFA - 16 and sp = x29 - frame, so [sp + off] is CFA - 16 - frame + off.
    let frame_info = Frame {
        prologue_end,
        saved: saved
            .iter()
            .enumerate()
            .map(|(k, (r, d))| {
                let dwarf = if *d { 64 + *r as u16 } else { *r as u16 };
                (dwarf, -16 - frame as i32 + (save_base + k * 8) as i32)
            })
            .collect(),
    };
    for (pos, &b) in emitted.iter().enumerate() {
        let next = emitted.get(pos + 1).copied();
        a.bind(labels[b]);
        for item in out.block_insts_and_edits(func, Block::new(b)) {
            match item {
                InstOrEdit::Edit(Edit::Move { from, to }) => {
                    let class = from.as_reg().map(|r| r.class()).or(to.as_reg().map(|r| r.class())).unwrap();
                    let float = class != RegClass::Int;
                    // In a partitioned function the Float class holds only
                    // doubles: move them as doubles, which also clears the
                    // upper half of the destination.
                    let scalar = func.partitioned && class == RegClass::Float;
                    match (from.as_reg(), to.as_reg()) {
                        (Some(f), Some(t)) if scalar && std::env::var("NUPP_SPIKE_QMOVE").is_err() => {
                            a.emit(asm::fmov_d(t.hw_enc() as u32, f.hw_enc() as u32))
                        }
                        (Some(f), Some(t)) => a.emit(if float {
                            asm::mov_16b(t.hw_enc() as u32, f.hw_enc() as u32)
                        } else {
                            asm::mov_reg(true, t.hw_enc() as u32, f.hw_enc() as u32)
                        }),
                        (Some(f), None) => a.emit(if float {
                            asm::str_q_imm(f.hw_enc() as u32, SP, slot(*to))
                        } else {
                            asm::str_x_imm(f.hw_enc() as u32, SP, slot(*to))
                        }),
                        (None, Some(t)) => a.emit(if float {
                            asm::ldr_q_imm(t.hw_enc() as u32, SP, slot(*from))
                        } else {
                            asm::ldr_x_imm(t.hw_enc() as u32, SP, slot(*from))
                        }),
                        (None, None) => unreachable!("stack-to-stack move"),
                    }
                }
                InstOrEdit::Inst(i) => {
                    let inst = &func.insts[i.index()];
                    let r: Vec<u32> = out.inst_allocs(i).iter().map(|x| reg(*x)).collect();
                    let target = |k: usize| resolve(inst.succs[k].index());
                    // A two-way branch: fall through to whichever successor
                    // comes next, inverting the condition when needed.
                    let two_way = |a: &mut Asm, cond: u32| {
                        let (t, f) = (target(0), target(1));
                        if Some(t) == next {
                            a.b_cond(cond ^ 1, labels[f]);
                        } else {
                            a.b_cond(cond, labels[t]);
                            if Some(f) != next {
                                a.b(labels[f]);
                            }
                        }
                    };
                    match &inst.op {
                        Op::Args => {}
                        Op::Ret => epilogue(&mut a),
                        Op::Imm { value } => {
                            let v = *value;
                            a.emit(asm::movz(true, r[0], (v & 0xFFFF) as u32, 0));
                            for hw in 1..4 {
                                let part = ((v >> (16 * hw)) & 0xFFFF) as u32;
                                if part != 0 {
                                    a.emit(asm::movk(true, r[0], part, hw));
                                }
                            }
                        }
                        Op::LitD { bits } => {
                            let mut bytes = [0u8; 16];
                            bytes[..8].copy_from_slice(&bits.to_le_bytes());
                            a.ldr_literal(r[0], bytes, false);
                        }
                        Op::LitQ { bytes } => a.ldr_literal(r[0], *bytes, true),
                        Op::Add { sf } => a.emit(asm::add_reg(*sf, r[0], r[1], r[2], 0)),
                        Op::Sub { sf } => a.emit(asm::sub_reg(*sf, r[0], r[1], r[2])),
                        Op::AddImm { sf, imm } => a.emit(asm::add_imm(*sf, r[0], r[1], *imm)),
                        Op::AddrIdx => a.emit(asm::add_reg(true, r[0], r[1], r[2], 3)),
                        Op::UcvtfW => a.emit(asm::ucvtf_d_w(r[0], r[1])),
                        Op::ScvtfW => a.emit(asm::scvtf_d_w(r[0], r[1])),
                        Op::FcvtzsW => a.emit(asm::fcvtzs_w_d(r[0], r[1])),
                        Op::UcvtfX => a.emit(asm::ucvtf_d_x(r[0], r[1])),
                        Op::FcvtzuW => a.emit(asm::fcvtzu_w_d(r[0], r[1])),
                        Op::FAdd => a.emit(asm::fadd_d(r[0], r[1], r[2])),
                        Op::FSub => a.emit(asm::fsub_d(r[0], r[1], r[2])),
                        Op::FMul => a.emit(asm::fmul_d(r[0], r[1], r[2])),
                        Op::VFAdd => a.emit(asm::fadd_2d(r[0], r[1], r[2])),
                        Op::VFMul => a.emit(asm::fmul_2d(r[0], r[1], r[2])),
                        Op::VFCmGt => a.emit(asm::fcmgt_2d(r[0], r[1], r[2])),
                        Op::VAnd => a.emit(asm::and_16b(r[0], r[1], r[2])),
                        Op::VCmHi => a.emit(asm::cmhi_2d(r[0], r[1], r[2])),
                        Op::Bsl => {
                            debug_assert_eq!(r[0], r[1]);
                            a.emit(asm::bsl_16b(r[0], r[2], r[3]));
                        }
                        Op::DupD => a.emit(asm::dup_2d_elem0(r[0], r[1])),
                        Op::DupX => a.emit(asm::dup_2d_x(r[0], r[1])),
                        Op::SumPair => {
                            a.emit(asm::fadd_2d(VS, r[1], r[2]));
                            a.emit(asm::faddp_d(r[0], VS));
                        }
                        Op::LdrIdx => a.emit(asm::ldr_d_idx(r[0], r[1], r[2])),
                        Op::StrIdx => a.emit(asm::str_d_idx(r[0], r[1], r[2])),
                        Op::Ldp { off } => a.emit(asm::ldp_q(r[0], r[1], r[2], *off)),
                        Op::Stp { off } => a.emit(asm::stp_q(r[0], r[1], r[2], *off)),
                        Op::MaskedLoad => {
                            let (lo, hi, addr, m0, m1) = (r[0], r[1], r[2], r[3], r[4]);
                            a.emit(asm::movi_2d_zero(lo));
                            a.emit(asm::movi_2d_zero(hi));
                            for k in 0..4u32 {
                                let (m, dst, j) = if k < 2 { (m0, lo, k) } else { (m1, hi, k - 2) };
                                let skip = a.label();
                                a.emit(asm::umov_x_d(XS, m, j));
                                a.cbz(XS, skip);
                                a.emit(asm::ldr_d_imm(VS, addr, 8 * k));
                                a.emit(asm::ins_d(dst, j, VS));
                                a.bind(skip);
                            }
                        }
                        Op::LoadV { .. }
                        | Op::StoreV { .. }
                        | Op::MaskLoadV
                        | Op::MaskStoreV
                        | Op::SumV
                        | Op::AnyV
                        | Op::LitY { .. }
                        | Op::Blend => panic!("x86 operation in AArch64 emission"),
                        Op::Call { import } => {
                            a.ldr_slot(XS, *import);
                            a.emit(asm::blr(XS));
                        }
                        Op::FrameAddr { off } => a.emit(asm::add_imm(true, r[0], SP, locals_base as u32 + *off)),
                        Op::LdrX { off } => a.emit(asm::ldr_x_imm(r[0], r[1], *off)),
                        Op::AdrData { bytes } => a.adr_data(r[0], bytes),
                        Op::TailLoad => {
                            let (lo, hi, addr, n) = (r[0], r[1], r[2], r[3]);
                            let (full, lt2, done) = (a.label(), a.label(), a.label());
                            a.emit(asm::movi_2d_zero(lo));
                            a.emit(asm::movi_2d_zero(hi));
                            a.emit(asm::cmp_imm(true, n, 4));
                            a.b_cond(asm::cond::HS, full);
                            a.emit(asm::cmp_imm(true, n, 2));
                            a.b_cond(asm::cond::LO, lt2);
                            a.emit(asm::ldr_q_imm(lo, addr, 0));
                            a.emit(asm::cmp_imm(true, n, 3));
                            a.b_cond(asm::cond::LO, done);
                            a.emit(asm::ldr_d_imm(hi, addr, 16));
                            a.b(done);
                            a.bind(lt2);
                            a.cbz(n, done);
                            a.emit(asm::ldr_d_imm(lo, addr, 0));
                            a.b(done);
                            a.bind(full);
                            a.emit(asm::ldp_q(lo, hi, addr, 0));
                            a.bind(done);
                        }
                        Op::TailStore => {
                            let (lo, hi, addr, n) = (r[0], r[1], r[2], r[3]);
                            let (full, lt2, done) = (a.label(), a.label(), a.label());
                            a.emit(asm::cmp_imm(true, n, 4));
                            a.b_cond(asm::cond::HS, full);
                            a.emit(asm::cmp_imm(true, n, 2));
                            a.b_cond(asm::cond::LO, lt2);
                            a.emit(asm::str_q_imm(lo, addr, 0));
                            a.emit(asm::cmp_imm(true, n, 3));
                            a.b_cond(asm::cond::LO, done);
                            a.emit(asm::str_d_imm(hi, addr, 16));
                            a.b(done);
                            a.bind(lt2);
                            a.cbz(n, done);
                            a.emit(asm::str_d_imm(lo, addr, 0));
                            a.b(done);
                            a.bind(full);
                            a.emit(asm::stp_q(lo, hi, addr, 0));
                            a.bind(done);
                        }
                        Op::MaskedStore => {
                            let (lo, hi, addr, m0, m1) = (r[0], r[1], r[2], r[3], r[4]);
                            for k in 0..4u32 {
                                let (m, src, j) = if k < 2 { (m0, lo, k) } else { (m1, hi, k - 2) };
                                let skip = a.label();
                                a.emit(asm::umov_x_d(XS, m, j));
                                a.cbz(XS, skip);
                                a.emit(asm::dup_d_elem(VS, src, j));
                                a.emit(asm::str_d_imm(VS, addr, 8 * k));
                                a.bind(skip);
                            }
                        }
                        Op::Jump => {
                            let t = target(0);
                            if Some(t) != next {
                                a.b(labels[t]);
                            }
                        }
                        Op::CmpBr { sf, cond } => {
                            a.emit(asm::cmp_reg(*sf, r[0], r[1]));
                            two_way(&mut a, *cond);
                        }
                        Op::FCmpBr { cond } => {
                            a.emit(asm::fcmp_d(r[0], r[1]));
                            two_way(&mut a, *cond);
                        }
                        Op::CmpAndBr { sf, c1, c2 } => {
                            a.emit(asm::cmp_reg(*sf, r[0], r[1]));
                            a.emit(asm::ccmp_reg(*sf, r[2], r[3], false_flags(*c2), *c1));
                            two_way(&mut a, *c2);
                        }
                        Op::FCmpAndBr { c1, c2 } => {
                            a.emit(asm::fcmp_d(r[0], r[1]));
                            a.emit(asm::fccmp_d(r[2], r[3], false_flags(*c2), *c1));
                            two_way(&mut a, *c2);
                        }
                        Op::AnyBr => {
                            a.emit(asm::orr_16b(VS, r[0], r[1]));
                            a.emit(asm::addp_d(VS, VS));
                            a.emit(asm::fmov_x_d(XS, VS));
                            let (t, f) = (target(0), target(1));
                            if Some(t) == next {
                                a.cbz(XS, labels[f]);
                            } else {
                                a.cbnz(XS, labels[t]);
                                if Some(f) != next {
                                    a.b(labels[f]);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    let layout = a.finish_layout(func.imports.len());
    let stats = Stats { words: layout.code_len / 4, spill_slots: out.num_spillslots, moves, saved: saved.len() };
    Emitted { layout, stats, frame: frame_info }
}
