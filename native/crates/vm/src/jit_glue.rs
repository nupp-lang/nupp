//! The JIT's glue (gate N09): a guest function is described as text, the
//! Nupp emitter (`nupp.compiler.clif.guest`, running on a VM of its own with
//! the emitter image) lowers it to CLIF, and `cranelift-jit` compiles the
//! text to a frame entry whose address goes into `frame_entries`. The entry's
//! contract and exit words are the emitter's (`guest.nupp`); this file holds
//! no lowering of its own, only the hand-off and the helpers the emitted code
//! calls by C ABI: the handlers' own runtime helpers under their names, and
//! three for the frame protocol (`nupp_jit_step`, `nupp_jit_call`,
//! `nupp_jit_finish`).
//!
//! Guest mode is on when the emitter image is named by `NUPP_JIT_IMAGE` and a
//! native core drives the task (the entries take the core's context); with it
//! on, every frame entry is a guest entry and the Rust lowering is not used.
#![cfg_attr(not(feature = "native-runtime"), allow(dead_code, unused_imports))]
use crate::interp::{Function, Interp, Outcome, Step};
use crate::threaded::{Ctx, NO_GUARD, ST_DONE, ST_ERROR, ST_PARKED, ST_REENTER};
use crate::value::Value;
use cranelift_codegen::ir::{ExternalName, UserExternalName};
use cranelift_codegen::settings::{self, Configurable};
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{Linkage, Module, default_libcall_names};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;

/// The exit words of a guest entry above any pc (`guest.nupp`).
pub const EXIT_LEFT: u64 = u64::MAX;
pub const EXIT_REENTER: u64 = u64::MAX - 1;
pub const EXIT_RETURNED: u64 = u64::MAX - 2;
const ERROR: u64 = Value::ERROR.0;
/// Every return goes to Rust: an unwind is driving the task's cleanups
/// (`dispatch.rs`'s own value).
const GUARD_ALL: u64 = u64::MAX - 1;

thread_local! {
    /// The context of the task the native core is running on this thread,
    /// set by `run_threaded` around the core; null when no core runs.
    static CURRENT_CTX: Cell<*mut Ctx> = const { Cell::new(std::ptr::null_mut()) };
    /// What a guest entry left for: the step a finished or parked task ended
    /// with, read by whoever receives `EXIT_LEFT`.
    static LEFT: RefCell<Option<Step>> = const { RefCell::new(None) };
    /// This thread's emitter, made on its first compile.
    static EMITTER: RefCell<Option<Emitter>> = const { RefCell::new(None) };
}

/// Marks `ctx` as the context the core runs on this thread, restoring the
/// previous one when dropped: VMs nest on one thread (the emitter's own runs
/// inside a compile).
pub(crate) struct ContextGuard(*mut Ctx);
impl ContextGuard {
    pub(crate) fn enter(ctx: *mut Ctx) -> ContextGuard {
        ContextGuard(CURRENT_CTX.with(|c| c.replace(ctx)))
    }
}
impl Drop for ContextGuard {
    fn drop(&mut self) { CURRENT_CTX.with(|c| c.set(self.0)); }
}

/// The emitter image's path, when guest mode is on.
fn image_path() -> Option<String> {
    std::env::var("NUPP_JIT_IMAGE").ok().filter(|p| !p.is_empty())
}

/// Whether frame entries are compiled by the Nupp emitter: the image is
/// named, and the native core is linked to drive the entries.
pub fn guest_mode() -> bool {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ON.get_or_init(|| cfg!(feature = "native-runtime") && image_path().is_some())
}

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

/// The layout table the emitter reads, as JSON: the glue's fields.
fn layouts_json() -> String {
    let mut text = String::from("{");
    for (i, field) in crate::native_glue::LAYOUT_FIELDS.iter().enumerate() {
        if i > 0 { text.push(','); }
        text.push_str(&format!("\"{field}\":{}", crate::native_glue::layout(field).unwrap()));
    }
    text.push_str(&format!(",\"interp\":{}", std::mem::offset_of!(Ctx, interp)));
    text.push('}');
    text
}

/// The emitter: a VM running the emitter image, and the module compiled
/// code accumulates in. One per thread that compiles.
pub struct Emitter {
    vm: Box<Interp>,
    compile: Value,
    layouts: Value,
    module: JITModule,
    ctx: cranelift_codegen::Context,
    serial: u64,
    /// Time spent emitting text and compiling it, in microseconds, for the
    /// compile-cost measurement (`JIT_GUEST_STATS=1` prints them at exit).
    pub emit_micros: u128,
    pub compile_micros: u128,
    pub compiled: u64,
    pub refused: u64,
    /// What making the emitter cost: loading its image and reaching its
    /// entry point, paid once per compiling thread.
    pub startup_micros: u128,
    /// The slowest emission and its function, for the compile-cost record.
    pub slowest_micros: u128,
    pub slowest: String,
}

impl Emitter {
    fn new() -> Result<Emitter, String> {
        let started = std::time::Instant::now();
        let path = image_path().ok_or("NUPP_JIT_IMAGE names no emitter image")?;
        let bytes = std::fs::read(&path).map_err(|e| format!("{path}: {e}"))?;
        let mut vm = Box::new(Interp::new());
        if bytes.starts_with(crate::graph::MAGIC) {
            crate::graph::load_owned(&mut vm, bytes)?;
        } else {
            let text = std::str::from_utf8(&bytes).map_err(|_| format!("{path}: not text"))?;
            crate::image::load(&mut vm, text)?;
        }
        vm.install_globals();
        vm.prepare_threaded();
        let module_value = vm.require("nupp.compiler.clif.guest");
        vm.registered.push(module_value);
        let key = vm.intern("compile");
        let compile = vm.get_index(module_value, key);
        if compile == Value::NIL { return Err("the emitter image has no nupp.compiler.clif.guest.compile".into()); }
        let layouts = vm.heap_new_string(&layouts_json());
        vm.registered.push(layouts);
        let mut flags = settings::builder();
        flags.set("opt_level", "none").unwrap();
        flags.set("enable_verifier", if std::env::var_os("JIT_VERIFY").is_some() { "true" } else { "false" }).unwrap();
        flags.set("use_colocated_libcalls", "false").unwrap();
        flags.set("is_pic", "false").unwrap();
        flags.set("preserve_frame_pointers", "true").unwrap();
        let isa = cranelift_native::builder().unwrap().finish(settings::Flags::new(flags)).unwrap();
        let mut builder = JITBuilder::with_isa(isa, default_libcall_names());
        #[cfg(feature = "native-runtime")]
        for (name, address) in helper_table() { builder.symbol(name, address); }
        let module = JITModule::new(builder);
        let ctx = module.make_context();
        Ok(Emitter { vm, compile, layouts, module, ctx, serial: 0, emit_micros: 0, compile_micros: 0, compiled: 0, refused: 0, startup_micros: started.elapsed().as_micros(), slowest_micros: 0, slowest: String::new() })
    }

    /// The CLIF of a function, or the reason the emitter refused it.
    pub fn emit(&mut self, text: &str) -> Result<String, String> {
        let source = self.vm.heap_new_string(text);
        let handle = self.vm.register(source);
        let nested = Value::num(std::mem::offset_of!(Interp, nested_calls) as f64);
        let compile = self.compile;
        let layouts = self.layouts;
        let answer = self.vm.guarded(|vm| {
            let outs = vm.call_value(compile, &[source, layouts, nested]);
            let clif = outs.first().copied().unwrap_or(Value::NIL);
            let reason = outs.get(1).copied().unwrap_or(Value::NIL);
            if vm.bytes_of(clif).is_empty() {
                let message = String::from_utf8_lossy(vm.bytes_of(reason)).into_owned();
                vm.err(&format!("refused: {message}"));
            }
            clif
        });
        self.vm.release(handle);
        if answer == Value::ERROR {
            let e = self.vm.pending_error.take().unwrap_or(Value::NIL);
            let message = String::from_utf8_lossy(self.vm.bytes_of(e)).into_owned();
            return Err(message.strip_prefix("refused: ").map(str::to_string).unwrap_or(format!("emitter raised: {message}")));
        }
        let clif = String::from_utf8_lossy(self.vm.bytes_of(answer)).into_owned();
        Ok(clif)
    }

    /// Compiles one function's CLIF and answers its entry address. The text
    /// names helpers as `%symbol`; they resolve to the helper table.
    pub fn compile(&mut self, clif: &str) -> Result<u64, String> {
        let mut functions = cranelift_reader::parse_functions(clif).map_err(|e| e.to_string())?;
        if functions.len() != 1 { return Err(format!("{} functions in the emitted text", functions.len())); }
        let mut function = functions.pop().unwrap();
        let conv = self.module.isa().default_call_conv();
        function.signature.call_conv = conv;
        for (_, signature) in function.dfg.signatures.iter_mut() { signature.call_conv = conv; }
        self.serial += 1;
        let name = format!("{}.{}", crate::native_glue::name_of(&function), self.serial);
        let id = self.module.declare_function(&name, Linkage::Local, &function.signature).map_err(|e| e.to_string())?;
        let references: Vec<_> = function.dfg.ext_funcs.iter().filter_map(|(reference, data)| match &data.name {
            ExternalName::TestCase(callee) => Some((reference, callee.to_string().trim_start_matches('%').to_string(), data.signature)),
            _ => None,
        }).collect();
        let mut imports: HashMap<String, cranelift_module::FuncId> = HashMap::new();
        for (reference, callee, signature) in references {
            let declared = match imports.get(&callee) {
                Some(id) => *id,
                None => {
                    let sig = function.dfg.signatures[signature].clone();
                    let id = self.module.declare_function(&callee, Linkage::Import, &sig).map_err(|e| format!("{callee}: {e}"))?;
                    imports.insert(callee.clone(), id);
                    id
                }
            };
            let user = function.declare_imported_user_function(UserExternalName { namespace: 0, index: declared.as_u32() });
            let data = &mut function.dfg.ext_funcs[reference];
            data.name = ExternalName::user(user);
            data.colocated = false;
        }
        self.ctx.func = function;
        self.module.define_function(id, &mut self.ctx).map_err(|e| format!("{name}: {e}"))?;
        self.module.clear_context(&mut self.ctx);
        self.module.finalize_definitions().map_err(|e| e.to_string())?;
        Ok(self.module.get_finalized_function(id) as u64)
    }

    /// Describes, emits and compiles `f`: the entry address, or why not.
    pub fn compile_function(&mut self, f: &Function, fid: u32) -> Result<u64, String> {
        let started = std::time::Instant::now();
        let clif = self.emit(&describe(f, fid));
        let emitted = std::time::Instant::now();
        let took = (emitted - started).as_micros();
        self.emit_micros += took;
        if took > self.slowest_micros { self.slowest_micros = took; self.slowest = format!("{} ({} ops)", f.name, f.code.len()); }
        if std::env::var_os("JIT_GUEST_TRACE").is_some() { eprintln!("guest jit: emitted {} ({} ops) in {} us", f.name, f.code.len(), took); }
        let clif = match clif { Ok(c) => c, Err(e) => { self.refused += 1; return Err(e); } };
        if std::env::var_os("JIT_GUEST_DUMP").is_some() { eprintln!("{clif}"); }
        let entry = self.compile(&clif);
        self.compile_micros += emitted.elapsed().as_micros();
        if entry.is_ok() { self.compiled += 1; }
        entry
    }
}

impl Drop for Emitter {
    fn drop(&mut self) {
        if std::env::var_os("JIT_GUEST_STATS").is_some() {
            eprintln!("guest jit: compiled {} refused {} emit {:.2} ms compile {:.2} ms startup {:.2} ms slowest {} {:.2} ms", self.compiled, self.refused, self.emit_micros as f64 / 1e3, self.compile_micros as f64 / 1e3, self.startup_micros as f64 / 1e3, self.slowest, self.slowest_micros as f64 / 1e3);
        }
    }
}

/// Compiles `f` with this thread's emitter. `JIT_GUEST_ONLY=a,b` compiles
/// those functions and nothing else, `JIT_GUEST_SKIP=a,b` everything but
/// those: the bisection controls.
pub fn compile_here(f: &Function, fid: u32) -> Result<u64, String> {
    if let Ok(only) = std::env::var("JIT_GUEST_ONLY") {
        if !only.split(',').any(|n| n == f.name) { return Err("not in JIT_GUEST_ONLY".into()); }
    }
    if let Ok(skip) = std::env::var("JIT_GUEST_SKIP") {
        if skip.split(',').any(|n| n == f.name) { return Err("in JIT_GUEST_SKIP".into()); }
    }
    EMITTER.with(|slot| {
        let mut slot = slot.borrow_mut();
        if slot.is_none() { *slot = Some(Emitter::new()?); }
        slot.as_mut().unwrap().compile_function(f, fid)
    })
}

// --- The helpers compiled code calls -----------------------------------------

/// The task record brought up to date with the context before Rust touches
/// it, and the context after: what `dispatch.rs` does around every helper,
/// repeated here until its `charge` and `sync` are shared.
fn budgeted(it: &Interp, tid: usize) -> bool { it.scheduler.as_ref().is_some_and(|s| s.controls.contains_key(&tid)) }

/// Charges what the core took since the last sync and tells the task record
/// where the core left the frame.
fn charge(ctx: &mut Ctx, it: &mut Interp) {
    let tid = ctx.tid as usize;
    let used = ctx.budget_mark.saturating_sub(ctx.budget);
    if used != 0 {
        ctx.budget_mark = ctx.budget;
        if let Some(n) = it.execution_limit.as_mut() { *n = n.saturating_sub(used as usize); }
        if budgeted(it, tid) { if let Some(n) = it.instruction_budget.as_mut() { *n = n.saturating_sub(used as usize); } }
    }
    it.tasks[tid].set_cur(ctx.cur as usize);
    it.last_nres = ctx.last_nres as usize;
}

fn enter(ctx: &mut Ctx) -> (&'static mut Interp, usize) {
    let it = unsafe { &mut *(ctx.interp as *mut Interp) };
    charge(ctx, it);
    (it, ctx.tid as usize)
}

fn leave(ctx: &mut Ctx, it: &mut Interp) {
    let tid = ctx.tid as usize;
    let mut limit = u64::MAX;
    if let Some(n) = it.execution_limit { limit = limit.min(n as u64); }
    if budgeted(it, tid) { if let Some(n) = it.instruction_budget { limit = limit.min(n as u64); } }
    ctx.budget = limit;
    ctx.budget_mark = limit;
    let unwinding = budgeted(it, tid) && it.unwind_state(tid) != Value::NIL;
    let t = &mut it.tasks[tid];
    ctx.stack = t.stack.as_mut_ptr();
    ctx.cap = t.stack.len() as u64;
    ctx.cur = t.cur() as u64;
    ctx.guard = if unwinding { GUARD_ALL } else {
        match (t.cleanups.last().map(|c| c.frame as u64), t.protected.last().map(|p| p.frame as u64)) { (None, None) => NO_GUARD, (a, b) => a.unwrap_or(0).max(b.unwrap_or(0)) }
    };
    ctx.last_nres = it.last_nres as u64;
    ctx.funcs = it.finfo.as_ptr();
    ctx.nfuncs = it.finfo.len() as u64;
    ctx.shapes = it.shape_info.as_ptr();
    ctx.nshapes = it.shape_info.len() as u64;
    ctx.frame_entries = it.frame_entries.as_ptr();
    ctx.nframe_entries = it.frame_entries.len() as u64;
}

/// The core's status words as the emitted code's exit words.
fn exit_word(ctx: &mut Ctx, status: u32) -> u64 {
    match status {
        ST_ERROR => { ctx.status = ST_ERROR; ERROR }
        ST_REENTER => EXIT_REENTER,
        ST_DONE => { LEFT.with(|l| *l.borrow_mut() = Some(Step::Return(Outcome::Done(Value(ctx.result))))); EXIT_LEFT }
        ST_PARKED => { LEFT.with(|l| *l.borrow_mut() = Some(Step::Return(Outcome::Parked(ctx.result)))); EXIT_LEFT }
        pc => pc as u64,
    }
}

/// Runs the interpreter on the task until the frame at `stop` is on top
/// again: the callee a compiled caller pushed, or the frames an instruction
/// it stepped left above it. `word` is what the callee's entry or the step
/// answered; a word that already ends the activation passes through.
fn finish(ctx: &mut Ctx, stop: u64, word: u64) -> u64 {
    if word == ERROR || word == EXIT_LEFT { return word; }
    if ctx.cur == stop { return EXIT_RETURNED; }
    if word < u32::MAX as u64 {
        // The frame on top goes on at that pc.
        let (it, tid) = enter(ctx);
        it.tasks[tid].note_pc(word as usize);
        leave(ctx, it);
    }
    let (it, tid) = enter(ctx);
    let mark = it.handles.len();
    let driven = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| it.drive_until(tid, stop as usize)));
    if driven.is_err() { it.handles.truncate(mark); }
    let answer = match driven {
        Ok(Ok(())) => EXIT_RETURNED,
        Ok(Err(Step::Reenter)) => EXIT_REENTER,
        Ok(Err(Step::Next(_))) => EXIT_REENTER,
        Ok(Err(step)) => { LEFT.with(|l| *l.borrow_mut() = Some(step)); EXIT_LEFT }
        Err(p) => { let v = it.error_value(p); it.pending_error = Some(v); ctx.status = ST_ERROR; ERROR }
    };
    leave(ctx, it);
    answer
}

#[cfg(feature = "native-runtime")]
mod exported {
    use super::*;
    /// The interpreter runs the instruction at `pc` of the frame on top; the
    /// next pc, or the exit word that ends the activation.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_jit_step(ctx: *mut Ctx, pc: u64) -> u64 {
        let status = crate::threaded::rt_exec_op(ctx, pc as u32);
        if std::env::var_os("JIT_GUEST_TRACE").is_some() { eprintln!("guest jit: step {pc} -> {status:#x}"); }
        exit_word(unsafe { &mut *ctx }, status)
    }
    /// A callee frame compiled code pushed, without a compiled entry: the
    /// frame driver's service enters it (compiling it first when `hot`), and
    /// the interpreter finishes it until the caller at `caller` is on top.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_jit_call(ctx: *mut Ctx, caller: u64, hot: u64) -> u64 {
        let status = crate::threaded::rt_enter_frame(ctx, 0, hot as u32);
        let word = exit_word(unsafe { &mut *ctx }, status);
        finish(unsafe { &mut *ctx }, caller, word)
    }
    /// Finishes a callee whose entry answered `word`.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_jit_finish(ctx: *mut Ctx, caller: u64, word: u64) -> u64 {
        finish(unsafe { &mut *ctx }, caller, word)
    }
    // The handlers' helpers, under the names the handler sources call them by.
    pub unsafe extern "C" fn nupp_rt_get_field(ctx: *mut Ctx, obj: u64, name: u64) -> u64 { crate::threaded::rt_get_field(ctx, obj, name) }
    pub unsafe extern "C" fn nupp_rt_barrier(ctx: *mut Ctx, parent: u64, child: u64) { crate::threaded::rt_barrier(ctx, parent, child) }
    pub unsafe extern "C" fn nupp_rt_new_record(ctx: *mut Ctx, shape: u64) -> u64 { crate::threaded::rt_new_record(ctx, shape as u32) }
    pub unsafe extern "C" fn nupp_rt_eq_slow(ctx: *mut Ctx, x: u64, y: u64) -> u64 { crate::threaded::rt_eq_slow(ctx, x, y) as u64 }
    pub unsafe extern "C" fn nupp_rt_observe(ctx: *mut Ctx, fid: u64, pc: u64, value: u64, kind: u64) {
        crate::specialize::rt_observe(unsafe { (*ctx).interp }, fid as u32, pc as u32, value, kind as u32);
    }
}

/// The symbols emitted code imports, by name.
#[cfg(feature = "native-runtime")]
fn helper_table() -> Vec<(&'static str, *const u8)> {
    use exported::*;
    vec![
        ("nupp_jit_step", nupp_jit_step as *const u8),
        ("nupp_jit_call", nupp_jit_call as *const u8),
        ("nupp_jit_finish", nupp_jit_finish as *const u8),
        ("nupp_rt_get_field", nupp_rt_get_field as *const u8),
        ("nupp_rt_barrier", nupp_rt_barrier as *const u8),
        ("nupp_rt_new_record", nupp_rt_new_record as *const u8),
        ("nupp_rt_eq_slow", nupp_rt_eq_slow as *const u8),
        ("nupp_rt_observe", nupp_rt_observe as *const u8),
    ]
}

// --- Entering compiled frames -------------------------------------------------

#[cfg(feature = "native-runtime")]
impl Interp {
    /// Runs the guest entry of the frame on top at `pc` and translates its
    /// exit word into the frame driver's answer: the pc to interpret at, or a
    /// step for a frame that changed (the driver's policy applies to the one
    /// on top now), left for the scheduler, or a pending raise.
    pub(crate) fn run_guest_frame(&mut self, tid: usize, fid: u32, pc: usize, entry: u64) -> Result<usize, Step> {
        let ctx = CURRENT_CTX.with(|c| c.get());
        if ctx.is_null() {
            // No core runs this task: the interpreter keeps it.
            return Ok(pc);
        }
        if unsafe { (*ctx).tid } as usize != tid { return Ok(pc); }
        // The context names this task; its view of the frame is brought up to
        // date (the interpreter may have moved frames since the core last
        // synced it, under `drive_until`) and read back afterwards.
        let context = unsafe { &mut *ctx };
        leave(context, self);
        let frame = unsafe { self.tasks[tid].stack.as_mut_ptr().add(self.tasks[tid].cur()) };
        self.compiled_frame_entries += 1;
        if pc != 0 { self.compiled_frame_continuations += 1; }
        let word = unsafe { std::mem::transmute::<u64, extern "C" fn(*mut Ctx, *mut u64, u64) -> u64>(entry)(ctx, frame, pc as u64) };
        charge(context, self);
        if std::env::var_os("JIT_GUEST_TRACE").is_some() { eprintln!("guest jit: {} entered at {pc} left with {word:#x} cur {} status {:#x} pending {}", self.funcs[fid as usize].name, context.cur, context.status, self.pending_error.is_some()); }
        match word {
            EXIT_RETURNED | EXIT_REENTER => Err(Step::Reenter),
            EXIT_LEFT => Err(LEFT.with(|l| l.borrow_mut().take()).expect("a guest entry left without a step")),
            ERROR => {
                let value = self.pending_error.take().unwrap_or(Value::NIL);
                std::panic::panic_any(crate::builtins::LuaError(value.0));
            }
            next => {
                assert!((next as usize) < self.funcs[fid as usize].code.len(), "guest entry answered pc {next} of {}", self.funcs[fid as usize].name);
                Ok(next as usize)
            }
        }
    }
}
