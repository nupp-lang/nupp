//! A program binary: this runtime with a program's image appended.
//!
//! The container is the one `docs/reference/distribution.md` specifies for
//! every Nupp executable: the payload, then a 48-byte trailer at the end of an
//! unsigned file, or before the zero padding and code signature of a signed
//! thin 64-bit Mach-O. Bit 1 of the trailer's flags says the payload is a VM
//! program: the entry module's name on the first line, the image text after it.
//!
//! Only the format-defined boundaries are read, never the whole executable, so
//! a runtime with nothing appended answers in a few small reads.

use nupp_native_platform::trailer_digest;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

const MAGIC: &[u8; 8] = b"NUPPLOAD";
const TRAILER_LENGTH: u64 = 48;
const FORMAT_VERSION: u32 = 1;
/// The payload is a LuaJIT bytecode chunk: a LuaJIT host's, never this one's.
const FLAG_BYTECODE: u32 = 1;
/// The payload is a VM program: entry module, newline, image text.
pub const FLAG_VM_PROGRAM: u32 = 2;
const MACH_HEADER_LENGTH: u64 = 32;
const MACH_O_64_LE_MAGIC: [u8; 4] = [0xcf, 0xfa, 0xed, 0xfe];
const LC_CODE_SIGNATURE: u32 = 0x1d;
const MAX_SIGNATURE_PADDING: u64 = 4095;
/// Load commands larger than this are not a Mach-O any linker writes.
const MAX_COMMAND_BYTES: u64 = 1 << 24;

/// The program a stamped runtime carries.
pub struct Program {
    pub entry: String,
    pub image: String,
}

/// The program appended to `executable`, `None` when nothing is appended.
/// Once the magic is present, damage is an error, never a reason to run as a
/// plain runtime.
pub fn read(executable: &Path) -> Result<Option<Program>, String> {
    let mut file = File::open(executable).map_err(|e| format!("cannot read this executable {}: {e}", executable.display()))?;
    let size = file.metadata().map_err(|e| e.to_string())?.len();
    let Some(trailer_at) = trailer_start(&mut file, size).map_err(|e| e.to_string())? else { return Ok(None) };
    let mut trailer = [0u8; TRAILER_LENGTH as usize];
    read_at(&mut file, trailer_at, &mut trailer).map_err(|e| e.to_string())?;
    let version = u32_at(&trailer, 8);
    if version != FORMAT_VERSION {
        return Err(format!("this executable carries a payload in format version {version}, and this runtime only knows version {FORMAT_VERSION}"));
    }
    let flags = u32_at(&trailer, 12);
    if flags & !(FLAG_BYTECODE | FLAG_VM_PROGRAM) != 0 {
        return Err(format!("the payload's trailer sets unknown flags 0x{flags:08x}, so it was written by something newer than this runtime"));
    }
    if flags & FLAG_VM_PROGRAM == 0 {
        return Err("this executable carries a LuaJIT payload, which this runtime does not run".into());
    }
    let (offset, length) = (u64_at(&trailer, 16), u64_at(&trailer, 24));
    if offset.checked_add(length).is_none_or(|end| end > trailer_at) {
        return Err(format!("the payload claims {length} bytes at {offset} but the file is only {size} bytes; it was probably truncated in transit"));
    }
    let mut payload = vec![0u8; length as usize];
    read_at(&mut file, offset, &mut payload).map_err(|e| e.to_string())?;
    if trailer_digest(&payload) != trailer[32..40] {
        return Err("the payload does not match the digest recorded beside it; it was probably damaged in transit".into());
    }
    let text = String::from_utf8(payload).map_err(|_| "the program image is not UTF-8 text".to_string())?;
    let (entry, image) = text.split_once('\n').ok_or("the program payload names no entry module")?;
    if entry.is_empty() {
        return Err("the program payload names no entry module".into());
    }
    Ok(Some(Program { entry: entry.to_string(), image: image.to_string() }))
}

fn trailer_start(file: &mut File, size: u64) -> std::io::Result<Option<u64>> {
    if size < TRAILER_LENGTH {
        return Ok(None);
    }
    let mut magic = [0u8; 8];
    read_at(file, size - TRAILER_LENGTH, &mut magic)?;
    if &magic == MAGIC {
        return Ok(Some(size - TRAILER_LENGTH));
    }
    let Some(signature_at) = mach_o_signature_offset(file, size)? else { return Ok(None) };
    // The trailer ends where the zero padding before the signature begins.
    let window_start = signature_at.saturating_sub(MAX_SIGNATURE_PADDING + TRAILER_LENGTH);
    let mut window = vec![0u8; (signature_at - window_start) as usize];
    read_at(file, window_start, &mut window)?;
    let n = window.len();
    for padding in 0..=(MAX_SIGNATURE_PADDING as usize).min(n) {
        if padding > 0 && window[n - padding] != 0 {
            break;
        }
        let Some(start) = (n - padding).checked_sub(TRAILER_LENGTH as usize) else { break };
        if &window[start..start + 8] == MAGIC {
            return Ok(Some(window_start + start as u64));
        }
    }
    Ok(None)
}

fn mach_o_signature_offset(file: &mut File, size: u64) -> std::io::Result<Option<u64>> {
    if size < MACH_HEADER_LENGTH {
        return Ok(None);
    }
    let mut header = [0u8; MACH_HEADER_LENGTH as usize];
    read_at(file, 0, &mut header)?;
    if header[..4] != MACH_O_64_LE_MAGIC {
        return Ok(None);
    }
    let (commands, command_bytes) = (u32_at(&header, 16), u32_at(&header, 20) as u64);
    if command_bytes > MAX_COMMAND_BYTES || MACH_HEADER_LENGTH + command_bytes > size {
        return Ok(None);
    }
    let mut table = vec![0u8; command_bytes as usize];
    read_at(file, MACH_HEADER_LENGTH, &mut table)?;
    let mut cursor = 0usize;
    for _ in 0..commands {
        if cursor + 8 > table.len() {
            return Ok(None);
        }
        let (command, length) = (u32_at(&table, cursor), u32_at(&table, cursor + 4) as usize);
        if length < 8 || cursor + length > table.len() {
            return Ok(None);
        }
        if command == LC_CODE_SIGNATURE {
            if length < 16 {
                return Ok(None);
            }
            let (offset, blob) = (u32_at(&table, cursor + 8) as u64, u32_at(&table, cursor + 12) as u64);
            return Ok((offset + blob == size).then_some(offset));
        }
        cursor += length;
    }
    Ok(None)
}

fn read_at(file: &mut File, offset: u64, buffer: &mut [u8]) -> std::io::Result<()> {
    file.seek(SeekFrom::Start(offset))?;
    file.read_exact(buffer)
}

fn u32_at(bytes: &[u8], at: usize) -> u32 { u32::from_le_bytes(bytes[at..at + 4].try_into().unwrap()) }
fn u64_at(bytes: &[u8], at: usize) -> u64 { u64::from_le_bytes(bytes[at..at + 8].try_into().unwrap()) }

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};

    static TEMPORARY: AtomicU32 = AtomicU32::new(0);

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
        bytes.extend_from_slice(&TRAILER_LENGTH.to_le_bytes());
        bytes
    }

    fn signed(payload: &[u8], padding: usize, signature: &[u8]) -> Vec<u8> {
        let mut header = vec![0; 48];
        header[..4].copy_from_slice(&MACH_O_64_LE_MAGIC);
        header[16..20].copy_from_slice(&1u32.to_le_bytes());
        header[20..24].copy_from_slice(&16u32.to_le_bytes());
        header[32..36].copy_from_slice(&LC_CODE_SIGNATURE.to_le_bytes());
        header[36..40].copy_from_slice(&16u32.to_le_bytes());
        let mut bytes = stamped(&header, payload, FLAG_VM_PROGRAM);
        bytes.extend(std::iter::repeat_n(0u8, padding));
        let signature_at = bytes.len() as u32;
        bytes[40..44].copy_from_slice(&signature_at.to_le_bytes());
        bytes[44..48].copy_from_slice(&(signature.len() as u32).to_le_bytes());
        bytes.extend_from_slice(signature);
        bytes
    }

    fn parse(bytes: &[u8]) -> Result<Option<Program>, String> {
        let path = std::env::temp_dir().join(format!("nupp-vm-payload-{}-{}", std::process::id(), TEMPORARY.fetch_add(1, Ordering::Relaxed)));
        std::fs::write(&path, bytes).unwrap();
        let result = read(&path);
        std::fs::remove_file(&path).unwrap();
        result
    }

    #[test]
    fn a_plain_runtime_carries_no_program() {
        assert!(parse(b"tiny").unwrap().is_none());
        assert!(parse(&vec![b'x'; 200]).unwrap().is_none());
    }

    #[test]
    fn an_appended_program_names_its_entry_and_image() {
        let program = parse(&stamped(b"RUNTIME", b"app.main\nmodule app.main 0 x\n", FLAG_VM_PROGRAM)).unwrap().unwrap();
        assert_eq!(program.entry, "app.main");
        assert_eq!(program.image, "module app.main 0 x\n");
    }

    #[test]
    fn a_signed_runtime_finds_its_trailer_before_the_padding() {
        for padding in [0, 3, 17, 4095] {
            let program = parse(&signed(b"main\nimage", padding, b"SIGNATURE")).unwrap().unwrap();
            assert_eq!((program.entry.as_str(), program.image.as_str()), ("main", "image"));
        }
    }

    #[test]
    fn damage_and_foreign_payloads_are_refused() {
        let mut damaged = stamped(b"RUNTIME", b"main\nimage", FLAG_VM_PROGRAM);
        damaged[8] ^= 1;
        assert!(parse(&damaged).unwrap_err().contains("damaged"));
        assert!(parse(&stamped(b"RUNTIME", b"return 1", 0)).unwrap_err().contains("LuaJIT"));
        assert!(parse(&stamped(b"RUNTIME", b"main\nimage", 0x8000_0002)).unwrap_err().contains("unknown flags"));
        assert!(parse(&stamped(b"RUNTIME", b"\nimage", FLAG_VM_PROGRAM)).unwrap_err().contains("no entry"));
        let mut truncated = stamped(b"RUNTIME", b"main\nimage", FLAG_VM_PROGRAM);
        let at = truncated.len() - 48;
        truncated[at + 24..at + 32].copy_from_slice(&9000u64.to_le_bytes());
        assert!(parse(&truncated).unwrap_err().contains("truncated"));
    }
}
