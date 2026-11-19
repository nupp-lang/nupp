// Generates the table of linked ahead-of-time entries.
fn main() {
    native_runtime();
    isal_crc();
    println!("cargo:rerun-if-env-changed=NUPP_AOT_OBJECT");
    let generated =
        std::path::PathBuf::from(std::env::var("OUT_DIR").unwrap()).join("aot_entries.rs");
    if let Ok(object) = std::env::var("NUPP_AOT_OBJECT") {
        assert!(
            std::env::var("CARGO_FEATURE_AOT_LINKED").is_ok(),
            "NUPP_AOT_OBJECT requires --features aot-linked (or aot)"
        );
        let object = std::fs::canonicalize(object).unwrap();
        let object = object.to_str().unwrap();
        println!("cargo:rerun-if-changed={object}");
        println!("cargo:rerun-if-changed={object}.rs");
        println!("cargo:rerun-if-changed={object}.maps");
        println!("cargo:rustc-link-arg-bin=nupp-vm={}", linker_path(object));
        std::fs::copy(format!("{object}.rs"), &generated).unwrap();
    } else {
        std::fs::write(&generated, "pub const ABI_VERSION: u32 = 4;\npub fn image_hash() -> [u8; 32] { [0; 32] }\npub fn entries() -> Vec<(usize, u64)> { vec![] }\npub fn frame_entries() -> Vec<(usize, u64)> { vec![] }\npub fn maps() -> Vec<(usize, usize, Vec<(u32, u32, Vec<u32>)>)> { vec![] }\n").unwrap();
    }
}

fn native_runtime() {
    println!("cargo:rerun-if-env-changed=NUPP_NATIVE_RUNTIME_OBJECT");
    if std::env::var_os("CARGO_FEATURE_NATIVE_RUNTIME").is_some() {
        let arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
        assert!(
            matches!(arch.as_str(), "aarch64" | "x86_64"),
            "native-runtime requires a 64-bit ARM or x86 host"
        );
        let object = std::fs::canonicalize(
            std::env::var("NUPP_NATIVE_RUNTIME_OBJECT")
                .expect("native-runtime requires NUPP_NATIVE_RUNTIME_OBJECT"),
        )
        .unwrap();
        let object = object.to_str().unwrap();
        println!("cargo:rerun-if-changed={object}");
        println!("cargo:rerun-if-changed={object}.rs");
        println!("cargo:rustc-link-arg={}", linker_path(object));
        let generated =
            std::path::PathBuf::from(std::env::var("OUT_DIR").unwrap()).join("native_runtime.rs");
        std::fs::copy(format!("{object}.rs"), generated).unwrap();
    } else {
        assert!(
            std::env::var_os("NUPP_NATIVE_RUNTIME_OBJECT").is_none(),
            "NUPP_NATIVE_RUNTIME_OBJECT requires native-runtime"
        );
    }
}

// Rust's canonical Windows paths use the verbatim prefix. MinGW's linker
// response-file parser does not accept that prefix, even for an existing file.
// Keep canonical paths for file access and normalize only the linker argument.
fn linker_path(path: &str) -> String {
    if cfg!(windows) {
        windows_linker_path(path)
    } else {
        path.to_owned()
    }
}

fn windows_linker_path(path: &str) -> String {
    let ordinary = if let Some(rest) = path.strip_prefix(r"\\?\UNC\") {
        format!(r"\\{rest}")
    } else {
        path.strip_prefix(r"\\?\").unwrap_or(path).to_owned()
    };
    ordinary.replace('\\', "/")
}

#[cfg(test)]
mod tests {
    use super::{linker_path, windows_linker_path};

    #[test]
    fn windows_link_arguments_accept_canonical_drive_and_unc_paths() {
        assert_eq!(
            windows_linker_path(r"\\?\D:\a\nupp\runtime.o"),
            "D:/a/nupp/runtime.o"
        );
        assert_eq!(
            windows_linker_path(r"\\?\C:\Program Files\nupp\runtime.o"),
            "C:/Program Files/nupp/runtime.o"
        );
        assert_eq!(
            windows_linker_path(r"\\?\UNC\host\shared folder\runtime.o"),
            "//host/shared folder/runtime.o"
        );
        assert_eq!(
            windows_linker_path(r"\\host\shared folder\runtime.o"),
            "//host/shared folder/runtime.o"
        );
        assert_eq!(
            windows_linker_path(r"D:\ordinary\runtime.o"),
            "D:/ordinary/runtime.o"
        );
        assert_eq!(
            windows_linker_path("D:/ordinary/runtime.o"),
            "D:/ordinary/runtime.o"
        );
        assert_eq!(
            windows_linker_path("/tmp/native core/runtime.o"),
            "/tmp/native core/runtime.o"
        );
        assert_eq!(
            windows_linker_path("relative/runtime.o"),
            "relative/runtime.o"
        );
        if !cfg!(windows) {
            assert_eq!(linker_path(r"/tmp/a\b.o"), r"/tmp/a\b.o");
        }
    }
}

/// Links the pinned ISA-L CRC bundle (`native/crc`) persistence frames are
/// checked with, built once per host by `scripts/native-libraries isal`.
fn isal_crc() {
    use std::{env, path::PathBuf, process::Command};

    let root = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap()).join("../../..");
    for path in [
        "scripts/toolchain.pins",
        "scripts/native-libraries",
        "scripts/c-libraries/isal.sh",
        "native/crc",
        "notices/ISA-L-LICENSE.txt",
        "notices/ISA-L-CRC-LICENSE.txt",
    ] {
        println!("cargo:rerun-if-changed={}", root.join(path).display());
    }
    for key in [
        "NUPP_CC",
        "CC",
        "NUPP_TOOLCHAIN_DIR",
        "NUPP_HOST_OFFLINE",
        "NUPP_HOST_SOURCE_DIR",
        "NUPP_HOST_SOURCE_BASE_URL",
        "CFLAGS",
        "CPPFLAGS",
        "LDFLAGS",
        "SDKROOT",
        "MACOSX_DEPLOYMENT_TARGET",
        "WindowsSDKVersion",
        "VCToolsVersion",
    ] {
        println!("cargo:rerun-if-env-changed={key}");
    }
    assert_eq!(
        env::var("HOST").unwrap(),
        env::var("TARGET").unwrap(),
        "ISA-L cross compilation needs an explicit target toolchain"
    );
    let mut command = Command::new("sh");
    command
        .arg(root.join("scripts/native-libraries"))
        .arg("isal")
        .env("NUPP_NATIVE_TARGET", env::var("TARGET").unwrap());
    if env::var_os("NUPP_CC").is_none() {
        if let Some(cc) = env::var_os("CC") {
            command.env("NUPP_CC", cc);
        } else if env::var("TARGET").unwrap().ends_with("windows-gnu") {
            command.env("NUPP_CC", "gcc");
        }
    }
    let output = command
        .output()
        .expect("run the pinned ISA-L C provisioner");
    assert!(
        output.status.success(),
        "ISA-L provisioning failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let mut prefix = String::from_utf8(output.stdout).unwrap().trim().to_owned();
    if cfg!(windows) {
        let converted = Command::new("cygpath")
            .args(["-w", &prefix])
            .output()
            .expect("convert the Git Bash prefix to a native Windows path");
        assert!(converted.status.success(), "cygpath failed");
        prefix = String::from_utf8(converted.stdout)
            .unwrap()
            .trim()
            .to_owned();
    }
    let prefix = PathBuf::from(prefix);
    println!(
        "cargo:rustc-link-search=native={}",
        prefix.join("lib").display()
    );
    println!("cargo:rustc-link-lib=static=nupp_crc_static");
}
