//! The public names for the HTTP transport, forwarding into the C that
//! implements it.
//!
//! See [`crate::files`] for why the names live on this side while the crate
//! does.

use std::ffi::{c_char, c_void};

forward! {
    nuppHttpClientCreate = nuppcHttpClientCreate(options: *const c_void) -> *mut c_void;
    nuppHttpClientDestroy = nuppcHttpClientDestroy(client: *mut c_void) -> ();
    nuppHttpClientSend = nuppcHttpClientSend(
        client: *mut c_void, request: *const c_void
    ) -> *const c_void;
    nuppHttpClientPending = nuppcHttpClientPending(client: *const c_void) -> usize;
    nuppHttpMonotonicMs = nuppcHttpMonotonicMs() -> f64;

    nuppHttpTransferCancel = nuppcHttpTransferCancel(transfer: *const c_void) -> ();
    nuppHttpTransferDestroy = nuppcHttpTransferDestroy(transfer: *const c_void) -> ();
    nuppHttpTransferOffer = nuppcHttpTransferOffer(
        transfer: *const c_void, data: *const u8, length: usize, finished: bool
    ) -> i32;
    nuppHttpTransferPollHeaders = nuppcHttpTransferPollHeaders(
        transfer: *const c_void, output: *mut c_void
    ) -> u32;
    nuppHttpTransferError = nuppcHttpTransferError(transfer: *const c_void) -> *const c_char;
    nuppHttpTransferTakeBody = nuppcHttpTransferTakeBody(
        transfer: *const c_void
    ) -> *const c_void;

    nuppHttpBodyArm = nuppcHttpBodyArm(body: *const c_void) -> bool;
    nuppHttpBodyPeek = nuppcHttpBodyPeek(
        body: *const c_void, data: *mut *const u8, length: *mut usize, state: *mut u32
    ) -> bool;
    nuppHttpBodyConsume = nuppcHttpBodyConsume(body: *const c_void, count: usize) -> bool;
    nuppHttpBodyError = nuppcHttpBodyError(body: *const c_void) -> *const c_char;
    nuppHttpBodyDestroy = nuppcHttpBodyDestroy(body: *const c_void) -> ();

    nuppHttpClientPoll = nuppcHttpClientPoll(
        client: *mut c_void, output: *mut c_void, capacity: usize, more: *mut bool
    ) -> usize;
    nuppHttpClientWait = nuppcHttpClientWait(
        client: *mut c_void, milliseconds: u64,
        output: *mut c_void, capacity: usize, more: *mut bool
    ) -> usize;
    nuppHttpReadyRelease = nuppcHttpReadyRelease(transfer: *const c_void) -> ();
}
