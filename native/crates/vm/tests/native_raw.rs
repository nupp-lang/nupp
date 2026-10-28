#![cfg(all(feature = "jit", target_arch = "aarch64", target_endian = "little"))]

use nupp_vm::native_raw::{ARCHITECTURE, ImageSpec, PendingImage};

// Assembler-checked transport fixture, not a backend implementation:
// ldr x2,[x0,#56]; ldr x3,[x2]; ldr x4,[x0,#24]; ldr x4,[x4];
// add x3,x3,x4; ldr x5,[x0,#40]; ldr x5,[x5]; eor x3,x3,x5;
// str x3,[x1]; ret
const CODE: [u32; 10] = [
    0xf9401c02, 0xf9400043, 0xf9400c04, 0xf9400084, 0x8b040063, 0xf9401405, 0xf94000a5, 0xca050063,
    0xf9000023, 0xd65f03c0,
];

#[test]
fn raw_words_data_and_imports_execute_without_codegen() {
    let code: Vec<u8> = CODE.iter().flat_map(|word| word.to_le_bytes()).collect();
    let spec = ImageSpec {
        architecture: ARCHITECTURE,
        layout_digest: [7; 32],
        entry: 0,
    };
    let mut pending =
        PendingImage::new(spec, &[7; 32], &code, &0u64.to_le_bytes(), &[0xaa]).unwrap();
    assert!(pending.bases().iter().all(|base| base % 16 == 0));
    assert_eq!(pending.code_mut(), &code);
    pending.data_mut().copy_from_slice(&35u64.to_le_bytes());
    let image = pending.seal().unwrap();
    let mut output = [u64::MAX];
    unsafe { image.call(&[7], &mut output) };
    assert_eq!(output, [128]);
    unsafe { image.call(&[8], &mut output) };
    assert_eq!(output, [129]);
}

#[test]
fn rejected_image_never_becomes_callable() {
    let code = [0xc0, 0x03, 0x5f, 0xd6];
    for (architecture, digest, entry, size) in [
        ("x86_64", [7; 32], 0, 4),
        (ARCHITECTURE, [8; 32], 0, 4),
        (ARCHITECTURE, [7; 32], 1, 4),
        (ARCHITECTURE, [7; 32], 4, 4),
        (ARCHITECTURE, [7; 32], 0, 3),
        (ARCHITECTURE, [7; 32], 0, 0),
    ] {
        let spec = ImageSpec {
            architecture,
            layout_digest: digest,
            entry,
        };
        assert!(PendingImage::new(spec, &[7; 32], &code[..size], &[], &[]).is_err());
    }
}

#[test]
#[cfg(target_os = "macos")]
fn executable_memory_denial_stops_publication() {
    use std::process::Command;
    let directory = std::env::temp_dir().join(format!("nupp-raw-denial-{}", std::process::id()));
    std::fs::create_dir(&directory).unwrap();
    let library = directory.join("deny-exec.dylib");
    let source = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/deny-exec.c");
    let compiled = Command::new("cc")
        .args(["-dynamiclib", "-o"])
        .arg(&library)
        .arg(source)
        .output()
        .unwrap();
    assert!(
        compiled.status.success(),
        "{}",
        String::from_utf8_lossy(&compiled.stderr)
    );
    let result = Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "raw_words_data_and_imports_execute_without_codegen",
            "--nocapture",
        ])
        .env("DYLD_INSERT_LIBRARIES", &library)
        .output()
        .unwrap();
    std::fs::remove_dir_all(directory).unwrap();
    assert_eq!(
        result.status.code(),
        Some(86),
        "stdout={} stderr={}",
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    );
}
