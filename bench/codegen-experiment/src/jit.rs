//! A narrow typed representation lowered to Cranelift.
//!
//! The kernels are written against a small typed emitter whose helpers mirror
//! the bytecode families in the runtime plan: arithmetic by width, checked and
//! proved span access, vector register values, direct and external calls. The
//! emitter asserts operand types at emission time, which is the only verifier
//! this experiment has. Nothing here is a product.

use cranelift_codegen::ir::condcodes::IntCC;
use cranelift_codegen::ir::{
    types, AbiParam, InstBuilder, MemFlagsData, Signature, StackSlotData, StackSlotKind, TrapCode,
    Type, Value,
};
use cranelift_codegen::settings::{self, Configurable};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Variable};
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{FuncId, Linkage, Module};
use std::time::Instant;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Ty {
    U32,
    U64,
    F64,
    F64x2,
    Ptr,
}

impl Ty {
    fn cl(self) -> Type {
        match self {
            Ty::U32 => types::I32,
            Ty::U64 | Ty::Ptr => types::I64,
            Ty::F64 => types::F64,
            Ty::F64x2 => types::F64X2,
        }
    }
}

#[derive(Clone, Copy)]
pub struct TV {
    pub v: Value,
    pub t: Ty,
}

/// A span is a pointer and an element count, both already loaded into registers.
#[derive(Clone, Copy)]
pub struct Span {
    pub ptr: TV,
    pub count: TV,
    pub elem_size: i64,
}

pub struct E<'a> {
    pub b: FunctionBuilder<'a>,
}

fn flags() -> MemFlagsData {
    MemFlagsData::new().with_notrap()
}

impl<'a> E<'a> {
    fn same(a: TV, b: TV, what: &str) {
        assert_eq!(a.t, b.t, "{what}: operand types differ");
    }
    pub fn param(&mut self, i: usize, t: Ty) -> TV {
        let entry = self.b.current_block().unwrap();
        TV { v: self.b.block_params(entry)[i], t }
    }
    pub fn k_u64(&mut self, k: i64) -> TV {
        TV { v: self.b.ins().iconst(types::I64, k), t: Ty::U64 }
    }
    pub fn k_u32(&mut self, k: u32) -> TV {
        TV { v: self.b.ins().iconst(types::I32, k as i64), t: Ty::U32 }
    }
    pub fn k_f64(&mut self, k: f64) -> TV {
        TV { v: self.b.ins().f64const(k), t: Ty::F64 }
    }
    pub fn add(&mut self, a: TV, b: TV) -> TV {
        Self::same(a, b, "add");
        let v = match a.t {
            Ty::U32 | Ty::U64 | Ty::Ptr => self.b.ins().iadd(a.v, b.v),
            Ty::F64 | Ty::F64x2 => self.b.ins().fadd(a.v, b.v),
        };
        TV { v, t: a.t }
    }
    pub fn sub(&mut self, a: TV, b: TV) -> TV {
        Self::same(a, b, "sub");
        let v = match a.t {
            Ty::U32 | Ty::U64 | Ty::Ptr => self.b.ins().isub(a.v, b.v),
            Ty::F64 | Ty::F64x2 => self.b.ins().fsub(a.v, b.v),
        };
        TV { v, t: a.t }
    }
    pub fn mul(&mut self, a: TV, b: TV) -> TV {
        Self::same(a, b, "mul");
        let v = match a.t {
            Ty::U32 | Ty::U64 => self.b.ins().imul(a.v, b.v),
            Ty::F64 | Ty::F64x2 => self.b.ins().fmul(a.v, b.v),
            Ty::Ptr => panic!("mul on pointer"),
        };
        TV { v, t: a.t }
    }
    /// a * b + c, fused where the target fuses.
    pub fn fma(&mut self, a: TV, b: TV, c: TV) -> TV {
        Self::same(a, b, "fma");
        Self::same(a, c, "fma");
        assert!(matches!(a.t, Ty::F64 | Ty::F64x2));
        TV { v: self.b.ins().fma(a.v, b.v, c.v), t: a.t }
    }
    pub fn xor(&mut self, a: TV, b: TV) -> TV {
        Self::same(a, b, "xor");
        TV { v: self.b.ins().bxor(a.v, b.v), t: a.t }
    }
    pub fn and(&mut self, a: TV, b: TV) -> TV {
        Self::same(a, b, "and");
        TV { v: self.b.ins().band(a.v, b.v), t: a.t }
    }
    pub fn not(&mut self, a: TV) -> TV {
        TV { v: self.b.ins().bnot(a.v), t: a.t }
    }
    pub fn rotr(&mut self, a: TV, k: u32) -> TV {
        assert_eq!(a.t, Ty::U32);
        TV { v: self.b.ins().rotr_imm(a.v, k as i64), t: a.t }
    }
    pub fn shr(&mut self, a: TV, k: u32) -> TV {
        TV { v: self.b.ins().ushr_imm(a.v, k as i64), t: a.t }
    }
    pub fn bswap32(&mut self, a: TV) -> TV {
        assert_eq!(a.t, Ty::U32);
        TV { v: self.b.ins().bswap(a.v), t: a.t }
    }
    pub fn splat(&mut self, a: TV) -> TV {
        assert_eq!(a.t, Ty::F64);
        TV { v: self.b.ins().splat(types::F64X2, a.v), t: Ty::F64x2 }
    }
    pub fn lane(&mut self, a: TV, i: u8) -> TV {
        assert_eq!(a.t, Ty::F64x2);
        TV { v: self.b.ins().extractlane(a.v, i), t: Ty::F64 }
    }
    pub fn zero_vec(&mut self) -> TV {
        let z = self.k_f64(0.0);
        self.splat(z)
    }
    pub fn ule(&mut self, a: TV, b: TV) -> Value {
        Self::same(a, b, "ule");
        self.b.ins().icmp(IntCC::UnsignedLessThanOrEqual, a.v, b.v)
    }
    pub fn ult(&mut self, a: TV, b: TV) -> Value {
        Self::same(a, b, "ult");
        self.b.ins().icmp(IntCC::UnsignedLessThan, a.v, b.v)
    }
    pub fn ne(&mut self, a: TV, b: TV) -> Value {
        Self::same(a, b, "ne");
        self.b.ins().icmp(IntCC::NotEqual, a.v, b.v)
    }
    /// Byte address of element `index` of `span`. No check: the caller cites
    /// the loop fact that proves it, as the bytecode's elided BOUNDS would.
    pub fn addr_proved(&mut self, span: Span, index: TV) -> TV {
        assert_eq!(index.t, Ty::U64);
        let off = self.b.ins().imul_imm(index.v, span.elem_size);
        TV { v: self.b.ins().iadd(span.ptr.v, off), t: Ty::Ptr }
    }
    /// Byte address of element `index`, with the BOUNDS the verifier keeps
    /// when nothing proves it: index < count or trap.
    pub fn addr_checked(&mut self, span: Span, index: TV) -> TV {
        Self::same(index, span.count, "bounds");
        let bad = self.b.ins().icmp(IntCC::UnsignedGreaterThanOrEqual, index.v, span.count.v);
        self.b.ins().trapnz(bad, TrapCode::user(1).unwrap());
        self.addr_proved(span, index)
    }
    pub fn load(&mut self, t: Ty, addr: TV, offset: i32) -> TV {
        assert_eq!(addr.t, Ty::Ptr);
        TV { v: self.b.ins().load(t.cl(), flags(), addr.v, offset), t }
    }
    pub fn store(&mut self, val: TV, addr: TV, offset: i32) {
        assert_eq!(addr.t, Ty::Ptr);
        self.b.ins().store(flags(), val.v, addr.v, offset);
    }
    pub fn var(&mut self, init: TV) -> (Variable, Ty) {
        let v = self.b.declare_var(init.t.cl());
        self.b.def_var(v, init.v);
        (v, init.t)
    }
    pub fn get(&mut self, v: (Variable, Ty)) -> TV {
        TV { v: self.b.use_var(v.0), t: v.1 }
    }
    pub fn set(&mut self, v: (Variable, Ty), val: TV) {
        assert_eq!(v.1, val.t, "set: type differs");
        self.b.def_var(v.0, val.v);
    }
}

pub struct Jit {
    pub module: JITModule,
    ctx: cranelift_codegen::Context,
    fbc: FunctionBuilderContext,
    pub compile_micros: Vec<(String, u128)>,
}

pub type Builder<'a> = dyn FnOnce(&mut E<'_>, &mut JITModule) + 'a;

impl Jit {
    pub fn new(symbols: &[(&str, *const u8)], opt: &str) -> Jit {
        let mut fb = settings::builder();
        fb.set("opt_level", opt).unwrap();
        fb.set("use_colocated_libcalls", "false").unwrap();
        fb.set("is_pic", "false").unwrap();
        let isa = cranelift_native::builder().unwrap().finish(settings::Flags::new(fb)).unwrap();
        let mut jb = JITBuilder::with_isa(isa, cranelift_module::default_libcall_names());
        for (name, ptr) in symbols {
            jb.symbol(*name, *ptr);
        }
        let module = JITModule::new(jb);
        let ctx = module.make_context();
        Jit { module, ctx, fbc: FunctionBuilderContext::new(), compile_micros: Vec::new() }
    }

    pub fn sig(&self, params: &[Ty], ret: Option<Ty>) -> Signature {
        let mut s = self.module.make_signature();
        for p in params {
            s.params.push(AbiParam::new(p.cl()));
        }
        if let Some(r) = ret {
            s.returns.push(AbiParam::new(r.cl()));
        }
        s
    }

    pub fn import(&mut self, name: &str, params: &[Ty], ret: Option<Ty>) -> FuncId {
        let s = self.sig(params, ret);
        self.module.declare_function(name, Linkage::Import, &s).unwrap()
    }

    pub fn declare(&mut self, name: &str, params: &[Ty], ret: Option<Ty>) -> FuncId {
        let s = self.sig(params, ret);
        self.module.declare_function(name, Linkage::Local, &s).unwrap()
    }

    /// Define `id` by running `body` on a fresh builder whose entry block holds
    /// the parameters. Records the wall time of building, compiling and defining.
    pub fn define(&mut self, name: &str, id: FuncId, params: &[Ty], ret: Option<Ty>, body: Box<Builder<'_>>) {
        let start = Instant::now();
        self.ctx.func.signature = self.sig(params, ret);
        self.ctx.want_disasm = std::env::var("DISASM").is_ok();
        let frontend = self.module.target_config();
        {
            let mut b = FunctionBuilder::new(&mut self.ctx.func, &mut self.fbc);
            let entry = b.create_block();
            b.append_block_params_for_function_params(entry);
            b.switch_to_block(entry);
            b.seal_block(entry);
            let mut e = E { b };
            body(&mut e, &mut self.module);
            e.b.seal_all_blocks();
            e.b.finalize(frontend);
        }
        self.module.define_function(id, &mut self.ctx).unwrap_or_else(|err| panic!("{name}: {err}"));
        if let (Ok(want), Some(code)) = (std::env::var("DISASM"), self.ctx.compiled_code()) {
            if want == "1" || want == name {
                eprintln!("==== {name} ({} bytes)\n{}", code.code_buffer().len(), code.vcode.as_deref().unwrap_or("(no vcode)"));
            }
        }
        self.module.clear_context(&mut self.ctx);
        self.compile_micros.push((name.to_string(), start.elapsed().as_micros()));
    }

    pub fn finish(&mut self) {
        let start = Instant::now();
        self.module.finalize_definitions().unwrap();
        self.compile_micros.push(("finalize".to_string(), start.elapsed().as_micros()));
    }

    pub fn ptr(&self, id: FuncId) -> *const u8 {
        self.module.get_finalized_function(id)
    }
}

/// A 64-word scratch slot for SHA-256's message schedule.
pub fn schedule_slot(e: &mut E<'_>) -> TV {
    let slot = e.b.create_sized_stack_slot(StackSlotData::new(StackSlotKind::ExplicitSlot, 256, 2));
    TV { v: e.b.ins().stack_addr(types::I64, slot, 0), t: Ty::Ptr }
}
