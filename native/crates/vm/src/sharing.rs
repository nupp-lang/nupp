//! Memory across workers: immutable blocks several VMs hold by reference, and
//! owned allocations whose ownership moves from one VM to another.
//!
//! A shared block is one allocation behind an `Arc`. Every VM that holds it
//! has its own bytes owner (`ByteBuffer::Shared`) whose views are read-only,
//! so readers never synchronize; publication and release go through the
//! reference count. A worker crossing (`send`/`receive`) carries the block as
//! an attachment beside the message, which costs the same whatever its size.
//! A checkpoint has no other process to share with, so it writes the bytes
//! and the block's process-unique id; a restore in the same process finds the
//! live block by that id and shares it again, and a restore elsewhere
//! rebuilds it once and registers it, so the restored worker that names the
//! same id shares it too. That is the channel registry's protocol.
//!
//! A moved allocation is a `nupp.mem.heap` array crossing to a worker. The
//! checker consumes the sender's binding; the runtime takes the allocation out
//! of the sender's owner, leaving a `ByteBuffer::Moved` husk that any stale
//! view reports, and the receiver adopts the same allocation. An allocation
//! that never reaches an owner (a delivery that failed after extraction) is
//! freed exactly once when its attachments drop.
use crate::{
    heap::{AlignedBytes, ByteBuffer, KIND_BYTES, KIND_RECORD, KIND_TABLE},
    interp::Interp,
    value::Value,
};
use std::{
    alloc::Layout,
    cell::RefCell,
    collections::{HashMap, HashSet},
    ptr::NonNull,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex, OnceLock, Weak,
    },
};
type Result<T> = std::result::Result<T, String>;

/// A self-contained shared block in a checkpoint: id, alignment, bytes.
pub(crate) const SHARED_BYTES: u8 = 32;
/// A shared block carried beside a worker message, by attachment index.
pub(crate) const ATTACHED_SHARED: u8 = 33;
/// A moved allocation carried beside a worker message, by attachment index.
pub(crate) const ATTACHED_MOVED: u8 = 34;
/// The husk a moved allocation left behind.
pub(crate) const MOVED_BYTES: u8 = 35;

const OWNER_KEY: &str = "\0nupp:storage:owner";
const ARRAY_IDENTITY: &str = "nupp.mem.heap:Array";

/// An immutable allocation shared between VMs. The last holder frees it.
pub struct Block {
    pointer: NonNull<u8>,
    length: usize,
    layout: Layout,
    id: (u64, u64),
}
// Nothing writes a block's bytes after it is published.
unsafe impl Send for Block {}
unsafe impl Sync for Block {}
impl Drop for Block {
    fn drop(&mut self) {
        unsafe { std::alloc::dealloc(self.pointer.as_ptr(), self.layout) }
    }
}
impl Block {
    /// Takes an owned allocation over as a block, without copying it.
    fn adopt(bytes: AlignedBytes) -> Self {
        let (pointer, length, layout) = bytes.into_raw();
        Self { pointer, length, layout, id: next_id() }
    }
    fn copy_of(bytes: &[u8], alignment: usize, id: (u64, u64)) -> Result<Self> {
        if !alignment.is_power_of_two() || alignment > ByteBuffer::MAX_ALIGNMENT {
            return Err("invalid shared block alignment".into());
        }
        let layout = Layout::from_size_align(bytes.len().max(1), alignment)
            .map_err(|_| "shared block is too large")?;
        let pointer = NonNull::new(unsafe { std::alloc::alloc(layout) })
            .unwrap_or_else(|| std::alloc::handle_alloc_error(layout));
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), pointer.as_ptr(), bytes.len()) };
        Ok(Self { pointer, length: bytes.len(), layout, id })
    }
    pub fn bytes(&self) -> &[u8] {
        unsafe { std::slice::from_raw_parts(self.pointer.as_ptr(), self.length) }
    }
    pub fn pointer(&self) -> *mut u8 {
        self.pointer.as_ptr()
    }
    pub fn len(&self) -> usize {
        self.length
    }
    pub fn is_empty(&self) -> bool {
        self.length == 0
    }
    pub fn alignment(&self) -> usize {
        self.layout.align()
    }
    pub fn capacity(&self) -> usize {
        self.layout.size()
    }
}

/// Process-unique block ids: a random process nonce and a counter, so an id a
/// checkpoint carries from another process cannot name a block of this one.
fn next_id() -> (u64, u64) {
    static NONCE: OnceLock<u64> = OnceLock::new();
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let nonce = *NONCE.get_or_init(|| {
        use std::hash::{BuildHasher, Hasher};
        let mut h = std::collections::hash_map::RandomState::new().build_hasher();
        h.write_u64(std::process::id() as u64);
        h.finish()
    });
    (nonce, COUNTER.fetch_add(1, Ordering::Relaxed))
}

#[derive(Default)]
struct Registry {
    blocks: HashMap<(u64, u64), Weak<Block>>,
    pruned_at: usize,
}
fn registry() -> &'static Mutex<Registry> {
    static REGISTRY: OnceLock<Mutex<Registry>> = OnceLock::new();
    REGISTRY.get_or_init(Default::default)
}
/// Makes a checkpointed block findable by its id while anything holds it.
fn publish(block: &Arc<Block>) {
    let mut r = registry().lock().unwrap();
    if r.blocks.len() >= 2 * r.pruned_at.max(32) {
        r.blocks.retain(|_, b| b.strong_count() > 0);
        r.pruned_at = r.blocks.len();
    }
    r.blocks.insert(block.id, Arc::downgrade(block));
}
fn find(id: (u64, u64)) -> Option<Arc<Block>> {
    registry().lock().unwrap().blocks.get(&id).and_then(Weak::upgrade)
}

/// What a worker message carries beside its graph bytes.
#[derive(Default)]
pub struct Attachments {
    shared: Vec<Arc<Block>>,
    moved: Vec<Option<AlignedBytes>>,
}
impl Attachments {
    pub fn is_empty(&self) -> bool {
        self.shared.is_empty() && self.moved.is_empty()
    }
    /// The self-contained form a checkpoint keeps of attachments still in
    /// flight: each shared block as a checkpoint writes one, each moved
    /// allocation as its bytes.
    pub(crate) fn write(&self, out: &mut Vec<u8>) {
        out.extend((self.shared.len() as u64).to_le_bytes());
        for block in &self.shared {
            publish(block);
            let payload = shared_payload(block);
            out.extend((payload.len() as u64).to_le_bytes());
            out.extend(payload);
        }
        out.extend((self.moved.len() as u64).to_le_bytes());
        for moved in &self.moved {
            match moved {
                Some(a) => {
                    out.push(1);
                    out.extend((a.alignment() as u32).to_le_bytes());
                    out.extend((a.len() as u64).to_le_bytes());
                    out.extend(a.bytes());
                }
                None => out.push(0),
            }
        }
    }
    pub(crate) fn read(mut data: &[u8]) -> Result<Self> {
        fn take<'a>(b: &mut &'a [u8], n: usize) -> Result<&'a [u8]> {
            if b.len() < n {
                return Err("truncated attachments".into());
            }
            let (head, tail) = b.split_at(n);
            *b = tail;
            Ok(head)
        }
        fn count(b: &mut &[u8]) -> Result<usize> {
            let n = u64::from_le_bytes(take(b, 8)?.try_into().unwrap());
            usize::try_from(n).map_err(|_| "attachment too large".into())
        }
        let mut a = Attachments::default();
        for _ in 0..count(&mut data)? {
            let n = count(&mut data)?;
            a.shared.push(shared_block(take(&mut data, n)?)?);
        }
        for _ in 0..count(&mut data)? {
            if take(&mut data, 1)?[0] == 0 {
                a.moved.push(None);
                continue;
            }
            let alignment = u32::from_le_bytes(take(&mut data, 4)?.try_into().unwrap()) as usize;
            let n = count(&mut data)?;
            let bytes = take(&mut data, n)?;
            if !alignment.is_power_of_two() || alignment > ByteBuffer::MAX_ALIGNMENT {
                return Err("invalid attachment alignment".into());
            }
            let mut buffer = ByteBuffer::aligned(n, alignment);
            buffer.copy_from_slice(bytes);
            let ByteBuffer::Aligned(owned) = buffer else { unreachable!() };
            a.moved.push(Some(owned));
        }
        if !data.is_empty() {
            return Err("trailing attachment data".into());
        }
        Ok(a)
    }
}
fn shared_payload(block: &Block) -> Vec<u8> {
    let mut b = Vec::with_capacity(20 + block.len());
    b.extend(block.id.0.to_le_bytes());
    b.extend(block.id.1.to_le_bytes());
    b.extend((block.alignment() as u32).to_le_bytes());
    b.extend(block.bytes());
    b
}
/// The live block a checkpoint's payload names, or a new one holding its bytes.
fn shared_block(data: &[u8]) -> Result<Arc<Block>> {
    if data.len() < 20 {
        return Err("truncated shared block".into());
    }
    let id = (
        u64::from_le_bytes(data[..8].try_into().unwrap()),
        u64::from_le_bytes(data[8..16].try_into().unwrap()),
    );
    let alignment = u32::from_le_bytes(data[16..20].try_into().unwrap()) as usize;
    let bytes = &data[20..];
    Ok(match find(id).filter(|b| b.bytes() == bytes) {
        Some(b) => b,
        None => {
            let b = Arc::new(Block::copy_of(bytes, alignment, id)?);
            publish(&b);
            b
        }
    })
}

#[derive(Default)]
struct Outbox {
    shared: Vec<Arc<Block>>,
    movable: HashSet<Value>,
    moving: Vec<Value>,
}
thread_local! {
    static OUTBOX: RefCell<Option<Outbox>> = const { RefCell::new(None) };
    static INBOX: RefCell<Option<Attachments>> = const { RefCell::new(None) };
}

fn buffer(owner: Value) -> &'static mut ByteBuffer {
    unsafe { &mut (*owner.as_obj().unwrap().as_ptr()).byte_buffer().data }
}
fn is_bytes(vm: &Interp, value: Value) -> bool {
    vm.kind_of(value) == Some(KIND_BYTES)
}
/// Whether a bytes owner is a shared block, whose views are read-only.
pub(crate) fn is_shared(vm: &Interp, owner: Value) -> bool {
    is_bytes(vm, owner) && matches!(buffer(owner), ByteBuffer::Shared(_))
}
/// Whether a bytes owner's allocation moved to another VM.
pub(crate) fn is_moved(vm: &Interp, owner: Value) -> bool {
    is_bytes(vm, owner) && matches!(buffer(owner), ByteBuffer::Moved)
}
/// The block a bytes owner shares, for tests and measurements.
pub fn block_of(vm: &Interp, owner: Value) -> Option<Arc<Block>> {
    if !is_bytes(vm, owner) {
        return None;
    }
    match buffer(owner) {
        ByteBuffer::Shared(b) => Some(b.clone()),
        _ => None,
    }
}
fn replace(vm: &mut Interp, owner: Value, data: ByteBuffer) -> ByteBuffer {
    let h = unsafe { &mut *owner.as_obj().unwrap().as_ptr() };
    let before = h.external_bytes();
    let old = std::mem::replace(&mut h.byte_buffer().data, data);
    h.refresh();
    vm.heap.account_resize(before, h.external_bytes());
    old
}
/// A new bytes owner over `data`, which it takes as is.
pub(crate) fn new_owner(vm: &mut Interp, data: ByteBuffer) -> Value {
    let owner = vm.heap_new_bytes(0);
    replace(vm, owner, data);
    owner
}
/// Turns an owner's allocation into a shared block in place. A fixed
/// allocation becomes the block itself; a growable buffer is copied once.
pub fn share_owner(vm: &mut Interp, owner: Value) -> Arc<Block> {
    if !is_bytes(vm, owner) {
        vm.err("nupp: only native storage can be shared");
    }
    let block = match replace(vm, owner, ByteBuffer::Moved) {
        ByteBuffer::Shared(b) => b,
        ByteBuffer::Aligned(a) => Arc::new(Block::adopt(a)),
        ByteBuffer::Bytes(v) => Arc::new(Block::copy_of(&v, 1, next_id()).unwrap()),
        ByteBuffer::Moved => vm.err("nupp: storage was moved to another worker"),
    };
    replace(vm, owner, ByteBuffer::Shared(block.clone()));
    block
}
/// Detaches an owner's allocation, leaving the moved husk behind.
fn detach(vm: &mut Interp, owner: Value) -> Option<AlignedBytes> {
    match replace(vm, owner, ByteBuffer::Moved) {
        ByteBuffer::Aligned(a) => Some(a),
        other => {
            replace(vm, owner, other);
            None
        }
    }
}

fn owner_of(vm: &Interp, view: Value) -> Value {
    if !matches!(vm.kind_of(view), Some(KIND_TABLE | KIND_RECORD)) {
        return Value::NIL;
    }
    let raw = vm.heap.interned_key(OWNER_KEY).map_or(Value::NIL, |k| vm.get_index(view, k));
    if raw != Value::NIL {
        return raw;
    }
    vm.heap.interned_key("owner").map_or(Value::NIL, |k| vm.get_index(view, k))
}

/// The owners of every `nupp.mem.heap` array reachable from `roots`: what a
/// crossing moves rather than copies. The checker allows such an array to
/// cross only where the sender gives it up (a `takes` argument or a result).
fn movable_owners(vm: &Interp, roots: &[Value]) -> HashSet<Value> {
    let mut owners = HashSet::new();
    let Some(&shape) = vm.heap.shape_identities.get(ARRAY_IDENTITY) else {
        return owners;
    };
    let Some(pointer_key) = vm.heap.interned_key("pointer") else {
        return owners;
    };
    let mut seen = HashSet::new();
    let mut pending: Vec<Value> = roots.iter().copied().filter(|v| v.as_obj().is_some()).collect();
    while let Some(v) = pending.pop() {
        if !seen.insert(v) {
            continue;
        }
        let h = unsafe { v.as_obj().unwrap().as_ref() };
        if h.kind == KIND_RECORD && h.shape() == shape {
            let owner = owner_of(vm, vm.get_index(v, pointer_key));
            if is_bytes(vm, owner) && matches!(buffer(owner), ByteBuffer::Aligned(_)) {
                owners.insert(owner);
            }
        }
        crate::heap::Heap::each_child(h, &mut |c| {
            if c.as_obj().is_some() {
                pending.push(c)
            }
        });
    }
    owners
}

/// Encodes `value` while a crossing or a checkpoint writes it, when it is a
/// bytes owner this module answers for: the node tag and its payload.
pub(crate) fn encode(vm: &Interp, value: Value) -> Result<Option<(u8, Vec<u8>)>> {
    if !is_bytes(vm, value) {
        return Ok(None);
    }
    let crossing = OUTBOX.with(|o| o.borrow().is_some());
    Ok(match buffer(value) {
        ByteBuffer::Shared(block) if crossing => {
            let index = OUTBOX.with(|o| {
                let mut o = o.borrow_mut();
                let o = o.as_mut().unwrap();
                o.shared.push(block.clone());
                o.shared.len() - 1
            });
            Some((ATTACHED_SHARED, (index as u32).to_le_bytes().to_vec()))
        }
        ByteBuffer::Shared(block) => {
            publish(block);
            Some((SHARED_BYTES, shared_payload(block)))
        }
        ByteBuffer::Moved => Some((MOVED_BYTES, Vec::new())),
        ByteBuffer::Aligned(_) if crossing => OUTBOX.with(|o| {
            let mut o = o.borrow_mut();
            let o = o.as_mut().unwrap();
            if !o.movable.contains(&value) {
                return None;
            }
            o.moving.push(value);
            Some((ATTACHED_MOVED, ((o.moving.len() - 1) as u32).to_le_bytes().to_vec()))
        }),
        _ => None,
    })
}

fn index(data: &[u8]) -> Result<usize> {
    Ok(u32::from_le_bytes(data.try_into().map_err(|_| "invalid attachment index")?) as usize)
}

/// Rebuilds the bytes owner `encode` wrote.
pub(crate) fn decode(vm: &mut Interp, tag: u8, data: &[u8]) -> Result<Value> {
    let data = match tag {
        SHARED_BYTES => ByteBuffer::Shared(shared_block(data)?),
        ATTACHED_SHARED => {
            let i = index(data)?;
            let block = INBOX.with(|b| b.borrow().as_ref().and_then(|a| a.shared.get(i).cloned()));
            ByteBuffer::Shared(block.ok_or("shared block attachment is missing")?)
        }
        ATTACHED_MOVED => {
            let i = index(data)?;
            let moved = INBOX.with(|b| {
                b.borrow_mut().as_mut().and_then(|a| a.moved.get_mut(i).and_then(Option::take))
            });
            ByteBuffer::Aligned(moved.ok_or("moved allocation attachment is missing or was taken twice")?)
        }
        MOVED_BYTES if data.is_empty() => ByteBuffer::Moved,
        _ => return Err("invalid shared storage node".into()),
    };
    Ok(new_owner(vm, data))
}

/// Writes a crossing: `body` encodes the message, during which shared blocks
/// become attachments and the arrays reachable from `movable` are claimed.
/// Only once the whole message has encoded are the claimed allocations taken
/// from their owners, so a failed encoding leaves the sender untouched.
pub(crate) fn send<T>(
    vm: &mut Interp,
    movable: &[Value],
    body: impl FnOnce(&mut Interp) -> Result<T>,
) -> Result<(T, Attachments)> {
    let outbox = Outbox { movable: movable_owners(vm, movable), ..Default::default() };
    let previous = OUTBOX.with(|o| o.borrow_mut().replace(outbox));
    let result = body(vm);
    let outbox = OUTBOX.with(|o| std::mem::replace(&mut *o.borrow_mut(), previous)).unwrap();
    let value = result?;
    let moved = outbox
        .moving
        .iter()
        .map(|&owner| detach(vm, owner))
        .collect();
    Ok((value, Attachments { shared: outbox.shared, moved }))
}

/// Reads a crossing `send` wrote. Attachments `body` did not take are
/// released when this returns, so a failed delivery frees a moved allocation
/// exactly once.
pub(crate) fn receive<T>(attachments: Attachments, body: impl FnOnce() -> Result<T>) -> Result<T> {
    let previous = INBOX.with(|b| b.borrow_mut().replace(attachments));
    let result = body();
    INBOX.with(|b| *b.borrow_mut() = previous);
    result
}

/// Adds `share` and `address` to the storage provider, where
/// `nupp.mem.sharedbytes` reaches the rest of native storage.
pub(crate) fn install(vm: &mut Interp) {
    let Some(&provider) = vm.loaded.get("nupp.runtime.provider.nativestorage") else {
        return;
    };
    for name in ["share", "address"] {
        let key = vm.intern(name);
        let id = crate::builtins::id_of(&format!("sharing.{name}")).unwrap();
        vm.set_index(provider, key, Value::builtin(id));
    }
}

/// The storage provider's `share(source)` answers a read-only byte view over a
/// shared block holding `source` -- a string, copied once, or a storage view,
/// whose whole allocation becomes the block without a copy. `address(view)`
/// answers where the allocation under a storage view lives, or nil: a block
/// has one address in every VM sharing it, and a moved allocation keeps its
/// address in the VM it moved to.
pub(crate) fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Value {
    let arg = |i: usize| args.get(i).copied().unwrap_or(Value::NIL);
    let scope = vm.open_scope();
    vm.handles.extend_from_slice(args);
    let result = match name {
        "share" => {
            let source = arg(0);
            let view = if vm.is_stringish(source) {
                let bytes = vm.bytes_of(source).to_vec();
                let n = crate::numeric::unsigned(vm, bytes.len() as u64);
                let view = crate::storage::call(vm, "allocateBytes", &[n]);
                vm.handles.push(view);
                let owner = owner_of(vm, view);
                vm.bytes_mut(owner)[..bytes.len()].copy_from_slice(&bytes);
                view
            } else {
                source
            };
            let owner = owner_of(vm, view);
            if !is_bytes(vm, owner) {
                vm.err("nupp: share expects a string or a native storage view");
            }
            share_owner(vm, owner);
            crate::storage::call(vm, "castBytes", &[view])
        }
        "address" => {
            let owner = owner_of(vm, arg(0));
            if is_bytes(vm, owner) && buffer(owner).is_fixed() && !is_moved(vm, owner) {
                crate::numeric::unsigned(vm, vm.bytes_of(owner).as_ptr() as usize as u64)
            } else {
                Value::NIL
            }
        }
        _ => vm.err("nupp: unknown sharing operation"),
    };
    vm.close_scope(scope);
    result
}

#[cfg(test)]
mod measure {
    use super::*;
    use crate::persist::{self, Policies};
    use std::time::{Duration, Instant};

    fn vm() -> Interp {
        let mut vm = Interp::new();
        crate::image::load(
            &mut vm,
            "shape 0 Array identity=nupp.mem.heap:Array pointer:any count:num\nfunction f 0 0 2 1 :v\nRetNil\nend\nentry 0\n",
        )
        .unwrap();
        vm.install_globals();
        vm
    }
    /// One crossing from `from` into `to`: the message encoded with its
    /// attachments, then decoded. What a worker spawn or result pays for its
    /// payload, without the VM and thread around it.
    fn cross(from: &mut Interp, to: &mut Interp, value: Value, moves: bool) -> (Value, Duration) {
        let start = Instant::now();
        let movable = if moves { vec![value] } else { vec![] };
        let (bytes, attached) =
            send(from, &movable, |vm| persist::save_graph(vm, &[value], &Policies::default())).unwrap();
        let v = receive(attached, || persist::load_graph(to, &bytes, &Policies::default(), None)).unwrap()[0];
        (v, start.elapsed())
    }
    fn array(vm: &mut Interp, count: usize) -> Value {
        let kind = vm.intern("int32");
        vm.handles.push(kind);
        let element = crate::storage::call(vm, "scalar", &[kind]);
        vm.handles.push(element);
        let view = crate::storage::call(vm, "allocateArray", &[element, Value::num(count as f64)]);
        vm.handles.push(view);
        let record = vm.new_record(vm.heap.shape_identities[ARRAY_IDENTITY]);
        vm.handles.push(record);
        let key = vm.intern("pointer");
        vm.set_index(record, key, view);
        let key = vm.intern("count");
        vm.set_index(record, key, Value::num(count as f64));
        record
    }

    #[test]
    #[ignore = "measurement: cargo test --release --lib sharing::measure -- --ignored --nocapture"]
    fn crossing_cost_does_not_grow_with_size() {
        let (mut a, mut b) = (vm(), vm());
        println!("{:>10} {:>12} {:>12} {:>12}", "bytes", "shared us", "moved us", "copied us");
        for shift in [10, 16, 20, 24, 26] {
            let n = 1usize << shift;
            let best = |samples: Vec<Duration>| samples.into_iter().min().unwrap().as_secs_f64() * 1e6;
            let text = a.new_string_bytes(&vec![1u8; n]);
            a.handles.push(text);
            let view = call(&mut a, "share", &[text]);
            a.handles.push(view);
            let shared: Vec<_> = (0..7).map(|_| cross(&mut a, &mut b, view, false).1).collect();
            // The array goes back and forth, so every sample moves it again.
            let mut current = array(&mut a, n / 4);
            let mut moved = vec![];
            for i in 0..8 {
                let (from, to) = if i % 2 == 0 { (&mut a, &mut b) } else { (&mut b, &mut a) };
                let (v, t) = cross(from, to, current, true);
                to.handles.push(v);
                current = v;
                moved.push(t);
            }
            let copied: Vec<_> = (0..7).map(|_| cross(&mut a, &mut b, text, false).1).collect();
            println!("{n:>10} {:>12.1} {:>12.1} {:>12.1}", best(shared), best(moved), best(copied));
            a.handles.clear();
            b.handles.clear();
            a.full_cycle();
            b.full_cycle();
        }
    }
}
