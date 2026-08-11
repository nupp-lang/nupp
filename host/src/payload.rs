//! Finding the payload appended to this executable.
//!
//! The trailer is the last 48 bytes of the file and says where the payload
//! starts, how long it is, and what its digest begins with. A file with no
//! magic there has no payload; a file with a version this stub does not know
//! is refused rather than read hopefully.

use std::fmt;
use std::path::Path;

pub const MAGIC: &[u8; 8] = b"NUPPLOAD";
pub const TRAILER_LENGTH: u64 = 48;
pub const FORMAT_VERSION: u32 = 1;

#[derive(Debug)]
pub enum Error {
    Unreadable(String),
    UnknownVersion(u32),
    Truncated { offset: u64, length: u64, size: u64 },
    Corrupt,
    Reserved,
}

impl fmt::Display for Error {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Unreadable(why) => write!(out, "cannot read this executable: {why}"),
            Error::UnknownVersion(found) => write!(
                out,
                "this executable carries a payload in format version {found}, \
                 and this host only knows version {FORMAT_VERSION}"
            ),
            Error::Truncated { offset, length, size } => write!(
                out,
                "the payload claims {length} bytes at {offset} but the file is \
                 only {size} bytes; it was probably truncated in transit"
            ),
            Error::Corrupt => write!(
                out,
                "the payload does not match the digest recorded beside it; it \
                 was probably damaged in transit"
            ),
            Error::Reserved => write!(
                out,
                "the payload's trailer sets bytes this version reserves, so it \
                 was written by something newer than this host"
            ),
        }
    }
}

fn u32_at(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap())
}

fn u64_at(bytes: &[u8], offset: usize) -> u64 {
    u64::from_le_bytes(bytes[offset..offset + 8].try_into().unwrap())
}

/// The payload this executable carries, or `None` when it carries none.
pub fn read(exe: &Path) -> Result<Option<Vec<u8>>, Error> {
    let bytes = std::fs::read(exe).map_err(|e| Error::Unreadable(e.to_string()))?;
    let size = bytes.len() as u64;
    if size < TRAILER_LENGTH {
        return Ok(None);
    }

    let trailer = &bytes[(size - TRAILER_LENGTH) as usize..];
    if &trailer[..8] != MAGIC {
        return Ok(None);
    }

    let version = u32_at(trailer, 8);
    if version != FORMAT_VERSION {
        return Err(Error::UnknownVersion(version));
    }
    if u32_at(trailer, 12) != 0 {
        return Err(Error::Reserved);
    }

    let offset = u64_at(trailer, 16);
    let length = u64_at(trailer, 24);
    let recorded = &trailer[32..40];

    // Checked before slicing, so a damaged file is a message rather than a
    // panic in a binary somebody else is running.
    if offset > size || length > size - offset || offset + length > size - TRAILER_LENGTH {
        return Err(Error::Truncated { offset, length, size });
    }

    let payload = bytes[offset as usize..(offset + length) as usize].to_vec();
    if crate::digest_prefix(&payload) != recorded {
        return Err(Error::Corrupt);
    }
    Ok(Some(payload))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    /// A stub-shaped file with `payload` stamped into it the way the emitter
    /// does, so these tests exercise the format rather than a mock of it.
    fn stamped(stub: &[u8], payload: &[u8]) -> Vec<u8> {
        let mut bytes = stub.to_vec();
        let offset = stub.len() as u64;
        bytes.extend_from_slice(payload);
        bytes.extend_from_slice(MAGIC);
        bytes.extend_from_slice(&FORMAT_VERSION.to_le_bytes());
        bytes.extend_from_slice(&0u32.to_le_bytes());
        bytes.extend_from_slice(&offset.to_le_bytes());
        bytes.extend_from_slice(&(payload.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&crate::digest_prefix(payload));
        bytes.extend_from_slice(&TRAILER_LENGTH.to_le_bytes());
        bytes
    }

    fn written(bytes: &[u8]) -> tempfile_lite::Temp {
        let temp = tempfile_lite::Temp::new();
        let mut file = std::fs::File::create(temp.path()).unwrap();
        file.write_all(bytes).unwrap();
        temp
    }

    #[test]
    fn reads_back_what_was_stamped() {
        let file = written(&stamped(b"STUBSTUBSTUB", b"print('hi')"));
        let found = read(file.path()).unwrap();
        assert_eq!(found.as_deref(), Some(&b"print('hi')"[..]));
    }

    #[test]
    fn an_empty_payload_is_still_a_payload() {
        // A program with nothing in it is a program, and answering None here
        // would silently turn it into an interpreter.
        let file = written(&stamped(b"STUB", b""));
        assert_eq!(read(file.path()).unwrap().as_deref(), Some(&b""[..]));
    }

    #[test]
    fn a_plain_executable_has_no_payload() {
        let file = written(b"an ordinary binary with no trailer at all");
        assert!(read(file.path()).unwrap().is_none());
    }

    #[test]
    fn a_file_shorter_than_a_trailer_has_no_payload() {
        let file = written(b"tiny");
        assert!(read(file.path()).unwrap().is_none());
    }

    #[test]
    fn a_future_version_is_refused_rather_than_guessed_at() {
        let mut bytes = stamped(b"STUB", b"print(1)");
        let version_at = bytes.len() - TRAILER_LENGTH as usize + 8;
        bytes[version_at..version_at + 4].copy_from_slice(&99u32.to_le_bytes());
        let file = written(&bytes);
        assert!(matches!(read(file.path()), Err(Error::UnknownVersion(99))));
    }

    #[test]
    fn reserved_bytes_in_use_mean_something_newer_wrote_this() {
        let mut bytes = stamped(b"STUB", b"print(1)");
        let reserved_at = bytes.len() - TRAILER_LENGTH as usize + 12;
        bytes[reserved_at..reserved_at + 4].copy_from_slice(&1u32.to_le_bytes());
        let file = written(&bytes);
        assert!(matches!(read(file.path()), Err(Error::Reserved)));
    }

    #[test]
    fn a_truncated_payload_is_reported_not_panicked_on() {
        let mut bytes = stamped(b"STUB", b"print(1)");
        let length_at = bytes.len() - TRAILER_LENGTH as usize + 24;
        bytes[length_at..length_at + 8].copy_from_slice(&9_000u64.to_le_bytes());
        let file = written(&bytes);
        assert!(matches!(read(file.path()), Err(Error::Truncated { .. })));
    }

    #[test]
    fn a_damaged_payload_does_not_run() {
        let mut bytes = stamped(b"STUB", b"print(1)");
        bytes[4] = b'!'; // inside the payload, which starts at 4
        let file = written(&bytes);
        assert!(matches!(read(file.path()), Err(Error::Corrupt)));
    }

    /// A temporary file that removes itself, so the tests need no dependency
    /// for the one thing they need from one.
    mod tempfile_lite {
        use std::path::{Path, PathBuf};
        use std::sync::atomic::{AtomicU32, Ordering};

        static COUNTER: AtomicU32 = AtomicU32::new(0);

        pub struct Temp(PathBuf);

        impl Temp {
            pub fn new() -> Self {
                let unique = COUNTER.fetch_add(1, Ordering::SeqCst);
                let mut path = std::env::temp_dir();
                path.push(format!("nupp-payload-{}-{}", std::process::id(), unique));
                Temp(path)
            }

            pub fn path(&self) -> &Path {
                &self.0
            }
        }

        impl Drop for Temp {
            fn drop(&mut self) {
                let _ = std::fs::remove_file(&self.0);
            }
        }
    }
}
