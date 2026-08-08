// Builds what the stub embeds: a pinned LuaJIT, and the pinned C libraries the
// compiler cannot start or document itself without, linked against it.
//
// Each is fetched by revision and verified against the digests below before a
// byte of any of them is compiled. LuaJIT used to come from the `luajit-src` crate,
// which pinned it through Cargo.lock; that pin trails upstream by weeks, and
// what Nupp needs is not weeks old. Generated Nupp is written in the LuaJIT 3.0
// syntax that 2.1 backported, so a stub whose interpreter predates the backport
// cannot load the payload it is carrying. The pin here is the requirement,
// stated where it can be read.
//
// Neither is committed. A generated dependency in the tree is a thing to keep
// current by hand, and the one artifact this project accepts on those terms is
// the bootstrap compiler, which has no alternative.

use std::path::{Path, PathBuf};
use std::process::Command;

const CJSON_VERSION: &str = "2.1.0.14";
const CJSON_SHA256: &str = "14cac5c7a4520b33449a1fc961344556b8b6a2a2c6b739b0e46e3002e6e605bc";

// What `nupp doc` renders with. lunamark's grammar is LPeg, and its entity
// table needs a utf8.char that Lua 5.1 does not have; neither is optional, so a
// binary without them is a binary whose documentation command does not run.
// Both are MIT, both are one small C library, and both are reached through
// require exactly as they would be from a rock tree.
const LPEG_VERSION: &str = "1.1.0";
const LPEG_SHA256: &str = "4b155d67d2246c1ffa7ad7bc466c1ea899bbc40fef0257cc9c03cecbaed4352a";

const LUAUTF8_VERSION: &str = "0.2.1";
const LUAUTF8_SHA256: &str = "ea52075cd960aed8c37512ab31cdc166aa77a6458504d29f33ae40b93d2d8594";

// LuaJIT v2.1, at 2.1.1785763465. The floor is 2.1.1784535649, the first build
// carrying the backported operators; anything older rejects generated Nupp at
// parse time.
const LUAJIT_REV: &str = "1edc3e52b67eaf6ce5f809be8e17d6862594b8bc";
const LUAJIT_SHA256: &str = "85497ea149d136afbe2d7ef222e08849248e52cecc6dc8deefd8588e551e4e00";

fn main() {
    println!("cargo:rerun-if-changed=build.rs");

    let out = PathBuf::from(std::env::var("OUT_DIR").expect("cargo sets OUT_DIR"));
    let luajit = build_luajit(&out);
    let include = luajit.join("src");
    let cjson = fetch_cjson(&out);

    // ENABLE_CJSON_GLOBAL is off: the compiler reaches cjson through require,
    // and a global installed by the host would be present in a stamped binary
    // and absent under a plain interpreter, so the same program would see two
    // different worlds depending on how it was started.
    cc::Build::new()
        .include(&include)
        .include(&cjson)
        .file(cjson.join("lua_cjson.c"))
        .file(cjson.join("strbuf.c"))
        .file(cjson.join("fpconv.c"))
        .define("NDEBUG", None)
        .warnings(false)
        .compile("lua_cjson");

    let lpeg = fetch_archive(
        &out,
        &format!("lpeg-{LPEG_VERSION}"),
        &format!("https://www.inf.puc-rio.br/~roberto/lpeg/lpeg-{LPEG_VERSION}.tar.gz"),
        LPEG_SHA256,
        "lptree.c",
    );
    cc::Build::new()
        .include(&include)
        .files(
            ["lpcap.c", "lpcode.c", "lpcset.c", "lpprint.c", "lptree.c", "lpvm.c"]
                .iter()
                .map(|name| lpeg.join(name)),
        )
        .define("NDEBUG", None)
        .warnings(false)
        .compile("lpeg");

    let luautf8 = fetch_archive(
        &out,
        &format!("luautf8-{LUAUTF8_VERSION}"),
        &format!(
            "https://github.com/starwing/luautf8/archive/refs/tags/{LUAUTF8_VERSION}.tar.gz"
        ),
        LUAUTF8_SHA256,
        "lutf8lib.c",
    );
    cc::Build::new()
        .include(&include)
        .file(luautf8.join("lutf8lib.c"))
        .define("NDEBUG", None)
        .warnings(false)
        .compile("lua_utf8");

    println!("cargo:rustc-link-search=native={}", include.display());
    println!("cargo:rustc-link-lib=static=luajit");
    for library in link_libraries() {
        println!("cargo:rustc-link-lib={library}");
    }
    println!("cargo:include={}", include.display());
}

/// Fetches and builds the pinned LuaJIT, returning its source root. The static
/// library and the headers both live in `src/` there, which is where LuaJIT's
/// own makefile leaves them.
fn build_luajit(out: &Path) -> PathBuf {
    let root = out.join(format!("LuaJIT-{LUAJIT_REV}"));
    let library = root.join("src").join(static_library_name());
    if library.exists() {
        return root;
    }

    let archive = out.join("luajit.tar.gz");
    let url = format!("https://github.com/LuaJIT/LuaJIT/archive/{LUAJIT_REV}.tar.gz");
    run(Command::new("curl").args(["-sSL", "-o"]).arg(&archive).arg(&url));

    let digest = sha256(&archive);
    assert_eq!(
        digest, LUAJIT_SHA256,
        "LuaJIT {LUAJIT_REV} does not match its pinned digest; refusing to \
         compile something other than what this build was written against"
    );
    run(Command::new("tar").arg("xzf").arg(&archive).arg("-C").arg(out));

    let target = std::env::var("TARGET").expect("cargo sets TARGET");
    if target.contains("msvc") {
        // msvcbuild.bat wants the compiler environment cc would have set up,
        // and it writes its output beside itself, which is where the rest of
        // this build looks for it.
        let source = root.join("src");
        let mut build = Command::new(source.join("msvcbuild.bat"));
        build.current_dir(&source).arg("static");
        let cl = cc::windows_registry::find_tool(&target, "cl.exe")
            .expect("the MSVC toolchain that builds this crate also builds LuaJIT");
        for (key, value) in cl.env() {
            build.env(key, value);
        }
        run(&mut build);
        return root;
    }

    let mut make = Command::new(if target.contains("freebsd") || target.contains("dragonfly") {
        "gmake"
    } else {
        "make"
    });
    make.arg("-C")
        .arg(root.join("src"))
        // A static library linked into a Rust binary is relocated like every
        // other object in it.
        .arg("BUILDMODE=static")
        .arg("XCFLAGS=-fPIC");
    // LuaJIT refuses to guess a deployment target, and would rather stop than
    // produce something that runs here and nowhere else.
    if target.contains("apple") && std::env::var_os("MACOSX_DEPLOYMENT_TARGET").is_none() {
        make.env(
            "MACOSX_DEPLOYMENT_TARGET",
            if target.starts_with("x86_64") { "10.14" } else { "11.0" },
        );
    }
    run(&mut make);
    root
}

fn static_library_name() -> &'static str {
    let target = std::env::var("TARGET").expect("cargo sets TARGET");
    if target.contains("msvc") { "lua51.lib" } else { "libluajit.a" }
}

/// What LuaJIT itself needs from the platform.
fn link_libraries() -> &'static [&'static str] {
    let target = std::env::var("TARGET").expect("cargo sets TARGET");
    if target.contains("msvc") || target.contains("windows") {
        &[]
    } else if target.contains("apple") {
        &["m"]
    } else {
        &["m", "dl"]
    }
}

/// The extracted lua-cjson source, fetched once per output directory.
fn fetch_cjson(out: &Path) -> PathBuf {
    fetch_archive(
        out,
        &format!("lua-cjson-{CJSON_VERSION}"),
        &format!(
            "https://github.com/openresty/lua-cjson/archive/refs/tags/{CJSON_VERSION}.tar.gz"
        ),
        CJSON_SHA256,
        "lua_cjson.c",
    )
}

/// One pinned source archive, extracted once per output directory. `marker` is a
/// file the archive is known to contain, which is how an extraction that already
/// happened is told from one that has not; `digest` is checked before anything
/// is unpacked, so a mirror that served something else is refused rather than
/// compiled.
fn fetch_archive(out: &Path, directory: &str, url: &str, digest: &str, marker: &str) -> PathBuf {
    let extracted = out.join(directory);
    if extracted.join(marker).exists() {
        return extracted;
    }

    let archive = out.join(format!("{directory}.tar.gz"));
    run(Command::new("curl").args(["-sSL", "-o"]).arg(&archive).arg(url));

    let found = sha256(&archive);
    assert_eq!(
        found, digest,
        "{directory} does not match its pinned digest; refusing to compile \
         something other than what this build was written against"
    );

    run(Command::new("tar").arg("xzf").arg(&archive).arg("-C").arg(out));
    extracted
}

fn sha256(path: &Path) -> String {
    let bytes = std::fs::read(path).expect("the archive was just written");
    let mut hasher = <sha2::Sha256 as sha2::Digest>::new();
    sha2::Digest::update(&mut hasher, &bytes);
    sha2::Digest::finalize(hasher)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn run(command: &mut Command) {
    let status = command
        .status()
        .unwrap_or_else(|error| panic!("cannot run {command:?}: {error}"));
    assert!(status.success(), "{command:?} failed with {status}");
}
