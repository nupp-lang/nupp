//! The LLVM backend: LIR to LLVM IR, optimized and compiled by LLVM 23 linked
//! into the process, and loaded by ORC's LLJIT through JITLink -- no clang, no
//! system linker.
//!
//! LIR is built at four f64 lanes on every target, so a `fixed4` species is
//! one `<4 x double>` and LLVM legalizes it (two q registers on NEON, one ymm
//! on AVX2). The numeric contract is the C backend's: no fast-math flags, no
//! contraction (the target machine is set to `FPOpFusion::Strict` and nothing
//! emits `fmuladd`), ordered compares; only `algebraic_sum` reassociates.

use crate::lir::{self, Inst, K, Node, T, V};
use crate::sem::{Cmp, CmpKind, Cond, Ret, Scalar, Signature, Vector};
use llvm_sys::core::*;
use llvm_sys::error::*;
use llvm_sys::orc2::lljit::*;
use llvm_sys::orc2::*;
use llvm_sys::prelude::*;
use llvm_sys::target_machine::*;
use llvm_sys::support::LLVMParseCommandLineOptions;
use llvm_sys::transforms::pass_builder::*;
use llvm_sys::{LLVMIntPredicate as IP, LLVMLinkage, LLVMRealPredicate as RP, LLVMUnnamedAddr};
use std::collections::HashMap;
use std::ffi::{CStr, CString, c_char, c_void};

unsafe extern "C" {
    fn nupp_llvm_strict_fp(tm: LLVMTargetMachineRef) -> i32;
    #[cfg(feature = "cxx-pipeline")]
    fn nupp_llvm_optimize(module: LLVMModuleRef, tm: LLVMTargetMachineRef, level: i32);
}

/// Lanes of one LIR vector value: a whole `fixed4` f64 species.
pub const LANES: usize = 4;

/// Masks as `<4 x i64>` lanes of all ones or zeros -- the form NEON and AVX2
/// compares produce -- instead of `<4 x i1>`. `NUPP_SPIKE_LLVM_MASKS=wide`.
/// Element addresses are in bounds and never below their base (Nupp indexes
/// spans from zero), so `nuw` is a fact, not a guess: it lets Wasm fold
/// offsets into the access. `NUPP_SPIKE_LLVM_NUW=0` leaves it off.
fn gep_flags() -> llvm_sys::LLVMGEPNoWrapFlags {
    let nuw = std::env::var("NUPP_SPIKE_LLVM_NUW").as_deref() != Ok("0");
    llvm_sys::LLVMGEPFlagInBounds | if nuw { llvm_sys::LLVMGEPFlagNUW } else { 0 }
}

pub fn wide_masks() -> bool {
    std::env::var("NUPP_SPIKE_LLVM_MASKS").as_deref() == Ok("wide")
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Tier {
    Arm64Neon,
    X86Avx2,
    X86Avx512,
    Wasm32Simd,
}

impl Tier {
    pub fn triple(self) -> &'static str {
        match self {
            Tier::Arm64Neon => "arm64-apple-macosx11.0.0",
            Tier::X86Avx2 | Tier::X86Avx512 => "x86_64-apple-macosx10.15.0",
            Tier::Wasm32Simd => "wasm32-unknown-unknown",
        }
    }
    fn cpu(self) -> &'static str {
        match self {
            // clang's default for arm64 macOS, which built the C oracle.
            Tier::Arm64Neon => "apple-m1",
            Tier::X86Avx2 | Tier::X86Avx512 => "x86-64",
            Tier::Wasm32Simd => "generic",
        }
    }
    fn features(self) -> &'static str {
        match self {
            Tier::Arm64Neon => "+neon",
            Tier::X86Avx2 => "+avx2,+fma",
            Tier::X86Avx512 => "+avx2,+fma,+avx512f,+avx512vl",
            Tier::Wasm32Simd => "+simd128",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Level {
    O2,
    O3,
}

impl Level {
    fn pipeline(self) -> &'static str {
        match self {
            Level::O2 => "default<O2>",
            Level::O3 => "default<O3>",
        }
    }
}

fn cs(s: &str) -> CString {
    CString::new(s).unwrap()
}

unsafe fn take_message(m: *mut c_char) -> String {
    unsafe {
        let s = CStr::from_ptr(m).to_string_lossy().into_owned();
        LLVMDisposeMessage(m);
        s
    }
}

unsafe fn check(e: LLVMErrorRef, what: &str) {
    if !e.is_null() {
        let m = unsafe { take_message(LLVMGetErrorMessage(e)) };
        panic!("{what}: {m}");
    }
}

/// Registers the targets this build carries. Once per process.
pub fn init_targets() {
    use std::sync::Once;
    static ONCE: Once = Once::new();
    ONCE.call_once(|| unsafe {
        llvm_sys::target::LLVMInitializeAArch64TargetInfo();
        llvm_sys::target::LLVMInitializeAArch64Target();
        llvm_sys::target::LLVMInitializeAArch64TargetMC();
        llvm_sys::target::LLVMInitializeAArch64AsmPrinter();
        #[cfg(any(not(feature = "probe"), feature = "x86"))]
        {
            llvm_sys::target::LLVMInitializeX86TargetInfo();
            llvm_sys::target::LLVMInitializeX86Target();
            llvm_sys::target::LLVMInitializeX86TargetMC();
            llvm_sys::target::LLVMInitializeX86AsmPrinter();
        }
        #[cfg(any(not(feature = "probe"), feature = "wasm"))]
        {
            llvm_sys::target::LLVMInitializeWebAssemblyTargetInfo();
            llvm_sys::target::LLVMInitializeWebAssemblyTarget();
            llvm_sys::target::LLVMInitializeWebAssemblyTargetMC();
            llvm_sys::target::LLVMInitializeWebAssemblyAsmPrinter();
        }
        // Investigation only: LLVM's own options (`-time-passes`, ...).
        if let Ok(extra) = std::env::var("NUPP_SPIKE_LLVM_ARGS") {
            let args: Vec<CString> = std::iter::once("nupp").chain(extra.split_whitespace()).map(cs).collect();
            let ptrs: Vec<*const c_char> = args.iter().map(|a| a.as_ptr()).collect();
            LLVMParseCommandLineOptions(ptrs.len() as i32, ptrs.as_ptr(), std::ptr::null());
        }
    });
}

/// A target machine for `tier` at `level`, with FP fusion forced off.
pub fn target_machine(tier: Tier, level: Level) -> LLVMTargetMachineRef {
    init_targets();
    unsafe {
        let triple = cs(tier.triple());
        let mut target = std::ptr::null_mut();
        let mut err = std::ptr::null_mut();
        if LLVMGetTargetFromTriple(triple.as_ptr(), &mut target, &mut err) != 0 {
            panic!("target {}: {}", tier.triple(), take_message(err));
        }
        let o = LLVMCreateTargetMachineOptions();
        let cpu = std::env::var("NUPP_SPIKE_LLVM_CPU").ok().filter(|_| tier == Tier::Arm64Neon).unwrap_or(tier.cpu().to_string());
        let (cpu, features) = (cs(&cpu), cs(tier.features()));
        LLVMTargetMachineOptionsSetCPU(o, cpu.as_ptr());
        LLVMTargetMachineOptionsSetFeatures(o, features.as_ptr());
        LLVMTargetMachineOptionsSetCodeGenOptLevel(
            o,
            if level == Level::O3 { LLVMCodeGenOptLevel::LLVMCodeGenLevelAggressive } else { LLVMCodeGenOptLevel::LLVMCodeGenLevelDefault },
        );
        LLVMTargetMachineOptionsSetRelocMode(o, LLVMRelocMode::LLVMRelocPIC);
        let tm = LLVMCreateTargetMachineWithOptions(target, triple.as_ptr(), o);
        LLVMDisposeTargetMachineOptions(o);
        assert!(!tm.is_null());
        assert_eq!(nupp_llvm_strict_fp(tm), 1);
        tm
    }
}

struct Tys {
    void: LLVMTypeRef,
    i1: LLVMTypeRef,
    i8: LLVMTypeRef,
    i32: LLVMTypeRef,
    i64: LLVMTypeRef,
    f64: LLVMTypeRef,
    ptr: LLVMTypeRef,
    vec: LLVMTypeRef,
    mask: LLVMTypeRef,
    ivec: LLVMTypeRef,
    /// `<4 x i1>`, what masked accesses and reductions take.
    bits: LLVMTypeRef,
    wide: bool,
}

/// One function's module, in a context of its own.
pub struct Module {
    pub ctx: LLVMContextRef,
    pub m: LLVMModuleRef,
    pub name: String,
}

impl Drop for Module {
    fn drop(&mut self) {
        unsafe {
            if !self.m.is_null() {
                LLVMDisposeModule(self.m);
                LLVMContextDispose(self.ctx);
            }
        }
    }
}

impl Module {
    pub fn ir(&self) -> String {
        unsafe { take_message(LLVMPrintModuleToString(self.m)) }
    }

    /// The optimization pipeline clang runs at the same level, vectorizers on.
    pub fn optimize(&self, tm: LLVMTargetMachineRef, level: Level) {
        #[cfg(feature = "cxx-pipeline")]
        {
            unsafe { nupp_llvm_optimize(self.m, tm, if level == Level::O3 { 3 } else { 2 }) };
            return;
        }
        #[allow(unreachable_code)]
        unsafe {
            let o = LLVMCreatePassBuilderOptions();
            LLVMPassBuilderOptionsSetLoopVectorization(o, 1);
            LLVMPassBuilderOptionsSetSLPVectorization(o, 1);
            LLVMPassBuilderOptionsSetLoopInterleaving(o, 1);
            LLVMPassBuilderOptionsSetLoopUnrolling(o, 1);
            // Investigation: NUPP_SPIKE_LLVM_PIPELINE replaces the default pipeline.
            let p = cs(&std::env::var("NUPP_SPIKE_LLVM_PIPELINE").unwrap_or(level.pipeline().to_string()));
            check(LLVMRunPasses(self.m, p.as_ptr(), tm, o), "passes");
            LLVMDisposePassBuilderOptions(o);
        }
    }

    fn emit(&self, tm: LLVMTargetMachineRef, kind: LLVMCodeGenFileType) -> Vec<u8> {
        unsafe {
            // Code generation rewrites IR (CodeGenPrepare), so emit a copy.
            let copy = LLVMCloneModule(self.m);
            let mut err = std::ptr::null_mut();
            let mut buf = std::ptr::null_mut();
            if LLVMTargetMachineEmitToMemoryBuffer(tm, copy, kind, &mut err, &mut buf) != 0 {
                panic!("codegen: {}", take_message(err));
            }
            LLVMDisposeModule(copy);
            let bytes = std::slice::from_raw_parts(LLVMGetBufferStart(buf) as *const u8, LLVMGetBufferSize(buf)).to_vec();
            LLVMDisposeMemoryBuffer(buf);
            bytes
        }
    }

    /// A relocatable object, in memory.
    pub fn object(&self, tm: LLVMTargetMachineRef) -> Vec<u8> {
        self.emit(tm, LLVMCodeGenFileType::LLVMObjectFile)
    }

    pub fn assembly(&self, tm: LLVMTargetMachineRef) -> String {
        String::from_utf8(self.emit(tm, LLVMCodeGenFileType::LLVMAssemblyFile)).unwrap()
    }

    /// Hands the module to ORC, which owns its context from here on.
    fn into_thread_safe(mut self) -> LLVMOrcThreadSafeModuleRef {
        unsafe {
            let tsc = LLVMOrcCreateNewThreadSafeContextFromLLVMContext(self.ctx);
            let tsm = LLVMOrcCreateNewThreadSafeModule(self.m, tsc);
            LLVMOrcDisposeThreadSafeContext(tsc);
            self.m = std::ptr::null_mut();
            tsm
        }
    }
}

/// What a function returns and how it may unwind.
pub enum Shape<'s> {
    Kernel { sig: &'s Signature, noalias: Vec<u32> },
    /// A `lua_CFunction`: Lua errors unwind through it.
    LuaBuilder,
}

struct E<'f> {
    f: &'f lir::Func,
    ctx: LLVMContextRef,
    m: LLVMModuleRef,
    b: LLVMBuilderRef,
    func: LLVMValueRef,
    t: Tys,
    vals: HashMap<V, LLVMValueRef>,
    frame: Option<LLVMValueRef>,
    data: HashMap<Vec<u8>, LLVMValueRef>,
    ret: LLVMTypeRef,
    tier: Tier,
}

impl<'f> E<'f> {
    fn ty(&self, t: T) -> LLVMTypeRef {
        match t {
            T::I32 => self.t.i32,
            T::I64 => self.t.i64,
            T::Ptr => self.t.ptr,
            T::F64 => self.t.f64,
            T::Vec => self.t.vec,
            T::Mask => self.t.mask,
        }
    }
    fn vty(&self, v: V) -> LLVMTypeRef {
        self.ty(self.f.types[v as usize])
    }
    fn v(&self, v: V) -> LLVMValueRef {
        *self.vals.get(&v).unwrap_or_else(|| panic!("v{v} used before definition"))
    }
    fn block(&self, name: &str) -> LLVMBasicBlockRef {
        let n = cs(name);
        unsafe { LLVMAppendBasicBlockInContext(self.ctx, self.func, n.as_ptr()) }
    }
    fn at(&self, bb: LLVMBasicBlockRef) {
        unsafe { LLVMPositionBuilderAtEnd(self.b, bb) }
    }
    fn cur(&self) -> LLVMBasicBlockRef {
        unsafe { LLVMGetInsertBlock(self.b) }
    }
    fn i64c(&self, x: u64) -> LLVMValueRef {
        unsafe { LLVMConstInt(self.t.i64, x, 0) }
    }
    /// An overloaded intrinsic's declaration.
    fn intrinsic(&self, name: &str, overloads: &[LLVMTypeRef]) -> (LLVMValueRef, LLVMTypeRef) {
        unsafe {
            let id = LLVMLookupIntrinsicID(name.as_ptr() as *const c_char, name.len());
            assert!(id != 0, "intrinsic {name}");
            let mut o = overloads.to_vec();
            let f = LLVMGetIntrinsicDeclaration(self.m, id, o.as_mut_ptr(), o.len());
            (f, LLVMGlobalGetValueType(f))
        }
    }
    fn call(&self, f: (LLVMValueRef, LLVMTypeRef), args: &[LLVMValueRef]) -> LLVMValueRef {
        let mut a = args.to_vec();
        let empty = cs("");
        unsafe { LLVMBuildCall2(self.b, f.1, f.0, a.as_mut_ptr(), a.len() as u32, empty.as_ptr()) }
    }
    fn gep_bytes(&self, p: LLVMValueRef, bytes: u64) -> LLVMValueRef {
        if bytes == 0 {
            return p;
        }
        let mut idx = [self.i64c(bytes)];
        let n = cs("");
        unsafe { LLVMBuildGEPWithNoWrapFlags(self.b, self.t.i8, p, idx.as_mut_ptr(), 1, n.as_ptr(), gep_flags()) }
    }
    fn gep_elem(&self, p: LLVMValueRef, i: LLVMValueRef) -> LLVMValueRef {
        let n = cs("");
        unsafe {
            let i = if LLVMTypeOf(i) == self.t.i64 { i } else { LLVMBuildZExt(self.b, i, self.t.i64, n.as_ptr()) };
            let mut idx = [i];
            LLVMBuildGEPWithNoWrapFlags(self.b, self.t.f64, p, idx.as_mut_ptr(), 1, n.as_ptr(), gep_flags())
        }
    }
    fn load(&self, t: LLVMTypeRef, p: LLVMValueRef) -> LLVMValueRef {
        let n = cs("");
        unsafe {
            let l = LLVMBuildLoad2(self.b, t, p, n.as_ptr());
            LLVMSetAlignment(l, 8);
            l
        }
    }
    fn store(&self, v: LLVMValueRef, p: LLVMValueRef) {
        unsafe {
            let s = LLVMBuildStore(self.b, v, p);
            LLVMSetAlignment(s, 8);
        }
    }
    /// `align 8` on a masked access's pointer argument (LLVM 22+ form).
    fn align_arg(&self, call: LLVMValueRef, arg: u32) {
        unsafe {
            let kind = LLVMGetEnumAttributeKindForName(c"align".as_ptr(), 5);
            let a = LLVMCreateEnumAttribute(self.ctx, kind, 8);
            LLVMAddCallSiteAttribute(call, arg + 1, a);
        }
    }
    /// A mask as `<4 x i1>`.
    fn bits(&self, m: LLVMValueRef) -> LLVMValueRef {
        if !self.t.wide {
            return m;
        }
        let n = cs("");
        unsafe { LLVMBuildICmp(self.b, IP::LLVMIntNE, m, LLVMConstNull(self.t.mask), n.as_ptr()) }
    }
    /// A lane-width mask entering a phi, behind an empty asm so InstCombine
    /// cannot narrow the phi back to `<4 x i1>` (the C backend's
    /// `ks_exp_keep_mask`). NEON needs two q-register halves.
    fn keep(&self, m: LLVMValueRef) -> LLVMValueRef {
        if !self.t.wide || !matches!(self.tier, Tier::Arm64Neon | Tier::X86Avx2) {
            return m;
        }
        let n = cs("");
        unsafe {
            let barrier = |v: LLVMValueRef, constraint: &str| {
                let t = LLVMTypeOf(v);
                let mut p = [t];
                let ft = LLVMFunctionType(t, p.as_mut_ptr(), 1, 0);
                let asm = LLVMGetInlineAsm(ft, c"".as_ptr() as *mut c_char, 0, constraint.as_ptr() as *mut c_char, constraint.len(), 0, 0, llvm_sys::LLVMInlineAsmDialect::LLVMInlineAsmDialectATT, 0);
                let mut a = [v];
                LLVMBuildCall2(self.b, ft, asm, a.as_mut_ptr(), 1, n.as_ptr())
            };
            if self.tier == Tier::X86Avx2 {
                return barrier(m, "=x,0");
            }
            let half = |k: u64| {
                let mut idx = [LLVMConstInt(self.t.i32, 2 * k, 0), LLVMConstInt(self.t.i32, 2 * k + 1, 0)];
                let mask = LLVMConstVector(idx.as_mut_ptr(), 2);
                barrier(LLVMBuildShuffleVector(self.b, m, LLVMGetPoison(self.t.mask), mask, n.as_ptr()), "=w,0")
            };
            let (lo, hi) = (half(0), half(1));
            let mut idx: Vec<LLVMValueRef> = (0..4).map(|k| LLVMConstInt(self.t.i32, k, 0)).collect();
            LLVMBuildShuffleVector(self.b, lo, hi, LLVMConstVector(idx.as_mut_ptr(), 4), n.as_ptr())
        }
    }
    fn kept(&self, vs: &[V]) -> Vec<LLVMValueRef> {
        vs.iter().map(|v| if self.f.types[*v as usize] == T::Mask { self.keep(self.v(*v)) } else { self.v(*v) }).collect()
    }
    /// A `<4 x i1>` as the function's mask type.
    fn mask(&self, bits: LLVMValueRef) -> LLVMValueRef {
        if !self.t.wide {
            return bits;
        }
        let n = cs("");
        unsafe { LLVMBuildSExt(self.b, bits, self.t.mask, n.as_ptr()) }
    }
    fn splat(&self, x: LLVMValueRef, vt: LLVMTypeRef) -> LLVMValueRef {
        let n = cs("");
        unsafe {
            let one = LLVMBuildInsertElement(self.b, LLVMGetPoison(vt), x, LLVMConstInt(self.t.i32, 0, 0), n.as_ptr());
            LLVMBuildShuffleVector(self.b, one, LLVMGetPoison(vt), LLVMConstNull(self.t.ivec), n.as_ptr())
        }
    }
    fn declare(&mut self, name: &str, params: &[LLVMTypeRef], ret: LLVMTypeRef) -> (LLVMValueRef, LLVMTypeRef) {
        let n = cs(name);
        unsafe {
            let mut p = params.to_vec();
            let ft = LLVMFunctionType(ret, p.as_mut_ptr(), p.len() as u32, 0);
            let mut f = LLVMGetNamedFunction(self.m, n.as_ptr());
            if f.is_null() {
                f = LLVMAddFunction(self.m, n.as_ptr(), ft);
            }
            (f, ft)
        }
    }
    fn data(&mut self, bytes: &[u8]) -> LLVMValueRef {
        if let Some(g) = self.data.get(bytes) {
            return *g;
        }
        unsafe {
            // NUL-terminated: sites reach `luaL_error`'s `%s`.
            let init = LLVMConstStringInContext2(self.ctx, bytes.as_ptr() as *const c_char, bytes.len(), 0);
            let n = cs("str");
            let g = LLVMAddGlobal(self.m, LLVMTypeOf(init), n.as_ptr());
            LLVMSetInitializer(g, init);
            LLVMSetGlobalConstant(g, 1);
            LLVMSetLinkage(g, LLVMLinkage::LLVMPrivateLinkage);
            LLVMSetUnnamedAddress(g, LLVMUnnamedAddr::LLVMGlobalUnnamedAddr);
            self.data.insert(bytes.to_vec(), g);
            g
        }
    }

    fn inst(&mut self, i: &Inst) {
        let n = cs("");
        let nm = n.as_ptr();
        let a: Vec<LLVMValueRef> = i.a.iter().map(|v| self.v(*v)).collect();
        let d = i.d.first().copied();
        let b = self.b;
        let r = unsafe {
            match &i.k {
                K::Param { index } => LLVMGetParam(self.func, *index),
                K::ConstInt { value } => LLVMConstInt(self.vty(d.unwrap()), *value, 0),
                K::ConstF64 { bits } => LLVMConstReal(self.t.f64, f64::from_bits(*bits)),
                K::Scalar(op) => match op {
                    Scalar::FAdd => LLVMBuildFAdd(b, a[0], a[1], nm),
                    Scalar::FSub => LLVMBuildFSub(b, a[0], a[1], nm),
                    Scalar::FMul => LLVMBuildFMul(b, a[0], a[1], nm),
                    Scalar::U32Add | Scalar::U64Add => LLVMBuildAdd(b, a[0], a[1], nm),
                    Scalar::U32ToF64 | Scalar::U64ToF64 => LLVMBuildUIToFP(b, a[0], self.t.f64, nm),
                    // Saturating, as the direct and Wasm backends convert.
                    Scalar::F64ToU32 => {
                        let f = self.intrinsic("llvm.fptoui.sat", &[self.t.i32, self.t.f64]);
                        self.call(f, &[a[0]])
                    }
                    Scalar::U32ToU64 => LLVMBuildZExt(b, a[0], self.t.i64, nm),
                },
                K::AddImm { imm } => LLVMBuildAdd(b, a[0], LLVMConstInt(self.vty(d.unwrap()), *imm, 0), nm),
                K::Elem => self.gep_elem(a[0], a[1]),
                K::PtrAdd { bytes } => self.gep_bytes(a[0], *bytes),
                K::IndexLoad => {
                    let p = self.gep_elem(a[0], a[1]);
                    self.load(self.t.f64, p)
                }
                K::IndexStore => {
                    let p = self.gep_elem(a[1], a[2]);
                    self.store(a[0], p);
                    return;
                }
                K::Load { off } => {
                    for (k, dv) in i.d.iter().enumerate() {
                        let p = self.gep_bytes(a[0], (*off as u64) + (k * LANES * 8) as u64);
                        let l = self.load(self.t.vec, p);
                        self.vals.insert(*dv, l);
                    }
                    return;
                }
                K::Store { off } => {
                    let (vals, addr) = (&a[..a.len() - 1], a[a.len() - 1]);
                    for (k, v) in vals.iter().enumerate() {
                        let p = self.gep_bytes(addr, (*off as u64) + (k * LANES * 8) as u64);
                        self.store(*v, p);
                    }
                    return;
                }
                K::MaskedLoad { .. } => {
                    // The prefix count, when known, is LLVM's to rediscover.
                    let f = self.intrinsic("llvm.masked.load", &[self.t.vec, self.t.ptr]);
                    for (k, dv) in i.d.iter().enumerate() {
                        let p = self.gep_bytes(a[0], (k * LANES * 8) as u64);
                        let m = self.bits(a[1 + k]);
                        let c = self.call(f, &[p, m, LLVMConstNull(self.t.vec)]);
                        self.align_arg(c, 0);
                        self.vals.insert(*dv, c);
                    }
                    return;
                }
                K::MaskedStore { prefix } => {
                    let g = (a.len() - 1 - *prefix as usize) / 2;
                    let (vals, addr, masks) = (&a[..g], a[g], &a[g + 1..2 * g + 1]);
                    let f = self.intrinsic("llvm.masked.store", &[self.t.vec, self.t.ptr]);
                    for k in 0..g {
                        let p = self.gep_bytes(addr, (k * LANES * 8) as u64);
                        let m = self.bits(masks[k]);
                        let c = self.call(f, &[vals[k], p, m]);
                        self.align_arg(c, 1);
                    }
                    return;
                }
                K::Vector(op) => match op {
                    Vector::Splat => self.splat(a[0], self.t.vec),
                    Vector::FAdd => LLVMBuildFAdd(b, a[0], a[1], nm),
                    Vector::FMul => LLVMBuildFMul(b, a[0], a[1], nm),
                    Vector::MaskAnd => LLVMBuildAnd(b, a[0], a[1], nm),
                    Vector::CmpGt => self.mask(LLVMBuildFCmp(b, RP::LLVMRealOGT, a[0], a[1], nm)),
                    Vector::Select if self.t.wide => {
                        // A bitwise select over lane masks: exact, and what `bsl` does.
                        let (x, y) = (LLVMBuildBitCast(b, a[1], self.t.mask, nm), LLVMBuildBitCast(b, a[2], self.t.mask, nm));
                        let keep = LLVMBuildAnd(b, a[0], x, nm);
                        let other = LLVMBuildAnd(b, LLVMBuildNot(b, a[0], nm), y, nm);
                        LLVMBuildBitCast(b, LLVMBuildOr(b, keep, other, nm), self.t.vec, nm)
                    }
                    Vector::Select => LLVMBuildSelect(b, a[0], a[1], a[2], nm),
                },
                K::TailMask { first, lanes } => {
                    assert_eq!(*lanes, LANES);
                    // Lane-width indices when masks are lane-width: one compare.
                    let (lane, x) = if self.t.wide { (self.t.i64, LLVMBuildZExt(b, a[0], self.t.i64, nm)) } else { (self.t.i32, a[0]) };
                    let n = self.splat(x, LLVMVectorType(lane, LANES as u32));
                    let mut idx: Vec<LLVMValueRef> = (0..LANES).map(|k| LLVMConstInt(lane, (first + k) as u64, 0)).collect();
                    let idx = LLVMConstVector(idx.as_mut_ptr(), LANES as u32);
                    self.mask(LLVMBuildICmp(b, IP::LLVMIntULT, idx, n, nm))
                }
                K::Sum => {
                    // The one reassociating operation: `algebraic_sum`.
                    let f = self.intrinsic("llvm.vector.reduce.fadd", &[self.t.vec]);
                    let mut parts: Vec<LLVMValueRef> = a
                        .iter()
                        .map(|v| {
                            let c = self.call(f, &[LLVMConstReal(self.t.f64, -0.0), *v]);
                            LLVMSetFastMathFlags(c, llvm_sys::LLVMFastMathAllowReassoc);
                            c
                        })
                        .collect();
                    while parts.len() > 1 {
                        let (x, y) = (parts.remove(0), parts.remove(0));
                        let s = LLVMBuildFAdd(b, x, y, nm);
                        LLVMSetFastMathFlags(s, llvm_sys::LLVMFastMathAllowReassoc);
                        parts.push(s);
                    }
                    parts[0]
                }
                K::Call { name } => {
                    let params: Vec<LLVMTypeRef> = i.a.iter().map(|v| self.vty(*v)).collect();
                    let ret = d.map(|v| self.vty(v)).unwrap_or(self.t.void);
                    let f = self.declare(name, &params, ret);
                    let c = self.call(f, &a);
                    if d.is_none() {
                        return;
                    }
                    c
                }
                K::FrameAddr { off } => {
                    let frame = self.frame.expect("frame memory");
                    self.gep_bytes(frame, *off as u64)
                }
                K::DataAddr { bytes } => self.data(bytes),
                K::LoadU64 { off } => {
                    let p = self.gep_bytes(a[0], *off as u64);
                    self.load(self.t.i64, p)
                }
                K::CheckedInt { lo, slow } => {
                    // Exact and in range inline; only the raising call out of line.
                    let (l, value, site) = (a[0], a[1], a[2]);
                    let f = self.intrinsic("llvm.fptosi.sat", &[self.t.i32, self.t.f64]);
                    let w = self.call(f, &[value]);
                    let back = LLVMBuildSIToFP(b, w, self.t.f64, nm);
                    let exact = LLVMBuildFCmp(b, RP::LLVMRealOEQ, value, back, nm);
                    let above = LLVMBuildICmp(b, IP::LLVMIntSGE, w, LLVMConstInt(self.t.i32, *lo, 0), nm);
                    let ok = LLVMBuildAnd(b, exact, above, nm);
                    let from = self.cur();
                    let (slow_b, join) = (self.block("slow"), self.block("checked"));
                    LLVMBuildCondBr(b, ok, join, slow_b);
                    self.at(slow_b);
                    let sf = self.declare(slow, &[self.t.ptr, self.t.f64, self.t.ptr], self.t.i32);
                    let r = self.call(sf, &[l, value, site]);
                    LLVMBuildBr(b, join);
                    self.at(join);
                    let phi = LLVMBuildPhi(b, self.t.i32, nm);
                    let mut vs = [w, r];
                    let mut bs = [from, slow_b];
                    LLVMAddIncoming(phi, vs.as_mut_ptr(), bs.as_mut_ptr(), 2);
                    phi
                }
            }
        };
        if let Some(v) = d {
            self.vals.insert(v, r);
        }
    }

    fn cmp(&self, c: Cmp, kind: CmpKind, x: LLVMValueRef, y: LLVMValueRef) -> LLVMValueRef {
        let n = cs("");
        unsafe {
            if kind == CmpKind::F64 {
                let p = match c {
                    Cmp::Lt => RP::LLVMRealOLT,
                    Cmp::Le => RP::LLVMRealOLE,
                    Cmp::Gt => RP::LLVMRealOGT,
                    Cmp::Ge => RP::LLVMRealOGE,
                };
                return LLVMBuildFCmp(self.b, p, x, y, n.as_ptr());
            }
            let p = match c {
                Cmp::Lt => IP::LLVMIntULT,
                Cmp::Le => IP::LLVMIntULE,
                Cmp::Gt => IP::LLVMIntUGT,
                Cmp::Ge => IP::LLVMIntUGE,
            };
            // Unsigned throughout, so widening the narrower side is exact.
            let (x, y) = match (LLVMTypeOf(x) == self.t.i64, LLVMTypeOf(y) == self.t.i64) {
                (true, false) => (x, LLVMBuildZExt(self.b, y, self.t.i64, n.as_ptr())),
                (false, true) => (LLVMBuildZExt(self.b, x, self.t.i64, n.as_ptr()), y),
                _ => (x, y),
            };
            LLVMBuildICmp(self.b, p, x, y, n.as_ptr())
        }
    }

    fn cond(&self, c: &Cond<V>) -> LLVMValueRef {
        let n = cs("");
        unsafe {
            match c {
                Cond::Cmp(k, kind, x, y) => self.cmp(*k, *kind, self.v(*x), self.v(*y)),
                Cond::And(l, r) => LLVMBuildAnd(self.b, self.cond(l), self.cond(r), n.as_ptr()),
                Cond::Any(g) if self.t.wide => {
                    // Reduced in lane-width form, never through `<4 x i1>`: the
                    // halves OR-ed, then an unsigned max over 32-bit lanes (one
                    // `umaxv` on NEON).
                    let mut all = self.v(g[0]);
                    for m in &g[1..] {
                        all = LLVMBuildOr(self.b, all, self.v(*m), n.as_ptr());
                    }
                    let half = |k: u64| {
                        let mut idx = [LLVMConstInt(self.t.i32, 2 * k, 0), LLVMConstInt(self.t.i32, 2 * k + 1, 0)];
                        LLVMBuildShuffleVector(self.b, all, LLVMGetPoison(self.t.mask), LLVMConstVector(idx.as_mut_ptr(), 2), n.as_ptr())
                    };
                    let both = LLVMBuildOr(self.b, half(0), half(1), n.as_ptr());
                    let words = LLVMBuildBitCast(self.b, both, self.t.ivec, n.as_ptr());
                    let f = self.intrinsic("llvm.vector.reduce.umax", &[self.t.ivec]);
                    let any = self.call(f, &[words]);
                    LLVMBuildICmp(self.b, IP::LLVMIntNE, any, LLVMConstInt(self.t.i32, 0, 0), n.as_ptr())
                }
                Cond::Any(g) => {
                    let f = self.intrinsic("llvm.vector.reduce.or", &[self.t.bits]);
                    let mut any = self.call(f, &[self.bits(self.v(g[0]))]);
                    for m in &g[1..] {
                        let x = self.call(f, &[self.bits(self.v(*m))]);
                        any = LLVMBuildOr(self.b, any, x, n.as_ptr());
                    }
                    any
                }
            }
        }
    }

    fn phis(&self, like: &[V], init: &[LLVMValueRef], from: LLVMBasicBlockRef) -> Vec<LLVMValueRef> {
        let n = cs("");
        like.iter()
            .zip(init)
            .map(|(v, x)| unsafe {
                let p = LLVMBuildPhi(self.b, self.vty(*v), n.as_ptr());
                let (mut xs, mut bs) = ([*x], [from]);
                LLVMAddIncoming(p, xs.as_mut_ptr(), bs.as_mut_ptr(), 1);
                p
            })
            .collect()
    }

    /// Emits a region; true when every path through it returned.
    fn region(&mut self, nodes: &[Node]) -> bool {
        for node in nodes {
            match node {
                Node::Inst(i) => self.inst(i),
                Node::Loop { init, params, head, cond, body, next, outs } => unsafe {
                    let init: Vec<LLVMValueRef> = self.kept(init);
                    let pre = self.cur();
                    let (header, body_b, exit) = (self.block("loop"), self.block("body"), self.block("exit"));
                    LLVMBuildBr(self.b, header);
                    self.at(header);
                    let phis = self.phis(params, &init, pre);
                    for (p, x) in params.iter().zip(&phis) {
                        self.vals.insert(*p, *x);
                    }
                    self.region(head);
                    let c = self.cond(cond);
                    LLVMBuildCondBr(self.b, c, body_b, exit);
                    self.at(body_b);
                    if !self.region(body) {
                        let next = self.kept(next);
                        let latch = self.cur();
                        for (p, nv) in phis.iter().zip(next) {
                            let (mut xs, mut bs) = ([nv], [latch]);
                            LLVMAddIncoming(*p, xs.as_mut_ptr(), bs.as_mut_ptr(), 1);
                        }
                        LLVMBuildBr(self.b, header);
                    }
                    self.at(exit);
                    // The exit's one predecessor is the header: the values
                    // the test failed on are the header's.
                    for (o, x) in outs.iter().zip(&phis) {
                        self.vals.insert(*o, *x);
                    }
                },
                Node::If { cond, then, then_out, other, other_out, outs } => unsafe {
                    let c = self.cond(cond);
                    let (t, e, merge) = (self.block("then"), self.block("else"), self.block("merge"));
                    LLVMBuildCondBr(self.b, c, t, e);
                    let mut arms: Vec<(LLVMBasicBlockRef, Vec<LLVMValueRef>)> = Vec::new();
                    for (bb, nodes, out) in [(t, then, then_out), (e, other, other_out)] {
                        self.at(bb);
                        if !self.region(nodes) {
                            let vals = self.kept(out);
                            arms.push((self.cur(), vals));
                            LLVMBuildBr(self.b, merge);
                        }
                    }
                    if arms.is_empty() {
                        LLVMDeleteBasicBlock(merge);
                        return true;
                    }
                    self.at(merge);
                    let n = cs("");
                    for (k, o) in outs.iter().enumerate() {
                        let p = LLVMBuildPhi(self.b, self.vty(*o), n.as_ptr());
                        for (bb, vals) in &arms {
                            let (mut xs, mut bs) = ([vals[k]], [*bb]);
                            LLVMAddIncoming(p, xs.as_mut_ptr(), bs.as_mut_ptr(), 1);
                        }
                        self.vals.insert(*o, p);
                    }
                },
                Node::Return { vals } => unsafe {
                    if self.ret == self.t.void {
                        LLVMBuildRetVoid(self.b);
                    } else if let Some(v) = vals.first() {
                        LLVMBuildRet(self.b, self.v(*v));
                    } else {
                        // The fall-off after a body that always returns.
                        LLVMBuildUnreachable(self.b);
                    }
                    return true;
                },
            }
        }
        false
    }
}

fn fn_attr(ctx: LLVMContextRef, f: LLVMValueRef, name: &str, value: u64) {
    unsafe {
        let kind = LLVMGetEnumAttributeKindForName(name.as_ptr() as *const c_char, name.len());
        assert!(kind != 0, "attribute {name}");
        LLVMAddAttributeAtIndex(f, llvm_sys::LLVMAttributeFunctionIndex, LLVMCreateEnumAttribute(ctx, kind, value));
    }
}

fn str_attr(ctx: LLVMContextRef, f: LLVMValueRef, k: &str, v: &str) {
    unsafe {
        let a = LLVMCreateStringAttribute(ctx, k.as_ptr() as *const c_char, k.len() as u32, v.as_ptr() as *const c_char, v.len() as u32);
        LLVMAddAttributeAtIndex(f, llvm_sys::LLVMAttributeFunctionIndex, a);
    }
}

/// LLVM IR for one LIR function, named `name`, in a fresh context.
pub fn build(f: &lir::Func, name: &str, shape: &Shape, tier: Tier) -> Module {
    let module = Module::empty(name, tier);
    module.add(f, name, shape, tier);
    module
}

impl Module {
    /// A module to hold several functions: a whole program's kernels.
    pub fn empty(name: &str, tier: Tier) -> Module {
        unsafe {
            let ctx = LLVMContextCreate();
            let mn = cs(name);
            let m = LLVMModuleCreateWithNameInContext(mn.as_ptr(), ctx);
            let triple = cs(tier.triple());
            LLVMSetTarget(m, triple.as_ptr());
            Module { ctx, m, name: name.to_string() }
        }
    }

    /// Adds one LIR function, named `name`, and verifies the module.
    pub fn add(&self, f: &lir::Func, name: &str, shape: &Shape, tier: Tier) {
    let (ctx, m) = (self.ctx, self.m);
    let mn = cs(name);
    unsafe {
        let f64t = LLVMDoubleTypeInContext(ctx);
        let i1 = LLVMInt1TypeInContext(ctx);
        let i32t = LLVMInt32TypeInContext(ctx);
        let t = Tys {
            void: LLVMVoidTypeInContext(ctx),
            i1,
            i8: LLVMInt8TypeInContext(ctx),
            i32: i32t,
            i64: LLVMInt64TypeInContext(ctx),
            f64: f64t,
            ptr: LLVMPointerTypeInContext(ctx, 0),
            vec: LLVMVectorType(f64t, LANES as u32),
            mask: if wide_masks() { LLVMVectorType(LLVMInt64TypeInContext(ctx), LANES as u32) } else { LLVMVectorType(i1, LANES as u32) },
            ivec: LLVMVectorType(i32t, LANES as u32),
            bits: LLVMVectorType(i1, LANES as u32),
            wide: wide_masks(),
        };
        let _ = t.i1;
        let mut params: Vec<(u32, T)> = Vec::new();
        for n in &f.body {
            let Node::Inst(Inst { k: K::Param { index }, d, .. }) = n else { break };
            params.push((*index, f.types[d[0] as usize]));
        }
        params.sort_by_key(|p| p.0);
        let ret = match shape {
            Shape::LuaBuilder => t.i32,
            Shape::Kernel { sig, .. } => match sig.ret {
                Ret::Void => t.void,
                Ret::F64 => t.f64,
                Ret::U32 => t.i32,
            },
        };
        let mut e = E { f, ctx, m, b: LLVMCreateBuilderInContext(ctx), func: std::ptr::null_mut(), t, vals: HashMap::new(), frame: None, data: HashMap::new(), ret, tier };
        let mut pts: Vec<LLVMTypeRef> = params.iter().map(|p| e.ty(p.1)).collect();
        let ft = LLVMFunctionType(ret, pts.as_mut_ptr(), pts.len() as u32, 0);
        let func = LLVMAddFunction(m, mn.as_ptr(), ft);
        e.func = func;
        // uwtable(async), as clang emits; kernels cannot unwind, builders can.
        // NUPP_SPIKE_NO_TABLES: the negative control, no unwind info at all.
        if std::env::var("NUPP_SPIKE_NO_TABLES").is_ok() {
            fn_attr(ctx, func, "nounwind", 0);
        } else {
            fn_attr(ctx, func, "uwtable", 2);
        }
        if tier == Tier::Arm64Neon {
            str_attr(ctx, func, "frame-pointer", "non-leaf");
        }
        match shape {
            Shape::Kernel { noalias, .. } => {
                if std::env::var("NUPP_SPIKE_NO_TABLES").is_err() {
                    fn_attr(ctx, func, "nounwind", 0);
                }
                let kind = LLVMGetEnumAttributeKindForName(c"noalias".as_ptr(), 7);
                for p in noalias {
                    LLVMAddAttributeAtIndex(func, p + 1, LLVMCreateEnumAttribute(ctx, kind, 0));
                }
            }
            Shape::LuaBuilder => {}
        }
        let entry = e.block("entry");
        e.at(entry);
        if f.locals > 0 {
            let at = LLVMArrayType2(e.t.i8, f.locals as u64);
            let n = cs("frame");
            let a = LLVMBuildAlloca(e.b, at, n.as_ptr());
            LLVMSetAlignment(a, 16);
            e.frame = Some(a);
        }
        if !e.region(&f.body) {
            if ret == e.t.void {
                LLVMBuildRetVoid(e.b);
            } else {
                LLVMBuildUnreachable(e.b);
            }
        }
        LLVMDisposeBuilder(e.b);
        let mut err = std::ptr::null_mut();
        if llvm_sys::analysis::LLVMVerifyModule(m, llvm_sys::analysis::LLVMVerifierFailureAction::LLVMReturnStatusAction, &mut err) != 0 {
            let msg = take_message(err);
            eprintln!("{}", take_message(LLVMPrintModuleToString(m)));
            panic!("verifier ({name}): {msg}");
        }
        if !err.is_null() {
            LLVMDisposeMessage(err);
        }
    }
    }
}

/// Parameters the IR marks exclusive (`restrict` in the C backend's entry).
pub fn exclusive_params(program: &serde_json::Value, sig: &Signature) -> Vec<u32> {
    let exclusive: Vec<String> = program["params"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|p| p["ownership"] == "exclusive")
        .map(|p| format!("p_{}", p["name"].as_str().unwrap()))
        .collect();
    sig.params.iter().enumerate().filter(|(_, p)| exclusive.contains(&p.name)).map(|(k, _)| k as u32).collect()
}

// ---- loading ----------------------------------------------------------------

/// ORC's LLJIT, linking through JITLink, resolving undefined symbols against
/// the process (the Lua C API, libm, the runtime wrappers).
pub struct Jit {
    j: LLVMOrcLLJITRef,
    jd: LLVMOrcJITDylibRef,
}

extern "C" fn plain_linking_layer(_ctx: *mut c_void, es: LLVMOrcExecutionSessionRef, _triple: *const c_char) -> LLVMOrcObjectLayerRef {
    // JITLink with no plugins: nothing registers the object's unwind info.
    let mut layer = std::ptr::null_mut();
    unsafe { check(llvm_sys::orc2::ee::LLVMOrcCreateObjectLinkingLayerWithInProcessMemoryManager(&mut layer, es), "linking layer") };
    layer
}

impl Jit {
    /// `register_unwind`: false builds the linking layer without LLJIT's
    /// eh-frame registration plugin.
    pub fn new(tier: Tier, level: Level, register_unwind: bool) -> Jit {
        unsafe {
            let builder = LLVMOrcCreateLLJITBuilder();
            let jtmb = LLVMOrcJITTargetMachineBuilderCreateFromTargetMachine(target_machine(tier, level));
            LLVMOrcLLJITBuilderSetJITTargetMachineBuilder(builder, jtmb);
            if !register_unwind {
                LLVMOrcLLJITBuilderSetObjectLinkingLayerCreator(builder, plain_linking_layer, std::ptr::null_mut());
            }
            let mut j = std::ptr::null_mut();
            check(LLVMOrcCreateLLJIT(&mut j, builder), "LLJIT");
            let jd = LLVMOrcLLJITGetMainJITDylib(j);
            let mut generator = std::ptr::null_mut();
            check(
                LLVMOrcCreateDynamicLibrarySearchGeneratorForProcess(&mut generator, LLVMOrcLLJITGetGlobalPrefix(j), None, std::ptr::null_mut()),
                "process symbols",
            );
            LLVMOrcJITDylibAddGenerator(jd, generator);
            Jit { j, jd }
        }
    }

    /// Links a relocatable object: the cached-AOT shape.
    pub fn add_object(&self, object: &[u8], name: &str) {
        unsafe {
            let n = cs(name);
            let buf = LLVMCreateMemoryBufferWithMemoryRangeCopy(object.as_ptr() as *const c_char, object.len(), n.as_ptr());
            check(LLVMOrcLLJITAddObjectFile(self.j, self.jd, buf), "add object");
        }
    }

    /// Hands optimized IR to the JIT, which runs code generation itself.
    pub fn add_ir(&self, module: Module) {
        unsafe { check(LLVMOrcLLJITAddLLVMIRModule(self.j, self.jd, module.into_thread_safe()), "add IR") };
    }

    /// The address of `name`, linking whatever defines it on first lookup.
    pub fn lookup(&self, name: &str) -> *const u8 {
        unsafe {
            let n = cs(name);
            let mut addr = 0;
            check(LLVMOrcLLJITLookup(self.j, &mut addr, n.as_ptr()), name);
            addr as *const u8
        }
    }
}

impl Drop for Jit {
    fn drop(&mut self) {
        unsafe {
            check(LLVMOrcDisposeLLJIT(self.j), "dispose");
        }
    }
}
