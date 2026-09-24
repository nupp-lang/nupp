//! The numeric contract, checked on what LLVM actually produced.
//!
//! Nupp's floating point is binary64 with no contraction and no reassociation,
//! except where the source asked: `@relax("fp-contract")` functions may fuse,
//! and algebraic reducers may reassociate their sums. The emitter marks such
//! functions with the string attributes `"nupp-fp-contract"` and
//! `"nupp-algebraic"`. These checks read the optimized IR and the assembly and
//! report anything outside those licences. They do not trust the emitter: they
//! are how a wrong emitter or a surprising pass is caught.

use std::collections::{HashMap, HashSet};

/// Flags LLVM may infer from facts it proves (InstCombine's FP-class
/// analysis). They change no result and are not licences.
const FACTS: &[&str] = &["nnan", "ninf", "nsz"];
const LICENCES: &[&str] = &["fast", "contract", "arcp", "afn", "reassoc"];

/// Functions (by IR name) carrying each licence, read from attribute groups.
struct Licences {
    contract: HashSet<String>,
    algebraic: HashSet<String>,
}

fn licences(ir: &str) -> Licences {
    let mut groups: HashMap<String, String> = HashMap::new();
    for line in ir.lines() {
        if let Some(rest) = line.strip_prefix("attributes #") {
            if let Some((number, body)) = rest.split_once(" = ") {
                groups.insert(number.trim().to_string(), body.to_string());
            }
        }
    }
    let mut result = Licences { contract: HashSet::new(), algebraic: HashSet::new() };
    for line in ir.lines().filter(|l| l.starts_with("define ")) {
        let Some(name) = function_name(line) else { continue };
        let tail = &line[line.find(')').unwrap_or(0)..];
        let mut text = tail.to_string();
        for word in tail.split_whitespace() {
            if let Some(number) = word.strip_prefix('#') {
                if let Some(body) = groups.get(number) {
                    text.push_str(body);
                }
            }
        }
        if text.contains("\"nupp-fp-contract\"") {
            result.contract.insert(name.clone());
        }
        if text.contains("\"nupp-algebraic\"") {
            result.algebraic.insert(name);
        }
    }
    result
}

fn function_name(define: &str) -> Option<String> {
    let at = define.find('@')?;
    let rest = &define[at + 1..];
    let rest = rest.strip_prefix('"').unwrap_or(rest);
    let end = rest.find(|c: char| c == '(' || c == '"').unwrap_or(rest.len());
    Some(rest[..end].to_string())
}

/// Violations of the numeric contract in optimized IR text.
pub fn ir_contract(ir: &str) -> Vec<String> {
    let allowed = licences(ir);
    let mut function = String::new();
    let mut bad = Vec::new();
    for line in ir.lines() {
        if line.starts_with("define ") {
            function = function_name(line).unwrap_or_default();
            continue;
        }
        if line.starts_with('}') {
            function.clear();
            continue;
        }
        if function.is_empty() {
            continue;
        }
        let contracting = allowed.contract.contains(&function);
        let words: Vec<&str> = line.split_whitespace().collect();
        if (line.contains("@llvm.fmuladd") || line.contains("@llvm.fma.")) && !contracting {
            bad.push(format!("{function}: fused multiply-add outside an fp-contract function: {}", line.trim()));
        }
        let marked: Vec<&str> = words.iter().copied().filter(|w| LICENCES.contains(w)).collect();
        for flag in marked {
            let ok = match flag {
                "contract" => contracting,
                "reassoc" => {
                    allowed.algebraic.contains(&function)
                        && (line.contains("@llvm.vector.reduce.fadd") || words.contains(&"fadd"))
                }
                _ => false,
            };
            if !ok {
                bad.push(format!("{function}: `{flag}` outside its licence: {}", line.trim()));
            }
        }
        let _ = FACTS;
    }
    bad
}

/// Fused multiply-add instructions in an assembly listing, outside the
/// functions `ir` licenses to contract. Covers AArch64 and x86 spellings.
pub fn fused_instructions(assembly: &str, ir: &str) -> Vec<String> {
    let allowed = licences(ir).contract;
    let mut function = String::new();
    let mut bad = Vec::new();
    for line in assembly.lines() {
        if !line.starts_with(|c: char| c.is_whitespace()) && line.ends_with(':') {
            let label = line.trim_end_matches(':');
            if !label.starts_with('L') && !label.starts_with('.') && !label.starts_with("ltmp") {
                function = label.trim_start_matches('_').to_string();
            }
            continue;
        }
        let op = line.split_whitespace().next().unwrap_or("");
        let fused = ["fmadd", "fmsub", "fnmadd", "fnmsub", "fmla", "fmls"].contains(&op)
            || op.starts_with("vfmadd")
            || op.starts_with("vfmsub")
            || op.starts_with("vfnmadd")
            || op.starts_with("vfnmsub")
            || op.starts_with("f64x2.relaxed_madd");
        if fused && !allowed.contains(&function) {
            bad.push(format!("{function}: {}", line.trim()));
        }
    }
    bad
}

#[cfg(test)]
mod tests {
    use super::*;

    const IR: &str = r#"
define void @plain(ptr %a) #0 {
  %x = fmul nnan double 1.0, 2.0
  %y = fadd reassoc double %x, 1.0
  ret void
}
define double @sum(<4 x double> %v) #1 {
  %r = call reassoc double @llvm.vector.reduce.fadd.v4f64(double -0.0, <4 x double> %v)
  ret double %r
}
define double @relaxed(double %a, double %b, double %c) #2 {
  %r = call double @llvm.fmuladd.f64(double %a, double %b, double %c)
  %s = fmul contract double %r, %a
  ret double %s
}
attributes #0 = { nounwind }
attributes #1 = { nounwind "nupp-algebraic" }
attributes #2 = { "nupp-fp-contract" }
"#;

    #[test]
    fn licences_follow_attributes() {
        let bad = ir_contract(IR);
        assert_eq!(bad.len(), 1, "{bad:?}");
        assert!(bad[0].starts_with("plain:"), "{bad:?}");
    }

    #[test]
    fn fused_instructions_outside_contract_functions() {
        let asm = "_plain:\n\tfmadd d0, d0, d1, d2\n\tret\n_relaxed:\n\tfmadd d0, d0, d1, d2\n";
        let bad = fused_instructions(asm, IR);
        assert_eq!(bad.len(), 1, "{bad:?}");
        assert!(bad[0].starts_with("plain:"));
    }
}
