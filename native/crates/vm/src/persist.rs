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

pub type Result<T> = std::result::Result<T, String>;
const MAGIC: &[u8; 8] = b"NUPPSAV1";
const LIMIT: usize = 256 * 1024 * 1024;
const ITEMS: usize = 4_000_000;

#[derive(Clone, Debug)]
pub(crate) enum CodeEvent {
    Image(String),
    Globals,
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
}
#[derive(Default)]
pub struct Policies {
    pub shapes: HashMap<String, ShapePolicy>,
}
impl Policies {
    fn name(&self, name: &str) -> String {
        self.shapes
            .get(name)
            .and_then(|p| p.name.clone())
            .unwrap_or_else(|| name.into())
    }
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
            CodeEvent::Globals => h.update([1]),
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
                if o.kind != KIND_STR {
                    return Err("non-string object in function constants".into());
                }
                h.update([1]);
                h.update((o.bytes().len() as u64).to_le_bytes());
                h.update(o.bytes());
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
    vm.heap
        .shapes
        .iter()
        .map(|s| Schema {
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
        })
        .collect()
}
fn schema_write(w: &mut Writer, ss: &[Schema]) -> Result<()> {
    w.u32(ss.len())?;
    for s in ss {
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
fn schema_read(r: &mut Reader) -> Result<Vec<Schema>> {
    let n = r.count()?;
    let mut ss = Vec::new();
    for _ in 0..n {
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
    String(bool, &'a [u8]),
    Table(Vec<Ref>, Vec<Ref>, Ref),
    Record(usize, Vec<Ref>, Vec<Ref>, Vec<Ref>),
    Storage(&'a [u8]),
    Closure(usize, Vec<Ref>),
    Cell(Ref),
    Bytes(&'a [u8]),
    Iter(u8, usize, Ref, Ref, Vec<Ref>),
    Slice(Ref, usize, usize),
    Resource(String, &'a [u8]),
}
fn node_read<'a>(r: &mut Reader<'a>) -> Result<Node<'a>> {
    Ok(match r.byte()? {
        KIND_STR => {
            let interned = match r.byte()? {
                0 => false,
                1 => true,
                _ => return Err("invalid string flag".into()),
            };
            let b = r.bytes()?;
            Node::String(interned, b)
        }
        KIND_TABLE => Node::Table(refs_read(r)?, refs_read(r)?, Ref::read(r)?),
        KIND_RECORD => Node::Record(r.u32()?, refs_read(r)?, refs_read(r)?, refs_read(r)?),
        KIND_STORAGE => {
            let b = r.bytes()?;
            if b.len() % 8 != 0 {
                return Err("unaligned storage span".into());
            }
            Node::Storage(b)
        }
        KIND_CLOSURE => Node::Closure(r.u32()?, refs_read(r)?),
        KIND_CELL => Node::Cell(Ref::read(r)?),
        KIND_BYTES => Node::Bytes(r.bytes()?),
        KIND_ITER => Node::Iter(
            r.byte()?,
            r.u32()?,
            Ref::read(r)?,
            Ref::read(r)?,
            refs_read(r)?,
        ),
        KIND_SLICE => Node::Slice(Ref::read(r)?, r.u32()?, r.u32()?),
        10 => Node::Resource(r.text()?, r.bytes()?),
        _ => return Err("unknown object kind".into()),
    })
}
fn node_refs<'a>(n: &'a Node) -> Vec<&'a Ref> {
    match n {
        Node::Table(a, b, m) => a.iter().chain(b).chain(std::iter::once(m)).collect(),
        Node::Record(_, a, b, c) => a.iter().chain(b).chain(c).collect(),
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
    save_graph_with(vm, roots, policies, None)
}
fn save_graph_with(
    vm: &mut Interp,
    roots: &[Value],
    policies: &Policies,
    mut codecs: Option<&mut ResourceCodecs>,
) -> Result<Vec<u8>> {
    let scope = vm.open_scope();
    vm.handles.extend_from_slice(roots);
    let result = (|| {
        let mut graph = GraphWriter::new();
        graph.roots = graph.values(vm, roots)?;
        let mut payload = Writer(vec![0; 33]);
        schema_write(&mut payload, &schemas(vm, policies))?;
        refs_write(&mut payload, &graph.roots)?;
        let count_at = payload.0.len();
        payload.u32(0)?;
        let mut index = 0;
        let mut rooted = 0;
        while index < graph.objects.len() {
            let v = graph.objects[index];
            if let Some(kind) = vm.resources.get(&v).cloned() {
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
            let p = v.as_obj().unwrap();
            let kind = unsafe { p.as_ref().kind };
            if kind == KIND_RECORD {
                let name = vm.heap.shapes[unsafe { p.as_ref().shape() } as usize]
                    .name
                    .clone();
                if let Some(hook) = policies.shapes.get(&name).and_then(|p| p.before_save) {
                    hook(vm, v)?;
                }
            }
            let h = unsafe { p.as_ref() };
            payload.byte(h.kind);
            // Use the collector's edge enumeration to discover every ordinary
            // reference. Transient records use their filtered edge list below.
            if kind != KIND_RECORD {
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
                    graph.value(vm, t.meta)?.write(&mut payload)?
                }
                KIND_RECORD => {
                    payload.u32(h.shape() as usize)?;
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
                    refs_write(&mut payload, &graph.values(vm, &extra)?)?
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
                KIND_BYTES => payload.bytes(h.bytes())?,
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
    let mut r = Reader {
        data: unframe(data, 0)?,
        at: 0,
    };
    let functions = match r.byte()? {
        0 => false,
        1 => true,
        _ => return Err("invalid function flag".into()),
    };
    let digest = r.take(32)?.try_into().unwrap();
    let schemas = schema_read(&mut r)?;
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
            .find(|&&id| id == ids.len())
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
            Node::Record(s, slots, _, extra) => {
                let schema = g.schemas.get(*s).ok_or("record shape out of bounds")?;
                if slots.len() != schema.fields.len() || extra.len() % 2 != 0 {
                    return Err("invalid record payload".into());
                }
            }
            Node::Table(_, pairs, meta) => {
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
        let pairs = match n {
            Node::Table(_, p, _) | Node::Record(_, _, _, p) => Some(p),
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
        SlotTy::Num => v.is_num(),
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
    let out = load_graph_with(
        vm,
        data,
        policies,
        Some(SlotTy::Record(h.shape())),
        None,
        false,
        Some(target),
    )?;
    Ok(out[0])
}
fn load_graph_with(
    vm: &mut Interp,
    data: &[u8],
    policies: &Policies,
    expected: Option<SlotTy>,
    mut codecs: Option<&mut ResourceCodecs>,
    create: bool,
    target: Option<Value>,
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
        loop {
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
        let shape_ids = bind_schemas(vm, &g.schemas, policies, create, &required)?;
        for node in &g.nodes {
            if let Node::Record(s, fields, ..) = node {
                let shape = &vm.heap.shapes[shape_ids[*s] as usize];
                for (index, value) in fields.iter().enumerate() {
                    let field = String::from_utf8_lossy(vm.bytes_of(shape.names[index]));
                    let deferred = matches!(value, Ref::Bits(n) if *n == Value::NIL.0)
                        && policies.shapes.get(&shape.name).is_some_and(|p| {
                            p.transient.contains(field.as_ref()) && p.after_load.is_some()
                        });
                    let fits = match shape.types[index] {
                        SlotTy::Any => true,
                        SlotTy::Num => matches!(value, Ref::Bits(n) if Value(*n).is_num()),
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
                    Node::Table(array, pairs, _) => {
                        vm.new_table_sized(array.len(), pairs.len() / 2)
                    }
                    Node::Resource(..) => vm.new_table(),
                    Node::Record(s, ..) => vm.new_record(shape_ids[*s]),
                    Node::Bytes(b) => {
                        let v = vm.heap_new_bytes(b.len());
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
            let h = unsafe { &mut *p.as_ptr() };
            let before = h.external_bytes();
            match n {
                Node::Table(array, pairs, meta) => {
                    let t = h.table();
                    t.array.extend(resolve_all(array, &objects)?);
                    t.meta = resolve(meta, &objects)?;
                    for pair in pairs.chunks_exact(2) {
                        t.hash
                            .insert(resolve(&pair[0], &objects)?, resolve(&pair[1], &objects)?);
                    }
                    h.refresh();
                }
                Node::Record(_, slots, array, extra) => {
                    h.slots_mut()
                        .copy_from_slice(&resolve_all(slots, &objects)?);
                    *h.record_array() = resolve_all(array, &objects)?;
                    *h.record_extra() = None;
                    if !extra.is_empty() {
                        let mut table = ValueTable::new();
                        for pair in extra.chunks_exact(2) {
                            table
                                .insert(resolve(&pair[0], &objects)?, resolve(&pair[1], &objects)?);
                        }
                        *h.record_extra() = Some(Box::new(table));
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
        for (i, n) in g.nodes.iter().enumerate() {
            let v = objects[i];
            match n {
                Node::Record(s, ..) => {
                    let name = &vm.heap.shapes[shape_ids[*s] as usize].name;
                    if let Some(hook) = policies.shapes.get(name).and_then(|p| p.after_load) {
                        hook(vm, v)?;
                    }
                }
                Node::Resource(kind, data) => {
                    codecs
                        .as_deref_mut()
                        .unwrap()
                        .get_mut(kind)
                        .unwrap()
                        .restore(vm, v, data)?;
                    vm.resources.insert(v, kind.clone());
                }
                _ => {}
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

fn safepoint(vm: &Interp) -> Result<()> {
    if vm.execution_depth.get() != 0 || vm.pending_error.is_some() {
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
    safepoint(vm)?;
    let recorded: usize = vm
        .code_events
        .iter()
        .map(|e| match e {
            CodeEvent::Image(s) => s
                .lines()
                .filter(|l| l.trim_start().starts_with("function "))
                .count(),
            CodeEvent::Globals => 2,
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
            CodeEvent::Globals => w.byte(1),
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
    match &vm.host {
        None => w.byte(0),
        Some(host) => {
            w.byte(1);
            w.u32(host.threads)?;
            w.u64(host.next);
        }
    }
    w.u32(vm.tasks.len())?;
    for t in &vm.tasks {
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
    let graph = save_graph_with(vm, &roots, policies, Some(codecs))?;
    w.bytes(&graph)?;
    frame(1, w.0)
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
    let mut r = Reader {
        data: unframe(data, 1)?,
        at: 0,
    };
    let digest: [u8; 32] = r.take(32)?.try_into().unwrap();
    let mut vm = Interp::new();
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
    if extra.len() > 8 {
        return Err("invalid result buffer".into());
    }
    let last_nres = r.u32()?;
    let parks = r.u64()?;
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
    r.done()?;
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
    vm.registered = get_roots(&roots, &registered)?;
    vm.loaded_table = get_root(&roots, loaded_table)?;
    vm.extra_n = extra.len();
    for (i, v) in get_roots(&roots, &extra)?.into_iter().enumerate() {
        vm.extra[i] = v;
    }
    vm.last_nres = last_nres;
    vm.parks = parks;
    vm.resources.clear();
    for (id, kind) in resources {
        vm.resources.insert(get_root(&roots, id)?, kind);
    }
    for (mut t, results, positions) in tasks {
        t.result = get_root(&roots, t.result.0 as usize)?;
        t.results = get_roots(&roots, &results)?;
        if let State::Parked(id) = t.state {
            t.state = State::Parked(get_root(&roots, id as usize)?.0);
        }
        for at in positions {
            t.stack[at] = get_root(&roots, t.stack[at] as usize)?.0;
        }
        vm.tasks.push(t);
    }
    vm.handles.truncate(handles.len());
    vm.entries = vec![0; vm.funcs.len()];
    vm.prepare_threaded();
    if let Some((threads, next)) = host {
        let mut host = crate::host::Host::start(threads);
        host.next = next;
        vm.host = Some(host);
    }
    Ok(vm)
}
