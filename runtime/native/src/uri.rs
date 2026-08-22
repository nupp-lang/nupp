//! The public names for the URI provider, forwarding into the C that implements
//! it.
//!
//! See [`crate::files`] for why the names live on this side while the crate
//! does.

use std::ffi::c_void;

forward! {
    nuppUriParse = nuppcUriParse(data: *const u8, length: usize) -> *mut c_void;
    nuppUriPart = nuppcUriPart(
        uri: *const c_void, kind: u32, length: *mut usize
    ) -> *const u8;
    nuppUriPort = nuppcUriPort(uri: *const c_void, port: *mut u16) -> bool;
    nuppUriWithText = nuppcUriWithText(
        uri: *const c_void, kind: u32, value: *const u8, length: usize, present: bool
    ) -> *mut c_void;
    nuppUriWithPort = nuppcUriWithPort(uri: *const c_void, port: i32) -> *mut c_void;
    nuppUriConcatPath = nuppcUriConcatPath(
        uri: *const c_void, suffix: *const u8, length: usize
    ) -> *mut c_void;
    nuppUriResolve = nuppcUriResolve(
        uri: *const c_void, reference: *const u8, length: usize
    ) -> *mut c_void;
    nuppUriWithEndpoint = nuppcUriWithEndpoint(
        uri: *const c_void, endpoint: *const c_void
    ) -> *mut c_void;
    nuppUriDestroy = nuppcUriDestroy(uri: *mut c_void) -> ();
}
