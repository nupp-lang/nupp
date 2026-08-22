//! The public names for the process provider, forwarding into the C that
//! implements it.
//!
//! See [`crate::files`] for why the names live on this side while the crate
//! does.

use std::ffi::c_void;

forward! {
    nuppProcessMonotonicMs = nuppcProcessMonotonicMs() -> f64;

    nuppProcessSpawnBegin = nuppcProcessSpawnBegin() -> *mut c_void;
    nuppProcessSpawnArg = nuppcProcessSpawnArg(
        request: *mut c_void, text: *const u8, length: usize
    ) -> bool;
    nuppProcessSpawnEnv = nuppcProcessSpawnEnv(
        request: *mut c_void, text: *const u8, length: usize
    ) -> bool;
    nuppProcessSpawnClearEnv = nuppcProcessSpawnClearEnv(
        request: *mut c_void, clear: bool
    ) -> bool;
    nuppProcessSpawnCwd = nuppcProcessSpawnCwd(
        request: *mut c_void, text: *const u8, length: usize
    ) -> bool;
    nuppProcessSpawnStdio = nuppcProcessSpawnStdio(
        request: *mut c_void, which: u8, mode: u8
    ) -> bool;
    nuppProcessSpawnCancel = nuppcProcessSpawnCancel(request: *mut c_void) -> ();
    nuppProcessSpawnRun = nuppcProcessSpawnRun(request: *mut c_void) -> *mut c_void;

    nuppProcessTakeStream = nuppcProcessTakeStream(
        child: *mut c_void, which: u8
    ) -> *mut c_void;
    nuppProcessTryRead = nuppcProcessTryRead(
        stream: *mut c_void, buffer: *mut u8, limit: usize
    ) -> isize;
    nuppProcessTryWrite = nuppcProcessTryWrite(
        stream: *mut c_void, buffer: *const u8, length: usize
    ) -> isize;
    nuppProcessCloseStream = nuppcProcessCloseStream(stream: *mut c_void) -> u8;
    nuppProcessStreamDestroy = nuppcProcessStreamDestroy(stream: *mut c_void) -> ();

    nuppProcessPollExit = nuppcProcessPollExit(
        child: *mut c_void, code: *mut i32, killed: *mut bool
    ) -> i32;
    nuppProcessId = nuppcProcessId(child: *mut c_void) -> u32;
    nuppProcessKill = nuppcProcessKill(child: *mut c_void, force: bool) -> bool;
    nuppProcessReap = nuppcProcessReap(child: *mut c_void) -> u8;
    nuppProcessUncollectedTotal = nuppcProcessUncollectedTotal() -> usize;
    nuppProcessDestroy = nuppcProcessDestroy(child: *mut c_void) -> ();

    nuppProcessWaitReady = nuppcProcessWaitReady(
        readable: *const *mut c_void, readable_count: usize,
        writable: *const *mut c_void, writable_count: usize,
        timeout_ms: i32,
    ) -> i32;
}
