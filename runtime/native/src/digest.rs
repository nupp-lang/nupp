//! The public names for the digest and identifier provider, forwarding into the
//! C that implements it.
//!
//! See [`crate::files`] for why the names live on this side while the crate
//! does.

use std::ffi::c_char;

#[cfg(feature = "sha256")]
forward! {
    nuppSha256 = nuppcSha256(bytes: *const u8, length: usize, output: *mut c_char) -> bool;
}

#[cfg(feature = "uuid")]
forward! {
    nuppUuid4 = nuppcUuid4(output: *mut c_char) -> bool;
    nuppUuid7 = nuppcUuid7(output: *mut c_char) -> bool;
}
