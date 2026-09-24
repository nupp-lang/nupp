//! Machine IR: AArch64 operations over virtual registers in blocks, shaped
//! for `regalloc2`. Each `MInst` may expand to several machine instructions
//! at emission; its operand list is what the allocator sees, in the order the
//! emitter reads allocations back.

use regalloc2::{Block, Inst, InstRange, Operand, PRegSet, RegClass, VReg};

#[derive(Clone, Debug)]
pub enum Op {
    /// Entry: fixed defs of the incoming argument registers.
    Args,
    /// Return: fixed use of the result register, if any.
    Ret,
    Imm { value: u64 },
    LitD { bits: u64 },
    LitQ { bytes: [u8; 16] },
    Add { sf: bool },
    Sub { sf: bool },
    AddImm { sf: bool, imm: u32 },
    /// def = use0 + (use1 << 3)
    AddrIdx,
    UcvtfW,
    UcvtfX,
    FcvtzuW,
    FAdd,
    FSub,
    FMul,
    VFAdd,
    VFMul,
    VFCmGt,
    VAnd,
    VCmHi,
    /// def (reuses the mask) = mask ? a : b
    Bsl,
    DupD,
    DupX,
    /// def d = horizontal sum of two 2d registers
    SumPair,
    LdrIdx,
    StrIdx,
    Ldp { off: i32 },
    Stp { off: i32 },
    MaskedLoad,
    MaskedStore,
    Jump,
    CmpBr { sf: bool, cond: u32 },
    FCmpBr { cond: u32 },
    /// Branch if any lane of a two-register mask is set.
    AnyBr,
}

#[derive(Clone, Debug)]
pub struct MInst {
    pub op: Op,
    pub operands: Vec<Operand>,
    /// Successors of a terminator; the first is taken when a conditional
    /// branch's condition holds.
    pub succs: Vec<Block>,
    /// Outgoing block arguments, one list per successor.
    pub args: Vec<Vec<VReg>>,
}

impl MInst {
    pub fn new(op: Op, operands: Vec<Operand>) -> MInst {
        MInst { op, operands, succs: Vec::new(), args: Vec::new() }
    }
    pub fn is_branch(&self) -> bool {
        matches!(self.op, Op::Jump | Op::CmpBr { .. } | Op::FCmpBr { .. } | Op::AnyBr)
    }
}

pub struct BlockInfo {
    pub range: InstRange,
    pub params: Vec<VReg>,
    pub succs: Vec<Block>,
    pub preds: Vec<Block>,
}

pub struct Func {
    pub insts: Vec<MInst>,
    pub blocks: Vec<BlockInfo>,
    pub num_vregs: usize,
}

impl Func {
    /// Lays out blocks in the given order and numbers their instructions.
    pub fn build(order: &[usize], blocks: Vec<(Vec<VReg>, Vec<MInst>)>, num_vregs: usize) -> Func {
        let mut renumber = vec![usize::MAX; blocks.len()];
        for (new, old) in order.iter().enumerate() {
            renumber[*old] = new;
        }
        let mut slots: Vec<Option<(Vec<VReg>, Vec<MInst>)>> = blocks.into_iter().map(Some).collect();
        let mut insts = Vec::new();
        let mut infos = Vec::new();
        for old in order {
            let (params, mut body) = slots[*old].take().unwrap();
            for inst in &mut body {
                for succ in &mut inst.succs {
                    *succ = Block::new(renumber[succ.index()]);
                }
            }
            let succs = body.last().map(|t| t.succs.clone()).unwrap_or_default();
            let start = insts.len();
            insts.extend(body);
            infos.push(BlockInfo {
                range: InstRange::new(Inst::new(start), Inst::new(insts.len())),
                params,
                succs,
                preds: Vec::new(),
            });
        }
        for b in 0..infos.len() {
            for s in infos[b].succs.clone() {
                infos[s.index()].preds.push(Block::new(b));
            }
        }
        Func { insts, blocks: infos, num_vregs }
    }
}

impl regalloc2::Function for Func {
    fn num_insts(&self) -> usize {
        self.insts.len()
    }
    fn num_blocks(&self) -> usize {
        self.blocks.len()
    }
    fn entry_block(&self) -> Block {
        Block::new(0)
    }
    fn block_insns(&self, block: Block) -> InstRange {
        self.blocks[block.index()].range
    }
    fn block_succs(&self, block: Block) -> &[Block] {
        &self.blocks[block.index()].succs
    }
    fn block_preds(&self, block: Block) -> &[Block] {
        &self.blocks[block.index()].preds
    }
    fn block_params(&self, block: Block) -> &[VReg] {
        &self.blocks[block.index()].params
    }
    fn is_ret(&self, insn: Inst) -> bool {
        matches!(self.insts[insn.index()].op, Op::Ret)
    }
    fn is_branch(&self, insn: Inst) -> bool {
        self.insts[insn.index()].is_branch()
    }
    fn branch_blockparams(&self, _block: Block, insn: Inst, succ_idx: usize) -> &[VReg] {
        &self.insts[insn.index()].args[succ_idx]
    }
    fn inst_operands(&self, insn: Inst) -> &[Operand] {
        &self.insts[insn.index()].operands
    }
    fn inst_clobbers(&self, _insn: Inst) -> PRegSet {
        PRegSet::empty()
    }
    fn num_vregs(&self) -> usize {
        self.num_vregs
    }
    fn spillslot_size(&self, regclass: RegClass) -> usize {
        match regclass {
            RegClass::Int => 1,
            _ => 2,
        }
    }
}
