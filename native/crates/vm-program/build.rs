// The runner's `aot_link` module, read from the program object's table
// rather than generated per object: the archive is built once.
fn main() {
    let out = std::path::PathBuf::from(std::env::var("OUT_DIR").unwrap()).join("aot_entries.rs");
    std::fs::write(
        out,
        "pub const ABI_VERSION: u32 = nupp_vm::compiled::AOT_ABI;\n\
         unsafe extern \"C\" { static nupp_aot_table: nupp_vm::compiled::LinkedTable; }\n\
         fn table() -> &'static nupp_vm::compiled::LinkedTable { unsafe { &*std::ptr::addr_of!(nupp_aot_table) } }\n\
         pub fn image_hash() -> [u8; 32] { table().image_hash() }\n\
         pub fn entries() -> Vec<(usize, u64)> { vec![] }\n\
         pub fn frame_entries() -> Vec<(usize, u64)> { table().frame_entries() }\n\
         pub fn maps() -> Vec<(usize, usize, Vec<(u32, u32, Vec<u32>)>)> { table().maps() }\n",
    )
    .unwrap();
}
