// Generates the table of linked ahead-of-time entries and checks the
// allocator selection.
fn main() {
    let mimalloc = std::env::var_os("CARGO_FEATURE_ALLOCATOR_MIMALLOC").is_some();
    let jemalloc = std::env::var_os("CARGO_FEATURE_ALLOCATOR_JEMALLOC").is_some();
    assert!(!(mimalloc && jemalloc), "allocator-mimalloc and allocator-jemalloc are mutually exclusive");
    if mimalloc || jemalloc {
        let arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
        let os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
        let env = std::env::var("CARGO_CFG_TARGET_ENV").unwrap();
        assert!(matches!(arch.as_str(), "aarch64" | "x86_64")
            && (os == "macos" || os == "linux" && env == "gnu"),
            "allocator experiments support only aarch64/x86_64 macOS and GNU Linux");
    }
    println!("cargo:rerun-if-env-changed=NUPP_AOT_OBJECT");
    let generated = std::path::PathBuf::from(std::env::var("OUT_DIR").unwrap()).join("aot_entries.rs");
    if let Ok(object) = std::env::var("NUPP_AOT_OBJECT") {
        assert!(std::env::var("CARGO_FEATURE_AOT_LINKED").is_ok(), "NUPP_AOT_OBJECT requires --features aot-linked (or aot)");
        let object = std::fs::canonicalize(object).unwrap();
        let object = object.to_str().unwrap();
        println!("cargo:rerun-if-changed={object}");
        println!("cargo:rerun-if-changed={object}.rs");
        println!("cargo:rerun-if-changed={object}.maps");
        println!("cargo:rustc-link-arg-bin=nupp-vm={object}");
        std::fs::copy(format!("{object}.rs"), &generated).unwrap();
    } else {
        std::fs::write(&generated, "pub const ABI_VERSION: u32 = 4;\npub fn image_hash() -> [u8; 32] { [0; 32] }\npub fn entries() -> Vec<(usize, u64)> { vec![] }\npub fn frame_entries() -> Vec<(usize, u64)> { vec![] }\npub fn maps() -> Vec<(usize, usize, Vec<(u32, u32, Vec<u32>)>)> { vec![] }\n").unwrap();
    }
}
