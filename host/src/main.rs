//! The Nupp stub: an executable that runs a payload appended to itself.
//!
//! With a payload it is that program and nothing else. Without one it is a
//! plain Lua interpreter over the file named as its first argument, which is
//! what makes a stub testable before anything has been stamped into it and
//! usable while the thing that stamps is still being written.
//!
//! The container is specified in `docs/distribution.md`; this is its first
//! implementation, and deliberately its simplest.

use sha2::{Digest, Sha256};
use std::os::raw::c_int;

mod lua;
#[cfg(feature = "workers")]
mod mcode;
mod payload;
#[cfg(feature = "workers")]
mod workers;

use lua::Lua;

const EXIT_USAGE: c_int = 2;

fn main() {
    #[cfg(feature = "workers")]
    mcode::reserve();
    let arguments: Vec<String> = std::env::args().collect();
    let status = run(&arguments);
    std::process::exit(status);
}

fn run(arguments: &[String]) -> c_int {
    // Give release LTO real references to the selected provider entry points.
    // build.rs exports those retained symbols so LuaJIT resolves them via ffi.C.
    #[cfg(any(feature = "native-files", feature = "native-process"))]
    nupp_native::retain_c_abi_exports();

    let exe = match std::env::current_exe() {
        Ok(path) => path,
        Err(error) => {
            // Everything below needs to read this file. A stub that cannot
            // find itself cannot know whether it has a payload, and guessing
            // from arg[0] is how you end up running the wrong file.
            eprintln!("nupp: cannot locate this executable: {error}");
            return 1;
        }
    };

    match payload::read(&exe) {
        Ok(Some(chunk)) => {
            #[cfg(feature = "workers")]
            workers::set_payload(chunk.clone());
            let name = format!("@{}", exe.display());
            execute(&chunk, &name, &arguments[1..])
        }
        Ok(None) => interpret(arguments),
        Err(error) => {
            eprintln!("nupp: {error}");
            1
        }
    }
}

/// No payload: run the Lua file named first, so a stub is useful on its own.
fn interpret(arguments: &[String]) -> c_int {
    if arguments.len() < 2 {
        eprintln!("nupp-host: no payload; usage: {} <file.lua> [args...]", arguments[0]);
        return EXIT_USAGE;
    }
    let path = &arguments[1];
    let chunk = match std::fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) => {
            eprintln!("nupp-host: cannot read {path}: {error}");
            return 1;
        }
    };
    execute(&chunk, &format!("@{path}"), &arguments[2..])
}

/// Loads and runs one chunk, with `arg` set from `forwarded`.
fn execute(chunk: &[u8], name: &str, forwarded: &[String]) -> c_int {
    let lua = match Lua::new() {
        Some(lua) => lua,
        None => {
            eprintln!("nupp: cannot create a Lua state");
            return 1;
        }
    };
    lua.open_libraries();
    lua.set_arg(forwarded);
    match lua.run(chunk, name) {
        Ok(()) => 0,
        Err(message) => {
            eprintln!("{message}");
            1
        }
    }
}

/// The first eight bytes of a payload's SHA-256, as the trailer records it.
pub fn digest_prefix(bytes: &[u8]) -> [u8; 8] {
    let digest = Sha256::digest(bytes);
    let mut prefix = [0u8; 8];
    prefix.copy_from_slice(&digest[..8]);
    prefix
}
