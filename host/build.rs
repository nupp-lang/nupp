// Builds what the stub embeds: pinned LuaJIT plus whichever pinned C modules
// Cargo features selected for this host variant.
//
// Each is fetched by revision and verified against the digests below before a
// byte of any of them is compiled. LuaJIT used to come from the `luajit-src` crate,
// which pinned it through Cargo.lock; that pin trails upstream by weeks, and
// what Nupp needs is not weeks old. Generated Nupp is written in the LuaJIT 3.0
// syntax that 2.1 backported, so a stub whose interpreter predates the backport
// cannot load the payload it is carrying. The pin here is the requirement,
// stated where it can be read.
//
// None is committed. A generated dependency in the tree is a thing to keep
// current by hand, and the one artifact this project accepts on those terms is
// the bootstrap compiler, which has no alternative.

use std::path::{Path, PathBuf};
use std::process::Command;

const SOURCE_DIR_ENV: &str = "NUPP_HOST_SOURCE_DIR";
const SOURCE_BASE_URL_ENV: &str = "NUPP_HOST_SOURCE_BASE_URL";
const OFFLINE_ENV: &str = "NUPP_HOST_OFFLINE";

const CJSON_VERSION: &str = "2.1.0.14";
const CJSON_SHA256: &str = "14cac5c7a4520b33449a1fc961344556b8b6a2a2c6b739b0e46e3002e6e605bc";

const LPEG_VERSION: &str = "1.1.0";
const LPEG_SHA256: &str = "4b155d67d2246c1ffa7ad7bc466c1ea899bbc40fef0257cc9c03cecbaed4352a";

// Lunamark's entity table needs a utf8.char that Lua 5.1 does not have.
const LUAUTF8_VERSION: &str = "0.2.1";
const LUAUTF8_SHA256: &str = "ea52075cd960aed8c37512ab31cdc166aa77a6458504d29f33ae40b93d2d8594";

// LuaJIT v2.1, at 2.1.1785763465. The floor is 2.1.1784535649, the first build
// carrying the backported operators; anything older rejects generated Nupp at
// parse time.
const LUAJIT_REV: &str = "1edc3e52b67eaf6ce5f809be8e17d6862594b8bc";
const LUAJIT_SHA256: &str = "85497ea149d136afbe2d7ef222e08849248e52cecc6dc8deefd8588e551e4e00";

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    for name in [SOURCE_DIR_ENV, SOURCE_BASE_URL_ENV, OFFLINE_ENV] {
        println!("cargo:rerun-if-env-changed={name}");
    }

    export_native_provider();

    let out = PathBuf::from(std::env::var("OUT_DIR").expect("cargo sets OUT_DIR"));
    let luajit = build_luajit(&out);
    verify_notice(&luajit.join("COPYRIGHT"), "LuaJIT-COPYRIGHT.txt");
    let include = luajit.join("src");
    println!(
        "cargo:rustc-env=NUPP_LUAJIT_VMDEF={}",
        include.join("jit/vmdef.lua").display()
    );

    // ENABLE_CJSON_GLOBAL is off: the compiler reaches cjson through require,
    // and a global installed by the host would be present in a stamped binary
    // and absent under a plain interpreter, so the same program would see two
    // different worlds depending on how it was started.
    if enabled("CJSON") {
        let cjson = fetch_cjson(&out);
        verify_notice(&cjson.join("LICENSE"), "lua-cjson-LICENSE.txt");
        cc::Build::new()
            .include(&include)
            .include(&cjson)
            .file(cjson.join("lua_cjson.c"))
            .file(cjson.join("strbuf.c"))
            .file(cjson.join("fpconv.c"))
            .define("NDEBUG", None)
            .warnings(false)
            .compile("lua_cjson");
    }

    if enabled("LPEG") {
        let lpeg = fetch_archive(
            &out,
            &format!("lpeg-{LPEG_VERSION}"),
            &format!("https://www.inf.puc-rio.br/~roberto/lpeg/lpeg-{LPEG_VERSION}.tar.gz"),
            LPEG_SHA256,
            "lptree.c",
        );
        verify_embedded_notice(&lpeg.join("lpeg.html"), "LPeg-LICENSE.txt");
        cc::Build::new()
            .include(&include)
            .include(&lpeg)
            .files([
                lpeg.join("lpvm.c"),
                lpeg.join("lpcap.c"),
                lpeg.join("lptree.c"),
                lpeg.join("lpcode.c"),
                lpeg.join("lpprint.c"),
                lpeg.join("lpcset.c"),
            ])
            .define("NDEBUG", None)
            .warnings(false)
            .compile("lpeg");
    }

    if enabled("LUA_UTF8") {
        let luautf8 = fetch_archive(
            &out,
            &format!("luautf8-{LUAUTF8_VERSION}"),
            &format!(
                "https://github.com/starwing/luautf8/archive/refs/tags/{LUAUTF8_VERSION}.tar.gz"
            ),
            LUAUTF8_SHA256,
            "lutf8lib.c",
        );
        verify_notice(&luautf8.join("LICENSE"), "luautf8-LICENSE.txt");
        cc::Build::new()
            .include(&include)
            .file(luautf8.join("lutf8lib.c"))
            .define("NDEBUG", None)
            .warnings(false)
            .compile("lua_utf8");
    }

    println!("cargo:rustc-link-search=native={}", include.display());
    if std::env::var("TARGET").expect("cargo sets TARGET").contains("msvc") {
        let library = include.join(static_library_name());
        assert!(library.is_file(), "LuaJIT did not write {}", library.display());
        println!("cargo:rustc-link-arg={}", library.display());
    } else {
        println!("cargo:rustc-link-lib=static=luajit");
    }
    for library in link_libraries() {
        println!("cargo:rustc-link-lib={library}");
    }
    println!("cargo:include={}", include.display());
}

const NATIVE_COMMON_SYMBOLS: &[&str] = &[
    "nuppNativeError",
    "nuppBytesData",
    "nuppBytesLength",
    "nuppBytesDestroy",
];

const NATIVE_FILES_SYMBOLS: &[&str] = &[
    "nuppFilesInfo",
    "nuppFilesReadLink",
    "nuppFilesCreateSymlink",
    "nuppFilesSetReadOnly",
    "nuppFilesCreateDirectory",
    "nuppFilesRemove",
    "nuppFilesRename",
    "nuppFilesList",
    "nuppFilesGlob",
    "nuppFilesCreateTemporary",
    "nuppFilesCurrentDirectory",
    "nuppFilesUserFolder",
    "nuppFileOpen",
    "nuppFileRead",
    "nuppFileWrite",
    "nuppFileSeek",
    "nuppFileSize",
    "nuppFileFlush",
    "nuppFileClose",
    "nuppFsSubmitRead",
    "nuppFsSubmitWrite",
    "nuppFsSubmitCopy",
    "nuppFsStatus",
    "nuppFsData",
    "nuppFsLength",
    "nuppFsError",
    "nuppFsCancel",
    "nuppFsDestroy",
    "nuppFsPoll",
    "nuppFsWait",
    "nuppFsPending",
];

const NATIVE_PROCESS_SYMBOLS: &[&str] = &[
    "nuppProcessMonotonicMs",
    "nuppProcessSpawnBegin",
    "nuppProcessSpawnArg",
    "nuppProcessSpawnEnv",
    "nuppProcessSpawnClearEnv",
    "nuppProcessSpawnCwd",
    "nuppProcessSpawnStdio",
    "nuppProcessSpawnCancel",
    "nuppProcessSpawnRun",
    "nuppProcessTakeStream",
    "nuppProcessTryRead",
    "nuppProcessTryWrite",
    "nuppProcessCloseStream",
    "nuppProcessStreamDestroy",
    "nuppProcessPollExit",
    "nuppProcessId",
    "nuppProcessKill",
    "nuppProcessReap",
    "nuppProcessUncollectedTotal",
    "nuppProcessDestroy",
    "nuppProcessWaitReady",
];

/// Makes statically linked provider functions visible to LuaJIT's `ffi.C`.
///
/// Each named undefined symbol also keeps that function alive when the linker
/// garbage-collects sections from the provider rlib. Windows' export directive
/// does both jobs; ELF and Mach-O need an export-all flag beside their roots.
fn export_native_provider() {
    let files = enabled("NATIVE_FILES");
    let process = enabled("NATIVE_PROCESS");
    if !files && !process {
        return;
    }

    let target = std::env::var("TARGET").expect("cargo sets TARGET");
    let mut symbols = NATIVE_COMMON_SYMBOLS.to_vec();
    if files {
        symbols.extend_from_slice(NATIVE_FILES_SYMBOLS);
    }
    if process {
        symbols.extend_from_slice(NATIVE_PROCESS_SYMBOLS);
    }

    if target.contains("msvc") {
        for symbol in symbols {
            println!("cargo:rustc-link-arg=/EXPORT:{symbol}");
        }
    } else if target.contains("apple") {
        println!("cargo:rustc-link-arg=-Wl,-export_dynamic");
        for symbol in symbols {
            println!("cargo:rustc-link-arg=-Wl,-u,_{symbol}");
        }
    } else {
        println!("cargo:rustc-link-arg=-Wl,--export-dynamic");
        for symbol in symbols {
            println!("cargo:rustc-link-arg=-Wl,-u,{symbol}");
        }
    }
}

fn enabled(name: &str) -> bool {
    std::env::var_os(format!("CARGO_FEATURE_{name}")).is_some()
}

/// Fetches and builds the pinned LuaJIT, returning its source root. The static
/// library and the headers both live in `src/` there, which is where LuaJIT's
/// own makefile leaves them.
fn build_luajit(out: &Path) -> PathBuf {
    let directory = format!("LuaJIT-{LUAJIT_REV}");
    let root = out.join(&directory);
    let library = root.join("src").join(static_library_name());
    if library.exists() {
        return root;
    }

    let url = format!("https://github.com/LuaJIT/LuaJIT/archive/{LUAJIT_REV}.tar.gz");
    extract_archive(out, &directory, &url, LUAJIT_SHA256, "src/lj_arch.h");

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
        let mut path = vec![cl
            .path()
            .parent()
            .expect("cl.exe has a tool directory")
            .to_path_buf()];
        path.extend(std::env::split_paths(
            &std::env::var_os("PATH").unwrap_or_default(),
        ));
        build.env(
            "PATH",
            std::env::join_paths(path).expect("the MSVC tool path is valid"),
        );
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
    extract_archive(out, directory, url, digest, marker)
}

/// Finds one exact pinned source archive and extracts it into Cargo's output.
///
/// An existing extraction or output-directory archive is the nearest cache. A
/// directory named by `NUPP_HOST_SOURCE_DIR` comes next, so an offline builder,
/// package manager or CI cache can supply the same immutable archives without
/// teaching Cargo about their layout. Only a miss reaches the network. A mirror
/// may replace the URL prefix, but never the digest which authenticates the
/// selected bytes.
fn extract_archive(out: &Path, directory: &str, url: &str, digest: &str, marker: &str) -> PathBuf {
    let extracted = out.join(directory);
    if extracted.join(marker).exists() {
        return extracted;
    }

    let archive_name = format!("{directory}.tar.gz");
    let cached = out.join(&archive_name);
    let archive = if cached.is_file() {
        cached
    } else if let Some(source_dir) = source_directory() {
        let supplied = source_dir.join(&archive_name);
        if supplied.is_file() {
            supplied
        } else if offline() {
            panic!(
                "{OFFLINE_ENV} is enabled and {archive_name} is not in {}; \
                 supply the pinned archive there or disable offline mode",
                source_dir.display()
            );
        } else {
            download_archive(out, &archive_name, archive_url(url, &archive_name), digest)
        }
    } else if offline() {
        panic!(
            "{OFFLINE_ENV} is enabled and {archive_name} is not cached; set \
             {SOURCE_DIR_ENV} to a directory containing the pinned archive"
        );
    } else {
        download_archive(out, &archive_name, archive_url(url, &archive_name), digest)
    };

    let found = sha256(&archive);
    assert_eq!(
        found, digest,
        "{directory} does not match its pinned digest; refusing to compile \
         something other than what this build was written against"
    );

    run(Command::new("tar").arg("xzf").arg(&archive).arg("-C").arg(out));
    assert!(
        extracted.join(marker).is_file(),
        "{archive_name} did not extract the expected {directory}/{marker}"
    );
    extracted
}

/// The optional directory holding already downloaded source archives. Relative
/// paths are resolved from the host crate, not from whichever directory invoked
/// Cargo, so the same setting means the same thing in every build frontend.
fn source_directory() -> Option<PathBuf> {
    let configured = std::env::var_os(SOURCE_DIR_ENV)?;
    assert!(!configured.is_empty(), "{SOURCE_DIR_ENV} must not be empty");
    let path = PathBuf::from(configured);
    if path.is_absolute() {
        Some(path)
    } else {
        Some(
            PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("cargo sets it"))
                .join(path),
        )
    }
}

/// Replaces the upstream location with a flat mirror when one is configured.
fn archive_url(upstream: &str, archive_name: &str) -> String {
    match std::env::var(SOURCE_BASE_URL_ENV) {
        Ok(base) => {
            let base = base.trim_end_matches('/');
            assert!(!base.is_empty(), "{SOURCE_BASE_URL_ENV} must not be empty");
            format!("{base}/{archive_name}")
        }
        Err(std::env::VarError::NotPresent) => upstream.to_owned(),
        Err(error) => panic!("cannot read {SOURCE_BASE_URL_ENV}: {error}"),
    }
}

/// Downloads into a temporary sibling, verifies it, then installs it as a cache
/// entry. A failed transfer or digest never becomes a file a later build trusts.
fn download_archive(out: &Path, archive_name: &str, url: String, digest: &str) -> PathBuf {
    let archive = out.join(archive_name);
    let temporary = out.join(format!(
        ".{archive_name}.{}.download",
        std::process::id()
    ));
    let _ = std::fs::remove_file(&temporary);
    let status = Command::new("curl")
        .args(["--fail", "--location", "--silent", "--show-error", "--output"])
        .arg(&temporary)
        .arg(&url)
        .status()
        .unwrap_or_else(|error| panic!("cannot download {url} with curl: {error}"));
    if !status.success() {
        let _ = std::fs::remove_file(&temporary);
        panic!("cannot download {url}: curl failed with {status}");
    }
    let found = sha256(&temporary);
    if found != digest {
        let _ = std::fs::remove_file(&temporary);
        panic!(
            "{archive_name} downloaded from {url} has digest {found}, expected \
             {digest}; refusing to cache or compile it"
        );
    }
    std::fs::rename(&temporary, &archive).unwrap_or_else(|error| {
        panic!(
            "cannot install downloaded {archive_name} at {}: {error}",
            archive.display()
        )
    });
    archive
}

fn offline() -> bool {
    let Some(value) = std::env::var_os(OFFLINE_ENV) else {
        return false;
    };
    match value.to_string_lossy().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => true,
        "0" | "false" | "no" | "off" => false,
        _ => panic!(
            "{OFFLINE_ENV} must be one of 1, true, yes, on, 0, false, no or off"
        ),
    }
}

/// Holds `host/notices` to what the pinned sources actually say.
///
/// Each of these is MIT, and MIT asks that its notice travel with the copies.
/// The sources are fetched rather than committed, so the only copy this
/// repository can ship is the one in `host/notices` -- and a copy that has
/// drifted from the source it claims to reproduce is worse than no copy at all,
/// because it is a false statement about what was distributed. Bumping a pin
/// therefore fails the build until the notice beside it is updated too.
fn verify_notice(source: &Path, notice: &str) {
    let committed = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("cargo sets it"))
        .join("notices")
        .join(notice);
    println!("cargo:rerun-if-changed=notices/{notice}");

    let found = std::fs::read(source)
        .unwrap_or_else(|error| panic!("cannot read {}: {error}", source.display()));
    let shipped = std::fs::read(&committed)
        .unwrap_or_else(|error| panic!("cannot read {}: {error}", committed.display()));
    assert!(
        found == shipped,
        "host/notices/{notice} is not what {} says any more. Copy it across: \
         the pinned source is what is distributed, and the notice beside it is \
         what says so.",
        source.display()
    );
}

fn verify_embedded_notice(source: &Path, notice: &str) {
    let committed = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("cargo sets it"))
        .join("notices")
        .join(notice);
    println!("cargo:rerun-if-changed=notices/{notice}");

    let found = std::fs::read_to_string(source)
        .unwrap_or_else(|error| panic!("cannot read {}: {error}", source.display()));
    let shipped = std::fs::read_to_string(&committed)
        .unwrap_or_else(|error| panic!("cannot read {}: {error}", committed.display()));
    for text in [
        "2007-2023 Lua.org, PUC-Rio",
        "Permission is hereby granted",
        "THE SOFTWARE IS PROVIDED \"AS IS\"",
    ] {
        assert!(
            found.contains(text) && shipped.contains(text),
            "host/notices/{notice} no longer agrees with {}",
            source.display()
        );
    }
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
