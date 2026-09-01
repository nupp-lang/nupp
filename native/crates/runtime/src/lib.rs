//! Bounded, Lua-free native lane bookkeeping.

use nupp_native_abi::Handle;
use std::collections::{HashSet, VecDeque};
use std::fmt;
use std::sync::{Condvar, Mutex, MutexGuard};
use std::time::Duration;

#[cfg(feature = "async")]
use std::sync::OnceLock;
#[cfg(feature = "async")]
use tokio::runtime::{Builder, Runtime};

#[cfg(feature = "async")]
fn pin_anchor() {}

/// Keeps the image containing the shared executor loaded for the remainder of
/// the process.
///
/// LuaJIT owns `ffi.load` handles through garbage-collected values. A Lua state
/// may therefore release its handle while another state, or a Tokio worker,
/// still has native work in flight. Retaining the image at the operating-system
/// loader prevents those threads from returning into unmapped Rust code.
#[cfg(feature = "async")]
fn pin_current_image() -> Result<(), &'static str> {
    static PINNED: OnceLock<Result<(), String>> = OnceLock::new();
    match PINNED.get_or_init(platform_pin_current_image) {
        Ok(()) => Ok(()),
        Err(error) => Err(error.as_str()),
    }
}

#[cfg(all(feature = "async", unix))]
fn platform_pin_current_image() -> Result<(), String> {
    use std::ffi::{CStr, c_char, c_int, c_void};
    use std::mem::MaybeUninit;
    use std::os::unix::ffi::OsStrExt;
    use std::path::Path;

    #[repr(C)]
    struct DlInfo {
        filename: *const c_char,
        base: *mut c_void,
        symbol_name: *const c_char,
        symbol_address: *mut c_void,
    }

    #[cfg_attr(not(target_vendor = "apple"), link(name = "dl"))]
    unsafe extern "C" {
        fn dladdr(address: *const c_void, info: *mut DlInfo) -> c_int;
        fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
        fn dlerror() -> *const c_char;
    }

    const RTLD_NOW: c_int = 2;

    let mut info = MaybeUninit::<DlInfo>::uninit();
    // SAFETY: `pin_anchor` is a live address in the current image and `info`
    // points to writable storage for the loader's fixed-layout result.
    if unsafe { dladdr(pin_anchor as *const () as *const c_void, info.as_mut_ptr()) } == 0 {
        return Err("cannot identify the loaded Rust native library".to_owned());
    }
    // SAFETY: a successful `dladdr` initialized the record.
    let info = unsafe { info.assume_init() };
    if info.filename.is_null() {
        return Err("the loaded Rust native library has no loader path".to_owned());
    }

    // Code linked directly into the process executable cannot be unloaded and
    // needs no extra loader reference. This also lets crate tests exercise the
    // same initialization path without trying to dlopen their PIE executable.
    // SAFETY: `dladdr` returns a NUL-terminated path owned by the loader.
    let filename = unsafe { CStr::from_ptr(info.filename) };
    let image_path = Path::new(std::ffi::OsStr::from_bytes(filename.to_bytes()));
    if let Ok(executable) = std::env::current_exe() {
        let same_canonical_image = match (image_path.canonicalize(), executable.canonicalize()) {
            (Ok(image), Ok(executable)) => image == executable,
            _ => false,
        };
        let same_image = image_path == executable || same_canonical_image;
        if same_image {
            return Ok(());
        }
    }

    // `dlopen` increments the image's loader reference count. The returned
    // reference is intentionally never paired with `dlclose`: losing the
    // opaque value does not release it, so this is a process-lifetime pin.
    // SAFETY: `filename` remains valid for the call and names the image that
    // contains `pin_anchor`.
    let retained = unsafe { dlopen(info.filename, RTLD_NOW) };
    if retained.is_null() {
        // SAFETY: `dlerror` returns either null or a loader-owned C string.
        let detail = unsafe {
            let error = dlerror();
            if error.is_null() {
                "unknown loader error".to_owned()
            } else {
                CStr::from_ptr(error).to_string_lossy().into_owned()
            }
        };
        return Err(format!("cannot pin the Rust native library: {detail}"));
    }
    Ok(())
}

#[cfg(all(feature = "async", windows))]
fn platform_pin_current_image() -> Result<(), String> {
    use std::ffi::c_void;
    use std::ptr;

    type Module = *mut c_void;

    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetModuleHandleExW(flags: u32, name: *const u16, module: *mut Module) -> i32;
    }

    const FROM_ADDRESS: u32 = 0x0000_0004;
    const PIN: u32 = 0x0000_0001;

    let mut module: Module = ptr::null_mut();
    // With FROM_ADDRESS, Windows interprets `name` as an address in the module
    // rather than as UTF-16. PIN makes that module non-unloadable until process
    // termination and does not require keeping the returned handle alive.
    // SAFETY: `pin_anchor` is a live address and `module` is writable output.
    let pinned = unsafe {
        GetModuleHandleExW(
            FROM_ADDRESS | PIN,
            pin_anchor as *const () as *const u16,
            &mut module,
        )
    };
    if pinned == 0 || module.is_null() {
        return Err(format!(
            "cannot pin the Rust native library: Windows error {}",
            std::io::Error::last_os_error()
        ));
    }
    Ok(())
}

#[cfg(all(feature = "async", not(any(unix, windows))))]
fn platform_pin_current_image() -> Result<(), String> {
    Err("the Rust native executor cannot pin its library on this platform".to_owned())
}

/// The process-wide executor used by asynchronous native providers.
///
/// Provider tasks may operate only on Rust-owned state and report readiness to
/// their owning lane. They never enter Lua from an executor thread.
#[cfg(feature = "async")]
pub fn executor() -> Result<&'static Runtime, &'static str> {
    static EXECUTOR: OnceLock<Result<Runtime, String>> = OnceLock::new();
    match EXECUTOR.get_or_init(|| {
        pin_current_image().map_err(str::to_owned)?;
        let workers = std::env::var("NUPP_NATIVE_WORKERS")
            .ok()
            .and_then(|value| value.parse::<usize>().ok())
            .filter(|value| *value > 0)
            .unwrap_or_else(|| {
                std::thread::available_parallelism()
                    .map(usize::from)
                    .unwrap_or(2)
                    .clamp(2, 8)
            });
        Builder::new_multi_thread()
            .worker_threads(workers)
            .enable_all()
            .thread_name("nupp-native")
            .build()
            .map_err(|error| error.to_string())
    }) {
        Ok(runtime) => Ok(runtime),
        Err(error) => Err(error.as_str()),
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Phase {
    Open,
    Closing,
    Closed,
}

struct State {
    phase: Phase,
    pending: HashSet<Handle>,
    ready: HashSet<Handle>,
    queue: VecDeque<Handle>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LaneError {
    ZeroCapacity,
    Capacity,
    Duplicate,
    Unknown,
    Closing,
    Pending(usize),
    Poisoned,
}

impl fmt::Display for LaneError {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ZeroCapacity => write!(out, "lane capacity must be positive"),
            Self::Capacity => write!(out, "lane capacity is exhausted"),
            Self::Duplicate => write!(out, "operation is already registered"),
            Self::Unknown => write!(out, "operation is not registered"),
            Self::Closing => write!(out, "lane is shutting down"),
            Self::Pending(count) => write!(out, "lane still owns {count} operations"),
            Self::Poisoned => write!(out, "lane state was poisoned"),
        }
    }
}

impl std::error::Error for LaneError {}

/// One runtime's bounded cross-thread completion lane.
pub struct NativeLane {
    capacity: usize,
    state: Mutex<State>,
    changed: Condvar,
}

impl NativeLane {
    pub fn new(capacity: usize) -> Result<Self, LaneError> {
        if capacity == 0 {
            return Err(LaneError::ZeroCapacity);
        }
        Ok(Self {
            capacity,
            state: Mutex::new(State {
                phase: Phase::Open,
                pending: HashSet::with_capacity(capacity),
                ready: HashSet::with_capacity(capacity),
                queue: VecDeque::with_capacity(capacity),
            }),
            changed: Condvar::new(),
        })
    }

    pub fn register(&self, handle: Handle) -> Result<(), LaneError> {
        let mut state = self.lock()?;
        if state.phase != Phase::Open {
            return Err(LaneError::Closing);
        }
        if !handle.is_valid() {
            return Err(LaneError::Unknown);
        }
        if state.pending.contains(&handle) {
            return Err(LaneError::Duplicate);
        }
        if state.pending.len() == self.capacity {
            return Err(LaneError::Capacity);
        }
        state.pending.insert(handle);
        Ok(())
    }

    pub fn complete(&self, handle: Handle) -> Result<(), LaneError> {
        let mut state = self.lock()?;
        if !state.pending.contains(&handle) {
            return Err(LaneError::Unknown);
        }
        if state.ready.insert(handle) {
            debug_assert!(state.queue.len() < self.capacity);
            state.queue.push_back(handle);
            self.changed.notify_all();
        }
        Ok(())
    }

    pub fn retire(&self, handle: Handle) -> Result<(), LaneError> {
        let mut state = self.lock()?;
        if !state.pending.remove(&handle) {
            return Err(LaneError::Unknown);
        }
        state.ready.remove(&handle);
        state.queue.retain(|queued| *queued != handle);
        self.changed.notify_all();
        Ok(())
    }

    pub fn poll(&self, limit: usize) -> Result<Vec<Handle>, LaneError> {
        let mut state = self.lock()?;
        Ok(take_ready(&mut state, limit))
    }

    pub fn wait(&self, limit: usize, timeout: Duration) -> Result<Vec<Handle>, LaneError> {
        let state = self.lock()?;
        let mut state = if state.ready.is_empty() && state.phase == Phase::Open {
            self.changed
                .wait_timeout(state, timeout)
                .map_err(|_| LaneError::Poisoned)?
                .0
        } else {
            state
        };
        Ok(take_ready(&mut state, limit))
    }

    pub fn begin_shutdown(&self) -> Result<Vec<Handle>, LaneError> {
        let mut state = self.lock()?;
        if state.phase == Phase::Open {
            state.phase = Phase::Closing;
            self.changed.notify_all();
        }
        Ok(state.pending.iter().copied().collect())
    }

    pub fn finish_shutdown(&self) -> Result<(), LaneError> {
        let mut state = self.lock()?;
        if !state.pending.is_empty() {
            return Err(LaneError::Pending(state.pending.len()));
        }
        state.phase = Phase::Closed;
        state.ready.clear();
        state.queue.clear();
        self.changed.notify_all();
        Ok(())
    }

    pub fn pending(&self) -> Result<usize, LaneError> {
        Ok(self.lock()?.pending.len())
    }

    pub fn is_shutting_down(&self) -> bool {
        self.state
            .lock()
            .map_or(true, |state| state.phase != Phase::Open)
    }

    fn lock(&self) -> Result<MutexGuard<'_, State>, LaneError> {
        self.state.lock().map_err(|_| LaneError::Poisoned)
    }
}

fn take_ready(state: &mut State, limit: usize) -> Vec<Handle> {
    let mut out = Vec::with_capacity(limit.min(state.ready.len()));
    while out.len() < limit {
        let Some(handle) = state.queue.pop_front() else {
            break;
        };
        if state.ready.remove(&handle) {
            out.push(handle);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Barrier, mpsc};

    fn handle(value: u64) -> Handle {
        Handle::from_raw((1_u64 << 32) | value)
    }

    #[cfg(feature = "async")]
    #[test]
    fn executor_initialization_pins_its_image_once() {
        pin_current_image().expect("pin the image containing the executor");
        pin_current_image().expect("repeat the process-lifetime pin");
        let first = executor().expect("create the shared executor");
        let second = executor().expect("reuse the shared executor");
        assert!(std::ptr::eq(first, second));
    }

    #[cfg(feature = "async")]
    #[test]
    fn executor_carries_a_tokio_io_driver() {
        executor()
            .expect("create the shared executor")
            .block_on(async {
                // The connection may be refused or prohibited by a test
                // sandbox. Constructing and polling it is the assertion: a
                // Tokio runtime without an I/O driver panics before it can
                // report either operating-system result.
                let _ = tokio::time::timeout(
                    Duration::from_millis(100),
                    tokio::net::TcpStream::connect(("127.0.0.1", 1)),
                )
                .await;
            });
    }

    #[test]
    fn pending_and_ready_work_share_one_bound() {
        let lane = NativeLane::new(2).unwrap();
        lane.register(handle(1)).unwrap();
        lane.register(handle(2)).unwrap();
        assert_eq!(lane.register(handle(3)), Err(LaneError::Capacity));
        lane.complete(handle(1)).unwrap();
        lane.complete(handle(1)).unwrap();
        lane.complete(handle(2)).unwrap();
        assert_eq!(lane.poll(8).unwrap(), vec![handle(1), handle(2)]);
    }

    #[test]
    fn retirement_discards_queued_readiness() {
        let lane = NativeLane::new(1).unwrap();
        lane.register(handle(1)).unwrap();
        lane.complete(handle(1)).unwrap();
        lane.retire(handle(1)).unwrap();
        assert!(lane.poll(1).unwrap().is_empty());
        assert_eq!(lane.pending(), Ok(0));
    }

    #[test]
    fn completion_wakes_a_waiter_without_losing_readiness() {
        let lane = Arc::new(NativeLane::new(1).unwrap());
        lane.register(handle(1)).unwrap();
        let waiter = Arc::clone(&lane);
        let (started, begin) = mpsc::channel();
        let waiting = std::thread::spawn(move || {
            started.send(()).unwrap();
            waiter.wait(1, Duration::from_secs(2)).unwrap()
        });
        begin.recv().unwrap();
        lane.complete(handle(1)).unwrap();
        assert_eq!(waiting.join().unwrap(), vec![handle(1)]);
        lane.retire(handle(1)).unwrap();
    }

    #[test]
    fn retirement_racing_completion_never_leaves_stale_readiness() {
        for generation in 1..=128 {
            let lane = Arc::new(NativeLane::new(1).unwrap());
            let operation = Handle::from_raw((generation << 32) | 1);
            lane.register(operation).unwrap();
            let barrier = Arc::new(Barrier::new(3));

            let completing = Arc::clone(&lane);
            let complete_barrier = Arc::clone(&barrier);
            let complete = std::thread::spawn(move || {
                complete_barrier.wait();
                completing.complete(operation)
            });
            let retiring = Arc::clone(&lane);
            let retire_barrier = Arc::clone(&barrier);
            let retire = std::thread::spawn(move || {
                retire_barrier.wait();
                retiring.retire(operation)
            });
            barrier.wait();

            let completed = complete.join().unwrap();
            assert!(matches!(completed, Ok(()) | Err(LaneError::Unknown)));
            retire.join().unwrap().unwrap();
            assert!(lane.poll(1).unwrap().is_empty());
            assert_eq!(lane.pending(), Ok(0));
        }
    }

    #[test]
    fn shutdown_wakes_waiters_before_the_lane_is_retired() {
        let lane = Arc::new(NativeLane::new(1).unwrap());
        let waiter = Arc::clone(&lane);
        let (started, begin) = mpsc::channel();
        let waiting = std::thread::spawn(move || {
            started.send(()).unwrap();
            waiter.wait(1, Duration::from_secs(2)).unwrap()
        });
        begin.recv().unwrap();
        assert!(lane.begin_shutdown().unwrap().is_empty());
        assert!(waiting.join().unwrap().is_empty());
        lane.finish_shutdown().unwrap();
    }

    #[test]
    fn repeated_retirement_cannot_grow_the_ready_queue() {
        let lane = NativeLane::new(1).unwrap();
        for value in 1..=128 {
            let operation = Handle::from_raw((value << 32) | 1);
            lane.register(operation).unwrap();
            lane.complete(operation).unwrap();
            lane.retire(operation).unwrap();
        }
        let final_operation = Handle::from_raw((129_u64 << 32) | 1);
        lane.register(final_operation).unwrap();
        lane.complete(final_operation).unwrap();
        assert_eq!(lane.poll(1).unwrap(), vec![final_operation]);
    }

    #[test]
    fn invalid_handles_are_rejected() {
        let lane = NativeLane::new(1).unwrap();
        assert_eq!(lane.register(Handle::INVALID), Err(LaneError::Unknown));
    }

    #[test]
    fn shutdown_names_and_drains_every_operation() {
        let lane = NativeLane::new(2).unwrap();
        lane.register(handle(1)).unwrap();
        lane.register(handle(2)).unwrap();
        let mut cancelled = lane.begin_shutdown().unwrap();
        cancelled.sort_by_key(|handle| handle.raw());
        assert_eq!(cancelled, vec![handle(1), handle(2)]);
        assert_eq!(lane.register(handle(3)), Err(LaneError::Closing));
        assert_eq!(lane.finish_shutdown(), Err(LaneError::Pending(2)));
        for handle in cancelled {
            lane.retire(handle).unwrap();
        }
        lane.finish_shutdown().unwrap();
        assert!(lane.is_shutting_down());
    }

    #[test]
    fn poisoned_state_is_never_reported_as_drained() {
        let lane = std::sync::Arc::new(NativeLane::new(1).unwrap());
        let poison = std::sync::Arc::clone(&lane);
        let _ = std::thread::spawn(move || {
            let _guard = poison.state.lock().unwrap();
            panic!("poison lane state");
        })
        .join();
        assert_eq!(lane.begin_shutdown(), Err(LaneError::Poisoned));
        assert_eq!(lane.pending(), Err(LaneError::Poisoned));
        assert_eq!(lane.finish_shutdown(), Err(LaneError::Poisoned));
    }
}
