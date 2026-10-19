use super::graph::{BOOL, F64, Graph};
use cranelift_codegen::{
    ir::{self, AbiParam, InstBuilder, MemFlagsData as MemFlags, types},
    settings::{self, Configurable},
};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Switch};
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{Linkage, Module};

pub enum Input {
    Number(f64),
    Text(Vec<u8>),
}
pub struct Inputs {
    pub strings: Vec<Vec<u8>>,
}
extern "C" fn length(inputs: &Inputs, id: u64) -> f64 {
    inputs.strings[id as usize].len() as f64
}
extern "C" fn byte(inputs: &Inputs, id: u64, index: f64) -> f64 {
    let bytes = &inputs.strings[id as usize];
    let i = index as i64;
    let offset = if i > 0 {
        usize::try_from(i - 1).ok()
    } else if i < 0 {
        usize::try_from(i.unsigned_abs())
            .ok()
            .and_then(|n| bytes.len().checked_sub(n))
    } else {
        None
    };
    offset.and_then(|i| bytes.get(i)).copied().unwrap_or(0) as f64
}
fn ty(t: u32) -> ir::Type {
    match t {
        F64 => types::F64,
        BOOL => types::I8,
        _ => types::I64,
    }
}

pub struct Native {
    module: Option<JITModule>,
    pub functions: Vec<Compiled>,
}
pub struct Compiled {
    pub entry: unsafe extern "C" fn(&Inputs, *mut u64) -> u32,
    pub slots: usize,
    pub clif: String,
    pub code_bytes: usize,
}
impl Drop for Native {
    fn drop(&mut self) {
        if let Some(module) = self.module.take() {
            unsafe {
                module.free_memory();
            }
        }
    }
}
impl Native {
    pub fn compile(graphs: &[Graph], optimize: bool, dump: bool) -> Result<Self, String> {
        let mut flags = settings::builder();
        flags
            .set("opt_level", if optimize { "speed" } else { "none" })
            .unwrap();
        flags.set("enable_verifier", "true").unwrap();
        flags.set("is_pic", "false").unwrap();
        flags.set("use_colocated_libcalls", "false").unwrap();
        flags.set("preserve_frame_pointers", "true").unwrap();
        let isa = cranelift_native::builder()
            .map_err(|e| e.to_string())?
            .finish(settings::Flags::new(flags))
            .map_err(|e| e.to_string())?;
        let mut jb = JITBuilder::with_isa(isa, cranelift_module::default_libcall_names());
        jb.symbol("cfg_length", length as *const u8);
        jb.symbol("cfg_byte", byte as *const u8);
        let mut module = JITModule::new(jb);
        let ptr = module.target_config().pointer_type();
        let mut helper = module.make_signature();
        helper
            .params
            .extend([AbiParam::new(ptr), AbiParam::new(types::I64)]);
        helper.returns.push(AbiParam::new(types::F64));
        let length_id = module
            .declare_function("cfg_length", Linkage::Import, &helper)
            .map_err(|e| e.to_string())?;
        helper.params.push(AbiParam::new(types::F64));
        let byte_id = module
            .declare_function("cfg_byte", Linkage::Import, &helper)
            .map_err(|e| e.to_string())?;
        let mut compiled = Vec::new();
        for g in graphs {
            let mut ctx = module.make_context();
            ctx.func
                .signature
                .params
                .extend([AbiParam::new(ptr), AbiParam::new(ptr)]);
            ctx.func.signature.returns.push(AbiParam::new(types::I32));
            let id = module
                .declare_function(&g.name, Linkage::Local, &ctx.func.signature)
                .map_err(|e| e.to_string())?;
            let length_ref = module.declare_func_in_func(length_id, &mut ctx.func);
            let byte_ref = module.declare_func_in_func(byte_id, &mut ctx.func);
            let mut fbc = FunctionBuilderContext::new();
            let mut b = FunctionBuilder::new(&mut ctx.func, &mut fbc);
            let entry = b.create_block();
            b.append_block_params_for_function_params(entry);
            b.switch_to_block(entry);
            let inputs = b.block_params(entry)[0];
            let slots = b.block_params(entry)[1];
            let blocks: Vec<_> = g.blocks.iter().map(|_| b.create_block()).collect();
            let mut values = vec![None; g.types.len()];
            for (bb, block) in blocks.iter().zip(&g.blocks) {
                for &p in g.params(block) {
                    values[p as usize] = Some(b.append_block_param(*bb, ty(g.types[p as usize])));
                }
            }
            let mut resumes = std::collections::BTreeSet::from([0]);
            for block in &g.blocks {
                if block.term == 3 {
                    resumes.insert(g.successors(block)[0].target);
                }
            }
            let mut switch = Switch::new();
            let bad = b.create_block();
            let mut entries = Vec::new();
            for target in resumes {
                let bb = b.create_block();
                switch.set_entry(target as u128, bb);
                entries.push((target, bb));
            }
            let resume = b.ins().load(types::I64, MemFlags::trusted(), slots, 0);
            switch.emit(&mut b, resume, bad);
            b.switch_to_block(bad);
            let status = b.ins().iconst(types::I32, 2);
            b.ins().return_(&[status]);
            for (target, stub) in entries {
                b.switch_to_block(stub);
                let mut args = Vec::new();
                for (i, &p) in g.params(&g.blocks[target as usize]).iter().enumerate() {
                    let v = b.ins().load(
                        ty(g.types[p as usize]),
                        MemFlags::trusted(),
                        slots,
                        ((i + 2) * 8) as i32,
                    );
                    args.push(ir::BlockArg::Value(v));
                }
                b.ins().jump(blocks[target as usize], &args);
            }
            for (bid, block) in g.blocks.iter().enumerate() {
                b.switch_to_block(blocks[bid]);
                for &[op, d, a, c] in block.nodes.get(&g.nodes) {
                    let x = if op == 0 { None } else { values[a as usize] };
                    let y = if matches!(op, 1..=6 | 8) {
                        values[c as usize]
                    } else {
                        None
                    };
                    let v = match op {
                        0 => b.ins().f64const(g.constants[a as usize]),
                        1 => b.ins().fadd(x.unwrap(), y.unwrap()),
                        2 => b.ins().fsub(x.unwrap(), y.unwrap()),
                        3 => b.ins().fmul(x.unwrap(), y.unwrap()),
                        4..=6 => {
                            let cc = match op {
                                4 => ir::condcodes::FloatCC::LessThan,
                                5 => ir::condcodes::FloatCC::LessThanOrEqual,
                                _ => ir::condcodes::FloatCC::Equal,
                            };
                            b.ins().fcmp(cc, x.unwrap(), y.unwrap())
                        }
                        7 => {
                            let c = b.ins().call(length_ref, &[inputs, x.unwrap()]);
                            b.inst_results(c)[0]
                        }
                        8 => {
                            let c = b.ins().call(byte_ref, &[inputs, x.unwrap(), y.unwrap()]);
                            b.inst_results(c)[0]
                        }
                        _ => unreachable!(),
                    };
                    values[d as usize] = Some(v);
                }
                let args = |edge: &super::graph::Edge| {
                    g.args(edge)
                        .iter()
                        .map(|&v| ir::BlockArg::Value(values[v as usize].unwrap()))
                        .collect::<Vec<_>>()
                };
                let edges = g.successors(block);
                match block.term {
                    0 | 3 => {
                        b.ins().store(
                            MemFlags::trusted(),
                            values[block.value as usize].unwrap(),
                            slots,
                            8,
                        );
                        if block.term == 3 {
                            let e = &edges[0];
                            let target = b.ins().iconst(types::I64, e.target as i64);
                            b.ins().store(MemFlags::trusted(), target, slots, 0);
                            for (i, &v) in g.args(e).iter().enumerate() {
                                b.ins().store(
                                    MemFlags::trusted(),
                                    values[v as usize].unwrap(),
                                    slots,
                                    ((i + 2) * 8) as i32,
                                );
                            }
                        }
                        let status = b
                            .ins()
                            .iconst(types::I32, if block.term == 3 { 1 } else { 0 });
                        b.ins().return_(&[status]);
                    }
                    1 => {
                        b.ins()
                            .jump(blocks[edges[0].target as usize], &args(&edges[0]));
                    }
                    2 => {
                        b.ins().brif(
                            values[block.value as usize].unwrap(),
                            blocks[edges[0].target as usize],
                            &args(&edges[0]),
                            blocks[edges[1].target as usize],
                            &args(&edges[1]),
                        );
                    }
                    _ => unreachable!(),
                }
            }
            b.seal_all_blocks();
            b.finalize(module.target_config());
            let clif = if dump {
                ctx.func.display().to_string()
            } else {
                String::new()
            };
            module
                .define_function(id, &mut ctx)
                .map_err(|e| format!("{}: {e:?}\n{clif}", g.name))?;
            let size = ctx.compiled_code().unwrap().code_buffer().len();
            compiled.push((
                id,
                g.blocks
                    .iter()
                    .map(|b| b.params.len as usize)
                    .max()
                    .unwrap()
                    + 2,
                clif,
                size,
            ));
        }
        module.finalize_definitions().map_err(|e| e.to_string())?;
        let functions =
            compiled
                .into_iter()
                .map(|(id, slots, clif, code_bytes)| Compiled {
                    entry: unsafe {
                        std::mem::transmute::<
                            *const u8,
                            unsafe extern "C" fn(&Inputs, *mut u64) -> u32,
                        >(module.get_finalized_function(id))
                    },
                    slots,
                    clif,
                    code_bytes,
                })
                .collect();
        Ok(Self {
            module: Some(module),
            functions,
        })
    }
    pub fn run(&self, index: usize, g: &Graph, args: &[Input]) -> Vec<f64> {
        assert_eq!(args.len(), g.params(&g.blocks[0]).len());
        let f = &self.functions[index];
        let mut slots = vec![0; f.slots];
        let mut inputs = Inputs { strings: vec![] };
        for (i, (arg, &p)) in args.iter().zip(g.params(&g.blocks[0])).enumerate() {
            slots[i + 2] = match arg {
                Input::Number(n) => {
                    assert_eq!(g.types[p as usize], F64);
                    n.to_bits()
                }
                Input::Text(s) => {
                    assert_eq!(g.types[p as usize], super::graph::TEXT);
                    let id = inputs.strings.len() as u64;
                    inputs.strings.push(s.clone());
                    id
                }
            };
        }
        let mut trace = Vec::new();
        for _ in 0..10000 {
            let status = unsafe { (f.entry)(&inputs, slots.as_mut_ptr()) };
            assert!(status <= 1, "invalid resume");
            trace.push(f64::from_bits(slots[1]));
            if status == 0 {
                return trace;
            }
        }
        panic!("suspension limit exceeded")
    }
}
