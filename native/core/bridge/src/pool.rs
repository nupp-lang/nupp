//! The blocking-work pool under the guest's reactor: a fixed set of OS
//! threads that make the system calls which cannot wait for readiness
//! (open, read and write on regular files) and post each result for the
//! reactor to collect. The pool runs no guest code: a job is the raw system
//! call, its bytes copied in at submission and out at collection, so nothing
//! on the guest's heap is touched off its thread. A byte written to the wake
//! pipe tells the reactor's poller that results are waiting; which tasks
//! they answer, and in what order, is the guest's.
use std::collections::{HashMap, VecDeque};
use std::sync::{Condvar, Mutex, OnceLock};

/// What a job does, as the guest encodes it.
const OPEN: u64 = 1;
const READ: u64 = 2;
const WRITE: u64 = 3;
const EINVAL: i64 = 22;
const EFAULT: i64 = 14;

struct Job {
    kind: u64,
    /// An open's access flags, or a read's or write's descriptor.
    word: u64,
    /// An open's path or a write's bytes going in; a read's bytes coming out.
    bytes: Vec<u8>,
    /// The most bytes a read asks for.
    count: usize,
    result: u64,
    done: bool,
}

#[derive(Default)]
struct State {
    jobs: HashMap<u64, Job>,
    waiting: VecDeque<u64>,
    finished: VecDeque<u64>,
    last: u64,
}

struct Pool {
    state: Mutex<State>,
    work: Condvar,
    /// The wake pipe's ends: the reactor polls the first, workers write the
    /// second.
    awake: u64,
    wake: u64,
}

static POOL: OnceLock<Result<Pool, u64>> = OnceLock::new();

fn failed(code: i64) -> u64 {
    (-code) as u64
}

fn perform(kind: u64, word: u64, bytes: Vec<u8>, count: usize) -> (u64, Vec<u8>) {
    match kind {
        OPEN => (unsafe { crate::files::file_open(bytes.as_ptr() as u64, bytes.len() as u64, word) }, Vec::new()),
        READ => {
            let mut out = vec![0u8; count];
            let result = unsafe { crate::files::file_read(word, out.as_mut_ptr() as u64, count as u64) };
            out.truncate(if (result as i64) < 0 { 0 } else { result as usize });
            (result, out)
        }
        _ => (unsafe { crate::files::file_write(word, bytes.as_ptr() as u64, bytes.len() as u64) }, Vec::new()),
    }
}

fn work(pool: &'static Pool) {
    loop {
        let (ticket, kind, word, bytes, count) = {
            let mut state = pool.state.lock().unwrap();
            while state.waiting.is_empty() {
                state = pool.work.wait(state).unwrap();
            }
            let ticket = state.waiting.pop_front().unwrap();
            let job = state.jobs.get_mut(&ticket).unwrap();
            (ticket, job.kind, job.word, std::mem::take(&mut job.bytes), job.count)
        };
        let (result, out) = perform(kind, word, bytes, count);
        {
            let mut state = pool.state.lock().unwrap();
            let job = state.jobs.get_mut(&ticket).unwrap();
            (job.result, job.bytes, job.done) = (result, out, true);
            state.finished.push_back(ticket);
        }
        // A full wake pipe already says results are waiting.
        let byte = [1u8];
        unsafe { crate::files::file_write(pool.wake, byte.as_ptr() as u64, 1) };
    }
}

fn started() -> Option<&'static Pool> {
    POOL.get().and_then(|pool| pool.as_ref().ok())
}

/// Starts the pool's `threads` workers (1 to 64), once: the wake pipe's
/// read end, which is readable while results wait; or the negated error
/// number. Later calls answer the same descriptor.
pub extern "C" fn pool_start(threads: u64) -> u64 {
    let pool = POOL.get_or_init(|| {
        let ends = crate::poll::pipe_open();
        if (ends as i64) < 0 {
            return Err(ends);
        }
        Ok(Pool { state: Mutex::default(), work: Condvar::new(), awake: ends & crate::poll::READ_END, wake: ends >> crate::poll::WRITE_END })
    });
    let pool = match pool {
        Ok(pool) => pool,
        Err(code) => return *code,
    };
    static THREADS: OnceLock<u64> = OnceLock::new();
    let spawned = *THREADS.get_or_init(|| {
        for index in 0..threads.clamp(1, 64) {
            let named = std::thread::Builder::new().name(format!("nupp-pool-{index}"));
            if named.spawn(move || work(pool)).is_err() {
                return failed(std::io::Error::last_os_error().raw_os_error().unwrap_or(11).into());
            }
        }
        0
    });
    if spawned != 0 { spawned } else { pool.awake }
}

/// Submits a job: an open of the `bytes`-byte path at `base` with the access
/// flags `word` (kind 1), a read of at most `bytes` bytes from descriptor
/// `word` (2), or a write of the `bytes` bytes at `base` to it (3). The
/// bytes are copied now. Its ticket, or the negated error number.
pub unsafe extern "C" fn pool_submit(kind: u64, word: u64, base: u64, bytes: u64) -> u64 {
    let Some(pool) = started() else { return failed(EINVAL) };
    if !(OPEN..=WRITE).contains(&kind) {
        return failed(EINVAL);
    }
    if base == 0 && bytes != 0 && kind != READ {
        return failed(EFAULT);
    }
    let copied = if kind == READ || bytes == 0 {
        Vec::new()
    } else {
        unsafe { std::slice::from_raw_parts(base as *const u8, bytes as usize) }.to_vec()
    };
    let count = if kind == READ { bytes as usize } else { 0 };
    let mut state = pool.state.lock().unwrap();
    state.last += 1;
    let ticket = state.last;
    state.jobs.insert(ticket, Job { kind, word, bytes: copied, count, result: 0, done: false });
    state.waiting.push_back(ticket);
    pool.work.notify_one();
    ticket
}

/// The ticket of a job that has finished and not been taken, oldest first;
/// zero when there is none.
pub extern "C" fn pool_take() -> u64 {
    started().and_then(|pool| pool.state.lock().unwrap().finished.pop_front()).unwrap_or(0)
}

/// Collects a taken job: copies what a read read into `out`, at most `room`
/// bytes, and answers what its system call did (a descriptor or count, or
/// the negated error number). The ticket is spent.
pub unsafe extern "C" fn pool_finish(ticket: u64, out: u64, room: u64) -> u64 {
    let Some(pool) = started() else { return failed(EINVAL) };
    let mut state = pool.state.lock().unwrap();
    if !state.jobs.get(&ticket).is_some_and(|job| job.done) || state.finished.contains(&ticket) {
        return failed(EINVAL);
    }
    let job = state.jobs.remove(&ticket).unwrap();
    if out != 0 {
        let count = job.bytes.len().min(room as usize);
        unsafe { std::ptr::copy_nonoverlapping(job.bytes.as_ptr(), out as *mut u8, count) };
    }
    job.result
}

/// Withdraws a job no worker has started: 1, and its ticket is spent; 0 when
/// it has started or finished, and it is still to be taken and collected.
pub extern "C" fn pool_cancel(ticket: u64) -> u64 {
    let Some(pool) = started() else { return 0 };
    let mut state = pool.state.lock().unwrap();
    let Some(at) = state.waiting.iter().position(|waiting| *waiting == ticket) else { return 0 };
    state.waiting.remove(at);
    state.jobs.remove(&ticket);
    1
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::c_int;

    unsafe extern "C" {
        fn close(fd: c_int) -> c_int;
    }

    /// The next `want` tickets to finish, as the reactor collects them: the
    /// wake pipe drained before the finished jobs are taken.
    fn gather(awake: u64, want: usize) -> Vec<u64> {
        let mut tickets = Vec::new();
        let poller = crate::poll::poll_open();
        while tickets.len() < want {
            assert_eq!(crate::poll::poll_arm(poller, awake, crate::poll::READABLE), 0);
            assert_eq!(crate::poll::poll_wait(poller, u64::MAX) >> crate::poll::EVENT_BITS, awake);
            let mut drain = [0u8; 64];
            while (unsafe { crate::files::file_read(awake, drain.as_mut_ptr() as u64, 64) } as i64) > 0 {}
            loop {
                match pool_take() {
                    0 => break,
                    ticket => tickets.push(ticket),
                }
            }
        }
        unsafe { close(poller as c_int) };
        tickets
    }

    #[test]
    fn jobs_open_write_and_read_off_the_calling_thread() {
        let awake = pool_start(2);
        assert!((awake as i64) >= 0);
        assert_eq!(pool_start(8), awake);
        let path = std::env::temp_dir().join(format!("nupp-pool-{}", std::process::id()));
        let name = path.as_os_str().as_encoded_bytes();
        // Read and write, created and truncated.
        let open = unsafe { pool_submit(OPEN, 1 | 2 | 4 | 8, name.as_ptr() as u64, name.len() as u64) };
        assert_eq!(gather(awake, 1), [open]);
        let fd = unsafe { pool_finish(open, 0, 0) };
        assert!((fd as i64) >= 0);
        assert_eq!(unsafe { pool_finish(open, 0, 0) } as i64, -EINVAL);
        let text = b"pooled";
        let write = unsafe { pool_submit(WRITE, fd, text.as_ptr() as u64, text.len() as u64) };
        assert_eq!(gather(awake, 1), [write]);
        assert_eq!(unsafe { pool_finish(write, 0, 0) }, 6);
        assert_eq!(unsafe { crate::files::file_seek(fd, 0, 0) }, 0);
        // Concurrent reads share the offset: each takes two of the bytes.
        let reads: Vec<_> = (0..3).map(|_| unsafe { pool_submit(READ, fd, 0, 2) }).collect();
        let mut tickets = gather(awake, 3);
        tickets.sort();
        assert_eq!(tickets, reads);
        let mut seen = Vec::new();
        for ticket in reads {
            let mut out = [0u8; 2];
            assert_eq!(unsafe { pool_finish(ticket, out.as_mut_ptr() as u64, 2) }, 2);
            seen.extend_from_slice(&out);
        }
        seen.sort();
        let mut expected = text.to_vec();
        expected.sort();
        assert_eq!(seen, expected);
        assert_eq!(pool_cancel(u64::MAX), 0);
        unsafe { close(fd as c_int) };
        let _ = std::fs::remove_file(path);
    }
}
