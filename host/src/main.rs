//! The Nupp stub: an executable that runs a payload appended to itself.
//!
//! With a payload it is that program and nothing else. Without one it is a
//! plain Lua interpreter over the file named as its first argument, which is
//! what makes a stub testable before anything has been stamped into it and
//! usable while the thing that stamps is still being written.
//!
//! The container is specified in `docs/distribution.md`; this is its first
//! implementation, and deliberately its simplest.

use std::os::raw::c_int;

use nupp::Runtime;

const EXIT_USAGE: c_int = 2;

fn main() {
    #[cfg(feature = "workers")]
    nupp::reserve_worker_mcode();
    nupp::retain_native_provider();
    let arguments: Vec<String> = std::env::args().collect();
    let status = run(&arguments);
    std::process::exit(status);
}

fn run(arguments: &[String]) -> c_int {
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

    match nupp::read_payload(&exe) {
        Ok(Some(chunk)) => {
            #[cfg(feature = "workers")]
            nupp::set_worker_payload(chunk.clone());
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
        eprintln!(
            "nupp-host: no payload; usage: {} <file.lua> [args...]",
            arguments[0]
        );
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
    let runtime = match Runtime::new(true) {
        Ok(runtime) => runtime,
        Err(_) => {
            eprintln!("nupp: cannot create a Lua state");
            return 1;
        }
    };
    let arguments = forwarded.to_vec();
    if let Err(message) = runtime.set_arguments(&arguments) {
        eprintln!("{message}");
        return 1;
    }
    match runtime.run(chunk, name) {
        Ok(()) => 0,
        Err(message) => {
            eprintln!("{message}");
            1
        }
    }
}
