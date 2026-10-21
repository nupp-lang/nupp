//! Isolated typed block-argument experiment. Logical PCs and register slots
//! remain the production frame ABI. This importer is deliberately timed: it
//! does not pretend that existing bytecode came directly from a graph frontend.
use crate::{interp::Function, verify::RegSet};
use cranelift_codegen::ir::{Block, BlockArg, Value, types};
use cranelift_frontend::FunctionBuilder;
use std::collections::{BTreeSet, HashMap};

#[derive(Clone, Copy)]
struct Param {
    class: u8,
    slot: u8,
}

pub(crate) struct TypedCfg {
    // Dense spans into one parameter column; no allocation per parameter.
    spans: Vec<(u32, u32)>,
    params: Vec<Param>,
    values: [[Option<Value>; 256]; 3],
}

impl TypedCfg {
    pub fn new(f: &Function, starts: &BTreeSet<usize>, live: &[[RegSet; 4]]) -> Self {
        let mut spans = vec![(0, 0); f.code.len() + 1];
        let mut params = Vec::new();
        for &pc in starts {
            let start = params.len() as u32;
            for class in 0..3 {
                for slot in live[pc][class + 1].iter() {
                    params.push(Param {
                        class: class as u8,
                        slot,
                    });
                }
            }
            spans[pc] = (start, params.len() as u32 - start);
        }
        Self {
            spans,
            params,
            values: [[None; 256]; 3],
        }
    }
    fn params(&self, pc: usize) -> &[Param] {
        let (start, len) = self.spans[pc];
        &self.params[start as usize..(start + len) as usize]
    }
    pub fn declare(&self, b: &mut FunctionBuilder, blocks: &HashMap<usize, Block>) {
        for (&pc, &block) in blocks {
            for p in self.params(pc) {
                b.append_block_param(
                    block,
                    [types::I64, types::F64, types::F64X2][p.class as usize],
                );
            }
        }
    }
    pub fn enter(&mut self, b: &FunctionBuilder, pc: usize, block: Block) {
        self.values = [[None; 256]; 3];
        let (start, len) = self.spans[pc];
        for (p, &value) in self.params[start as usize..(start + len) as usize]
            .iter()
            .zip(b.block_params(block))
        {
            self.values[p.class as usize][p.slot as usize] = Some(value);
        }
    }
    pub fn get(&self, class: usize, slot: usize) -> Value {
        self.values[class][slot].expect("typed CFG use has no local definition or block parameter")
    }
    pub fn set(&mut self, class: usize, slot: usize, value: Value) {
        self.values[class][slot] = Some(value);
    }
    pub fn args(&self, pc: usize) -> Vec<BlockArg> {
        self.params(pc)
            .iter()
            .map(|p| self.get(p.class as usize, p.slot as usize).into())
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use crate::{
        hotpatch, image,
        interp::{Interp, Outcome},
        jit::Jit,
        persist::{self, Policies, ResourceCodecs},
        value::Value,
    };

    fn image(seed: u32) -> String {
        format!(
            "function module:m 0 0 3 1 :v\nsource m\nconst 0 func 1\nK 1 0\nRet 1\nend\nfunction carried 1 1 3 4 v:v\nsource m\nvectors 2\nIUnbox 0 1\nIK 1 0\nIK 2 1\nFK 0 {seed}\nVSplatN 0 0 9\nFK 1 1\nVSplatN 1 1 9\nICmpLt 3 1 0\nJmpIfIZero 3 3\nVOp add 9 0 0 1 1\nIAdd 1 1 2\nJmp -5\nVExtractN 0 0 9 0\nFBox 2 0\nRet 2\nend\nmodule m 0\nentry 0\n"
        )
    }

    #[test]
    fn typed_return_does_not_fall_through_to_a_later_block() {
        let mut vm = Box::new(Interp::new());
        image::load(&mut vm, "function module:m 0 0 3 1 :v\nsource m\nconst 0 func 1\nK 1 0\nRet 1\nend\nfunction branch 1 1 3 3 v:v\nsource m\nvectors 1\nFK 0 42\nVSplatN 0 0 9\nIUnbox 0 1\nJmpIfIZero 0 3\nFK 1 17\nFBox 2 1\nRet 2\nFBox 2 0\nRet 2\nend\nmodule m 0\nentry 0\n").unwrap();
        vm.install_globals();
        let function = vm.require("m");
        vm.register(function);
        vm.enable_scheduler().unwrap();
        vm.jit = Some(Box::new(Jit::new()));
        vm.jit
            .as_mut()
            .unwrap()
            .compile_frame(&vm.funcs[1], 1)
            .unwrap();
        for (input, expected) in [(0., 42.), (1., 17.)] {
            let task = vm.schedule(function, &[Value::num(input)], None).unwrap();
            vm.run_ready(1).unwrap();
            assert_eq!(vm.tasks[task.index].result, Value::num(expected));
        }
    }

    #[test]
    fn typed_budget_resume_keeps_the_old_body_after_patch_and_checkpoint() {
        let generated = include_str!("../experiments/cfg/typed-carried.image");
        let wrap = |body: &str| {
            format!(
                "function module:m 0 0 3 1 :v\nsource m\nconst 0 func 1\nK 1 0\nRet 1\nend\n{body}module m 0\nentry 0\n"
            )
        };
        let changed = generated.replacen("FK 1 1\n", "FK 1 10\n", 1);
        assert_ne!(generated, changed);
        for (before, after, old_result, new_result) in [
            (image(1), image(10), 4., 13.),
            (wrap(generated), wrap(&changed), 16., 52.),
        ] {
            let mut vm = Box::new(Interp::new());
            image::load(&mut vm, &before).unwrap();
            vm.install_globals();
            let function = vm.require("m");
            vm.register(function);
            vm.enable_scheduler().unwrap();
            vm.jit = Some(Box::new(Jit::new()));
            // Compile explicitly so a refusal cannot silently pass on the interpreter.
            vm.jit
                .as_mut()
                .unwrap()
                .compile_frame(&vm.funcs[1], 1)
                .unwrap();
            let task = vm.schedule(function, &[Value::num(3.)], None).unwrap();
            vm.instruction_budget = Some(1);
            assert!(matches!(vm.run(task.index), Outcome::Parked(0)));
            let backedge = vm.funcs[1]
                .code
                .iter()
                .position(|op| matches!(op, crate::interp::Op::Jmp(n) if *n < 0))
                .unwrap();
            assert_eq!(vm.tasks[task.index].stack[0] >> 32, backedge as u64);
            vm.instruction_budget = None;
            let report =
                hotpatch::apply(&mut vm, format!("patch m\nmap 0 1\n{after}").as_bytes(), true).unwrap();
            assert_eq!((report.changed, report.retained), (1, 1));
            let data = persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new())
                .unwrap();
            let mut restored = Box::new(
                persist::load_vm(&data, &Policies::default(), &mut ResourceCodecs::new()).unwrap(),
            );
            restored.jit = Some(Box::new(Jit::new()));
            for vm in [&mut vm, &mut restored] {
                vm.heap.stress_steps = true;
                vm.heap.oracle = true;
                vm.heap.quarantine = true;
                vm.full_cycle();
                vm.run_ready(1).unwrap();
                assert_eq!(vm.tasks[task.index].result, Value::num(old_result));
                let fresh = vm.schedule(function, &[Value::num(3.)], None).unwrap();
                vm.run_ready(1).unwrap();
                assert_eq!(vm.tasks[fresh.index].result, Value::num(new_result));
            }
        }
    }
}
