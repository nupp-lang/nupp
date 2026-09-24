//! Machine IR plus allocations to x86-64 AVX2 code, encoded by iced-x86.
//!
//! SysV: arguments in rdi, rsi, rdx, rcx, r8, r9 and xmm0..; every vector
//! register is caller-saved; rbx and r12-r15 are callee-saved and pushed only
//! when the allocator used them. Constants sit in a pool after the code and
//! are read RIP-relative, so the image has no relocations.

use crate::mir::{Func, Op};
use iced_x86::code_asm::*;
use regalloc2::{Allocation, Block, Edit, Function, InstOrEdit, MachineEnv, Output, PReg, PRegSet, RegClass};

const G64: [AsmRegister64; 16] = [rax, rcx, rdx, rbx, rsp, rbp, rsi, rdi, r8, r9, r10, r11, r12, r13, r14, r15];
const G32: [AsmRegister32; 16] =
    [eax, ecx, edx, ebx, esp, ebp, esi, edi, r8d, r9d, r10d, r11d, r12d, r13d, r14d, r15d];
const X: [AsmRegisterXmm; 16] = [
    xmm0, xmm1, xmm2, xmm3, xmm4, xmm5, xmm6, xmm7, xmm8, xmm9, xmm10, xmm11, xmm12, xmm13, xmm14, xmm15,
];
const Y: [AsmRegisterYmm; 16] = [
    ymm0, ymm1, ymm2, ymm3, ymm4, ymm5, ymm6, ymm7, ymm8, ymm9, ymm10, ymm11, ymm12, ymm13, ymm14, ymm15,
];

/// Temporaries inside one instruction: xmm14 is never allocated, xmm15 is
/// the allocator's move scratch (free within an instruction), r11 likewise.
const T0: usize = 14;
const T1: usize = 15;

const K: [AsmRegisterK; 8] = [k0, k1, k2, k3, k4, k5, k6, k7];

/// `reg{k}` for an allocated mask register (k0 cannot mask).
fn ymm_k(r: AsmRegisterYmm, k: usize) -> AsmRegisterYmm {
    match k {
        1 => r.k1(),
        2 => r.k2(),
        3 => r.k3(),
        4 => r.k4(),
        5 => r.k5(),
        6 => r.k6(),
        7 => r.k7(),
        other => panic!("k{other} cannot write-mask"),
    }
}
fn mem_k(m: AsmMemoryOperand, k: usize) -> AsmMemoryOperand {
    match k {
        1 => m.k1(),
        2 => m.k2(),
        3 => m.k3(),
        4 => m.k4(),
        5 => m.k5(),
        6 => m.k6(),
        7 => m.k7(),
        other => panic!("k{other} cannot write-mask"),
    }
}

/// With `avx512`, the third class is the opmask registers k1-k6 (k7 is the
/// allocator's scratch).
pub fn machine_env_for(avx512: bool) -> MachineEnv {
    let mut env = machine_env();
    if avx512 {
        let mut masks = PRegSet::empty();
        for r in 1..7 {
            masks.add(PReg::new(r, RegClass::Vector));
        }
        env.preferred_regs_by_class[2] = masks;
        env.scratch_by_class[2] = Some(PReg::new(7, RegClass::Vector));
    }
    env
}

pub fn machine_env() -> MachineEnv {
    let mut int_pref = PRegSet::empty();
    let mut int_non = PRegSet::empty();
    let mut f_pref = PRegSet::empty();
    for r in [0, 1, 2, 6, 7, 8, 9, 10] {
        int_pref.add(PReg::new(r, RegClass::Int));
    }
    for r in [3, 12, 13, 14, 15] {
        int_non.add(PReg::new(r, RegClass::Int));
    }
    for r in 0..14 {
        f_pref.add(PReg::new(r, RegClass::Float));
    }
    MachineEnv {
        preferred_regs_by_class: [int_pref, f_pref, PRegSet::empty()],
        non_preferred_regs_by_class: [int_non, PRegSet::empty(), PRegSet::empty()],
        scratch_by_class: [Some(PReg::new(11, RegClass::Int)), Some(PReg::new(T1, RegClass::Float)), None],
        fixed_stack_slots: vec![],
    }
}

fn reg(a: Allocation) -> usize {
    a.as_reg().expect("operand in a register").hw_enc()
}

/// x86 condition for one of the spike's AArch64-numbered conditions.
fn jcc(a: &mut CodeAssembler, cond: u32, l: CodeLabel) {
    use crate::asm::cond::*;
    match cond {
        EQ => a.je(l),
        NE => a.jne(l),
        HS => a.jae(l),
        LO => a.jb(l),
        HI => a.ja(l),
        LS => a.jbe(l),
        GE => a.jge(l),
        LT => a.jl(l),
        GT => a.jg(l),
        LE => a.jle(l),
        other => panic!("condition {other}"),
    }
    .unwrap();
}

pub struct Emitted {
    pub bytes: Vec<u8>,
    pub words: usize,
    pub spill_slots: usize,
    pub moves: usize,
}

pub fn emit(func: &Func, out: &Output) -> Emitted {
    let mut saved = std::collections::BTreeSet::new();
    let mut note = |a: &Allocation| {
        if let Some(p) = a.as_reg() {
            if p.class() == RegClass::Int && [3, 12, 13, 14, 15].contains(&p.hw_enc()) {
                saved.insert(p.hw_enc());
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
    let saved: Vec<usize> = saved.into_iter().collect();
    // After the return address and rbp, `saved` pushes; keep rsp 16-aligned.
    let spill = out.num_spillslots * 8;
    let mut frame = spill;
    while (8 * saved.len() + frame) % 16 != 0 {
        frame += 8;
    }

    let mut a = CodeAssembler::new(64).unwrap();
    let nblocks = func.num_blocks();
    // Forward blocks that are a bare jump with no edits.
    let mut forward: Vec<Option<usize>> = vec![None; nblocks];
    for b in 1..nblocks {
        let items: Vec<_> = out.block_insts_and_edits(func, Block::new(b)).collect();
        if items.len() == 1 {
            if let InstOrEdit::Inst(i) = items[0] {
                let inst = &func.insts[i.index()];
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
    let mut labels: Vec<CodeLabel> = (0..nblocks).map(|_| a.create_label()).collect();
    let emitted: Vec<usize> = (0..nblocks).filter(|b| forward[*b].is_none()).collect();
    let mut literals: Vec<(Vec<u8>, CodeLabel)> = Vec::new();
    let mut literal = |a: &mut CodeAssembler, bytes: Vec<u8>| -> CodeLabel {
        if let Some((_, l)) = literals.iter().find(|(b, _)| *b == bytes) {
            return *l;
        }
        let l = a.create_label();
        literals.push((bytes, l));
        l
    };

    a.push(rbp).unwrap();
    a.mov(rbp, rsp).unwrap();
    for r in &saved {
        a.push(G64[*r]).unwrap();
    }
    if frame > 0 {
        a.sub(rsp, frame as i32).unwrap();
    }
    let slot = |x: Allocation| (x.as_stack().unwrap().index() * 8) as i32;

    for (pos, &b) in emitted.iter().enumerate() {
        let next = emitted.get(pos + 1).copied();
        let mut label = labels[b];
        a.set_label(&mut label).unwrap();
        labels[b] = label;
        let mut wrote = false;
        for item in out.block_insts_and_edits(func, Block::new(b)) {
            match item {
                InstOrEdit::Edit(Edit::Move { from, to }) => {
                    wrote = true;
                    let class = from.as_reg().map(|r| r.class()).or(to.as_reg().map(|r| r.class())).unwrap();
                    let int = class == RegClass::Int;
                    if class == RegClass::Vector {
                        match (from.as_reg(), to.as_reg()) {
                            (Some(f), Some(t)) => a.kmovw(K[t.hw_enc()], K[f.hw_enc()]).unwrap(),
                            (Some(f), None) => a.kmovw(word_ptr(rsp + slot(*to)), K[f.hw_enc()]).unwrap(),
                            (None, Some(t)) => a.kmovw(K[t.hw_enc()], word_ptr(rsp + slot(*from))).unwrap(),
                            (None, None) => unreachable!(),
                        }
                        continue;
                    }
                    match (from.as_reg(), to.as_reg()) {
                        (Some(f), Some(t)) if int => a.mov(G64[t.hw_enc()], G64[f.hw_enc()]).unwrap(),
                        (Some(f), Some(t)) => a.vmovapd(Y[t.hw_enc()], Y[f.hw_enc()]).unwrap(),
                        (Some(f), None) if int => a.mov(qword_ptr(rsp + slot(*to)), G64[f.hw_enc()]).unwrap(),
                        (Some(f), None) => a.vmovupd(ymmword_ptr(rsp + slot(*to)), Y[f.hw_enc()]).unwrap(),
                        (None, Some(t)) if int => a.mov(G64[t.hw_enc()], qword_ptr(rsp + slot(*from))).unwrap(),
                        (None, Some(t)) => a.vmovupd(Y[t.hw_enc()], ymmword_ptr(rsp + slot(*from))).unwrap(),
                        (None, None) => unreachable!(),
                    }
                }
                InstOrEdit::Inst(i) => {
                    let inst = &func.insts[i.index()];
                    let allocs = out.inst_allocs(i);
                    let r: Vec<usize> = allocs.iter().map(|x| reg(*x)).collect();
                    // AVX-512: a mask operand is a k register.
                    let is_k = |n: usize| allocs[n].as_reg().map(|p| p.class() == RegClass::Vector).unwrap_or(false);
                    let target = |k: usize| resolve(inst.succs[k].index());
                    let before = a.instructions().len();
                    match &inst.op {
                        Op::Args => {}
                        Op::Ret => {
                            if frame > 0 {
                                a.add(rsp, frame as i32).unwrap();
                            }
                            for s in saved.iter().rev() {
                                a.pop(G64[*s]).unwrap();
                            }
                            a.pop(rbp).unwrap();
                            a.vzeroupper().unwrap();
                            a.ret().unwrap();
                        }
                        Op::Imm { value } => a.mov(G64[r[0]], *value).unwrap(),
                        Op::LitD { bits } => {
                            let mut bytes = bits.to_le_bytes().to_vec();
                            bytes.resize(8, 0);
                            let l = literal(&mut a, bytes);
                            a.vmovsd(X[r[0]], qword_ptr(l)).unwrap();
                        }
                        Op::LitQ { bytes } => {
                            let l = literal(&mut a, bytes.to_vec());
                            a.vmovupd(X[r[0]], xmmword_ptr(l)).unwrap();
                        }
                        Op::LitY { bytes } => {
                            let l = literal(&mut a, bytes.to_vec());
                            a.vmovupd(Y[r[0]], ymmword_ptr(l)).unwrap();
                        }
                        Op::Add { sf } => {
                            if *sf {
                                a.lea(G64[r[0]], ptr(G64[r[1]] + G64[r[2]])).unwrap()
                            } else {
                                a.lea(G32[r[0]], ptr(G64[r[1]] + G64[r[2]])).unwrap()
                            }
                        }
                        Op::Sub { sf } => {
                            let (d, l, s) = (r[0], r[1], r[2]);
                            if *sf {
                                if d == s {
                                    a.neg(G64[d]).unwrap();
                                    a.add(G64[d], G64[l]).unwrap();
                                } else {
                                    a.mov(G64[d], G64[l]).unwrap();
                                    a.sub(G64[d], G64[s]).unwrap();
                                }
                            } else if d == s {
                                a.neg(G32[d]).unwrap();
                                a.add(G32[d], G32[l]).unwrap();
                            } else {
                                a.mov(G32[d], G32[l]).unwrap();
                                a.sub(G32[d], G32[s]).unwrap();
                            }
                        }
                        Op::AddImm { sf, imm } => {
                            if *sf {
                                a.lea(G64[r[0]], ptr(G64[r[1]] + *imm as i32)).unwrap()
                            } else {
                                a.lea(G32[r[0]], ptr(G64[r[1]] + *imm as i32)).unwrap()
                            }
                        }
                        Op::AddrIdx => a.lea(G64[r[0]], ptr(G64[r[1]] + G64[r[2]] * 8)).unwrap(),
                        // u32 values are zero-extended in their 64-bit register, and
                        // counts stay below 2^63, so the signed conversions are exact.
                        Op::UcvtfW | Op::UcvtfX => {
                            a.vxorpd(X[r[0]], X[r[0]], X[r[0]]).unwrap();
                            a.vcvtsi2sd(X[r[0]], X[r[0]], G64[r[1]]).unwrap();
                        }
                        Op::FcvtzuW => a.vcvttsd2si(G64[r[0]], X[r[1]]).unwrap(),
                        Op::FAdd => a.vaddsd(X[r[0]], X[r[1]], X[r[2]]).unwrap(),
                        Op::FSub => a.vsubsd(X[r[0]], X[r[1]], X[r[2]]).unwrap(),
                        Op::FMul => a.vmulsd(X[r[0]], X[r[1]], X[r[2]]).unwrap(),
                        Op::VFAdd => a.vaddpd(Y[r[0]], Y[r[1]], Y[r[2]]).unwrap(),
                        Op::VFMul => a.vmulpd(Y[r[0]], Y[r[1]], Y[r[2]]).unwrap(),
                        // _CMP_GT_OQ: false for NaN, like NEON's fcmgt.
                        Op::VFCmGt if is_k(0) => a.vcmppd(K[r[0]], Y[r[1]], Y[r[2]], 0x1E).unwrap(),
                        Op::VFCmGt => a.vcmppd(Y[r[0]], Y[r[1]], Y[r[2]], 0x1E).unwrap(),
                        Op::VAnd if is_k(0) => a.kandw(K[r[0]], K[r[1]], K[r[2]]).unwrap(),
                        Op::VAnd => a.vandpd(Y[r[0]], Y[r[1]], Y[r[2]]).unwrap(),
                        // Lane indices and tail counts are small and non-negative.
                        // Unsigned `n > lane`: vpcmpuq with predicate 6 (not-less-or-equal).
                        Op::VCmHi if is_k(0) => a.vpcmpuq(K[r[0]], Y[r[1]], Y[r[2]], 6).unwrap(),
                        Op::VCmHi => a.vpcmpgtq(Y[r[0]], Y[r[1]], Y[r[2]]).unwrap(),
                        // vblendmpd dst{k}, false, true.
                        Op::Blend => a.vblendmpd(ymm_k(Y[r[0]], r[1]), Y[r[3]], Y[r[2]]).unwrap(),
                        Op::Bsl => a.vblendvpd(Y[r[0]], Y[r[3]], Y[r[2]], Y[r[1]]).unwrap(),
                        Op::DupD => a.vbroadcastsd(Y[r[0]], X[r[1]]).unwrap(),
                        Op::DupX => {
                            a.vmovq(X[r[0]], G64[r[1]]).unwrap();
                            a.vpbroadcastq(Y[r[0]], X[r[0]]).unwrap();
                        }
                        Op::Sum => {
                            assert_eq!(r.len(), 2, "x86 holds a species in one register");
                            // (a0 + a2) + (a1 + a3), the association NEON's path uses.
                            a.vextractf128(X[T0], Y[r[1]], 1).unwrap();
                            a.vaddpd(X[T0], X[T0], X[r[1]]).unwrap();
                            a.vpermilpd(X[T1], X[T0], 1).unwrap();
                            a.vaddsd(X[r[0]], X[T0], X[T1]).unwrap();
                        }
                        Op::LdrIdx => a.vmovsd(X[r[0]], qword_ptr(G64[r[1]] + G64[r[2]] * 8)).unwrap(),
                        Op::StrIdx => a.vmovsd(qword_ptr(G64[r[1]] + G64[r[2]] * 8), X[r[0]]).unwrap(),
                        Op::Load { off } => a.vmovupd(Y[r[0]], ymmword_ptr(G64[r[1]] + *off)).unwrap(),
                        Op::Store { off } => a.vmovupd(ymmword_ptr(G64[r[1]] + *off), Y[r[0]]).unwrap(),
                        // Masked-off lanes neither fault nor load: the tail stays in bounds.
                        // AVX-512 masked moves suppress faults on masked-off lanes too.
                        // The mask does the work on x86; a known prefix count adds nothing.
                        Op::MaskedLoad { .. } if is_k(2) => a.vmovupd(ymm_k(Y[r[0]], r[2]).z(), ymmword_ptr(G64[r[1]])).unwrap(),
                        Op::MaskedStore { .. } if is_k(2) => a.vmovupd(mem_k(ymmword_ptr(G64[r[1]]), r[2]), Y[r[0]]).unwrap(),
                        Op::MaskedLoad { .. } => a.vmaskmovpd(Y[r[0]], Y[r[2]], ymmword_ptr(G64[r[1]])).unwrap(),
                        Op::MaskedStore { .. } => a.vmaskmovpd(ymmword_ptr(G64[r[1]]), Y[r[2]], Y[r[0]]).unwrap(),
                        Op::Jump => {
                            let t = target(0);
                            if Some(t) != next {
                                a.jmp(labels[t]).unwrap();
                            }
                        }
                        Op::CmpBr { sf, cond } => {
                            if *sf {
                                a.cmp(G64[r[0]], G64[r[1]]).unwrap();
                            } else {
                                a.cmp(G32[r[0]], G32[r[1]]).unwrap();
                            }
                            let (t, f) = (target(0), target(1));
                            if Some(t) == next {
                                jcc(&mut a, cond ^ 1, labels[f]);
                            } else {
                                jcc(&mut a, *cond, labels[t]);
                                if Some(f) != next {
                                    a.jmp(labels[f]).unwrap();
                                }
                            }
                        }
                        Op::FCmpBr { cond } => {
                            // Ordered comparisons from ucomisd's unsigned flags:
                            // unordered sets CF and ZF, so "above" is false for NaN.
                            use crate::asm::cond::*;
                            let (x, y, strict) = match *cond {
                                MI => (r[1], r[0], true),  // a < b  as  b > a
                                LS => (r[1], r[0], false), // a <= b as  b >= a
                                GT => (r[0], r[1], true),
                                GE => (r[0], r[1], false),
                                other => panic!("float condition {other}"),
                            };
                            a.vucomisd(X[x], X[y]).unwrap();
                            let (t, f) = (target(0), target(1));
                            let (yes, no) = if strict { (HI, LS) } else { (HS, LO) };
                            if Some(t) == next {
                                jcc(&mut a, no, labels[f]);
                            } else {
                                jcc(&mut a, yes, labels[t]);
                                if Some(f) != next {
                                    a.jmp(labels[f]).unwrap();
                                }
                            }
                        }
                        Op::AnyBr => {
                            if is_k(0) {
                                a.kortestw(K[r[0]], K[r[0]]).unwrap();
                            } else {
                                a.vptest(Y[r[0]], Y[r[0]]).unwrap();
                            }
                            let (t, f) = (target(0), target(1));
                            if Some(t) == next {
                                a.je(labels[f]).unwrap();
                            } else {
                                a.jne(labels[t]).unwrap();
                                if Some(f) != next {
                                    a.jmp(labels[f]).unwrap();
                                }
                            }
                        }
                        other => panic!("{other:?} has no x86 AVX2 lowering in the spike"),
                    }
                    if a.instructions().len() > before {
                        wrote = true;
                    }
                }
            }
        }
        // A label must precede an instruction; an empty block still gets one.
        if !wrote {
            a.nop().unwrap();
        }
    }
    // Constant pool, 32-byte aligned, after the code.
    let code_instructions = a.instructions().len();
    for (bytes, l) in &mut literals {
        a.set_label(l).unwrap();
        a.db(bytes).unwrap();
    }
    let _ = code_instructions;
    let mut bytes = a.assemble(0).unwrap();
    while bytes.len() % 16 != 0 {
        bytes.push(0xCC);
    }
    Emitted { words: bytes.len(), bytes, spill_slots: out.num_spillslots, moves }
}
