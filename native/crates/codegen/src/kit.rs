//! Link kits travel as gzip-compressed POSIX tar archives. An archive is
//! fetched over HTTPS or read from disk, checked against the size and SHA-256
//! the caller's catalog holds, and unpacked into a directory the caller then
//! moves into place. Nothing here decides where kits live or which one a
//! build needs.

use std::fs;
use std::io::Read;
use std::path::{Component, Path, PathBuf};

/// The largest archive this will fetch or unpack, compressed or not.
const LIMIT: u64 = 1 << 30;

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Checks `bytes` against the catalog's size and lowercase SHA-256.
pub fn verify(bytes: &[u8], size: u64, sha256: &str) -> Result<(), String> {
    if bytes.len() as u64 != size {
        return Err(format!("the kit archive is {} bytes; its catalog record says {size}", bytes.len()));
    }
    let digest = hex(ring::digest::digest(&ring::digest::SHA256, bytes).as_ref());
    if digest != sha256 {
        return Err(format!("the kit archive's SHA-256 is {digest}; its catalog record says {sha256}"));
    }
    Ok(())
}

/// Fetches `url` into `path`, refusing a body larger than `size` or one that
/// does not match `sha256`. The file is written only once it has verified.
pub fn fetch(url: &str, path: &Path, size: u64, sha256: &str) -> Result<(), String> {
    if !url.starts_with("https://") {
        return Err(format!("kits are fetched over HTTPS only, not {url}"));
    }
    let _ = rustls::crypto::ring::default_provider().install_default();
    let client = reqwest::blocking::Client::builder()
        .user_agent(concat!("nupp/", env!("CARGO_PKG_VERSION")))
        .build()
        .map_err(|e| format!("cannot start an HTTPS client: {e}"))?;
    let response = client.get(url).send().map_err(|e| format!("cannot fetch {url}: {e}"))?;
    if !response.status().is_success() {
        return Err(format!("fetching {url} answered {}", response.status()));
    }
    let mut bytes = Vec::new();
    response
        .take(size.min(LIMIT) + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| format!("reading {url} failed: {e}"))?;
    verify(&bytes, size, sha256)?;
    fs::write(path, &bytes).map_err(|e| format!("cannot write {}: {e}", path.display()))
}

fn octal(field: &[u8]) -> Result<u64, String> {
    let text = std::str::from_utf8(field).map_err(|_| "a tar header number is not text".to_string())?;
    let digits = text.trim_matches(|c: char| c == '\0' || c == ' ');
    if digits.is_empty() {
        return Ok(0);
    }
    u64::from_str_radix(digits, 8).map_err(|_| format!("a tar header number is not octal: {digits:?}"))
}

fn text(field: &[u8]) -> String {
    let end = field.iter().position(|&b| b == 0).unwrap_or(field.len());
    String::from_utf8_lossy(&field[..end]).into_owned()
}

/// A member path, relative and without `..`, under `root`.
fn contained(root: &Path, name: &str) -> Result<PathBuf, String> {
    let relative = Path::new(name);
    let mut out = root.to_path_buf();
    for part in relative.components() {
        match part {
            Component::Normal(piece) => out.push(piece),
            Component::CurDir => {}
            _ => return Err(format!("the kit archive names a path outside itself: {name}")),
        }
    }
    Ok(out)
}

/// A pax extended header's `path` record, when it has one.
fn pax_path(data: &[u8]) -> Option<String> {
    let mut rest = data;
    while !rest.is_empty() {
        let space = rest.iter().position(|&b| b == b' ')?;
        let length: usize = std::str::from_utf8(&rest[..space]).ok()?.parse().ok()?;
        if length <= space || length > rest.len() {
            return None;
        }
        let record = &rest[space + 1..length - 1];
        if let Some(value) = record.strip_prefix(b"path=") {
            return Some(String::from_utf8_lossy(value).into_owned());
        }
        rest = &rest[length..];
    }
    None
}

/// Unpacks the gzip-compressed tar `bytes` into `root`, which must exist.
/// Regular files and directories only: a kit carries nothing else.
pub fn unpack(bytes: &[u8], root: &Path) -> Result<(), String> {
    let mut tar = Vec::new();
    flate2::read::GzDecoder::new(bytes)
        .take(LIMIT + 1)
        .read_to_end(&mut tar)
        .map_err(|e| format!("the kit archive is not gzip: {e}"))?;
    if tar.len() as u64 > LIMIT {
        return Err("the kit archive unpacks to more than a gigabyte".into());
    }
    let mut at = 0usize;
    let mut long_name: Option<String> = None;
    while at + 512 <= tar.len() {
        let header = &tar[at..at + 512];
        if header.iter().all(|&b| b == 0) {
            return Ok(());
        }
        let size = octal(&header[124..136])? as usize;
        let kind = header[156];
        let start = at + 512;
        let end = start.checked_add(size).filter(|&e| e <= tar.len()).ok_or("the kit archive is truncated")?;
        let data = &tar[start..end];
        at = start + size.div_ceil(512) * 512;
        let name = match long_name.take() {
            Some(name) => name,
            None => {
                let base = text(&header[0..100]);
                let prefix = if &header[257..262] == b"ustar" { text(&header[345..500]) } else { String::new() };
                if prefix.is_empty() { base } else { format!("{prefix}/{base}") }
            }
        };
        match kind {
            b'x' => long_name = pax_path(data),
            b'L' => long_name = Some(text(data)),
            b'g' => {}
            b'5' => {
                let path = contained(root, &name)?;
                fs::create_dir_all(&path).map_err(|e| format!("cannot create {}: {e}", path.display()))?;
            }
            b'0' | 0 => {
                let path = contained(root, &name)?;
                if let Some(parent) = path.parent() {
                    fs::create_dir_all(parent).map_err(|e| format!("cannot create {}: {e}", parent.display()))?;
                }
                fs::write(&path, data).map_err(|e| format!("cannot write {}: {e}", path.display()))?;
            }
            other => {
                return Err(format!("the kit archive holds {name}, of tar type {:?}, which a kit never carries", other as char));
            }
        }
    }
    Err("the kit archive ends without its closing blocks".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn header(name: &str, kind: u8, size: usize) -> Vec<u8> {
        let mut h = vec![0u8; 512];
        h[..name.len()].copy_from_slice(name.as_bytes());
        h[100..108].copy_from_slice(b"0000644\0");
        h[124..136].copy_from_slice(format!("{size:011o}\0").as_bytes());
        h[156] = kind;
        h[257..263].copy_from_slice(b"ustar\0");
        h[148..156].copy_from_slice(b"        ");
        let sum: u32 = h.iter().map(|&b| b as u32).sum();
        h[148..156].copy_from_slice(format!("{sum:06o}\0 ").as_bytes());
        h
    }

    fn archive(members: &[(&str, u8, &[u8])]) -> Vec<u8> {
        let mut tar = Vec::new();
        for (name, kind, data) in members {
            tar.extend(header(name, *kind, data.len()));
            tar.extend_from_slice(data);
            tar.resize(tar.len().div_ceil(512) * 512, 0);
        }
        tar.extend(vec![0u8; 1024]);
        let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        gz.write_all(&tar).unwrap();
        gz.finish().unwrap()
    }

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("nupp-kit-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn unpacks_files_and_directories() {
        let dir = scratch("unpack");
        let bytes = archive(&[("sdk/", b'5', b""), ("sdk/usr/lib/libSystem.tbd", b'0', b"stub"), ("kit.json", b'0', b"{}")]);
        unpack(&bytes, &dir).unwrap();
        assert_eq!(fs::read(dir.join("sdk/usr/lib/libSystem.tbd")).unwrap(), b"stub");
        assert_eq!(fs::read(dir.join("kit.json")).unwrap(), b"{}");
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn refuses_paths_outside_the_kit() {
        let dir = scratch("escape");
        let bytes = archive(&[("../escaped", b'0', b"x")]);
        assert!(unpack(&bytes, &dir).unwrap_err().contains("outside"));
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn refuses_links() {
        let dir = scratch("link");
        let bytes = archive(&[("runtime", b'2', b"")]);
        assert!(unpack(&bytes, &dir).unwrap_err().contains("never carries"));
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn verifies_size_and_digest() {
        let empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
        verify(b"", 0, empty).unwrap();
        assert!(verify(b"x", 0, empty).unwrap_err().contains("bytes"));
        assert!(verify(b"", 0, &"0".repeat(64)).unwrap_err().contains("SHA-256"));
    }

    #[test]
    fn follows_pax_paths() {
        let dir = scratch("pax");
        let record = b"29 path=a/very/long/name.tbd\n";
        let bytes = archive(&[("PaxHeader", b'x', record), ("ignored", b'0', b"body")]);
        unpack(&bytes, &dir).unwrap();
        assert_eq!(fs::read(dir.join("a/very/long/name.tbd")).unwrap(), b"body");
        fs::remove_dir_all(dir).unwrap();
    }
}
