#![cfg(all(
    feature = "aot",
    feature = "native-runtime",
    target_arch = "aarch64",
    target_endian = "little"
))]

use nupp_vm::native_raw_bundle::{HOST_IMPORT_NAMES, host_symbol, layout_digest_hex};
use serde_json::{Value, json};
use std::path::PathBuf;
use std::process::{Command, Output};

struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir =
            std::env::temp_dir().join(format!("nupp-raw-bundle-{}-{unique}", std::process::id()));
        std::fs::create_dir(&dir).unwrap();
        // Assembler-checked C entry: preserve x19/LR, call import zero with no
        // arguments, write its word result, restore the native frame and return.
        let code: [u32; 11] = [
            0xa9be7bfd, 0x910003fd, 0xf9000bf3, 0xaa0103f3, 0xf9401402, 0xf9400042, 0xd63f0040,
            0xf9000260, 0xf9400bf3, 0xa8c27bfd, 0xd65f03c0,
        ];
        std::fs::write(
            dir.join("code.bin"),
            code.iter()
                .flat_map(|word| word.to_le_bytes())
                .collect::<Vec<_>>(),
        )
        .unwrap();
        std::fs::write(dir.join("data.bin"), []).unwrap();
        std::fs::write(dir.join("input.bin"), []).unwrap();
        Self(dir)
    }
    fn manifest(&self) -> Value {
        json!({"version":1,"architecture":"aarch64","layoutDigest":layout_digest_hex().unwrap(),"entry":0,"code":"code.bin","data":"data.bin","imports":["nupp_os_page_size"],"outputWords":1})
    }
    fn run(&self, manifest: &Value) -> Output {
        let bundle = self.0.join("bundle.json");
        std::fs::write(&bundle, serde_json::to_vec(manifest).unwrap()).unwrap();
        Command::new(env!("CARGO_BIN_EXE_nupp-vm"))
            .current_dir(std::env::temp_dir())
            .args(["native", "raw"])
            .arg(bundle)
            .arg(self.0.join("input.bin"))
            .arg(self.0.join("output.bin"))
            .output()
            .unwrap()
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        std::fs::remove_dir_all(&self.0).unwrap();
    }
}

#[test]
fn bundle_cli_executes_existing_host_import_with_relative_files() {
    let fixture = Fixture::new();
    let output = fixture.run(&fixture.manifest());
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let result = std::fs::read(fixture.0.join("output.bin")).unwrap();
    assert_eq!(
        result,
        unsafe { nupp_vm::os_glue::nupp_os_page_size() }.to_le_bytes()
    );
    let digest = Command::new(env!("CARGO_BIN_EXE_nupp-vm"))
        .args(["native", "raw-layout"])
        .output()
        .unwrap();
    assert!(digest.status.success());
    assert_eq!(
        String::from_utf8(digest.stdout).unwrap().trim(),
        layout_digest_hex().unwrap()
    );
}

#[test]
fn bundle_rejects_bad_metadata_and_preserves_output() {
    let fixture = Fixture::new();
    let original = fixture.manifest();
    for (field, value) in [
        ("version", json!(2)),
        ("version", json!(1.0)),
        ("architecture", json!("x86_64")),
        ("layoutDigest", json!("00".repeat(32))),
        ("entry", json!(4_000_000)),
        ("entry", json!(-1)),
        ("entry", json!(2)),
        ("imports", json!(["nupp_rt_unknown"])),
        ("imports", json!([7])),
        ("imports", json!(vec!["nupp_os_page_size"; 89])),
        ("outputWords", json!(1_048_577)),
        ("code", json!(null)),
        ("unknown", json!(true)),
    ] {
        let mut manifest = original.clone();
        manifest[field] = value;
        std::fs::write(fixture.0.join("output.bin"), b"untouched").unwrap();
        let output = fixture.run(&manifest);
        assert!(!output.status.success(), "accepted {manifest}");
        assert_eq!(
            std::fs::read(fixture.0.join("output.bin")).unwrap(),
            b"untouched"
        );
    }
    std::fs::write(fixture.0.join("input.bin"), [1, 2, 3]).unwrap();
    assert!(!fixture.run(&original).status.success());
    std::fs::write(fixture.0.join("input.bin"), []).unwrap();
    std::fs::OpenOptions::new()
        .write(true)
        .open(fixture.0.join("code.bin"))
        .unwrap()
        .set_len(64 * 1024 * 1024 + 1)
        .unwrap();
    assert!(!fixture.run(&original).status.success());
}

#[test]
fn host_resolver_matches_the_frozen_core_import_inventory() {
    let receipt: Value =
        serde_json::from_str(include_str!("runtime/s0-raw-loader-2026-10-27.json")).unwrap();
    let expected: Vec<&str> = receipt["fullCoreProviderAudit"]["hostImports"]
        .as_array()
        .unwrap()
        .iter()
        .map(|name| name.as_str().unwrap())
        .collect();
    assert_eq!(HOST_IMPORT_NAMES, expected);
    assert!(
        HOST_IMPORT_NAMES
            .iter()
            .all(|name| host_symbol(name).is_some_and(|address| address != 0))
    );
    assert!(host_symbol("nupp_rt_any").is_none());
}
