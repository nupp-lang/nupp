//! Standalone, opaque native-code transport. Nupp owns all execution semantics.
mod platform;

#[cfg(all(test, target_arch = "aarch64"))]
#[path = "../tests/support/abi.rs"]
mod abi;

#[cfg(test)]
#[path = "../tests/support/scratch.rs"]
mod scratch;

use std::fs::File;
use std::io::Read;
use std::path::Path;

const HEADER: usize = 72;
const MAX_REGION: u64 = 64 * 1024 * 1024;
const MAX_TOTAL: u64 = 128 * 1024 * 1024;
const MAX_WORDS: u64 = 1024 * 1024;

#[derive(Debug)]
struct Spec {
    entry: usize,
    code: usize,
    data: usize,
    scratch: usize,
    output: usize,
}

fn header(bytes: &[u8], file_size: u64) -> Result<Spec, String> {
    if bytes.len() != HEADER || &bytes[..8] != b"NUPPCORE" {
        return Err("invalid bundle header".into());
    }
    let field =
        |index: usize| u64::from_le_bytes(bytes[8 + index * 8..16 + index * 8].try_into().unwrap());
    if field(0) != 1 || field(1) != 1 || field(7) != 0 {
        return Err("unsupported bundle version, architecture or reserved field".into());
    }
    let (entry, code, data, scratch, output) = (field(2), field(3), field(4), field(5), field(6));
    if code == 0 || code % 4 != 0 || entry % 4 != 0 || entry >= code {
        return Err("invalid code extent or entry alignment".into());
    }
    if code > MAX_REGION || data > MAX_REGION || scratch > MAX_REGION || output > MAX_WORDS {
        return Err("bundle region exceeds transport limit".into());
    }
    let total = code
        .checked_add(data)
        .and_then(|n| n.checked_add(scratch))
        .ok_or("bundle extent overflow")?;
    if total > MAX_TOTAL || code + data + HEADER as u64 != file_size {
        return Err("bundle extent differs from file or exceeds total limit".into());
    }
    Ok(Spec {
        entry: entry as usize,
        code: code as usize,
        data: data as usize,
        scratch: scratch as usize,
        output: output as usize,
    })
}

fn input(path: &Path) -> Result<Vec<u64>, String> {
    let mut file = File::open(path).map_err(|e| format!("input: {e}"))?;
    let size = file.metadata().map_err(|e| e.to_string())?.len();
    if size % 8 != 0 || size / 8 > MAX_WORDS {
        return Err("input must contain bounded complete words".into());
    }
    let mut bytes = Vec::new();
    file.by_ref()
        .take(size + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    if bytes.len() as u64 != size {
        return Err("input changed while reading".into());
    }
    Ok(bytes
        .chunks_exact(8)
        .map(|word| u64::from_le_bytes(word.try_into().unwrap()))
        .collect())
}

fn execute(bundle: &Path, words: &[u64]) -> Result<Vec<u64>, String> {
    if !platform::supported() {
        return Err("standalone bridge requires little-endian ARM64 macOS or Linux".into());
    }
    let mut file = File::open(bundle).map_err(|e| format!("bundle: {e}"))?;
    let size = file.metadata().map_err(|e| e.to_string())?.len();
    let mut bytes = [0; HEADER];
    file.read_exact(&mut bytes)
        .map_err(|e| format!("bundle header: {e}"))?;
    let spec = header(&bytes, size)?;
    let mut payload = Vec::new();
    file.take((spec.code + spec.data + 1) as u64)
        .read_to_end(&mut payload)
        .map_err(|e| e.to_string())?;
    if payload.len() != spec.code + spec.data {
        return Err("bundle changed while reading".into());
    }
    let mut code = platform::Mapping::new(spec.code)?;
    let mut data = platform::Mapping::new(spec.data)?;
    #[cfg(test)]
    let scratch = scratch::Mapping::new(spec.scratch)?;
    #[cfg(not(test))]
    let scratch = platform::Mapping::new(spec.scratch)?;
    code.copy(&payload[..spec.code]);
    data.copy(&payload[spec.code..]);
    code.executable()?;
    let imports = [
        platform::map_pages as *const () as u64,
        platform::unmap_pages as *const () as u64,
        platform::page_size as *const () as u64,
        platform::environment as *const () as u64,
        platform::format_number as *const () as u64,
        platform::parse_number as *const () as u64,
        platform::write_output as *const () as u64,
        platform::math_function as *const () as u64,
        platform::random_seed as *const () as u64,
    ];
    let packet = [
        1,
        code.address as u64,
        spec.code as u64,
        data.address as u64,
        spec.data as u64,
        scratch.address as u64,
        spec.scratch as u64,
        imports.as_ptr() as u64,
        imports.len() as u64,
        words.as_ptr() as u64,
        words.len() as u64,
        spec.output as u64,
    ];
    let mut output = vec![0u64; spec.output];
    // Trusted Nupp-produced machine code implements this C boundary. It owns
    // all register saves, layout, imports, task/arena state and guest behavior.
    // No pointer from the packet may survive the call or be used concurrently.
    let entry: unsafe extern "C" fn(*const u64, *mut u64) -> u64 =
        unsafe { std::mem::transmute(code.address.add(spec.entry)) };
    #[cfg(all(test, target_arch = "aarch64"))]
    let status = unsafe { abi::invoke(entry, packet.as_ptr(), output.as_mut_ptr()) };
    #[cfg(not(all(test, target_arch = "aarch64")))]
    let status = unsafe { entry(packet.as_ptr(), output.as_mut_ptr()) };
    #[cfg(test)]
    scratch.verify()?;
    if status != 0 {
        return Err(format!("Nupp entry refused with transport status {status}"));
    }
    Ok(output)
}

fn run() -> Result<(), String> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    if args.len() != 3 {
        return Err("usage: nupp-core BUNDLE INPUT OUTPUT".into());
    }
    let words = input(Path::new(&args[1]))?;
    let output = execute(Path::new(&args[0]), &words)?;
    let bytes: Vec<_> = output.into_iter().flat_map(u64::to_le_bytes).collect();
    std::fs::write(&args[2], bytes).map_err(|e| format!("output: {e}"))
}

fn main() {
    if let Err(error) = run() {
        eprintln!("nupp-core: {error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn valid() -> [u8; HEADER] {
        let mut bytes = [0; HEADER];
        bytes[..8].copy_from_slice(b"NUPPCORE");
        for (index, value) in [1u64, 1, 0, 4, 0, 0, 0, 0].into_iter().enumerate() {
            bytes[8 + index * 8..16 + index * 8].copy_from_slice(&value.to_le_bytes());
        }
        bytes
    }

    #[test]
    fn accepts_empty_optional_regions() {
        let spec = header(&valid(), 76).unwrap();
        assert_eq!(
            (spec.code, spec.data, spec.scratch, spec.output),
            (4, 0, 0, 0)
        );
    }

    #[test]
    fn rejects_every_truncated_header_and_wrong_magic() {
        let bytes = valid();
        for end in 0..HEADER {
            assert!(header(&bytes[..end], 76).is_err());
        }
        let mut bytes = bytes;
        bytes[0] = 0;
        assert!(header(&bytes, 76).is_err());
    }

    #[test]
    fn rejects_invalid_fields_before_mapping() {
        for (field, value) in [
            (0, 0),
            (0, 2),
            (1, 0),
            (1, 2),
            (2, 1),
            (2, 4),
            (2, u64::MAX),
            (3, 0),
            (3, 3),
            (3, MAX_REGION + 4),
            (3, u64::MAX),
            (4, MAX_REGION + 1),
            (4, u64::MAX),
            (5, MAX_REGION + 1),
            (5, u64::MAX),
            (6, MAX_WORDS + 1),
            (6, u64::MAX),
            (7, 1),
        ] {
            let mut bytes = valid();
            bytes[8 + field * 8..16 + field * 8].copy_from_slice(&value.to_le_bytes());
            assert!(header(&bytes, 76).is_err(), "field {field}={value}");
        }
        assert!(header(&valid(), 75).is_err());
        assert!(header(&valid(), 77).is_err());
        assert!(header(&valid(), u64::MAX).is_err());
    }

    #[test]
    fn rejects_combined_region_limit() {
        let mut bytes = valid();
        for field in [3, 4, 5] {
            bytes[8 + field * 8..16 + field * 8].copy_from_slice(&MAX_REGION.to_le_bytes());
        }
        assert!(header(&bytes, 2 * MAX_REGION + HEADER as u64).is_err());
    }

    #[test]
    fn mapped_storage_is_zero_and_scoped() {
        let mut region = platform::Mapping::new(31).unwrap();
        assert!(
            unsafe { std::slice::from_raw_parts(region.address, 31) }
                .iter()
                .all(|byte| *byte == 0)
        );
        region.copy(&[1, 2, 3]);
        assert_eq!(
            unsafe { std::slice::from_raw_parts(region.address, 3) },
            &[1, 2, 3]
        );
        assert!(platform::Mapping::new(0).unwrap().address.is_null());
        assert_eq!(platform::map_pages(0), 0);
        assert_eq!(platform::map_pages(u64::MAX), 0);
    }
}
