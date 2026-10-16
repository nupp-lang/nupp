//! `nupp.snapshot`: the public layer over `persist`.
//!
//! Three things live here rather than in the graph format. Standard providers
//! whose handles live in Rust side tables (`nfiles`, `nnet`, `nhttp`,
//! `ncompression`) take part in VM checkpoints through sentinel resources:
//! files reopen at their saved offsets after a verification or strategy
//! check, and the rest refuse with the open handles counted. Nupp code
//! registers its own resources per operation (capture a descriptor, restore
//! into the placeholder, discard on abort). Restores are transactions: every
//! resource and fallible hook completes before publication, and a failure
//! discards what was staged and leaves an in-place target unchanged. Durable
//! saves run their selection and hooks in a scratch VM on another thread, so
//! they cannot mutate the running game.
use crate::{
    builtins::Outs,
    heap::*,
    interp::Interp,
    persist::{self, CodeEvent, Policies, ResourceCodec, ResourceCodecs, ShapePolicy},
    value::Value,
};
use nupp_native_files::{OpenFile, OpenMode};
use sha2::{Digest, Sha256};
use std::{
    cell::RefCell,
    collections::{HashMap, HashSet},
    path::{Path, PathBuf},
    rc::Rc,
    time::SystemTime,
};
type Result<T> = std::result::Result<T, String>;

/// Resource kinds of the standard providers' side tables. A sentinel table
/// registered under one of these stands for every handle the table holds.
pub const FILES: &str = "nupp.io.files.handles";
pub const NET: &str = "nupp.net.handles";
pub const HTTP: &str = "nupp.http.handles";
pub const COMPRESSION: &str = "nupp.compression.handles";
const SENTINEL_PREFIX: &str = "nupp.vm.snapshot:";
/// The files provider's handle record, refused by graph saves while open.
const FILE_IDENTITY: &str = "nupp.runtime.provider.nativefiles:File";
const DURABLE_FORMAT: &str = "nupp.snapshot.durable";
const DURABLE_VERSION: f64 = 1.0;

/// Kinds registered in `Interp::resources` by providers that cannot be
/// restored into another VM, and what to do about each instead.
const REFUSED: &[(&str, &str)] = &[
    ("nupp.io.file", "an io.open handle cannot be captured; open the file through nupp.io.files, whose open files restore at their offset, or close it first"),
    ("nupp.io.process.child", "a running child process cannot be captured; wait for it or kill it first"),
    ("nupp.io.process.stream", "a child process stream cannot be captured; drain and close it first"),
    ("nupp.io.process.pipe", "an io.popen pipe cannot be captured; read it to the end and close it first"),
    ("nupp.io.temporaryPath", "a temporary path the VM removes on close cannot be captured; persist or close it first"),
    ("nupp.foreign.library", "a loaded foreign library holds process addresses; load it again after restoring, through a resource that names it"),
    ("nupp.foreign.function", "a bound foreign function holds a process address; bind it again after restoring"),
    ("nupp.foreign.pointer", "a foreign pointer is a process address; keep the data in runtime storage instead"),
    ("nupp.foreign.callback", "a retained C callback holds a trampoline address; release it and retain it again after restoring"),
];

// ---------------------------------------------------------------------------
// Open native files.

/// What a checkpoint does with one open file.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Strategy {
    /// Fail the capture, naming the file.
    Refuse = 0,
    /// Reopen without truncating, at the saved offset, whatever the file holds.
    Reopen = 1,
    /// Record the size and SHA-256 at capture; refuse a restore that differs.
    Verify = 2,
}
impl Strategy {
    fn parse(name: &[u8]) -> Option<Self> {
        match name {
            b"refuse" => Some(Self::Refuse),
            b"reopen" => Some(Self::Reopen),
            b"verify" => Some(Self::Verify),
            _ => None,
        }
    }
    fn from_byte(byte: u8) -> Result<Option<Self>> {
        match byte {
            0 => Ok(Some(Self::Refuse)),
            1 => Ok(Some(Self::Reopen)),
            2 => Ok(Some(Self::Verify)),
            255 => Ok(None),
            _ => Err("snapshot: invalid file strategy".into()),
        }
    }
}

struct Opened {
    path: PathBuf,
    mode: OpenMode,
    /// The last digest, kept while the file's size and modification time hold.
    digest: RefCell<Option<(u64, Option<SystemTime>, [u8; 32])>>,
}

/// The paths of `nfiles` handles and the strategies that govern them.
/// Strategies are VM state: they travel inside every checkpoint, whether or
/// not a file they name is open.
#[derive(Default)]
pub struct FileTracking {
    files: HashMap<u64, Opened>,
    /// Strategies by canonical path, for files open now or opened later.
    rules: std::collections::BTreeMap<PathBuf, Strategy>,
    /// The strategy for writable files no rule names.
    writable: Option<Strategy>,
}
/// The path a restore in another process or directory reopens. A file not
/// yet created resolves through its parent directory.
fn canonical(path: &Path) -> PathBuf {
    std::fs::canonicalize(path)
        .ok()
        .or_else(|| {
            let parent = path.parent().filter(|p| !p.as_os_str().is_empty()).unwrap_or(Path::new("."));
            Some(std::fs::canonicalize(parent).ok()?.join(path.file_name()?))
        })
        .or_else(|| std::path::absolute(path).ok())
        .unwrap_or_else(|| path.to_path_buf())
}
impl FileTracking {
    pub(crate) fn opened(&mut self, id: u64, path: &Path, mode: OpenMode) {
        self.files.insert(id, Opened { path: canonical(path), mode, digest: RefCell::new(None) });
    }
    pub(crate) fn closed(&mut self, id: u64) {
        self.files.remove(&id);
    }
    fn effective(&self, opened: &Opened) -> Strategy {
        self.rules.get(&opened.path).copied().unwrap_or(if opened.mode == OpenMode::Read {
            Strategy::Verify
        } else {
            self.writable.unwrap_or(Strategy::Refuse)
        })
    }
    fn configured(&self) -> bool {
        !self.rules.is_empty() || self.writable.is_some()
    }
}

fn mode_byte(mode: OpenMode) -> u8 {
    match mode {
        OpenMode::Read => 0,
        OpenMode::Write => 1,
        OpenMode::Append => 2,
        OpenMode::ReadWrite => 3,
        OpenMode::ReadWriteTruncate => 4,
        OpenMode::ReadAppend => 5,
    }
}
fn mode_of(byte: u8) -> Result<OpenMode> {
    Ok(match byte {
        0 => OpenMode::Read,
        1 => OpenMode::Write,
        2 => OpenMode::Append,
        3 => OpenMode::ReadWrite,
        4 => OpenMode::ReadWriteTruncate,
        5 => OpenMode::ReadAppend,
        _ => return Err("snapshot: invalid file mode".into()),
    })
}
fn mode_name(mode: OpenMode) -> &'static str {
    ["r", "w", "a", "r+", "w+", "a+"][mode_byte(mode) as usize]
}
fn path_bytes(path: &Path) -> Vec<u8> {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        path.as_os_str().as_bytes().to_vec()
    }
    #[cfg(not(unix))]
    {
        path.to_string_lossy().into_owned().into_bytes()
    }
}
fn file_digest(path: &Path) -> std::io::Result<(u64, [u8; 32])> {
    use std::io::Read;
    let mut file = std::fs::File::open(path)?;
    let mut hash = Sha256::new();
    let mut buffer = vec![0u8; 1 << 16];
    let mut size = 0u64;
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            return Ok((size, hash.finalize().into()));
        }
        hash.update(&buffer[..count]);
        size += count as u64;
    }
}
impl Opened {
    fn digest_now(&self) -> Result<(u64, [u8; 32])> {
        let fail = |e: std::io::Error| format!("snapshot: verifying {}: {e}", self.path.display());
        let meta = std::fs::metadata(&self.path).map_err(fail)?;
        let modified = meta.modified().ok();
        if let Some((size, when, digest)) = *self.digest.borrow() {
            if size == meta.len() && when.is_some() && when == modified {
                return Ok((size, digest));
            }
        }
        let (size, digest) = file_digest(&self.path).map_err(fail)?;
        *self.digest.borrow_mut() = Some((size, modified, digest));
        Ok((size, digest))
    }
}
fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

struct Bytes<'a>(&'a [u8], usize);
impl<'a> Bytes<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8]> {
        let end = self.1.checked_add(n).filter(|&e| e <= self.0.len()).ok_or("snapshot: truncated resource descriptor")?;
        let out = &self.0[self.1..end];
        self.1 = end;
        Ok(out)
    }
    fn byte(&mut self) -> Result<u8> {
        Ok(self.take(1)?[0])
    }
    fn u32(&mut self) -> Result<usize> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().unwrap()) as usize)
    }
    fn u64(&mut self) -> Result<u64> {
        Ok(u64::from_le_bytes(self.take(8)?.try_into().unwrap()))
    }
    fn bytes(&mut self) -> Result<&'a [u8]> {
        let n = self.u32()?;
        self.take(n)
    }
}

/// Saves every open `nfiles` handle with its path, mode, offset and strategy;
/// restore reopens each without truncation under the same handle number.
struct FilesCodec;
impl ResourceCodec for FilesCodec {
    fn save(&mut self, vm: &Interp, _: Value) -> Result<Vec<u8>> {
        let files = &vm.nfiles;
        let mut out = vec![1, files.snapshot.writable.map_or(255, |s| s as u8)];
        out.extend(files.next.to_le_bytes());
        out.extend((files.snapshot.rules.len() as u32).to_le_bytes());
        for (path, strategy) in &files.snapshot.rules {
            let path = path_bytes(path);
            out.extend((path.len() as u32).to_le_bytes());
            out.extend(path);
            out.push(*strategy as u8);
        }
        let mut ids: Vec<u64> = files.open.keys().copied().collect();
        ids.sort_unstable();
        out.extend((ids.len() as u32).to_le_bytes());
        for id in ids {
            let opened = files.snapshot.files.get(&id).ok_or_else(|| format!("snapshot: open file handle {id} has no recorded path"))?;
            let strategy = files.snapshot.effective(opened);
            if strategy == Strategy::Refuse {
                return Err(format!(
                    "snapshot: {} is open for writing (mode \"{}\"), and restoring it could repeat or lose writes; give its path a strategy with snapshot.fileStrategy(path, \"reopen\" or \"verify\"), or close it before capturing",
                    opened.path.display(),
                    mode_name(opened.mode)
                ));
            }
            out.extend(id.to_le_bytes());
            out.push(mode_byte(opened.mode));
            out.push(strategy as u8);
            let path = path_bytes(&opened.path);
            out.extend((path.len() as u32).to_le_bytes());
            out.extend(path);
            out.extend(files.open[&id].position().to_le_bytes());
            if strategy == Strategy::Verify {
                let (size, digest) = opened.digest_now()?;
                out.extend(size.to_le_bytes());
                out.extend(digest);
            }
        }
        Ok(out)
    }
    fn restore(&mut self, vm: &mut Interp, _: Value, data: &[u8]) -> Result<()> {
        let mut r = Bytes(data, 0);
        if r.byte()? != 1 {
            return Err("snapshot: unsupported open-file descriptor version".into());
        }
        let writable = Strategy::from_byte(r.byte()?)?;
        let next = r.u64()?;
        let mut rules = std::collections::BTreeMap::new();
        for _ in 0..r.u32()? {
            let path = nupp_native_files::path_from_bytes(r.bytes()?).map_err(|e| e.to_string())?;
            rules.insert(path, Strategy::from_byte(r.byte()?)?.ok_or("snapshot: invalid file strategy")?);
        }
        let count = r.u32()?;
        // Reopen everything before publishing any handle: a failure part way
        // drops the files reopened so far, and the candidate VM never sees them.
        let mut reopened: Vec<(u64, OpenFile, Opened)> = Vec::new();
        for _ in 0..count {
            let id = r.u64()?;
            let mode = mode_of(r.byte()?)?;
            let strategy = Strategy::from_byte(r.byte()?)?.ok_or("snapshot: invalid file strategy")?;
            let path = nupp_native_files::path_from_bytes(r.bytes()?).map_err(|e| e.to_string())?;
            let position = r.u64()?;
            if id >= next || vm.nfiles.open.contains_key(&id) || reopened.iter().any(|(i, ..)| *i == id) {
                return Err("snapshot: invalid open-file handle number".into());
            }
            let shown = path.display();
            if strategy == Strategy::Verify {
                let size = r.u64()?;
                let digest: [u8; 32] = r.take(32)?.try_into().unwrap();
                let (found, actual) = file_digest(&path).map_err(|e| format!("snapshot: restoring {shown}: {e}"))?;
                if found != size || actual != digest {
                    return Err(format!(
                        "snapshot: restoring {shown}: its contents changed since the capture (captured {size} bytes, SHA-256 {}; found {found} bytes, SHA-256 {})",
                        hex(&digest[..8]),
                        hex(&actual[..8])
                    ));
                }
            } else if strategy == Strategy::Refuse {
                return Err("snapshot: invalid file strategy".into());
            }
            let file = OpenFile::reopen(&path, mode, position).map_err(|e| format!("snapshot: restoring {shown}: {e}"))?;
            reopened.push((id, file, Opened { path, mode, digest: RefCell::new(None) }));
        }
        if r.1 != data.len() {
            return Err("snapshot: trailing open-file descriptor data".into());
        }
        let files = &mut vm.nfiles;
        files.next = files.next.max(next);
        files.snapshot.writable = writable;
        files.snapshot.rules = rules;
        for (id, file, opened) in reopened {
            files.open.insert(id, file);
            files.snapshot.files.insert(id, opened);
        }
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Providers that refuse.

fn describe(counts: &[(&str, usize)]) -> String {
    let parts: Vec<String> = counts
        .iter()
        .filter(|(_, n)| *n != 0)
        .map(|(what, n)| if *n == 1 { format!("1 {what}") } else { format!("{n} {what}s") })
        .collect();
    match parts.len() {
        0 => "no handles".into(),
        1 => parts[0].clone(),
        n => format!("{} and {}", parts[..n - 1].join(", "), parts[n - 1]),
    }
}
#[cfg(feature = "net")]
fn net_counts(vm: &Interp) -> Vec<(&'static str, usize)> {
    vm.nnet.open_counts().to_vec()
}
#[cfg(not(feature = "net"))]
fn net_counts(_: &Interp) -> Vec<(&'static str, usize)> {
    Vec::new()
}
#[cfg(feature = "http")]
fn http_counts(vm: &Interp) -> Vec<(&'static str, usize)> {
    vm.nhttp.open_counts().to_vec()
}
#[cfg(not(feature = "http"))]
fn http_counts(_: &Interp) -> Vec<(&'static str, usize)> {
    Vec::new()
}
#[cfg(feature = "compression")]
fn compression_counts(vm: &Interp) -> Vec<(&'static str, usize)> {
    vm.ncompression.open_counts().to_vec()
}
#[cfg(not(feature = "compression"))]
fn compression_counts(_: &Interp) -> Vec<(&'static str, usize)> {
    Vec::new()
}
fn open(counts: &[(&str, usize)]) -> bool {
    counts.iter().any(|(_, n)| *n != 0)
}

/// Fails a capture with an actionable reason. A caller that supplies its own
/// codec for the kind replaces this one: that is an explicit strategy.
struct Refuse {
    kind: &'static str,
    reason: Reason,
}
enum Reason {
    Fixed(&'static str),
    Counted(fn(&Interp) -> String),
}
impl ResourceCodec for Refuse {
    fn save(&mut self, vm: &Interp, _: Value) -> Result<Vec<u8>> {
        let reason = match self.reason {
            Reason::Fixed(text) => text.to_string(),
            Reason::Counted(f) => f(vm),
        };
        Err(format!("snapshot cannot capture {}: {reason}", self.kind))
    }
    fn restore(&mut self, _: &mut Interp, _: Value, _: &[u8]) -> Result<()> {
        Err(format!("snapshot: {} has no restoration", self.kind))
    }
}
fn net_reason(vm: &Interp) -> String {
    format!(
        "{} open; sockets cannot be restored into another VM. Close them before capturing, or supply a \"{NET}\" resource strategy",
        describe(&net_counts(vm))
    )
}
fn http_reason(vm: &Interp) -> String {
    format!("{} open; finish or release them before capturing", describe(&http_counts(vm)))
}
fn compression_reason(vm: &Interp) -> String {
    format!(
        "{} open; their codec state is native. Finish or release them before capturing",
        describe(&compression_counts(vm))
    )
}

/// The refusals every capture and restore carries. The files codec belongs
/// only to whole-VM checkpoints, where its sentinel is reachable.
fn refusals(codecs: &mut ResourceCodecs) {
    let counted: [(&'static str, fn(&Interp) -> String); 3] = [(NET, net_reason), (HTTP, http_reason), (COMPRESSION, compression_reason)];
    for (kind, reason) in counted {
        codecs.entry(kind.into()).or_insert_with(|| Box::new(Refuse { kind, reason: Reason::Counted(reason) }));
    }
    for &(kind, reason) in REFUSED {
        codecs.entry(kind.into()).or_insert_with(|| Box::new(Refuse { kind, reason: Reason::Fixed(reason) }));
    }
}

/// Standard-provider codecs for whole-VM checkpoints, installed unless the
/// caller supplied a codec of the same kind.
pub(crate) fn install_codecs(codecs: &mut ResourceCodecs) {
    codecs.entry(FILES.into()).or_insert_with(|| Box::new(FilesCodec));
    refusals(codecs);
}

/// Registers or retires each provider's sentinel to match its side table, so
/// a VM that never opened one checkpoints exactly as before.
pub(crate) fn before_checkpoint(vm: &mut Interp, codecs: &mut ResourceCodecs) {
    let files = !vm.nfiles.open.is_empty() || vm.nfiles.snapshot.configured();
    let net = open(&net_counts(vm));
    let http = open(&http_counts(vm));
    let compression = open(&compression_counts(vm));
    for (kind, live) in [(FILES, files), (NET, net), (HTTP, http), (COMPRESSION, compression)] {
        let key = format!("{SENTINEL_PREFIX}{kind}");
        let sentinel = match vm.loaded.get(&key) {
            Some(&t) => t,
            None if !live => continue,
            None => {
                let t = vm.new_table();
                vm.registered.push(t);
                vm.loaded.insert(key, t);
                t
            }
        };
        if live {
            vm.resources.insert(sentinel, kind.into());
        } else {
            vm.resources.remove(&sentinel);
        }
    }
    install_codecs(codecs);
}

// ---------------------------------------------------------------------------
// Calling Nupp callbacks.

/// Calls a callback outside any parking region and returns its results,
/// rooted in the caller's scope. A failure leaves no scratch task behind.
fn call(vm: &mut Interp, f: Value, args: &[Value], phase: &str) -> Result<Vec<Value>> {
    let scope = vm.open_scope();
    vm.handles.push(f);
    vm.handles.extend_from_slice(args);
    let tasks = vm.tasks.len();
    let (extra, extra_n, nres) = (vm.extra, vm.extra_n, vm.last_nres);
    vm.handles.extend(extra);
    vm.persistence_hook_depth += 1;
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| vm.call_value(f, args)));
    vm.persistence_hook_depth -= 1;
    let result = result.map_err(|payload| {
        let value = vm.error_value(payload);
        let message = if vm.is_stringish(value) {
            String::from_utf8_lossy(vm.bytes_of(value)).into_owned()
        } else {
            format!("a {} value", crate::builtins::type_name(vm, value))
        };
        format!("snapshot {phase}: {message}")
    });
    vm.tasks.truncate(tasks);
    vm.extra = extra;
    vm.extra_n = extra_n;
    vm.last_nres = nres;
    vm.close_scope(scope);
    if let Ok(values) = &result {
        vm.handles.extend_from_slice(values);
    }
    result
}
fn callable(vm: &Interp, v: Value) -> bool {
    v.as_func().is_some_and(|f| (f as usize) < vm.funcs.len())
        || v.as_builtin().is_some()
        || v.as_obj().is_some_and(|p| vm.heap.is_live_slot(p) && unsafe { p.as_ref().kind == KIND_CLOSURE })
}
fn text(vm: &Interp, v: Value, what: &str) -> Result<String> {
    if !vm.is_stringish(v) {
        return Err(format!("snapshot: {what} must be a string"));
    }
    String::from_utf8(vm.bytes_of(v).to_vec()).map_err(|_| format!("snapshot: {what} must be UTF-8"))
}
fn get(vm: &mut Interp, t: Value, name: &str) -> Value {
    crate::task_api::field(vm, t, name)
}
fn is_table(vm: &Interp, v: Value) -> bool {
    matches!(vm.kind_of(v), Some(KIND_TABLE | KIND_RECORD)) && v.as_obj().is_some_and(|p| vm.heap.is_live_slot(p))
}

// ---------------------------------------------------------------------------
// Nupp-defined resources.

/// One registration from a `resources` list: a stable kind and its callbacks.
#[derive(Clone)]
struct NuppResource {
    kind: String,
    capture: Value,
    restore: Value,
    discard: Value,
}

/// Reads a `resources` list. Every callback is reachable from the argument,
/// which the caller keeps rooted for the operation.
fn resources_from(vm: &mut Interp, list: Value) -> Result<Vec<NuppResource>> {
    let mut out: Vec<NuppResource> = Vec::new();
    if list == Value::NIL {
        return Ok(out);
    }
    if !is_table(vm, list) {
        return Err("snapshot: resources must be a list of resource descriptions".into());
    }
    for index in 1..=vm.array_len(list) {
        let entry = vm.get_index(list, Value::num(index as f64));
        if !is_table(vm, entry) {
            return Err("snapshot: a resource description must be a table".into());
        }
        let kind = get(vm, entry, "kind");
        let kind = text(vm, kind, "a resource kind")?;
        if kind.is_empty() || kind.starts_with("nupp.") {
            return Err(format!("snapshot: resource kind \"{kind}\" is reserved; name it after the application"));
        }
        let capture = get(vm, entry, "capture");
        let restore = get(vm, entry, "restore");
        let discard = get(vm, entry, "discard");
        if !callable(vm, capture) || !callable(vm, restore) || (discard != Value::NIL && !callable(vm, discard)) {
            return Err(format!("snapshot: resource {kind} needs capture and restore functions, and discard must be a function"));
        }
        if out.iter().any(|r| r.kind == kind) {
            return Err(format!("snapshot: duplicate resource kind {kind}"));
        }
        out.push(NuppResource { kind, capture, restore, discard });
    }
    Ok(out)
}

/// Records which resources a save reaches, without running anything.
struct Recorder(Rc<RefCell<Vec<Value>>>);
impl ResourceCodec for Recorder {
    fn save(&mut self, _: &Interp, object: Value) -> Result<Vec<u8>> {
        self.0.borrow_mut().push(object);
        Ok(Vec::new())
    }
    fn restore(&mut self, _: &mut Interp, _: Value, _: &[u8]) -> Result<()> {
        Err("snapshot: a recording codec cannot restore".into())
    }
}
/// Answers the descriptors `capture` produced before the save began.
struct Captured {
    kind: String,
    descriptors: Rc<HashMap<u64, Vec<u8>>>,
}
impl ResourceCodec for Captured {
    fn save(&mut self, _: &Interp, object: Value) -> Result<Vec<u8>> {
        self.descriptors.get(&object.0).cloned().ok_or_else(|| {
            format!("snapshot: a {} resource became reachable during a beforeSave hook; capture runs before hooks, so reach it from the saved value", self.kind)
        })
    }
    fn restore(&mut self, _: &mut Interp, _: Value, _: &[u8]) -> Result<()> {
        Err("snapshot: a capture codec cannot restore".into())
    }
}
/// Calls `restore(placeholder, descriptor)` and stages the placeholder, so
/// an abort can discard every resource restored so far.
struct Restorer {
    resource: NuppResource,
    staged: Rc<RefCell<Vec<(Value, usize)>>>,
}
impl ResourceCodec for Restorer {
    fn save(&mut self, _: &Interp, _: Value) -> Result<Vec<u8>> {
        Err("snapshot: a restore codec cannot save".into())
    }
    fn restore(&mut self, vm: &mut Interp, object: Value, data: &[u8]) -> Result<()> {
        // Root the placeholder past the graph load's own scope before calling out.
        let root = vm.register(object);
        self.staged.borrow_mut().push((object, root));
        let scope = vm.open_scope();
        vm.handles.push(object);
        let descriptor = vm.new_string_bytes(data);
        vm.handles.push(descriptor);
        let result = call(vm, self.resource.restore, &[object, descriptor], &format!("restore of {}", self.resource.kind));
        vm.close_scope(scope);
        result.map(drop)
    }
}

/// Discards staged resources newest first. Every discard runs; the failures
/// are reported together.
fn discard(vm: &mut Interp, resources: &[NuppResource], staged: &[(Value, usize)]) -> Option<String> {
    let mut failures = Vec::new();
    for &(object, root) in staged.iter().rev() {
        // Only application kinds are staged; a runtime resource stays put.
        let kind = vm.resources.get(&object).filter(|k| !k.starts_with("nupp.")).cloned();
        if kind.is_some() {
            vm.resources.remove(&object);
        }
        let hook = kind.and_then(|k| resources.iter().find(|r| r.kind == k)).map(|r| r.discard).unwrap_or(Value::NIL);
        if hook != Value::NIL {
            let scope = vm.open_scope();
            if let Err(e) = call(vm, hook, &[object], "discard") {
                failures.push(e);
            }
            vm.close_scope(scope);
        }
        vm.release(root);
    }
    (!failures.is_empty()).then(|| failures.join("; "))
}

// ---------------------------------------------------------------------------
// Graph saves and restores.

/// Refuses a files-provider handle record that is still open: its handle
/// number names a native file of this VM, and a copy would alias it.
fn refuse_open_file(vm: &mut Interp, value: Value) -> Result<()> {
    let Some(&id) = vm.heap.shape_identities.get(FILE_IDENTITY) else { return Ok(()) };
    let Some(p) = value.as_obj() else { return Ok(()) };
    if unsafe { p.as_ref().shape() } != id || get(vm, value, "_closed") == Value::TRUE {
        return Ok(());
    }
    let handle = get(vm, value, "_handle");
    let path = (handle.is_num())
        .then(|| vm.nfiles.snapshot.files.get(&(handle.as_num() as u64)))
        .flatten()
        .map(|o| o.path.display().to_string())
        .unwrap_or_else(|| "a file".into());
    Err(format!(
        "snapshot cannot save an open file ({path}) inside a value: its handle belongs to this VM. Close it first, or save its path and reopen it after loading"
    ))
}
fn guard(vm: &Interp, policies: &mut Policies) {
    if let Some(&id) = vm.heap.shape_identities.get(FILE_IDENTITY) {
        let name = vm.heap.shapes[id as usize].name.clone();
        let policy = policies.shapes.entry(name).or_default();
        if policy.before_save.is_none() {
            policy.before_save = Some(refuse_open_file);
        }
    }
}

/// Saves `roots` with Nupp resources captured first. A first pass with no
/// hooks finds the reachable resources; their descriptors are captured; the
/// real save then runs the policies' hooks once.
fn save_with(vm: &mut Interp, roots: &[Value], policies: &Policies, resources: &[NuppResource]) -> Result<Vec<u8>> {
    let scope = vm.open_scope();
    vm.handles.extend_from_slice(roots);
    let result = (|| {
        let kinds: HashSet<&str> = resources.iter().map(|r| r.kind.as_str()).collect();
        let mut descriptors = HashMap::new();
        if vm.resources.values().any(|k| kinds.contains(k.as_str())) {
            let found = Rc::new(RefCell::new(Vec::new()));
            let mut codecs = ResourceCodecs::new();
            for r in resources {
                codecs.insert(r.kind.clone(), Box::new(Recorder(found.clone())));
            }
            refusals(&mut codecs);
            // Transient fields still exclude; hooks wait for the real save.
            let mut plain = Policies::default();
            for (name, p) in &policies.shapes {
                plain.shapes.insert(name.clone(), ShapePolicy { name: p.name.clone(), transient: p.transient.clone(), ..Default::default() });
            }
            persist::save_graph_with(vm, roots, &plain, Some(&mut codecs), false)?;
            let found = found.borrow().clone();
            vm.handles.extend_from_slice(&found);
            for object in found {
                if descriptors.contains_key(&object.0) {
                    continue;
                }
                let kind = vm.resources[&object].clone();
                let resource = resources.iter().find(|r| r.kind == kind).unwrap();
                let out = call(vm, resource.capture, &[object], &format!("capture of {kind}"))?;
                let descriptor = out.first().copied().unwrap_or(Value::NIL);
                if !vm.is_stringish(descriptor) {
                    return Err(format!("snapshot: capture of {kind} must return a string descriptor"));
                }
                descriptors.insert(object.0, vm.bytes_of(descriptor).to_vec());
            }
        }
        let descriptors = Rc::new(descriptors);
        let mut codecs = ResourceCodecs::new();
        for r in resources {
            codecs.insert(r.kind.clone(), Box::new(Captured { kind: r.kind.clone(), descriptors: descriptors.clone() }));
        }
        refusals(&mut codecs);
        persist::save_graph_with(vm, roots, policies, Some(&mut codecs), false)
    })();
    vm.close_scope(scope);
    result
}

/// The saved state of an in-place target, so a failed restore can put it back.
struct TargetState {
    slots: Vec<Value>,
    array: Vec<Value>,
    extra: Option<(Vec<(Value, Value)>, Value)>,
    meta_flag: u8,
}
fn target_state(vm: &mut Interp, target: Value) -> TargetState {
    let h = unsafe { target.as_obj().unwrap().as_ref() };
    let state = TargetState {
        slots: h.slots().to_vec(),
        array: h.record_array_ref().clone(),
        extra: h.record_extra_ref().as_ref().map(|e| (e.fields.iter().map(|(k, v)| (*k, *v)).collect(), e.meta)),
        meta_flag: h.flags & F_METATABLE,
    };
    vm.handles.extend_from_slice(&state.slots);
    vm.handles.extend_from_slice(&state.array);
    if let Some((pairs, meta)) = &state.extra {
        vm.handles.extend(pairs.iter().flat_map(|(k, v)| [*k, *v]));
        vm.handles.push(*meta);
    }
    state
}
fn restore_target(vm: &mut Interp, target: Value, state: TargetState) {
    let p = target.as_obj().unwrap();
    vm.heap.schema_write(p);
    let h = unsafe { &mut *p.as_ptr() };
    let before = h.external_bytes();
    h.slots_mut().copy_from_slice(&state.slots);
    *h.record_array() = state.array;
    h.flags = (h.flags & !F_METATABLE) | state.meta_flag;
    *h.record_extra() = state.extra.map(|(pairs, meta)| {
        let mut fields = ValueTable::new();
        for (k, v) in pairs {
            fields.insert(k, v);
        }
        Box::new(RecordExtra { fields, meta })
    });
    vm.heap.account_resize(before, h.external_bytes());
    let mut children = Vec::new();
    Heap::each_child(h, &mut |v| children.push(v));
    for child in children {
        vm.heap.barrier(p, child);
    }
}

/// Restores a graph as an unpublished candidate: resources restored, hooks
/// run, types validated. Nothing outside the candidate changes on failure.
/// With a target, the root replaces it in place, or it is left as it was.
fn prepare(
    vm: &mut Interp,
    data: &[u8],
    expected: Option<SlotTy>,
    policies: &Policies,
    resources: &[NuppResource],
    target: Option<Value>,
) -> Result<(Vec<Value>, Vec<(Value, usize)>)> {
    let staged = Rc::new(RefCell::new(Vec::new()));
    let mut codecs = ResourceCodecs::new();
    for r in resources {
        codecs.insert(r.kind.clone(), Box::new(Restorer { resource: r.clone(), staged: staged.clone() }));
    }
    let scope = vm.open_scope();
    let saved = target.map(|t| {
        vm.handles.push(t);
        target_state(vm, t)
    });
    let result = match target {
        Some(t) => persist::load_into_with(vm, data, t, policies, Some(&mut codecs)).map(|v| vec![v]),
        None => persist::load_graph_with(vm, data, policies, expected, Some(&mut codecs), false, None),
    };
    let staged = staged.borrow().clone();
    let result = match result {
        Ok(roots) => Ok(roots),
        Err(error) => {
            if let (Some(t), Some(state)) = (target, saved) {
                restore_target(vm, t, state);
            }
            Err(match discard(vm, resources, &staged) {
                Some(more) => format!("{error} (discarding staged resources also failed: {more})"),
                None => error,
            })
        }
    };
    vm.close_scope(scope);
    if let Ok(roots) = &result {
        vm.handles.extend_from_slice(roots);
    }
    result.map(|roots| (roots, staged))
}

// ---------------------------------------------------------------------------
// Durable saves in a scratch VM.

/// Carries resource descriptors through the scratch VM without opening
/// anything: restore keeps the bytes, save hands them back.
struct Passthrough(Rc<RefCell<HashMap<u64, Vec<u8>>>>);
impl ResourceCodec for Passthrough {
    fn save(&mut self, _: &Interp, object: Value) -> Result<Vec<u8>> {
        self.0.borrow().get(&object.0).cloned().ok_or_else(|| "snapshot: a durable save cannot create a resource; return resources from the saved value".into())
    }
    fn restore(&mut self, _: &mut Interp, object: Value, data: &[u8]) -> Result<()> {
        self.0.borrow_mut().insert(object.0, data.to_vec());
        Ok(())
    }
}

fn refuse_callables(bytes: &[u8], what: &str) -> Result<()> {
    // Frame header (21 bytes), then the graph's "contains functions" byte.
    if bytes.get(8) == Some(&0) && bytes.get(21).is_some_and(|&b| b != 0) {
        return Err(format!(
            "snapshot: a durable save's {what} contains functions, which bind it to this exact build; save data and rebuild behavior after loading"
        ));
    }
    Ok(())
}

/// Builds a VM from the live VM's code recipe, without running any module.
fn scratch_vm(recipe: Vec<CodeEvent>) -> Result<Interp> {
    let mut vm = Interp::new();
    for event in recipe {
        match event {
            CodeEvent::Image(s) => {
                crate::image::load(&mut vm, &s)?;
            }
            CodeEvent::Globals => vm.install_globals(),
            CodeEvent::Patch { text, retired, added } => {
                crate::hotpatch::replay(&mut vm, &text, &retired)?;
                vm.code_events.push(CodeEvent::Patch { text, retired, added });
            }
        }
    }
    vm.entries = vec![0; vm.funcs.len()];
    vm.prepare_threaded();
    vm.calltab = vm
        .funcs
        .iter()
        .map(|f| f.nparams as u64 | (((f.sig.iter().all(|&c| c == b'v') && f.ret != b'f' && !f.vararg) as u64) << 8))
        .collect();
    vm.shape_probe = vm.heap.shapes.iter().map(|s| (s.table.as_ptr() as u64, s.mask)).collect();
    vm.runtime_consts = vm.funcs.iter().map(|f| f.consts.as_ptr() as u64).collect();
    Ok(vm)
}

/// Selection, metadata, sections and beforeSave hooks over a private copy.
fn durable_in_scratch(recipe: Vec<CodeEvent>, graph: Vec<u8>, kinds: Vec<String>) -> Result<Vec<u8>> {
    let mut vm = scratch_vm(recipe)?;
    let carried = Rc::new(RefCell::new(HashMap::new()));
    let mut codecs = ResourceCodecs::new();
    for kind in kinds {
        codecs.insert(kind, Box::new(Passthrough(carried.clone())));
    }
    let roots = persist::load_graph_with(&mut vm, &graph, &Policies::default(), None, Some(&mut codecs), false, None)?;
    vm.handles.extend_from_slice(&roots);
    let (root, options) = (roots[0], roots[1]);
    let policies_value = get(&mut vm, options, "policies");
    let mut policies = persist::policies_from_value(&mut vm, policies_value)?;
    guard(&vm, &mut policies);
    let select = get(&mut vm, options, "select");
    let selected = if select == Value::NIL { root } else { call(&mut vm, select, &[root], "select")?.first().copied().unwrap_or(Value::NIL) };
    vm.handles.push(selected);
    let metadata_hook = get(&mut vm, options, "metadata");
    let metadata = if metadata_hook == Value::NIL { Value::NIL } else { call(&mut vm, metadata_hook, &[selected], "metadata")?.first().copied().unwrap_or(Value::NIL) };
    vm.handles.push(metadata);
    let sections_hook = get(&mut vm, options, "sections");
    let sections = if sections_hook == Value::NIL { Value::NIL } else { call(&mut vm, sections_hook, &[selected], "sections")?.first().copied().unwrap_or(Value::NIL) };
    vm.handles.push(sections);
    let envelope = vm.new_table();
    vm.handles.push(envelope);
    let saved_sections = vm.new_table();
    vm.handles.push(saved_sections);
    if sections != Value::NIL {
        if !is_table(&vm, sections) {
            return Err("snapshot: sections must return a table of named values".into());
        }
        let mut names: Vec<(String, Value)> = Vec::new();
        for key in vm.table_keys(sections) {
            names.push((text(&vm, key, "a section name")?, key));
        }
        names.sort_by(|a, b| a.0.cmp(&b.0));
        for (name, key) in names {
            let value = vm.get_index(sections, key);
            let bytes = persist::save_graph_with(&mut vm, &[value], &policies, Some(&mut codecs), false)?;
            refuse_callables(&bytes, &format!("section {name}"))?;
            let saved = vm.new_string_bytes(&bytes);
            vm.handles.push(saved);
            vm.set_index(saved_sections, key, saved);
        }
    }
    let main = persist::save_graph_with(&mut vm, &[selected], &policies, Some(&mut codecs), false)?;
    refuse_callables(&main, "value")?;
    let main = vm.new_string_bytes(&main);
    vm.handles.push(main);
    let format = vm.intern(DURABLE_FORMAT);
    vm.handles.push(format);
    let application = get(&mut vm, options, "application");
    let version = get(&mut vm, options, "version");
    for (name, value) in [
        ("format", format),
        ("formatVersion", Value::num(DURABLE_VERSION)),
        ("application", application),
        ("version", version),
        ("metadata", metadata),
        ("root", main),
        ("sections", saved_sections),
    ] {
        crate::task_api::put(&mut vm, envelope, name, value);
    }
    persist::save_data(&mut vm, envelope).map_err(|e| format!("snapshot: durable metadata must be plain data: {e}"))
}

fn durable(vm: &mut Interp, root: Value, options: Value) -> Result<Vec<u8>> {
    if !is_table(vm, options) {
        return Err("snapshot: durable options must be a table".into());
    }
    let application = get(vm, options, "application");
    let application = text(vm, application, "the application name")?;
    if application.is_empty() {
        return Err("snapshot: the application name must not be empty".into());
    }
    let version = get(vm, options, "version");
    if !version.is_num() || version.as_num().fract() != 0.0 || version.as_num() < 0.0 {
        return Err("snapshot: the version must be a whole number".into());
    }
    for hook in ["select", "metadata", "sections"] {
        let f = get(vm, options, hook);
        if f != Value::NIL && !callable(vm, f) {
            return Err(format!("snapshot: {hook} must be a function"));
        }
    }
    // Validate the policies against the live program before copying anything.
    let policies_value = get(vm, options, "policies");
    persist::policies_from_value(vm, policies_value)?;
    let resources_value = get(vm, options, "resources");
    let resources = resources_from(vm, resources_value)?;
    // A complete copy: hooks and transient fields apply in the scratch VM.
    let graph = save_with(vm, &[root, options], &Policies::default(), &resources)?;
    let recipe = vm.code_events.clone();
    let kinds: Vec<String> = resources.iter().map(|r| r.kind.clone()).collect();
    std::thread::Builder::new()
        .name("nupp-snapshot".into())
        .stack_size(16 << 20)
        .spawn(move || {
            std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| durable_in_scratch(recipe, graph, kinds)))
                .unwrap_or_else(|_| Err("snapshot: the durable save's scratch VM failed".into()))
        })
        .map_err(|e| e.to_string())?
        .join()
        .unwrap_or_else(|_| Err("snapshot: the durable save's scratch VM failed".into()))
}

// ---------------------------------------------------------------------------
// The primitive table `nupp.snapshot` is written over.

pub(crate) fn install(vm: &mut Interp) {
    let module = vm.new_table();
    vm.registered.push(module);
    for (name, builtin) in [
        ("save", "snapshot.save"),
        ("prepare", "snapshot.prepare"),
        ("loadInto", "snapshot.loadInto"),
        ("track", "snapshot.track"),
        ("untrack", "snapshot.untrack"),
        ("fileStrategy", "snapshot.fileStrategy"),
        ("durable", "snapshot.durable"),
        ("discard", "snapshot.discard"),
        ("saveData", "vm.saveData"),
        ("loadData", "vm.loadData"),
    ] {
        crate::task_api::put(vm, module, name, Value::builtin(crate::builtins::id_of(builtin).unwrap()));
    }
    vm.loaded.insert("nupp.vm.snapshot".into(), module);
}

fn arg(args: &[Value], i: usize) -> Value {
    args.get(i).copied().unwrap_or(Value::NIL)
}

pub(crate) fn call_builtin(vm: &mut Interp, name: &str, args: &[Value]) -> Outs {
    let result: Result<Outs> = (|| match name {
        "snapshot.save" => {
            let mut policies = persist::policies_from_value(vm, arg(args, 1))?;
            guard(vm, &mut policies);
            let resources = resources_from(vm, arg(args, 2))?;
            let bytes = save_with(vm, &[arg(args, 0)], &policies, &resources)?;
            Ok([vm.new_string_bytes(&bytes)].into_iter().collect())
        }
        "snapshot.prepare" | "snapshot.loadInto" => {
            if !vm.is_stringish(arg(args, 0)) {
                return Err("snapshot: a snapshot must be a string".into());
            }
            let data = vm.bytes_of(arg(args, 0)).to_vec();
            let into = name == "snapshot.loadInto";
            let target = into.then(|| arg(args, 1));
            if let Some(t) = target {
                if vm.kind_of(t) != Some(KIND_RECORD) || !t.as_obj().is_some_and(|p| vm.heap.is_live_slot(p)) {
                    return Err("snapshot: loadInto needs a record target".into());
                }
            }
            let expected = if !into && arg(args, 1) != Value::NIL {
                let shape = text(vm, arg(args, 1), "the expected shape")?;
                let id = vm.heap.shapes.iter().position(|s| s.name == shape).ok_or_else(|| format!("snapshot: unknown shape {shape}"))?;
                Some(SlotTy::Record(id as u32))
            } else {
                None
            };
            let policies = persist::policies_from_value(vm, arg(args, 2))?;
            let resources = resources_from(vm, arg(args, 3))?;
            let (roots, staged) = prepare(vm, &data, expected, &policies, &resources, target)?;
            if roots.len() != 1 {
                return Err("snapshot: a snapshot must have exactly one root".into());
            }
            let list = vm.new_table();
            vm.handles.push(list);
            for (i, &(object, root)) in staged.iter().enumerate() {
                vm.set_index(list, Value::num(i as f64 + 1.0), object);
                vm.release(root);
            }
            Ok([roots[0], list].into_iter().collect())
        }
        "snapshot.track" => {
            let object = arg(args, 0);
            let kind = text(vm, arg(args, 1), "a resource kind")?;
            if kind.is_empty() || kind.starts_with("nupp.") {
                return Err(format!("snapshot: resource kind \"{kind}\" is reserved; name it after the application"));
            }
            if vm.kind_of(object) != Some(KIND_TABLE) || !object.as_obj().is_some_and(|p| vm.heap.is_live_slot(p)) {
                return Err("snapshot: a tracked resource must be a table".into());
            }
            if crate::storage::is_native(object) || vm.heap.channels.contains_key(&object) {
                return Err("snapshot: this table is already a runtime resource".into());
            }
            match vm.resources.get(&object) {
                Some(existing) if *existing != kind => {
                    Err(format!("snapshot: the table is already tracked as {existing}"))
                }
                _ => {
                    vm.resources.insert(object, kind);
                    Ok(Outs::new())
                }
            }
        }
        "snapshot.untrack" => {
            let object = arg(args, 0);
            if let Some(kind) = vm.resources.get(&object) {
                if kind.starts_with("nupp.") {
                    return Err(format!("snapshot: {kind} is a runtime resource; close it instead"));
                }
                vm.resources.remove(&object);
            }
            Ok(Outs::new())
        }
        "snapshot.fileStrategy" => {
            let strategy = if arg(args, 1) == Value::NIL {
                None
            } else {
                let name = arg(args, 1);
                Some(
                    vm.is_stringish(name)
                        .then(|| Strategy::parse(vm.bytes_of(name)))
                        .flatten()
                        .ok_or("snapshot: a file strategy is \"refuse\", \"reopen\" or \"verify\"")?,
                )
            };
            let path = arg(args, 0);
            if path == Value::NIL {
                vm.nfiles.snapshot.writable = strategy;
                return Ok(Outs::new());
            }
            if !vm.is_stringish(path) || vm.bytes_of(path).is_empty() {
                return Err("snapshot: a file strategy names a path".into());
            }
            let path = canonical(&nupp_native_files::path_from_bytes(vm.bytes_of(path)).map_err(|e| e.to_string())?);
            match strategy {
                Some(strategy) => vm.nfiles.snapshot.rules.insert(path, strategy),
                None => vm.nfiles.snapshot.rules.remove(&path),
            };
            Ok(Outs::new())
        }
        "snapshot.discard" => {
            let list = arg(args, 0);
            if !is_table(vm, list) {
                return Err("snapshot: staged resources must be a list".into());
            }
            let resources = resources_from(vm, arg(args, 1))?;
            let staged: Vec<(Value, usize)> = (1..=vm.array_len(list))
                .map(|i| {
                    let object = vm.get_index(list, Value::num(i as f64));
                    (object, vm.register(object))
                })
                .collect();
            match discard(vm, &resources, &staged) {
                Some(failures) => Err(failures),
                None => Ok(Outs::new()),
            }
        }
        "snapshot.durable" => {
            let bytes = durable(vm, arg(args, 0), arg(args, 1))?;
            Ok([vm.new_string_bytes(&bytes)].into_iter().collect())
        }
        _ => Err(format!("unknown snapshot primitive {name}")),
    })();
    result.unwrap_or_else(|e| vm.err(&e))
}
