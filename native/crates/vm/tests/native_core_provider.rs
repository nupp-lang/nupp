#![cfg(all(
    feature = "aot",
    feature = "native-runtime",
    target_arch = "aarch64",
    target_endian = "little"
))]

use nupp_vm::native_core_provider::{self as provider, CORE_EXPORT_COUNT, CORE_EXPORT_NAMES};
use serde_json::json;
use std::process::Command;

nupp_vm::native_core_api! {
    fn nupp_allocator_slot_bytes(class: u64) -> u64;
    fn nupp_object_string_hash(bytes: *const u8, count: u64, state: u64) -> u64;
}

#[test]
fn provider_child() {
    let Ok(mode) = std::env::var("NUPP_PROVIDER_TEST") else {
        return;
    };
    if mode == "reject" {
        assert!(provider::initialize().unwrap_err().contains("all 105"));
        return;
    }
    provider::initialize().unwrap();
    assert_eq!(CORE_EXPORT_NAMES.len(), CORE_EXPORT_COUNT);
    for (i, name) in CORE_EXPORT_NAMES.iter().enumerate() {
        assert_eq!(provider::export_index(name), i);
        assert_ne!(provider::address(i), 0);
        assert!(!CORE_EXPORT_NAMES[..i].contains(name));
    }
    if mode == "owned" {
        // These unrelated signatures both reach the retained fixture entry.
        // The fixture proves transport only; it is not a native runtime.
        assert_eq!(unsafe { nupp_allocator_slot_bytes(0) }, 42);
        assert_eq!(
            unsafe { nupp_object_string_hash(std::ptr::null(), 0, 0) },
            42
        );
        unsafe { std::env::remove_var("NUPP_RAW_CORE") };
        std::thread::spawn(|| assert_eq!(unsafe { nupp_allocator_slot_bytes(5) }, 42))
            .join()
            .unwrap();
    } else {
        let before = unsafe { nupp_allocator_slot_bytes(0) };
        assert!(before >= 32);
        unsafe { std::env::set_var("NUPP_RAW_CORE", "/does/not/exist") };
        assert_eq!(unsafe { nupp_allocator_slot_bytes(0) }, before);
    }
}

#[test]
fn complete_provider_is_selected_once_for_linked_and_owned_routes() {
    let receipt: serde_json::Value =
        serde_json::from_str(include_str!("runtime/s0-raw-loader-2026-10-27.json")).unwrap();
    let expected: Vec<&str> = receipt["fullCoreProviderAudit"]["exports"]
        .as_object()
        .unwrap()
        .keys()
        .map(String::as_str)
        .collect();
    assert_eq!(CORE_EXPORT_NAMES, expected);
    let dir = std::env::temp_dir().join(format!("nupp-core-provider-{}", std::process::id()));
    std::fs::create_dir(&dir).unwrap();
    // Assembler-checked: fill 105 output words with the address of an entry
    // returning 42. Each exported call retains its original Rust C signature.
    let code: [u32; 8] = [
        0x100000c5, 0xd2800d26, 0xf8008425, 0xf10004c6, 0x54ffffc1, 0xd65f03c0, 0xd2800540,
        0xd65f03c0,
    ];
    std::fs::write(
        dir.join("code.bin"),
        code.iter()
            .flat_map(|word| word.to_le_bytes())
            .collect::<Vec<_>>(),
    )
    .unwrap();
    std::fs::write(dir.join("data.bin"), []).unwrap();
    for (mode, count) in [("linked", 105), ("owned", 105), ("reject", 104)] {
        let manifest = json!({"version":1,"architecture":"aarch64","layoutDigest":nupp_vm::native_raw_bundle::layout_digest_hex().unwrap(),"entry":0,"code":"code.bin","data":"data.bin","imports":[],"outputWords":count});
        let path = dir.join("bundle.json");
        std::fs::write(&path, serde_json::to_vec(&manifest).unwrap()).unwrap();
        let mut child = Command::new(std::env::current_exe().unwrap());
        child
            .args(["--exact", "provider_child", "--nocapture"])
            .env("NUPP_PROVIDER_TEST", mode)
            .env_remove("NUPP_RAW_CORE");
        if mode != "linked" {
            child.env("NUPP_RAW_CORE", &path);
        }
        let result = child.output().unwrap();
        assert!(
            result.status.success(),
            "{mode}: {}\n{}",
            String::from_utf8_lossy(&result.stdout),
            String::from_utf8_lossy(&result.stderr)
        );
        assert!(String::from_utf8_lossy(&result.stdout).contains("1 passed; 0 failed"));
    }
    std::fs::remove_dir_all(dir).unwrap();
    let exports = Command::new(env!("CARGO_BIN_EXE_nupp-vm"))
        .args(["native", "raw-exports"])
        .output()
        .unwrap();
    assert!(exports.status.success());
    assert_eq!(
        String::from_utf8(exports.stdout)
            .unwrap()
            .lines()
            .collect::<Vec<_>>(),
        CORE_EXPORT_NAMES
    );
}
