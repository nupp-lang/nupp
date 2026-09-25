//! The implementation over the LLVM C API, plus the few C++ entry points in
//! `glue.cpp`.

use crate::{CODEGEN_VERSION, CompileOptions, Compiled, Timings, contract};
use llvm_sys::core::*;
use llvm_sys::error::*;
use llvm_sys::ir_reader::LLVMParseIRInContext2;
use llvm_sys::prelude::*;
use llvm_sys::target_machine::*;
use llvm_sys::transforms::pass_builder::*;
use std::ffi::{CStr, CString, c_char, c_int};
use std::time::Instant;

unsafe extern "C" {
    fn nupp_codegen_strict_fp(tm: LLVMTargetMachineRef) -> c_int;
    fn nupp_codegen_lld(argc: c_int, argv: *const *const c_char, out: *mut *mut c_char) -> c_int;
    fn nupp_codegen_import_library(
        dll: *const c_char,
        path: *const c_char,
        names: *const *const c_char,
        renames: *const *const c_char,
        n: c_int,
        error: *mut *mut c_char,
    ) -> c_int;
    fn nupp_codegen_archive(
        path: *const c_char,
        members: *const *const c_char,
        n: c_int,
        kind: c_int,
        error: *mut *mut c_char,
    ) -> c_int;
    fn nupp_codegen_free(p: *mut c_char);
}

pub fn version() -> String {
    let (mut major, mut minor, mut patch) = (0, 0, 0);
    unsafe { LLVMGetVersion(&mut major, &mut minor, &mut patch) };
    format!("llvm {major}.{minor}.{patch}; codegen {CODEGEN_VERSION}")
}

fn cs(s: &str) -> CString {
    CString::new(s.replace('\0', "?")).unwrap()
}

/// Takes an LLVM-owned message.
unsafe fn take(message: *mut c_char) -> String {
    if message.is_null() {
        return String::new();
    }
    let text = unsafe { CStr::from_ptr(message) }.to_string_lossy().into_owned();
    unsafe { LLVMDisposeMessage(message) };
    text
}

fn init_targets() {
    use std::sync::Once;
    static ONCE: Once = Once::new();
    ONCE.call_once(|| unsafe {
        use llvm_sys::target::*;
        LLVMInitializeAArch64TargetInfo();
        LLVMInitializeAArch64Target();
        LLVMInitializeAArch64TargetMC();
        LLVMInitializeAArch64AsmPrinter();
        LLVMInitializeAArch64AsmParser();
        LLVMInitializeAArch64Disassembler();
        LLVMInitializeX86TargetInfo();
        LLVMInitializeX86Target();
        LLVMInitializeX86TargetMC();
        LLVMInitializeX86AsmPrinter();
        LLVMInitializeX86AsmParser();
        LLVMInitializeX86Disassembler();
        LLVMInitializeWebAssemblyTargetInfo();
        LLVMInitializeWebAssemblyTarget();
        LLVMInitializeWebAssemblyTargetMC();
        LLVMInitializeWebAssemblyAsmPrinter();
        LLVMInitializeWebAssemblyAsmParser();
        LLVMInitializeWebAssemblyDisassembler();
    });
}

struct TargetMachine(LLVMTargetMachineRef);

impl Drop for TargetMachine {
    fn drop(&mut self) {
        unsafe { LLVMDisposeTargetMachine(self.0) };
    }
}

fn target_machine(options: &CompileOptions) -> Result<TargetMachine, String> {
    init_targets();
    unsafe {
        let triple = cs(&options.triple);
        let mut target = std::ptr::null_mut();
        let mut err = std::ptr::null_mut();
        if LLVMGetTargetFromTriple(triple.as_ptr(), &mut target, &mut err) != 0 {
            return Err(format!("target {}: {}", options.triple, take(err)));
        }
        let o = LLVMCreateTargetMachineOptions();
        let (cpu, features) = (cs(&options.cpu), cs(&options.features));
        LLVMTargetMachineOptionsSetCPU(o, cpu.as_ptr());
        LLVMTargetMachineOptionsSetFeatures(o, features.as_ptr());
        LLVMTargetMachineOptionsSetCodeGenOptLevel(
            o,
            match options.opt {
                0 => LLVMCodeGenOptLevel::LLVMCodeGenLevelNone,
                1 => LLVMCodeGenOptLevel::LLVMCodeGenLevelLess,
                2 => LLVMCodeGenOptLevel::LLVMCodeGenLevelDefault,
                _ => LLVMCodeGenOptLevel::LLVMCodeGenLevelAggressive,
            },
        );
        LLVMTargetMachineOptionsSetRelocMode(o, LLVMRelocMode::LLVMRelocPIC);
        let tm = LLVMCreateTargetMachineWithOptions(target, triple.as_ptr(), o);
        LLVMDisposeTargetMachineOptions(o);
        if tm.is_null() {
            return Err(format!("cannot create a target machine for {}", options.triple));
        }
        if nupp_codegen_strict_fp(tm) != 1 {
            LLVMDisposeTargetMachine(tm);
            return Err("cannot set strict floating-point fusion".into());
        }
        Ok(TargetMachine(tm))
    }
}

struct Module {
    ctx: LLVMContextRef,
    m: LLVMModuleRef,
}

impl Drop for Module {
    fn drop(&mut self) {
        unsafe {
            if !self.m.is_null() {
                LLVMDisposeModule(self.m);
            }
            LLVMContextDispose(self.ctx);
        }
    }
}

fn parse(ir: &str, name: &str) -> Result<Module, String> {
    unsafe {
        let ctx = LLVMContextCreate();
        let n = cs(name);
        let buffer = LLVMCreateMemoryBufferWithMemoryRangeCopy(ir.as_ptr() as *const c_char, ir.len(), n.as_ptr());
        let mut m = std::ptr::null_mut();
        let mut message = std::ptr::null_mut();
        // Borrows the buffer, which is disposed here either way.
        let failed = LLVMParseIRInContext2(ctx, buffer, &mut m, &mut message) != 0;
        LLVMDisposeMemoryBuffer(buffer);
        if failed {
            LLVMContextDispose(ctx);
            return Err(format!("{name}: {}", take(message)));
        }
        let module = Module { ctx, m };
        let mut message = std::ptr::null_mut();
        if llvm_sys::analysis::LLVMVerifyModule(
            m,
            llvm_sys::analysis::LLVMVerifierFailureAction::LLVMReturnStatusAction,
            &mut message,
        ) != 0
        {
            return Err(format!("{name}: invalid IR: {}", take(message)));
        }
        take(message);
        Ok(module)
    }
}

fn optimize(module: &Module, tm: &TargetMachine, opt: u8) -> Result<(), String> {
    unsafe {
        let o = LLVMCreatePassBuilderOptions();
        LLVMPassBuilderOptionsSetLoopVectorization(o, (opt >= 2) as i32);
        LLVMPassBuilderOptionsSetSLPVectorization(o, (opt >= 2) as i32);
        LLVMPassBuilderOptionsSetLoopInterleaving(o, (opt >= 2) as i32);
        LLVMPassBuilderOptionsSetLoopUnrolling(o, (opt >= 2) as i32);
        let pipeline = cs(&format!("default<O{opt}>"));
        let err = LLVMRunPasses(module.m, pipeline.as_ptr(), tm.0, o);
        LLVMDisposePassBuilderOptions(o);
        if !err.is_null() {
            return Err(format!("optimization: {}", take(LLVMGetErrorMessage(err))));
        }
        Ok(())
    }
}

fn emit(module: &Module, tm: &TargetMachine, kind: LLVMCodeGenFileType) -> Result<Vec<u8>, String> {
    unsafe {
        // Code generation rewrites IR (CodeGenPrepare); emit from a copy so the
        // module can be emitted again.
        let copy = LLVMCloneModule(module.m);
        let mut err = std::ptr::null_mut();
        let mut buf = std::ptr::null_mut();
        let failed = LLVMTargetMachineEmitToMemoryBuffer(tm.0, copy, kind, &mut err, &mut buf) != 0;
        LLVMDisposeModule(copy);
        if failed {
            return Err(format!("code generation: {}", take(err)));
        }
        let bytes = std::slice::from_raw_parts(LLVMGetBufferStart(buf) as *const u8, LLVMGetBufferSize(buf)).to_vec();
        LLVMDisposeMemoryBuffer(buf);
        Ok(bytes)
    }
}

fn micros(t: Instant) -> f64 {
    t.elapsed().as_secs_f64() * 1e6
}

pub fn compile(ir: &str, name: &str, options: &CompileOptions) -> Result<Compiled, String> {
    let tm = target_machine(options)?;
    let t = Instant::now();
    let module = parse(ir, name)?;
    // The target decides the triple and data layout; the emitter's IR names
    // neither, so the same text serves every target.
    let triple = cs(&options.triple);
    unsafe {
        LLVMSetTarget(module.m, triple.as_ptr());
        let layout = LLVMCreateTargetDataLayout(tm.0);
        llvm_sys::target::LLVMSetModuleDataLayout(module.m, layout);
        llvm_sys::target::LLVMDisposeTargetData(layout);
    }
    let parse_us = micros(t);
    let t = Instant::now();
    optimize(&module, &tm, options.opt)?;
    let optimize_us = micros(t);
    let optimized = if options.verify || options.optimized_ir {
        Some(unsafe { take(LLVMPrintModuleToString(module.m)) })
    } else {
        None
    };
    let t = Instant::now();
    let object = emit(&module, &tm, LLVMCodeGenFileType::LLVMObjectFile)?;
    let codegen_us = micros(t);
    let assembly = if options.assembly {
        Some(String::from_utf8_lossy(&emit(&module, &tm, LLVMCodeGenFileType::LLVMAssemblyFile)?).into_owned())
    } else {
        None
    };
    let mut violations = Vec::new();
    if options.verify {
        let ir = optimized.as_deref().unwrap_or_default();
        violations.extend(contract::ir_contract(ir));
        if let Some(asm) = &assembly {
            violations.extend(contract::fused_instructions(asm, ir));
        }
    }
    Ok(Compiled {
        object,
        assembly,
        optimized_ir: optimized.filter(|_| options.optimized_ir),
        violations,
        timings: Timings { parse: parse_us, optimize: optimize_us, codegen: codegen_us },
    })
}

pub fn link(argv: &[String]) -> Result<String, String> {
    init_targets();
    let owned: Vec<CString> = argv.iter().map(|a| cs(a)).collect();
    let pointers: Vec<*const c_char> = owned.iter().map(|a| a.as_ptr()).collect();
    let mut out = std::ptr::null_mut();
    let code = unsafe { nupp_codegen_lld(pointers.len() as c_int, pointers.as_ptr(), &mut out) };
    let text = if out.is_null() {
        String::new()
    } else {
        let t = unsafe { CStr::from_ptr(out) }.to_string_lossy().into_owned();
        unsafe { nupp_codegen_free(out) };
        t
    };
    if code == 0 { Ok(text) } else { Err(format!("lld exited {code}: {}", text.trim())) }
}

pub fn import_library(dll: &str, path: &str, names: &[(String, String)]) -> Result<(), String> {
    let n: Vec<CString> = names.iter().map(|(name, _)| cs(name)).collect();
    let r: Vec<CString> = names.iter().map(|(_, rename)| cs(rename)).collect();
    let np: Vec<*const c_char> = n.iter().map(|s| s.as_ptr()).collect();
    let rp: Vec<*const c_char> = r.iter().map(|s| s.as_ptr()).collect();
    let (d, p) = (cs(dll), cs(path));
    let mut error = std::ptr::null_mut();
    let code = unsafe {
        nupp_codegen_import_library(d.as_ptr(), p.as_ptr(), np.as_ptr(), rp.as_ptr(), np.len() as c_int, &mut error)
    };
    if code == 0 {
        return Ok(());
    }
    let text = if error.is_null() {
        String::new()
    } else {
        let t = unsafe { CStr::from_ptr(error) }.to_string_lossy().into_owned();
        unsafe { nupp_codegen_free(error) };
        t
    };
    Err(format!("import library {path}: {text}"))
}

pub fn archive(path: &str, members: &[String], kind: i32) -> Result<(), String> {
    let m: Vec<CString> = members.iter().map(|member| cs(member)).collect();
    let mp: Vec<*const c_char> = m.iter().map(|s| s.as_ptr()).collect();
    let p = cs(path);
    let mut error = std::ptr::null_mut();
    let code = unsafe { nupp_codegen_archive(p.as_ptr(), mp.as_ptr(), mp.len() as c_int, kind, &mut error) };
    if code == 0 {
        return Ok(());
    }
    let text = if error.is_null() {
        String::new()
    } else {
        let t = unsafe { CStr::from_ptr(error) }.to_string_lossy().into_owned();
        unsafe { nupp_codegen_free(error) };
        t
    };
    Err(format!("archive {path}: {text}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    const KERNEL: &str = r#"
define void @scale(ptr noalias %out, ptr noalias readonly %in, i64 %n) #0 {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %next, %body ]
  %done = icmp uge i64 %i, %n
  br i1 %done, label %exit, label %body
body:
  %p = getelementptr inbounds nuw double, ptr %in, i64 %i
  %x = load double, ptr %p, align 8
  %m = fmul double %x, 1.25
  %y = fadd double %m, -0.5
  %q = getelementptr inbounds nuw double, ptr %out, i64 %i
  store double %y, ptr %q, align 8
  %next = add nuw i64 %i, 1
  br label %loop
exit:
  ret void
}
attributes #0 = { nounwind }
"#;

    fn options(triple: &str) -> CompileOptions {
        CompileOptions { triple: triple.into(), opt: 3, verify: true, assembly: true, ..CompileOptions::default() }
    }

    #[test]
    fn compiles_for_every_target_without_fusing() {
        for triple in ["arm64-apple-macosx11.0.0", "x86_64-unknown-linux-gnu", "x86_64-w64-windows-gnu", "wasm32-unknown-unknown"] {
            let mut o = options(triple);
            if triple.starts_with("x86_64") {
                o.features = "+avx2,+fma".into();
            }
            let c = compile(KERNEL, "scale", &o).unwrap_or_else(|e| panic!("{triple}: {e}"));
            assert!(!c.object.is_empty(), "{triple}");
            assert!(c.violations.is_empty(), "{triple}: {:?}", c.violations);
        }
    }

    #[test]
    fn invalid_ir_is_an_error_not_an_abort() {
        let e = compile("define void @f() { ret i32 1 }", "bad", &options("x86_64-unknown-linux-gnu")).unwrap_err();
        assert!(e.contains("bad"), "{e}");
    }

    #[test]
    fn lld_reports_failure() {
        let e = link(&["ld.lld".into(), "/nonexistent.o".into(), "-o".into(), "/dev/null".into()]).unwrap_err();
        assert!(e.contains("nonexistent"), "{e}");
    }
}
