//! Bounded cross-VM channels carry serialized graphs, never heap pointers.
use crate::{
    interp::Interp,
    persist::{self, Policies, ResourceCodec, ResourceCodecs},
    task_api::{put, Answer},
    value::Value,
};
use std::{
    collections::{HashMap, VecDeque},
    sync::{Arc, Mutex, Weak},
};
type Result<T> = std::result::Result<T, String>;
pub(crate) const KIND: &str = "nupp.channel";
#[derive(Default)]
pub(crate) struct Registry {
    next: u64,
    channels: HashMap<u64, Weak<Mutex<Queue>>>,
}
pub(crate) type Shared = Arc<Mutex<Registry>>;
pub(crate) struct Queue {
    id: u64,
    capacity: usize,
    closed: bool,
    messages: VecDeque<Vec<u8>>,
}
pub(crate) type Channel = Arc<Mutex<Queue>>;
pub(crate) struct Codec {
    pub registry: Shared,
    pub transfer: bool,
}
impl ResourceCodec for Codec {
    fn save(&mut self, vm: &Interp, object: Value) -> Result<Vec<u8>> {
        let q = vm
            .heap
            .channels
            .get(&object)
            .ok_or("unknown channel")?
            .lock()
            .map_err(|e| e.to_string())?;
        let mut b = vec![if self.transfer { 0 } else { 1 }];
        b.extend(q.id.to_le_bytes());
        if !self.transfer {
            b.extend((q.capacity as u64).to_le_bytes());
            b.push(q.closed as u8);
            b.extend((q.messages.len() as u64).to_le_bytes());
            for m in &q.messages {
                b.extend((m.len() as u64).to_le_bytes());
                b.extend(m);
            }
        }
        Ok(b)
    }
    fn restore(&mut self, vm: &mut Interp, object: Value, data: &[u8]) -> Result<()> {
        fn take<'a>(b: &mut &'a [u8], n: usize) -> Result<&'a [u8]> {
            if b.len() < n {
                return Err("truncated channel".into());
            }
            let (head, tail) = b.split_at(n);
            *b = tail;
            Ok(head)
        }
        fn num(b: &mut &[u8]) -> Result<u64> {
            Ok(u64::from_le_bytes(take(b, 8)?.try_into().unwrap()))
        }
        let mut b = data;
        let mode = take(&mut b, 1)?[0];
        let id = num(&mut b)?;
        let restored = if mode == 1 {
            let cap = num(&mut b)?;
            if cap == 0 || cap > 1_000_000 {
                return Err("invalid channel capacity".into());
            }
            let closed = take(&mut b, 1)?[0] != 0;
            let count = num(&mut b)?;
            if count > cap {
                return Err("channel exceeds capacity".into());
            }
            let mut messages = VecDeque::new();
            for _ in 0..count {
                let n = num(&mut b)?;
                let n = usize::try_from(n).map_err(|_| "message too large")?;
                messages.push_back(take(&mut b, n)?.to_vec());
            }
            Some(Queue {
                id,
                capacity: cap as usize,
                closed,
                messages,
            })
        } else if mode == 0 {
            None
        } else {
            return Err("unknown channel format".into());
        };
        if !b.is_empty() {
            return Err("trailing channel data".into());
        }
        let channel = {
            let mut registry = self.registry.lock().map_err(|e| e.to_string())?;
            if let Some(q) = registry.channels.get(&id).and_then(Weak::upgrade) {
                q
            } else {
                let q = Arc::new(Mutex::new(
                    restored.ok_or("channel transfer requires its source registry")?,
                ));
                registry.next = registry.next.max(id);
                registry.channels.insert(id, Arc::downgrade(&q));
                q
            }
        };
        vm.heap.channels.insert(object, channel);
        install_methods(vm, object);
        Ok(())
    }
}
fn install_methods(vm: &mut Interp, object: Value) {
    for (n, b) in [
        ("share", "tasks.channelShare"),
        ("send", "tasks.channelSend"),
        ("receive", "tasks.channelReceive"),
        ("close", "tasks.channelClose"),
    ] {
        put(
            vm,
            object,
            n,
            Value::builtin(crate::builtins::id_of(b).unwrap()),
        );
    }
}
pub(crate) fn codecs(registry: Shared, transfer: bool) -> ResourceCodecs {
    let mut c = ResourceCodecs::default();
    c.insert(KIND.into(), Box::new(Codec { registry, transfer }));
    c
}
pub(crate) fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Answer {
    let at = |i| args.get(i).copied().unwrap_or(Value::NIL);
    if name == "tasks.channel" {
        let cap = at(0);
        if !cap.is_num()
            || cap.as_num() < 1.0
            || cap.as_num() > 1_000_000.0
            || cap.as_num().fract() != 0.0
        {
            vm.err("channel capacity must be an integer from 1 to 1000000");
        }
        let channel = {
            let mut r = vm.channel_registry.lock().unwrap();
            r.next = r.next.checked_add(1).expect("channel id overflow");
            let id = r.next;
            r.channels.retain(|_, q| q.strong_count() > 0);
            let c = Arc::new(Mutex::new(Queue {
                id,
                capacity: cap.as_num() as usize,
                closed: false,
                messages: VecDeque::new(),
            }));
            r.channels.insert(id, Arc::downgrade(&c));
            c
        };
        let object = vm.new_table();
        let root = vm.register(object);
        vm.heap.channels.insert(object, channel);
        install_methods(vm, object);
        vm.release(root);
        return Answer::Values(vec![object]);
    }
    let object = at(0);
    if name == "tasks.channelShare" {
        return Answer::Values(vec![object]);
    }
    if !vm.heap.channels.contains_key(&object)
        && crate::task_api::field(vm, object, "_closed") == Value::TRUE
    {
        return match name {
            "tasks.channelClose" => Answer::Values(vec![]),
            "tasks.channelReceive" => Answer::Values(vec![Value::NIL, Value::FALSE]),
            _ => vm.err("send on closed channel"),
        };
    }
    let channel = vm
        .heap
        .channels
        .get(&object)
        .cloned()
        .unwrap_or_else(|| vm.err("invalid channel"));
    match name {
        "tasks.channelClose" => {
            channel.lock().unwrap().closed = true;
            put(vm, object, "_closed", Value::TRUE);
            crate::task_api::wake_event(vm, object);
            if channel.lock().unwrap().messages.is_empty() {
                vm.heap.channels.remove(&object);
                vm.resources.remove(&object);
            }
            Answer::Values(vec![])
        }
        "tasks.channelSend" => {
            {
                let q = channel.lock().unwrap();
                if q.closed {
                    vm.err("send on closed channel");
                }
                if q.messages.len() == q.capacity {
                    return Answer::Event(object);
                }
            }
            let bytes = persist::save_graph(vm, &[at(1)], &Policies::default())
                .unwrap_or_else(|e| vm.err(&e));
            let mut q = channel.lock().unwrap();
            if q.closed {
                vm.err("send on closed channel");
            }
            if q.messages.len() == q.capacity {
                return Answer::Event(object);
            }
            q.messages.push_back(bytes);
            drop(q);
            crate::task_api::wake_event(vm, object);
            Answer::Values(vec![])
        }
        "tasks.channelReceive" => {
            let bytes = {
                let mut q = channel.lock().unwrap();
                if let Some(b) = q.messages.pop_front() {
                    Some(b)
                } else if q.closed {
                    return Answer::Values(vec![Value::NIL, Value::FALSE]);
                } else {
                    None
                }
            };
            if let Some(b) = bytes {
                crate::task_api::wake_event(vm, object);
                if {
                    let q = channel.lock().unwrap();
                    q.closed && q.messages.is_empty()
                } {
                    put(vm, object, "_closed", Value::TRUE);
                    crate::task_api::wake_event(vm, object);
                    vm.heap.channels.remove(&object);
                    vm.resources.remove(&object);
                }
                let values = persist::load_graph(vm, &b, &Policies::default(), None)
                    .unwrap_or_else(|e| vm.err(&e));
                Answer::Values(vec![values[0], Value::TRUE])
            } else {
                Answer::Event(object)
            }
        }
        _ => vm.err("unknown channel operation"),
    }
}
impl Interp {
    pub(crate) fn poll_channels(&mut self) {
        let Some(s) = &self.scheduler else {
            return;
        };
        let waiters: Vec<_> = s
            .controls
            .iter()
            .filter_map(|(&tid, c)| {
                if c.status == crate::scheduler::Status::Active {
                    if let crate::interp::State::Parked(k) = self.tasks[tid].state {
                        let value = Value(k);
                        if self.heap.channels.contains_key(&value) {
                            return Some(value);
                        }
                    }
                    None
                } else {
                    None
                }
            })
            .collect();
        // A parked sender and receiver can share an endpoint. Both retry atomically;
        // no message is removed until its receiving turn owns the queue lock.
        for value in waiters {
            crate::task_api::wake_event(self, value);
        }
    }
}
