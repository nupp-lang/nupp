//! Rust ownership behind `nupp.host` requests to an embedding application.
//!
//! `host_shim.c` reads and writes the Lua stack and calls the application's
//! handlers; this side owns the registrations, which requests are outstanding,
//! and every answer from `nupp_host_answer` until the shim has copied it into
//! Lua values. An answer is only ever queued here, never delivered from inside
//! the call that gave it, so a handler that answers at once and one that answers
//! from its own loop reach Lua the same way: through the next poll.

#![deny(unsafe_op_in_unsafe_fn)]
#![deny(clippy::undocumented_unsafe_blocks)]

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::ffi::{c_char, c_int, c_void};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;
use std::slice;

/// The most values one request or answer carries.
pub(crate) const MAX_VALUES: usize = 255;
/// The longest string value, which the browser carries inside a text envelope.
pub(crate) const MAX_STRING_BYTES: usize = 64 * 1024;
/// The largest byte value an application may answer with.
pub(crate) const MAX_ANSWER_BYTES: usize = 16 * 1024 * 1024;

pub(crate) const VALUE_NIL: u32 = 0;
pub(crate) const VALUE_BOOLEAN: u32 = 1;
pub(crate) const VALUE_NUMBER: u32 = 2;
pub(crate) const VALUE_STRING: u32 = 3;
pub(crate) const VALUE_BYTES: u32 = 4;

/// The layout of `nupp_value`, which the shim reads answers through.
#[repr(C)]
#[derive(Clone, Copy)]
pub(crate) struct RawValue {
    pub kind: u32,
    pub boolean: c_int,
    pub number: f64,
    pub data: *mut u8,
    pub length: usize,
    pub handle: *mut c_void,
}

pub(crate) type HostHandler = unsafe extern "C" fn(
    runtime: *mut c_void,
    request: u64,
    kind: *const c_char,
    arguments: *const RawValue,
    count: usize,
    userdata: *mut c_void,
);
pub(crate) type HostCancel =
    unsafe extern "C" fn(runtime: *mut c_void, request: u64, userdata: *mut c_void);

#[derive(Clone, Copy)]
struct Registration {
    handler: HostHandler,
    cancel: Option<HostCancel>,
    userdata: *mut c_void,
}

/// One value of an answer, owned until the shim has copied it.
pub(crate) enum Owned {
    Nil,
    Boolean(bool),
    Number(f64),
    Text(Vec<u8>),
    Bytes(Vec<u8>),
}

enum State {
    Waiting,
    // `raw` points into `_owned`, which is kept only to keep those bytes alive.
    Answered { _owned: Vec<Owned>, raw: Vec<RawValue> },
    Failed(Vec<u8>),
}

struct Request {
    kind: Vec<u8>,
    post: bool,
    cancelled: bool,
    state: State,
}

/// Why an answer was refused.
pub(crate) enum AnswerError {
    Unknown,
    AlreadyAnswered,
}

/// One runtime's registered kinds and outstanding requests.
pub(crate) struct HostChannel {
    runtime: Cell<*mut c_void>,
    handlers: RefCell<HashMap<Vec<u8>, Registration>>,
    requests: RefCell<HashMap<u64, Request>>,
    ready: RefCell<VecDeque<u64>>,
}

impl HostChannel {
    pub(crate) fn new() -> Self {
        Self {
            runtime: Cell::new(ptr::null_mut()),
            handlers: RefCell::new(HashMap::new()),
            requests: RefCell::new(HashMap::new()),
            ready: RefCell::new(VecDeque::new()),
        }
    }

    /// The runtime pointer handed to every handler as its first argument.
    pub(crate) fn set_runtime(&self, runtime: *mut c_void) {
        self.runtime.set(runtime);
    }

    /// Registers, replaces or (with no handler) removes a kind's handler.
    pub(crate) fn register(
        &self,
        kind: &[u8],
        handler: Option<HostHandler>,
        cancel: Option<HostCancel>,
        userdata: *mut c_void,
    ) {
        let mut handlers = self.handlers.borrow_mut();
        match handler {
            Some(handler) => {
                handlers.insert(
                    kind.to_vec(),
                    Registration {
                        handler,
                        cancel,
                        userdata,
                    },
                );
            }
            None => {
                handlers.remove(kind);
            }
        }
    }

    /// Stores a request's answer, copying every value.
    pub(crate) fn answer(&self, request: u64, owned: Vec<Owned>) -> Result<(), AnswerError> {
        let mut requests = self.requests.borrow_mut();
        let entry = requests.get_mut(&request).ok_or(AnswerError::Unknown)?;
        if !matches!(entry.state, State::Waiting) {
            return Err(AnswerError::AlreadyAnswered);
        }
        if entry.post {
            // Nobody waits on a post: its answer is the application's to drop.
            requests.remove(&request);
            return Ok(());
        }
        let raw = owned.iter().map(raw_value).collect();
        entry.state = State::Answered { _owned: owned, raw };
        drop(requests);
        self.ready.borrow_mut().push_back(request);
        Ok(())
    }

    /// Stores a request's failure.
    pub(crate) fn fail(&self, request: u64, message: Vec<u8>) -> Result<(), AnswerError> {
        let mut requests = self.requests.borrow_mut();
        let entry = requests.get_mut(&request).ok_or(AnswerError::Unknown)?;
        if !matches!(entry.state, State::Waiting) {
            return Err(AnswerError::AlreadyAnswered);
        }
        if entry.post {
            let kind = String::from_utf8_lossy(&entry.kind).into_owned();
            requests.remove(&request);
            eprintln!(
                "nupp: host {kind}: post failed: {}",
                String::from_utf8_lossy(&message)
            );
            return Ok(());
        }
        entry.state = State::Failed(message);
        drop(requests);
        self.ready.borrow_mut().push_back(request);
        Ok(())
    }

    /// Forgets every outstanding request, for a runtime shutting down.
    pub(crate) fn clear(&self) {
        self.requests.borrow_mut().clear();
        self.ready.borrow_mut().clear();
    }
}

fn raw_value(value: &Owned) -> RawValue {
    let mut raw = RawValue {
        kind: VALUE_NIL,
        boolean: 0,
        number: 0.0,
        data: ptr::null_mut(),
        length: 0,
        handle: ptr::null_mut(),
    };
    match value {
        Owned::Nil => {}
        Owned::Boolean(boolean) => {
            raw.kind = VALUE_BOOLEAN;
            raw.boolean = c_int::from(*boolean);
        }
        Owned::Number(number) => {
            raw.kind = VALUE_NUMBER;
            raw.number = *number;
        }
        Owned::Text(bytes) | Owned::Bytes(bytes) => {
            raw.kind = if matches!(value, Owned::Text(_)) {
                VALUE_STRING
            } else {
                VALUE_BYTES
            };
            // The vector's heap buffer stays put while the answer is stored,
            // whatever moves the vector itself.
            raw.data = bytes.as_ptr().cast_mut();
            raw.length = bytes.len();
        }
    }
    raw
}

fn ffi_value<T>(fallback: T, body: impl FnOnce() -> T) -> T {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or(fallback)
}

/// # Safety
/// `channel` is the live `HostChannel` the runtime installed; the shim reads it
/// from the state's globals and only on that state's owner thread.
unsafe fn channel<'a>(channel: *const c_void) -> &'a HostChannel {
    // SAFETY: see the function's contract.
    unsafe { &*channel.cast::<HostChannel>() }
}

unsafe extern "C" fn lookup(
    channel_pointer: *const c_void,
    kind: *const c_char,
    length: usize,
    handler: *mut Option<HostHandler>,
    userdata: *mut *mut c_void,
    runtime: *mut *mut c_void,
) -> c_int {
    ffi_value(0, || {
        // SAFETY: the shim passes its installed channel and a borrowed kind.
        let channel = unsafe { channel(channel_pointer) };
        // SAFETY: `kind` is a Lua string of `length` bytes live on the stack.
        let kind = unsafe { slice::from_raw_parts(kind.cast::<u8>(), length) };
        let Some(found) = channel.handlers.borrow().get(kind).copied() else {
            return 0;
        };
        // SAFETY: the out pointers are the shim's locals.
        unsafe {
            handler.write(Some(found.handler));
            userdata.write(found.userdata);
            runtime.write(channel.runtime.get());
        }
        1
    })
}

unsafe extern "C" fn dispatched(
    channel_pointer: *const c_void,
    request: u64,
    post: c_int,
    kind: *const c_char,
    length: usize,
) -> c_int {
    ffi_value(0, || {
        // SAFETY: as in `lookup`.
        let channel = unsafe { channel(channel_pointer) };
        // SAFETY: `kind` is a Lua string of `length` bytes live on the stack.
        let kind = unsafe { slice::from_raw_parts(kind.cast::<u8>(), length) };
        let mut requests = channel.requests.borrow_mut();
        if requests.contains_key(&request) {
            return 0;
        }
        requests.insert(
            request,
            Request {
                kind: kind.to_vec(),
                post: post != 0,
                cancelled: false,
                state: State::Waiting,
            },
        );
        1
    })
}

unsafe extern "C" fn answer(
    channel_pointer: *const c_void,
    request: u64,
    count: *mut usize,
    values: *mut *const RawValue,
    message: *mut *const c_char,
    message_length: *mut usize,
) -> c_int {
    ffi_value(0, || {
        // SAFETY: as in `lookup`.
        let channel = unsafe { channel(channel_pointer) };
        let requests = channel.requests.borrow();
        let Some(entry) = requests.get(&request) else {
            return 0;
        };
        match &entry.state {
            State::Waiting => 0,
            State::Answered { raw, .. } => {
                // SAFETY: the out pointers are the shim's locals; the answer
                // stays stored until the shim calls `release`.
                unsafe {
                    count.write(raw.len());
                    values.write(raw.as_ptr());
                }
                1
            }
            State::Failed(text) => {
                // SAFETY: as above.
                unsafe {
                    message.write(text.as_ptr().cast());
                    message_length.write(text.len());
                }
                2
            }
        }
    })
}

unsafe extern "C" fn release(channel_pointer: *const c_void, request: u64) {
    ffi_value((), || {
        // SAFETY: as in `lookup`.
        let channel = unsafe { channel(channel_pointer) };
        channel.requests.borrow_mut().remove(&request);
    });
}

unsafe extern "C" fn ready(channel_pointer: *const c_void, requests: *mut u64, capacity: usize) -> usize {
    ffi_value(0, || {
        // SAFETY: as in `lookup`.
        let channel = unsafe { channel(channel_pointer) };
        let mut ready = channel.ready.borrow_mut();
        let taken = capacity.min(ready.len());
        for index in 0..taken {
            let request = ready.pop_front().expect("counted above");
            // SAFETY: `requests` has room for `capacity` ids.
            unsafe { requests.add(index).write(request) };
        }
        taken
    })
}

unsafe extern "C" fn cancelled(
    channel_pointer: *const c_void,
    request: u64,
    cancel: *mut Option<HostCancel>,
    userdata: *mut *mut c_void,
    runtime: *mut *mut c_void,
) -> c_int {
    ffi_value(0, || {
        // SAFETY: as in `lookup`.
        let channel = unsafe { channel(channel_pointer) };
        let mut requests = channel.requests.borrow_mut();
        let Some(entry) = requests.get_mut(&request) else {
            return 0;
        };
        if entry.cancelled {
            return 0;
        }
        entry.cancelled = true;
        if !matches!(entry.state, State::Waiting) {
            return 0;
        }
        let kind = entry.kind.clone();
        drop(requests);
        let Some(found) = channel.handlers.borrow().get(&kind).copied() else {
            return 0;
        };
        let Some(callback) = found.cancel else {
            return 0;
        };
        // SAFETY: the out pointers are the shim's locals.
        unsafe {
            cancel.write(Some(callback));
            userdata.write(found.userdata);
            runtime.write(channel.runtime.get());
        }
        1
    })
}

#[repr(C)]
struct HostAdapterTable {
    lookup: unsafe extern "C" fn(
        *const c_void,
        *const c_char,
        usize,
        *mut Option<HostHandler>,
        *mut *mut c_void,
        *mut *mut c_void,
    ) -> c_int,
    dispatched: unsafe extern "C" fn(*const c_void, u64, c_int, *const c_char, usize) -> c_int,
    answer: unsafe extern "C" fn(
        *const c_void,
        u64,
        *mut usize,
        *mut *const RawValue,
        *mut *const c_char,
        *mut usize,
    ) -> c_int,
    release: unsafe extern "C" fn(*const c_void, u64),
    ready: unsafe extern "C" fn(*const c_void, *mut u64, usize) -> usize,
    cancelled: unsafe extern "C" fn(
        *const c_void,
        u64,
        *mut Option<HostCancel>,
        *mut *mut c_void,
        *mut *mut c_void,
    ) -> c_int,
}

static HOST_ADAPTER: HostAdapterTable = HostAdapterTable {
    lookup,
    dispatched,
    answer,
    release,
    ready,
    cancelled,
};

unsafe extern "C" {
    fn nupp_host_shim_install(table: *const HostAdapterTable);
}

/// Gives the shim its table, once per process, before any state can open the
/// host module.
pub(crate) fn install_shim() {
    static INSTALLED: std::sync::Once = std::sync::Once::new();
    INSTALLED.call_once(|| {
        // SAFETY: the table is a static that lives for the whole process, and
        // the shim only stores the pointer.
        unsafe { nupp_host_shim_install(&raw const HOST_ADAPTER) };
    });
}
