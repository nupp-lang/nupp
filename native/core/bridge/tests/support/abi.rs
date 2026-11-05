//! C-boundary preservation proof, compiled only in the test executable.
use super::{HEADER, execute, header, input};
use std::path::PathBuf;

std::arch::global_asm!(include_str!("abi-aarch64.S"));

type Entry = unsafe extern "C" fn(*const u64, *mut u64) -> u64;

unsafe extern "C" {
    fn nupp_core_test_abi(entry: Entry, packet: *const u64, output: *mut u64, report: *mut u64);
    fn nupp_core_test_abi_clobber(packet: *const u64, output: *mut u64) -> u64;
}

pub(super) unsafe fn invoke(entry: Entry, packet: *const u64, output: *mut u64) -> u64 {
    let mut report = [0u64; 2];
    unsafe {
        nupp_core_test_abi(entry, packet, output, report.as_mut_ptr());
    }
    assert_eq!(
        report[1], 0,
        "C ABI preservation: bits0..10=x19..x29; bits11..18=low64 d8..d15"
    );
    report[0]
}

#[test]
fn wrapper_detects_integer_and_float_clobber() {
    let mut report = [0u64; 2];
    unsafe {
        nupp_core_test_abi(
            nupp_core_test_abi_clobber,
            std::ptr::null(),
            std::ptr::null_mut(),
            report.as_mut_ptr(),
        );
    }
    assert_eq!(report, [7, 1 | (1 << 11)]);
}

#[test]
#[ignore = "requires an actual Nupp-produced bundle; select explicitly with CORE_TEST_BUNDLE/INPUT/EXPECTED"]
fn generated_entry_preserves_c_abi_and_output() {
    let required = |name| {
        PathBuf::from(
            std::env::var_os(name)
                .unwrap_or_else(|| panic!("required artifact variable {name} is missing")),
        )
    };
    let bundle = required("CORE_TEST_BUNDLE");
    let words = input(&required("CORE_TEST_INPUT")).expect("read input artifact");
    let expected =
        input(&required("CORE_TEST_EXPECTED")).expect("read independent expected output");
    // The program's arguments after its own, as the bridge takes them.
    if let Some(extra) = std::env::var_os("CORE_TEST_ARGUMENTS") {
        let mut program = vec![bundle.clone().into_os_string()];
        program.extend(
            extra
                .to_string_lossy()
                .split(' ')
                .filter(|s| !s.is_empty())
                .map(Into::into),
        );
        let _ = super::platform::ARGUMENTS.set(program);
    }
    let actual = execute(&bundle, &words).expect("invoke Nupp-produced entry through ABI checker");
    assert_eq!(actual, expected, "exact entry output");
}

#[test]
#[ignore = "requires an actual Nupp-produced bundle; select explicitly with CORE_TEST_BUNDLE/INPUT"]
fn generated_entry_refuses_short_regions() {
    let bundle =
        PathBuf::from(std::env::var_os("CORE_TEST_BUNDLE").expect("CORE_TEST_BUNDLE required"));
    let words = input(&PathBuf::from(
        std::env::var_os("CORE_TEST_INPUT").expect("CORE_TEST_INPUT required"),
    ))
    .expect("read input artifact");
    let original = std::fs::read(bundle).expect("read generated bundle");
    let spec =
        header(&original[..HEADER], original.len() as u64).expect("generated transport header");
    let directory = std::env::temp_dir().join(format!(
        "nupp-core-abi-refusals-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir(&directory).unwrap();
    struct Cleanup(PathBuf);
    impl Drop for Cleanup {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
    let _cleanup = Cleanup(directory.clone());
    for (field, value) in [(4usize, 0u64), (4, 31), (5, 0), (5, 65535), (6, 0)] {
        let mut bytes = original.clone();
        bytes[8 + field * 8..16 + field * 8].copy_from_slice(&value.to_le_bytes());
        if field == 4 {
            bytes.truncate(HEADER + spec.code + value as usize);
        }
        header(&bytes[..HEADER], bytes.len() as u64)
            .expect("refusal case must remain a valid transport");
        let path = directory.join(format!("field{field}-{value}.bundle"));
        std::fs::write(&path, bytes).unwrap();
        let error =
            execute(&path, &words).expect_err("Nupp entry must refuse undersized opaque regions");
        assert!(
            error.starts_with("Nupp entry refused with transport status "),
            "entry rather than bridge refusal: {error}"
        );
    }
}

#[test]
#[ignore = "requires actual Nupp-produced bundle/input and opaque expected transport status"]
fn generated_entry_returns_requested_status() {
    let bundle =
        PathBuf::from(std::env::var_os("CORE_TEST_BUNDLE").expect("CORE_TEST_BUNDLE required"));
    let words = input(&PathBuf::from(
        std::env::var_os("CORE_TEST_INPUT").expect("CORE_TEST_INPUT required"),
    ))
    .expect("read input artifact");
    let status: u64 = std::env::var("CORE_TEST_STATUS")
        .expect("CORE_TEST_STATUS required")
        .parse()
        .expect("integer transport status");
    assert_ne!(status, 0, "successful entry uses the output test");
    let error = execute(&bundle, &words).expect_err("expected generated-entry refusal");
    assert_eq!(
        error,
        format!("Nupp entry refused with transport status {status}")
    );
}
