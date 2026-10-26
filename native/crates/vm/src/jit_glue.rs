//! The JIT's glue (gate N09): the hand-off between the runtime and the Nupp
//! emitter (`nupp.compiler.clif.guest`), which lowers a guest function's
//! bytecode to CLIF. The description below is what the emitter reads.
use crate::interp::Function;

/// A function as the emitter reads it: the image's function dialect, every
/// constant as its raw word.
pub fn describe(f: &Function, fid: u32) -> String {
    let mut text = String::new();
    let sig: String = f.sig.iter().map(|&c| c as char).collect();
    text.push_str(&format!("function {} {fid} {} {} {} {sig}:{}{}\n", f.name, f.nparams, f.nregs, f.nireg, f.ret as char, if f.vararg { " vararg" } else { "" }));
    text.push_str(&format!("  vectors {}\n", f.nvreg));
    for (i, c) in f.consts.iter().enumerate() {
        text.push_str(&format!("  const {i} word {:#x}\n", c.0));
    }
    for (i, (default, offsets)) in f.jump_tables.iter().enumerate() {
        text.push_str(&format!("  table {i} {default}"));
        for off in offsets { text.push_str(&format!(" {off}")); }
        text.push('\n');
    }
    for op in &f.code {
        text.push_str("  ");
        text.push_str(op.name());
        for operand in op.operands() { text.push_str(&format!(" {operand}")); }
        text.push('\n');
    }
    text.push_str("end\n");
    text
}

