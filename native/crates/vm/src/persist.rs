//! Versioned binary graphs and VM checkpoints. Addresses and native code never
//! enter the format. Graph edges are object IDs; storage and bytes are spans.
use crate::{
    heap::*,
    interp::{HDR, Interp, State, Task},
    value::Value,
};
use sha2::{Digest, Sha256};
use std::{
    cell::Cell,
    collections::{HashMap, HashSet},
    rc::Rc,
};

/// The caller word's flag for a protected record that carries xpcall's handler.
const XPCALL_RECORD: usize = 1 << 31;

pub type Result<T> = std::result::Result<T, String>;
const MAGIC: &[u8; 8] = b"NUPPSAV1";
// Plain compiler data uses a sparse schema catalog with original identity hints.
// Graph/checkpoint kinds 0, 1 and 2 retain their existing representations.
const PLAIN_GRAPH: u8 = 3;
// Preserve the original record encoding for graphs without metatables.
const RECORD_WITH_METATABLE: u8 = 11;
const ALIGNED_BYTES: u8 = 13;
const NATIVE_TABLE: u8 = 14;
const OWNED_NATIVE_TABLE: u8 = 15;
const LIMIT: usize = 256 * 1024 * 1024;
const ITEMS: usize = 4_000_000;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum CodeEvent {
    Image(String),
    /// A graph image (`graph::load`): its bytes and how many functions it
    /// derived.
    Graph { bytes: Vec<u8>, functions: u32 },
    Globals,
    /// A committed hot patch (`hotpatch`): its text, the ids whose old bodies
    /// running frames kept (moved to new ids in this order), and how many
    /// functions it added before those.
    Patch { patch: Vec<u8>, retired: Vec<u32>, added: u32 },
}
pub(crate) struct Execution(Rc<Cell<usize>>);
impl Execution {
    pub(crate) fn enter(depth: &Rc<Cell<usize>>) -> Self {
        depth.set(depth.get() + 1);
        Self(depth.clone())
    }
}
impl Drop for Execution {
    fn drop(&mut self) {
        self.0.set(self.0.get() - 1);
    }
}

/// The default codec refuses external resources. Checkpoints can opt into
/// explicit codecs; restore fills the same placeholder identity in place.
/// A codec must keep irreversible side effects out of save, and clean up its
/// own partially restored resource on error. It owns the external state.
pub trait ResourceCodec {
    fn save(&mut self, vm: &Interp, object: Value) -> Result<Vec<u8>>;
    fn restore(&mut self, vm: &mut Interp, object: Value, data: &[u8]) -> Result<()>;
}
pub type ResourceCodecs = HashMap<String, Box<dyn ResourceCodec>>;

pub type ShapeHook = fn(&mut Interp, Value) -> Result<()>;
#[derive(Default)]
pub struct ShapePolicy {
    /// A persisted name independent of the source type name.
    pub name: Option<String>,
    /// Field names replaced by nil on disk. after_load must initialize typed fields.
    pub transient: HashSet<String>,
    pub before_save: Option<ShapeHook>,
    pub after_load: Option<ShapeHook>,
    /// VM-local callbacks for graph operations; not transferable between VMs.
    pub before_save_value: Option<Value>,
    pub after_load_value: Option<Value>,
}
#[derive(Default)]
pub struct Policies {
    pub shapes: HashMap<String, ShapePolicy>,
}
impl Policies {
    fn root_callbacks(&self, vm: &mut Interp) {
        for policy in self.shapes.values() {
            vm.handles.extend(policy.before_save_value);
            vm.handles.extend(policy.after_load_value);
        }
    }
    fn checkpoint_safe(&self) -> Result<()> {
        if self
            .shapes
            .values()
            .any(|p| p.before_save_value.is_some() || p.after_load_value.is_some())
        {
            return Err(
                "VM-local callbacks require graph save/load; checkpoints use host restore hooks"
                    .into(),
            );
        }
        Ok(())
    }
    fn name(&self, name: &str) -> String {
        self.shapes
            .get(name)
            .and_then(|p| p.name.clone())
            .unwrap_or_else(|| name.into())
    }
}

/// Decode explicit per-operation Nupp policies. `shape` is a record exemplar or
/// exact runtime shape name; callbacks remain rooted for the whole operation.
pub fn policies_from_value(vm: &mut Interp, value: Value) -> Result<Policies> {
    fn object(vm: &Interp, v: Value) -> Result<&Header> {
        let p = v
            .as_obj()
            .filter(|p| vm.heap.is_live_slot(*p))
            .ok_or("policy must be a table or record")?;
        let h = unsafe { p.as_ref() };
        if h.kind != KIND_TABLE && h.kind != KIND_RECORD {
            return Err("policy must be a table or record".into());
        }
        Ok(h)
    }
    fn text(vm: &Interp, v: Value) -> Result<String> {
        let p = v
            .as_obj()
            .filter(|p| vm.heap.is_live_slot(*p))
            .ok_or("policy name must be a string")?;
        let h = unsafe { p.as_ref() };
        if !h.is_stringish() {
            return Err("policy name must be a string".into());
        }
        String::from_utf8(h.bytes().to_vec()).map_err(|_| "policy name must be UTF-8".into())
    }
    fn field(vm: &mut Interp, v: Value, name: &str) -> Value {
        let key = vm.intern(name);
        vm.get_index(v, key)
    }
    fn callback(vm: &Interp, v: Value) -> Result<Option<Value>> {
        if v == Value::NIL {
            return Ok(None);
        }
        if v.as_func().is_some_and(|f| (f as usize) < vm.funcs.len())
            || v.as_obj().is_some_and(|p| {
                vm.heap.is_live_slot(p) && unsafe { p.as_ref().kind == KIND_CLOSURE }
            })
        {
            return Ok(Some(v));
        }
        Err("persistence hook must be a Nupp function".into())
    }
    let mut out = Policies::default();
    if value == Value::NIL {
        return Ok(out);
    }
    object(vm, value)?;
    let scope = vm.open_scope();
    vm.handles.push(value);
    let result = (|| {
        for index in 1..=vm.array_len(value) {
            let v = vm.get_index(value, Value::num(index as f64));
            object(vm, v)?;
            let shape = field(vm, v, "shape");
            let name = if let Some(p) = shape
                .as_obj()
                .filter(|p| vm.heap.is_live_slot(*p) && unsafe { p.as_ref().kind == KIND_RECORD })
            {
                vm.heap.shapes[unsafe { p.as_ref().shape() } as usize]
                    .name
                    .clone()
            } else {
                text(vm, shape)?
            };
            let sid = vm
                .heap
                .shapes
                .iter()
                .position(|s| s.name == name)
                .ok_or_else(|| format!("unknown policy shape {name}"))?;
            let mut policy = ShapePolicy::default();
            let durable = field(vm, v, "name");
            if durable != Value::NIL {
                policy.name = Some(text(vm, durable)?);
            }
            let transient = field(vm, v, "transient");
            if transient != Value::NIL {
                object(vm, transient)?;
                for i in 1..=vm.array_len(transient) {
                    let key = text(vm, vm.get_index(transient, Value::num(i as f64)))?;
                    if !vm.heap.shapes[sid]
                        .names
                        .iter()
                        .any(|&n| vm.bytes_of(n) == key.as_bytes())
                    {
                        return Err(format!("unknown transient field {name}.{key}"));
                    }
                    policy.transient.insert(key);
                }
            }
            let before = field(vm, v, "beforeSave");
            let after = field(vm, v, "afterLoad");
            policy.before_save_value = callback(vm, before)?;
            policy.after_load_value = callback(vm, after)?;
            if out.shapes.insert(name.clone(), policy).is_some() {
                return Err(format!("duplicate policy for {name}"));
            }
        }
        let mut names = HashSet::new();
        for shape in &vm.heap.shapes {
            if !names.insert(out.name(&shape.name)) {
                return Err("duplicate durable shape name".into());
            }
        }
        Ok(out)
    })();
    vm.close_scope(scope);
    result
}

fn run_value_hook(vm: &mut Interp, hook: Value, value: Value, phase: &str) -> Result<()> {
    // A failed/parking callback must not leave scratch tasks, root scopes, or
    // result buffers in the caller. Preserve the caller's multiple-return state.
    let scope = vm.open_scope();
    vm.handles.extend([hook, value]);
    let tasks = vm.tasks.len();
    let extra = vm.extra;
    let extra_n = vm.extra_n;
    let nres = vm.last_nres;
    vm.handles.extend(extra);
    vm.persistence_hook_depth += 1;
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        vm.call_value(hook, &[value])
    }));
    vm.persistence_hook_depth -= 1;
    let result = result.map(|_| ()).map_err(|payload| {
        let value = vm.error_value(payload);
        let message = if value
            .as_obj()
            .is_some_and(|p| vm.heap.is_live_slot(p) && unsafe { p.as_ref().is_stringish() })
        {
            String::from_utf8_lossy(vm.bytes_of(value)).into_owned()
        } else {
            format!("value {:#x}", value.0)
        };
        format!("{phase} hook: {message}")
    });
    vm.tasks.truncate(tasks);
    vm.extra = extra;
    vm.extra_n = extra_n;
    vm.last_nres = nres;
    vm.close_scope(scope);
    result
}

struct Writer(Vec<u8>);
impl Writer {
    fn byte(&mut self, n: u8) {
        self.0.push(n);
    }
    fn u32(&mut self, n: usize) -> Result<()> {
        self.0.extend(
            u32::try_from(n)
                .map_err(|_| "format length overflow")?
                .to_le_bytes(),
        );
        Ok(())
    }
    fn u64(&mut self, n: u64) {
        self.0.extend(n.to_le_bytes());
    }
    fn bytes(&mut self, b: &[u8]) -> Result<()> {
        self.u32(b.len())?;
        self.0.extend(b);
        Ok(())
    }
    fn text(&mut self, s: &str) -> Result<()> {
        self.bytes(s.as_bytes())
    }
}
struct Reader<'a> {
    data: &'a [u8],
    at: usize,
}
impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8]> {
        let end = self.at.checked_add(n).ok_or("length overflow")?;
        let b = self
            .data
            .get(self.at..end)
            .ok_or("truncated persistence data")?;
        self.at = end;
        Ok(b)
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
    fn count(&mut self) -> Result<usize> {
        let n = self.u32()?;
        if n > ITEMS || n > self.data.len() - self.at {
            return Err("collection length exceeds limit or input".into());
        }
        Ok(n)
    }
    fn bytes(&mut self) -> Result<&'a [u8]> {
        let n = self.u32()?;
        self.take(n)
    }
    fn text(&mut self) -> Result<String> {
        String::from_utf8(self.bytes()?.to_vec()).map_err(|_| "invalid UTF-8 metadata".into())
    }
    fn done(&self) -> Result<()> {
        if self.at == self.data.len() {
            Ok(())
        } else {
            Err("trailing persistence data".into())
        }
    }
}
fn frame(kind: u8, payload: Vec<u8>) -> Result<Vec<u8>> {
    if payload.len() > LIMIT {
        return Err("persistence data exceeds 256 MiB limit".into());
    }
    let mut w = Writer(Vec::with_capacity(21 + payload.len()));
    w.0.extend(MAGIC);
    w.byte(kind);
    w.u64(payload.len() as u64);
    w.0.extend(crc32fast::hash(&payload).to_le_bytes());
    w.0.extend(payload);
    Ok(w.0)
}
fn unframe(data: &[u8], kind: u8) -> Result<&[u8]> {
    if data.len() > LIMIT + 21 {
        return Err("persistence data exceeds limit".into());
    }
    let mut r = Reader { data, at: 0 };
    if r.take(8)? != MAGIC || r.byte()? != kind {
        return Err("unsupported persistence version or kind".into());
    }
    let n = r.u64()?;
    if n > LIMIT as u64 {
        return Err("persistence length exceeds limit".into());
    }
    let hash = r.u32()? as u32;
    let data = r.take(n as usize)?;
    r.done()?;
    if crc32fast::hash(data) != hash {
        return Err("persistence checksum mismatch".into());
    }
    Ok(data)
}

/// Identity of the image occupying function IDs starting at zero. Linked
/// objects can reattach only after comparing this to their build-time digest.
pub fn primary_image_hash(vm: &Interp) -> Result<[u8; 32]> {
    match vm.code_events.first() {
        Some(CodeEvent::Image(text)) => Ok(primary_image_digest(text.as_bytes())),
        Some(CodeEvent::Graph { bytes, .. }) => Ok(primary_image_digest(bytes)),
        _ => Err("linked code requires an image loaded before runtime globals".into()),
    }
}

// Hash the raw image bytes without the persistence code digest's tags/lengths.
// ring is already part of a net-enabled ARM64 runtime through TLS; its backend
// selects CPU SHA256 support. Other targets and minimal builds retain sha2.
fn primary_image_digest(bytes: &[u8]) -> [u8; 32] {
    #[cfg(all(target_arch = "aarch64", target_endian = "little", feature = "net"))]
    {
        let digest = ring::digest::digest(&ring::digest::SHA256, bytes);
        digest.as_ref().try_into().expect("SHA256 has 32 bytes")
    }
    #[cfg(not(all(target_arch = "aarch64", target_endian = "little", feature = "net")))]
    {
        Sha256::digest(bytes).into()
    }
}

/// Conservative code identity: function bodies, signatures, constant contents,
/// shape layouts, and the exact image/compiler inputs. Not native addresses.
fn code_digest(vm: &Interp) -> Result<[u8; 32]> {
    let mut h = Sha256::new();
    h.update(b"nupp-vm-persistence-code-1");
    for e in &vm.code_events {
        match e {
            CodeEvent::Image(s) => {
                h.update([0]);
                h.update((s.len() as u64).to_le_bytes());
                h.update(s);
            }
            CodeEvent::Graph { bytes, .. } => {
                h.update([3]);
                h.update((bytes.len() as u64).to_le_bytes());
                h.update(bytes);
            }
            CodeEvent::Globals => h.update([1]),
            CodeEvent::Patch { patch, retired, added } => {
                h.update([2]);
                h.update((patch.len() as u64).to_le_bytes());
                h.update(patch);
                h.update(added.to_le_bytes());
                for fid in retired { h.update(fid.to_le_bytes()); }
            }
        }
    }
    for f in &vm.funcs {
        h.update(format!(
            "{:?}",
            (
                &f.module,
                &f.name,
                &f.sig,
                f.ret,
                f.nparams,
                f.nregs,
                f.nireg,
                f.nfreg,
                f.nvreg,
                f.vararg,
                &f.code,
                &f.jump_tables
            )
        ));
        for &v in &f.consts {
            if let Some(p) = v.as_obj() {
                if !vm.heap.is_live_slot(p) {
                    return Err("dead function constant".into());
                }
                let o = unsafe { p.as_ref() };
                if o.kind == KIND_INTEGER {
                    h.update([2, 0]);
                    h.update(o.aux_len.to_le_bytes());
                } else if o.kind == KIND_STR {
                    h.update([1]);
                    h.update((o.bytes().len() as u64).to_le_bytes());
                    h.update(o.bytes());
                } else {
                    return Err("mutable object in function constants".into());
                }
            } else {
                h.update([0]);
                h.update(v.0.to_le_bytes());
            }
        }
    }
    Ok(h.finalize().into())
}

#[derive(Clone, Debug)]
enum Ref {
    Bits(u64),
    Obj(usize),
    Func(usize),
    Builtin(String),
}
impl Ref {
    fn write(&self, w: &mut Writer) -> Result<()> {
        match self {
            Self::Bits(n) => {
                w.byte(0);
                w.u64(*n)
            }
            Self::Obj(n) => {
                w.byte(1);
                w.u32(*n)?
            }
            Self::Func(n) => {
                w.byte(2);
                w.u32(*n)?
            }
            Self::Builtin(s) => {
                w.byte(3);
                w.text(s)?
            }
        }
        Ok(())
    }
    fn read(r: &mut Reader) -> Result<Self> {
        Ok(match r.byte()? {
            0 => {
                let n = r.u64()?;
                let v = Value(n);
                if !v.is_num() && ![Value::NIL, Value::FALSE, Value::TRUE].contains(&v) {
                    return Err("invalid immediate value".into());
                }
                Self::Bits(n)
            }
            1 => Self::Obj(r.u32()?),
            2 => Self::Func(r.u32()?),
            3 => Self::Builtin(r.text()?),
            _ => return Err("invalid reference tag".into()),
        })
    }
}
fn refs_write(w: &mut Writer, refs: &[Ref]) -> Result<()> {
    w.u32(refs.len())?;
    for v in refs {
        v.write(w)?
    }
    Ok(())
}
fn refs_read(r: &mut Reader) -> Result<Vec<Ref>> {
    let n = r.count()?;
    (0..n).map(|_| Ref::read(r)).collect()
}
fn builtin_name(id: u32) -> Result<String> {
    // A host function by its per-VM id, which a checkpoint keeps by name.
    if id >= crate::extension::FUNCTION_BASE {
        return Ok(format!("hostfn.{}", id - crate::extension::FUNCTION_BASE));
    }
    if let Some(n) = crate::builtins::NAMES.get(id as usize) {
        return Ok((*n).into());
    }
    if id >= crate::host::HOST_BASE {
        if let Some(n) = crate::host::HOST_NAMES.get((id - crate::host::HOST_BASE) as usize) {
            return Ok(format!("host.{n}"));
        }
    }
    Err("unknown builtin".into())
}
fn builtin_id(name: &str) -> Result<u32> {
    if let Some(index) = name.strip_prefix("hostfn.") {
        return index.parse::<u32>().ok().filter(|i| *i < crate::extension::FUNCTION_BASE).map(|i| crate::extension::FUNCTION_BASE + i).ok_or_else(|| format!("unknown builtin {name}"));
    }
    crate::builtins::id_of(name)
        .or_else(|| {
            name.strip_prefix("host.").and_then(|n| {
                crate::host::HOST_NAMES
                    .iter()
                    .position(|x| *x == n)
                    .map(|i| crate::host::HOST_BASE + i as u32)
            })
        })
        .ok_or_else(|| format!("unknown builtin {name}"))
}

#[derive(Debug)]
struct Schema {
    source_id: usize,
    name: String,
    structural: bool,
    fields: Vec<(String, String)>,
}
fn ty_name(vm: &Interp, t: SlotTy, p: &Policies) -> String {
    match t {
        SlotTy::Any => "any".into(),
        SlotTy::Num => "num".into(),
        SlotTy::Str => "str".into(),
        SlotTy::Bool => "bool".into(),
        SlotTy::Record(s) => format!("rec:{}", p.name(&vm.heap.shapes[s as usize].name)),
    }
}
fn schemas(vm: &Interp, p: &Policies) -> Vec<Schema> {
    (0..vm.heap.shapes.len()).map(|id| schema(vm, p, id)).collect()
}
fn schema(vm: &Interp, p: &Policies, id: usize) -> Schema {
    let s = &vm.heap.shapes[id];
    Schema {
        source_id: id,
        name: p.name(&s.name),
        structural: s.structural,
        fields: s
            .names
            .iter()
            .zip(&s.types)
            .map(|(&n, &t)| {
                (
                    String::from_utf8_lossy(vm.bytes_of(n)).into_owned(),
                    ty_name(vm, t, p),
                )
            })
            .collect(),
    }
}
fn schema_write(w: &mut Writer, ss: &[Schema], sparse: bool) -> Result<()> {
    w.u32(ss.len())?;
    for s in ss {
        if sparse { w.u32(s.source_id)?; }
        w.text(&s.name)?;
        w.byte(s.structural as u8);
        w.u32(s.fields.len())?;
        for (n, t) in &s.fields {
            w.text(n)?;
            w.text(t)?
        }
    }
    Ok(())
}
fn schema_read(r: &mut Reader, sparse: bool) -> Result<Vec<Schema>> {
    let n = r.count()?;
    let mut ss = Vec::new();
    for _ in 0..n {
        let source_id = if sparse { r.u32()? } else { ss.len() };
        let name = r.text()?;
        let structural = match r.byte()? {
            0 => false,
            1 => true,
            _ => return Err("invalid structural flag".into()),
        };
        let n = r.count()?;
        let mut fields = Vec::new();
        for _ in 0..n {
            fields.push((r.text()?, r.text()?));
        }
        ss.push(Schema {
            source_id,
            name,
            structural,
            fields,
        });
    }
    Ok(ss)
}

// Payloads keep spans borrowed from the checked input during restore.
#[derive(Debug)]
enum Node<'a> {
    Integer(crate::numeric::Integer),
    String(bool, &'a [u8]),
    Table(Vec<Ref>, Vec<Ref>, Ref, u8),
    Record(usize, Vec<Ref>, Vec<Ref>, Vec<Ref>, Ref),
    Storage(&'a [u8]),
    Closure(usize, Vec<Ref>),
    Cell(Ref),
    Bytes(&'a [u8], usize),
    Iter(u8, usize, Ref, Ref, Vec<Ref>),
    Slice(Ref, usize, usize),
    Resource(String, &'a [u8]),
    /// A bytes owner `crate::sharing` encodes: a shared block or a moved allocation.
    Sharing(u8, &'a [u8]),
}
fn node_read<'a>(r: &mut Reader<'a>) -> Result<Node<'a>> {
    Ok(match r.byte()? {
        KIND_INTEGER => {
            if r.byte()? != 0 { return Err("invalid integer kind".into()); }
            let integer = crate::numeric::Integer { bits: r.u64()?, unsigned: false };
            if integer.immediate().is_some() { return Err("noncanonical boxed integer".into()); }
            Node::Integer(integer)
        }
        KIND_STR => {
            let interned = match r.byte()? {
                0 => false,
                1 => true,
                _ => return Err("invalid string flag".into()),
            };
            let b = r.bytes()?;
            Node::String(interned, b)
        }
        KIND_TABLE => Node::Table(refs_read(r)?, refs_read(r)?, Ref::read(r)?, 0),
        NATIVE_TABLE => Node::Table(refs_read(r)?, refs_read(r)?, Ref::read(r)?, F_NATIVE_STORAGE),
        OWNED_NATIVE_TABLE => Node::Table(refs_read(r)?, refs_read(r)?, Ref::read(r)?, F_NATIVE_STORAGE | F_NATIVE_OWNED),
        KIND_RECORD => Node::Record(r.u32()?, refs_read(r)?, refs_read(r)?, refs_read(r)?, Ref::Bits(Value::NIL.0)),
        RECORD_WITH_METATABLE => Node::Record(r.u32()?, refs_read(r)?, refs_read(r)?, refs_read(r)?, Ref::read(r)?),
        KIND_STORAGE => {
            let b = r.bytes()?;
            if b.len() % 8 != 0 {
                return Err("unaligned storage span".into());
            }
            Node::Storage(b)
        }
        KIND_CLOSURE => Node::Closure(r.u32()?, refs_read(r)?),
        KIND_CELL => Node::Cell(Ref::read(r)?),
        KIND_BYTES => Node::Bytes(r.bytes()?, 0),
        ALIGNED_BYTES => {
            let alignment = r.u32()?;
            if !alignment.is_power_of_two() || alignment > ByteBuffer::MAX_ALIGNMENT { return Err("invalid byte alignment".into()); }
            Node::Bytes(r.bytes()?, alignment)
        },
        KIND_ITER => Node::Iter(
            r.byte()?,
            r.u32()?,
            Ref::read(r)?,
            Ref::read(r)?,
            refs_read(r)?,
        ),
        KIND_SLICE => Node::Slice(Ref::read(r)?, r.u32()?, r.u32()?),
        10 => Node::Resource(r.text()?, r.bytes()?),
        tag @ crate::sharing::SHARED_BYTES..=crate::sharing::MOVED_BYTES => Node::Sharing(tag, r.bytes()?),
        _ => return Err("unknown object kind".into()),
    })
}
fn node_refs<'a>(n: &'a Node) -> Vec<&'a Ref> {
    match n {
        Node::Table(a, b, m, _) => a.iter().chain(b).chain(std::iter::once(m)).collect(),
        Node::Record(_, a, b, c, m) => a.iter().chain(b).chain(c).chain(std::iter::once(m)).collect(),
        Node::Closure(_, a) => a.iter().collect(),
        Node::Cell(v) | Node::Slice(v, _, _) => vec![v],
        Node::Iter(_, _, o, p, k) => std::iter::once(o)
            .chain(std::iter::once(p))
            .chain(k)
            .collect(),
        _ => Vec::new(),
    }
}

struct GraphWriter {
    ids: HashMap<Value, usize>,
    objects: Vec<Value>,
    roots: Vec<Ref>,
    functions: bool,
}
impl GraphWriter {
    fn new() -> Self {
        Self {
            ids: HashMap::new(),
            objects: Vec::new(),
            roots: Vec::new(),
            functions: false,
        }
    }
    fn value(&mut self, vm: &Interp, v: Value) -> Result<Ref> {
        if let Some(p) = v.as_obj() {
            if !vm.heap.is_live_slot(p) {
                return Err("dangling object in saved graph".into());
            }
            let id = if let Some(&id) = self.ids.get(&v) {
                id
            } else {
                let id = self.objects.len();
                if id >= ITEMS {
                    return Err("too many graph objects".into());
                }
                self.ids.insert(v, id);
                self.objects.push(v);
                id
            };
            return Ok(Ref::Obj(id));
        }
        if let Some(f) = v.as_func() {
            if f as usize >= vm.funcs.len() {
                return Err("unknown function".into());
            }
            self.functions = true;
            return Ok(Ref::Func(f as usize));
        }
        if let Some(id) = v.as_builtin() {
            // Host function ids hold only within the code they were made for.
            self.functions |= id >= crate::extension::FUNCTION_BASE;
            return Ok(Ref::Builtin(builtin_name(id)?));
        }
        if v.is_num() || [Value::NIL, Value::FALSE, Value::TRUE].contains(&v) {
            return Ok(Ref::Bits(v.0));
        }
        Err("runtime sentinel cannot be saved".into())
    }
    fn values(&mut self, vm: &Interp, vs: &[Value]) -> Result<Vec<Ref>> {
        vs.iter().map(|&v| self.value(vm, v)).collect()
    }
}

/// Saves directly from VM objects, with no user codec or intermediate value tree.
/// Returned bytes have a checksum and explicit version. Default resource policy is refusal.
pub fn save_graph(vm: &mut Interp, roots: &[Value], policies: &Policies) -> Result<Vec<u8>> {
    save_graph_with(vm, roots, policies, None, false)
}
pub(crate) fn save_graph_with(
    vm: &mut Interp,
    roots: &[Value],
    policies: &Policies,
    codecs: Option<&mut ResourceCodecs>,
    whole_vm: bool,
) -> Result<Vec<u8>> {
    save_graph_mode(vm, roots, policies, codecs, whole_vm, false)
}
fn save_graph_mode(
    vm: &mut Interp,
    roots: &[Value],
    policies: &Policies,
    mut codecs: Option<&mut ResourceCodecs>,
    whole_vm: bool,
    plain: bool,
) -> Result<Vec<u8>> {
    let scope = vm.open_scope();
    vm.handles.extend_from_slice(roots);
    policies.root_callbacks(vm);
    let result = (|| {
        let mut graph = GraphWriter::new();
        graph.roots = graph.values(vm, roots)?;
        let mut payload = Writer(vec![0; 33]);
        // Plain messages carry only the declarations their objects use. Writing
        // the entire compiler's catalog into each nested bundle is quadratic in
        // the number of bundles and can exhaust the frame limit on small data.
        let mut plain_shapes = Vec::new();
        let mut plain_shape_ids = HashMap::new();
        if !plain { schema_write(&mut payload, &schemas(vm, policies), false)?; }
        refs_write(&mut payload, &graph.roots)?;
        let count_at = payload.0.len();
        payload.u32(0)?;
        let mut index = 0;
        let mut rooted = 0;
        while index < graph.objects.len() {
            let v = graph.objects[index];
            if !whole_vm && (crate::coroutines::is_coroutine(vm,v) || crate::coroutines::wrapped(vm,v)!=Value::NIL) {
                return Err("coroutine continuations require a whole-VM checkpoint".into());
            }
            if let Some(kind) = vm.resources.get(&v).cloned().or_else(|| vm.heap.channels.contains_key(&v).then(|| crate::channels::KIND.to_owned())) {
                if unsafe { v.as_obj().unwrap().as_ref().kind } != KIND_TABLE {
                    return Err(format!("resource {kind} requires a table identity"));
                }
                let codec = codecs
                    .as_deref_mut()
                    .and_then(|c| c.get_mut(&kind))
                    .ok_or_else(|| {
                        format!("resource {kind} at object {index} has no save codec")
                    })?;
                let data = codec.save(vm, v)?;
                payload.byte(10);
                payload.text(&kind)?;
                payload.bytes(&data)?;
                index += 1;
                continue;
            }
            if !plain {
                if let Some((tag, data)) = crate::sharing::encode(vm, v)? {
                    payload.byte(tag);
                    payload.bytes(&data)?;
                    index += 1;
                    continue;
                }
            }
            let p = v.as_obj().unwrap();
            let kind = unsafe { p.as_ref().kind };
            if kind == KIND_RECORD {
                let name = vm.heap.shapes[unsafe { p.as_ref().shape() } as usize]
                    .name
                    .clone();
                if let Some(hook) = policies.shapes.get(&name).and_then(|p| p.before_save) {
                    hook(vm, v)?;
                }
                if let Some(hook) = policies.shapes.get(&name).and_then(|p| p.before_save_value) {
                    run_value_hook(vm, hook, v, "beforeSave")?;
                }
            }
            let h = unsafe { p.as_ref() };
            if h.kind == KIND_BYTES && crate::storage::holds_pointers(vm, v) {
                return Err("native storage whose pointer fields are set holds process addresses; \
                            clear them before it is saved or sent"
                    .into());
            }
            payload.byte(if !plain && h.kind == KIND_RECORD && h.flags & F_METATABLE != 0 { RECORD_WITH_METATABLE } else if !plain && h.kind == KIND_TABLE && h.flags & F_NATIVE_STORAGE != 0 { if h.flags & F_NATIVE_OWNED != 0 { OWNED_NATIVE_TABLE } else { NATIVE_TABLE } } else if h.kind == KIND_BYTES && unsafe { &*(h.payload() as *const BytesPayload) }.data.is_fixed() { ALIGNED_BYTES } else { h.kind });
            // Use the collector's edge enumeration to discover every ordinary
            // reference. Transient records use their filtered edge list below.
            if kind != KIND_RECORD && !(plain && kind == KIND_TABLE) {
                let mut children = Vec::new();
                Heap::each_child(h, &mut |c| children.push(c));
                for c in children {
                    graph.value(vm, c)?;
                }
            }
            match h.kind {
                KIND_STR => {
                    payload.byte((h.flags & F_INTERNED != 0) as u8);
                    payload.bytes(h.bytes())?
                }
                KIND_TABLE => {
                    let t = h.table_ref();
                    refs_write(&mut payload, &graph.values(vm, &t.array)?)?;
                    let pairs: Vec<Value> = t.hash.iter().flat_map(|(k, v)| [*k, *v]).collect();
                    refs_write(&mut payload, &graph.values(vm, &pairs)?)?;
                    graph.value(vm, if plain { Value::NIL } else { t.meta })?.write(&mut payload)?
                }
                KIND_RECORD => {
                    let source_shape = h.shape() as usize;
                    let saved_shape = if plain {
                        *plain_shape_ids.entry(source_shape).or_insert_with(|| {
                            plain_shapes.push(source_shape);
                            plain_shapes.len() - 1
                        })
                    } else { source_shape };
                    payload.u32(saved_shape)?;
                    let shape = &vm.heap.shapes[h.shape() as usize];
                    let policy = policies.shapes.get(&shape.name);
                    let slots: Vec<Value> = h
                        .slots()
                        .iter()
                        .zip(&shape.names)
                        .map(|(&v, &n)| {
                            if policy.is_some_and(|p| {
                                p.transient
                                    .contains(&String::from_utf8_lossy(vm.bytes_of(n)).into_owned())
                            }) {
                                Value::NIL
                            } else {
                                v
                            }
                        })
                        .collect();
                    refs_write(&mut payload, &graph.values(vm, &slots)?)?;
                    refs_write(&mut payload, &graph.values(vm, h.record_array_ref())?)?;
                    let extra: Vec<Value> = h
                        .record_extra_ref()
                        .as_ref()
                        .map(|m| m.iter().flat_map(|(k, v)| [*k, *v]).collect())
                        .unwrap_or_default();
                    refs_write(&mut payload, &graph.values(vm, &extra)?)?;
                    if !plain && h.flags & F_METATABLE != 0 { graph.value(vm, h.record_extra_ref().as_ref().unwrap().meta)?.write(&mut payload)?; }
                }
                KIND_STORAGE => {
                    let s = unsafe { &*(h.payload() as *const StoragePayload) };
                    payload.u32(
                        s.data
                            .len()
                            .checked_mul(8)
                            .ok_or("storage length overflow")?,
                    )?;
                    #[cfg(target_endian = "little")]
                    payload.0.extend_from_slice(unsafe {
                        std::slice::from_raw_parts(s.data.as_ptr().cast::<u8>(), s.data.len() * 8)
                    });
                    #[cfg(target_endian = "big")]
                    for f in &s.data {
                        payload.u64(f.to_bits());
                    }
                }
                KIND_INTEGER => { payload.byte(0); payload.u64(h.aux_len); }
                KIND_BYTES => {
                    let alignment = unsafe { &*(h.payload() as *const BytesPayload) }.data.alignment();
                    if unsafe { &*(h.payload() as *const BytesPayload) }.data.is_fixed() { payload.u32(alignment)?; }
                    payload.bytes(h.bytes())?;
                },
                KIND_CLOSURE => {
                    graph.functions = true;
                    payload.u32(h.fid() as usize)?;
                    refs_write(&mut payload, &graph.values(vm, h.slots())?)?
                }
                KIND_CELL => graph.value(vm, h.slots()[0])?.write(&mut payload)?,
                KIND_SLICE => {
                    let s = h.slice();
                    graph.value(vm, s.source)?.write(&mut payload)?;
                    payload.u32(s.off as usize)?;
                    payload.u32(s.len as usize)?
                }
                KIND_ITER => {
                    let i = unsafe { &*(h.payload() as *const IterPayload) };
                    payload.byte(h.aux as u8);
                    payload.u32(i.pos)?;
                    graph.value(vm, i.obj)?.write(&mut payload)?;
                    graph.value(vm, i.pattern)?.write(&mut payload)?;
                    refs_write(&mut payload, &graph.values(vm, &i.keys)?)?
                }
                _ => return Err(format!("unsupported object kind {}", h.kind)),
            }
            // Hooks can allocate. Keep every discovered object rooted until done.
            vm.handles.extend_from_slice(&graph.objects[rooted..]);
            rooted = graph.objects.len();
            index += 1;
            if payload.0.len() > LIMIT {
                return Err("graph exceeds persistence limit".into());
            }
        }
        payload.0[0] = graph.functions as u8;
        if graph.functions {
            payload.0[1..33].copy_from_slice(&code_digest(vm)?);
        }
        payload.0[count_at..count_at + 4]
            .copy_from_slice(&(graph.objects.len() as u32).to_le_bytes());
        if plain {
            // A typed field can name a declaration even without an object of
            // that type. Keep its transitive schema dependencies too.
            let mut cursor = 0;
            while cursor < plain_shapes.len() {
                for ty in &vm.heap.shapes[plain_shapes[cursor]].types {
                    if let SlotTy::Record(id) = ty {
                        plain_shape_ids.entry(*id as usize).or_insert_with(|| {
                            plain_shapes.push(*id as usize);
                            plain_shapes.len() - 1
                        });
                    }
                }
                cursor += 1;
            }
            let selected: Vec<_> = plain_shapes.iter().map(|&id| schema(vm, policies, id)).collect();
            let mut framed = Writer(payload.0[..33].to_vec());
            schema_write(&mut framed, &selected, true)?;
            framed.0.extend_from_slice(&payload.0[33..]);
            return frame(PLAIN_GRAPH, framed.0);
        }
        frame(0, payload.0)
    })();
    vm.close_scope(scope);
    result
}

struct Graph<'a> {
    functions: bool,
    digest: [u8; 32],
    schemas: Vec<Schema>,
    roots: Vec<Ref>,
    nodes: Vec<Node<'a>>,
}
fn parse_graph(data: &[u8]) -> Result<Graph<'_>> {
    let sparse = data.get(8) == Some(&PLAIN_GRAPH);
    let mut r = Reader {
        data: unframe(data, if sparse { PLAIN_GRAPH } else { 0 })?,
        at: 0,
    };
    let functions = match r.byte()? {
        0 => false,
        1 => true,
        _ => return Err("invalid function flag".into()),
    };
    let digest = r.take(32)?.try_into().unwrap();
    let schemas = schema_read(&mut r, sparse)?;
    let roots = refs_read(&mut r)?;
    let n = r.count()?;
    let mut nodes = Vec::new();
    for _ in 0..n {
        nodes.push(node_read(&mut r)?)
    }
    r.done()?;
    Ok(Graph {
        functions,
        digest,
        schemas,
        roots,
        nodes,
    })
}
fn bind_schemas(
    vm: &mut Interp,
    ss: &[Schema],
    policies: &Policies,
    create: bool,
    required: &HashSet<usize>,
) -> Result<Vec<u32>> {
    if ss.is_empty() { return Ok(Vec::new()); }
    let known = schemas(vm, policies);
    let mut ids = Vec::new();
    for (index, s) in ss.iter().enumerate() {
        if !create && !required.contains(&index) {
            ids.push(u32::MAX);
            continue;
        }
        let matches: Vec<usize> = known
            .iter()
            .enumerate()
            .filter(|(_, k)| {
                k.name == s.name && k.fields == s.fields && k.structural == s.structural
            })
            .map(|(i, _)| i)
            .collect();
        if let Some(&id) = matches
            .iter()
            .find(|&&id| id == s.source_id)
            .or(matches.first())
        {
            ids.push(id as u32);
            continue;
        }
        if known.iter().any(|k| k.name == s.name) {
            return Err(format!("shape schema changed: {}", s.name));
        }
        if !create {
            return Err(format!("unknown shape {}", s.name));
        }
        let mut names = Vec::new();
        let mut unique = HashSet::new();
        for (n, _) in &s.fields {
            if !unique.insert(n) {
                return Err("duplicate shape field".into());
            }
            let v = vm.intern(n);
            vm.handles.push(v);
            names.push(v);
        }
        let source_name = policies
            .shapes
            .iter()
            .find(|(_, p)| p.name.as_deref() == Some(s.name.as_str()))
            .map(|(n, _)| n.as_str())
            .unwrap_or(s.name.as_str());
        let id = vm
            .heap
            .shape(source_name, &names, &vec![SlotTy::Any; names.len()]);
        vm.heap.shapes[id as usize].structural = s.structural;
        ids.push(id);
    }
    for (i, s) in ss.iter().enumerate() {
        if ids[i] == u32::MAX {
            continue;
        }
        let mut types = Vec::new();
        for (_, t) in &s.fields {
            types.push(match t.as_str() {
                "any" => SlotTy::Any,
                "num" => SlotTy::Num,
                "str" => SlotTy::Str,
                "bool" => SlotTy::Bool,
                t => {
                    let name = t.strip_prefix("rec:").ok_or("unknown slot type")?;
                    let n = ss
                        .iter()
                        .position(|s| s.name == name)
                        .ok_or("unknown record type")?;
                    SlotTy::Record(ids[n])
                }
            });
        }
        if (ids[i] as usize) >= known.len() {
            vm.heap.shapes[ids[i] as usize].types = types;
        }
    }
    Ok(ids)
}
fn resolve(r: &Ref, objects: &[Value]) -> Result<Value> {
    Ok(match r {
        Ref::Bits(n) => Value(*n),
        Ref::Obj(i) => *objects.get(*i).ok_or("object ID out of bounds")?,
        Ref::Func(i) => Value::func(*i as u32),
        Ref::Builtin(n) => Value::builtin(builtin_id(n)?),
    })
}
fn resolve_all(rs: &[Ref], objects: &[Value]) -> Result<Vec<Value>> {
    rs.iter().map(|r| resolve(r, objects)).collect()
}
fn refs_validate(vm: &Interp, g: &Graph) -> Result<()> {
    let mut needs_code = false;
    for r in g.roots.iter().chain(g.nodes.iter().flat_map(node_refs)) {
        match r {
            Ref::Obj(i) if *i >= g.nodes.len() => return Err("object ID out of bounds".into()),
            Ref::Func(i) => {
                needs_code = true;
                if *i >= vm.funcs.len() {
                    return Err("function ID out of bounds".into());
                }
            }
            Ref::Builtin(n) => {
                builtin_id(n)?;
            }
            _ => {}
        }
    }
    for n in &g.nodes {
        match n {
            Node::Closure(f, caps) => {
                needs_code = true;
                let f = vm.funcs.get(*f).ok_or("closure function out of bounds")?;
                for op in &f.code {
                    if let crate::interp::Op::GetUpval(_, i) = op {
                        if *i as usize >= caps.len() {
                            return Err("closure captures are incomplete".into());
                        }
                    }
                }
            }
            Node::Record(s, slots, _, extra, _) => {
                let schema = g.schemas.get(*s).ok_or("record shape out of bounds")?;
                if slots.len() != schema.fields.len() || extra.len() % 2 != 0 {
                    return Err("invalid record payload".into());
                }
            }
            Node::Table(_, pairs, meta, _) => {
                if pairs.len() % 2 != 0 {
                    return Err("invalid table pairs".into());
                }
                if !matches!(meta,Ref::Bits(n) if *n==Value::NIL.0)
                    && !matches!(meta,Ref::Obj(i) if matches!(g.nodes.get(*i),Some(Node::Table(..) | Node::Record(..))))
                {
                    return Err("invalid table metatable".into());
                }
            }
            Node::Slice(Ref::Obj(i), off, len) => match g.nodes.get(*i) {
                Some(Node::String(_, b)) if off.checked_add(*len).is_some_and(|n| n <= b.len()) => {
                }
                _ => return Err("invalid slice range or source".into()),
            },
            Node::Slice(..) => return Err("invalid slice source".into()),
            Node::Iter(kind, pos, object, pattern, keys) => {
                let obj = if let Ref::Obj(i) = object {
                    g.nodes.get(*i)
                } else {
                    None
                };
                match kind {
                    1 if *pos <= keys.len()
                        && matches!(obj, Some(Node::Table(..) | Node::Record(..))) => {}
                    2 if matches!(obj, Some(Node::Table(..) | Node::Record(..))) => {}
                    3 if matches!(obj, Some(Node::String(..) | Node::Slice(..)))
                        && matches!(pattern,Ref::Obj(i) if matches!(g.nodes.get(*i),Some(Node::String(..)|Node::Slice(..)))) =>
                        {}
                    _ => return Err("invalid iterator payload".into()),
                }
            }
            _ => {}
        }
        if let Node::Record(_, _, _, _, meta) = n {
            if !matches!(meta, Ref::Bits(n) if *n == Value::NIL.0)
                && !matches!(meta, Ref::Obj(i) if matches!(g.nodes.get(*i), Some(Node::Table(..) | Node::Record(..)))) {
                return Err("invalid record metatable".into());
            }
        }
        let pairs = match n {
            Node::Table(_, p, _, _) | Node::Record(_, _, _, p, _) => Some(p),
            _ => None,
        };
        if let Some(pairs) = pairs {
            for pair in pairs.chunks_exact(2) {
                if matches!(pair[0],Ref::Bits(n) if n==Value::NIL.0 || Value(n).is_num() && Value(n).as_num().is_nan())
                {
                    return Err("nil or NaN table key".into());
                }
            }
        }
    }
    if needs_code && (!g.functions || g.digest != code_digest(vm)?) {
        return Err("function/compiler digest changed".into());
    }
    Ok(())
}
fn typed(vm: &Interp, v: Value, t: SlotTy) -> bool {
    match t {
        SlotTy::Any => true,
        SlotTy::Num => crate::numeric::is_numeric(v),
        SlotTy::Bool => v == Value::TRUE || v == Value::FALSE,
        SlotTy::Str => vm.is_stringish(v),
        SlotTy::Record(s) => v
            .as_obj()
            .is_some_and(|p| unsafe { p.as_ref().kind == KIND_RECORD && p.as_ref().shape() == s }),
    }
}
fn validate_types(vm: &Interp, objects: &[Value]) -> Result<()> {
    for &v in objects {
        if let Some(p) = v.as_obj() {
            let h = unsafe { p.as_ref() };
            if h.kind == KIND_RECORD {
                let shape = &vm.heap.shapes[h.shape() as usize];
                for (i, (&v, &ty)) in h.slots().iter().zip(&shape.types).enumerate() {
                    if !typed(vm, v, ty) {
                        return Err(format!(
                            "invalid typed field {}.{}",
                            shape.name,
                            String::from_utf8_lossy(vm.bytes_of(shape.names[i]))
                        ));
                    }
                }
            }
        }
    }
    Ok(())
}

/// Load into a VM with matching shape declarations/code. Validation and all
/// relocation finish before roots are returned. The caller must root returned
/// values before another allocation, as with every VM allocation API.
pub fn load_graph(
    vm: &mut Interp,
    data: &[u8],
    policies: &Policies,
    expected: Option<SlotTy>,
) -> Result<Vec<Value>> {
    load_graph_with(vm, data, policies, expected, None, false, None)
}
// Compiler caches and worker messages may come from project-writable files.
// Validate the complete graph before allocating or resolving executable values.
fn plain_graph(data: &[u8], portable: bool) -> Result<()> {
    let graph = parse_graph(data)?;
    if graph.functions || graph.roots.len() != 1 {
        return Err("plain data must contain one non-executable root".into());
    }
    let reference = |value: &Ref| match value {
        Ref::Bits(_) | Ref::Obj(_) => Ok(()),
        _ => Err("plain data cannot contain callable values".to_string()),
    };
    reference(&graph.roots[0])?;
    for node in &graph.nodes {
        if portable {
            if let Node::Record(schema, ..) = node {
                if !graph
                    .schemas
                    .get(*schema)
                    .is_some_and(|schema| schema.structural)
                {
                    return Err(
                        "data graphs cannot contain nominal records; encode their fields as data"
                            .into(),
                    );
                }
            }
        }
        match node {
            Node::Integer(_) | Node::String(..) | Node::Slice(..) => (),
            Node::Table(_, _, meta, 0) | Node::Record(_, _, _, _, meta) if matches!(meta, Ref::Bits(bits) if *bits == Value::NIL.0) => {
                ()
            }
            _ => return Err("plain data cannot contain resources, closures, or metatables".into()),
        }
        for value in node_refs(node) { reference(value)?; }
    }
    Ok(())
}

/// Encode stored compiler data, omitting table behavior as Lua plain-data encoding does.
pub fn save_plain(vm: &mut Interp, value: Value) -> Result<Vec<u8>> {
    let bytes = save_graph_mode(vm, &[value], &Policies::default(), None, false, true)?;
    plain_graph(&bytes, false)?;
    Ok(bytes)
}

/// Decode compiler data after rejecting every executable and external edge.
pub fn load_plain(vm: &mut Interp, data: &[u8]) -> Result<Value> {
    plain_graph(data, false)?;
    Ok(load_graph(vm, data, &Policies::default(), None)?[0])
}

/// Durable data cannot regain behavior through a program's nominal record witness.
pub fn save_data(vm: &mut Interp, value: Value) -> Result<Vec<u8>> {
    let bytes = save_graph_mode(vm, &[value], &Policies::default(), None, false, false)?;
    plain_graph(&bytes, true)?;
    Ok(bytes)
}

pub fn load_data(vm: &mut Interp, data: &[u8]) -> Result<Value> {
    plain_graph(data, true)?;
    Ok(load_graph_mode(
        vm,
        data,
        &Policies::default(),
        None,
        None,
        false,
        None,
        true,
    )?[0])
}

/// Replace a record in place, preserving references to its identity. A rejected
/// framing/schema leaves it unchanged. Hook failures can leave it modified.
pub fn load_into(
    vm: &mut Interp,
    data: &[u8],
    target: Value,
    policies: &Policies,
) -> Result<Value> {
    let p = target
        .as_obj()
        .filter(|p| vm.heap.is_live_slot(*p))
        .ok_or("in-place target is not live")?;
    let h = unsafe { p.as_ref() };
    if h.kind != KIND_RECORD {
        return Err("in-place load requires a record".into());
    }
    load_into_with(vm, data, target, policies, None)
}
/// `load_into` with resource codecs; `crate::snapshot` stages its resources.
pub(crate) fn load_into_with(
    vm: &mut Interp,
    data: &[u8],
    target: Value,
    policies: &Policies,
    codecs: Option<&mut ResourceCodecs>,
) -> Result<Value> {
    let p = target
        .as_obj()
        .filter(|p| vm.heap.is_live_slot(*p))
        .ok_or("in-place target is not live")?;
    let h = unsafe { p.as_ref() };
    if h.kind != KIND_RECORD {
        return Err("in-place load requires a record".into());
    }
    let out = load_graph_with(
        vm,
        data,
        policies,
        Some(SlotTy::Record(h.shape())),
        codecs,
        false,
        Some(target),
    )?;
    Ok(out[0])
}
pub(crate) fn load_graph_with(
    vm: &mut Interp,
    data: &[u8],
    policies: &Policies,
    expected: Option<SlotTy>,
    codecs: Option<&mut ResourceCodecs>,
    create: bool,
    target: Option<Value>,
) -> Result<Vec<Value>> {
    load_graph_mode(vm, data, policies, expected, codecs, create, target, false)
}

fn load_graph_mode(
    vm: &mut Interp,
    data: &[u8],
    policies: &Policies,
    expected: Option<SlotTy>,
    mut codecs: Option<&mut ResourceCodecs>,
    create: bool,
    target: Option<Value>,
    data_only: bool,
) -> Result<Vec<Value>> {
    let g = parse_graph(data)?;
    refs_validate(vm, &g)?;
    for n in &g.nodes {
        if let Node::Resource(kind, _) = n {
            if !codecs.as_ref().is_some_and(|c| c.contains_key(kind)) {
                return Err(format!("resource {kind} has no restore codec"));
            }
        }
    }
    let scope = vm.open_scope();
    policies.root_callbacks(vm);
    if let Some(v) = target {
        vm.handles.push(v);
    }
    let result = (|| {
        let mut required: HashSet<usize> = g
            .nodes
            .iter()
            .filter_map(|n| {
                if let Node::Record(s, ..) = n {
                    Some(*s)
                } else {
                    None
                }
            })
            .collect();
        while !data_only {
            let previous = required.len();
            for index in required.clone() {
                for (_, ty) in &g.schemas[index].fields {
                    if let Some(name) = ty.strip_prefix("rec:") {
                        let index = g
                            .schemas
                            .iter()
                            .position(|s| s.name == name)
                            .ok_or("unknown record schema")?;
                        required.insert(index);
                    }
                }
            }
            if required.len() == previous {
                break;
            }
        }
        // Durable data uses field names, never a destination program's shape
        // identity or methods. Root every interned key before allocating nodes.
        let mut data_names = if data_only { vec![Vec::new(); g.schemas.len()] } else { Vec::new() };
        let shape_ids = if data_only {
            for &index in &required {
                let mut unique = HashSet::new();
                for (name, _) in &g.schemas[index].fields {
                    if !unique.insert(name) {
                        return Err("duplicate data field".into());
                    }
                    let key = vm.intern(name);
                    vm.handles.push(key);
                    data_names[index].push(key);
                }
            }
            Vec::new()
        } else {
            bind_schemas(vm, &g.schemas, policies, create, &required)?
        };
        for node in &g.nodes {
            if data_only {
                continue;
            }
            if let Node::Record(s, fields, ..) = node {
                let shape = &vm.heap.shapes[shape_ids[*s] as usize];
                for (index, value) in fields.iter().enumerate() {
                    let field = String::from_utf8_lossy(vm.bytes_of(shape.names[index]));
                    let deferred = matches!(value, Ref::Bits(n) if *n == Value::NIL.0)
                        && policies.shapes.get(&shape.name).is_some_and(|p| {
                            p.transient.contains(field.as_ref())
                                && (p.after_load.is_some() || p.after_load_value.is_some())
                        });
                    let fits = match shape.types[index] {
                        SlotTy::Any => true,
                        SlotTy::Num => match value {
                            Ref::Bits(n) => Value(*n).is_num(),
                            Ref::Obj(i) => matches!(g.nodes[*i], Node::Integer(..)),
                            _ => false,
                        },
                        SlotTy::Bool => {
                            matches!(value, Ref::Bits(n) if *n == Value::TRUE.0 || *n == Value::FALSE.0)
                        }
                        SlotTy::Str => {
                            matches!(value, Ref::Obj(i) if matches!(g.nodes[*i], Node::String(..) | Node::Slice(..)))
                        }
                        SlotTy::Record(target) => {
                            matches!(value, Ref::Obj(i) if matches!(g.nodes[*i], Node::Record(s,..) if shape_ids[s] == target))
                        }
                    };
                    if !fits && !deferred {
                        return Err(format!("invalid typed field {}.{}", shape.name, field));
                    }
                }
            }
        }
        let target_id = if let Some(target) = target {
            let Some(Ref::Obj(id)) = g.roots.first() else {
                return Err("in-place root is not a record".into());
            };
            let Some(Node::Record(s, ..)) = g.nodes.get(*id) else {
                return Err("in-place root is not a record".into());
            };
            if !typed(vm, target, SlotTy::Record(shape_ids[*s])) {
                return Err("in-place shape mismatch".into());
            }
            Some(*id)
        } else {
            None
        };
        let mut objects = vec![Value::NIL; g.nodes.len()];
        // Strings first: slices can point forward in object order.
        for (i, n) in g.nodes.iter().enumerate() {
            if let Node::String(interned, b) = n {
                let v = if *interned {
                    vm.intern_bytes(b)
                } else {
                    vm.new_string_bytes(b)
                };
                objects[i] = v;
                vm.handles.push(v);
            }
        }
        for (i, n) in g.nodes.iter().enumerate() {
            if matches!(n, Node::String(..)) {
                continue;
            }
            let v = if target_id == Some(i) {
                target.unwrap()
            } else {
                match n {
                    Node::Table(array, pairs, _, _) => {
                        vm.new_table_sized(array.len(), pairs.len() / 2)
                    }
                    Node::Resource(..) => vm.new_table(),
                    Node::Integer(value) => vm.box_integer(*value),
                    Node::Record(_, fields, array, extra, _) if data_only => {
                        vm.new_table_sized(array.len(), fields.len() + extra.len() / 2)
                    }
                    Node::Record(s, ..) => vm.new_record(shape_ids[*s]),
                    Node::Sharing(tag, data) => crate::sharing::decode(vm, *tag, data)?,
                    Node::Bytes(b, alignment) => {
                        let v = if *alignment != 0 { vm.heap_new_aligned_bytes(b.len(), *alignment) } else { vm.heap_new_bytes(b.len()) };
                        vm.bytes_mut(v).copy_from_slice(b);
                        v
                    }
                    Node::Storage(b) => {
                        let v = vm.new_storage(b.len() / 8);
                        let h = unsafe { &mut *v.as_obj().unwrap().as_ptr() };
                        #[cfg(target_endian = "little")]
                        unsafe {
                            std::ptr::copy_nonoverlapping(
                                b.as_ptr(),
                                h.storage().data.as_mut_ptr().cast::<u8>(),
                                b.len(),
                            );
                        }
                        #[cfg(target_endian = "big")]
                        for (dst, src) in h.storage().data.iter_mut().zip(b.chunks_exact(8)) {
                            *dst = f64::from_bits(u64::from_le_bytes(src.try_into().unwrap()));
                        }
                        v
                    }
                    Node::Closure(f, caps) => {
                        vm.new_closure(*f as u32, &vec![Value::NIL; caps.len()])
                    }
                    Node::Cell(_) => vm.new_cell(Value::NIL),
                    Node::Slice(source, off, len) => vm.new_slice(
                        resolve(source, &objects)?,
                        u32::try_from(*off).map_err(|_| "slice offset overflow")?,
                        u32::try_from(*len).map_err(|_| "slice length overflow")?,
                    ),
                    Node::Iter(kind, ..) => vm.new_iter(*kind, Value::NIL, Value::NIL),
                    Node::String(..) => unreachable!(),
                }
            };
            objects[i] = v;
            vm.handles.push(v);
        }
        // Resolve every edge once. Rebuild hash tables from relocated keys.
        for (i, n) in g.nodes.iter().enumerate() {
            let v = objects[i];
            let p = v.as_obj().unwrap();
            vm.heap.schema_write(p);
            let h = unsafe { &mut *p.as_ptr() };
            let before = h.external_bytes();
            match n {
                Node::Table(array, pairs, meta, native) => {
                    h.flags &= !(F_NATIVE_STORAGE | F_NATIVE_OWNED);
                    h.flags |= *native;
                    let t = h.table();
                    t.array.extend(resolve_all(array, &objects)?);
                    t.meta = resolve(meta, &objects)?;
                    for pair in pairs.chunks_exact(2) {
                        t.hash
                            .insert(resolve(&pair[0], &objects)?, resolve(&pair[1], &objects)?);
                    }
                    h.refresh();
                }
                Node::Record(schema, slots, array, extra, _) if data_only => {
                    let table = h.table();
                    table.array.extend(resolve_all(array, &objects)?);
                    for pair in extra.chunks_exact(2) {
                        table
                            .hash
                            .insert(resolve(&pair[0], &objects)?, resolve(&pair[1], &objects)?);
                    }
                    for (&key, field) in data_names[*schema].iter().zip(slots) {
                        table.hash.insert(key, resolve(field, &objects)?);
                    }
                    h.refresh();
                }
                Node::Record(_, slots, array, extra, meta) => {
                    h.slots_mut()
                        .copy_from_slice(&resolve_all(slots, &objects)?);
                    h.record_array().truncate(0);
                    h.record_array().extend(resolve_all(array, &objects)?);
                    h.record_tail().clear_extra();
                    let meta = resolve(meta, &objects)?;
                    h.flags &= !F_METATABLE;
                    if meta != Value::NIL { h.flags |= F_METATABLE; }
                    if !extra.is_empty() || meta != Value::NIL {
                        let mut table = ValueTable::new();
                        for pair in extra.chunks_exact(2) {
                            table
                                .insert(resolve(&pair[0], &objects)?, resolve(&pair[1], &objects)?);
                        }
                        let extra = h.ensure_record_extra();
                        extra.fields = table;
                        extra.meta = meta;
                    }
                }
                Node::Closure(_, caps) => {
                    h.slots_mut().copy_from_slice(&resolve_all(caps, &objects)?)
                }
                Node::Cell(value) => h.slots_mut()[0] = resolve(value, &objects)?,
                Node::Iter(_, pos, obj, pattern, keys) => {
                    let it = h.iter();
                    it.pos = *pos;
                    it.obj = resolve(obj, &objects)?;
                    it.pattern = resolve(pattern, &objects)?;
                    it.keys = resolve_all(keys, &objects)?;
                    h.refresh();
                }
                _ => {}
            }
            vm.heap.account_resize(before, h.external_bytes());
            let mut children = Vec::new();
            Heap::each_child(h, &mut |v| children.push(v));
            for child in children {
                vm.heap.barrier(p, child);
            }
        }
        // Recreate all external identities before object hooks can consult them.
        // Resource codecs see relocated VM edges, but must not assume another
        // resource's external state is ready until this pass has completed.
        for (i, n) in g.nodes.iter().enumerate() {
            if let Node::Resource(kind, data) = n {
                codecs
                    .as_deref_mut()
                    .unwrap()
                    .get_mut(kind)
                    .unwrap()
                    .restore(vm, objects[i], data)?;
                if kind != crate::channels::KIND { vm.resources.insert(objects[i], kind.clone()); }
            }
        }
        for (i, n) in g.nodes.iter().enumerate() {
            if data_only {
                continue;
            }
            if let Node::Record(s, ..) = n {
                let name = vm.heap.shapes[shape_ids[*s] as usize].name.clone();
                if let Some(hook) = policies.shapes.get(&name).and_then(|p| p.after_load) {
                    hook(vm, objects[i])?;
                }
                if let Some(hook) = policies.shapes.get(&name).and_then(|p| p.after_load_value) {
                    run_value_hook(vm, hook, objects[i], "afterLoad")?;
                }
            }
        }
        validate_types(vm, &objects)?;
        let roots = resolve_all(&g.roots, &objects)?;
        if let Some(t) = expected {
            if roots.len() != 1 || !typed(vm, roots[0], t) {
                return Err("loaded root does not match requested type".into());
            }
        }
        Ok(roots)
    })();
    vm.close_scope(scope);
    result
}

pub(crate) fn safepoint(vm: &Interp) -> Result<()> {
    if vm.execution_depth.get() != 0
        || vm.pending_error.is_some()
        || vm.active_cancellation.is_some()
    {
        return Err("checkpoint requires a safepoint outside VM calls and exceptions".into());
    }
    if vm
        .host
        .as_ref()
        .is_some_and(|h| h.threads == 0 || h.threads > 64)
    {
        return Err("checkpoint supports host pools of 1 to 64 threads".into());
    }
    if !vm.host_waiters.is_empty() || vm.host.as_ref().is_some_and(|h| h.outstanding != 0) {
        return Err("checkpoint blocked by pending host requests; drain completions first".into());
    }
    #[cfg(feature = "compiled-runtime")]
    if crate::compiled::HELPER_FP.load(std::sync::atomic::Ordering::Relaxed) != 0 {
        return Err("checkpoint inside a native callback".into());
    }
    Ok(())
}
fn root(roots: &mut Vec<Value>, v: Value) -> usize {
    let i = roots.len();
    roots.push(v);
    i
}
fn save_roots(w: &mut Writer, roots: &mut Vec<Value>, vs: &[Value]) -> Result<()> {
    w.u32(vs.len())?;
    for &v in vs {
        w.u32(root(roots, v))?;
    }
    Ok(())
}
fn read_ids(r: &mut Reader) -> Result<Vec<usize>> {
    let n = r.count()?;
    (0..n).map(|_| r.u32()).collect()
}
fn get_root(roots: &[Value], i: usize) -> Result<Value> {
    roots
        .get(i)
        .copied()
        .ok_or_else(|| "root index out of bounds".into())
}
fn get_roots(roots: &[Value], ids: &[usize]) -> Result<Vec<Value>> {
    ids.iter().map(|&i| get_root(roots, i)).collect()
}

/// Save all runtime-owned state at an embedding safepoint. Task order is the
/// current scheduler order; parked keys and all class windows are preserved.
/// Native code/caches are omitted. External roots require named restore codecs.
pub fn save_vm(
    vm: &mut Interp,
    policies: &Policies,
    codecs: &mut ResourceCodecs,
) -> Result<Vec<u8>> {
    policies.checkpoint_safe()?;
    if !vm.supervised.is_empty() {
        return Err("checkpoint cannot capture external VM supervision owners; capture the game instead".into());
    }
    safepoint(vm)?;
    vm.snapshot_workers()?;
    // Standard providers' handles take part through sentinel resources.
    crate::snapshot::before_checkpoint(vm, codecs);
    if let Some(&clock) = vm.loaded.get("nupp.vm.clock") {
        let now = Value::num(vm.clock.now());
        crate::task_api::put(vm, clock, "_checkpointNow", now);
    }
    codecs.entry(crate::channels::KIND.into()).or_insert_with(|| Box::new(crate::channels::Codec {registry:vm.channel_registry.clone(),transfer:false}));
    if let Some(s) = &vm.scheduler {
        s.validate(vm)?;
    }
    let recorded: usize = vm
        .code_events
        .iter()
        .map(|e| match e {
            CodeEvent::Image(s) => s
                .lines()
                .filter(|l| l.trim_start().starts_with("function "))
                .count(),
            CodeEvent::Graph { functions, .. } => *functions as usize,
            CodeEvent::Globals => 2,
            CodeEvent::Patch { retired, added, .. } => *added as usize + retired.len(),
        })
        .sum();
    if recorded != vm.funcs.len() {
        return Err("checkpoint code has no complete image loading recipe".into());
    }
    let mut w = Writer(Vec::new());
    w.0.extend(code_digest(vm)?);
    w.u32(vm.code_events.len())?;
    for e in &vm.code_events {
        match e {
            CodeEvent::Image(s) => {
                w.byte(0);
                w.text(s)?
            }
            CodeEvent::Graph { bytes, .. } => {
                w.byte(3);
                w.bytes(bytes)?
            }
            CodeEvent::Globals => w.byte(1),
            CodeEvent::Patch { patch, retired, added } => {
                w.byte(2);
                w.bytes(patch)?;
                w.u32(*added as usize)?;
                w.u32(retired.len())?;
                for &fid in retired { w.u32(fid as usize)?; }
            }
        }
    }
    let mut roots = Vec::new();
    w.u32(vm.funcs.len())?;
    for f in &vm.funcs {
        save_roots(&mut w, &mut roots, &f.consts)?;
    }
    w.u32(vm.heap.shapes.len())?;
    for s in &vm.heap.shapes {
        let mut methods: Vec<_> = s.methods.iter().collect();
        methods.sort_by(|(a, _), (b, _)| vm.bytes_of(**a).cmp(vm.bytes_of(**b)));
        w.u32(methods.len())?;
        for (&k, &v) in methods {
            w.u32(root(&mut roots, k))?;
            w.u32(root(&mut roots, v))?;
        }
    }
    let mut modules: Vec<_> = vm.modules.iter().collect();
    modules.sort_by_key(|(n, _)| *n);
    w.u32(modules.len())?;
    for (n, &f) in modules {
        w.text(n)?;
        w.u32(f as usize)?;
    }
    let mut paths: Vec<_> = vm.module_paths.iter().collect();
    paths.sort_by_key(|(n, _)| *n);
    w.u32(paths.len())?;
    for (n, p) in paths {
        w.text(n)?;
        w.text(p)?;
    }
    let mut loaded: Vec<_> = vm.loaded.iter().collect();
    loaded.sort_by_key(|(n, _)| *n);
    w.u32(loaded.len())?;
    for (n, &v) in loaded {
        w.text(n)?;
        w.u32(root(&mut roots, v))?;
    }
    save_roots(&mut w, &mut roots, &vm.handles)?;
    save_roots(&mut w, &mut roots, &vm.registered)?;
    let mut resources: Vec<_> = vm.resources.iter().collect();
    resources.sort_by_key(|(v, _)| v.0);
    w.u32(resources.len())?;
    for (&v, kind) in resources {
        w.u32(root(&mut roots, v))?;
        w.text(kind)?;
    }
    w.u32(root(&mut roots, vm.loaded_table))?;
    save_roots(&mut w, &mut roots, &vm.extra[..vm.extra_n])?;
    w.u32(vm.last_nres)?;
    w.u64(vm.parks);
    w.u64(vm.random_state);
    match &vm.host {
        None => w.byte(0),
        Some(host) => {
            w.byte(1);
            w.u32(host.threads)?;
            w.u64(host.next);
        }
    }
    let regions = vm
        .tasks
        .iter()
        .any(|t| !t.cleanups.is_empty() || !t.protected.is_empty() || t.error != Value::NIL);
    w.u32(vm.tasks.len())?;
    for t in &vm.tasks {
        if regions {
            w.u32(root(&mut roots, t.error))?;
            w.u32(t.cleanups.len())?;
            for c in &t.cleanups {
                w.u32(c.frame)?;
                w.u32(root(&mut roots, c.value))?;
                w.u32(root(&mut roots, c.callback))?;
            }
            w.u32(t.protected.len())?;
            for h in &t.protected {
                // An xpcall record marks its caller word and adds the
                // handler; a pcall record is as it always was.
                w.u32(h.frame)?;
                if h.caller >= XPCALL_RECORD {
                    return Err("protected frame out of range".into());
                }
                if h.handler == Value::NIL {
                    w.u32(h.caller)?;
                    w.u32(h.result)?;
                } else {
                    w.u32(h.caller | XPCALL_RECORD)?;
                    w.u32(h.result)?;
                    w.u32(root(&mut roots, h.handler))?;
                }
            }
        }
        match t.state {
            State::Runnable => w.byte(0),
            State::Parked(key) => {
                w.byte(1);
                w.u32(root(&mut roots, Value(key)))?;
            }
            State::Done => w.byte(2),
        }
        w.u32(root(&mut roots, t.result))?;
        save_roots(&mut w, &mut roots, &t.results)?;
        w.u32(t.deliver_at)?;
        if t.state == State::Done {
            w.u32(0)?;
            w.u32(0)?;
            w.u32(0)?;
            continue;
        }
        let positions = frame_positions(vm, t)?;
        let mut words = t.stack[..positions.0].to_vec();
        for &at in &positions.1 {
            let mut v = Value(words[at]);
            // Dead registers can retain tombstones after a collection. They
            // are not logical state; the collector filters them the same way.
            if v.as_obj().is_some_and(|p| !vm.heap.is_live_slot(p)) {
                v = Value::NIL;
            }
            words[at] = root(&mut roots, v) as u64;
        }
        w.u32(t.cur())?;
        w.u32(words.len())?;
        for word in words {
            w.u64(word);
        }
        w.u32(positions.1.len())?;
        for at in positions.1 {
            w.u32(at)?;
        }
    }
    let graph = save_graph_with(vm, &roots, policies, Some(codecs), true)?;
    w.bytes(&graph)?;
    if let Some(s) = &vm.scheduler {
        write_scheduler(&mut w, s)?;
    }
    frame(if regions { 2 } else { 1 }, w.0)
}

// Optional scheduler extension after the original VM graph. Readers accept
// older checkpoints without it; older readers reject the trailing extension.
fn write_scheduler(w: &mut Writer, s: &crate::scheduler::Scheduler) -> Result<()> {
    use crate::scheduler::Status;
    w.byte(2);
    w.u64(s.now);
    w.u64(s.next_timer);
    w.u64(s.next_generation);
    w.u32(s.free.len())?;
    for &tid in &s.free {
        w.u32(tid)?;
    }
    w.u32(s.ready.len())?;
    for &tid in &s.ready {
        w.u32(tid)?;
    }
    w.u32(s.controls.len())?;
    for (&tid, c) in &s.controls {
        w.u32(tid)?;
        w.u64(c.generation);
        match &c.status {
            Status::Active => w.byte(0),
            Status::Completed => w.byte(1),
            Status::Cancelled => w.byte(2),
            Status::Failed(e) => {
                w.byte(3);
                w.text(e)?;
            }
        }
        w.byte(c.token.requested() as u8);
        for at in [c.deadline, c.wake] {
            match at {
                Some(n) => {
                    w.byte(1);
                    w.u64(n);
                }
                None => w.byte(0),
            }
        }
        w.u32(c.last_nres)?;
        if let Some(task) = c.waiting {
            w.byte(1);
            w.u32(task.index)?;
            w.u64(task.generation);
        } else {
            w.byte(0);
        }
    }
    Ok(())
}
fn read_scheduler(r: &mut Reader) -> Result<Option<crate::scheduler::Scheduler>> {
    use crate::scheduler::{Cancellation, Control, Scheduler, Status};
    if r.at == r.data.len() {
        return Ok(None);
    }
    let version = r.byte()?;
    if version != 1 && version != 2 {
        return Err("unsupported scheduler checkpoint extension".into());
    }
    let mut s = Scheduler::default();
    s.now = r.u64()?;
    s.next_timer = r.u64()?;
    s.next_generation = r.u64()?;
    if s.next_generation == 0 {
        return Err("invalid task generation sequence".into());
    }
    for _ in 0..r.count()? {
        s.free.push(r.u32()?);
    }
    if s.next_timer == 0 || s.next_timer > (1 << 63) {
        return Err("invalid scheduler timer sequence".into());
    }
    for _ in 0..r.count()? {
        s.ready.push_back(r.u32()?);
    }
    for _ in 0..r.count()? {
        let tid = r.u32()?;
        let generation = r.u64()?;
        let status = match r.byte()? {
            0 => Status::Active,
            1 => Status::Completed,
            2 => Status::Cancelled,
            3 => Status::Failed(r.text()?),
            _ => return Err("invalid scheduler status".into()),
        };
        let token = Cancellation::default();
        match r.byte()? {
            0 => {}
            1 => token.cancel(),
            _ => return Err("invalid cancellation flag".into()),
        }
        let mut times = [None; 2];
        for (kind, time) in times.iter_mut().enumerate() {
            match r.byte()? {
                0 => {}
                1 => {
                    let at = r.u64()?;
                    *time = Some(at);
                    s.timers.insert((at, kind as u8, tid));
                }
                _ => return Err("invalid scheduler timer".into()),
            }
        }
        let last_nres = r.u32()?;
        if last_nres > crate::interp::MAX_RESULTS {
            return Err("invalid scheduler result count".into());
        }
        let waiting = if version == 2 {
            match r.byte()? {
                0 => None,
                1 => Some(crate::scheduler::TaskId {
                    index: r.u32()?,
                    generation: r.u64()?,
                }),
                _ => return Err("invalid wait tag".into()),
            }
        } else {
            None
        };
        if s.controls
            .insert(
                tid,
                Control {
                    generation,
                    token,
                    status,
                    deadline: times[0],
                    wake: times[1],
                    last_nres,
                    waiting,
                },
            )
            .is_some()
        {
            return Err("duplicate scheduler task".into());
        }
    }
    Ok(Some(s))
}

// Exact value locations in live frames; typed numeric/vector words remain raw.
fn frame_positions(vm: &Interp, t: &Task) -> Result<(usize, Vec<usize>)> {
    let mut s = t.cur();
    let mut positions = Vec::new();
    let mut high = 0;
    loop {
        let header = t
            .stack
            .get(s..s.checked_add(HDR).ok_or("frame overflow")?)
            .ok_or("truncated frame")?;
        let f = vm
            .funcs
            .get((header[0] & 0xffff_ffff) as usize)
            .ok_or("invalid frame function")?;
        let pc = (header[0] >> 32) as usize;
        if pc >= f.code.len() {
            return Err("invalid saved program counter".into());
        }
        let words = ((header[3] >> 33) & 0xffff) as usize;
        let nvar = (header[3] >> 49) as usize;
        if words != f.frame_words()
            || nvar > s
            || s + words > t.stack.len()
            || (!f.vararg && nvar != 0)
        {
            return Err("invalid frame layout".into());
        }
        high = high.max(s + words);
        positions.extend(s - nvar..s);
        positions.push(s + 2);
        positions.extend(s + HDR..s + HDR + f.nregs as usize + 1);
        let caller = (header[1] & 0xffff_ffff) as u32;
        if caller == u32::MAX {
            if s != nvar {
                return Err("invalid entry frame offset".into());
            }
            break;
        }
        if caller as usize >= s - nvar {
            return Err("invalid frame caller chain".into());
        }
        let caller_header = t
            .stack
            .get(caller as usize..caller as usize + HDR)
            .ok_or("invalid caller header")?;
        let caller_f = vm
            .funcs
            .get((caller_header[0] & 0xffff_ffff) as usize)
            .ok_or("invalid caller function")?;
        if caller as usize + caller_f.frame_words() != s - nvar {
            return Err("overlapping or missing frame".into());
        }
        let ret = (header[1] >> 32) as usize;
        if ret < caller as usize + HDR || ret > caller as usize + HDR + caller_f.nregs as usize {
            return Err("invalid return register".into());
        }
        if header[3] & (1 << 32) != 0 {
            let retf = (header[3] & 0xffff_ffff) as usize;
            if retf < caller as usize + caller_f.off_f()
                || retf >= caller as usize + caller_f.off_f() + caller_f.nfreg as usize
            {
                return Err("invalid float return register".into());
            }
        }
        s = caller as usize;
    }
    positions.sort_unstable();
    positions.dedup();
    Ok((high, positions))
}

/// Restore into a new VM, never overwriting a running VM. Image loading does
/// not execute module initializers. Code is verified, graph edges relocated,
/// then host resources rebound before the caller can resume any task.
pub fn load_vm(data: &[u8], policies: &Policies, codecs: &mut ResourceCodecs) -> Result<Interp> {
    load_vm_channels(data,policies,codecs,Default::default())
}
pub(crate) fn load_vm_channels(data: &[u8], policies: &Policies, codecs: &mut ResourceCodecs, registry:crate::channels::Shared) -> Result<Interp> {
    load_vm_channels_mode(data, policies, codecs, registry, false)
}
// An unstarted worker has no host pool or native provider effects. Do not open
// resources or start host threads while validating its queued snapshot.
pub(crate) fn load_queued_worker_vm(data: &[u8], registry: crate::channels::Shared) -> Result<Interp> {
    load_vm_channels_mode(data, &Policies::default(), &mut ResourceCodecs::default(), registry, true)
}
fn load_vm_channels_mode(data: &[u8], policies: &Policies, codecs: &mut ResourceCodecs, registry:crate::channels::Shared, queued: bool) -> Result<Interp> {
    policies.checkpoint_safe()?;
    let regions = data.get(8) == Some(&2);
    let mut r = Reader {
        data: unframe(data, if regions { 2 } else { 1 })?,
        at: 0,
    };
    let digest: [u8; 32] = r.take(32)?.try_into().unwrap();
    let mut vm = Interp::new();
    vm.channel_registry=registry;
    codecs.insert(crate::channels::KIND.into(),Box::new(crate::channels::Codec {registry:vm.channel_registry.clone(),transfer:false}));
    if !queued { crate::snapshot::install_codecs(codecs); }
    let n = r.count()?;
    for _ in 0..n {
        match r.byte()? {
            0 => {
                let s = r.text()?;
                std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    crate::image::load(&mut vm, &s)
                }))
                .map_err(|_| "malformed checkpoint code image")??;
            }
            1 => vm.install_globals(),
            2 => {
                let patch = r.bytes()?.to_vec();
                let added = r.u32()? as u32;
                let n = r.count()?;
                let mut retired = Vec::with_capacity(n);
                for _ in 0..n { retired.push(r.u32()? as u32); }
                std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| crate::hotpatch::replay(&mut vm, &patch, &retired)))
                    .map_err(|_| "malformed checkpoint code patch")??;
                vm.code_events.push(CodeEvent::Patch { patch, retired, added });
            }
            3 => {
                let bytes = r.bytes()?.to_vec();
                std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| crate::graph::load(&mut vm, &bytes)))
                    .map_err(|_| "malformed checkpoint graph image")??;
            }
            _ => return Err("unknown code recipe".into()),
        }
    }
    if code_digest(&vm)? != digest {
        return Err("checkpoint compiler/code digest mismatch".into());
    }
    let n = r.count()?;
    if n != vm.funcs.len() {
        return Err("function count mismatch".into());
    }
    let mut constants = Vec::new();
    for _ in 0..n {
        constants.push(read_ids(&mut r)?);
    }
    let n = r.count()?;
    let mut methods = Vec::new();
    for _ in 0..n {
        let n = r.count()?;
        let mut m = Vec::new();
        for _ in 0..n {
            m.push((r.u32()?, r.u32()?));
        }
        methods.push(m);
    }
    let n = r.count()?;
    let mut modules = HashMap::new();
    for _ in 0..n {
        let name = r.text()?;
        let f = r.u32()?;
        if f >= vm.funcs.len() {
            return Err("module function out of bounds".into());
        }
        if modules.insert(name, f as u32).is_some() {
            return Err("duplicate module".into());
        }
    }
    let n = r.count()?;
    let mut paths = HashMap::new();
    for _ in 0..n {
        paths.insert(r.text()?, r.text()?);
    }
    let n = r.count()?;
    let mut loaded = Vec::new();
    for _ in 0..n {
        loaded.push((r.text()?, r.u32()?));
    }
    let handles = read_ids(&mut r)?;
    let registered = read_ids(&mut r)?;
    let n = r.count()?;
    let mut resources = Vec::new();
    for _ in 0..n {
        resources.push((r.u32()?, r.text()?));
    }
    let loaded_table = r.u32()?;
    let extra = read_ids(&mut r)?;
    if extra.len() >= crate::interp::MAX_RESULTS {
        return Err("invalid result buffer".into());
    }
    let last_nres = r.u32()?;
    if last_nres > crate::interp::MAX_RESULTS { return Err("invalid result count".into()); }
    let parks = r.u64()?;
    let random_state = r.u64()?;
    let host = match r.byte()? {
        0 => None,
        1 => {
            let threads = r.u32()?;
            let next = r.u64()?;
            if threads == 0 || threads > 64 || next == 0 {
                return Err("invalid host pool state".into());
            }
            Some((threads, next))
        }
        _ => return Err("invalid host pool tag".into()),
    };
    let n = r.count()?;
    let mut tasks = Vec::new();
    for _ in 0..n {
        let error = if regions {
            Value(r.u32()? as u64)
        } else {
            Value::NIL
        };
        let mut cleanups = Vec::new();
        let mut protected = Vec::new();
        if regions {
            for _ in 0..r.count()? {
                cleanups.push(crate::interp::Cleanup {
                    frame: r.u32()?,
                    value: Value(r.u32()? as u64),
                    callback: Value(r.u32()? as u64),
                });
            }
        }
        if regions {
            for _ in 0..r.count()? {
                let frame = r.u32()?;
                let caller = r.u32()?;
                let result = r.u32()?;
                let handler = if caller & XPCALL_RECORD != 0 {
                    Value(r.u32()? as u64)
                } else {
                    Value::NIL
                };
                protected.push(crate::interp::Protected {
                    frame,
                    caller: caller & !XPCALL_RECORD,
                    result,
                    handler,
                });
            }
        }
        let state = match r.byte()? {
            0 => State::Runnable,
            1 => State::Parked(r.u32()? as u64),
            2 => State::Done,
            _ => return Err("invalid task state".into()),
        };
        let result = r.u32()?;
        let results = read_ids(&mut r)?;
        let deliver_at = r.u32()?;
        let cur = r.u32()?;
        let words = r.count()?;
        let mut stack = Vec::new();
        for _ in 0..words {
            stack.push(r.u64()?);
        }
        let positions = read_ids(&mut r)?;
        let mut task = Task::restored(stack, cur, state, deliver_at);
        task.error = error;
        task.cleanups = cleanups;
        task.protected = protected;
        if state != State::Done {
            let expected = frame_positions(&vm, &task)?;
            if expected.0 != task.stack.len() || expected.1 != positions {
                return Err("invalid frame relocation map".into());
            }
            let f = &vm.funcs[(task.stack[cur] & 0xffff_ffff) as usize];
            if deliver_at > f.nregs as usize {
                return Err("invalid completion register".into());
            }
        } else if !task.stack.is_empty() || cur != 0 || !positions.is_empty() {
            return Err("done task has a stack".into());
        }
        task.result = Value(result as u64);
        tasks.push((task, results, positions));
    }
    let graph = r.bytes()?;
    let scheduler = read_scheduler(&mut r)?;
    r.done()?;
    if queued && host.is_some() { return Err("queued worker checkpoint has a host pool".into()); }
    let roots = load_graph_with(&mut vm, graph, policies, None, Some(codecs), true, None)?;
    // Publish every root before doing anything that can allocate in the heap.
    let mut new_handles = get_roots(&roots, &handles)?;
    new_handles.extend_from_slice(&roots);
    vm.handles = new_handles;
    for (f, ids) in vm.funcs.iter_mut().zip(constants) {
        if ids.len() != f.consts.len() {
            return Err("constant count mismatch".into());
        }
        f.consts = get_roots(&roots, &ids)?;
    }
    if methods.len() != vm.heap.shapes.len() {
        return Err("shape count mismatch".into());
    }
    for (s, pairs) in vm.heap.shapes.iter_mut().zip(methods) {
        s.methods.clear();
        for (k, v) in pairs {
            s.methods.insert(get_root(&roots, k)?, get_root(&roots, v)?);
        }
    }
    vm.modules = modules;
    vm.module_paths = paths;
    vm.loaded.clear();
    for (n, v) in loaded {
        vm.loaded.insert(n, get_root(&roots, v)?);
    }
    vm.forget_loaded_lookups();
    vm.registered = get_roots(&roots, &registered)?;
    vm.loaded_table = get_root(&roots, loaded_table)?;
    vm.extra_n = extra.len();
    for (i, v) in get_roots(&roots, &extra)?.into_iter().enumerate() {
        vm.extra[i] = v;
    }
    vm.last_nres = last_nres;
    vm.parks = parks;
    vm.random_state = random_state;
    vm.resources.clear();
    for (id, kind) in resources {
        if kind != crate::channels::KIND { vm.resources.insert(get_root(&roots, id)?, kind); }
    }
    for (mut t, results, positions) in tasks {
        t.result = get_root(&roots, t.result.0 as usize)?;
        if regions {
            t.error = get_root(&roots, t.error.0 as usize)?;
        }
        t.results = get_roots(&roots, &results)?;
        if let State::Parked(id) = t.state {
            t.state = State::Parked(get_root(&roots, id as usize)?.0);
        }
        for at in positions {
            t.stack[at] = get_root(&roots, t.stack[at] as usize)?.0;
        }
        let mut frames = std::collections::BTreeSet::new();
        if t.state != State::Done {
            let mut at = t.cur();
            loop {
                frames.insert(at);
                let caller = t.stack[at + 1] as u32;
                if caller == u32::MAX {
                    break;
                }
                at = caller as usize;
            }
        }
        let mut previous = None;
        for h in &t.protected {
            if !frames.contains(&h.frame)
                || !frames.contains(&h.caller)
                || h.frame < h.caller
                || (h.frame == h.caller
                    && (h.frame != t.cur()
                        || !matches!(t.state, State::Parked(_))
                        || h.result + 1 != h.frame + HDR + t.deliver_at))
                || previous.is_some_and(|p| h.frame <= p)
            {
                return Err("invalid protected frame".into());
            }
            let f = &vm.funcs[t.stack[h.caller] as u32 as usize];
            if h.result < h.caller + HDR || h.result + 1 > h.caller + HDR + f.nregs as usize {
                return Err("invalid protected result".into());
            }
            previous = Some(h.frame);
        }
        for h in &mut t.protected {
            if h.handler != Value::NIL {
                h.handler = get_root(&roots, h.handler.0 as usize)?;
            }
        }
        let mut previous = 0;
        for c in &mut t.cleanups {
            if !frames.contains(&c.frame) || c.frame < previous {
                return Err("invalid cleanup frame".into());
            }
            previous = c.frame;
            c.value = get_root(&roots, c.value.0 as usize)?;
            c.callback = get_root(&roots, c.callback.0 as usize)?;
            if c.value != Value::NIL
                && c.callback.as_func().is_none()
                && c.callback.as_builtin().is_none()
                && !c
                    .callback
                    .as_obj()
                    .is_some_and(|p| unsafe { p.as_ref().kind == crate::heap::KIND_CLOSURE })
            {
                return Err("invalid cleanup callback".into());
            }
        }
        vm.tasks.push(t);
    }
    if let Some(s) = &scheduler {
        s.validate(&vm)?;
    }
    vm.scheduler = scheduler;
    vm.handles.truncate(handles.len());
    vm.entries = vec![0; vm.funcs.len()];
    vm.prepare_threaded();
    if let Some((threads, next)) = host {
        let mut host = crate::host::Host::start(threads);
        host.next = next;
        vm.host = Some(host);
    }

    if let Some(&clock) = vm.loaded.get("nupp.vm.clock") {
        let saved = crate::task_api::field(&mut vm, clock, "_checkpointNow");
        if !saved.is_num() || !saved.as_num().is_finite() || saved.as_num() < 0.0 {
            return Err("invalid monotonic clock checkpoint".into());
        }
        vm.clock.restore(saved.as_num());
    }
    Ok(vm)
}

#[cfg(test)]
mod primary_image_digest_tests {
    use super::primary_image_digest;
    use sha2::{Digest, Sha256};

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|byte| format!("{byte:02x}")).collect()
    }

    #[test]
    fn raw_primary_image_hash_matches_standard_vectors() {
        for (input, expected) in [
            (
                &b""[..],
                "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            ),
            (
                &b"abc"[..],
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            ),
            (
                &b"a\0b"[..],
                "59b271ae1bbcb1d31d41929817f4b16fb439eb4f31520b5ad1d5ce98920a7138",
            ),
        ] {
            assert_eq!(hex(&primary_image_digest(input)), expected);
        }
    }

    #[test]
    fn raw_primary_image_hash_matches_sha2_at_padding_and_binary_boundaries() {
        for length in [
            1, 2, 3, 31, 32, 55, 56, 63, 64, 65, 119, 120, 127, 128, 129, 1024, 65537,
        ] {
            let bytes: Vec<u8> = (0..length).map(|i| (i * 37 + 129) as u8).collect();
            let expected: [u8; 32] = Sha256::digest(&bytes).into();
            assert_eq!(primary_image_digest(&bytes), expected, "{length} bytes");
        }
        let unicode = "image λ 🦀\0é\r\n".as_bytes();
        let expected: [u8; 32] = Sha256::digest(unicode).into();
        assert_eq!(primary_image_digest(unicode), expected);
    }
}

#[cfg(test)]
mod canonical_integer_tests {
    use super::*;

    #[test]
    fn integer_nodes_require_canonical_signed_flag_and_wide_payload() {
        let mut bytes = vec![KIND_INTEGER, 0];
        bytes.extend_from_slice(&i64::MAX.to_le_bytes());
        let mut reader = Reader { data: &bytes, at: 0 };
        assert!(matches!(node_read(&mut reader).unwrap(), Node::Integer(i) if i.bits == i64::MAX as u64 && !i.unsigned));
        bytes[1] = 1;
        let mut reader = Reader { data: &bytes, at: 0 };
        assert!(matches!(node_read(&mut reader), Err(e) if e.contains("invalid integer kind")));
        bytes[1] = 0;
        bytes[2..].copy_from_slice(&u64::MAX.to_le_bytes());
        let mut reader = Reader { data: &bytes, at: 0 };
        assert!(matches!(node_read(&mut reader), Err(e) if e.contains("noncanonical boxed integer")));
    }
}
