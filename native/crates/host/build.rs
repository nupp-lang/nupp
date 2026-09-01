use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const LUAJIT_PREFIX_ENV: &str = "NUPP_LUAJIT_PREFIX";

fn main() {
    println!("cargo:rerun-if-env-changed={LUAJIT_PREFIX_ENV}");
    println!("cargo:rerun-if-env-changed=NUPP_LPEG_PREFIX");
    println!("cargo:rerun-if-env-changed=NUPP_CC");
    println!("cargo:rerun-if-env-changed=CC");
    println!("cargo:rerun-if-env-changed=AR");
    println!("cargo:rerun-if-changed=../../../scripts/toolchain");
    println!("cargo:rerun-if-changed=../../../scripts/toolchain.pins");
    println!("cargo:rerun-if-changed=c/lua_shim.c");
    println!("cargo:rerun-if-changed=c/worker_shim.c");

    let manifest = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("Cargo sets it"));
    let repository = manifest
        .join("../../..")
        .canonicalize()
        .expect("the host crate is inside the Nupp repository");
    let prefix = env::var_os(LUAJIT_PREFIX_ENV)
        .map(PathBuf::from)
        .unwrap_or_else(|| stage_luajit(&repository));

    let library = prefix.join("lib");
    assert!(
        library.is_dir(),
        "the staged LuaJIT has no library directory at {}",
        library.display()
    );
    println!("cargo:rustc-link-search=native={}", library.display());
    compile_shim(&manifest, &prefix, &target());
    // The shim refers to LuaJIT, so keep its archive before LuaJIT on linkers
    // that resolve static archives in a single left-to-right pass.
    println!("cargo:rustc-link-lib=static=luajit-5.1");
    if env::var_os("CARGO_FEATURE_LPEG").is_some() {
        let prefix = PathBuf::from(
            env::var_os("NUPP_LPEG_PREFIX")
                .expect("the lpeg host feature requires NUPP_LPEG_PREFIX"),
        );
        println!(
            "cargo:rustc-link-search=native={}",
            prefix.join("lib").display()
        );
        println!("cargo:rustc-link-lib=static=lpeg");
    }

    let vmdef = lua_module(&prefix, "vmdef");
    let zone = lua_module(&prefix, "zone");
    println!("cargo:rustc-env=NUPP_LUAJIT_VMDEF={}", vmdef.display());
    println!("cargo:rustc-env=NUPP_LUAJIT_ZONE={}", zone.display());

    let target = target();
    if !target.contains("windows") {
        println!("cargo:rustc-link-lib=m");
        println!("cargo:rustc-link-lib=pthread");
    }
    if !target.contains("windows") && !target.contains("apple") {
        println!("cargo:rustc-link-lib=dl");
    }
}

fn target() -> String {
    env::var("TARGET").expect("Cargo sets TARGET")
}

fn compile_shim(manifest: &Path, prefix: &Path, target: &str) {
    let include_file = prefix.join(".include");
    let include = fs::read_to_string(&include_file)
        .unwrap_or_else(|error| panic!("cannot read {}: {error}", include_file.display()));
    let include = include.trim();
    assert!(!include.is_empty(), "{} is empty", include_file.display());
    let output = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo sets it"));
    let object = output.join("lua_shim.o");
    let worker_object = output.join("worker_shim.o");
    let archive = output.join("libnupp_lua_shim.a");
    let compiler = env::var_os("NUPP_CC")
        .or_else(|| env::var_os("CC"))
        .unwrap_or_else(|| {
            if target.contains("windows") {
                "gcc".into()
            } else {
                "cc".into()
            }
        });
    let status = Command::new(&compiler)
        .arg("-c")
        .arg("-std=c11")
        .arg("-O2")
        .arg("-fPIC")
        .arg(format!("-I{include}"))
        .arg("-o")
        .arg(&object)
        .arg(manifest.join("c/lua_shim.c"))
        .status()
        .unwrap_or_else(|error| panic!("cannot run {:?}: {error}", compiler));
    assert!(
        status.success(),
        "the LuaJIT protection shim did not compile"
    );

    let status = Command::new(&compiler)
        .arg("-c")
        .arg("-std=c11")
        .arg("-O2")
        .arg("-fPIC")
        .arg(format!("-I{include}"))
        .arg("-o")
        .arg(&worker_object)
        .arg(manifest.join("c/worker_shim.c"))
        .status()
        .unwrap_or_else(|error| panic!("cannot run {:?}: {error}", compiler));
    assert!(status.success(), "the worker Lua shim did not compile");

    let archiver = env::var_os("AR").unwrap_or_else(|| "ar".into());
    let status = Command::new(&archiver)
        .arg("rcs")
        .arg(&archive)
        .arg(&object)
        .arg(&worker_object)
        .status()
        .unwrap_or_else(|error| panic!("cannot run {:?}: {error}", archiver));
    assert!(
        status.success(),
        "the LuaJIT protection shim did not archive"
    );
    println!("cargo:rustc-link-search=native={}", output.display());
    println!("cargo:rustc-link-lib=static=nupp_lua_shim");
}

fn stage_luajit(repository: &Path) -> PathBuf {
    let driver = repository.join("scripts/toolchain");
    let output = Command::new(&driver)
        .arg("luajit")
        .current_dir(repository)
        .output()
        .unwrap_or_else(|error| panic!("cannot run {}: {error}", driver.display()));
    if !output.status.success() {
        panic!(
            "{} luajit failed:\n{}",
            driver.display(),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    let printed =
        String::from_utf8(output.stdout).expect("scripts/toolchain prints its result as UTF-8");
    let answer = printed
        .lines()
        .rev()
        .find(|line| !line.trim().is_empty())
        .expect("scripts/toolchain luajit named no staged prefix");
    PathBuf::from(answer.trim())
}

fn lua_module(prefix: &Path, name: &str) -> PathBuf {
    let relative = PathBuf::from("jit").join(format!("{name}.lua"));
    let candidates = [
        prefix.join("share/luajit-2.1").join(&relative),
        prefix.join("bin/lua").join(&relative),
    ];
    candidates
        .into_iter()
        .find(|candidate| candidate.is_file())
        .unwrap_or_else(|| {
            panic!(
                "the staged LuaJIT at {} has no jit/{name}.lua",
                prefix.display()
            )
        })
}
