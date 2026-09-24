//! AArch64 encoder: the instructions the spike's selection emits, and an
//! assembler with labels and a literal pool. Every reference is PC-relative,
//! so the finished image has no relocations.

pub type R = u32; // register number 0..=31

pub const SP: R = 31;
pub const ZR: R = 31;
pub const FP: R = 29;
pub const LR: R = 30;

/// Condition codes.
pub mod cond {
    pub const EQ: u32 = 0;
    pub const NE: u32 = 1;
    pub const HS: u32 = 2;
    pub const LO: u32 = 3;
    pub const MI: u32 = 4;
    pub const PL: u32 = 5;
    pub const HI: u32 = 8;
    pub const LS: u32 = 9;
    pub const GE: u32 = 10;
    pub const LT: u32 = 11;
    pub const GT: u32 = 12;
    pub const LE: u32 = 13;
}

// ---- integer ----
pub fn add_reg(sf: bool, rd: R, rn: R, rm: R, lsl: u32) -> u32 {
    (if sf { 0x8B00_0000 } else { 0x0B00_0000 }) | (rm << 16) | (lsl << 10) | (rn << 5) | rd
}
pub fn sub_reg(sf: bool, rd: R, rn: R, rm: R) -> u32 {
    (if sf { 0xCB00_0000 } else { 0x4B00_0000 }) | (rm << 16) | (rn << 5) | rd
}
pub fn cmp_reg(sf: bool, rn: R, rm: R) -> u32 {
    (if sf { 0xEB00_0000 } else { 0x6B00_0000 }) | (rm << 16) | (rn << 5) | ZR
}
pub fn add_imm(sf: bool, rd: R, rn: R, imm: u32) -> u32 {
    assert!(imm < 4096);
    (if sf { 0x9100_0000 } else { 0x1100_0000 }) | (imm << 10) | (rn << 5) | rd
}
pub fn sub_imm(sf: bool, rd: R, rn: R, imm: u32) -> u32 {
    assert!(imm < 4096);
    (if sf { 0xD100_0000 } else { 0x5100_0000 }) | (imm << 10) | (rn << 5) | rd
}
pub fn cmp_imm(sf: bool, rn: R, imm: u32) -> u32 {
    assert!(imm < 4096);
    (if sf { 0xF100_0000 } else { 0x7100_0000 }) | (imm << 10) | (rn << 5) | ZR
}
pub fn movz(sf: bool, rd: R, imm16: u32, hw: u32) -> u32 {
    (if sf { 0xD280_0000 } else { 0x5280_0000 }) | (hw << 21) | (imm16 << 5) | rd
}
pub fn movk(sf: bool, rd: R, imm16: u32, hw: u32) -> u32 {
    (if sf { 0xF280_0000 } else { 0x7280_0000 }) | (hw << 21) | (imm16 << 5) | rd
}
pub fn mov_reg(sf: bool, rd: R, rm: R) -> u32 {
    (if sf { 0xAA00_03E0 } else { 0x2A00_03E0 }) | (rm << 16) | rd
}
pub fn mov_from_sp(rd: R) -> u32 {
    add_imm(true, rd, SP, 0)
}

// ---- branches ----
pub fn b(off: i32) -> u32 {
    0x1400_0000 | ((off >> 2) as u32 & 0x03FF_FFFF)
}
pub fn b_cond(cond: u32, off: i32) -> u32 {
    0x5400_0000 | ((((off >> 2) as u32) & 0x7FFFF) << 5) | cond
}
pub fn cbnz(sf: bool, rt: R, off: i32) -> u32 {
    (if sf { 0xB500_0000 } else { 0x3500_0000 }) | ((((off >> 2) as u32) & 0x7FFFF) << 5) | rt
}
pub fn cbz(sf: bool, rt: R, off: i32) -> u32 {
    (if sf { 0xB400_0000 } else { 0x3400_0000 }) | ((((off >> 2) as u32) & 0x7FFFF) << 5) | rt
}
pub fn ret() -> u32 {
    0xD65F_03C0
}

// ---- loads and stores ----
pub fn ldr_d_imm(rt: R, rn: R, byte: u32) -> u32 {
    assert!(byte % 8 == 0 && byte / 8 < 4096);
    0xFD40_0000 | ((byte / 8) << 10) | (rn << 5) | rt
}
pub fn str_d_imm(rt: R, rn: R, byte: u32) -> u32 {
    assert!(byte % 8 == 0 && byte / 8 < 4096);
    0xFD00_0000 | ((byte / 8) << 10) | (rn << 5) | rt
}
pub fn ldr_q_imm(rt: R, rn: R, byte: u32) -> u32 {
    assert!(byte % 16 == 0 && byte / 16 < 4096);
    0x3DC0_0000 | ((byte / 16) << 10) | (rn << 5) | rt
}
pub fn str_q_imm(rt: R, rn: R, byte: u32) -> u32 {
    assert!(byte % 16 == 0 && byte / 16 < 4096);
    0x3D80_0000 | ((byte / 16) << 10) | (rn << 5) | rt
}
pub fn ldr_x_imm(rt: R, rn: R, byte: u32) -> u32 {
    assert!(byte % 8 == 0 && byte / 8 < 4096);
    0xF940_0000 | ((byte / 8) << 10) | (rn << 5) | rt
}
pub fn str_x_imm(rt: R, rn: R, byte: u32) -> u32 {
    assert!(byte % 8 == 0 && byte / 8 < 4096);
    0xF900_0000 | ((byte / 8) << 10) | (rn << 5) | rt
}
/// `ldr dT, [xN, xM, lsl #3]`
pub fn ldr_d_idx(rt: R, rn: R, rm: R) -> u32 {
    0xFC60_7800 | (rm << 16) | (rn << 5) | rt
}
/// `str dT, [xN, xM, lsl #3]`
pub fn str_d_idx(rt: R, rn: R, rm: R) -> u32 {
    0xFC20_7800 | (rm << 16) | (rn << 5) | rt
}
fn imm7(off: i32, scale: i32) -> u32 {
    assert!(off % scale == 0);
    let v = off / scale;
    assert!((-64..64).contains(&v));
    (v as u32) & 0x7F
}
pub fn ldp_q(rt: R, rt2: R, rn: R, off: i32) -> u32 {
    0xAD40_0000 | (imm7(off, 16) << 15) | (rt2 << 10) | (rn << 5) | rt
}
pub fn stp_q(rt: R, rt2: R, rn: R, off: i32) -> u32 {
    0xAD00_0000 | (imm7(off, 16) << 15) | (rt2 << 10) | (rn << 5) | rt
}
pub fn stp_x(rt: R, rt2: R, rn: R, off: i32) -> u32 {
    0xA900_0000 | (imm7(off, 8) << 15) | (rt2 << 10) | (rn << 5) | rt
}
pub fn ldp_x(rt: R, rt2: R, rn: R, off: i32) -> u32 {
    0xA940_0000 | (imm7(off, 8) << 15) | (rt2 << 10) | (rn << 5) | rt
}
pub fn stp_x_pre(rt: R, rt2: R, rn: R, off: i32) -> u32 {
    0xA980_0000 | (imm7(off, 8) << 15) | (rt2 << 10) | (rn << 5) | rt
}
pub fn ldp_x_post(rt: R, rt2: R, rn: R, off: i32) -> u32 {
    0xA8C0_0000 | (imm7(off, 8) << 15) | (rt2 << 10) | (rn << 5) | rt
}
pub fn stp_d(rt: R, rt2: R, rn: R, off: i32) -> u32 {
    0x6D00_0000 | (imm7(off, 8) << 15) | (rt2 << 10) | (rn << 5) | rt
}
pub fn ldp_d(rt: R, rt2: R, rn: R, off: i32) -> u32 {
    0x6D40_0000 | (imm7(off, 8) << 15) | (rt2 << 10) | (rn << 5) | rt
}
pub fn sub_sp(imm: u32) -> u32 {
    sub_imm(true, SP, SP, imm)
}
pub fn add_sp(imm: u32) -> u32 {
    add_imm(true, SP, SP, imm)
}

// ---- scalar floating point ----
pub fn fadd_d(rd: R, rn: R, rm: R) -> u32 {
    0x1E60_2800 | (rm << 16) | (rn << 5) | rd
}
pub fn fsub_d(rd: R, rn: R, rm: R) -> u32 {
    0x1E60_3800 | (rm << 16) | (rn << 5) | rd
}
pub fn fmul_d(rd: R, rn: R, rm: R) -> u32 {
    0x1E60_0800 | (rm << 16) | (rn << 5) | rd
}
pub fn fcmp_d(rn: R, rm: R) -> u32 {
    0x1E60_2000 | (rm << 16) | (rn << 5)
}
pub fn fmov_d(rd: R, rn: R) -> u32 {
    0x1E60_4000 | (rn << 5) | rd
}
pub fn ucvtf_d_w(rd: R, rn: R) -> u32 {
    0x1E63_0000 | (rn << 5) | rd
}
pub fn ucvtf_d_x(rd: R, rn: R) -> u32 {
    0x9E63_0000 | (rn << 5) | rd
}
pub fn fcvtzu_w_d(rd: R, rn: R) -> u32 {
    0x1E79_0000 | (rn << 5) | rd
}
pub fn fmov_x_d(rd: R, rn: R) -> u32 {
    0x9E66_0000 | (rn << 5) | rd
}

// ---- Advanced SIMD ----
pub fn fadd_2d(rd: R, rn: R, rm: R) -> u32 {
    0x4E60_D400 | (rm << 16) | (rn << 5) | rd
}
pub fn fmul_2d(rd: R, rn: R, rm: R) -> u32 {
    0x6E60_DC00 | (rm << 16) | (rn << 5) | rd
}
pub fn fcmgt_2d(rd: R, rn: R, rm: R) -> u32 {
    0x6EE0_E400 | (rm << 16) | (rn << 5) | rd
}
pub fn cmhi_2d(rd: R, rn: R, rm: R) -> u32 {
    0x6EE0_3400 | (rm << 16) | (rn << 5) | rd
}
pub fn and_16b(rd: R, rn: R, rm: R) -> u32 {
    0x4E20_1C00 | (rm << 16) | (rn << 5) | rd
}
pub fn orr_16b(rd: R, rn: R, rm: R) -> u32 {
    0x4EA0_1C00 | (rm << 16) | (rn << 5) | rd
}
pub fn mov_16b(rd: R, rn: R) -> u32 {
    orr_16b(rd, rn, rn)
}
pub fn bsl_16b(rd: R, rn: R, rm: R) -> u32 {
    0x6E60_1C00 | (rm << 16) | (rn << 5) | rd
}
pub fn dup_2d_elem0(rd: R, rn: R) -> u32 {
    0x4E08_0400 | (rn << 5) | rd
}
pub fn dup_2d_x(rd: R, rn: R) -> u32 {
    0x4E08_0C00 | (rn << 5) | rd
}
/// `addp dD, vN.2d`
pub fn addp_d(rd: R, rn: R) -> u32 {
    0x5EF1_B800 | (rn << 5) | rd
}
/// `faddp dD, vN.2d`
pub fn faddp_d(rd: R, rn: R) -> u32 {
    0x7E70_D800 | (rn << 5) | rd
}
pub fn movi_2d_zero(rd: R) -> u32 {
    0x6F00_E400 | rd
}
/// `umov xD, vN.d[i]`
pub fn umov_x_d(rd: R, rn: R, i: u32) -> u32 {
    (if i == 0 { 0x4E08_3C00 } else { 0x4E18_3C00 }) | (rn << 5) | rd
}
/// `mov vD.d[i], vN.d[0]`
pub fn ins_d(rd: R, i: u32, rn: R) -> u32 {
    (if i == 0 { 0x6E08_0400 } else { 0x6E18_0400 }) | (rn << 5) | rd
}
/// `mov dD, vN.d[i]`
pub fn dup_d_elem(rd: R, rn: R, i: u32) -> u32 {
    (if i == 0 { 0x5E08_0400 } else { 0x5E18_0400 }) | (rn << 5) | rd
}

// ---- assembler ----

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Label(pub usize);

enum Fixup {
    B,
    BCond,
    Cb,
    LdrLiteral,
}

pub struct Asm {
    pub words: Vec<u32>,
    labels: Vec<Option<usize>>,
    fixups: Vec<(usize, Label, Fixup)>,
    /// 16-byte literals, each placed in the pool after the code.
    literals: Vec<([u8; 16], Label)>,
}

impl Asm {
    pub fn new() -> Asm {
        Asm { words: Vec::new(), labels: Vec::new(), fixups: Vec::new(), literals: Vec::new() }
    }
    pub fn label(&mut self) -> Label {
        self.labels.push(None);
        Label(self.labels.len() - 1)
    }
    pub fn bind(&mut self, l: Label) {
        assert!(self.labels[l.0].is_none());
        self.labels[l.0] = Some(self.words.len());
    }
    pub fn emit(&mut self, w: u32) {
        self.words.push(w);
    }
    pub fn b(&mut self, l: Label) {
        self.fixups.push((self.words.len(), l, Fixup::B));
        self.words.push(b(0));
    }
    pub fn b_cond(&mut self, c: u32, l: Label) {
        self.fixups.push((self.words.len(), l, Fixup::BCond));
        self.words.push(b_cond(c, 0));
    }
    pub fn cbnz(&mut self, rt: R, l: Label) {
        self.fixups.push((self.words.len(), l, Fixup::Cb));
        self.words.push(cbnz(true, rt, 0));
    }
    pub fn cbz(&mut self, rt: R, l: Label) {
        self.fixups.push((self.words.len(), l, Fixup::Cb));
        self.words.push(cbz(true, rt, 0));
    }
    /// `ldr dT, =value` / `ldr qT, =value` from the pool.
    pub fn ldr_literal(&mut self, rt: R, bytes: [u8; 16], q: bool) {
        let l = match self.literals.iter().find(|(b, _)| *b == bytes) {
            Some((_, l)) => *l,
            None => {
                let l = self.label();
                self.literals.push((bytes, l));
                l
            }
        };
        self.fixups.push((self.words.len(), l, Fixup::LdrLiteral));
        self.words.push(if q { 0x9C00_0000 | rt } else { 0x5C00_0000 | rt });
    }
    pub fn finish(mut self) -> Vec<u8> {
        // Pool after the code, 16-byte aligned.
        while self.words.len() % 4 != 0 {
            self.words.push(0xD503_201F); // nop
        }
        let literals = std::mem::take(&mut self.literals);
        for (bytes, l) in &literals {
            self.bind(*l);
            for c in bytes.chunks(4) {
                self.words.push(u32::from_le_bytes([c[0], c[1], c[2], c[3]]));
            }
        }
        for (at, l, kind) in &self.fixups {
            let target = self.labels[l.0].expect("unbound label");
            let off = (target as i32 - *at as i32) * 4;
            let w = &mut self.words[*at];
            match kind {
                Fixup::B => {
                    *w |= ((off >> 2) as u32) & 0x03FF_FFFF;
                }
                Fixup::BCond | Fixup::Cb | Fixup::LdrLiteral => {
                    assert!((-(1 << 20)..(1 << 20)).contains(&off));
                    *w |= (((off >> 2) as u32) & 0x7FFFF) << 5;
                }
            }
        }
        self.words.iter().flat_map(|w| w.to_le_bytes()).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::Command;

    /// Assembles `text` with the system assembler and returns its words.
    fn reference(lines: &[&str]) -> Vec<u32> {
        let dir = std::env::temp_dir().join(format!("nupp-asm-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let src = dir.join("t.s");
        let obj = dir.join("t.o");
        let body: String = lines.iter().map(|l| format!("  {l}\n")).collect();
        std::fs::write(&src, format!(".text\n.globl _t\n_t:\n{body}")).unwrap();
        let ok = Command::new("clang").args(["-c", "-arch", "arm64", "-o"]).arg(&obj).arg(&src).status().unwrap();
        assert!(ok.success());
        // `otool -t` prints the text section as address then 32-bit words.
        let out = Command::new("otool").arg("-t").arg(&obj).output().unwrap();
        assert!(out.status.success());
        String::from_utf8(out.stdout)
            .unwrap()
            .lines()
            .filter(|l| l.starts_with('0'))
            .flat_map(|l| l.split_whitespace().skip(1).map(|w| u32::from_str_radix(w, 16).unwrap()).collect::<Vec<_>>())
            .collect()
    }

    #[test]
    fn encodings_match_the_system_assembler() {
        let cases: Vec<(u32, &str)> = vec![
            (add_reg(true, 1, 2, 3, 3), "add x1, x2, x3, lsl #3"),
            (add_reg(false, 1, 2, 3, 0), "add w1, w2, w3"),
            (sub_reg(true, 4, 5, 6), "sub x4, x5, x6"),
            (cmp_reg(true, 7, 8), "cmp x7, x8"),
            (cmp_reg(false, 7, 8), "cmp w7, w8"),
            (add_imm(true, 1, 2, 4), "add x1, x2, #4"),
            (add_imm(false, 1, 2, 4), "add w1, w2, #4"),
            (sub_imm(true, 1, 2, 16), "sub x1, x2, #16"),
            (cmp_imm(true, 3, 4), "cmp x3, #4"),
            (movz(true, 5, 0x1234, 0), "movz x5, #0x1234"),
            (movz(false, 5, 4, 0), "movz w5, #4"),
            (movk(true, 5, 0xabcd, 1), "movk x5, #0xabcd, lsl #16"),
            (mov_reg(true, 1, 2), "mov x1, x2"),
            (mov_reg(false, 1, 2), "mov w1, w2"),
            (mov_from_sp(FP), "mov x29, sp"),
            (ret(), "ret"),
            (ldr_d_imm(1, 2, 24), "ldr d1, [x2, #24]"),
            (str_d_imm(1, 2, 8), "str d1, [x2, #8]"),
            (ldr_q_imm(3, SP, 32), "ldr q3, [sp, #32]"),
            (str_q_imm(3, SP, 48), "str q3, [sp, #48]"),
            (ldr_x_imm(3, SP, 8), "ldr x3, [sp, #8]"),
            (str_x_imm(3, SP, 16), "str x3, [sp, #16]"),
            (ldr_d_idx(1, 2, 3), "ldr d1, [x2, x3, lsl #3]"),
            (str_d_idx(1, 2, 3), "str d1, [x2, x3, lsl #3]"),
            (ldp_q(1, 2, 3, 0), "ldp q1, q2, [x3]"),
            (ldp_q(1, 2, 3, 32), "ldp q1, q2, [x3, #32]"),
            (stp_q(1, 2, 3, -32), "stp q1, q2, [x3, #-32]"),
            (stp_x(19, 20, SP, 16), "stp x19, x20, [sp, #16]"),
            (ldp_x(19, 20, SP, 16), "ldp x19, x20, [sp, #16]"),
            (stp_x_pre(FP, LR, SP, -16), "stp x29, x30, [sp, #-16]!"),
            (ldp_x_post(FP, LR, SP, 16), "ldp x29, x30, [sp], #16"),
            (stp_d(8, 9, SP, 32), "stp d8, d9, [sp, #32]"),
            (ldp_d(8, 9, SP, 32), "ldp d8, d9, [sp, #32]"),
            (sub_sp(64), "sub sp, sp, #64"),
            (add_sp(64), "add sp, sp, #64"),
            (fadd_d(1, 2, 3), "fadd d1, d2, d3"),
            (fsub_d(1, 2, 3), "fsub d1, d2, d3"),
            (fmul_d(1, 2, 3), "fmul d1, d2, d3"),
            (fcmp_d(1, 2), "fcmp d1, d2"),
            (fmov_d(1, 2), "fmov d1, d2"),
            (ucvtf_d_w(1, 2), "ucvtf d1, w2"),
            (ucvtf_d_x(1, 2), "ucvtf d1, x2"),
            (fcvtzu_w_d(1, 2), "fcvtzu w1, d2"),
            (fmov_x_d(1, 2), "fmov x1, d2"),
            (fadd_2d(1, 2, 3), "fadd v1.2d, v2.2d, v3.2d"),
            (fmul_2d(1, 2, 3), "fmul v1.2d, v2.2d, v3.2d"),
            (fcmgt_2d(1, 2, 3), "fcmgt v1.2d, v2.2d, v3.2d"),
            (cmhi_2d(1, 2, 3), "cmhi v1.2d, v2.2d, v3.2d"),
            (and_16b(1, 2, 3), "and v1.16b, v2.16b, v3.16b"),
            (orr_16b(1, 2, 3), "orr v1.16b, v2.16b, v3.16b"),
            (bsl_16b(1, 2, 3), "bsl v1.16b, v2.16b, v3.16b"),
            (dup_2d_elem0(1, 2), "dup v1.2d, v2.d[0]"),
            (dup_2d_x(1, 2), "dup v1.2d, x2"),
            (addp_d(1, 2), "addp d1, v2.2d"),
            (faddp_d(1, 2), "faddp d1, v2.2d"),
            (movi_2d_zero(3), "movi v3.2d, #0"),
            (umov_x_d(1, 2, 0), "mov x1, v2.d[0]"),
            (umov_x_d(1, 2, 1), "mov x1, v2.d[1]"),
            (ins_d(1, 0, 2), "mov v1.d[0], v2.d[0]"),
            (ins_d(1, 1, 2), "mov v1.d[1], v2.d[0]"),
            (dup_d_elem(1, 2, 1), "mov d1, v2.d[1]"),
            (dup_d_elem(1, 2, 0), "mov d1, v2.d[0]"),
            (b(8), "b #8"),
            (b_cond(cond::LS, -8), "b.ls #-8"),
            (cbnz(true, 3, 12), "cbnz x3, #12"),
            (cbz(true, 3, 12), "cbz x3, #12"),
        ];
        let text: Vec<&str> = cases.iter().map(|(_, t)| *t).collect();
        let want = reference(&text);
        assert_eq!(want.len(), cases.len());
        let mut bad = Vec::new();
        for ((got, t), w) in cases.iter().zip(want) {
            if *got != w {
                bad.push(format!("{t}: got {got:08x} want {w:08x}"));
            }
        }
        assert!(bad.is_empty(), "{}", bad.join("\n"));
    }
}
