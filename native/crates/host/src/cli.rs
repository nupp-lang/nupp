use crate::{HostRuntime, read_payload};
#[cfg(all(feature = "application-entry", not(test)))]
use std::ffi::c_char;
use std::ffi::{OsString, c_int};
use std::path::{Path, PathBuf};

const EXIT_FAILURE: c_int = 1;
const EXIT_USAGE: c_int = 2;

#[doc(hidden)]
pub fn run_environment() -> c_int {
    run(std::env::current_exe(), std::env::args_os().collect())
}

fn run(executable: std::io::Result<PathBuf>, arguments: Vec<OsString>) -> c_int {
    let executable = match executable {
        Ok(executable) => executable,
        Err(_) => {
            eprintln!("nupp: cannot locate this executable");
            return EXIT_FAILURE;
        }
    };
    let mut arguments = arguments.into_iter();
    let invoked = arguments
        .next()
        .unwrap_or_else(|| executable.clone().into_os_string());
    let payload = match read_payload(&executable) {
        Ok(payload) => payload,
        Err(error) => {
            eprintln!("nupp: {error}");
            return EXIT_FAILURE;
        }
    };
    let (chunk, name, forwarded, stamped) = match payload {
        Some(payload) => (
            payload.bytes().to_vec(),
            format!("@{}", executable.display()),
            arguments.map(os_bytes).collect::<Vec<_>>(),
            true,
        ),
        None => {
            let Some(file) = arguments.next() else {
                eprintln!(
                    "nupp-host: no payload; usage: {} <file.lua> [args...]",
                    Path::new(&invoked).display()
                );
                return EXIT_USAGE;
            };
            let path = PathBuf::from(&file);
            let chunk = match std::fs::read(&path) {
                Ok(chunk) => chunk,
                Err(_) => {
                    eprintln!("nupp-host: cannot read {}", path.display());
                    return EXIT_FAILURE;
                }
            };
            (
                chunk,
                format!("@{}", path.display()),
                arguments.map(os_bytes).collect::<Vec<_>>(),
                false,
            )
        }
    };
    HostRuntime::reserve_worker_mcode();
    let mut runtime = match HostRuntime::new(&executable) {
        Ok(runtime) => runtime,
        Err(error) => {
            eprintln!("nupp: {error}");
            return EXIT_FAILURE;
        }
    };
    #[cfg(feature = "workers")]
    if stamped {
        if let Err(error) = runtime.enable_workers(&chunk) {
            eprintln!("nupp: {error}");
            return EXIT_FAILURE;
        }
    }
    #[cfg(not(feature = "workers"))]
    let _ = stamped;
    if let Err(error) = runtime.run_buffer(&chunk, &name, &forwarded) {
        eprintln!("{error}");
        return EXIT_FAILURE;
    }
    if let Err(error) = runtime.shutdown() {
        eprintln!("nupp: {error}");
        return EXIT_FAILURE;
    }
    0
}

#[cfg(unix)]
fn os_bytes(value: OsString) -> Vec<u8> {
    use std::os::unix::ffi::OsStringExt;
    value.into_vec()
}

#[cfg(not(unix))]
fn os_bytes(value: OsString) -> Vec<u8> {
    value.to_string_lossy().into_owned().into_bytes()
}

#[cfg(all(feature = "application-entry", not(test)))]
#[unsafe(no_mangle)]
pub extern "C" fn main(_argc: c_int, _argv: *const *const c_char) -> c_int {
    run_environment()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unstamped_host_requires_a_file() {
        let executable = std::env::current_exe().unwrap();
        assert_eq!(
            run(Ok(executable.clone()), vec![executable.into_os_string()]),
            EXIT_USAGE
        );
    }

    #[test]
    fn unstamped_host_preserves_file_name_and_arguments() {
        let mut source = std::env::temp_dir();
        source.push(format!("nupp-host-cli-{}.lua", std::process::id()));
        let renamed = source.with_file_name("cli fixture.lua");
        std::fs::write(
            &renamed,
            "assert(debug.getinfo(1, 'S').source == '@' .. arg[1]); assert(arg[2] == 'one' and arg[3] == 'two')",
        )
        .unwrap();
        let executable = std::env::current_exe().unwrap();
        let status = run(
            Ok(executable.clone()),
            vec![
                executable.into_os_string(),
                renamed.clone().into_os_string(),
                renamed.clone().into_os_string(),
                OsString::from("one"),
                OsString::from("two"),
            ],
        );
        std::fs::remove_file(renamed).unwrap();
        assert_eq!(status, 0);
    }
}
