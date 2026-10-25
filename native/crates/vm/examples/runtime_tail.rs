//! Native runtime ABI experiment. No production dispatch or image semantics change.
//! Run with --features aot --example runtime_tail -- <output directory> [iterations].
#![feature(explicit_tail_calls)]
#![allow(incomplete_features)]
#![allow(unsafe_op_in_unsafe_fn)]
#![allow(unexpected_cfgs)] // runtime_tail_object is used only by the standalone link probe.

use cranelift_codegen::{
    ir::{AbiParam, InstBuilder, MemFlagsData, Signature, types},
    isa::CallConv,
    settings::{self, Configurable},
};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext};
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{FuncId, Linkage, Module};
use nupp_vm::threaded::Ins;
use std::{hint::black_box, mem::offset_of, path::Path, time::Instant};

#[path = "support/runtime_ir.rs"]
mod runtime_ir;

type Entry =
    unsafe extern "C" fn(*const Ins, *mut u64, *mut i64, *mut f64, *mut Context, *mut u64) -> u64;
type Handler = unsafe fn(*const Ins, *mut u64, *mut i64, *mut f64, *mut Context, *mut u64) -> u64;
const STOP: u8 = 0;
const ADD: u8 = 1;
const XOR: u8 = 2;
const LOOP: u8 = 3;
const HELPER: u8 = 4;
const CALL: u8 = 5;
const RET: u8 = 6;
const COUNT: usize = 7;

#[repr(C)]
struct Context {
    table: *const usize,
    helper_calls: u64,
    stack_min: usize,
    stack_max: usize,
    stack: [u64; 8],
    depth: u64,
}

impl Context {
    fn new(table: *const usize) -> Self {
        Self {
            table,
            helper_calls: 0,
            stack_min: usize::MAX,
            stack_max: 0,
            stack: [0; 8],
            depth: 0,
        }
    }
}

// This helper intentionally changes every live register class and touches a
// stack local. It detects lost values across the host ABI and growing native
// stacks; the production collector is not part of this ABI-only experiment.
#[inline(never)]
#[unsafe(no_mangle)]
unsafe extern "C" fn probe_helper(
    ctx: *mut Context,
    regs: *mut u64,
    ints: *mut i64,
    floats: *mut f64,
    frame: *mut u64,
) {
    let local = black_box(0u64);
    let address = black_box(&local as *const u64 as usize);
    (*ctx).stack_min = (*ctx).stack_min.min(address);
    (*ctx).stack_max = (*ctx).stack_max.max(address);
    (*ctx).helper_calls += 1;
    *regs = regs.read().wrapping_add(1);
    *ints = ints.read().wrapping_add(3);
    *floats += 0.5;
    *frame = frame.read().wrapping_add(7);
}

static RUST_TABLE: [Handler; COUNT] = [stop, add, xor, loop_back, host, call, ret];

macro_rules! next {
    ($pc:expr, $r:expr, $i:expr, $f:expr, $c:expr, $s:expr) => {
        become (*RUST_TABLE.get_unchecked((*$pc).op as usize))($pc, $r, $i, $f, $c, $s)
    };
}

unsafe fn stop(
    _: *const Ins,
    r: *mut u64,
    _: *mut i64,
    _: *mut f64,
    _: *mut Context,
    _: *mut u64,
) -> u64 {
    *r
}
unsafe fn add(
    pc: *const Ins,
    r: *mut u64,
    i: *mut i64,
    f: *mut f64,
    c: *mut Context,
    s: *mut u64,
) -> u64 {
    let op = *pc;
    *i.add(op.a as usize) = i
        .add(op.b as usize)
        .read()
        .wrapping_add(i.add(op.c as usize).read());
    let pc = pc.add(1);
    next!(pc, r, i, f, c, s);
}
unsafe fn xor(
    pc: *const Ins,
    r: *mut u64,
    i: *mut i64,
    f: *mut f64,
    c: *mut Context,
    s: *mut u64,
) -> u64 {
    let op = *pc;
    *i.add(op.a as usize) = i.add(op.b as usize).read() ^ op.k;
    let pc = pc.add(1);
    next!(pc, r, i, f, c, s);
}
unsafe fn loop_back(
    pc: *const Ins,
    r: *mut u64,
    i: *mut i64,
    f: *mut f64,
    c: *mut Context,
    s: *mut u64,
) -> u64 {
    let op = *pc;
    let counter = i.add(op.a as usize);
    *counter -= 1;
    let pc = if *counter != 0 {
        pc.offset(op.imm as isize)
    } else {
        pc.add(1)
    };
    next!(pc, r, i, f, c, s);
}
unsafe fn host(
    pc: *const Ins,
    r: *mut u64,
    i: *mut i64,
    f: *mut f64,
    c: *mut Context,
    s: *mut u64,
) -> u64 {
    probe_helper(c, r, i, f, s);
    let pc = pc.add(1);
    next!(pc, r, i, f, c, s);
}
unsafe fn call(
    pc: *const Ins,
    r: *mut u64,
    i: *mut i64,
    f: *mut f64,
    c: *mut Context,
    s: *mut u64,
) -> u64 {
    (*c).stack[(*c).depth as usize] = pc.add(1) as u64;
    (*c).depth += 1;
    let pc = pc.offset((*pc).imm as isize);
    next!(pc, r, i, f, c, s);
}
unsafe fn ret(
    _: *const Ins,
    r: *mut u64,
    i: *mut i64,
    f: *mut f64,
    c: *mut Context,
    s: *mut u64,
) -> u64 {
    (*c).depth -= 1;
    let pc = (*c).stack[(*c).depth as usize] as *const Ins;
    next!(pc, r, i, f, c, s);
}
unsafe extern "C" fn rust_entry(
    pc: *const Ins,
    r: *mut u64,
    i: *mut i64,
    f: *mut f64,
    c: *mut Context,
    s: *mut u64,
) -> u64 {
    RUST_TABLE[(*pc).op as usize](pc, r, i, f, c, s)
}

fn signature(cc: CallConv) -> Signature {
    let mut sig = Signature::new(cc);
    sig.params = vec![AbiParam::new(types::I64); 6];
    sig.returns.push(AbiParam::new(types::I64));
    sig
}

fn generate<M: Module>(
    module: &mut M,
    out: &Path,
    label: &str,
    preserve: bool,
    source: Option<&runtime_ir::Program>,
) -> Result<(FuncId, Vec<FuncId>), String> {
    let tail = signature(CallConv::Tail);
    let ids: Vec<_> = (0..COUNT)
        .map(|op| {
            module
                .declare_function(&format!("handler_{op}"), Linkage::Local, &tail)
                .unwrap()
        })
        .collect();
    let mut hs = module.make_signature();
    hs.params = vec![AbiParam::new(types::I64); 5];
    let hid = module
        .declare_function("probe_helper", Linkage::Import, &hs)
        .unwrap();
    let entry_sig = signature(module.isa().default_call_conv());
    let entry = module
        .declare_function("runtime_entry", Linkage::Export, &entry_sig)
        .unwrap();
    let mut listings = String::new();
    for which in 0..=COUNT {
        let mut ctx = module.make_context();
        ctx.want_disasm = true;
        ctx.func.signature = if which == COUNT {
            entry_sig.clone()
        } else {
            tail.clone()
        };
        let mut fbc = FunctionBuilderContext::new();
        {
            let mut b = FunctionBuilder::new(&mut ctx.func, &mut fbc);
            let start = b.create_block();
            b.append_block_params_for_function_params(start);
            b.switch_to_block(start);
            b.seal_block(start);
            let args = b.block_params(start).to_vec();
            let [pc, regs, ints, floats, context, frame]: [_; 6] = args.clone().try_into().unwrap();
            let flags = MemFlagsData::new().with_notrap();
            let ts = b.import_signature(tail.clone());
            if let Some(function) = source
                .and_then(|source| source.functions.get(which))
                .filter(|_| which < COUNT)
            {
                let helper = module.declare_func_in_func(hid, b.func);
                runtime_ir::emit(function, &mut b, &args, ts, helper, None)?;
            } else if which == COUNT {
                let table = b.ins().load(
                    types::I64,
                    flags,
                    context,
                    offset_of!(Context, table) as i32,
                );
                let op = b.ins().uload8(types::I64, flags, pc, 0);
                let off = b.ins().ishl_imm_u(op, 3);
                let addr = b.ins().iadd(table, off);
                let handler = b.ins().load(types::I64, flags, addr, 0);
                let call = b.ins().call_indirect(ts, handler, &args);
                let result = b.inst_results(call)[0];
                b.ins().return_(&[result]);
            } else if which == STOP as usize {
                let value = b.ins().load(types::I64, flags, regs, 0);
                b.ins().return_(&[value]);
            } else {
                let mut next_pc = b.ins().iadd_imm_s(pc, size_of::<Ins>() as i64);
                match which as u8 {
                    ADD | XOR => {
                        let a = b.ins().uload8(types::I64, flags, pc, 1);
                        let x = b.ins().uload8(types::I64, flags, pc, 2);
                        let a = b.ins().ishl_imm_u(a, 3);
                        let x = b.ins().ishl_imm_u(x, 3);
                        let dest = b.ins().iadd(ints, a);
                        let src = b.ins().iadd(ints, x);
                        let x = b.ins().load(types::I64, flags, src, 0);
                        let value = if which == ADD as usize {
                            let y = b.ins().uload8(types::I64, flags, pc, 3);
                            let y = b.ins().ishl_imm_u(y, 3);
                            let src = b.ins().iadd(ints, y);
                            let y = b.ins().load(types::I64, flags, src, 0);
                            b.ins().iadd(x, y)
                        } else {
                            let y = b.ins().load(types::I64, flags, pc, 8);
                            b.ins().bxor(x, y)
                        };
                        b.ins().store(flags, value, dest, 0);
                    }
                    LOOP => {
                        let a = b.ins().uload8(types::I64, flags, pc, 1);
                        let a = b.ins().ishl_imm_u(a, 3);
                        let addr = b.ins().iadd(ints, a);
                        let n = b.ins().load(types::I64, flags, addr, 0);
                        let n = b.ins().iadd_imm_s(n, -1);
                        b.ins().store(flags, n, addr, 0);
                        let off = b.ins().sload32(flags, pc, 4);
                        let off = b.ins().ishl_imm_u(off, 4);
                        let back = b.ins().iadd(pc, off);
                        next_pc = b.ins().select(n, back, next_pc);
                    }
                    HELPER => {
                        let h = module.declare_func_in_func(hid, b.func);
                        b.ins().call(h, &[context, regs, ints, floats, frame]);
                    }
                    CALL | RET => {
                        let depth = b.ins().load(
                            types::I64,
                            flags,
                            context,
                            offset_of!(Context, depth) as i32,
                        );
                        let index = if which == RET as usize {
                            b.ins().iadd_imm_s(depth, -1)
                        } else {
                            depth
                        };
                        let off = b.ins().ishl_imm_u(index, 3);
                        let addr = b.ins().iadd(context, off);
                        if which == CALL as usize {
                            b.ins()
                                .store(flags, next_pc, addr, offset_of!(Context, stack) as i32);
                            let off = b.ins().sload32(flags, pc, 4);
                            let off = b.ins().ishl_imm_u(off, 4);
                            next_pc = b.ins().iadd(pc, off);
                        } else {
                            next_pc = b.ins().load(
                                types::I64,
                                flags,
                                addr,
                                offset_of!(Context, stack) as i32,
                            );
                        }
                        let depth = if which == CALL as usize {
                            b.ins().iadd_imm_s(depth, 1)
                        } else {
                            index
                        };
                        b.ins()
                            .store(flags, depth, context, offset_of!(Context, depth) as i32);
                    }
                    _ => unreachable!(),
                }
                let table = b.ins().load(
                    types::I64,
                    flags,
                    context,
                    offset_of!(Context, table) as i32,
                );
                let op = b.ins().uload8(types::I64, flags, next_pc, 0);
                let off = b.ins().ishl_imm_u(op, 3);
                let addr = b.ins().iadd(table, off);
                let handler = b.ins().load(types::I64, flags, addr, 0);
                b.ins().return_call_indirect(
                    ts,
                    handler,
                    &[next_pc, regs, ints, floats, context, frame],
                );
            }
            b.seal_all_blocks();
            b.finalize(module.target_config());
        }
        listings.push_str(&format!(
            "\n; {label} handler {which} preserve_frame_pointers={preserve}\n{}\n",
            ctx.func.display()
        ));
        let id = if which == COUNT { entry } else { ids[which] };
        module
            .define_function(id, &mut ctx)
            .map_err(|e| e.to_string())?;
        if let Some(code) = ctx.compiled_code() {
            listings.push_str(code.vcode.as_deref().unwrap_or("; no disassembly"));
        }
    }
    std::fs::write(out.join(format!("{label}.txt")), listings).unwrap();
    Ok((entry, ids))
}

struct Native {
    module: JITModule,
    entry: Entry,
    table: Vec<usize>,
}
impl Native {
    fn build(
        out: &Path,
        label: &str,
        preserve: bool,
        opt: &str,
        source: Option<&runtime_ir::Program>,
    ) -> Self {
        let mut flags = settings::builder();
        flags.set("opt_level", opt).unwrap();
        flags
            .set(
                "preserve_frame_pointers",
                if preserve || cfg!(target_arch = "x86_64") {
                    "true"
                } else {
                    "false"
                },
            )
            .unwrap();
        let isa = cranelift_native::builder()
            .unwrap()
            .finish(settings::Flags::new(flags))
            .unwrap();
        let mut builder = JITBuilder::with_isa(isa, cranelift_module::default_libcall_names());
        builder.symbol("probe_helper", probe_helper as *const u8);
        let mut module = JITModule::new(builder);
        let (entry, ids) = generate(&mut module, out, label, preserve, source).unwrap();
        module.finalize_definitions().unwrap();
        let entry = unsafe {
            std::mem::transmute::<*const u8, Entry>(module.get_finalized_function(entry))
        };
        let table = ids
            .iter()
            .map(|id| module.get_finalized_function(*id) as usize)
            .collect();
        Self {
            module,
            entry,
            table,
        }
    }
}

fn object(out: &Path, triple: &str, source: Option<&runtime_ir::Program>) -> Result<(), String> {
    use cranelift_module::DataDescription;
    use cranelift_object::{ObjectBuilder, ObjectModule};
    let mut flags = settings::builder();
    flags.set("opt_level", "speed").unwrap();
    let preserve = triple.starts_with("x86_64");
    flags
        .set(
            "preserve_frame_pointers",
            if preserve { "true" } else { "false" },
        )
        .unwrap();
    flags.set("is_pic", "true").unwrap();
    flags.set("use_colocated_libcalls", "false").unwrap();
    let isa = cranelift_codegen::isa::lookup_by_name(triple)
        .map_err(|e| e.to_string())?
        .finish(settings::Flags::new(flags))
        .map_err(|e| e.to_string())?;
    let builder = ObjectBuilder::new(
        isa,
        "nupp-runtime-probe",
        cranelift_module::default_libcall_names(),
    )
    .unwrap();
    let mut module = ObjectModule::new(builder);
    let (_, ids) = generate(&mut module, out, triple, preserve, source)?;
    let table = module
        .declare_data("runtime_handlers", Linkage::Export, false, false)
        .unwrap();
    let mut data = DataDescription::new();
    data.define(vec![0; COUNT * 8].into_boxed_slice());
    data.set_align(8);
    for (index, id) in ids.into_iter().enumerate() {
        let function = module.declare_func_in_data(id, &mut data);
        data.write_function_addr((index * 8) as u32, function);
    }
    module
        .define_data(table, &data)
        .map_err(|e| e.to_string())?;
    let bytes = module.finish().emit().map_err(|e| e.to_string())?;
    std::fs::write(out.join(format!("{triple}.o")), bytes).map_err(|e| e.to_string())
}

#[cfg(runtime_tail_object)]
unsafe extern "C" {
    fn runtime_entry(
        pc: *const Ins,
        r: *mut u64,
        i: *mut i64,
        f: *mut f64,
        c: *mut Context,
        s: *mut u64,
    ) -> u64;
    static runtime_handlers: [usize; COUNT];
}

#[derive(Debug, PartialEq)]
struct ResultState {
    value: u64,
    ints: [i64; 4],
    floats: [f64; 1],
    frame: u64,
    calls: u64,
    depth: u64,
}
fn run(entry: Entry, table: *const usize, program: &[Ins], n: i64) -> ResultState {
    let mut ctx = Context::new(table);
    let mut regs = [11];
    let mut ints = [13, 17, 23, n];
    let mut floats = [1.25];
    let mut frame = 19;
    let value = unsafe {
        entry(
            program.as_ptr(),
            regs.as_mut_ptr(),
            ints.as_mut_ptr(),
            floats.as_mut_ptr(),
            &mut ctx,
            &mut frame,
        )
    };
    assert!(
        ctx.stack_max == 0 || ctx.stack_max - ctx.stack_min < 4096,
        "native stack grew"
    );
    ResultState {
        value,
        ints,
        floats,
        frame,
        calls: ctx.helper_calls,
        depth: ctx.depth,
    }
}

fn instruction(op: u8, a: u8, b: u8, c: u8, imm: i32, k: i64) -> Ins {
    Ins {
        op,
        a,
        b,
        c,
        imm,
        k,
    }
}
fn programs() -> Vec<(&'static str, Vec<Ins>)> {
    let add = instruction(ADD, 0, 0, 1, 0, 0);
    let xor = instruction(XOR, 1, 0, 0, 0, 0x123456789abcdef);
    let stop = instruction(STOP, 0, 0, 0, 0, 0);
    vec![
        (
            "arithmetic",
            vec![add, xor, instruction(LOOP, 3, 0, 0, -2, 0), stop],
        ),
        (
            "helper",
            vec![
                instruction(HELPER, 0, 0, 0, 0, 0),
                add,
                instruction(LOOP, 3, 0, 0, -2, 0),
                stop,
            ],
        ),
        (
            "calls",
            vec![
                instruction(CALL, 0, 0, 0, 3, 0),
                instruction(LOOP, 3, 0, 0, -1, 0),
                stop,
                add,
                xor,
                instruction(RET, 0, 0, 0, 0, 0),
            ],
        ),
    ]
}

fn main() {
    let mut args = std::env::args().skip(1);
    let path = args.next().expect("output directory");
    let out = Path::new(&path);
    std::fs::create_dir_all(out).unwrap();
    let iterations: i64 = args
        .next()
        .unwrap_or_else(|| "10000000".into())
        .parse()
        .unwrap();
    assert!(iterations > 0);
    let source = args
        .next()
        .map(|path| runtime_ir::Program::read(Path::new(&path)).unwrap());
    if let Some(source) = &source {
        assert_eq!(
            source
                .functions
                .iter()
                .map(|f| f.name.as_str())
                .collect::<Vec<_>>(),
            ["stop", "add", "xor", "loop_back", "host", "call", "ret"]
        );
        assert_eq!(offset_of!(Context, stack), 32);
        assert_eq!(offset_of!(Context, depth), 96);
        assert_eq!(size_of::<Ins>(), 16);
    }
    for triple in [
        "aarch64-apple-darwin",
        "x86_64-unknown-linux-gnu",
        "x86_64-pc-windows-gnu",
    ] {
        match object(out, triple, source.as_ref()) {
            Ok(()) => eprintln!("object: {triple}"),
            Err(e) => panic!(
                "object {triple}: {e}; build with cranelift-codegen/x86 and cranelift-codegen/arm64"
            ),
        }
    }
    let native = Native::build(out, "tail", false, "speed", None);
    let framed = Native::build(out, "tail-fp", true, "speed", None);
    let unoptimized = Native::build(out, "tail-none", false, "none", None);
    let authored = source
        .as_ref()
        .map(|source| Native::build(out, "nupp", false, "speed", Some(source)));
    let mut variants = vec![
        ("rust", rust_entry as Entry, std::ptr::null()),
        ("tail", native.entry, native.table.as_ptr()),
        ("tail-fp", framed.entry, framed.table.as_ptr()),
        ("tail-none", unoptimized.entry, unoptimized.table.as_ptr()),
    ];
    if let Some(nupp) = &authored {
        variants.push(("nupp", nupp.entry, nupp.table.as_ptr()));
    }
    #[cfg(runtime_tail_object)]
    variants.push((
        "nupp-aot",
        runtime_entry as Entry,
        std::ptr::addr_of!(runtime_handlers).cast(),
    ));
    for (name, program) in programs() {
        for count in [1, 2, 17, 100_000] {
            let expected = run(rust_entry, std::ptr::null(), &program, count);
            for (label, entry, table) in &variants {
                assert_eq!(
                    run(*entry, *table, &program, count),
                    expected,
                    "{name}/{label}/{count}"
                );
            }
        }
        let expected = run(rust_entry, std::ptr::null(), &program, iterations);
        for round in 0..12 {
            for v in 0..variants.len() {
                let (label, entry, table) = variants[(v + round) % variants.len()];
                let start = Instant::now();
                let actual = black_box(run(entry, table, &program, black_box(iterations)));
                let seconds = start.elapsed().as_secs_f64();
                assert_eq!(actual, expected, "{name}/{label}");
                println!("{name}\t{round}\t{label}\t{seconds:.9}\t{}", actual.ints[0]);
            }
        }
    }
    // Keep executable memory alive until every call has returned.
    black_box((&native.module, &framed.module, &unoptimized.module));
}
