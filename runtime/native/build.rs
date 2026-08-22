// Compiles the C half of the native provider.
//
// The provider is being reimplemented in C behind the ABI it already exports
// (see NEP 17). While that is in progress the crate holds both halves: the
// features already ported are C sources compiled here and linked into the same
// library, and the rest are still Rust. The shared surface -- the error slot,
// the returned byte buffer -- belongs to the C side, and the Rust half calls
// into it, so there is one definition of each rather than two that must agree.
//
// When the last feature is ported this file and the crate around it go away, and
// what is left is the C build the toolchain driver already knows how to run.

use std::path::PathBuf;

/// One ported feature: the Cargo feature that selects it, and the C the feature
/// is. `common.c` is not here because it is not optional.
const PORTED: &[(&str, &[&str])] = &[
    ("FILES", &["files.c", "glob.c", "fslane.c"]),
    ("PATH", &["path.c"]),
    ("HTTP", &["http.c"]),
    ("PROCESS", &["process.c"]),
    ("SHA256", &["digest.c"]),
    ("URI", &["uri.c"]),
    ("UUID", &["digest.c"]),
];

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=c");
    for name in ["NUPP_CC", "NUPP_NATIVE_CC"] {
        println!("cargo:rerun-if-env-changed={name}");
    }

    // The error slot and the returned byte buffer are what every facility
    // answers through, ported or not, so they are compiled whatever was
    // selected. The Rust half calls into them rather than defining its own.
    let mut sources: Vec<PathBuf> = vec![PathBuf::from("c/common.c")];
    for (feature, files) in PORTED {
        if std::env::var_os(format!("CARGO_FEATURE_{feature}")).is_none() {
            continue;
        }
        for file in *files {
            // Two features can be the same translation unit, and compiling it
            // twice is two definitions of everything in it.
            let path = PathBuf::from("c").join(file);
            if !sources.contains(&path) {
                sources.push(path);
            }
        }
    }

    let target = std::env::var("TARGET").expect("cargo sets TARGET");
    if target.contains("windows") {
        sources.push(PathBuf::from("c/platform_windows.c"));
    } else {
        sources.push(PathBuf::from("c/platform_posix.c"));
    }

    // The transport stands on the pinned libcurl the toolchain driver builds.
    // Asked for here rather than by the launcher, because this is where it is
    // needed and a build script runs only when the crate rebuilds.
    let curl = if std::env::var_os("CARGO_FEATURE_HTTP").is_some() {
        Some(provision_curl())
    } else {
        None
    };

    let mut build = cc::Build::new();
    if let Some(prefix) = &curl {
        build.include(prefix.join("include"));
    }
    // The archive is named to Cargo below rather than by `cc`, because what it
    // emits is an ordinary static library and every symbol in this one is
    // reached only from Lua. A linker selecting archive members by what the rest
    // of the link already needs would take none of them.
    build.cargo_metadata(false);
    // `NUPP_CC` names the compiler for everything Nupp builds; `cc` reads `CC`.
    // Setting it here rather than leaving the crate to inherit whatever the
    // environment had keeps one answer for the whole tree.
    if let Some(named) = std::env::var_os("NUPP_CC").or_else(|| std::env::var_os("NUPP_NATIVE_CC"))
    {
        build.compiler(named);
    }
    build
        .files(&sources)
        .include("c")
        // gnu11 rather than c11: the POSIX half needs `readlink`, `fsync` and
        // `dirent`, and a strict standard mode hides every one of them.
        .flag_if_supported("-std=gnu11")
        .define("NDEBUG", None)
        .warnings(true)
        .extra_warnings(true)
        .compile("nupp_native_c");

    let out = std::env::var("OUT_DIR").expect("cargo sets OUT_DIR");
    println!("cargo:rustc-link-search=native={out}");
    // `+whole-archive` is what carries the whole thing into a cdylib and into a
    // statically linked host alike. A link modifier travels with the library
    // through a dependency the way a bare link argument does not.
    println!("cargo:rustc-link-lib=static:+whole-archive=nupp_native_c");

    if let Some(prefix) = &curl {
        link_curl(prefix);
    }

    if target.contains("windows") {
        // Where the bytes behind a temporary name come from.
        println!("cargo:rustc-link-lib=bcrypt");
    } else {
        // The transfer lane runs its workers on threads.
        println!("cargo:rustc-link-lib=pthread");
    }
}

/// Builds the pinned libcurl, or finds the build the driver already cached, and
/// answers where it was installed.
fn provision_curl() -> PathBuf {
    let root = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("cargo sets it"))
        .join("../..");
    let driver = root.join("scripts/toolchain");
    let answered = std::process::Command::new("sh")
        .arg(&driver)
        .arg("curl")
        .output()
        .unwrap_or_else(|error| panic!("cannot run {}: {error}", driver.display()));
    if !answered.status.success() {
        panic!(
            "{} could not build libcurl:\n{}",
            driver.display(),
            String::from_utf8_lossy(&answered.stderr)
        );
    }
    let prefix = String::from_utf8(answered.stdout)
        .expect("the driver answers a path")
        .trim()
        .to_owned();
    PathBuf::from(prefix)
}

/// What a static libcurl needs linked beside it, taken from the `curl-config`
/// installed with it rather than guessed: the TLS backend, the platform
/// libraries it reaches, and on Apple the frameworks under those.
fn link_curl(prefix: &std::path::Path) {
    let config = prefix.join("bin/curl-config");
    let answered = std::process::Command::new(&config)
        .arg("--static-libs")
        .output()
        .unwrap_or_else(|error| panic!("cannot run {}: {error}", config.display()));
    let flags = String::from_utf8_lossy(&answered.stdout).into_owned();
    let mut tokens = flags.split_whitespace().peekable();
    while let Some(token) = tokens.next() {
        if let Some(path) = token.strip_prefix("-L") {
            println!("cargo:rustc-link-search=native={path}");
        } else if let Some(name) = token.strip_prefix("-l") {
            println!("cargo:rustc-link-lib={name}");
        } else if token == "-framework" {
            if let Some(name) = tokens.next() {
                println!("cargo:rustc-link-arg=-framework");
                println!("cargo:rustc-link-arg={name}");
            }
        } else if token.ends_with(".a") {
            println!("cargo:rustc-link-arg={token}");
        }
    }
}
