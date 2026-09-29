use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const LUAJIT_PREFIX_ENV: &str = "NUPP_LUAJIT_PREFIX";
/// Where `scripts/toolchain` wants this build's resolved export list, for the
/// Linux link of `libnupp.so` it makes from the static archive.
const EXPORT_LIST_ENV: &str = "NUPP_EXPORT_LIST";

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
    println!("cargo:rerun-if-changed=../../../host/include/nupp.exports");
    println!("cargo:rerun-if-env-changed={EXPORT_LIST_ENV}");

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
    if target().contains("apple") {
        // Darwin's linker can still prefer a sibling dylib for a `static=`
        // native library when one rustc invocation emits both a staticlib and
        // a cdylib. Force the pinned archive into linked outputs, then discard
        // the unused dylib load command so the embedding SDK does not retain a
        // content-cache path at runtime. The `rustc-link-lib` line above still
        // makes Cargo bundle LuaJIT into the staticlib output.
        println!(
            "cargo:rustc-link-arg=-Wl,-force_load,{}",
            library.join("libluajit-5.1.a").display()
        );
        println!("cargo:rustc-link-arg=-Wl,-dead_strip_dylibs");
    }
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

    export_list(&repository, &prefix, &target());

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

/// The symbols `host/include/nupp.exports` names for this build's features,
/// with the LuaJIT version symbol resolved from the staged header.
fn exported_symbols(repository: &Path, prefix: &Path) -> Vec<String> {
    let list = repository.join("host/include/nupp.exports");
    let text = fs::read_to_string(&list)
        .unwrap_or_else(|error| panic!("cannot read {}: {error}", list.display()));
    let version = luajit_version_symbol(prefix);
    let mut symbols = Vec::new();
    let mut applies = false;
    for line in text.lines().map(str::trim) {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(section) = line
            .strip_prefix('[')
            .and_then(|rest| rest.strip_suffix(']'))
        {
            applies = section.split_whitespace().any(|feature| {
                feature == "always" || {
                    let variable = format!(
                        "CARGO_FEATURE_{}",
                        feature.to_ascii_uppercase().replace('-', "_")
                    );
                    env::var_os(variable).is_some()
                }
            });
            continue;
        }
        if applies {
            symbols.push(if line == "LUAJIT_VERSION_SYM" {
                version.clone()
            } else {
                line.to_owned()
            });
        }
    }
    symbols
}

fn luajit_version_symbol(prefix: &Path) -> String {
    let include_file = prefix.join(".include");
    let include = fs::read_to_string(&include_file)
        .unwrap_or_else(|error| panic!("cannot read {}: {error}", include_file.display()));
    let header = PathBuf::from(include.trim()).join("luajit.h");
    let text = fs::read_to_string(&header)
        .unwrap_or_else(|error| panic!("cannot read {}: {error}", header.display()));
    text.lines()
        .find_map(|line| line.strip_prefix("#define LUAJIT_VERSION_SYM"))
        .map(|name| name.trim().to_owned())
        .unwrap_or_else(|| panic!("{} defines no LUAJIT_VERSION_SYM", header.display()))
}

/// Gives each linker the committed export list in the form it reads.
///
/// rustc already exports a cdylib's Rust symbols; the list adds LuaJIT's C API,
/// which rustc cannot see, and names everything else so that a symbol missing
/// from the build is a link error rather than an absent export. On macOS the
/// executable exports exactly the list too. Linux cannot take a second version
/// script beside rustc's, so `scripts/toolchain` links `libnupp.so` itself from
/// the static archive with the list this writes.
fn export_list(repository: &Path, prefix: &Path, target: &str) {
    let symbols = exported_symbols(repository, prefix);
    let output = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo sets it"));
    if let Some(path) = env::var_os(EXPORT_LIST_ENV) {
        write(Path::new(&path), &symbols.join("\n"));
    }
    if target.contains("apple") {
        let list = output.join("nupp.exports.darwin");
        let names: Vec<String> = symbols.iter().map(|name| format!("_{name}")).collect();
        write(&list, &names.join("\n"));
        let argument = format!("-Wl,-exported_symbols_list,{}", list.display());
        println!("cargo:rustc-cdylib-link-arg={argument}");
        println!("cargo:rustc-link-arg-bins={argument}");
    } else if target.contains("windows") {
        // rustc's own module definition file already exports the Rust half,
        // so this one names only what it cannot.
        let definition = output.join("nupp-lua.def");
        let names: Vec<&str> = symbols
            .iter()
            .map(String::as_str)
            .filter(|name| name.starts_with("lua"))
            .collect();
        write(
            &definition,
            &format!("EXPORTS\n    {}", names.join("\n    ")),
        );
        println!("cargo:rustc-cdylib-link-arg={}", definition.display());
    }
}

fn write(path: &Path, text: &str) {
    fs::write(path, format!("{text}\n"))
        .unwrap_or_else(|error| panic!("cannot write {}: {error}", path.display()));
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
        // The shims are the type firewall between two independently compiled
        // ABIs. Refuse implicit or mismatched declarations instead of allowing
        // a pointer-width/signature mistake to survive into the static archive.
        .arg("-Wall")
        .arg("-Wextra")
        .arg("-Werror=implicit-function-declaration")
        .arg("-Werror=incompatible-pointer-types")
        .arg("-Werror=return-type")
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
        .arg("-Wall")
        .arg("-Wextra")
        .arg("-Werror=implicit-function-declaration")
        .arg("-Werror=incompatible-pointer-types")
        .arg("-Werror=return-type")
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
