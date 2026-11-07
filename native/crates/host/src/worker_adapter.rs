//! Rust ownership behind the Lua-facing Nupp worker adapter.
//!
//! `worker_shim.c` is the only code that reads or writes a Lua stack. It copies
//! primitive arguments into these opaque Rust objects and copies answers back.
//! Channels, messages, dictionaries, attachments, regions, task state, worker
//! threads, payload lifetime, cancellation, and teardown are owned here.

#![deny(unsafe_op_in_unsafe_fn)]
#![deny(clippy::undocumented_unsafe_blocks)]

use crate::channels::{BoundedQueue, Endpoint, Receive, SendError};
use crate::workers::DEFAULT_QUEUE_BYTES;
use crate::{
    HostRuntime, SharedBytes, SharedBytesBuilder, Worker, WorkerEvent, WorkerJob, WorkerLimits,
};
use std::collections::{HashMap, HashSet};
use std::ffi::{c_char, c_int, c_void};
use std::fmt::Write as _;
use std::mem::ManuallyDrop;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::PathBuf;
use std::ptr;
use std::slice;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};
use std::time::Duration;

const MAX_MESSAGES: usize = 1024;
const MAX_BYTES: usize = 256 * 1024 * 1024;
const MAX_DICTIONARY: usize = 256;
const MAX_ATTACHMENTS: usize = 255;
const ACCOUNT_STEP_BYTES: usize = 1 << 20;

/// Frees a caught panic's payload without letting its destructor unwind.
///
/// A user-supplied payload may itself panic from Drop, so it is dropped under a
/// second catch, and only the payload of that second panic, whose destructor
/// could panic again, is leaked. Nothing unwinds through the Lua/C callback
/// ABI, and an ordinary message is freed, which LeakSanitizer reported when
/// every payload was leaked.
fn discard_payload(payload: Box<dyn std::any::Any + Send>) {
    if let Err(nested) = catch_unwind(AssertUnwindSafe(move || drop(payload))) {
        std::mem::forget(nested);
    }
}

fn ffi_value<T>(fallback: T, body: impl FnOnce() -> T) -> T {
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(value) => value,
        Err(payload) => {
            discard_payload(payload);
            fallback
        }
    }
}

fn ffi_void(body: impl FnOnce()) {
    if let Err(payload) = catch_unwind(AssertUnwindSafe(body)) {
        discard_payload(payload);
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

pub(crate) struct AdapterChannel {
    queue: BoundedQueue<Box<AdapterMessage>>,
    waits_for_room: AtomicBool,
    dictionary: Mutex<Vec<Vec<u8>>>,
}

impl AdapterChannel {
    fn new() -> Self {
        Self {
            queue: BoundedQueue::new(MAX_MESSAGES, MAX_BYTES, |message| message.measured_bytes()),
            waits_for_room: AtomicBool::new(false),
            dictionary: Mutex::new(Vec::new()),
        }
    }

    fn try_push(&self, message: Box<AdapterMessage>) -> bool {
        if self.waits_for_room.load(Ordering::Relaxed) {
            self.queue.push_wait(message).is_ok()
        } else {
            self.queue.try_push(message).is_ok()
        }
    }

    fn pop(&self, timeout_ms: i32) -> Option<Box<AdapterMessage>> {
        let timeout = (timeout_ms >= 0).then(|| Duration::from_millis(timeout_ms as u64));
        self.queue.pop(timeout)
    }

    fn close(&self) {
        self.queue.close();
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
    Endpoint(Box<MessageEndpoint>),
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
    fn payload_bytes(&self) -> usize {
        self.attachments
            .iter()
            .flatten()
            .fold(self.first.len(), |bytes, attachment| {
                bytes.saturating_add(match attachment {
                    Attachment::Region { region, .. } => region.bytes.len(),
                    Attachment::Moved { count, layout, .. } => {
                        let width = match layout {
                            1 | 2 => 1,
                            3 | 4 => 2,
                            5 | 6 | 9 => 4,
                            7 | 8 | 10 => 8,
                            _ => usize::MAX,
                        };
                        count.saturating_mul(width).max(1)
                    }
                    Attachment::Endpoint(_) => usize::MAX,
                })
            })
    }

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

/// Converts the shim's attachment array. Moved blocks belong to this call
/// from here on: a rejected array frees every one of them, including those
/// after the entry that was rejected, so the shim never has to guess which
/// blocks a failed push still owns.
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
    let answer = convert_attachments(raw);
    if answer.is_none() {
        for item in raw
            .iter()
            .filter(|item| item.kind == 1 && !item.block.is_null())
        {
            // SAFETY: a moved block is an exclusive malloc owner handed to this
            // call; nothing else frees it once the array was passed to Rust.
            unsafe { free(item.block) };
        }
    }
    answer
}

/// Validate before taking moved storage. Endpoint generations are claimed first,
/// so a refused capability cannot leave a partially built malloc-owner list.
fn convert_attachments(raw: &[RawAttachment]) -> Option<Vec<Option<Attachment>>> {
    if !raw.iter().all(valid_attachment) {
        return None;
    }
    let mut identities = HashSet::new();
    for item in raw.iter().filter(|item| item.kind == 2) {
        if !identities.insert(item.block) {
            return None;
        }
    }
    let mut endpoints = HashMap::new();
    for (index, item) in raw.iter().enumerate().filter(|(_, item)| item.kind == 2) {
        let source = borrowed_endpoint(item.block.cast::<MessageEndpoint>())?;
        endpoints.insert(index, Box::new(source.transfer()?));
    }
    let mut converted = Vec::with_capacity(raw.len());
    for (index, item) in raw.iter().enumerate() {
        converted.push(Some(match item.kind {
            0 => {
                let region = borrowed_arc(item.block.cast::<Region>())?;
                Attachment::Region {
                    region: Arc::clone(&region),
                    first: item.first,
                    length: item.length,
                }
            }
            2 => Attachment::Endpoint(endpoints.remove(&index)?),
            _ => Attachment::Moved {
                pointer: item.block,
                count: item.first,
                layout: item.length,
            },
        }));
    }
    Some(converted)
}

fn valid_attachment(item: &RawAttachment) -> bool {
    match item.kind {
        0 => borrowed_arc(item.block.cast::<Region>()).is_some_and(|region| {
            item.first
                .checked_sub(1)
                .and_then(|zero| zero.checked_add(item.length))
                .is_some_and(|end| end <= region.bytes.len())
        }),
        1 => !item.block.is_null() && item.length >= 1,
        2 => borrowed_endpoint(item.block.cast::<MessageEndpoint>()).is_some_and(|endpoint| {
            endpoint.is_live()
                && item.first == usize::from(endpoint.is_sender())
                && item.length == 0
        }),
        _ => false,
    }
}

pub(crate) extern "C" fn nupp_rust_worker_channel_new() -> *const AdapterChannel {
    ffi_value(ptr::null(), || {
        Arc::into_raw(Arc::new(AdapterChannel::new()))
    })
}

pub(crate) unsafe extern "C" fn nupp_rust_worker_channel_destroy(channel: *const AdapterChannel) {
    ffi_void(|| {
        if !channel.is_null() {
            // SAFETY: C transfers exactly one strong owner created by
            // `channel_new`; the lightuserdata must not be destroyed twice.
            drop(unsafe { Arc::from_raw(channel) });
        }
    });
}

pub(crate) unsafe extern "C" fn nupp_rust_worker_channel_close(channel: *const AdapterChannel) {
    ffi_void(|| {
        if let Some(channel) = borrowed_arc(channel) {
            channel.close();
        }
    });
}

pub(crate) unsafe extern "C" fn nupp_rust_worker_channel_count(
    channel: *const AdapterChannel,
) -> usize {
    ffi_value(0, || {
        borrowed_arc(channel)
            .map(|channel| channel.queue.len())
            .unwrap_or(0)
    })
}

pub(crate) unsafe extern "C" fn nupp_rust_worker_channel_closed(
    channel: *const AdapterChannel,
) -> c_int {
    ffi_value(1, || {
        borrowed_arc(channel)
            .is_none_or(|channel| channel.queue.is_closed())
            .into()
    })
}

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

pub(crate) unsafe extern "C" fn nupp_rust_worker_message_destroy(message: *mut AdapterMessage) {
    ffi_void(|| {
        if !message.is_null() {
            // SAFETY: `channel_pop` transfers one Box owner to C; C calls this
            // once after copying all borrowed message bytes and attachments.
            drop(unsafe { Box::from_raw(message) });
        }
    });
}

pub(crate) unsafe extern "C" fn nupp_rust_worker_message_kind(
    message: *const AdapterMessage,
) -> c_int {
    ffi_value(0, || {
        // SAFETY: C retains the transferred message owner through this getter.
        unsafe { message.as_ref() }.map_or(0, |message| message.kind)
    })
}

pub(crate) unsafe extern "C" fn nupp_rust_worker_message_id(message: *const AdapterMessage) -> i64 {
    ffi_value(0, || {
        // SAFETY: C retains the transferred message owner through this getter.
        unsafe { message.as_ref() }.map_or(0, |message| message.id)
    })
}

pub(crate) unsafe extern "C" fn nupp_rust_worker_message_number(
    message: *const AdapterMessage,
) -> f64 {
    ffi_value(0.0, || {
        // SAFETY: C retains the transferred message owner through this getter.
        unsafe { message.as_ref() }.map_or(0.0, |message| message.number)
    })
}

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

pub(crate) unsafe extern "C" fn nupp_rust_worker_message_attachment_count(
    message: *const AdapterMessage,
) -> usize {
    ffi_value(0, || {
        // SAFETY: C retains the transferred message owner through this getter.
        unsafe { message.as_ref() }.map_or(0, |message| message.attachments.len())
    })
}

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
            Attachment::Endpoint(endpoint) => RawAttachment {
                kind: 2,
                first: usize::from(endpoint.is_sender()),
                length: 0,
                // SAFETY: ManuallyDrop transfers the unique endpoint to its registry owner.
                block: register_endpoint(*unsafe { ptr::read(endpoint) }).cast(),
            },
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
    if raw.kind == 2 {
        if !raw.block.is_null() {
            discard_endpoint(raw.block.cast::<MessageEndpoint>());
        }
    } else if raw.kind == 0 {
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

pub(crate) unsafe extern "C" fn nupp_rust_worker_channel_dict_count(
    channel: *const AdapterChannel,
) -> usize {
    ffi_value(0, || {
        borrowed_arc(channel)
            .map(|channel| lock(&channel.dictionary).len())
            .unwrap_or(0)
    })
}

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

pub(crate) unsafe extern "C" fn nupp_rust_region_release(region: *const Region) {
    ffi_void(|| {
        if !region.is_null() {
            // SAFETY: each C region handle transfers exactly one Arc strong
            // owner here and clears its pointer before it can be released again.
            drop(unsafe { Arc::from_raw(region) });
        }
    });
}

pub(crate) unsafe extern "C" fn nupp_rust_region_data(region: *const Region) -> *const u8 {
    ffi_value(ptr::null(), || {
        // SAFETY: the Lua region handle retains a strong Arc owner while C
        // obtains this immutable pointer; SharedBytes never reallocates it.
        unsafe { region.as_ref() }
            .map(|region| region.bytes.as_slice().as_ptr())
            .unwrap_or(ptr::null())
    })
}

pub(crate) unsafe extern "C" fn nupp_rust_region_length(region: *const Region) -> usize {
    ffi_value(0, || {
        // SAFETY: the Lua region handle retains a strong Arc owner through call.
        unsafe { region.as_ref() }.map_or(0, |region| region.bytes.len())
    })
}

pub(crate) extern "C" fn nupp_rust_region_account_new() -> *mut AdapterAccount {
    ffi_value(ptr::null_mut(), || {
        Box::into_raw(Box::new(AdapterAccount::default()))
    })
}

pub(crate) unsafe extern "C" fn nupp_rust_region_account_destroy(account: *mut AdapterAccount) {
    ffi_void(|| {
        if !account.is_null() {
            // SAFETY: registry userdata owns this Box and calls its finalizer once.
            drop(unsafe { Box::from_raw(account) });
        }
    });
}

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

pub(crate) unsafe extern "C" fn nupp_rust_region_accounted(
    account: *const AdapterAccount,
) -> usize {
    ffi_value(0, || {
        // SAFETY: registry userdata keeps the account live through this callback.
        unsafe { account.as_ref() }.map_or(0, |account| account.charged)
    })
}

pub(crate) extern "C" fn nupp_rust_region_builder_new() -> *mut AdapterBuilder {
    ffi_value(ptr::null_mut(), || {
        Box::into_raw(Box::new(AdapterBuilder {
            builder: Some(SharedBytesBuilder::default()),
        }))
    })
}

pub(crate) unsafe extern "C" fn nupp_rust_region_builder_destroy(builder: *mut AdapterBuilder) {
    ffi_void(|| {
        if !builder.is_null() {
            // SAFETY: builder userdata owns this Box and finalizes it once.
            drop(unsafe { Box::from_raw(builder) });
        }
    });
}

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
        outbox.waits_for_room.store(true, Ordering::Relaxed);
        let tasks = Arc::new(AdapterTasks::new());
        let payload = host.payload.clone();
        let executable = host.executable.clone();
        let thread_inbox = Arc::clone(&inbox);
        let thread_outbox = Arc::clone(&outbox);
        let thread_tasks = Arc::clone(&tasks);
        let worker = Worker::spawn(
            "nupp.worker.scheduler",
            // One ingress job, the payload; the same byte bound also holds
            // the result queue, so it must leave room for a result or a
            // failure's text, not only for the payload.
            WorkerLimits {
                messages: 1,
                bytes: DEFAULT_QUEUE_BYTES.max(payload.len().saturating_add(1)),
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
                Ok(move |job: WorkerJob| {
                    let answer = runtime
                        .run_buffer(job.bytes.as_slice(), "=nupp-worker", &[])
                        .map(|()| SharedBytes::default())
                        .map_err(|problem| problem.to_string());
                    // No entry can consume more input after the guest stops.
                    // Release queued moved owners and endpoint directions here,
                    // independently of when the parent observes the failure.
                    thread_inbox.queue.close_and_discard();
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
        if let Err(problem) = worker.submit(1, host.payload.clone()) {
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
        worker.inbox.close();
        // A scheduler waiting for room in its outbox would be waiting for a
        // parent that is now waiting for it, so replies are drained while the
        // join waits; nothing reads a lane's replies past its join.
        let event = loop {
            match worker.worker.poll(Some(Duration::from_millis(10))) {
                Ok(None) => {
                    while worker.outbox.pop(0).is_some() {}
                    if worker.worker.is_finished() {
                        break worker.worker.poll(Some(Duration::ZERO));
                    }
                }
                answer => break answer,
            }
        };
        worker.outbox.close();
        let (status, problem) = match event {
            Ok(Some(WorkerEvent::Completed { .. })) => (0, None),
            Ok(Some(WorkerEvent::Failed { error, .. })) => (1, Some(error)),
            Ok(None) => (
                1,
                Some("worker scheduler ended without a result".to_owned()),
            ),
            Err(problem) => (1, Some(problem.to_string())),
        };
        let shutdown = worker.worker.shutdown();
        if let Some(problem) = problem.or_else(|| shutdown.err().map(|error| error.to_string())) {
            write_error(error, error_capacity, &problem);
        }
        status
    })
}

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

pub(crate) extern "C" fn nupp_rust_worker_parallelism() -> usize {
    ffi_value(1, || {
        std::thread::available_parallelism().map_or(1, usize::from)
    })
}

// Application endpoints are generation-checked capabilities. Lua userdata holds
// an authenticated registry key rather than a queue or allocation address.
type MessageEndpoint = Endpoint<Box<AdapterMessage>>;

fn pending_messages() -> &'static Mutex<HashMap<usize, Box<AdapterMessage>>> {
    static PENDING: OnceLock<Mutex<HashMap<usize, Box<AdapterMessage>>>> = OnceLock::new();
    PENDING.get_or_init(|| Mutex::new(HashMap::new()))
}

fn take_pending(key: usize) -> Option<Box<AdapterMessage>> {
    let mut pending = lock(pending_messages());
    let value = pending.remove(&key);
    if pending.is_empty() {
        pending.shrink_to_fit();
    }
    value
}

unsafe extern "C" fn pending_prepare(
    data: *const u8,
    length: usize,
    raw: *const RawAttachment,
    count: usize,
) -> usize {
    ffi_value(0, || {
        // SAFETY: the shim keeps its string and attachment array live for this call.
        let Some(data) = (unsafe { bytes(data, length) }) else {
            return 0;
        };
        let Some(attachments) = attachments(raw, count) else {
            return 0;
        };
        if attachments
            .iter()
            .flatten()
            .any(|item| matches!(item, Attachment::Endpoint(_)))
        {
            return 0;
        }
        static NEXT: AtomicUsize = AtomicUsize::new(1);
        let Ok(key) = NEXT.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |key| {
            key.checked_add(1)
        }) else {
            return 0;
        };
        lock(pending_messages()).insert(
            key,
            Box::new(AdapterMessage {
                kind: 0,
                id: 0,
                number: 0.0,
                first: data.to_vec(),
                second: vec![],
                value: vec![],
                attachments,
            }),
        );
        key
    })
}

unsafe extern "C" fn pending_release(key: usize) -> c_int {
    ffi_value(0, || i32::from(take_pending(key).is_some()))
}

unsafe extern "C" fn pending_take(key: usize) -> *mut AdapterMessage {
    ffi_value(ptr::null_mut(), || {
        take_pending(key).map_or(ptr::null_mut(), Box::into_raw)
    })
}

unsafe extern "C" fn pending_size(key: usize) -> usize {
    ffi_value(usize::MAX, || {
        lock(pending_messages())
            .get(&key)
            .map_or(usize::MAX, |message| message.payload_bytes())
    })
}

unsafe extern "C" fn pending_offer(endpoint: *const MessageEndpoint, key: usize) -> c_int {
    ffi_value(4, || {
        let Some(endpoint) = borrowed_endpoint(endpoint) else {
            return 4;
        };
        let Some(message) = take_pending(key) else {
            return 4;
        };
        let (status, returned) = match endpoint.try_send(message) {
            Ok(()) => return 0,
            Err(SendError::Full(value)) => (1, value),
            Err(SendError::Closed(value)) => (2, value),
            Err(SendError::Oversized(value)) => (3, value),
            Err(SendError::Invalid(value)) => (4, value),
        };
        lock(pending_messages()).insert(key, returned);
        status
    })
}

// Userdata stores an opaque, never-reused key. Validate it before touching Rust
// storage even if a dynamic caller forges another userdata's metatable.
fn endpoint_handles() -> &'static Mutex<HashMap<usize, Arc<MessageEndpoint>>> {
    static HANDLES: OnceLock<Mutex<HashMap<usize, Arc<MessageEndpoint>>>> = OnceLock::new();
    HANDLES.get_or_init(|| Mutex::new(HashMap::new()))
}

fn register_endpoint(endpoint: MessageEndpoint) -> *mut MessageEndpoint {
    register_endpoint_shared(Arc::new(endpoint))
}

fn register_endpoint_shared(endpoint: Arc<MessageEndpoint>) -> *mut MessageEndpoint {
    static NEXT: AtomicUsize = AtomicUsize::new(1);
    let Ok(key) = NEXT.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |value| {
        value.checked_add(1)
    }) else {
        return ptr::null_mut();
    };
    lock(endpoint_handles()).insert(key, endpoint);
    key as *mut MessageEndpoint
}

fn borrowed_endpoint(handle: *const MessageEndpoint) -> Option<Arc<MessageEndpoint>> {
    lock(endpoint_handles()).get(&(handle as usize)).cloned()
}

fn discard_endpoint(handle: *const MessageEndpoint) {
    let endpoint = {
        let mut handles = lock(endpoint_handles());
        let endpoint = handles.remove(&(handle as usize));
        if handles.is_empty() {
            handles.shrink_to_fit();
        }
        endpoint
    };
    if let Some(endpoint) = endpoint {
        endpoint.close();
    }
}

unsafe extern "C" fn endpoint_pair(
    messages: usize,
    bytes: usize,
    receiver: *mut *mut MessageEndpoint,
) -> *mut MessageEndpoint {
    ffi_value(ptr::null_mut(), || {
        if receiver.is_null() {
            return ptr::null_mut();
        }
        let Some((send, receive)) =
            Endpoint::<Box<AdapterMessage>>::pair(messages, bytes, |message| {
                message.payload_bytes()
            })
        else {
            return ptr::null_mut();
        };
        let send = register_endpoint(send);
        let receive = register_endpoint(receive);
        if send.is_null() || receive.is_null() {
            discard_endpoint(send);
            discard_endpoint(receive);
            return ptr::null_mut();
        }
        // SAFETY: C provides one writable output slot for this synchronous call.
        unsafe {
            *receiver = receive;
        }
        send
    })
}

unsafe extern "C" fn endpoint_destroy(endpoint: *mut MessageEndpoint) {
    ffi_void(|| discard_endpoint(endpoint));
}

unsafe extern "C" fn endpoint_close(endpoint: *const MessageEndpoint) {
    ffi_void(|| {
        if let Some(endpoint) = borrowed_endpoint(endpoint) {
            endpoint.close();
        }
    });
}

unsafe extern "C" fn endpoint_transfer(endpoint: *const MessageEndpoint) -> *mut MessageEndpoint {
    ffi_value(ptr::null_mut(), || {
        borrowed_endpoint(endpoint)
            .and_then(|endpoint| endpoint.transfer())
            .map_or(ptr::null_mut(), register_endpoint)
    })
}

unsafe extern "C" fn endpoint_anchor(endpoint: *const MessageEndpoint) -> *mut MessageEndpoint {
    ffi_value(ptr::null_mut(), || {
        borrowed_endpoint(endpoint).map_or(ptr::null_mut(), register_endpoint_shared)
    })
}

unsafe extern "C" fn endpoint_abort(endpoint: *const MessageEndpoint) {
    ffi_void(|| {
        if let Some(endpoint) = borrowed_endpoint(endpoint) {
            endpoint.abort_resource();
        }
    });
}

unsafe extern "C" fn endpoint_send(
    endpoint: *const MessageEndpoint,
    data: *const u8,
    length: usize,
) -> c_int {
    ffi_value(4, || {
        let Some(endpoint) = borrowed_endpoint(endpoint) else {
            return 4;
        };
        if !endpoint.is_live() || !endpoint.is_sender() {
            return 4;
        }
        if length > endpoint.byte_limit() {
            return 3;
        }
        // SAFETY: C retains the immutable Lua string for this call only.
        let Some(data) = (unsafe { bytes(data, length) }) else {
            return 4;
        };
        match endpoint.try_send(Box::new(AdapterMessage {
            kind: 0,
            id: 0,
            number: 0.0,
            first: data.to_vec(),
            second: vec![],
            value: vec![],
            attachments: vec![],
        })) {
            Ok(()) => 0,
            Err(SendError::Full(_)) => 1,
            Err(SendError::Closed(_)) => 2,
            Err(SendError::Oversized(_)) => 3,
            Err(SendError::Invalid(_)) => 4,
        }
    })
}

unsafe extern "C" fn endpoint_direction(endpoint: *const MessageEndpoint) -> c_int {
    ffi_value(-1, || {
        borrowed_endpoint(endpoint).map_or(-1, |endpoint| {
            if endpoint.is_live() {
                i32::from(endpoint.is_sender())
            } else {
                -2
            }
        })
    })
}

unsafe extern "C" fn attachment_kind(message: *const AdapterMessage, index: usize) -> c_int {
    ffi_value(-1, || {
        // SAFETY: C retains the message while peeking before an owning take.
        unsafe { message.as_ref() }
            .and_then(|message| message.attachments.get(index))
            .and_then(Option::as_ref)
            .map_or(-1, |attachment| match attachment {
                Attachment::Region { .. } => 0,
                Attachment::Moved { .. } => 1,
                Attachment::Endpoint(_) => 2,
            })
    })
}

unsafe extern "C" fn endpoint_ready(endpoint: *const MessageEndpoint, bytes: usize) -> c_int {
    ffi_value(4, || {
        borrowed_endpoint(endpoint).map_or(4, |endpoint| endpoint.readiness(bytes) as c_int)
    })
}

unsafe extern "C" fn endpoint_wait(
    endpoint: *const MessageEndpoint,
    bytes: usize,
    timeout_ms: i32,
) -> c_int {
    ffi_value(4, || {
        // Short waits let the guest check cancellation between host sleeps.
        let timeout = Duration::from_millis(if timeout_ms < 0 {
            10
        } else {
            timeout_ms.min(10) as u64
        });
        // The lookup releases the registry lock before sleeping on this queue.
        borrowed_endpoint(endpoint)
            .map_or(4, |endpoint| endpoint.wait_ready(bytes, timeout) as c_int)
    })
}

unsafe extern "C" fn endpoint_receive(
    endpoint: *const MessageEndpoint,
    status: *mut c_int,
) -> *mut AdapterMessage {
    ffi_value(ptr::null_mut(), || {
        if status.is_null() {
            return ptr::null_mut();
        }
        // Resolve the opaque handle before touching endpoint storage.
        let answer =
            borrowed_endpoint(endpoint).map_or(Receive::Invalid, |endpoint| endpoint.try_receive());
        let (code, value) = match answer {
            Receive::Value(value) => (0, Some(value)),
            Receive::Empty => (1, None),
            Receive::Closed => (2, None),
            Receive::Invalid => (4, None),
        };
        // SAFETY: C keeps the status slot writable until this call returns.
        unsafe {
            *status = code;
        }
        value.map_or(ptr::null_mut(), Box::into_raw)
    })
}

/// The shim's entry points into this module, handed to C as one table so that
/// none of them is a symbol the library exports. Field order and signatures
/// match `NuppRustWorkerAdapter` in `worker_shim.c` exactly.
#[repr(C)]
pub(crate) struct WorkerAdapterTable {
    worker_channel_new: extern "C" fn() -> *const AdapterChannel,
    worker_channel_destroy: unsafe extern "C" fn(*const AdapterChannel),
    worker_channel_close: unsafe extern "C" fn(*const AdapterChannel),
    worker_channel_count: unsafe extern "C" fn(*const AdapterChannel) -> usize,
    worker_channel_closed: unsafe extern "C" fn(*const AdapterChannel) -> c_int,
    worker_channel_push: unsafe extern "C" fn(
        *const AdapterChannel,
        c_int,
        i64,
        f64,
        *const u8,
        usize,
        *const u8,
        usize,
        *const u8,
        usize,
        *const RawAttachment,
        usize,
    ) -> c_int,
    worker_channel_pop: unsafe extern "C" fn(*const AdapterChannel, i32) -> *mut AdapterMessage,
    worker_message_destroy: unsafe extern "C" fn(*mut AdapterMessage),
    worker_message_kind: unsafe extern "C" fn(*const AdapterMessage) -> c_int,
    worker_message_id: unsafe extern "C" fn(*const AdapterMessage) -> i64,
    worker_message_number: unsafe extern "C" fn(*const AdapterMessage) -> f64,
    worker_message_bytes:
        unsafe extern "C" fn(*const AdapterMessage, c_int, *mut usize) -> *const u8,
    worker_message_attachment_count: unsafe extern "C" fn(*const AdapterMessage) -> usize,
    worker_message_take_attachment:
        unsafe extern "C" fn(*mut AdapterMessage, usize, *mut RawAttachment) -> c_int,
    worker_channel_dict_register:
        unsafe extern "C" fn(*const AdapterChannel, *const u8, usize) -> usize,
    worker_channel_dict_count: unsafe extern "C" fn(*const AdapterChannel) -> usize,
    worker_channel_dict_address:
        unsafe extern "C" fn(*const AdapterChannel, usize, *mut usize) -> *const u8,
    region_new: unsafe extern "C" fn(*const u8, usize) -> *const Region,
    region_read_file: unsafe extern "C" fn(*const u8, usize, *mut c_char, usize) -> *const Region,
    region_release: unsafe extern "C" fn(*const Region),
    region_data: unsafe extern "C" fn(*const Region) -> *const u8,
    region_length: unsafe extern "C" fn(*const Region) -> usize,
    region_account_new: extern "C" fn() -> *mut AdapterAccount,
    region_account_destroy: unsafe extern "C" fn(*mut AdapterAccount),
    region_account_charge: unsafe extern "C" fn(*mut AdapterAccount, *const Region) -> usize,
    region_account_discharge: unsafe extern "C" fn(*mut AdapterAccount, *const Region),
    region_accounted: unsafe extern "C" fn(*const AdapterAccount) -> usize,
    region_builder_new: extern "C" fn() -> *mut AdapterBuilder,
    region_builder_destroy: unsafe extern "C" fn(*mut AdapterBuilder),
    region_builder_append: unsafe extern "C" fn(*mut AdapterBuilder, *const u8, usize) -> c_int,
    region_builder_reserve: unsafe extern "C" fn(*mut AdapterBuilder, usize) -> *mut u8,
    region_builder_commit: unsafe extern "C" fn(*mut AdapterBuilder, usize) -> c_int,
    region_builder_open: unsafe extern "C" fn(*const AdapterBuilder) -> c_int,
    region_builder_freeze: unsafe extern "C" fn(*mut AdapterBuilder) -> *const Region,
    worker_spawn: unsafe extern "C" fn(
        *const WorkersHost,
        *const AdapterChannel,
        *const AdapterChannel,
        *mut c_char,
        usize,
    ) -> *mut AdapterWorker,
    worker_join: unsafe extern "C" fn(*mut AdapterWorker, *mut c_char, usize) -> c_int,
    worker_task_create: unsafe extern "C" fn(*const AdapterWorker, i64, c_int, f64) -> c_int,
    worker_task_cancel: unsafe extern "C" fn(*const AdapterWorker, i64) -> c_int,
    worker_task_start: unsafe extern "C" fn(*const AdapterTasks, i64, *mut c_int) -> c_int,
    worker_task_checkpoint: unsafe extern "C" fn(*const AdapterTasks, *mut c_int) -> c_int,
    worker_task_finish: unsafe extern "C" fn(*const AdapterTasks, i64, *mut c_int) -> c_int,
    worker_task_release: unsafe extern "C" fn(*const AdapterWorker, i64),
    worker_task_status: unsafe extern "C" fn(*const AdapterWorker, i64) -> c_int,
    worker_parallelism: extern "C" fn() -> usize,
    endpoint_pair:
        unsafe extern "C" fn(usize, usize, *mut *mut MessageEndpoint) -> *mut MessageEndpoint,
    endpoint_destroy: unsafe extern "C" fn(*mut MessageEndpoint),
    endpoint_close: unsafe extern "C" fn(*const MessageEndpoint),
    endpoint_transfer: unsafe extern "C" fn(*const MessageEndpoint) -> *mut MessageEndpoint,
    endpoint_send: unsafe extern "C" fn(*const MessageEndpoint, *const u8, usize) -> c_int,
    endpoint_receive:
        unsafe extern "C" fn(*const MessageEndpoint, *mut c_int) -> *mut AdapterMessage,
    endpoint_ready: unsafe extern "C" fn(*const MessageEndpoint, usize) -> c_int,
    endpoint_wait: unsafe extern "C" fn(*const MessageEndpoint, usize, i32) -> c_int,
    endpoint_direction: unsafe extern "C" fn(*const MessageEndpoint) -> c_int,
    attachment_kind: unsafe extern "C" fn(*const AdapterMessage, usize) -> c_int,
    pending_prepare: unsafe extern "C" fn(*const u8, usize, *const RawAttachment, usize) -> usize,
    pending_release: unsafe extern "C" fn(usize) -> c_int,
    pending_take: unsafe extern "C" fn(usize) -> *mut AdapterMessage,
    pending_size: unsafe extern "C" fn(usize) -> usize,
    pending_offer: unsafe extern "C" fn(*const MessageEndpoint, usize) -> c_int,
    endpoint_anchor: unsafe extern "C" fn(*const MessageEndpoint) -> *mut MessageEndpoint,
    endpoint_abort: unsafe extern "C" fn(*const MessageEndpoint),
}

static WORKER_ADAPTER: WorkerAdapterTable = WorkerAdapterTable {
    worker_channel_new: nupp_rust_worker_channel_new,
    worker_channel_destroy: nupp_rust_worker_channel_destroy,
    worker_channel_close: nupp_rust_worker_channel_close,
    worker_channel_count: nupp_rust_worker_channel_count,
    worker_channel_closed: nupp_rust_worker_channel_closed,
    worker_channel_push: nupp_rust_worker_channel_push,
    worker_channel_pop: nupp_rust_worker_channel_pop,
    worker_message_destroy: nupp_rust_worker_message_destroy,
    worker_message_kind: nupp_rust_worker_message_kind,
    worker_message_id: nupp_rust_worker_message_id,
    worker_message_number: nupp_rust_worker_message_number,
    worker_message_bytes: nupp_rust_worker_message_bytes,
    worker_message_attachment_count: nupp_rust_worker_message_attachment_count,
    worker_message_take_attachment: nupp_rust_worker_message_take_attachment,
    worker_channel_dict_register: nupp_rust_worker_channel_dict_register,
    worker_channel_dict_count: nupp_rust_worker_channel_dict_count,
    worker_channel_dict_address: nupp_rust_worker_channel_dict_address,
    region_new: nupp_rust_region_new,
    region_read_file: nupp_rust_region_read_file,
    region_release: nupp_rust_region_release,
    region_data: nupp_rust_region_data,
    region_length: nupp_rust_region_length,
    region_account_new: nupp_rust_region_account_new,
    region_account_destroy: nupp_rust_region_account_destroy,
    region_account_charge: nupp_rust_region_account_charge,
    region_account_discharge: nupp_rust_region_account_discharge,
    region_accounted: nupp_rust_region_accounted,
    region_builder_new: nupp_rust_region_builder_new,
    region_builder_destroy: nupp_rust_region_builder_destroy,
    region_builder_append: nupp_rust_region_builder_append,
    region_builder_reserve: nupp_rust_region_builder_reserve,
    region_builder_commit: nupp_rust_region_builder_commit,
    region_builder_open: nupp_rust_region_builder_open,
    region_builder_freeze: nupp_rust_region_builder_freeze,
    worker_spawn: nupp_rust_worker_spawn,
    worker_join: nupp_rust_worker_join,
    worker_task_create: nupp_rust_worker_task_create,
    worker_task_cancel: nupp_rust_worker_task_cancel,
    worker_task_start: nupp_rust_worker_task_start,
    worker_task_checkpoint: nupp_rust_worker_task_checkpoint,
    worker_task_finish: nupp_rust_worker_task_finish,
    worker_task_release: nupp_rust_worker_task_release,
    worker_task_status: nupp_rust_worker_task_status,
    worker_parallelism: nupp_rust_worker_parallelism,
    endpoint_pair,
    endpoint_destroy,
    endpoint_close,
    endpoint_transfer,
    endpoint_send,
    endpoint_receive,
    endpoint_ready,
    endpoint_wait,
    endpoint_direction,
    attachment_kind,
    pending_prepare,
    pending_release,
    pending_take,
    pending_size,
    pending_offer,
    endpoint_anchor,
    endpoint_abort,
};

unsafe extern "C" {
    fn nupp_worker_shim_install(table: *const WorkerAdapterTable);
}

/// Gives the shim its table. Once per process, before any state can open the
/// worker modules; `Once` orders that write before every later caller.
pub(crate) fn install_shim() {
    static INSTALLED: std::sync::Once = std::sync::Once::new();
    INSTALLED.call_once(|| {
        // SAFETY: the table is a static that lives for the whole process, and
        // the shim only stores the pointer.
        unsafe { nupp_worker_shim_install(&raw const WORKER_ADAPTER) };
    });
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
    fn pending_storage_counts_backing_bytes_and_survives_refusal() {
        let region = Arc::new(Region {
            bytes: SharedBytes::new(vec![0; 4096]),
        });
        let raw = RawAttachment {
            kind: 0,
            block: Arc::as_ptr(&region).cast_mut().cast(),
            first: 1,
            length: 1,
        };
        unsafe {
            let key = pending_prepare(b"wire".as_ptr(), 4, &raw, 1);
            assert_ne!(key, 0);
            assert_eq!(pending_size(key), 4100);
            assert_eq!(Arc::strong_count(&region), 2);
            let mut receiver = ptr::null_mut();
            let sender = endpoint_pair(1, 128, &mut receiver);
            assert_eq!(pending_offer(sender, key), 3);
            assert_eq!(pending_size(key), 4100);
            pending_release(key);
            pending_release(key);
            assert_eq!(Arc::strong_count(&region), 1);
            assert!(pending_take(key).is_null());
            endpoint_destroy(sender);
            endpoint_destroy(receiver);
        }
    }

    #[test]
    fn queued_storage_has_one_owner_after_a_move_or_receiver_close() {
        let region = Arc::new(Region {
            bytes: SharedBytes::new(vec![7; 8]),
        });
        let raw = RawAttachment {
            kind: 0,
            block: Arc::as_ptr(&region).cast_mut().cast(),
            first: 1,
            length: 8,
        };
        unsafe {
            let mut receiver = ptr::null_mut();
            let sender = endpoint_pair(1, 128, &mut receiver);
            assert_eq!(endpoint_send(sender, b"filled".as_ptr(), 6), 0);
            let anchor = endpoint_anchor(sender);
            let key = pending_prepare(b"wire".as_ptr(), 4, &raw, 1);
            assert_eq!(pending_offer(sender, key), 1);
            assert_eq!(Arc::strong_count(&region), 2);
            let moved = endpoint_transfer(sender);
            assert_eq!(pending_offer(sender, key), 4);
            let mut status = 4;
            nupp_rust_worker_message_destroy(endpoint_receive(receiver, &mut status));
            assert_eq!(status, 0);
            assert_eq!(pending_offer(moved, key), 0);
            assert!(pending_take(key).is_null());
            endpoint_abort(anchor);
            assert_eq!(Arc::strong_count(&region), 1);
            endpoint_destroy(sender);
            endpoint_destroy(moved);
            endpoint_destroy(receiver);
            endpoint_destroy(anchor);
        }
    }

    #[test]
    fn lua_endpoint_handles_enforce_bounds_moves_and_directional_close() {
        let mut runtime = HostRuntime::owned(true, None).unwrap();
        runtime.enable_workers(b"return nil").unwrap();
        runtime
            .run_buffer(
                br#"
local native = require("nupp.workers.native")
for _, limits in ipairs({{0, 1}, {1, 0}, {-1, 1}, {1.5, 1}, {1, math.huge}, {0/0, 1}}) do
    assert(not pcall(native.endpointCreate, unpack(limits)))
end
assert(native.endpointReady({}, 0) == 4)
assert(native.endpointWait({}, 0, 0) == 4)
local sender, receiver = native.endpointCreate(2, 3)
assert(native.endpointReady(sender, 3) == 0)
assert(native.endpointReady(sender, 4) == 3)
assert(native.endpointWait(receiver, 0, 0) == 1)
assert(native.endpointReady(sender, -1) == 4)
assert(native.endpointReady(sender, 0/0) == 4)
assert(native.endpointWait(receiver, 0, math.huge) == 4)
assert(native.endpointSend(receiver, "x") == 4)
assert(native.endpointReceive(sender) == 4)
assert(native.endpointSend({}, "x") == 4)
assert(native.endpointSend(123, "x") == 4)
local foreign = io.stdout
local original = getmetatable(foreign)
debug.setmetatable(foreign, getmetatable(sender))
assert(native.endpointSend(foreign, "x") == 4)
assert(native.endpointReceive(foreign) == 4)
assert(native.endpointDirection(foreign) == -1)
debug.setmetatable(foreign, original)
assert(native.endpointSend(sender, "abcd") == 3)
assert(native.endpointSend(sender, "ab") == 0)
assert(native.endpointSend(sender, "c") == 0)
assert(native.endpointSend(sender, "") == 1)
local status, bytes = native.endpointReceive(receiver)
assert(status == 0 and bytes == "ab")
local moved = native.endpointMove(sender)
assert(native.endpointSend(sender, "x") == 4)
assert(not pcall(native.endpointMove, sender))
native.endpointClose(sender)
assert(native.endpointSend(moved, "de") == 0)
native.endpointClose(moved)
assert(native.endpointSend(moved, "x") == 4)
status, bytes = native.endpointReceive(receiver)
assert(status == 0 and bytes == "c")
status, bytes = native.endpointReceive(receiver)
assert(status == 0 and bytes == "de")
assert(native.endpointReceive(receiver) == 2)
local producer, consumer = native.endpointCreate(1, 1)
assert(native.endpointSend(producer, "x") == 0)
native.endpointClose(consumer)
assert(native.endpointSend(producer, "x") == 2)
assert(native.endpointReceive(consumer) == 4)
local abandoned, ending = native.endpointCreate(1, 1)
abandoned = nil
collectgarbage("collect")
assert(native.endpointReceive(ending) == 2)
local upstream, downstream = native.endpointCreate(1, 8)
local moved = native.endpointMove(downstream)
local bridge = native.channelCreate()
assert(native.channelPushBufferTask(bridge, 1, "fixture", "entry", 1, "", {moved, 0, 0}))
assert(native.endpointDirection(moved) == -1)
local _, _, _, _, _, _, _, _, flat = native.channelPop(bridge, 0)
assert(native.endpointDirection(flat[1]) == 0)
assert(native.endpointSend(upstream, "during execution") == 3)
assert(native.endpointSend(upstream, "live") == 0)
local code, payload = native.endpointReceive(flat[1])
assert(code == 0 and payload == "live")
native.endpointClose(flat[1])
assert(native.endpointSend(upstream, "closed") == 2)
native.endpointClose(upstream)
native.channelClose(bridge)
native.channelDestroy(bridge)
local producing, consuming = native.endpointCreate(1, 8)
local lifetime = native.endpointAnchor(producing)
local transferred = native.endpointMove(producing)
assert(native.endpointSend(lifetime, "forged direction") == 4)
assert(native.endpointSend(transferred, "held") == 0)
native.channelRelease(lifetime)
native.channelRelease(lifetime)
assert(native.endpointReceive(consuming) == 2)
assert(native.endpointSend(transferred, "late") == 2)
native.endpointClose(transferred)
native.endpointClose(consuming)
"#,
                "=endpoint-contract",
                &[],
            )
            .unwrap();
        runtime.shutdown().unwrap();
    }

    #[test]
    fn rust_panic_firewall_returns_conservative_values() {
        assert_eq!(ffi_value(17, || panic!("value boundary fixture")), 17);
        ffi_void(|| panic!("void boundary fixture"));
    }

    #[test]
    fn a_payload_whose_destructor_panics_stays_inside_the_firewall() {
        // Both payloads are zero-sized, so the one the firewall leaks by design
        // allocates nothing for LeakSanitizer to see.
        struct Bomb;
        impl Drop for Bomb {
            fn drop(&mut self) {
                std::panic::panic_any(());
            }
        }
        assert_eq!(ffi_value(5, || -> i32 { std::panic::panic_any(Bomb) }), 5);
        ffi_void(|| std::panic::panic_any(Bomb));
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

    fn empty_message(id: i64) -> Box<AdapterMessage> {
        Box::new(AdapterMessage {
            kind: 0,
            id,
            number: 0.0,
            first: vec![],
            second: vec![],
            value: vec![],
            attachments: vec![],
        })
    }

    #[test]
    fn an_outbox_producer_waits_for_room_instead_of_being_refused() {
        let channel = Arc::new(AdapterChannel::new());
        channel.waits_for_room.store(true, Ordering::Relaxed);
        for id in 0..MAX_MESSAGES {
            assert!(channel.try_push(empty_message(id as i64)));
        }
        let producer = {
            let channel = Arc::clone(&channel);
            std::thread::spawn(move || channel.try_push(empty_message(-1)))
        };
        // The producer is still waiting: nothing has left the queue.
        std::thread::sleep(Duration::from_millis(20));
        assert!(!producer.is_finished());
        assert_eq!(channel.pop(0).unwrap().id, 0);
        assert!(producer.join().unwrap());
        for _ in 1..MAX_MESSAGES {
            channel.pop(0).unwrap();
        }
        assert_eq!(channel.pop(0).unwrap().id, -1);
        for id in 0..MAX_MESSAGES {
            assert!(channel.try_push(empty_message(id as i64)));
        }

        // Closing refuses a waiting producer rather than stranding it.
        let producer = {
            let channel = Arc::clone(&channel);
            std::thread::spawn(move || channel.try_push(empty_message(-2)))
        };
        std::thread::sleep(Duration::from_millis(20));
        channel.close();
        assert!(!producer.join().unwrap());
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
                Ok(|job: WorkerJob| Ok(job.bytes))
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
