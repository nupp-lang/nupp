//! Affine sender/receiver handles over bounded cross-VM queues.
use crate::{
    channels::{Resource, Shared},
    heap::{Heap, KIND_RECORD, KIND_TABLE},
    interp::Interp,
    persist::{self, Policies, ResourceCodec, ResourceCodecs},
    task_api::{field, put, Answer},
    value::Value,
};
use std::{
    collections::{HashMap, HashSet, VecDeque},
    sync::{
        atomic::{AtomicU64, AtomicU8, Ordering},
        Arc, Mutex, Weak,
    },
};

type Result<T> = std::result::Result<T, String>;
pub(crate) const KIND: &str = "nupp.channel.endpoint";
pub(crate) const MESSAGE_KIND: &str = "nupp.channel.message";
static NEXT_TOKEN: AtomicU64 = AtomicU64::new(1);

pub(crate) struct Queue {
    id: u64,
    capacity: usize,
    byte_capacity: usize,
    bytes: usize,
    sender_closed: bool,
    receiver_closed: bool,
    messages: VecDeque<Message>,
}
pub(crate) struct Message {
    graph: Vec<u8>,
    attachments: crate::sharing::Attachments,
    retained: usize,
}
pub(crate) struct Token {
    id: u64,
    queue: Arc<Mutex<Queue>>,
    // 0 receiver, 1 sender, 2 scope anchor.
    direction: u8,
    // 0 live, 1 closed, 2 moved (must not close the new owner's direction).
    state: AtomicU8,
}
impl Token {
    fn new(queue: Arc<Mutex<Queue>>, direction: u8, state: u8) -> Self {
        Self {
            id: NEXT_TOKEN.fetch_add(1, Ordering::Relaxed),
            queue,
            direction,
            state: AtomicU8::new(state),
        }
    }
    fn close(&self) {
        if self.state.swap(1, Ordering::AcqRel) != 0 {
            return;
        }
        let mut q = self.queue.lock().unwrap();
        match self.direction {
            1 => q.sender_closed = true,
            _ => {
                q.receiver_closed = true;
                q.sender_closed = true;
                q.messages.clear();
                q.bytes = 0;
            }
        }
    }
}
impl Drop for Token {
    fn drop(&mut self) {
        self.close();
    }
}
#[derive(Clone)]
pub(crate) struct Endpoint {
    token: Arc<Token>,
    facade: bool,
}
pub(crate) type Pending = Arc<Mutex<Option<Message>>>;

fn endpoint(vm: &Interp, value: Value) -> Result<Endpoint> {
    vm.heap
        .channels
        .get(&value)
        .and_then(Resource::endpoint)
        .cloned()
        .ok_or_else(|| "nupp: invalid channel endpoint".into())
}
pub(crate) fn direction(vm: &Interp, value: Value) -> Option<u8> {
    vm.heap
        .channels
        .get(&value)
        .and_then(Resource::endpoint)
        .filter(|e| e.token.direction < 2 && e.token.state.load(Ordering::Acquire) == 0)
        .map(|e| e.token.direction)
}
pub(crate) fn contains(vm: &Interp, roots: &[Value]) -> bool {
    let mut seen = HashSet::new();
    let mut pending = roots.to_vec();
    while let Some(v) = pending.pop() {
        if vm
            .heap
            .channels
            .get(&v)
            .and_then(Resource::endpoint)
            .is_some_and(|e| e.token.direction < 2)
        {
            return true;
        }
        if let Some(p) = v.as_obj() {
            if seen.insert(v) {
                unsafe { Heap::each_child(p.as_ref(), &mut |v| pending.push(v)) };
            }
        }
    }
    false
}
fn raw(vm: &Interp, value: Value, name: &str) -> Value {
    if !matches!(vm.kind_of(value), Some(KIND_TABLE | KIND_RECORD)) {
        return Value::NIL;
    }
    vm.heap
        .interned_key(name)
        .map_or(Value::NIL, |key| vm.get_index(value, key))
}
pub(crate) fn is_array(vm: &Interp, value: Value) -> bool {
    value.as_obj().is_some_and(|p| {
        let h = unsafe { p.as_ref() };
        h.kind == KIND_RECORD
            && vm.heap.shape_identities.get(crate::sharing::ARRAY_IDENTITY) == Some(&h.shape())
    })
}
fn owner(vm: &Interp, view: Value) -> Value {
    let found = raw(vm, view, "\0nupp:storage:owner");
    if found != Value::NIL {
        found
    } else {
        raw(vm, view, "owner")
    }
}
fn allocation_size(vm: &Interp, value: Value) -> Option<usize> {
    if vm.kind_of(value) != Some(crate::heap::KIND_BYTES) {
        return None;
    }
    Some(unsafe {
        (*(value.as_obj().unwrap().as_ref().payload() as *const crate::heap::BytesPayload))
            .data
            .capacity()
    })
}
fn retained(vm: &Interp, value: Value, seen: &mut HashSet<Value>, depth: usize) -> Result<usize> {
    if value == Value::NIL || value == Value::TRUE || value == Value::FALSE {
        return Ok(1);
    }
    if crate::numeric::is_numeric(value) {
        return Ok(24);
    }
    if vm.is_stringish(value) {
        let n = vm.bytes_of(value).len();
        return Ok(n + n.to_string().len() + 2);
    }
    if is_array(vm, value) {
        if raw(vm, value, "closed") == Value::TRUE {
            return Err("nupp: array is closed".into());
        }
        return allocation_size(vm, owner(vm, raw(vm, value, "pointer")))
            .map(|n| n + 24)
            .ok_or_else(|| "nupp: only native fixed-width arrays can cross a channel".into());
    }
    let handle = raw(vm, value, "_handle");
    let data = raw(vm, handle, "data");
    if let Some(n) = allocation_size(vm, owner(vm, data)).or_else(|| allocation_size(vm, data)) {
        return Ok(n + 24);
    }
    if !matches!(vm.kind_of(value), Some(KIND_TABLE | KIND_RECORD)) {
        return Err("nupp: channel payload contains an unsupported value".into());
    }
    if vm
        .heap
        .channels
        .get(&value)
        .and_then(Resource::endpoint)
        .is_some()
    {
        return Err("nupp: channel payload cannot contain a channel endpoint".into());
    }
    if depth >= 32 || !seen.insert(value) {
        return Err("nupp: channel payload repeats a table or exceeds its depth limit".into());
    }
    let h = unsafe { value.as_obj().unwrap().as_ref() };
    let mut members = Vec::new();
    if h.kind == KIND_TABLE {
        if h.table_ref().meta != Value::NIL {
            return Err("nupp: channel payload has a metatable".into());
        }
        members.extend(h.table_ref().array.iter().copied());
        for (&key, &value) in h.table_ref().hash.iter() {
            members.extend([key, value]);
        }
    } else {
        members.extend(h.slots().iter().copied());
        members.extend(h.record_array_ref().iter().copied());
        if let Some(extra) = h.record_extra_ref() {
            for (&key, &value) in extra.iter() {
                members.extend([key, value]);
            }
        }
    }
    let mut size: usize = 4;
    for member in members {
        size = size
            .checked_add(retained(vm, member, seen, depth + 1)?)
            .ok_or("channel message too large")?;
    }
    Ok(size)
}
fn prepare(vm: &mut Interp, value: Value) -> Result<Message> {
    let size = retained(vm, value, &mut HashSet::new(), 0)?
        .checked_add(2)
        .ok_or("channel message too large")?;
    let (graph, attachments) = crate::sharing::send(vm, &[value], |vm| {
        if value == Value::NIL
            || value == Value::TRUE
            || value == Value::FALSE
            || crate::numeric::is_numeric(value)
            || vm.is_stringish(value)
        {
            persist::save_plain(vm, value)
        } else {
            persist::save_graph(vm, &[value], &Policies::default())
        }
    })?;
    // The new graph contains the live wrapper. The old wrapper is now a moved husk.
    if is_array(vm, value) {
        put(vm, value, "closed", Value::TRUE);
    }
    Ok(Message {
        graph,
        attachments,
        retained: size,
    })
}
fn decode(vm: &mut Interp, message: Message) -> Result<Value> {
    crate::sharing::receive(message.attachments, || {
        persist::load_graph(vm, &message.graph, &Policies::default(), None).map(|roots| roots[0])
    })
}
fn offer(e: &Endpoint, message: &mut Option<Message>) -> u8 {
    if e.token.direction != 1 || e.token.state.load(Ordering::Acquire) != 0 {
        return 4;
    }
    let Some(m) = message.as_ref() else { return 4 };
    let mut q = e.token.queue.lock().unwrap();
    if m.retained > q.byte_capacity {
        return 3;
    }
    if q.receiver_closed || q.sender_closed {
        return 2;
    }
    if q.messages.len() >= q.capacity || m.retained > q.byte_capacity - q.bytes {
        return 1;
    }
    q.bytes += m.retained;
    q.messages.push_back(message.take().unwrap());
    0
}
fn take(e: &Endpoint) -> Result<(u8, Option<Message>)> {
    if e.token.direction != 0 || e.token.state.load(Ordering::Acquire) != 0 {
        return Err("nupp: invalid, closed, or moved channel endpoint".into());
    }
    let mut q = e.token.queue.lock().unwrap();
    if q.receiver_closed {
        return Err("nupp: channel scope is closed".into());
    }
    if let Some(m) = q.messages.pop_front() {
        q.bytes -= m.retained;
        Ok((0, Some(m)))
    } else {
        Ok((if q.sender_closed { 2 } else { 1 }, None))
    }
}
fn ready(e: &Endpoint, bytes: usize) -> u8 {
    if e.token.state.load(Ordering::Acquire) != 0 {
        return 2;
    }
    let q = e.token.queue.lock().unwrap();
    if q.receiver_closed {
        return 2;
    }
    if e.token.direction == 0 {
        if !q.messages.is_empty() {
            0
        } else if q.sender_closed {
            2
        } else {
            1
        }
    } else if q.sender_closed {
        2
    } else if bytes > q.byte_capacity {
        3
    } else if q.messages.len() < q.capacity && bytes <= q.byte_capacity - q.bytes {
        0
    } else {
        1
    }
}
fn facade(vm: &mut Interp, object: Value, e: Endpoint) {
    let roots = vm.open_scope();
    vm.handles.push(object);
    let state = vm.new_table();
    vm.handles.push(state);
    put(vm, state, "handle", object);
    put(
        vm,
        state,
        "closed",
        Value::boolean(e.token.state.load(Ordering::Acquire) != 0),
    );
    put(vm, object, "_state", state);
    for (n, b) in [
        ("_close", "tasks.channelEndpointCloseState"),
        ("close", "tasks.channelEndpointClose"),
    ] {
        put(
            vm,
            object,
            n,
            Value::builtin(crate::builtins::id_of(b).unwrap()),
        );
    }
    let methods = if e.token.direction == 1 {
        [
            ("send", "tasks.channelEndpointSend"),
            ("trysend", "tasks.channelEndpointTrySend"),
        ]
    } else {
        [
            ("receive", "tasks.channelEndpointReceive"),
            ("tryreceive", "tasks.channelEndpointTryReceive"),
        ]
    };
    for (n, b) in methods {
        put(
            vm,
            object,
            n,
            Value::builtin(crate::builtins::id_of(b).unwrap()),
        );
    }
    vm.close_scope(roots);
}
pub(crate) fn moved(vm: &mut Interp, object: Value) {
    if let Some(e) = vm.heap.channels.get(&object).and_then(Resource::endpoint) {
        e.token.state.store(2, Ordering::Release);
        let state = field(vm, object, "_state");
        if state != Value::NIL {
            put(vm, state, "closed", Value::TRUE);
        }
    }
}
pub(crate) fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Answer {
    let at = |i| args.get(i).copied().unwrap_or(Value::NIL);
    let values = |v| Answer::Values(v);
    if name == "tasks.channelEndpointCreate" {
        let capacity = crate::numeric::integral(at(0)).filter(|n| (1..=1_000_000).contains(n));
        let bytes = crate::numeric::integral(at(1)).filter(|n| *n > 0 && *n <= usize::MAX as i128);
        let (Some(capacity), Some(bytes)) = (capacity, bytes) else {
            vm.err("nupp: channel limits must be positive integers");
        };
        let queue = {
            let mut r = vm.channel_registry.lock().unwrap();
            r.next = r.next.checked_add(1).expect("channel id overflow");
            let q = Arc::new(Mutex::new(Queue {
                id: r.next,
                capacity: capacity as usize,
                byte_capacity: bytes as usize,
                bytes: 0,
                sender_closed: false,
                receiver_closed: false,
                messages: VecDeque::new(),
            }));
            r.endpoints.retain(|_, q| q.strong_count() > 0);
            let id = r.next;
            r.endpoints.insert(id, Arc::downgrade(&q));
            q
        };
        let roots = vm.open_scope();
        let mut out = Vec::new();
        for direction in [1, 0] {
            let object = vm.new_table();
            vm.handles.push(object);
            vm.heap.channels.insert(
                object,
                Resource::Endpoint(Endpoint {
                    token: Arc::new(Token::new(queue.clone(), direction, 0)),
                    facade: false,
                }),
            );
            out.push(object);
        }
        vm.close_scope(roots);
        return values(out);
    }
    if name == "tasks.channelEndpointIsArray" {
        return values(vec![Value::boolean(is_array(vm, at(0)))]);
    }
    if name == "tasks.channelEndpointDirection" {
        return values(vec![Value::num(
            direction(vm, at(0)).map_or(-1.0, |d| d as f64),
        )]);
    }
    if name == "tasks.channelEndpointPrepare" {
        let message = prepare(vm, at(0)).unwrap_or_else(|e| vm.err(&e));
        let object = vm.new_table();
        vm.heap.channels.insert(
            object,
            Resource::Message(Arc::new(Mutex::new(Some(message)))),
        );
        return values(vec![object]);
    }
    if name.starts_with("tasks.channelMessage") {
        let pending = vm
            .heap
            .channels
            .get(&at(0))
            .and_then(Resource::message)
            .cloned()
            .unwrap_or_else(|| vm.err("nupp: invalid channel message"));
        return match name {
            "tasks.channelMessageSize" => values(vec![Value::num(
                pending.lock().unwrap().as_ref().map_or(0, |m| m.retained) as f64,
            )]),
            "tasks.channelMessageClose" => {
                pending.lock().unwrap().take();
                values(vec![])
            }
            "tasks.channelMessageTake" => {
                let message = pending
                    .lock()
                    .unwrap()
                    .take()
                    .unwrap_or_else(|| vm.err("nupp: channel message was consumed"));
                values(vec![decode(vm, message).unwrap_or_else(|e| vm.err(&e))])
            }
            _ => vm.err("unknown channel message operation"),
        };
    }
    let object = if name == "tasks.channelEndpointCloseState" {
        field(vm, at(0), "handle")
    } else {
        at(0)
    };
    let e = endpoint(vm, object).unwrap_or_else(|e| vm.err(&e));
    match name {
        "tasks.channelEndpointMove" => {
            if e.token.direction == 2 || e.token.state.load(Ordering::Acquire) != 0 {
                vm.err("nupp: invalid, closed, or moved channel endpoint");
            }
            let object = vm.new_table();
            let moved = Endpoint {
                token: Arc::new(Token::new(e.token.queue.clone(), e.token.direction, 0)),
                facade: false,
            };
            e.token.state.store(2, Ordering::Release);
            vm.heap.channels.insert(object, Resource::Endpoint(moved));
            values(vec![object])
        }
        "tasks.channelEndpointBind" => {
            vm.heap
                .channels
                .insert(at(1), Resource::Endpoint(Endpoint { facade: true, ..e }));
            values(vec![])
        }
        "tasks.channelEndpointAnchor" => {
            let object = vm.new_table();
            vm.heap.channels.insert(
                object,
                Resource::Endpoint(Endpoint {
                    token: Arc::new(Token::new(e.token.queue.clone(), 2, 0)),
                    facade: false,
                }),
            );
            values(vec![object])
        }
        "tasks.channelEndpointClose" | "tasks.channelEndpointCloseState" => {
            e.token.close();
            let state = field(vm, object, "_state");
            if state != Value::NIL {
                put(vm, state, "closed", Value::TRUE);
            }
            values(vec![])
        }
        "tasks.channelEndpointReady" => {
            let bytes = crate::numeric::integral(at(1)).unwrap_or(0).max(0) as usize;
            values(vec![Value::num(ready(&e, bytes) as f64)])
        }
        "tasks.channelEndpointOffer" => {
            let pending = vm
                .heap
                .channels
                .get(&at(1))
                .and_then(Resource::message)
                .cloned()
                .unwrap_or_else(|| vm.err("nupp: invalid channel message"));
            values(vec![Value::num(
                offer(&e, &mut pending.lock().unwrap()) as f64
            )])
        }
        "tasks.channelEndpointTake"
        | "tasks.channelEndpointTryReceive"
        | "tasks.channelEndpointReceive" => {
            let (status, message) = take(&e).unwrap_or_else(|e| vm.err(&e));
            if name == "tasks.channelEndpointReceive" && status == 1 {
                return Answer::Event(object);
            }
            let value = message
                .map(|m| decode(vm, m).unwrap_or_else(|e| vm.err(&e)))
                .unwrap_or(Value::NIL);
            if name == "tasks.channelEndpointTake" {
                values(vec![Value::num(status as f64), value])
            } else {
                let tag = vm.intern(match status {
                    0 => "value",
                    1 => "empty",
                    _ => "closed",
                });
                values(vec![tag, value])
            }
        }
        "tasks.channelEndpointTrySend" | "tasks.channelEndpointSend" => {
            if e.token.state.load(Ordering::Acquire) != 0 || e.token.direction != 1 {
                vm.err("nupp: invalid, closed, or moved channel endpoint");
            }
            let retained =
                retained(vm, at(1), &mut HashSet::new(), 0).unwrap_or_else(|e| vm.err(&e)) + 2;
            if name == "tasks.channelEndpointSend" && ready(&e, retained) == 1 {
                return Answer::Event(object);
            }
            let mut message = Some(prepare(vm, at(1)).unwrap_or_else(|e| vm.err(&e)));
            let status = offer(&e, &mut message);
            if status > 2 || name == "tasks.channelEndpointSend" && status != 0 {
                vm.err(if status == 3 {
                    "nupp: channel payload exceeds its byte limit"
                } else {
                    "nupp: channel receiver is closed"
                });
            }
            if name == "tasks.channelEndpointSend" {
                return values(vec![]);
            }
            let returned = message
                .map(|m| decode(vm, m).unwrap_or_else(|e| vm.err(&e)))
                .unwrap_or(Value::NIL);
            let tag = vm.intern(match status {
                0 => "sent",
                1 => "full",
                _ => "closed",
            });
            values(vec![tag, returned])
        }
        _ => vm.err("unknown channel endpoint operation"),
    }
}

struct Reader<'a>(&'a [u8]);
impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8]> {
        if self.0.len() < n {
            return Err("truncated channel endpoint".into());
        }
        let (out, rest) = self.0.split_at(n);
        self.0 = rest;
        Ok(out)
    }
    fn byte(&mut self) -> Result<u8> {
        Ok(self.take(1)?[0])
    }
    fn number(&mut self) -> Result<usize> {
        usize::try_from(u64::from_le_bytes(self.take(8)?.try_into().unwrap()))
            .map_err(|_| "channel extent too large".into())
    }
    fn message(&mut self) -> Result<Message> {
        let retained = self.number()?;
        let n = self.number()?;
        let graph = self.take(n)?.to_vec();
        let n = self.number()?;
        let attachments = crate::sharing::Attachments::read(self.take(n)?)?;
        Ok(Message {
            retained,
            graph,
            attachments,
        })
    }
}
fn write_message(out: &mut Vec<u8>, message: &Message) {
    out.extend((message.retained as u64).to_le_bytes());
    out.extend((message.graph.len() as u64).to_le_bytes());
    out.extend(&message.graph);
    let mut attached = Vec::new();
    message.attachments.write(&mut attached);
    out.extend((attached.len() as u64).to_le_bytes());
    out.extend(attached);
}
pub(crate) struct Codec {
    registry: Shared,
    transfer: bool,
    message: bool,
    allowed: Option<HashSet<Value>>,
    transfer_tokens: HashMap<u64, Arc<Token>>,
}
impl ResourceCodec for Codec {
    fn save(&mut self, vm: &Interp, object: Value) -> Result<Vec<u8>> {
        if self.message {
            let pending = vm
                .heap
                .channels
                .get(&object)
                .and_then(Resource::message)
                .ok_or("unknown channel message")?
                .lock()
                .unwrap();
            let mut b = vec![pending.is_some() as u8];
            if let Some(m) = &*pending {
                write_message(&mut b, m);
            }
            return Ok(b);
        }
        let e = endpoint(vm, object)?;
        if self.transfer
            && self
                .allowed
                .as_ref()
                .is_some_and(|allowed| !allowed.contains(&object))
        {
            return Err("nupp: channel endpoints must be direct worker arguments, not captures or nested values".into());
        }
        let state = e.token.state.load(Ordering::Acquire);
        if self.transfer && (state != 0 || e.token.direction == 2) {
            return Err("nupp: closed endpoints and scope anchors cannot cross workers".into());
        }
        let q = e.token.queue.lock().unwrap();
        let mut b = vec![
            self.transfer as u8,
            e.token.direction,
            state,
            e.facade as u8,
        ];
        b.extend(q.id.to_le_bytes());
        let token = self.transfer_tokens.get(&e.token.id).unwrap_or(&e.token);
        b.extend(token.id.to_le_bytes());
        if !self.transfer {
            b.extend((q.capacity as u64).to_le_bytes());
            b.extend((q.byte_capacity as u64).to_le_bytes());
            b.extend([q.sender_closed as u8, q.receiver_closed as u8]);
            b.extend((q.messages.len() as u64).to_le_bytes());
            for m in &q.messages {
                write_message(&mut b, m);
            }
        }
        Ok(b)
    }
    fn restore(&mut self, vm: &mut Interp, object: Value, data: &[u8]) -> Result<()> {
        let mut r = Reader(data);
        if self.message {
            let pending = match r.byte()? {
                0 => None,
                1 => Some(r.message()?),
                _ => return Err("invalid channel message".into()),
            };
            if !r.0.is_empty() {
                return Err("trailing channel message data".into());
            }
            vm.heap
                .channels
                .insert(object, Resource::Message(Arc::new(Mutex::new(pending))));
            return Ok(());
        }
        let transfer = r.byte()?;
        let direction = r.byte()?;
        let state = r.byte()?;
        let is_facade = r.byte()?;
        if transfer > 1 || direction > 2 || state > 2 || is_facade > 1 {
            return Err("invalid channel endpoint".into());
        }
        let id = r.number()? as u64;
        let token_id = r.number()? as u64;
        if token_id == 0 || token_id == u64::MAX {
            return Err("invalid channel token id".into());
        }
        let restored = if transfer == 0 {
            let capacity = r.number()?;
            let byte_capacity = r.number()?;
            if capacity == 0 || capacity > 1_000_000 || byte_capacity == 0 {
                return Err("invalid channel limits".into());
            }
            let sender_closed = r.byte()? != 0;
            let receiver_closed = r.byte()? != 0;
            let count = r.number()?;
            if count > capacity {
                return Err("channel exceeds capacity".into());
            }
            let mut messages = VecDeque::new();
            let mut bytes: usize = 0;
            for _ in 0..count {
                let m = r.message()?;
                bytes = bytes
                    .checked_add(m.retained)
                    .filter(|n| *n <= byte_capacity)
                    .ok_or("channel exceeds byte capacity")?;
                messages.push_back(m);
            }
            Some(Queue {
                id,
                capacity,
                byte_capacity,
                bytes,
                sender_closed,
                receiver_closed,
                messages,
            })
        } else {
            None
        };
        if !r.0.is_empty() {
            return Err("trailing channel endpoint data".into());
        }
        let queue = {
            let mut registry = self.registry.lock().unwrap();
            if let Some(q) = registry.endpoints.get(&id).and_then(Weak::upgrade) {
                q
            } else {
                let q = Arc::new(Mutex::new(
                    restored.ok_or("channel transfer requires its source registry")?,
                ));
                registry.next = registry.next.max(id);
                registry.endpoints.insert(id, Arc::downgrade(&q));
                q
            }
        };
        let mut registry = self.registry.lock().unwrap();
        let token = if let Some(token) = registry
            .endpoint_tokens
            .get(&token_id)
            .and_then(Weak::upgrade)
        {
            if token.direction != direction {
                return Err("channel endpoint alias changes direction".into());
            }
            token
        } else {
            NEXT_TOKEN.fetch_max(token_id + 1, Ordering::Relaxed);
            let token = Arc::new(Token {
                id: token_id,
                queue,
                direction,
                state: AtomicU8::new(state),
            });
            registry
                .endpoint_tokens
                .insert(token_id, Arc::downgrade(&token));
            token
        };
        drop(registry);
        let e = Endpoint {
            token,
            facade: is_facade != 0,
        };
        vm.heap
            .channels
            .insert(object, Resource::Endpoint(e.clone()));
        if e.facade {
            facade(vm, object, e);
        }
        Ok(())
    }
}
pub(crate) fn add_codecs(codecs: &mut ResourceCodecs, registry: Shared, transfer: bool) {
    for (kind, message) in [(KIND, false), (MESSAGE_KIND, true)] {
        codecs.entry(kind.into()).or_insert_with(|| {
            Box::new(Codec {
                registry: registry.clone(),
                transfer,
                message,
                allowed: None,
                transfer_tokens: HashMap::new(),
            })
        });
    }
}
/// A queued handoff owns live directions without retaining parent heap values.
/// Failed graph encoding leaves these reservations inactive.
pub(crate) struct Transfer {
    tokens: HashMap<u64, Arc<Token>>,
}
impl Transfer {
    pub(crate) fn new(vm: &Interp, args: &[Value]) -> Self {
        let mut tokens = HashMap::new();
        let mut registry = vm.channel_registry.lock().unwrap();
        registry
            .endpoint_tokens
            .retain(|_, token| token.strong_count() > 0);
        for &arg in args {
            if let Some(e) = vm.heap.channels.get(&arg).and_then(Resource::endpoint) {
                tokens.entry(e.token.id).or_insert_with(|| {
                    let token = Arc::new(Token::new(e.token.queue.clone(), e.token.direction, 2));
                    registry
                        .endpoint_tokens
                        .insert(token.id, Arc::downgrade(&token));
                    token
                });
            }
        }
        Self { tokens }
    }
    pub(crate) fn codec(&self, registry: Shared, args: &[Value]) -> Box<dyn ResourceCodec> {
        Box::new(Codec {
            registry,
            transfer: true,
            message: false,
            allowed: Some(args.iter().copied().collect()),
            transfer_tokens: self.tokens.clone(),
        })
    }
    pub(crate) fn commit(&self, vm: &mut Interp, args: &[Value]) {
        for token in self.tokens.values() {
            token.state.store(0, Ordering::Release);
        }
        for &arg in args {
            moved(vm, arg);
        }
    }
    pub(crate) fn into_tokens(self) -> Vec<Arc<Token>> {
        self.tokens.into_values().collect()
    }
}
pub(crate) fn held_tokens(vm: &Interp) -> Vec<Arc<Token>> {
    vm.heap
        .channels
        .values()
        .filter_map(Resource::endpoint)
        .filter(|e| e.token.direction < 2 && e.token.state.load(Ordering::Acquire) == 0)
        .map(|e| e.token.clone())
        .collect()
}
pub(crate) fn poll(vm: &mut Interp) {
    let Some(s) = &vm.scheduler else { return };
    let values: Vec<_> = s
        .controls
        .iter()
        .filter_map(|(&tid, c)| {
            if c.status == crate::scheduler::Status::Active {
                if let crate::interp::State::Parked(k) = vm.tasks[tid].state {
                    let value = Value(k);
                    if vm
                        .heap
                        .channels
                        .get(&value)
                        .and_then(Resource::endpoint)
                        .is_some()
                    {
                        return Some(value);
                    }
                }
            }
            None
        })
        .collect();
    for value in values {
        crate::task_api::wake_event(vm, value);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn fixture() -> Interp {
        let mut vm = Interp::new();
        crate::image::load(
            &mut vm,
            r#"
shape 0 Array identity=nupp.array:ArrayImpl pointer:any count:num closed:any
shape 1 Receiver identity=nupp.workers.internal.channeltypes:Receiver _state:any _close:any receive:any tryreceive:any
function echo 0 1 4 1 v:v
Ret 1
end
function receive 1 1 10 1 v:v
const 0 builtin tasks.channelEndpointReceive
K 2 0
Move 4 1
CallDyn 2 3 1
RetN 3 2
end
function publish 2 1 10 1 v:v
const 0 builtin tasks.channelEndpointSend
const 1 num 1
const 2 num 2
K 2 0
Move 4 1
K 5 1
CallDyn 2 3 2
K 2 0
Move 4 1
K 5 2
CallDyn 2 3 2
RetNil
end
function forkReceive 3 1 18 1 v:v
const 0 builtin tasks.open
const 1 builtin tasks.fork
const 2 func 1
const 3 builtin tasks.await
const 4 builtin tasks.close
K 2 0
CallDyn 2 3 0
K 4 4
Defer 3 4
K 4 1
Move 6 3
K 7 2
Move 8 1
CallDyn 4 5 3
K 6 3
Move 8 5
CallDyn 6 7 1
RetN 7 2
end
function receiveFacade 4 1 10 1 v:v
const 0 str "receive"
GetField 2 1 0
Move 4 1
CallDyn 2 3 1
RetN 3 2
end
entry 0
"#,
        )
        .unwrap();
        vm.install_globals();
        vm.enable_scheduler().unwrap();
        vm.heap.stress = true;
        vm
    }
    fn run(vm: &mut Interp, method: &str, args: &[Value]) -> Vec<Value> {
        let scope = vm.open_scope();
        vm.handles.extend_from_slice(args);
        let Answer::Values(values) = call(vm, &format!("tasks.channel{method}"), args) else {
            panic!("unexpected wait");
        };
        vm.close_scope(scope);
        values
    }
    fn pair(vm: &mut Interp, messages: usize, bytes: usize) -> (Value, Value) {
        let endpoints = run(
            vm,
            "EndpointCreate",
            &[Value::num(messages as f64), Value::num(bytes as f64)],
        );
        vm.register(endpoints[0]);
        vm.register(endpoints[1]);
        (endpoints[0], endpoints[1])
    }
    fn pending(vm: &mut Interp, value: Value) -> Value {
        let m = run(vm, "EndpointPrepare", &[value])[0];
        vm.register(m);
        m
    }
    #[test]
    fn byte_bounds_nil_messages_and_directional_close() {
        let mut vm = fixture();
        let (sender, receiver) = pair(&mut vm, 2, 10);
        let text = vm.new_string_bytes(b"123");
        let first = pending(&mut vm, text);
        assert_eq!(
            run(&mut vm, "EndpointOffer", &[sender, first]),
            vec![Value::num(0.0)]
        );
        let second = pending(&mut vm, text);
        assert_eq!(
            run(&mut vm, "EndpointOffer", &[sender, second]),
            vec![Value::num(1.0)]
        );
        let result = run(&mut vm, "EndpointTake", &[receiver]);
        assert_eq!(vm.bytes_of(result[1]), b"123");
        run(&mut vm, "MessageClose", &[second]);
        for _ in 0..2 {
            let message = pending(&mut vm, Value::NIL);
            assert_eq!(
                run(&mut vm, "EndpointOffer", &[sender, message]),
                vec![Value::num(0.0)]
            );
        }
        run(&mut vm, "EndpointClose", &[sender]);
        for _ in 0..2 {
            assert_eq!(
                run(&mut vm, "EndpointTake", &[receiver]),
                vec![Value::num(0.0), Value::NIL]
            );
        }
        assert_eq!(
            run(&mut vm, "EndpointTake", &[receiver]),
            vec![Value::num(2.0), Value::NIL]
        );
        let forged = vm.new_table();
        assert_eq!(direction(&vm, forged), None);
    }
    #[test]
    fn a_worker_rejects_a_message_larger_than_the_channel_instead_of_parking() {
        let mut vm = fixture();
        let (sender, _) = pair(&mut vm, 1, 10);
        let mut worker = crate::workers::Worker::spawn(&mut vm, Value::func(2), &[sender]).unwrap();
        assert!(matches!(
            finish(&mut worker).status,
            crate::scheduler::Status::Failed(error) if error.contains("exceeds its byte limit")
        ));
    }
    #[test]
    fn refused_array_move_returns_the_original_allocation() {
        let mut vm = fixture();
        let (sender, receiver) = pair(&mut vm, 1, 128);
        let first = pending(&mut vm, Value::NIL);
        run(&mut vm, "EndpointOffer", &[sender, first]);
        let element = vm.intern("int32");
        let element = vm.call_value(
            Value::builtin(crate::builtins::id_of("storage.scalar").unwrap()),
            &[element],
        )[0];
        vm.register(element);
        let view = vm.call_value(
            Value::builtin(crate::builtins::id_of("storage.allocateArray").unwrap()),
            &[element, Value::num(4.0)],
        )[0];
        vm.register(view);
        let array_owner = owner(&vm, view);
        let address = vm.bytes_of(array_owner).as_ptr();
        let array = vm.new_record(vm.heap.shape_identities[crate::sharing::ARRAY_IDENTITY]);
        vm.register(array);
        put(&mut vm, array, "pointer", view);
        put(&mut vm, array, "count", Value::num(4.0));
        put(&mut vm, array, "closed", Value::FALSE);
        let message = pending(&mut vm, array);
        assert!(crate::sharing::is_moved(&vm, array_owner));
        assert_eq!(raw(&vm, array, "closed"), Value::TRUE);
        assert_eq!(
            run(&mut vm, "EndpointOffer", &[sender, message]),
            vec![Value::num(1.0)]
        );
        let returned = run(&mut vm, "MessageTake", &[message])[0];
        vm.register(returned);
        assert_eq!(raw(&vm, returned, "closed"), Value::FALSE);
        let returned_owner = owner(&vm, raw(&vm, returned, "pointer"));
        assert_eq!(vm.bytes_of(returned_owner).as_ptr(), address);
        run(&mut vm, "EndpointTake", &[receiver]);
        let message = pending(&mut vm, returned);
        run(&mut vm, "EndpointOffer", &[sender, message]);
        let arrived = run(&mut vm, "EndpointTake", &[receiver])[1];
        vm.register(arrived);
        assert_eq!(
            vm.bytes_of(owner(&vm, raw(&vm, arrived, "pointer")))
                .as_ptr(),
            address
        );
    }
    #[test]
    fn checkpoint_keeps_aliases_and_pending_messages() {
        let mut vm = fixture();
        let (sender, receiver) = pair(&mut vm, 1, 64);
        let alias = vm.new_table();
        vm.register(alias);
        run(&mut vm, "EndpointBind", &[sender, alias]);
        let message = pending(&mut vm, Value::num(17.0));
        let bytes = persist::save_graph_with(
            &mut vm,
            &[sender, alias, receiver, message],
            &Policies::default(),
            Some(&mut crate::channels::codecs(Default::default(), false)),
            false,
        )
        .unwrap();
        let mut restored = fixture();
        let roots = persist::load_graph_with(
            &mut restored,
            &bytes,
            &Policies::default(),
            None,
            Some(&mut crate::channels::codecs(Default::default(), false)),
            false,
            None,
        )
        .unwrap();
        for &root in &roots {
            restored.register(root);
        }
        assert!(Arc::ptr_eq(
            &endpoint(&restored, roots[0]).unwrap().token,
            &endpoint(&restored, roots[1]).unwrap().token
        ));
        assert_eq!(
            run(&mut restored, "EndpointOffer", &[roots[1], roots[3]]),
            vec![Value::num(0.0)]
        );
        assert_eq!(
            run(&mut restored, "EndpointTake", &[roots[2]]),
            vec![Value::num(0.0), Value::num(17.0)]
        );
    }
    #[test]
    fn receiver_close_discards_unread_messages() {
        let mut vm = fixture();
        let (sender, receiver) = pair(&mut vm, 1, 64);
        let message = pending(&mut vm, Value::num(17.0));
        run(&mut vm, "EndpointOffer", &[sender, message]);
        run(&mut vm, "EndpointClose", &[receiver]);
        let message = pending(&mut vm, Value::NIL);
        assert_eq!(
            run(&mut vm, "EndpointOffer", &[sender, message]),
            vec![Value::num(2.0)]
        );
        assert!(endpoint(&vm, sender)
            .unwrap()
            .token
            .queue
            .lock()
            .unwrap()
            .messages
            .is_empty());
    }
    fn finish(worker: &mut crate::workers::Worker) -> crate::workers::Progress {
        for _ in 0..2000 {
            worker.step(0).unwrap();
            if let Some(progress) = worker.poll().unwrap() {
                if progress.status != crate::scheduler::Status::Active {
                    return progress;
                }
            }
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
        panic!("worker did not finish");
    }
    #[test]
    fn endpoint_transfer_consumes_the_parent_and_delivers_across_vms() {
        let mut vm = fixture();
        let (sender, receiver) = pair(&mut vm, 1, 64);
        let mut worker =
            crate::workers::Worker::spawn(&mut vm, Value::func(1), &[receiver]).unwrap();
        assert_eq!(direction(&vm, receiver), None);
        let message = pending(&mut vm, Value::num(17.0));
        run(&mut vm, "EndpointOffer", &[sender, message]);
        let result = finish(&mut worker);
        assert_eq!(result.status, crate::scheduler::Status::Completed);
        let result = result.load_values(&mut vm).unwrap();
        assert_eq!(vm.bytes_of(result[0]), b"value");
        assert_eq!(result[1], Value::num(17.0));
    }
    #[test]
    fn typed_record_facades_keep_their_methods_when_transferred() {
        let mut vm = fixture();
        let (sender, receiver) = pair(&mut vm, 1, 64);
        let facade = vm.new_record(1);
        vm.register(facade);
        run(&mut vm, "EndpointBind", &[receiver, facade]);
        let mut worker = crate::workers::Worker::spawn(&mut vm, Value::func(4), &[facade]).unwrap();
        assert_eq!(direction(&vm, facade), None);
        let message = pending(&mut vm, Value::num(41.0));
        run(&mut vm, "EndpointOffer", &[sender, message]);
        let result = finish(&mut worker);
        assert_eq!(result.status, crate::scheduler::Status::Completed);
        let result = result.load_values(&mut vm).unwrap();
        assert_eq!(vm.bytes_of(result[0]), b"value");
        assert_eq!(result[1], Value::num(41.0));
    }
    #[test]
    fn collecting_a_record_facade_releases_its_channel_direction() {
        let mut vm = fixture();
        let (sender, receiver) = pair(&mut vm, 1, 64);
        let receiver_root = vm.registered.iter().position(|&v| v == receiver).unwrap();
        let facade = vm.new_record(1);
        let facade_root = vm.register(facade);
        run(&mut vm, "EndpointBind", &[receiver, facade]);
        vm.release(receiver_root);
        vm.full_cycle();
        assert!(
            !endpoint(&vm, sender)
                .unwrap()
                .token
                .queue
                .lock()
                .unwrap()
                .receiver_closed
        );
        vm.release(facade_root);
        vm.full_cycle();
        assert!(!vm.heap.channels.contains_key(&facade));
        let message = pending(&mut vm, Value::NIL);
        assert_eq!(
            run(&mut vm, "EndpointOffer", &[sender, message]),
            vec![Value::num(2.0)]
        );
    }
    #[test]
    fn affine_cleanup_closes_an_endpoint_through_the_builtin_path() {
        let mut vm = fixture();
        let (sender, receiver) = pair(&mut vm, 1, 64);
        let facade = vm.new_record(1);
        vm.register(facade);
        run(&mut vm, "EndpointBind", &[receiver, facade]);
        let state = vm.new_table();
        vm.register(state);
        put(&mut vm, state, "handle", facade);
        vm.nonsuspending_cleanup = 1;
        let close =
            Value::builtin(crate::builtins::id_of("tasks.channelEndpointCloseState").unwrap());
        vm.call_value(close, &[state]);
        vm.nonsuspending_cleanup = 0;
        assert_eq!(direction(&vm, facade), None);
        let message = pending(&mut vm, Value::NIL);
        assert_eq!(
            run(&mut vm, "EndpointOffer", &[sender, message]),
            vec![Value::num(2.0)]
        );
    }
    #[test]
    fn cancelling_a_parked_publisher_closes_its_transferred_sender() {
        let mut vm = fixture();
        let (sender, receiver) = pair(&mut vm, 1, 64);
        let mut worker = crate::workers::Worker::spawn(&mut vm, Value::func(2), &[sender]).unwrap();
        for _ in 0..2000 {
            worker.step(0).unwrap();
            worker.poll().unwrap();
            if ready(&endpoint(&vm, receiver).unwrap(), 0) == 0 {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
        worker.cancel();
        assert_eq!(
            finish(&mut worker).status,
            crate::scheduler::Status::Cancelled
        );
        drop(worker);
        assert_eq!(
            run(&mut vm, "EndpointTake", &[receiver]),
            vec![Value::num(0.0), Value::num(1.0)]
        );
        assert_eq!(
            run(&mut vm, "EndpointTake", &[receiver]),
            vec![Value::num(2.0), Value::NIL]
        );
    }
    #[test]
    fn nested_endpoint_admission_does_not_consume_the_owner() {
        let mut vm = fixture();
        let (_, receiver) = pair(&mut vm, 1, 64);
        let nested = vm.new_table();
        vm.register(nested);
        put(&mut vm, nested, "receiver", receiver);
        let error = crate::workers::Worker::spawn(&mut vm, Value::func(0), &[nested])
            .err()
            .unwrap();
        assert!(error.contains("direct worker arguments"), "{error}");
        assert_eq!(direction(&vm, receiver), Some(0));
    }
    #[test]
    fn cancelling_a_queued_worker_closes_its_startup_endpoint() {
        let mut vm = fixture();
        let (sender, receiver) = pair(&mut vm, 1, 64);
        let task = vm.fork_inner(Value::func(1), &[receiver], None).unwrap();
        assert_eq!(direction(&vm, receiver), None);
        assert!(vm.cancel_queued_worker(task).is_some());
        let message = pending(&mut vm, Value::NIL);
        assert_eq!(
            run(&mut vm, "EndpointOffer", &[sender, message]),
            vec![Value::num(2.0)]
        );
    }
    #[test]
    fn checkpointing_a_queued_worker_does_not_close_its_startup_endpoint() {
        let mut vm = fixture();
        let (sender, receiver) = pair(&mut vm, 1, 64);
        vm.fork_inner(Value::func(1), &[receiver], None).unwrap();
        persist::save_vm(&mut vm, &Policies::default(), &mut Default::default()).unwrap();
        let message = pending(&mut vm, Value::NIL);
        assert_eq!(
            run(&mut vm, "EndpointOffer", &[sender, message]),
            vec![Value::num(0.0)]
        );
    }
    #[test]
    fn a_restored_queued_worker_keeps_its_endpoint_until_admission() {
        let mut vm = fixture();
        let (sender, receiver) = pair(&mut vm, 1, 64);
        let task = vm.fork_inner(Value::func(1), &[receiver], None).unwrap();
        let globals = vm.loaded["_G"];
        put(&mut vm, globals, "checkpointSender", sender);
        let bytes =
            persist::save_vm(&mut vm, &Policies::default(), &mut Default::default()).unwrap();
        drop(vm);
        let mut restored =
            persist::load_vm(&bytes, &Policies::default(), &mut Default::default()).unwrap();
        let globals = restored.loaded["_G"];
        let sender = field(&mut restored, globals, "checkpointSender");
        let message = pending(&mut restored, Value::num(37.0));
        assert_eq!(
            run(&mut restored, "EndpointOffer", &[sender, message]),
            vec![Value::num(0.0)]
        );
        for _ in 0..2000 {
            restored.run_ready(8).unwrap();
            if restored.scheduler.as_ref().unwrap().status(task)
                == Some(&crate::scheduler::Status::Completed)
            {
                assert_eq!(restored.tasks[task.index].results[1], Value::num(37.0));
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
        panic!("restored queued worker did not receive the message");
    }
    #[test]
    fn whole_vm_checkpoint_reconnects_a_waiting_worker_to_its_sender() {
        let mut vm = fixture();
        let (sender, receiver) = pair(&mut vm, 1, 64);
        let task = vm.schedule(Value::func(3), &[receiver], None).unwrap();
        for _ in 0..4 {
            vm.run_ready(8).unwrap();
        }
        assert!(vm.has_workers());
        let globals = vm.loaded["_G"];
        put(&mut vm, globals, "checkpointSender", sender);
        let bytes =
            persist::save_vm(&mut vm, &Policies::default(), &mut Default::default()).unwrap();
        drop(vm);
        let mut restored =
            persist::load_vm(&bytes, &Policies::default(), &mut Default::default()).unwrap();
        restored.heap.stress = true;
        let globals = restored.loaded["_G"];
        let sender = field(&mut restored, globals, "checkpointSender");
        let message = pending(&mut restored, Value::num(29.0));
        assert_eq!(
            run(&mut restored, "EndpointOffer", &[sender, message]),
            vec![Value::num(0.0)]
        );
        for _ in 0..2000 {
            restored.run_ready(8).unwrap();
            if restored.scheduler.as_ref().unwrap().status(task)
                == Some(&crate::scheduler::Status::Completed)
            {
                assert_eq!(restored.tasks[task.index].results[1], Value::num(29.0));
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
        panic!("restored worker did not receive the message");
    }
}
