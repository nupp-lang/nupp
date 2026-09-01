//! Finding the payload appended to a Nupp executable.
//!
//! An unsigned executable ends with a 48-byte trailer. A signed thin
//! little-endian 64-bit Mach-O instead puts that trailer immediately before
//! the zero alignment padding and final code-signature blob.

use nupp_native_platform::trailer_digest;
use std::fmt;
use std::path::{Path, PathBuf};

const MAGIC: &[u8; 8] = b"NUPPLOAD";
const TRAILER_LENGTH: usize = 48;
const FORMAT_VERSION: u32 = 1;
const PAYLOAD_FLAG_BYTECODE: u32 = 1;
const PAYLOAD_FLAGS_KNOWN: u32 = PAYLOAD_FLAG_BYTECODE;
const MACH_HEADER_LENGTH: usize = 32;
const MACH_O_64_LE_MAGIC: &[u8; 4] = &[0xcf, 0xfa, 0xed, 0xfe];
const LC_CODE_SIGNATURE: u32 = 0x1d;
const MAX_SIGNATURE_PADDING: usize = 4095;

/// A checked source or LuaJIT-bytecode payload owned independently of its
/// surrounding executable.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Payload {
    bytes: Vec<u8>,
    bytecode: bool,
}

impl Payload {
    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }

    pub fn is_bytecode(&self) -> bool {
        self.bytecode
    }
}

#[derive(Debug)]
pub enum Error {
    Unreadable {
        path: PathBuf,
        source: std::io::Error,
    },
    UnknownVersion(u32),
    UnknownFlags(u32),
    InvalidBounds {
        offset: u64,
        length: u64,
        size: u64,
    },
    DigestMismatch,
}

impl fmt::Display for Error {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Unreadable { path, source } => {
                write!(
                    out,
                    "cannot read this executable {}: {source}",
                    path.display()
                )
            }
            Self::UnknownVersion(found) => write!(
                out,
                "this executable carries a payload in format version {found}, and this host \
                 only knows version {FORMAT_VERSION}"
            ),
            Self::UnknownFlags(flags) => write!(
                out,
                "the payload's trailer sets unknown flags 0x{flags:08x}, so it was written \
                 by something newer than this host"
            ),
            Self::InvalidBounds {
                offset,
                length,
                size,
            } => write!(
                out,
                "the payload claims {length} bytes at {offset} but the file is only {size} \
                 bytes; it was probably truncated in transit"
            ),
            Self::DigestMismatch => write!(
                out,
                "the payload does not match the digest recorded beside it; it was probably \
                 damaged in transit"
            ),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Unreadable { source, .. } => Some(source),
            _ => None,
        }
    }
}

/// Reads and checks the payload carried by `executable`.
///
/// `None` means neither the unsigned nor signed trailer position carries the
/// format magic. Once the magic is present, damage is an error rather than a
/// reason to fall back to interpreting another file.
pub fn read(executable: &Path) -> Result<Option<Payload>, Error> {
    let bytes = std::fs::read(executable).map_err(|source| Error::Unreadable {
        path: executable.to_owned(),
        source,
    })?;
    parse(&bytes).map(|payload| {
        payload.map(|payload| Payload {
            bytes: payload.bytes.to_vec(),
            bytecode: payload.bytecode,
        })
    })
}

struct PayloadSlice<'a> {
    bytes: &'a [u8],
    bytecode: bool,
}

fn parse(bytes: &[u8]) -> Result<Option<PayloadSlice<'_>>, Error> {
    if bytes.len() < TRAILER_LENGTH {
        return Ok(None);
    }

    let unsigned_start = bytes.len() - TRAILER_LENGTH;
    let trailer_start = if bytes.get(unsigned_start..unsigned_start + MAGIC.len()) == Some(MAGIC) {
        unsigned_start
    } else if let Some(start) = signed_trailer_start(bytes) {
        start
    } else {
        return Ok(None);
    };
    let trailer = &bytes[trailer_start..trailer_start + TRAILER_LENGTH];

    let version = read_u32(trailer, 8).expect("fixed-size trailer contains its version");
    if version != FORMAT_VERSION {
        return Err(Error::UnknownVersion(version));
    }
    let flags = read_u32(trailer, 12).expect("fixed-size trailer contains its flags");
    if flags & !PAYLOAD_FLAGS_KNOWN != 0 {
        return Err(Error::UnknownFlags(flags));
    }

    let offset = read_u64(trailer, 16).expect("fixed-size trailer contains its offset");
    let length = read_u64(trailer, 24).expect("fixed-size trailer contains its length");
    let size = u64::try_from(bytes.len()).expect("an addressable slice length fits in u64");
    let trailer_at = u64::try_from(trailer_start).expect("an addressable offset fits in u64");
    let Some(end) = offset.checked_add(length) else {
        return Err(Error::InvalidBounds {
            offset,
            length,
            size,
        });
    };
    if offset > size || end > trailer_at {
        return Err(Error::InvalidBounds {
            offset,
            length,
            size,
        });
    }

    let start = usize::try_from(offset).expect("checked payload offset fits in usize");
    let end = usize::try_from(end).expect("checked payload end fits in usize");
    let payload = &bytes[start..end];
    if trailer_digest(payload) != trailer[32..40] {
        return Err(Error::DigestMismatch);
    }

    Ok(Some(PayloadSlice {
        bytes: payload,
        bytecode: flags & PAYLOAD_FLAG_BYTECODE != 0,
    }))
}

fn signed_trailer_start(bytes: &[u8]) -> Option<usize> {
    let signature_at = mach_o_signature_offset(bytes)?;
    let maximum_padding = signature_at.min(MAX_SIGNATURE_PADDING);
    for padding in 0..=maximum_padding {
        let trailer_end = signature_at.checked_sub(padding)?;
        let trailer_start = trailer_end.checked_sub(TRAILER_LENGTH)?;
        if bytes.get(trailer_start..trailer_start + MAGIC.len()) == Some(MAGIC)
            && bytes[trailer_end..signature_at]
                .iter()
                .all(|byte| *byte == 0)
        {
            return Some(trailer_start);
        }
    }
    None
}

fn mach_o_signature_offset(bytes: &[u8]) -> Option<usize> {
    if bytes.len() < MACH_HEADER_LENGTH || bytes.get(..4)? != MACH_O_64_LE_MAGIC {
        return None;
    }
    let commands = usize::try_from(read_u32(bytes, 16)?).ok()?;
    let command_bytes = usize::try_from(read_u32(bytes, 20)?).ok()?;
    let command_end = MACH_HEADER_LENGTH.checked_add(command_bytes)?;
    if command_end > bytes.len() {
        return None;
    }

    let mut cursor = MACH_HEADER_LENGTH;
    for _ in 0..commands {
        if cursor.checked_add(8)? > command_end {
            return None;
        }
        let command = read_u32(bytes, cursor)?;
        let command_size = usize::try_from(read_u32(bytes, cursor + 4)?).ok()?;
        let next = cursor.checked_add(command_size)?;
        if command_size < 8 || next > command_end {
            return None;
        }
        if command == LC_CODE_SIGNATURE {
            if command_size < 16 {
                return None;
            }
            let offset = usize::try_from(read_u32(bytes, cursor + 8)?).ok()?;
            let size = usize::try_from(read_u32(bytes, cursor + 12)?).ok()?;
            return (offset.checked_add(size)? == bytes.len()).then_some(offset);
        }
        cursor = next;
    }
    None
}

fn read_u32(bytes: &[u8], offset: usize) -> Option<u32> {
    Some(u32::from_le_bytes(
        bytes.get(offset..offset.checked_add(4)?)?.try_into().ok()?,
    ))
}

fn read_u64(bytes: &[u8], offset: usize) -> Option<u64> {
    Some(u64::from_le_bytes(
        bytes.get(offset..offset.checked_add(8)?)?.try_into().ok()?,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};

    static TEMPORARY: AtomicU32 = AtomicU32::new(0);

    struct TempFile(PathBuf);

    impl TempFile {
        fn containing(bytes: &[u8]) -> Self {
            let mut path = std::env::temp_dir();
            path.push(format!(
                "nupp-rust-payload-{}-{}",
                std::process::id(),
                TEMPORARY.fetch_add(1, Ordering::Relaxed)
            ));
            std::fs::write(&path, bytes).expect("write payload fixture");
            Self(path)
        }
    }

    impl Drop for TempFile {
        fn drop(&mut self) {
            let _ = std::fs::remove_file(&self.0);
        }
    }

    fn stamped(stub: &[u8], payload: &[u8], flags: u32) -> Vec<u8> {
        let mut bytes = stub.to_vec();
        let offset = bytes.len() as u64;
        bytes.extend_from_slice(payload);
        bytes.extend_from_slice(MAGIC);
        bytes.extend_from_slice(&FORMAT_VERSION.to_le_bytes());
        bytes.extend_from_slice(&flags.to_le_bytes());
        bytes.extend_from_slice(&offset.to_le_bytes());
        bytes.extend_from_slice(&(payload.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&trailer_digest(payload));
        bytes.extend_from_slice(&(TRAILER_LENGTH as u64).to_le_bytes());
        bytes
    }

    fn signed(payload: &[u8], padding: &[u8], signature: &[u8]) -> Vec<u8> {
        let mut header = vec![0; 48];
        header[..4].copy_from_slice(MACH_O_64_LE_MAGIC);
        header[16..20].copy_from_slice(&1u32.to_le_bytes());
        header[20..24].copy_from_slice(&16u32.to_le_bytes());
        header[32..36].copy_from_slice(&LC_CODE_SIGNATURE.to_le_bytes());
        header[36..40].copy_from_slice(&16u32.to_le_bytes());
        let mut bytes = stamped(&header, payload, 0);
        bytes.extend_from_slice(padding);
        let signature_at = bytes.len() as u32;
        bytes[40..44].copy_from_slice(&signature_at.to_le_bytes());
        bytes[44..48].copy_from_slice(&(signature.len() as u32).to_le_bytes());
        bytes.extend_from_slice(signature);
        bytes
    }

    fn trailer_start(bytes: &[u8]) -> usize {
        bytes.len() - TRAILER_LENGTH
    }

    #[test]
    fn plain_and_short_files_have_no_payload() {
        assert!(parse(b"tiny").unwrap().is_none());
        assert!(parse(&vec![b'x'; TRAILER_LENGTH + 20]).unwrap().is_none());
    }

    #[test]
    fn source_and_bytecode_payloads_are_accepted() {
        let source = stamped(b"STUB", b"return 42", 0);
        let source = parse(&source).unwrap().unwrap();
        assert_eq!(source.bytes, b"return 42");
        assert!(!source.bytecode);

        let bytecode = stamped(b"STUB", b"\x1bLJ\x02\0compiled", PAYLOAD_FLAG_BYTECODE);
        let bytecode = parse(&bytecode).unwrap().unwrap();
        assert_eq!(bytecode.bytes, b"\x1bLJ\x02\0compiled");
        assert!(bytecode.bytecode);
    }

    #[test]
    fn file_reader_returns_only_an_owned_payload() {
        let bytes = stamped(b"a potentially large executable", b"return 'owned'", 0);
        let file = TempFile::containing(&bytes);
        let payload = read(&file.0).unwrap().unwrap();
        std::fs::write(&file.0, b"replaced").expect("replace fixture");
        assert_eq!(payload.bytes(), b"return 'owned'");
        assert!(!payload.is_bytecode());
    }

    #[test]
    fn empty_and_embedded_nul_payloads_are_not_sentinels() {
        let empty = stamped(b"STUB", b"", 0);
        assert_eq!(parse(&empty).unwrap().unwrap().bytes, b"");

        let binary = b"left\0middle\0right";
        let nul = stamped(b"STUB", binary, 0);
        assert_eq!(parse(&nul).unwrap().unwrap().bytes, binary);
    }

    #[test]
    fn future_version_and_unknown_flags_are_refused() {
        let mut version = stamped(b"STUB", b"return 1", 0);
        let at = trailer_start(&version);
        version[at + 8..at + 12].copy_from_slice(&99u32.to_le_bytes());
        assert!(matches!(parse(&version), Err(Error::UnknownVersion(99))));

        let mut flags = stamped(b"STUB", b"return 1", 0);
        let at = trailer_start(&flags);
        flags[at + 12..at + 16].copy_from_slice(&0x8000_0001u32.to_le_bytes());
        assert!(matches!(
            parse(&flags),
            Err(Error::UnknownFlags(0x8000_0001))
        ));
    }

    #[test]
    fn every_invalid_payload_bound_is_refused() {
        for (offset, length) in [(u64::MAX, 1), (4, u64::MAX), (4, 9_000), (4, 64)] {
            let mut bytes = stamped(b"STUB", b"return 1", 0);
            let at = trailer_start(&bytes);
            bytes[at + 16..at + 24].copy_from_slice(&offset.to_le_bytes());
            bytes[at + 24..at + 32].copy_from_slice(&length.to_le_bytes());
            assert!(matches!(parse(&bytes), Err(Error::InvalidBounds { .. })));
        }
    }

    #[test]
    fn digest_mismatch_is_refused() {
        let mut bytes = stamped(b"STUB", b"return 1", 0);
        bytes[4] ^= 1;
        assert!(matches!(parse(&bytes), Err(Error::DigestMismatch)));
    }

    #[test]
    fn signed_mach_o_finds_the_trailer_before_zero_padding_and_signature() {
        let bytes = signed(b"return 'signed'", &[0; 17], b"SIGNATURE");
        assert_eq!(parse(&bytes).unwrap().unwrap().bytes, b"return 'signed'");
    }

    #[test]
    fn signed_mach_o_requires_clean_padding_and_a_final_signature() {
        let dirty = signed(b"return 1", &[0, 0, 1, 0], b"SIGN");
        assert!(parse(&dirty).unwrap().is_none());

        let mut misplaced = signed(b"return 1", &[0; 3], b"SIGN");
        misplaced.extend_from_slice(b"AFTER");
        assert!(parse(&misplaced).unwrap().is_none());
    }

    #[test]
    fn malformed_mach_o_load_commands_are_not_sliced_or_guessed() {
        let valid = signed(b"return 1", &[0; 3], b"SIGN");
        let cases = [(20, u32::MAX), (36, 7), (36, u32::MAX), (36, 8)];
        for (at, value) in cases {
            let mut malformed = valid.clone();
            malformed[at..at + 4].copy_from_slice(&value.to_le_bytes());
            assert!(parse(&malformed).unwrap().is_none());
        }
    }
}
