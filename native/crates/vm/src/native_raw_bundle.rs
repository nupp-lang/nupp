//! Opaque S0 bundles and word-file transport for the native runner.
use crate::native_raw::{CALL_ABI, ImageSpec, PendingImage};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::io::Read;
use std::path::Path;

#[path = "native_raw_imports.rs"]
mod imports;
pub use imports::{HOST_IMPORT_NAMES, host_symbol};

const MANIFEST_LIMIT: usize = 64 * 1024;
const IMAGE_LIMIT: usize = 64 * 1024 * 1024;
const WORD_LIMIT: usize = 1024 * 1024;
const FIELDS: [&str; 8] = [
    "version",
    "architecture",
    "layoutDigest",
    "entry",
    "code",
    "data",
    "imports",
    "outputWords",
];

pub fn layout_digest() -> Result<[u8; 32], String> {
    let mut hash = Sha256::new();
    hash.update(b"nupp-raw-layout-v1\0");
    hash.update(std::env::consts::ARCH.as_bytes());
    hash.update([0]);
    hash.update(std::env::consts::OS.as_bytes());
    hash.update([0]);
    hash.update(crate::native_glue::layout_json()?.as_bytes());
    hash.update(crate::dispatch::OBJECT_ABI.to_le_bytes());
    hash.update(CALL_ABI.to_le_bytes());
    Ok(hash.finalize().into())
}

pub fn layout_digest_hex() -> Result<String, String> {
    Ok(layout_digest()?
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect())
}

fn read_bounded(path: &Path, limit: usize) -> Result<Vec<u8>, String> {
    let file = std::fs::File::open(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let metadata = file.metadata().map_err(|e| e.to_string())?;
    if !metadata.is_file() || metadata.len() > limit as u64 {
        return Err(format!(
            "{} exceeds the {limit}-byte file limit",
            path.display()
        ));
    }
    let mut bytes = Vec::with_capacity(metadata.len() as usize);
    file.take(limit as u64 + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    if bytes.len() > limit {
        return Err(format!("{} grew beyond its file limit", path.display()));
    }
    Ok(bytes)
}

fn string<'a>(value: &'a Value, field: &str) -> Result<&'a str, String> {
    value[field]
        .as_str()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| format!("bundle {field} must be a nonempty string"))
}
fn integer(value: &Value, field: &str) -> Result<usize, String> {
    value[field]
        .as_u64()
        .and_then(|n| usize::try_from(n).ok())
        .ok_or_else(|| format!("bundle {field} must be an unsigned integer"))
}
fn digest(text: &str) -> Result<[u8; 32], String> {
    if text.len() != 64 || !text.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("bundle layoutDigest must contain 64 hexadecimal digits".into());
    }
    let mut bytes = [0; 32];
    for (i, byte) in bytes.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&text[2 * i..2 * i + 2], 16).map_err(|e| e.to_string())?;
    }
    Ok(bytes)
}

/// Executes a bundle with little-endian u64 input and output files.
///
/// # Safety
/// The bundle is native code and must obey `Image::call`'s contract. The
/// digest validates host compatibility; it does not establish code safety.
pub unsafe fn run(bundle: &str, input: &str, output: &str) -> Result<(), String> {
    let path = Path::new(bundle);
    let value: Value =
        serde_json::from_slice(&read_bounded(path, MANIFEST_LIMIT)?).map_err(|e| e.to_string())?;
    let object = value.as_object().ok_or("bundle must be a JSON object")?;
    if object.len() != FIELDS.len() || object.keys().any(|key| !FIELDS.contains(&key.as_str())) {
        return Err("bundle fields must be version, architecture, layoutDigest, entry, code, data, imports and outputWords".into());
    }
    if integer(&value, "version")? != 1 {
        return Err("unsupported raw bundle version".into());
    }
    let spec = ImageSpec {
        architecture: string(&value, "architecture")?,
        layout_digest: digest(string(&value, "layoutDigest")?)?,
        entry: integer(&value, "entry")?,
    };
    let expected = layout_digest()?;
    if spec.layout_digest != expected {
        return Err("raw image layout digest differs from the host".into());
    }
    let output_words = integer(&value, "outputWords")?;
    if output_words > WORD_LIMIT {
        return Err("bundle outputWords exceeds the word limit".into());
    }
    let names = value["imports"]
        .as_array()
        .ok_or("bundle imports must be an array of symbol names")?;
    if names.len() > HOST_IMPORT_NAMES.len() {
        return Err("bundle exceeds the import limit".into());
    }
    let addresses = names
        .iter()
        .map(|name| {
            let name = name.as_str().ok_or("bundle import must be a symbol name")?;
            host_symbol(name).ok_or_else(|| format!("unknown raw host import {name}"))
        })
        .collect::<Result<Vec<_>, String>>()?;
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    let code = read_bounded(&parent.join(string(&value, "code")?), IMAGE_LIMIT)?;
    let data = read_bounded(&parent.join(string(&value, "data")?), IMAGE_LIMIT)?;
    let bytes = read_bounded(Path::new(input), WORD_LIMIT * 8)?;
    if bytes.len() % 8 != 0 {
        return Err("raw input must contain complete little-endian u64 words".into());
    }
    let words: Vec<u64> = bytes
        .chunks_exact(8)
        .map(|word| u64::from_le_bytes(word.try_into().unwrap()))
        .collect();
    let image = PendingImage::new(spec, &expected, &code, &data, &addresses)?.seal()?;
    let mut out = vec![0; output_words];
    unsafe { image.call(&words, &mut out) };
    let bytes: Vec<u8> = out.iter().flat_map(|word| word.to_le_bytes()).collect();
    std::fs::write(output, bytes).map_err(|e| e.to_string())
}
