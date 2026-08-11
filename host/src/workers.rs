//! Bounded byte channels and fresh-state worker threads.
//!
//! Lua owns validation, serialization, and request routing. This module owns
//! only byte copies, thread lifecycle, and bootstrapping the selected module in
//! another LuaJIT state.

use crate::lua::{Lua, lua_State as LuaState};
use std::collections::VecDeque;
use std::ffi::{c_char, c_int, c_void};
use std::slice;
use std::sync::{Arc, Condvar, Mutex, MutexGuard, OnceLock};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

const MAX_CHANNEL_MESSAGES: usize = 1024;
const MAX_CHANNEL_BYTES: usize = 256 * 1024 * 1024;

static PAYLOAD: OnceLock<Arc<[u8]>> = OnceLock::new();
static CLOCK: OnceLock<Instant> = OnceLock::new();

struct ChannelState {
    messages: VecDeque<Box<[u8]>>,
    bytes: usize,
    closed: bool,
}

struct Channel {
    state: Mutex<ChannelState>,
    arrived: Condvar,
}

struct Worker {
    thread: Option<JoinHandle<c_int>>,
    error: Arc<Mutex<Option<String>>>,
}

unsafe extern "C" {
    fn lua_getfield(state: *mut LuaState, index: c_int, name: *const c_char);
    fn lua_createtable(state: *mut LuaState, narr: c_int, nrec: c_int);
    fn lua_pushboolean(state: *mut LuaState, value: c_int);
    fn lua_pushcclosure(
        state: *mut LuaState,
        function: unsafe extern "C" fn(*mut LuaState) -> c_int,
        upvalues: c_int,
    );
    fn lua_pushinteger(state: *mut LuaState, value: isize);
    fn lua_pushlightuserdata(state: *mut LuaState, value: *mut c_void);
    fn lua_pushlstring(state: *mut LuaState, value: *const c_char, length: usize);
    fn lua_pushnil(state: *mut LuaState);
    fn lua_pushnumber(state: *mut LuaState, value: f64);
    fn lua_setfield(state: *mut LuaState, index: c_int, name: *const c_char);
    fn lua_tolstring(state: *mut LuaState, index: c_int, length: *mut usize) -> *const c_char;
    fn lua_tointeger(state: *mut LuaState, index: c_int) -> isize;
    fn lua_touserdata(state: *mut LuaState, index: c_int) -> *mut c_void;
}

const LUA_GLOBALS_INDEX: c_int = -10_002;

pub(crate) fn set_payload(payload: Vec<u8>) {
    let _ = PAYLOAD.set(payload.into());
}

fn lock_channel(channel: &Channel) -> MutexGuard<'_, ChannelState> {
    channel
        .state
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn new_channel() -> *mut Channel {
    Box::into_raw(Box::new(Channel {
        state: Mutex::new(ChannelState {
            messages: VecDeque::new(),
            bytes: 0,
            closed: false,
        }),
        arrived: Condvar::new(),
    }))
}

unsafe fn close_channel(channel: *mut Channel) {
    let Some(channel) = (unsafe { channel.as_ref() }) else {
        return;
    };
    let mut state = lock_channel(channel);
    state.closed = true;
    channel.arrived.notify_all();
}

unsafe fn push_channel(channel: *mut Channel, bytes: Box<[u8]>) -> bool {
    let Some(channel) = (unsafe { channel.as_ref() }) else {
        return false;
    };
    let mut state = lock_channel(channel);
    if state.closed
        || state.messages.len() >= MAX_CHANNEL_MESSAGES
        || state.bytes.saturating_add(bytes.len()) > MAX_CHANNEL_BYTES
    {
        return false;
    }
    state.bytes += bytes.len();
    state.messages.push_back(bytes);
    channel.arrived.notify_one();
    true
}

unsafe fn pop_channel(channel: *mut Channel, timeout_ms: i32) -> Option<Box<[u8]>> {
    let channel = unsafe { channel.as_ref() }?;
    let mut state = lock_channel(channel);
    if timeout_ms < 0 {
        while state.messages.is_empty() && !state.closed {
            state = channel
                .arrived
                .wait(state)
                .unwrap_or_else(std::sync::PoisonError::into_inner);
        }
    } else if timeout_ms > 0 {
        let deadline = Instant::now() + Duration::from_millis(timeout_ms as u64);
        while state.messages.is_empty() && !state.closed {
            let Some(remaining) = deadline.checked_duration_since(Instant::now()) else {
                break;
            };
            let waited = channel
                .arrived
                .wait_timeout(state, remaining)
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state = waited.0;
            if waited.1.timed_out() {
                break;
            }
        }
    }
    let bytes = state.messages.pop_front()?;
    state.bytes = state.bytes.saturating_sub(bytes.len());
    Some(bytes)
}

unsafe fn pointer<T>(state: *mut LuaState, index: c_int) -> *mut T {
    unsafe { lua_touserdata(state, index).cast() }
}

unsafe fn bytes(state: *mut LuaState, index: c_int) -> Option<Box<[u8]>> {
    let mut length = 0;
    let data = unsafe { lua_tolstring(state, index, &mut length) };
    if data.is_null() {
        None
    } else {
        Some(unsafe { slice::from_raw_parts(data.cast(), length) }.into())
    }
}

unsafe fn push_text(state: *mut LuaState, text: &str) {
    unsafe { lua_pushlstring(state, text.as_ptr().cast(), text.len()) };
}

unsafe extern "C" fn channel_create(state: *mut LuaState) -> c_int {
    unsafe { lua_pushlightuserdata(state, new_channel().cast()) };
    1
}

unsafe extern "C" fn channel_destroy(state: *mut LuaState) -> c_int {
    let channel = unsafe { pointer::<Channel>(state, 1) };
    if !channel.is_null() {
        drop(unsafe { Box::from_raw(channel) });
    }
    0
}

unsafe extern "C" fn channel_close(state: *mut LuaState) -> c_int {
    unsafe { close_channel(pointer(state, 1)) };
    0
}

unsafe extern "C" fn channel_push(state: *mut LuaState) -> c_int {
    let channel = unsafe { pointer(state, 1) };
    let accepted =
        unsafe { bytes(state, 2) }.is_some_and(|message| unsafe { push_channel(channel, message) });
    unsafe { lua_pushboolean(state, accepted as c_int) };
    1
}

unsafe extern "C" fn channel_pop(state: *mut LuaState) -> c_int {
    let channel = unsafe { pointer(state, 1) };
    let timeout = unsafe { lua_tointeger(state, 2) };
    let timeout = i32::try_from(timeout).unwrap_or(if timeout < 0 { i32::MIN } else { i32::MAX });
    match unsafe { pop_channel(channel, timeout) } {
        Some(message) => unsafe {
            lua_pushlstring(state, message.as_ptr().cast(), message.len());
        },
        None => unsafe { lua_pushnil(state) },
    }
    1
}

unsafe extern "C" fn channel_count(state: *mut LuaState) -> c_int {
    let channel = unsafe { pointer::<Channel>(state, 1) };
    let count = unsafe { channel.as_ref() }
        .map(|channel| lock_channel(channel).messages.len())
        .unwrap_or(0);
    unsafe { lua_pushinteger(state, isize::try_from(count).unwrap_or(isize::MAX)) };
    1
}

unsafe extern "C" fn channel_closed(state: *mut LuaState) -> c_int {
    let channel = unsafe { pointer::<Channel>(state, 1) };
    let closed = unsafe { channel.as_ref() }
        .map(|channel| lock_channel(channel).closed)
        .unwrap_or(true);
    unsafe { lua_pushboolean(state, closed as c_int) };
    1
}

fn worker_entry(
    entry: String,
    payload: Arc<[u8]>,
    inbox: usize,
    outbox: usize,
    failure: Arc<Mutex<Option<String>>>,
) -> c_int {
    let result = (|| {
        crate::mcode::release();
        let lua = Lua::new().ok_or_else(|| "cannot create a Lua state".to_owned())?;
        lua.open_libraries();
        lua.set_pointer("__nuppWorkerIn", inbox as *mut Channel as *mut c_void);
        lua.set_pointer("__nuppWorkerOut", outbox as *mut Channel as *mut c_void);
        lua.set_string("__nuppWorkerEntry", &entry);
        lua.set_arg(&[]);
        lua.run(&payload, "=nupp-worker")
    })();
    unsafe { close_channel(inbox as *mut Channel) };
    unsafe { close_channel(outbox as *mut Channel) };
    match result {
        Ok(()) => 0,
        Err(error) => {
            *failure
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(error);
            1
        }
    }
}

unsafe extern "C" fn worker_spawn(state: *mut LuaState) -> c_int {
    let Some(entry) = (unsafe { bytes(state, 1) }) else {
        unsafe { lua_pushnil(state) };
        unsafe { push_text(state, "worker entry must be a string") };
        return 2;
    };
    let Ok(entry) = std::str::from_utf8(&entry) else {
        unsafe { lua_pushnil(state) };
        unsafe { push_text(state, "worker entry must be UTF-8") };
        return 2;
    };
    let Some(payload) = PAYLOAD.get().cloned() else {
        unsafe { lua_pushnil(state) };
        unsafe { push_text(state, "workers require a stamped Nupp payload") };
        return 2;
    };
    let inbox = unsafe { pointer::<Channel>(state, 2) };
    let outbox = unsafe { pointer::<Channel>(state, 3) };
    if inbox.is_null() || outbox.is_null() {
        unsafe { lua_pushnil(state) };
        unsafe { push_text(state, "worker channels are missing") };
        return 2;
    }

    let error = Arc::new(Mutex::new(None));
    let thread_error = Arc::clone(&error);
    let entry = entry.to_owned();
    let inbox_address = inbox as usize;
    let outbox_address = outbox as usize;
    let thread = thread::Builder::new()
        .name(format!("nupp.worker.{entry}"))
        .spawn(move || worker_entry(entry, payload, inbox_address, outbox_address, thread_error));
    let thread = match thread {
        Ok(thread) => thread,
        Err(problem) => {
            unsafe { lua_pushnil(state) };
            unsafe { push_text(state, &format!("cannot start worker: {problem}")) };
            return 2;
        }
    };
    let worker = Box::new(Worker {
        thread: Some(thread),
        error,
    });
    unsafe { lua_pushlightuserdata(state, Box::into_raw(worker).cast()) };
    1
}

unsafe extern "C" fn worker_finished(state: *mut LuaState) -> c_int {
    let worker = unsafe { pointer::<Worker>(state, 1) };
    let finished = unsafe { worker.as_ref() }
        .and_then(|worker| worker.thread.as_ref())
        .is_none_or(JoinHandle::is_finished);
    unsafe { lua_pushboolean(state, finished as c_int) };
    1
}

unsafe extern "C" fn worker_join(state: *mut LuaState) -> c_int {
    let worker = unsafe { pointer::<Worker>(state, 1) };
    if worker.is_null() {
        unsafe { lua_pushinteger(state, 1) };
        unsafe { push_text(state, "worker handle is missing") };
        return 2;
    }
    let mut worker = unsafe { Box::from_raw(worker) };
    let status = worker
        .thread
        .take()
        .map(|thread| thread.join().unwrap_or(1))
        .unwrap_or(1);
    let error = worker
        .error
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .clone();
    unsafe { lua_pushinteger(state, status as isize) };
    match error {
        Some(error) => unsafe { push_text(state, &error) },
        None => unsafe { lua_pushnil(state) },
    }
    2
}

unsafe extern "C" fn current(state: *mut LuaState) -> c_int {
    unsafe { lua_getfield(state, LUA_GLOBALS_INDEX, c"__nuppWorkerIn".as_ptr()) };
    unsafe { lua_getfield(state, LUA_GLOBALS_INDEX, c"__nuppWorkerOut".as_ptr()) };
    2
}

unsafe extern "C" fn now(state: *mut LuaState) -> c_int {
    let elapsed = CLOCK.get_or_init(Instant::now).elapsed().as_secs_f64() * 1000.0;
    unsafe { lua_pushnumber(state, elapsed) };
    1
}

unsafe fn field(
    state: *mut LuaState,
    name: &std::ffi::CStr,
    function: unsafe extern "C" fn(*mut LuaState) -> c_int,
) {
    unsafe {
        lua_pushcclosure(state, function, 0);
        lua_setfield(state, -2, name.as_ptr());
    }
}

pub(crate) unsafe extern "C" fn luaopen(state: *mut LuaState) -> c_int {
    unsafe { lua_createtable(state, 0, 12) };
    unsafe { field(state, c"channelCreate", channel_create) };
    unsafe { field(state, c"channelDestroy", channel_destroy) };
    unsafe { field(state, c"channelClose", channel_close) };
    unsafe { field(state, c"channelPush", channel_push) };
    unsafe { field(state, c"channelPop", channel_pop) };
    unsafe { field(state, c"channelCount", channel_count) };
    unsafe { field(state, c"channelClosed", channel_closed) };
    unsafe { field(state, c"workerSpawn", worker_spawn) };
    unsafe { field(state, c"workerFinished", worker_finished) };
    unsafe { field(state, c"workerJoin", worker_join) };
    unsafe { field(state, c"current", current) };
    unsafe { field(state, c"now", now) };
    1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn channel_is_fifo_and_drains_after_close() {
        let channel = new_channel();
        unsafe {
            assert!(push_channel(channel, Box::from(&b"one"[..])));
            assert!(push_channel(channel, Box::from(&b"two"[..])));
            close_channel(channel);
            assert_eq!(pop_channel(channel, 0).as_deref(), Some(&b"one"[..]));
            assert_eq!(pop_channel(channel, 0).as_deref(), Some(&b"two"[..]));
            assert!(pop_channel(channel, 0).is_none());
            assert!(!push_channel(channel, Box::from(&b"three"[..])));
            drop(Box::from_raw(channel));
        }
    }

    #[test]
    fn channel_refuses_more_than_its_message_bound() {
        let channel = new_channel();
        unsafe {
            for _ in 0..MAX_CHANNEL_MESSAGES {
                assert!(push_channel(channel, Box::from(&b"x"[..])));
            }
            assert!(!push_channel(channel, Box::from(&b"overflow"[..])));
            drop(Box::from_raw(channel));
        }
    }

    #[test]
    fn channel_refuses_more_than_its_byte_bound() {
        let channel = new_channel();
        unsafe {
            lock_channel(&*channel).bytes = MAX_CHANNEL_BYTES;
            assert!(!push_channel(channel, Box::from(&b"overflow"[..])));
            drop(Box::from_raw(channel));
        }
    }
}
