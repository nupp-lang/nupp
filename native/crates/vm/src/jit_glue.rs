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
use crate::threaded::{Ctx, ST_DONE, ST_ERROR, ST_PARKED, ST_REENTER};
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

/// The emitter image's path, when one is named.
fn image_path() -> Option<String> {
    std::env::var("NUPP_JIT_IMAGE").ok().filter(|p| !p.is_empty())
}

/// The module the emitter lives in.
pub const EMITTER_MODULE: &str = "nupp.compiler.clif.guest";

/// The image the emitter VM loads when none is named: the running VM's own,
/// when it carries the emitter (the compiler's image does), set by the
/// runner before the first compile.
static DEFAULT_IMAGE: std::sync::OnceLock<Vec<u8>> = std::sync::OnceLock::new();

/// Linked AOT frame entries of the image the emitter runs, when the runtime
/// carries them: the emitter then runs compiled rather than interpreted.
struct Linked { hash: [u8; 32], frames: Vec<(usize, u64)> }
static LINKED: std::sync::OnceLock<Linked> = std::sync::OnceLock::new();

/// Whether `it` is a VM whose frame entries the Nupp emitter should compile:
/// the native core is linked to drive them, and an emitter image is named or
/// the VM's own image carries the emitter.
pub fn guest_available(it: &Interp) -> bool {
    cfg!(feature = "native-runtime") && (image_path().is_some() || it.modules.contains_key(EMITTER_MODULE))
}

/// Remembers the running VM's image as the emitter's default.
pub fn set_default_image(it: &Interp) {
    if image_path().is_some() { return; }
    let bytes = match it.code_events.first() {
        Some(crate::persist::CodeEvent::Image(text)) => text.as_bytes().to_vec(),
        Some(crate::persist::CodeEvent::Graph { bytes, .. }) => bytes.clone(),
        _ => return,
    };
    let _ = DEFAULT_IMAGE.set(bytes);
}

/// Remembers the linked frame entries of the image with `hash`.
pub fn register_linked(hash: [u8; 32], frames: Vec<(usize, u64)>) {
    let _ = LINKED.set(Linked { hash, frames });
}

/// Whether frame entries are compiled by the Nupp emitter on this process's
/// worker: an image is named, and the native core is linked to drive the
/// entries. Per VM, `Interp::guest_jit` decides.
pub fn guest_mode() -> bool {
    cfg!(feature = "native-runtime") && (image_path().is_some() || DEFAULT_IMAGE.get().is_some())
}

/// A function as the emitter reads it: the image's function dialect, every
/// constant as its raw word, and the address of the inline-cache bank its
/// field sites write (`caches`), two words per `GetField` or `SetField` in
/// code order; zero when there is none.
pub fn describe(f: &Function, fid: u32, caches: u64) -> String {
    let mut text = String::new();
    let sig: String = f.sig.iter().map(|&c| c as char).collect();
    text.push_str(&format!("function {} {fid} {} {} {} {sig}:{}{}\n", f.name, f.nparams, f.nregs, f.nireg, f.ret as char, if f.vararg { " vararg" } else { "" }));
    text.push_str(&format!("  vectors {}\n", f.nvreg));
    if caches != 0 { text.push_str(&format!("  caches {caches:#x}\n")); }
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

/// The field sites of a function: what an inline-cache bank holds a pair of
/// words for.
pub fn field_sites(f: &Function) -> usize {
    f.code.iter().filter(|op| matches!(op, crate::interp::Op::GetField(..) | crate::interp::Op::SetField(..))).count()
}

/// What the specializer's feedback says a function's sites may assume, as
/// lines the emitter reads after the function: `epoch ADDRESS VALUE` names
/// the descriptor epoch (`Heap::proto_epoch`) and its value at planning;
/// `site PC method SHAPE WORD` says the method site at `pc` saw records of
/// one shape only, whose descriptor answers the method `WORD` (a closure or a
/// bare function of this image) while the epoch holds. Empty without
/// feedback (`JIT_FEEDBACK`/`JIT_SPECIALIZE`) or when nothing is monomorphic.
pub fn plan_text(it: &Interp, fid: u32) -> String {
    let Some(Some(feedback)) = it.spec.funcs.get(fid as usize) else { return String::new() };
    let f = &it.funcs[fid as usize];
    let mut text = String::new();
    for (pc, op) in f.code.iter().enumerate() {
        let crate::interp::Op::CallMethod(k, _, _) = *op else { continue };
        let Some(&site) = feedback.site_of.get(pc) else { continue };
        if site == crate::specialize::NO_SITE { continue }
        let Some(key) = feedback.sites[site as usize].mono() else { continue };
        if key & (0xf << 60) != crate::specialize::K_SHAPE { continue }
        let shape = (key & 0xffff_ffff) as usize;
        let name = f.consts[k as usize];
        let Some(&method) = it.heap.shapes.get(shape).and_then(|s| s.methods.get(&name)) else { continue };
        // A function of this image, as a closure or a bare value; builtins
        // and the rest keep the generic path.
        let ok = method.as_func().is_some_and(|id| (id as usize) < f.consts.len() || true) || it.kind_of(method) == Some(crate::heap::KIND_CLOSURE);
        if !ok { continue }
        text.push_str(&format!("  site {pc} method {shape} {:#x}\n", method.0));
    }
    if !text.is_empty() {
        text.insert_str(0, &format!("  epoch {:#x} {}\n", &it.heap.proto_epoch as *const u64 as u64, it.heap.proto_epoch));
    }
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
    pub parse_micros: u128,
    pub compile_micros: u128,
    pub compiled: u64,
    pub refused: u64,
    /// What making the emitter cost: loading its image and reaching its
    /// entry point, paid once per compiling thread.
    pub startup_micros: u128,
    /// The slowest emission and its function, for the compile-cost record.
    pub slowest_micros: u128,
    pub slowest: String,
    /// The inline-cache banks of the functions compiled, kept for the life
    /// of the code that embeds their addresses.
    banks: Vec<Box<[u64]>>,
}

impl Emitter {
    fn new() -> Result<Emitter, String> {
        let started = std::time::Instant::now();
        let (bytes, path) = match image_path() {
            Some(path) => (std::fs::read(&path).map_err(|e| format!("{path}: {e}"))?, path),
            None => (DEFAULT_IMAGE.get().ok_or("no emitter image: NUPP_JIT_IMAGE is unset and the running image has no emitter")?.clone(), "<running image>".to_string()),
        };
        let mut vm = Box::new(Interp::new());
        if bytes.starts_with(crate::graph::MAGIC) {
            crate::graph::load_owned(&mut vm, bytes)?;
        } else {
            let text = std::str::from_utf8(&bytes).map_err(|_| format!("{path}: not text"))?;
            crate::image::load(&mut vm, text)?;
        }
        // The emitter runs compiled when the runtime links its image's
        // frame entries: attached as the runner attaches them to the VM it
        // runs, with the tables linked code reads through the runtime view.
        let mut linked = false;
        if let Some(table) = LINKED.get() {
            if crate::persist::primary_image_hash(&vm).ok() == Some(table.hash) {
                vm.frame_entries.resize(vm.funcs.len(), 0);
                for &(fid, ptr) in &table.frames { if fid < vm.frame_entries.len() { vm.frame_entries[fid] = ptr; } }
                vm.entries = vec![0; vm.funcs.len()];
                vm.calltab = vm.funcs.iter().map(|f| { let plain = f.sig.iter().all(|&c| c == b'v') && f.ret != b'f' && !f.vararg; f.nparams as u64 | ((plain as u64) << 8) }).collect();
                vm.shape_probe = vm.heap.shapes.iter().map(|s| (s.table.as_ptr() as u64, s.mask)).collect();
                vm.runtime_consts = vm.funcs.iter().map(|f| f.consts.as_ptr() as u64).collect();
                vm.linked_frames = vm.frame_entries.clone();
                linked = true;
            }
        }
        vm.install_globals();
        vm.prepare_threaded();
        if std::env::var_os("JIT_GUEST_STATS").is_some() { eprintln!("guest jit: emitter from {path}, {}", if linked { "linked frame entries" } else { "interpreted" }); }
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
        Ok(Emitter { vm, compile, layouts, module, ctx, serial: 0, emit_micros: 0, parse_micros: 0, compile_micros: 0, compiled: 0, refused: 0, startup_micros: started.elapsed().as_micros(), slowest_micros: 0, slowest: String::new(), banks: Vec::new() })
    }

    /// The CLIF of a function, or the reason the emitter refused it.
    pub fn emit(&mut self, text: &str) -> Result<String, String> {
        let source = self.vm.heap_new_string(text);
        let handle = self.vm.register(source);
        let nested = Value::num(std::mem::offset_of!(Interp, nested_calls) as f64);
        let compile = self.compile;
        let layouts = self.layouts;
        // The emitter VM is the one the Rust-lowered helpers see while it
        // runs; the VM being compiled for gets its context back after.
        let _isolation = Isolation::enter(&mut *self.vm);
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
        let parsing = std::time::Instant::now();
        let mut functions = cranelift_reader::parse_functions(clif).map_err(|e| e.to_string())?;
        self.parse_micros += parsing.elapsed().as_micros();
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

    /// Describes, emits and compiles `f` under `plan` (what feedback lets its
    /// sites assume): the entry address, or why not.
    pub fn compile_function(&mut self, f: &Function, fid: u32, plan: &str) -> Result<u64, String> {
        let started = std::time::Instant::now();
        let sites = field_sites(f);
        let caches = if sites == 0 { 0 } else {
            let bank: Box<[u64]> = vec![0u64; sites * 2].into_boxed_slice();
            let address = bank.as_ptr() as u64;
            self.banks.push(bank);
            address
        };
        let mut text = describe(f, fid, caches);
        if !plan.is_empty() {
            // The plan lines go before `end`.
            text.truncate(text.len() - "end\n".len());
            text.push_str(plan);
            text.push_str("end\n");
        }
        let clif = self.emit(&text);
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
            eprintln!("guest jit: compiled {} refused {} emit {:.2} ms parse {:.2} ms compile {:.2} ms startup {:.2} ms slowest {} {:.2} ms", self.compiled, self.refused, self.emit_micros as f64 / 1e3, self.parse_micros as f64 / 1e3, (self.compile_micros - self.parse_micros) as f64 / 1e3, self.startup_micros as f64 / 1e3, self.slowest, self.slowest_micros as f64 / 1e3);
        }
    }
}

/// The thread's compiled-code context while the emitter VM runs: the
/// Rust-lowered helpers of its linked code read the VM through
/// `compiled::CTX`, and the VM compiled for gets its own back afterwards.
struct Isolation { previous: (*mut Interp, usize, u64) }
impl Isolation {
    fn enter(vm: *mut Interp) -> Isolation {
        use std::sync::atomic::Ordering::Relaxed;
        let previous = (crate::compiled::CTX.load(Relaxed), crate::compiled::HELPER_FP.swap(0, Relaxed), crate::compiled::CUR_CLOSURE.load(Relaxed));
        crate::compiled::CTX.store(vm, Relaxed);
        crate::compiled::CUR_CLOSURE.store(0, Relaxed);
        Isolation { previous }
    }
}
impl Drop for Isolation {
    fn drop(&mut self) {
        use std::sync::atomic::Ordering::Relaxed;
        crate::compiled::CTX.store(self.previous.0, Relaxed);
        crate::compiled::HELPER_FP.store(self.previous.1, Relaxed);
        crate::compiled::CUR_CLOSURE.store(self.previous.2, Relaxed);
    }
}

/// Compiles `f` with this thread's emitter. `JIT_GUEST_ONLY=a,b` compiles
/// those functions and nothing else, `JIT_GUEST_SKIP=a,b` everything but
/// those: the bisection controls.
pub fn compile_here(f: &Function, fid: u32, plan: &str) -> Result<u64, String> {
    if let Ok(only) = std::env::var("JIT_GUEST_ONLY") {
        if !only.split(',').any(|n| n == f.name) { return Err("not in JIT_GUEST_ONLY".into()); }
    }
    if let Ok(skip) = std::env::var("JIT_GUEST_SKIP") {
        if skip.split(',').any(|n| n == f.name) { return Err("in JIT_GUEST_SKIP".into()); }
    }
    EMITTER.with(|slot| {
        let mut slot = slot.borrow_mut();
        if slot.is_none() { *slot = Some(Emitter::new()?); }
        slot.as_mut().unwrap().compile_function(f, fid, plan)
    })
}

// --- The helpers compiled code calls -----------------------------------------

/// The task record brought up to date with the context before Rust touches
/// it (`threaded::charge`, then where the core left the frame), and the
/// context after (`threaded::sync`).
#[cfg(feature = "native-runtime")]
fn charge(ctx: &mut Ctx, it: &mut Interp) {
    crate::threaded::charge(ctx, it);
    let tid = ctx.tid as usize;
    it.tasks[tid].set_cur(ctx.cur as usize);
    it.last_nres = ctx.last_nres as usize;
}

#[cfg(feature = "native-runtime")]
fn enter(ctx: &mut Ctx) -> (&'static mut Interp, usize) {
    let it = unsafe { &mut *(ctx.interp as *mut Interp) };
    charge(ctx, it);
    (it, ctx.tid as usize)
}

#[cfg(feature = "native-runtime")]
fn leave(ctx: &mut Ctx, it: &mut Interp) { crate::threaded::sync(ctx, it); }

/// The core's status words as the emitted code's exit words.
#[cfg(feature = "native-runtime")]
fn exit_word(ctx: &mut Ctx, status: u32) -> u64 {
    match status {
        ST_ERROR => { ctx.status = ST_ERROR; ERROR }
        ST_REENTER => EXIT_REENTER,
        ST_DONE => { LEFT.with(|l| *l.borrow_mut() = Some(Step::Return(Outcome::Done(Value(ctx.result))))); EXIT_LEFT }
        ST_PARKED => { LEFT.with(|l| *l.borrow_mut() = Some(Step::Return(Outcome::Parked(ctx.result)))); EXIT_LEFT }
        pc => pc as u64,
    }
}

#[cfg(feature = "native-runtime")]
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
    pub unsafe extern "C" fn nupp_rt_call_builtin(ctx: *mut Ctx, id: u64, base: u64, nargs: u64) { crate::threaded::rt_call_builtin(ctx, id as u32, base, nargs as u32) }
    pub unsafe extern "C" fn nupp_rt_call_iter(ctx: *mut Ctx, iter: u64, base: u64) { crate::threaded::rt_call_iter(ctx, iter, base) }
    pub unsafe extern "C" fn nupp_rt_observe(ctx: *mut Ctx, fid: u64, pc: u64, value: u64, kind: u64) {
        crate::specialize::rt_observe(unsafe { (*ctx).interp }, fid as u32, pc as u32, value, kind as u32);
    }
    /// A field read the site's inline cache did not answer: the read itself,
    /// and the cache filled with the record's shape and the field's slot when
    /// the shape has one (a shape is permanent, contracts 2.5, so the pair
    /// stays right until the site sees another shape).
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_jit_field_miss(ctx: *mut Ctx, obj: u64, name: u64, cache: *mut u64) -> u64 {
        let value = crate::threaded::rt_get_field(ctx, obj, name);
        fill_cache(unsafe { &*(*ctx).interp.cast::<Interp>() }, obj, name, cache);
        value
    }
    /// A field store the site's inline cache did not take: the store itself,
    /// under the interpreter's rules, and the cache filled as for a read.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_jit_field_store(ctx: *mut Ctx, obj: u64, name: u64, value: u64, cache: *mut u64) {
        let context = unsafe { &mut *ctx };
        let (it, _) = enter(context);
        let r = it.guarded(|it| { it.store_field(Value(obj), Value(name), Value(value)); Value::NIL });
        if r == Value::ERROR { context.status = ST_ERROR; }
        fill_cache(it, obj, name, cache);
        leave(context, it);
    }
}

/// Fills a field site's cache with (shape + 1, slot) when `obj` is a record
/// whose shape holds `name` as a slot; a shape number is offset by one so an
/// empty cache (zero) matches nothing.
#[cfg(feature = "native-runtime")]
fn fill_cache(it: &Interp, obj: u64, name: u64, cache: *mut u64) {
    if cache.is_null() { return; }
    let Some(p) = Value(obj).as_obj() else { return };
    let header = unsafe { &*p.as_ptr() };
    if header.kind != crate::heap::KIND_RECORD { return; }
    let shape = header.aux as usize;
    let Some(slot) = it.heap.shapes.get(shape).and_then(|s| s.slot_of(Value(name))) else { return };
    unsafe { *cache = shape as u64 + 1; *cache.add(1) = slot as u64; }
}

/// The symbols emitted code imports, by name.
#[cfg(feature = "native-runtime")]
fn helper_table() -> Vec<(&'static str, *const u8)> {
    use exported::*;
    vec![
        ("nupp_jit_field_miss", nupp_jit_field_miss as *const u8),
        ("nupp_jit_field_store", nupp_jit_field_store as *const u8),
        ("nupp_jit_step", nupp_jit_step as *const u8),
        ("nupp_jit_call", nupp_jit_call as *const u8),
        ("nupp_jit_finish", nupp_jit_finish as *const u8),
        ("nupp_rt_get_field", nupp_rt_get_field as *const u8),
        ("nupp_rt_barrier", nupp_rt_barrier as *const u8),
        ("nupp_rt_new_record", nupp_rt_new_record as *const u8),
        ("nupp_rt_eq_slow", nupp_rt_eq_slow as *const u8),
        ("nupp_rt_call_builtin", nupp_rt_call_builtin as *const u8),
        ("nupp_rt_call_iter", nupp_rt_call_iter as *const u8),
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
