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

    let mut build = cc::Build::new();
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

    if target.contains("windows") {
        // Where the bytes behind a temporary name come from.
        println!("cargo:rustc-link-lib=bcrypt");
    } else {
        // The transfer lane runs its workers on threads.
        println!("cargo:rustc-link-lib=pthread");
    }
}
