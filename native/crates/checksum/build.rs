use std::{env, path::PathBuf, process::Command};

fn main() {
    // The retained browser runtime has no native C-library provisioner yet.
    if env::var("CARGO_CFG_TARGET_FAMILY").unwrap() == "wasm" {
        return;
    }
    let root = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap()).join("../../..");
    for path in [
        "scripts/toolchain.pins",
        "scripts/native-libraries",
        "scripts/c-libraries/isal.sh",
        "native/crates/checksum/csrc",
        "host/notices/ISA-L-LICENSE.txt",
        "host/notices/ISA-L-CRC-LICENSE.txt",
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
