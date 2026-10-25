//! A whole-function bridge for the private runtime-authoring experiment.
//! This is privileged native code, never an accepted guest image format.
use cranelift_codegen::ir::{
    FuncRef, InstBuilder, MemFlagsData, SigRef, Value, condcodes::IntCC, types,
};
use cranelift_frontend::FunctionBuilder;
use serde_json::Value as Json;
use std::{
    collections::{BTreeMap, BTreeSet},
    path::Path,
};

pub struct Program {
    pub functions: Vec<Function>,
}
pub struct Function {
    pub name: String,
    instructions: Vec<Instruction>,
}
struct Instruction {
    op: String,
    args: Vec<Json>,
    result: usize,
}

impl Function {
    #[allow(dead_code)] // Used by runtime_slice; the synthetic ABI pilot permits helpers.
    pub fn require_leaf(&self) -> Result<(), String> {
        if self
            .instructions
            .iter()
            .any(|i| i.op == "helper" || i.op == "return")
        {
            return Err("VM slice may only dispatch or leave before executing a helper".into());
        }
        for instruction in &self.instructions {
            if instruction.op == "dispatch" || instruction.op == "slow" {
                let first = if instruction.op == "slow" { 0 } else { 1 };
                for parameter in first..6 {
                    if instruction.args[parameter].as_u64() != Some(parameter as u64 + 1) {
                        return Err("leaf transfer must preserve its VM windows and context; slow must preserve pc".into());
                    }
                }
            }
        }
        Ok(())
    }
}

impl Program {
    pub fn read(path: &Path) -> Result<Self, String> {
        let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
        if bytes.len() > 16 * 1024 * 1024 {
            return Err("native source exceeds 16 MiB".into());
        }
        let json: Json = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
        if json["format"] != "nupp-native-runtime-1" {
            return Err("unknown native source format".into());
        }
        let functions = json["functions"]
            .as_array()
            .ok_or("function array required")?;
        if functions.is_empty() || functions.len() > 256 {
            return Err("native function count outside 1..256".into());
        }
        let mut names = BTreeSet::new();
        let mut out = Vec::new();
        for function in functions {
            let name = function["name"].as_str().ok_or("function name required")?;
            if name.is_empty()
                || !name.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'_')
                || !names.insert(name.to_string())
            {
                return Err("invalid or duplicate function name".into());
            }
            let code = function["instructions"]
                .as_array()
                .ok_or("instruction array required")?;
            if code.is_empty() || code.len() > 10_000 {
                return Err("native instruction count outside 1..10000".into());
            }
            let mut instructions = Vec::new();
            for row in code {
                let op = row["op"].as_str().ok_or("opcode required")?.to_string();
                let (arity, result) = match op.as_str() {
                    "constant" | "layout" | "asWord" => (1, true),
                    "load8" | "load32" | "load64" | "loadIndex" | "loadPointer" | "shl" | "shr"
                    | "offset" | "add" | "sub" | "mul" | "xor" | "and" | "or" | "eq" | "ne"
                    | "slt" | "sle" | "ult" | "ule" => (2, true),
                    "store64" | "storeIndex" | "storePointer" | "branch" => (3, false),
                    "block" | "return" => (1, false),
                    "dispatch" | "slow" => (6, false),
                    "helper" => (5, false),
                    _ => return Err(format!("unknown native opcode {op}")),
                };
                let args = row["args"]
                    .as_array()
                    .ok_or("operand array required")?
                    .clone();
                if args.len() != arity {
                    return Err(format!("{op}: expected {arity} operands"));
                }
                let target = index(&row["result"])?;
                if (target != 0) != result || (result && target <= 6) || target > 100_000 {
                    return Err(format!("{op}: invalid result"));
                }
                instructions.push(Instruction {
                    op,
                    args,
                    result: target,
                });
            }
            out.push(Function {
                name: name.into(),
                instructions,
            });
        }
        Ok(Self { functions: out })
    }
}

fn index(v: &Json) -> Result<usize, String> {
    v.as_u64()
        .and_then(|n| usize::try_from(n).ok())
        .ok_or_else(|| "unsigned index required".into())
}

pub fn emit(
    function: &Function,
    b: &mut FunctionBuilder<'_>,
    params: &[Value],
    tail: SigRef,
    helper: FuncRef,
    table: Option<Value>,
) -> Result<(), String> {
    let mut values: BTreeMap<usize, Value> = params
        .iter()
        .enumerate()
        .map(|(i, v)| (i + 1, *v))
        .collect();
    let mut blocks = BTreeMap::new();
    for ins in &function.instructions {
        if ins.op == "block" {
            let label = index(&ins.args[0])?;
            if label == 0 || blocks.insert(label, b.create_block()).is_some() {
                return Err("duplicate or zero block label".into());
            }
        }
    }
    let flags = MemFlagsData::new().with_notrap();
    let mut ended = false;
    for ins in &function.instructions {
        if ended && ins.op != "block" {
            return Err("instruction after native terminator".into());
        }
        let value = |i: usize| -> Result<Value, String> {
            values
                .get(&index(&ins.args[i])?)
                .copied()
                .ok_or_else(|| format!("{}: undefined operand", ins.op))
        };
        let operands = match ins.op.as_str() {
            "block" | "constant" | "layout" => 0,
            "branch" => 1,
            _ => ins.args.len(),
        };
        let expected = if ins.op == "branch" || ins.op == "asWord" {
            types::I8
        } else {
            types::I64
        };
        for index in 0..operands {
            if b.func.dfg.value_type(value(index)?) != expected {
                return Err(format!(
                    "{}: operand has the wrong native representation",
                    ins.op
                ));
            }
        }
        let result = match ins.op.as_str() {
            "block" => {
                if !ended {
                    return Err("native block must end explicitly".into());
                }
                b.switch_to_block(blocks[&index(&ins.args[0])?]);
                ended = false;
                None
            }
            "layout" => {
                use nupp_vm::threaded::Ctx;
                let offset = match ins.args[0].as_str().ok_or("layout field required")? {
                    "frame_mode" => std::mem::offset_of!(Ctx, frame_mode),
                    "jit_frames" => std::mem::offset_of!(Ctx, jit_frames),
                    "nframe_entries" => std::mem::offset_of!(Ctx, nframe_entries),
                    _ => return Err("unknown context field".into()),
                };
                Some(b.ins().iconst(types::I64, offset as i64))
            }
            "constant" => {
                let text = ins.args[0]
                    .as_str()
                    .ok_or("integer constant must be a string")?;
                let v = text
                    .parse::<i64>()
                    .or_else(|_| text.parse::<u64>().map(|v| v as i64))
                    .map_err(|_| "integer constant outside 64 bits")?;
                Some(b.ins().iconst(types::I64, v))
            }
            "load8" | "load32" | "load64" | "loadIndex" | "loadPointer" => {
                let addr = b.ins().iadd(value(0)?, value(1)?);
                Some(match ins.op.as_str() {
                    "load8" => b.ins().uload8(types::I64, flags, addr, 0),
                    "load32" => b.ins().sload32(flags, addr, 0),
                    _ => b.ins().load(types::I64, flags, addr, 0),
                })
            }
            "store64" | "storeIndex" | "storePointer" => {
                let addr = b.ins().iadd(value(0)?, value(1)?);
                b.ins().store(flags, value(2)?, addr, 0);
                None
            }
            "asWord" => Some(b.ins().uextend(types::I64, value(0)?)),
            "shl" => Some(b.ins().ishl(value(0)?, value(1)?)),
            "shr" => Some(b.ins().ushr(value(0)?, value(1)?)),
            "add" | "offset" => Some(b.ins().iadd(value(0)?, value(1)?)),
            "sub" => Some(b.ins().isub(value(0)?, value(1)?)),
            "mul" => Some(b.ins().imul(value(0)?, value(1)?)),
            "xor" => Some(b.ins().bxor(value(0)?, value(1)?)),
            "and" => Some(b.ins().band(value(0)?, value(1)?)),
            "or" => Some(b.ins().bor(value(0)?, value(1)?)),
            "eq" | "ne" | "ult" | "ule" | "slt" | "sle" => {
                let cc = match ins.op.as_str() {
                    "eq" => IntCC::Equal,
                    "ne" => IntCC::NotEqual,
                    "ult" => IntCC::UnsignedLessThan,
                    "ule" => IntCC::UnsignedLessThanOrEqual,
                    "slt" => IntCC::SignedLessThan,
                    _ => IntCC::SignedLessThanOrEqual,
                };
                Some(b.ins().icmp(cc, value(0)?, value(1)?))
            }
            "helper" => {
                let args = (0..5).map(value).collect::<Result<Vec<_>, _>>()?;
                b.ins().call(helper, &args);
                None
            }
            "branch" => {
                let yes = *blocks
                    .get(&index(&ins.args[1])?)
                    .ok_or("unknown true block")?;
                let no = *blocks
                    .get(&index(&ins.args[2])?)
                    .ok_or("unknown false block")?;
                b.ins().brif(value(0)?, yes, &[], no, &[]);
                ended = true;
                None
            }
            "return" => {
                b.ins().return_(&[value(0)?]);
                ended = true;
                None
            }
            "slow" => {
                b.ins().return_(&[value(0)?]);
                ended = true;
                None
            }
            "dispatch" => {
                let args = (0..6).map(value).collect::<Result<Vec<_>, _>>()?;
                let table = table.unwrap_or_else(|| b.ins().load(types::I64, flags, args[4], 0));
                let opcode = b.ins().uload8(types::I64, flags, args[0], 0);
                let offset = b.ins().ishl_imm_u(opcode, 3);
                let slot = b.ins().iadd(table, offset);
                let callee = b.ins().load(types::I64, flags, slot, 0);
                b.ins().return_call_indirect(tail, callee, &args);
                ended = true;
                None
            }
            _ => unreachable!(),
        };
        if let Some(result) = result {
            if values.insert(ins.result, result).is_some() {
                return Err("duplicate native value".into());
            }
        }
    }
    if !ended {
        return Err("native function has no terminator".into());
    }
    Ok(())
}
