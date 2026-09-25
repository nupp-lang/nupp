//! Compiling many modules, each where a crash cannot reach the caller.
//!
//! LLVM ends a process on an internal error (`report_fatal_error`, a failed
//! assertion in legalization), and the process is the user's `nupp`. On POSIX
//! each job therefore runs in a forked child: it compiles, writes the object
//! and its report beside the object, and exits. A child that dies instead is
//! that one module's error, carrying what LLVM printed. Children run side by
//! side, which is also what makes a build's units compile in parallel.
//!
//! The child touches nothing but LLVM, the files it writes and the allocator,
//! and `nupp` does not use LLVM from any other thread, so no lock LLVM needs
//! can be held by a thread the fork left behind. Without `fork` (Windows) the
//! jobs run here, one after another.

use crate::{CompileOptions, compile};
use std::path::PathBuf;

/// One module to compile: its IR file, the object to write and how.
pub struct Job {
    pub ir: PathBuf,
    pub object: PathBuf,
    pub options: CompileOptions,
}

fn report_path(job: &Job) -> PathBuf {
    let mut path = job.object.clone().into_os_string();
    path.push(".report");
    PathBuf::from(path)
}

/// Compiles one job here, writing its object; answers the report.
fn run(job: &Job) -> Result<String, String> {
    let ir = std::fs::read_to_string(&job.ir).map_err(|e| format!("cannot read {}: {e}", job.ir.display()))?;
    let name = job.ir.to_string_lossy();
    let compiled = compile(&ir, &name, &job.options)?;
    std::fs::write(&job.object, &compiled.object).map_err(|e| format!("cannot write {}: {e}", job.object.display()))?;
    Ok(compiled.report())
}

#[cfg(unix)]
mod posix {
    use std::ffi::c_int;
    unsafe extern "C" {
        pub fn fork() -> c_int;
        pub fn waitpid(pid: c_int, status: *mut c_int, options: c_int) -> c_int;
        pub fn _exit(code: c_int) -> !;
        pub fn dup2(from: c_int, to: c_int) -> c_int;
    }
}

/// Compiles every job, at most `width` at a time, answering each one's report
/// or error in job order.
pub fn compile_files(jobs: &[Job], width: usize) -> Vec<Result<String, String>> {
    #[cfg(unix)]
    {
        forked(jobs, width.max(1))
    }
    #[cfg(not(unix))]
    {
        let _ = width;
        jobs.iter().map(run).collect()
    }
}

#[cfg(unix)]
fn forked(jobs: &[Job], width: usize) -> Vec<Result<String, String>> {
    use std::collections::HashMap;
    use std::os::fd::AsRawFd;

    let mut results: Vec<Option<Result<String, String>>> = (0..jobs.len()).map(|_| None).collect();
    let mut running: HashMap<i32, usize> = HashMap::new();
    let mut next = 0;
    let stderr_path = |job: &Job| {
        let mut path = job.object.clone().into_os_string();
        path.push(".stderr");
        PathBuf::from(path)
    };
    while next < jobs.len() || !running.is_empty() {
        while next < jobs.len() && running.len() < width {
            let job = &jobs[next];
            let _ = std::fs::remove_file(report_path(job));
            let errors = std::fs::File::create(stderr_path(job));
            let pid = unsafe { posix::fork() };
            if pid == 0 {
                // The child: its diagnostics go to its own file, and it leaves
                // with `_exit`, running nothing the parent registered.
                if let Ok(file) = &errors {
                    unsafe { posix::dup2(file.as_raw_fd(), 2) };
                }
                let (code, text) = match run(job) {
                    Ok(report) => (0, report),
                    Err(error) => (1, error),
                };
                let _ = std::fs::write(report_path(job), text);
                unsafe { posix::_exit(code) };
            }
            if pid < 0 {
                results[next] = Some(run(job));
            } else {
                running.insert(pid, next);
            }
            next += 1;
        }
        if running.is_empty() {
            continue;
        }
        let mut status = 0;
        let pid = unsafe { posix::waitpid(-1, &mut status, 0) };
        if pid <= 0 {
            // Nothing left to reap: whatever was running is lost.
            for (_, index) in running.drain() {
                results[index] = Some(Err("the compiling process could not be waited for".into()));
            }
            continue;
        }
        let Some(index) = running.remove(&pid) else { continue };
        let job = &jobs[index];
        let report = std::fs::read_to_string(report_path(job)).unwrap_or_default();
        let printed = std::fs::read_to_string(stderr_path(job)).unwrap_or_default();
        let _ = std::fs::remove_file(report_path(job));
        let _ = std::fs::remove_file(stderr_path(job));
        let exited = status & 0x7f == 0;
        let code = (status >> 8) & 0xff;
        results[index] = Some(if exited && code == 0 {
            Ok(report)
        } else if exited {
            Err(report)
        } else {
            let signal = status & 0x7f;
            let said = printed.trim();
            Err(format!(
                "LLVM stopped compiling {} (signal {signal}){}",
                job.ir.display(),
                if said.is_empty() { String::new() } else { format!(": {said}") }
            ))
        });
    }
    results.into_iter().map(|r| r.unwrap_or_else(|| Err("not compiled".into()))).collect()
}
