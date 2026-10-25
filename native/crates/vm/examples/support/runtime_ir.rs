//! A whole-function bridge for the private runtime-authoring experiment.
//! This is privileged native code, never an accepted guest image format.
use cranelift_codegen::ir::{
    FuncRef, InstBuilder, MemFlagsData, SigRef, Value,
    condcodes::{FloatCC, IntCC},
    types,
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
                    "constant" | "layout" | "asWord" | "bits" | "fromBits" | "pointer"
                    | "floor" | "neg" | "toFloat" | "toInt" | "unsignedFloat" | "unsignedInt"
                    | "index" => (1, true),
                    "both" | "either" | "loadFloat" | "fadd" | "fsub" | "fmul" | "fdiv" | "feq"
                    | "fne" | "flt" | "fle" | "load8" | "load32" | "load64" | "loadIndex"
                    | "loadPointer" | "shl" | "shr" | "offset" | "add" | "sub" | "mul" | "xor"
                    | "and" | "or" | "eq" | "ne" | "slt" | "sle" | "ult" | "ule" => (2, true),
                    "chooseWord" => (3, true),
                    "storeFloat" | "store64" | "storeIndex" | "storePointer" | "branch" => {
                        (3, false)
                    }
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
    state: Option<Value>,
    derived_frame: bool,
) -> Result<(), String> {
    let mut values: BTreeMap<usize, Value> = params[..6]
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
        for index in 0..operands {
            let expected = match ins.op.as_str() {
                "branch" | "asWord" | "both" | "either" => types::I8,
                "chooseWord" if index == 0 => types::I8,
                "fadd" | "fsub" | "fmul" | "fdiv" | "feq" | "fne" | "flt" | "fle" | "bits"
                | "floor" | "neg" | "toInt" | "unsignedInt" => types::F64,
                "storeFloat" if index == 2 => types::F64,
                _ => types::I64,
            };
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
                    "funcs" => std::mem::offset_of!(Ctx, funcs),
                    "FuncInfo.size" => std::mem::size_of::<nupp_vm::threaded::FuncInfo>(),
                    "FuncInfo.consts" => std::mem::offset_of!(nupp_vm::threaded::FuncInfo, consts),
                    "frame_mode" => std::mem::offset_of!(Ctx, frame_mode),
                    "jit_frames" => std::mem::offset_of!(Ctx, jit_frames),
                    "nframe_entries" => std::mem::offset_of!(Ctx, nframe_entries),
                    "Header.aux_len" => std::mem::offset_of!(nupp_vm::heap::Header, aux_len),
                    "Header.aux" => std::mem::offset_of!(nupp_vm::heap::Header, aux),
                    "Header.flags" => std::mem::offset_of!(nupp_vm::heap::Header, flags),
                    "Table.meta" => nupp_vm::heap::OFF_T_META as usize,
                    "Header.kind" => std::mem::offset_of!(nupp_vm::heap::Header, kind),
                    "Header.aux_ptr" => std::mem::offset_of!(nupp_vm::heap::Header, aux_ptr),
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
            "loadFloat" | "load8" | "load32" | "load64" | "loadIndex" | "loadPointer" => {
                let addr = b.ins().iadd(value(0)?, value(1)?);
                Some(match ins.op.as_str() {
                    "loadFloat" => b.ins().load(types::F64, flags, addr, 0),
                    "load8" => b.ins().uload8(types::I64, flags, addr, 0),
                    "load32" => b.ins().sload32(flags, addr, 0),
                    _ => b.ins().load(types::I64, flags, addr, 0),
                })
            }
            "storeFloat" | "store64" | "storeIndex" | "storePointer" => {
                let addr = b.ins().iadd(value(0)?, value(1)?);
                b.ins().store(flags, value(2)?, addr, 0);
                None
            }
            "both" => Some(b.ins().band(value(0)?, value(1)?)),
            "either" => Some(b.ins().bor(value(0)?, value(1)?)),
            "chooseWord" => Some(b.ins().select(value(0)?, value(1)?, value(2)?)),
            "bits" => Some(b.ins().bitcast(types::I64, MemFlagsData::new(), value(0)?)),
            "fromBits" => Some(b.ins().bitcast(types::F64, MemFlagsData::new(), value(0)?)),
            "pointer" | "index" => Some(value(0)?),
            "unsignedFloat" => Some(b.ins().fcvt_from_uint(types::F64, value(0)?)),
            "unsignedInt" => Some(b.ins().fcvt_to_uint_sat(types::I64, value(0)?)),
            "floor" => Some(b.ins().floor(value(0)?)),
            "neg" => Some(b.ins().fneg(value(0)?)),
            "toFloat" => Some(b.ins().fcvt_from_sint(types::F64, value(0)?)),
            "toInt" => Some(b.ins().fcvt_to_sint_sat(types::I64, value(0)?)),
            "fadd" => Some(b.ins().fadd(value(0)?, value(1)?)),
            "fsub" => Some(b.ins().fsub(value(0)?, value(1)?)),
            "fmul" => Some(b.ins().fmul(value(0)?, value(1)?)),
            "fdiv" => Some(b.ins().fdiv(value(0)?, value(1)?)),
            "feq" | "fne" | "flt" | "fle" => {
                let cc = match ins.op.as_str() {
                    "feq" => FloatCC::Equal,
                    "fne" => FloatCC::NotEqual,
                    "flt" => FloatCC::LessThan,
                    _ => FloatCC::LessThanOrEqual,
                };
                Some(b.ins().fcmp(cc, value(0)?, value(1)?))
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
                let mut args = (0..6).map(value).collect::<Result<Vec<_>, _>>()?;
                let table = table.unwrap_or_else(|| b.ins().load(types::I64, flags, args[4], 0));
                let opcode = b.ins().uload8(types::I64, flags, args[0], 0);
                let offset = b.ins().ishl_imm_u(opcode, 3);
                let slot = b.ins().iadd(table, offset);
                let callee = b.ins().load(types::I64, flags, slot, 0);
                if let Some(state) = state {
                    args[4] = state;
                    args[5] = table;
                }
                if derived_frame {
                    args[5] = table;
                }
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
