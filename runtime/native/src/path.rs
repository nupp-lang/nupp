//! The public names for the path provider, forwarding into the C that implements
//! it.
//!
//! See [`crate::files`] for why the names live on this side while the crate
//! does.

use std::ffi::c_void;

forward! {
    nuppPathJoin = nuppcPathJoin(parts: *const c_void, count: usize) -> *mut c_void;
    nuppPathNormalize = nuppcPathNormalize(data: *const u8, length: usize) -> *mut c_void;
    nuppPathAbsolute = nuppcPathAbsolute(data: *const u8, length: usize) -> *mut c_void;
    nuppPathCanonicalize = nuppcPathCanonicalize(
        data: *const u8, length: usize
    ) -> *mut c_void;
    nuppPathRelative = nuppcPathRelative(
        data: *const u8, length: usize, base: *const u8, base_length: usize
    ) -> *mut c_void;
    nuppPathPart = nuppcPathPart(data: *const u8, length: usize, kind: u32) -> *mut c_void;
    nuppPathWith = nuppcPathWith(
        data: *const u8, length: usize,
        value: *const u8, value_length: usize,
        extension: bool,
    ) -> *mut c_void;
    nuppPathIsAbsolute = nuppcPathIsAbsolute(data: *const u8, length: usize) -> bool;
}
