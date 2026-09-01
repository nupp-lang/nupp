//! Rust ownership behind the Lua-facing Nupp worker adapter.
//!
//! `worker_shim.c` is the only code that reads or writes a Lua stack. It copies
//! primitive arguments into these opaque Rust objects and copies answers back.
//! Channels, messages, dictionaries, attachments, regions, task state, worker
//! threads, payload lifetime, cancellation, and teardown are owned here.

#![deny(unsafe_op_in_unsafe_fn)]
#![deny(clippy::undocumented_unsafe_blocks)]

use crate::{
    CancellationToken, HostRuntime, SharedBytes, SharedBytesBuilder, Worker, WorkerEvent,
    WorkerJob, WorkerLimits,
};
use std::collections::{HashMap, VecDeque};
use std::ffi::{c_char, c_int, c_void};
use std::fmt::Write as _;
use std::mem::ManuallyDrop;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::PathBuf;
use std::ptr;
use std::slice;
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::time::Duration;

const MAX_MESSAGES: usize = 1024;
const MAX_BYTES: usize = 256 * 1024 * 1024;
const MAX_DICTIONARY: usize = 256;
const MAX_ATTACHMENTS: usize = 255;
const ACCOUNT_STEP_BYTES: usize = 1 << 20;

fn ffi_value<T>(fallback: T, body: impl FnOnce() -> T) -> T {
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(value) => value,
        Err(payload) => {
            // A user-supplied panic payload may itself panic from Drop. Leak it
            // on this exceptional path so even that destructor cannot unwind
            // through the Lua/C callback ABI.
            std::mem::forget(payload);
            fallback
        }
    }
}

fn ffi_void(body: impl FnOnce()) {
    if let Err(payload) = catch_unwind(AssertUnwindSafe(body)) {
        std::mem::forget(payload);
    }
}

pub(crate) struct WorkersHost {
    payload: SharedBytes,
    executable: Option<PathBuf>,
}

impl WorkersHost {
    pub(crate) fn new(payload: &[u8], executable: Option<PathBuf>) -> Self {
        Self {
            payload: SharedBytes::new(payload.to_vec()),
            executable,
        }
    }
}

struct QueueState {
    messages: VecDeque<Box<AdapterMessage>>,
    bytes: usize,
    closed: bool,
}

pub(crate) struct AdapterChannel {
    queue: Mutex<QueueState>,
    arrived: Condvar,
    dictionary: Mutex<Vec<Vec<u8>>>,
}

impl AdapterChannel {
    fn new() -> Self {
        Self {
            queue: Mutex::new(QueueState {
                messages: VecDeque::new(),
                bytes: 0,
                closed: false,
            }),
            arrived: Condvar::new(),
            dictionary: Mutex::new(Vec::new()),
        }
    }

    fn try_push(&self, message: Box<AdapterMessage>) -> bool {
        let measured = message.measured_bytes();
        let mut queue = lock(&self.queue);
        if queue.closed
            || queue.messages.len() >= MAX_MESSAGES
            || queue
                .bytes
                .checked_add(measured)
                .is_none_or(|bytes| bytes > MAX_BYTES)
        {
            return false;
        }
        queue.bytes += measured;
        queue.messages.push_back(message);
        self.arrived.notify_one();
        true
    }

    fn pop(&self, timeout_ms: i32) -> Option<Box<AdapterMessage>> {
        let mut queue = lock(&self.queue);
        if timeout_ms < 0 {
            while queue.messages.is_empty() && !queue.closed {
                queue = self
                    .arrived
                    .wait(queue)
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
            }
        } else if timeout_ms > 0 {
            let timeout = Duration::from_millis(timeout_ms as u64);
            let waited = self
                .arrived
                .wait_timeout_while(queue, timeout, |queue| {
                    queue.messages.is_empty() && !queue.closed
                })
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            queue = waited.0;
        }
        let message = queue.messages.pop_front()?;
        queue.bytes = queue.bytes.saturating_sub(message.measured_bytes());
        Some(message)
    }

    fn close(&self) {
        lock(&self.queue).closed = true;
        self.arrived.notify_all();
    }
}

pub(crate) struct Region {
    bytes: SharedBytes,
}

#[derive(Default)]
pub(crate) struct AdapterAccount {
    blocks: HashMap<usize, (usize, usize)>,
    charged: usize,
    debt: usize,
}

enum Attachment {
    Region {
        region: Arc<Region>,
        first: usize,
        length: usize,
    },
    Moved {
        pointer: *mut c_void,
        count: usize,
        layout: usize,
    },
}

// SAFETY: a moved allocation is exclusively owned by the message while it
// crosses a channel. malloc storage is thread-independent and may be freed on
// either lane; region attachments use Arc and are Send through that owner.
unsafe impl Send for Attachment {}

impl Drop for Attachment {
    fn drop(&mut self) {
        if let Self::Moved { pointer, .. } = self
            && !pointer.is_null()
        {
            // SAFETY: a moved attachment is an exclusive malloc owner. The
            // pointer is cleared immediately so no later Drop can free it twice.
            unsafe { free(*pointer) };
            *pointer = ptr::null_mut();
        }
    }
}

#[repr(C)]
pub(crate) struct RawAttachment {
    kind: c_int,
    block: *mut c_void,
    first: usize,
    length: usize,
}

pub(crate) struct AdapterMessage {
    kind: c_int,
    id: i64,
    number: f64,
    first: Vec<u8>,
    second: Vec<u8>,
    value: Vec<u8>,
    attachments: Vec<Option<Attachment>>,
}

impl AdapterMessage {
    fn measured_bytes(&self) -> usize {
        std::mem::size_of::<Self>()
            .saturating_add(self.first.len())
            .saturating_add(self.second.len())
            .saturating_add(self.value.len())
            .saturating_add(
                self.attachments
                    .len()
                    .saturating_mul(std::mem::size_of::<Attachment>()),
            )
    }
}

pub(crate) struct AdapterBuilder {
    builder: Option<SharedBytesBuilder>,
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum AdapterTaskStatus {
    Queued = 1,
    Running = 2,
    CancellationRequested = 3,
    Cancelled = 4,
    Done = 5,
}

struct AdapterTask {
    deadline_ms: Option<f64>,
    status: AdapterTaskStatus,
}

#[derive(Default)]
struct TaskState {
    tasks: HashMap<i64, AdapterTask>,
    current: Option<i64>,
}

pub(crate) struct AdapterTasks {
    state: Mutex<TaskState>,
}

impl AdapterTasks {
    fn new() -> Self {
        Self {
            state: Mutex::new(TaskState::default()),
        }
    }

    fn expired(task: &AdapterTask) -> bool {
        task.deadline_ms
            .is_some_and(|deadline| monotonic_ms() >= deadline)
    }
}

pub(crate) struct AdapterWorker {
    worker: Worker,
    tasks: Arc<AdapterTasks>,
    inbox: Arc<AdapterChannel>,
    outbox: Arc<AdapterChannel>,
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn monotonic_ms() -> f64 {
    nupp_native_platform::monotonic_ns() as f64 / 1.0e6
}

fn borrowed_arc<T>(pointer: *const T) -> Option<ManuallyDrop<Arc<T>>> {
    if pointer.is_null() {
        None
    } else {
        // SAFETY: each C pointer passed here originated in `Arc::into_raw` and
        // C retains that strong owner. `ManuallyDrop` makes this a borrow only.
        Some(ManuallyDrop::new(unsafe { Arc::from_raw(pointer) }))
    }
}

unsafe fn bytes<'a>(data: *const u8, length: usize) -> Option<&'a [u8]> {
    if data.is_null() && length != 0 {
        None
    } else if length == 0 {
        Some(&[])
    } else {
        // SAFETY: the caller proves `data` addresses `length` readable bytes for
        // the returned borrow and keeps them live for that borrow's duration.
        Some(unsafe { slice::from_raw_parts(data, length) })
    }
}

fn write_error(buffer: *mut c_char, capacity: usize, message: &str) {
    if buffer.is_null() || capacity == 0 {
        return;
    }
    let count = message.len().min(capacity - 1);
    // SAFETY: C provides `capacity` writable bytes at non-null `buffer`; source
    // and destination do not overlap and the final byte is reserved for NUL.
    unsafe {
        ptr::copy_nonoverlapping(message.as_ptr().cast(), buffer, count);
        *buffer.add(count) = 0;
    }
}

fn attachments(raw: *const RawAttachment, count: usize) -> Option<Vec<Option<Attachment>>> {
    if count > MAX_ATTACHMENTS || (raw.is_null() && count != 0) {
        return None;
    }
    let raw = if count == 0 {
        &[][..]
    } else {
        // SAFETY: the C shim owns a stack array of at least `count` elements and
        // keeps it live and immutable until this synchronous conversion returns.
        unsafe { slice::from_raw_parts(raw, count) }
    };
    let mut answer = Vec::with_capacity(count);
    for item in raw {
        if item.kind == 0 {
            let region = borrowed_arc(item.block.cast::<Region>())?;
            let zero = item.first.checked_sub(1)?;
            let end = zero.checked_add(item.length)?;
            if end > region.bytes.len() {
                return None;
            }
            answer.push(Some(Attachment::Region {
                region: Arc::clone(&region),
                first: item.first,
                length: item.length,
            }));
        } else if item.kind == 1 && !item.block.is_null() && item.length >= 1 {
            answer.push(Some(Attachment::Moved {
                pointer: item.block,
                count: item.first,
                layout: item.length,
            }));
        } else {
            return None;
        }
    }
    Some(answer)
}

#[unsafe(no_mangle)]
pub(crate) extern "C" fn nupp_rust_worker_channel_new() -> *const AdapterChannel {
    ffi_value(ptr::null(), || {
        Arc::into_raw(Arc::new(AdapterChannel::new()))
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_channel_destroy(channel: *const AdapterChannel) {
    ffi_void(|| {
        if !channel.is_null() {
            // SAFETY: C transfers exactly one strong owner created by
            // `channel_new`; the lightuserdata must not be destroyed twice.
            drop(unsafe { Arc::from_raw(channel) });
        }
    });
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_channel_close(channel: *const AdapterChannel) {
    ffi_void(|| {
        if let Some(channel) = borrowed_arc(channel) {
            channel.close();
        }
    });
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_channel_count(
    channel: *const AdapterChannel,
) -> usize {
    ffi_value(0, || {
        borrowed_arc(channel)
            .map(|channel| lock(&channel.queue).messages.len())
            .unwrap_or(0)
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_channel_closed(
    channel: *const AdapterChannel,
) -> c_int {
    ffi_value(1, || {
        borrowed_arc(channel)
            .is_none_or(|channel| lock(&channel.queue).closed)
            .into()
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_channel_push(
    channel: *const AdapterChannel,
    kind: c_int,
    id: i64,
    number: f64,
    first: *const u8,
    first_length: usize,
    second: *const u8,
    second_length: usize,
    value: *const u8,
    value_length: usize,
    raw_attachments: *const RawAttachment,
    attachment_count: usize,
) -> c_int {
    ffi_value(0, || {
        let Some(channel) = borrowed_arc(channel) else {
            return 0;
        };
        // SAFETY: C keeps each Lua string live and immutable until this call
        // returns; the function copies every slice before returning to C.
        let Some(first) = (unsafe { bytes(first, first_length) }) else {
            return 0;
        };
        // SAFETY: same synchronous Lua-string borrow as `first`.
        let Some(second) = (unsafe { bytes(second, second_length) }) else {
            return 0;
        };
        // SAFETY: same synchronous Lua-string borrow as `first`.
        let Some(value) = (unsafe { bytes(value, value_length) }) else {
            return 0;
        };
        let Some(attachments) = attachments(raw_attachments, attachment_count) else {
            return 0;
        };
        channel
            .try_push(Box::new(AdapterMessage {
                kind,
                id,
                number,
                first: first.to_vec(),
                second: second.to_vec(),
                value: value.to_vec(),
                attachments,
            }))
            .into()
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_channel_pop(
    channel: *const AdapterChannel,
    timeout_ms: i32,
) -> *mut AdapterMessage {
    ffi_value(ptr::null_mut(), || {
        borrowed_arc(channel)
            .and_then(|channel| channel.pop(timeout_ms))
            .map(Box::into_raw)
            .unwrap_or(ptr::null_mut())
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_message_destroy(message: *mut AdapterMessage) {
    ffi_void(|| {
        if !message.is_null() {
            // SAFETY: `channel_pop` transfers one Box owner to C; C calls this
            // once after copying all borrowed message bytes and attachments.
            drop(unsafe { Box::from_raw(message) });
        }
    });
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_message_kind(
    message: *const AdapterMessage,
) -> c_int {
    ffi_value(0, || {
        // SAFETY: C retains the transferred message owner through this getter.
        unsafe { message.as_ref() }.map_or(0, |message| message.kind)
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_message_id(message: *const AdapterMessage) -> i64 {
    ffi_value(0, || {
        // SAFETY: C retains the transferred message owner through this getter.
        unsafe { message.as_ref() }.map_or(0, |message| message.id)
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_message_number(
    message: *const AdapterMessage,
) -> f64 {
    ffi_value(0.0, || {
        // SAFETY: C retains the transferred message owner through this getter.
        unsafe { message.as_ref() }.map_or(0.0, |message| message.number)
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_message_bytes(
    message: *const AdapterMessage,
    which: c_int,
    length: *mut usize,
) -> *const u8 {
    ffi_value(ptr::null(), || {
        // SAFETY: C retains the message until after it copies the returned
        // slice, so the selected Vec cannot move or be freed during this call.
        let Some(message) = (unsafe { message.as_ref() }) else {
            return ptr::null();
        };
        let value = match which {
            0 => &message.first,
            1 => &message.second,
            _ => &message.value,
        };
        if !length.is_null() {
            // SAFETY: non-null `length` points to C stack storage for this call.
            unsafe { *length = value.len() };
        }
        value.as_ptr()
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_message_attachment_count(
    message: *const AdapterMessage,
) -> usize {
    ffi_value(0, || {
        // SAFETY: C retains the transferred message owner through this getter.
        unsafe { message.as_ref() }.map_or(0, |message| message.attachments.len())
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_message_take_attachment(
    message: *mut AdapterMessage,
    index: usize,
    out: *mut RawAttachment,
) -> c_int {
    ffi_value(0, || {
        // SAFETY: C retains exclusive ownership of the message and serializes
        // attachment extraction before destroying it.
        let Some(message) = (unsafe { message.as_mut() }) else {
            return 0;
        };
        let Some(slot) = message.attachments.get_mut(index) else {
            return 0;
        };
        let Some(attachment) = slot.take() else {
            return 0;
        };
        let attachment = ManuallyDrop::new(attachment);
        let raw = match &*attachment {
            Attachment::Region {
                region,
                first,
                length,
            } => RawAttachment {
                kind: 0,
                // SAFETY: `attachment` is ManuallyDrop and uniquely consumed;
                // reading its Arc transfers that strong owner to the C handle.
                block: Arc::into_raw(unsafe { ptr::read(region) })
                    .cast_mut()
                    .cast(),
                first: *first,
                length: *length,
            },
            Attachment::Moved {
                pointer,
                count,
                layout,
            } => RawAttachment {
                kind: 1,
                block: *pointer,
                first: *count,
                length: *layout,
            },
        };
        if out.is_null() {
            release_raw_attachment(raw);
            return 0;
        }
        // SAFETY: non-null `out` is writable C stack storage for one RawAttachment.
        unsafe { out.write(raw) };
        1
    })
}

fn release_raw_attachment(raw: RawAttachment) {
    if raw.kind == 0 {
        if !raw.block.is_null() {
            // SAFETY: a region raw attachment carries exactly one Arc strong
            // owner transferred from `message_take_attachment`.
            drop(unsafe { Arc::from_raw(raw.block.cast::<Region>()) });
        }
    } else if !raw.block.is_null() {
        // SAFETY: a moved raw attachment exclusively owns this malloc pointer.
        unsafe { free(raw.block) };
    }
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_channel_dict_register(
    channel: *const AdapterChannel,
    address: *const u8,
    length: usize,
) -> usize {
    ffi_value(0, || {
        let Some(channel) = borrowed_arc(channel) else {
            return 0;
        };
        // SAFETY: C borrows a Lua string for this synchronous call; Rust copies
        // it before returning and retains no pointer into the Lua heap.
        let Some(address) = (unsafe { bytes(address, length) }) else {
            return 0;
        };
        if address.is_empty() {
            return 0;
        }
        let mut dictionary = lock(&channel.dictionary);
        if let Some(index) = dictionary.iter().position(|known| known == address) {
            return index + 1;
        }
        if dictionary.len() >= MAX_DICTIONARY {
            return 0;
        }
        dictionary.push(address.to_vec());
        dictionary.len()
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_channel_dict_count(
    channel: *const AdapterChannel,
) -> usize {
    ffi_value(0, || {
        borrowed_arc(channel)
            .map(|channel| lock(&channel.dictionary).len())
            .unwrap_or(0)
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_channel_dict_address(
    channel: *const AdapterChannel,
    index: usize,
    length: *mut usize,
) -> *const u8 {
    ffi_value(ptr::null(), || {
        let Some(channel) = borrowed_arc(channel) else {
            return ptr::null();
        };
        let dictionary = lock(&channel.dictionary);
        let Some(address) = index.checked_sub(1).and_then(|index| dictionary.get(index)) else {
            return ptr::null();
        };
        if !length.is_null() {
            // SAFETY: non-null `length` points to writable C stack storage.
            unsafe { *length = address.len() };
        }
        // The Vec's allocation is stable: dictionary entries are append-only
        // and the C shim copies these bytes before any channel call can destroy
        // the final Arc owner on this Lua state's thread.
        address.as_ptr()
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_region_new(
    data: *const u8,
    length: usize,
) -> *const Region {
    ffi_value(ptr::null(), || {
        // SAFETY: C keeps the Lua string live for this call; the bytes are copied
        // into Rust ownership before the function returns.
        let Some(data) = (unsafe { bytes(data, length) }) else {
            return ptr::null();
        };
        Arc::into_raw(Arc::new(Region {
            bytes: SharedBytes::new(data.to_vec()),
        }))
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_region_read_file(
    path: *const u8,
    length: usize,
    error: *mut c_char,
    error_capacity: usize,
) -> *const Region {
    ffi_value(ptr::null(), || {
        // SAFETY: C keeps the Lua path string live until this call returns; the
        // platform path conversion takes owned/copied storage as necessary.
        let Some(path) = (unsafe { bytes(path, length) }) else {
            write_error(error, error_capacity, "a file path is required");
            return ptr::null();
        };
        let path = path_from_bytes(path);
        match std::fs::read(&path) {
            Ok(data) => Arc::into_raw(Arc::new(Region {
                bytes: SharedBytes::new(data),
            })),
            Err(problem) => {
                let mut message = String::new();
                let _ = write!(message, "cannot read {}: {problem}", path.display());
                write_error(error, error_capacity, &message);
                ptr::null()
            }
        }
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_region_retain(region: *const Region) {
    ffi_void(|| {
        if !region.is_null() {
            // SAFETY: the pointer names a live Arc allocation held by the source
            // Lua region handle; this creates the destination handle's owner.
            unsafe { Arc::increment_strong_count(region) };
        }
    });
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_region_release(region: *const Region) {
    ffi_void(|| {
        if !region.is_null() {
            // SAFETY: each C region handle transfers exactly one Arc strong
            // owner here and clears its pointer before it can be released again.
            drop(unsafe { Arc::from_raw(region) });
        }
    });
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_region_data(region: *const Region) -> *const u8 {
    ffi_value(ptr::null(), || {
        // SAFETY: the Lua region handle retains a strong Arc owner while C
        // obtains this immutable pointer; SharedBytes never reallocates it.
        unsafe { region.as_ref() }
            .map(|region| region.bytes.as_slice().as_ptr())
            .unwrap_or(ptr::null())
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_region_length(region: *const Region) -> usize {
    ffi_value(0, || {
        // SAFETY: the Lua region handle retains a strong Arc owner through call.
        unsafe { region.as_ref() }.map_or(0, |region| region.bytes.len())
    })
}

#[unsafe(no_mangle)]
pub(crate) extern "C" fn nupp_rust_region_account_new() -> *mut AdapterAccount {
    ffi_value(ptr::null_mut(), || {
        Box::into_raw(Box::new(AdapterAccount::default()))
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_region_account_destroy(account: *mut AdapterAccount) {
    ffi_void(|| {
        if !account.is_null() {
            // SAFETY: registry userdata owns this Box and calls its finalizer once.
            drop(unsafe { Box::from_raw(account) });
        }
    });
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_region_account_charge(
    account: *mut AdapterAccount,
    region: *const Region,
) -> usize {
    ffi_value(0, || {
        // SAFETY: the state registry exclusively owns and serializes this
        // account on one Lua thread for the duration of the callback.
        let Some(account) = (unsafe { account.as_mut() }) else {
            return 0;
        };
        // SAFETY: the region handle retains a strong Arc owner during charging.
        let Some(region) = (unsafe { region.as_ref() }) else {
            return 0;
        };
        let key = region as *const Region as usize;
        if let Some((count, _)) = account.blocks.get_mut(&key) {
            *count = count.saturating_add(1);
            return 0;
        }
        let length = region.bytes.len();
        account.blocks.insert(key, (1, length));
        account.charged = account.charged.saturating_add(length);
        account.debt = account.debt.saturating_add(length);
        if account.debt < ACCOUNT_STEP_BYTES {
            return 0;
        }
        let step = account.debt >> 10;
        account.debt = 0;
        step
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_region_account_discharge(
    account: *mut AdapterAccount,
    region: *const Region,
) {
    ffi_void(|| {
        // SAFETY: the registry owns this account and the state serializes it.
        let Some(account) = (unsafe { account.as_mut() }) else {
            return;
        };
        // SAFETY: the region handle is still live while its charge is removed.
        let Some(region) = (unsafe { region.as_ref() }) else {
            return;
        };
        let key = region as *const Region as usize;
        let Some((count, length)) = account.blocks.get_mut(&key) else {
            return;
        };
        if *count > 1 {
            *count -= 1;
            return;
        }
        let length = *length;
        account.blocks.remove(&key);
        account.charged = account.charged.saturating_sub(length);
        account.debt = account.debt.saturating_sub(length);
    });
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_region_accounted(
    account: *const AdapterAccount,
) -> usize {
    ffi_value(0, || {
        // SAFETY: registry userdata keeps the account live through this callback.
        unsafe { account.as_ref() }.map_or(0, |account| account.charged)
    })
}

#[unsafe(no_mangle)]
pub(crate) extern "C" fn nupp_rust_region_builder_new() -> *mut AdapterBuilder {
    ffi_value(ptr::null_mut(), || {
        Box::into_raw(Box::new(AdapterBuilder {
            builder: Some(SharedBytesBuilder::default()),
        }))
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_region_builder_destroy(builder: *mut AdapterBuilder) {
    ffi_void(|| {
        if !builder.is_null() {
            // SAFETY: builder userdata owns this Box and finalizes it once.
            drop(unsafe { Box::from_raw(builder) });
        }
    });
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_region_builder_append(
    builder: *mut AdapterBuilder,
    data: *const u8,
    length: usize,
) -> c_int {
    ffi_value(0, || {
        // SAFETY: Lua userdata exclusively owns and serializes this builder.
        let Some(builder) = (unsafe { builder.as_mut() }) else {
            return 0;
        };
        // SAFETY: C keeps the Lua string live through this synchronous append.
        let Some(data) = (unsafe { bytes(data, length) }) else {
            return 0;
        };
        builder
            .builder
            .as_mut()
            .is_some_and(|builder| builder.append(data).is_ok())
            .into()
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_region_builder_reserve(
    builder: *mut AdapterBuilder,
    count: usize,
) -> *mut u8 {
    ffi_value(ptr::null_mut(), || {
        // SAFETY: Lua userdata exclusively owns and serializes this builder.
        let Some(builder) = (unsafe { builder.as_mut() }) else {
            return ptr::null_mut();
        };
        // The returned pointer is borrowed until one matching commit. The
        // builder rejects append/reserve/freeze while that reservation is open.
        builder
            .builder
            .as_mut()
            .and_then(|builder| builder.reserve(count).ok())
            .map(|bytes| bytes.as_mut_ptr())
            .unwrap_or(ptr::null_mut())
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_region_builder_commit(
    builder: *mut AdapterBuilder,
    written: usize,
) -> c_int {
    ffi_value(0, || {
        // SAFETY: Lua userdata exclusively owns and serializes this builder.
        unsafe { builder.as_mut() }
            .and_then(|builder| builder.builder.as_mut())
            .is_some_and(|builder| builder.commit(written).is_ok())
            .into()
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_region_builder_open(
    builder: *const AdapterBuilder,
) -> c_int {
    ffi_value(0, || {
        // SAFETY: Lua userdata keeps the builder live through this callback.
        unsafe { builder.as_ref() }
            .and_then(|builder| builder.builder.as_ref())
            .is_some_and(SharedBytesBuilder::reservation_open)
            .into()
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_region_builder_freeze(
    builder: *mut AdapterBuilder,
) -> *const Region {
    ffi_value(ptr::null(), || {
        // SAFETY: Lua userdata exclusively owns and serializes this builder.
        let Some(builder) = (unsafe { builder.as_mut() }) else {
            return ptr::null();
        };
        if builder
            .builder
            .as_ref()
            .is_some_and(SharedBytesBuilder::reservation_open)
        {
            return ptr::null();
        }
        let Some(owned) = builder.builder.take() else {
            return ptr::null();
        };
        match owned.freeze() {
            Ok(bytes) => Arc::into_raw(Arc::new(Region { bytes })),
            Err(_) => ptr::null(),
        }
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_spawn(
    host: *const WorkersHost,
    inbox: *const AdapterChannel,
    outbox: *const AdapterChannel,
    error: *mut c_char,
    error_capacity: usize,
) -> *mut AdapterWorker {
    ffi_value(ptr::null_mut(), || {
        // SAFETY: the parent HostRuntime owns WorkersHost for as long as its Lua
        // state can invoke workerSpawn, and parent-state access is thread-affine.
        let Some(host) = (unsafe { host.as_ref() }) else {
            write_error(
                error,
                error_capacity,
                "workers require a stamped Nupp payload",
            );
            return ptr::null_mut();
        };
        let Some(inbox) = borrowed_arc(inbox) else {
            write_error(error, error_capacity, "worker channels are missing");
            return ptr::null_mut();
        };
        let Some(outbox) = borrowed_arc(outbox) else {
            write_error(error, error_capacity, "worker channels are missing");
            return ptr::null_mut();
        };
        let inbox = Arc::clone(&inbox);
        let outbox = Arc::clone(&outbox);
        let tasks = Arc::new(AdapterTasks::new());
        let payload = host.payload.clone();
        let executable = host.executable.clone();
        let thread_inbox = Arc::clone(&inbox);
        let thread_outbox = Arc::clone(&outbox);
        let thread_tasks = Arc::clone(&tasks);
        let worker = Worker::spawn(
            "nupp.worker.scheduler",
            WorkerLimits {
                messages: 1,
                bytes: payload.len().saturating_add(1).max(1),
            },
            move || {
                let mut runtime = HostRuntime::owned(true, executable.as_deref())
                    .map_err(|problem| problem.to_string())?;
                runtime
                    .enable_workers(payload.as_slice())
                    .map_err(|problem| problem.to_string())?;
                runtime
                    .set_worker_context(
                        Arc::as_ptr(&thread_inbox).cast(),
                        Arc::as_ptr(&thread_outbox).cast(),
                        Arc::as_ptr(&thread_tasks).cast(),
                    )
                    .map_err(|problem| problem.to_string())?;
                Ok(move |job: WorkerJob, _cancel: CancellationToken| {
                    let answer = runtime
                        .run_buffer(job.bytes.as_slice(), "=nupp-worker", &[])
                        .map(|()| SharedBytes::default())
                        .map_err(|problem| problem.to_string());
                    thread_inbox.close();
                    thread_outbox.close();
                    answer
                })
            },
        );
        let mut worker = match worker {
            Ok(worker) => worker,
            Err(problem) => {
                write_error(error, error_capacity, &problem.to_string());
                return ptr::null_mut();
            }
        };
        if let Err(problem) = worker.submit(1, host.payload.clone(), None) {
            let _ = worker.shutdown();
            write_error(error, error_capacity, &problem.to_string());
            return ptr::null_mut();
        }
        Box::into_raw(Box::new(AdapterWorker {
            worker,
            tasks,
            inbox,
            outbox,
        }))
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_join(
    worker: *mut AdapterWorker,
    error: *mut c_char,
    error_capacity: usize,
) -> c_int {
    ffi_value(1, || {
        if worker.is_null() {
            write_error(error, error_capacity, "worker handle is missing");
            return 1;
        }
        // SAFETY: workerJoin consumes the one Box owner returned by workerSpawn;
        // the Lua scheduler removes the handle after this call and never joins twice.
        let mut worker = unsafe { Box::from_raw(worker) };
        let event = worker.worker.poll(None);
        let (status, problem) = match event {
            Ok(Some(WorkerEvent::Completed { .. })) => (0, None),
            Ok(Some(WorkerEvent::Failed { error, .. })) => (1, Some(error)),
            Ok(Some(WorkerEvent::Cancelled { .. })) => {
                (1, Some("worker scheduler was cancelled".to_owned()))
            }
            Ok(None) => (
                1,
                Some("worker scheduler ended without a result".to_owned()),
            ),
            Err(problem) => (1, Some(problem.to_string())),
        };
        worker.inbox.close();
        worker.outbox.close();
        let shutdown = worker.worker.shutdown();
        if let Some(problem) = problem.or_else(|| shutdown.err().map(|error| error.to_string())) {
            write_error(error, error_capacity, &problem);
        }
        status
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_task_create(
    worker: *const AdapterWorker,
    id: i64,
    has_deadline: c_int,
    deadline_ms: f64,
) -> c_int {
    ffi_value(0, || {
        // SAFETY: the Lua worker handle retains the AdapterWorker Box until join.
        let Some(worker) = (unsafe { worker.as_ref() }) else {
            return 0;
        };
        if id < 1 {
            return 0;
        }
        let mut state = lock(&worker.tasks.state);
        if state.tasks.contains_key(&id) {
            return 0;
        }
        state.tasks.insert(
            id,
            AdapterTask {
                deadline_ms: (has_deadline != 0 && deadline_ms.is_finite()).then_some(deadline_ms),
                status: AdapterTaskStatus::Queued,
            },
        );
        1
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_task_cancel(
    worker: *const AdapterWorker,
    id: i64,
) -> c_int {
    ffi_value(0, || {
        // SAFETY: the Lua worker handle retains the AdapterWorker Box until join.
        let Some(worker) = (unsafe { worker.as_ref() }) else {
            return 0;
        };
        let mut state = lock(&worker.tasks.state);
        let Some(task) = state.tasks.get_mut(&id) else {
            return 0;
        };
        match task.status {
            AdapterTaskStatus::Queued => {
                task.status = AdapterTaskStatus::Cancelled;
                1
            }
            AdapterTaskStatus::Running => {
                task.status = AdapterTaskStatus::CancellationRequested;
                2
            }
            _ => 0,
        }
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_task_start(
    tasks: *const AdapterTasks,
    id: i64,
    deadline: *mut c_int,
) -> c_int {
    ffi_value(0, || {
        // SAFETY: the isolated worker closure holds this Arc for the entire lifetime
        // of the worker Lua state and serializes callbacks on that lane.
        let Some(tasks) = (unsafe { tasks.as_ref() }) else {
            return 0;
        };
        let mut state = lock(&tasks.state);
        let Some(task) = state.tasks.get_mut(&id) else {
            return 0;
        };
        if task.status != AdapterTaskStatus::Queued {
            return 0;
        }
        if AdapterTasks::expired(task) {
            task.status = AdapterTaskStatus::Cancelled;
            if !deadline.is_null() {
                // SAFETY: C provides a writable stack `int` for this synchronous call.
                unsafe { *deadline = 1 };
            }
            return 0;
        }
        task.status = AdapterTaskStatus::Running;
        state.current = Some(id);
        1
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_task_checkpoint(
    tasks: *const AdapterTasks,
    deadline: *mut c_int,
) -> c_int {
    ffi_value(0, || {
        // SAFETY: the isolated worker closure retains this tasks Arc and invokes the
        // callback only on its Lua state's owner thread.
        let Some(tasks) = (unsafe { tasks.as_ref() }) else {
            return 0;
        };
        let mut state = lock(&tasks.state);
        let Some(id) = state.current else {
            return 0;
        };
        let Some(task) = state.tasks.get_mut(&id) else {
            return 0;
        };
        let expired = AdapterTasks::expired(task);
        let cancelled = expired
            || matches!(
                task.status,
                AdapterTaskStatus::CancellationRequested | AdapterTaskStatus::Cancelled
            );
        if cancelled && task.status == AdapterTaskStatus::Running {
            task.status = AdapterTaskStatus::CancellationRequested;
        }
        if expired && !deadline.is_null() {
            // SAFETY: C provides a writable stack `int` for this synchronous call.
            unsafe { *deadline = 1 };
        }
        cancelled.into()
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_task_finish(
    tasks: *const AdapterTasks,
    id: i64,
    deadline: *mut c_int,
) -> c_int {
    ffi_value(0, || {
        // SAFETY: the isolated worker closure retains this tasks Arc and serializes
        // mutation on its Lua state's owner thread.
        let Some(tasks) = (unsafe { tasks.as_ref() }) else {
            return 0;
        };
        let mut state = lock(&tasks.state);
        let Some(task) = state.tasks.get_mut(&id) else {
            return 0;
        };
        let expired = AdapterTasks::expired(task);
        let cancelled = expired
            || matches!(
                task.status,
                AdapterTaskStatus::CancellationRequested | AdapterTaskStatus::Cancelled
            );
        task.status = AdapterTaskStatus::Done;
        if state.current == Some(id) {
            state.current = None;
        }
        if expired && !deadline.is_null() {
            // SAFETY: C provides a writable stack `int` for this synchronous call.
            unsafe { *deadline = 1 };
        }
        cancelled.into()
    })
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_task_release(
    worker: *const AdapterWorker,
    id: i64,
) {
    ffi_void(|| {
        // SAFETY: the Lua worker handle retains this Box until join and calls
        // task operations serially from the parent state.
        if let Some(worker) = unsafe { worker.as_ref() } {
            lock(&worker.tasks.state).tasks.remove(&id);
        }
    });
}

#[unsafe(no_mangle)]
pub(crate) unsafe extern "C" fn nupp_rust_worker_task_status(
    worker: *const AdapterWorker,
    id: i64,
) -> c_int {
    ffi_value(0, || {
        // SAFETY: the Lua worker handle retains this Box until join.
        unsafe { worker.as_ref() }
            .and_then(|worker| {
                lock(&worker.tasks.state)
                    .tasks
                    .get(&id)
                    .map(|task| task.status as c_int)
            })
            .unwrap_or(0)
    })
}

#[unsafe(no_mangle)]
pub(crate) extern "C" fn nupp_rust_worker_parallelism() -> usize {
    ffi_value(1, || {
        std::thread::available_parallelism().map_or(1, usize::from)
    })
}

#[cfg(unix)]
fn path_from_bytes(bytes: &[u8]) -> PathBuf {
    use std::os::unix::ffi::OsStrExt;
    PathBuf::from(std::ffi::OsStr::from_bytes(bytes))
}

#[cfg(not(unix))]
fn path_from_bytes(bytes: &[u8]) -> PathBuf {
    PathBuf::from(String::from_utf8_lossy(bytes).into_owned())
}

unsafe extern "C" {
    fn free(pointer: *mut c_void);
}

#[cfg(test)]
#[allow(clippy::undocumented_unsafe_blocks)]
mod tests {
    use super::*;

    #[test]
    fn rust_panic_firewall_returns_conservative_values() {
        assert_eq!(ffi_value(17, || panic!("value boundary fixture")), 17);
        ffi_void(|| panic!("void boundary fixture"));
    }

    #[test]
    fn channel_is_bounded_fifo_and_drains_after_close() {
        let channel = AdapterChannel::new();
        for id in 0..MAX_MESSAGES {
            assert!(channel.try_push(Box::new(AdapterMessage {
                kind: 0,
                id: id as i64,
                number: 0.0,
                first: vec![],
                second: vec![],
                value: vec![],
                attachments: vec![],
            })));
        }
        assert!(!channel.try_push(Box::new(AdapterMessage {
            kind: 0,
            id: -1,
            number: 0.0,
            first: vec![],
            second: vec![],
            value: vec![],
            attachments: vec![],
        })));
        channel.close();
        for id in 0..MAX_MESSAGES {
            assert_eq!(channel.pop(0).unwrap().id, id as i64);
        }
        assert!(channel.pop(0).is_none());
    }

    #[test]
    fn dictionary_is_ordered_deduplicated_and_bounded() {
        let channel = Arc::new(AdapterChannel::new());
        let raw = Arc::as_ptr(&channel);
        for index in 0..MAX_DICTIONARY {
            let address = format!("module.Record{index}");
            assert_eq!(
                unsafe {
                    nupp_rust_worker_channel_dict_register(raw, address.as_ptr(), address.len())
                },
                index + 1
            );
        }
        assert_eq!(
            unsafe { nupp_rust_worker_channel_dict_register(raw, b"extra".as_ptr(), 5) },
            0
        );
        assert_eq!(
            unsafe { nupp_rust_worker_channel_dict_register(raw, b"module.Record0".as_ptr(), 14) },
            1
        );
    }

    #[test]
    fn region_accounting_counts_each_allocation_once() {
        let account = nupp_rust_region_account_new();
        let bytes = vec![0; ACCOUNT_STEP_BYTES + 17];
        let region = unsafe { nupp_rust_region_new(bytes.as_ptr(), bytes.len()) };
        assert!(!account.is_null() && !region.is_null());
        assert!(unsafe { nupp_rust_region_account_charge(account, region) } >= 1024);
        assert_eq!(
            unsafe { nupp_rust_region_account_charge(account, region) },
            0
        );
        assert_eq!(
            unsafe { nupp_rust_region_accounted(account) },
            ACCOUNT_STEP_BYTES + 17
        );
        unsafe { nupp_rust_region_account_discharge(account, region) };
        assert_eq!(
            unsafe { nupp_rust_region_accounted(account) },
            ACCOUNT_STEP_BYTES + 17
        );
        unsafe { nupp_rust_region_account_discharge(account, region) };
        assert_eq!(unsafe { nupp_rust_region_accounted(account) }, 0);
        unsafe {
            nupp_rust_region_release(region);
            nupp_rust_region_account_destroy(account);
        }
    }

    #[test]
    fn task_cancel_start_finish_races_have_one_owner() {
        let tasks = AdapterTasks::new();
        let worker = AdapterWorker {
            worker: Worker::spawn("adapter.test", WorkerLimits::default(), || {
                Ok(|job: WorkerJob, _cancel: CancellationToken| Ok(job.bytes))
            })
            .unwrap(),
            tasks: Arc::new(tasks),
            inbox: Arc::new(AdapterChannel::new()),
            outbox: Arc::new(AdapterChannel::new()),
        };
        assert_eq!(
            unsafe { nupp_rust_worker_task_create(&worker, 1, 0, 0.0) },
            1
        );
        assert_eq!(unsafe { nupp_rust_worker_task_cancel(&worker, 1) }, 1);
        let mut deadline = 0;
        assert_eq!(
            unsafe { nupp_rust_worker_task_start(&*worker.tasks, 1, &mut deadline) },
            0
        );
    }
}
