use nupp_native_host::{HostRuntime, read_payload};
use std::path::Path;

const SMOKE: &[u8] = b"assert(__nuppHost.hostAbi == 1); assert(type(__nuppHost.hostFeatures) == 'table'); assert(type(__NUPP_EXECUTABLE) == 'string')";

fn main() {
    if let Err(error) = run() {
        eprintln!("nupp-host-rust: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let executable = std::env::current_exe()?;
    let mut runtime = HostRuntime::new(&executable)?;
    let mut arguments = std::env::args_os().skip(1);
    if let Some(payload) = read_payload(&executable)? {
        let forwarded = arguments.map(os_bytes).collect::<Vec<_>>();
        runtime.run_buffer(
            payload.bytes(),
            &format!("@{}", executable.display()),
            &forwarded,
        )?;
    } else if let Some(file) = arguments.next() {
        let forwarded = arguments.map(os_bytes).collect::<Vec<_>>();
        runtime.run_file(Path::new(&file), &forwarded)?;
    } else {
        runtime.run_buffer(SMOKE, "=host-smoke", &[])?;
    }
    runtime.shutdown()?;
    Ok(())
}

#[cfg(unix)]
fn os_bytes(value: std::ffi::OsString) -> Vec<u8> {
    use std::os::unix::ffi::OsStringExt;
    value.into_vec()
}

#[cfg(not(unix))]
fn os_bytes(value: std::ffi::OsString) -> Vec<u8> {
    value.to_string_lossy().into_owned().into_bytes()
}
