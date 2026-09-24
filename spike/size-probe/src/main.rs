//! Size probe: the backend as a product would carry it (no driver, no
//! decoders, no validators), fed IR JSON so nothing is optimized away.
#![allow(dead_code, unused_imports)]
#[cfg(feature = "arm64")]
#[path = "../../direct-backend/src/asm.rs"]
mod asm;
#[cfg(feature = "arm64")]
#[path = "../../direct-backend/src/emit.rs"]
mod emit;
#[cfg(feature = "x86")]
#[path = "../../direct-backend/src/emit_x86.rs"]
mod emit_x86;
#[cfg(feature = "arm64")]
#[path = "../../direct-backend/src/loader.rs"]
mod loader;
#[cfg(any(feature = "arm64", feature = "wasm"))]
#[path = "../../direct-backend/src/sem.rs"]
mod sem;
#[cfg(feature = "arm64")]
#[path = "../../direct-backend/src/lower.rs"]
mod lower;
#[cfg(feature = "arm64")]
#[path = "../../direct-backend/src/mir.rs"]
mod mir;
#[cfg(feature = "wasm")]
#[path = "../../direct-backend/src/wasmphase.rs"]
mod wasmphase;

fn main() {
    let path = std::env::args().nth(1).unwrap_or_default();
    let doc: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(path).unwrap_or("{}".into())).unwrap_or_default();
    let mut total = 0usize;
    #[cfg(feature = "arm64")]
    if let Some(fs) = doc["functions"].as_array() {
        let c = doc["c"].as_str().unwrap_or("");
        for f in fs {
            let sig = lower::signature(c, f["symbol"].as_str().unwrap_or(""));
            let func = if f["entryMode"] == "lua-builder" { lower::lower_builder(&f["tree"], 64) } else { lower::lower(&f["tree"], &sig) };
            let out = regalloc2::run(&func, &emit::machine_env_for(func.partitioned), &Default::default()).unwrap();
            let e = emit::emit_image(&func, &out);
            let image = loader::Image::load_with(&e.layout, &vec![0; e.layout.slots], Some(&e.frame));
            total += e.layout.bytes.len() + image.entry() as usize % 2;
            #[cfg(feature = "x86")]
            {
                let x = lower::lower_for(&f["tree"], &sig, lower::Target::X86Avx512);
                let o = regalloc2::run(&x, &emit_x86::machine_env_for(true), &Default::default()).unwrap();
                total += emit_x86::emit(&x, &o).bytes.len();
            }
        }
    }
    #[cfg(feature = "wasm")]
    if doc["functions"].is_array() {
        total += wasmphase::module(&doc).len();
    }
    #[cfg(feature = "embed")]
    {
        let mut obj = object::write::Object::new(object::BinaryFormat::MachO, object::Architecture::Aarch64, object::Endianness::Little);
        let text = obj.section_id(object::write::StandardSection::Text);
        obj.append_section_data(text, &[0u8; 16], 16);
        let bytes = obj.write().unwrap();
        let m = ar_archive_writer::NewArchiveMember::new(bytes, &ar_archive_writer::DEFAULT_OBJECT_READER, "k.o".into());
        let mut w = std::io::Cursor::new(Vec::new());
        ar_archive_writer::write_archive_to_stream(&mut w, &[m], ar_archive_writer::ArchiveKind::Darwin, false, None).unwrap();
        total += w.into_inner().len();
    }
    println!("{total}");
}
