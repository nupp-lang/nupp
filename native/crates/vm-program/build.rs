// The versioned table belongs to the same trusted native link as this runner.
fn main() {
    let out = std::path::PathBuf::from(std::env::var("OUT_DIR").unwrap()).join("aot_entries.rs");
    std::fs::write(out, r#"
pub const ABI_VERSION: u32 = nupp_vm::compiled::AOT_ABI;
unsafe extern "C" { static nupp_aot_table_v1: nupp_vm::compiled::LinkedTable; }
fn program() -> &'static std::sync::Mutex<nupp_vm::compiled::LinkedProgram> {
    static VALUE: std::sync::OnceLock<std::sync::Mutex<nupp_vm::compiled::LinkedProgram>> = std::sync::OnceLock::new();
    VALUE.get_or_init(|| {
        // All pointer storage is emitted into this executable and remains
        // readable and immutable for the process lifetime. Validate before
        // publishing entries/maps or running any program initializer.
        let decoded = unsafe { nupp_aot_table_v1.read() }.unwrap_or_else(|problem| {
            eprintln!("{problem}"); std::process::exit(1)
        });
        std::sync::Mutex::new(decoded)
    })
}
pub fn image_hash() -> [u8; 32] { program().lock().unwrap().hash }
pub fn entries() -> Vec<(usize, u64)> { vec![] }
pub fn frame_entries() -> Vec<(usize, u64)> { std::mem::take(&mut program().lock().unwrap().entries) }
pub fn maps() -> Vec<(usize, usize, Vec<(u32, u32, Vec<u32>)>)> { std::mem::take(&mut program().lock().unwrap().maps) }
"#).unwrap();
}
