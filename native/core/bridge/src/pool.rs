//! The blocking-work pool under the guest's reactor: a fixed set of OS
//! threads that make the system calls which cannot wait for readiness
//! (open, read and write on regular files) and post each result for the
//! reactor to collect. The pool runs no guest code: a job is the raw system
//! call, its bytes copied in at submission and out at collection, so nothing
//! on the guest's heap is touched off its thread. A byte written to the wake
//! pipe tells the reactor's poller that results are waiting; which tasks
//! they answer, and in what order, is the guest's.
use std::collections::{HashMap, VecDeque};
use std::ffi::{c_char, c_int, c_uint, c_void};
use std::sync::{Condvar, Mutex, OnceLock};

unsafe extern "C" {
    fn open(path: *const c_char, flags: c_int, ...) -> c_int;
    fn read(fd: c_int, buffer: *mut c_void, count: usize) -> isize;
    fn write(fd: c_int, buffer: *const c_void, count: usize) -> isize;
    fn pipe(fds: *mut c_int) -> c_int;
    fn fcntl(fd: c_int, command: c_int, ...) -> c_int;
}

/// What a job does, as the guest encodes it.
const OPEN: u64 = 1;
const READ: u64 = 2;
const WRITE: u64 = 3;
const EINVAL: i64 = 22;
const EFAULT: i64 = 14;
/// An open job's word: the C open flags, and the mode above them
/// (`hostfiles.poolFlags`), so its policy is Nupp's.
const MODE_SHIFT: u64 = 32;
const F_SETFD: c_int = 2;
const F_GETFL: c_int = 3;
const F_SETFL: c_int = 4;
const FD_CLOEXEC: c_int = 1;
const O_NONBLOCK: c_int = if cfg!(target_os = "macos") { 0x4 } else { 0o4000 };

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
    settled: Condvar,
    /// The wake pipe's ends: the reactor polls the first, workers write the
    /// second.
    awake: u64,
    wake: u64,
}

static POOL: OnceLock<Result<Pool, u64>> = OnceLock::new();

fn failed(code: i64) -> u64 {
    (-code) as u64
}

/// The system call `call` makes, again while a signal interrupts it: its
/// count or descriptor, or the negated error number.
fn retried(mut call: impl FnMut() -> isize) -> u64 {
    loop {
        let result = call();
        if result >= 0 {
            return result as u64;
        }
        if std::io::Error::last_os_error().kind() != std::io::ErrorKind::Interrupted {
            return last();
        }
    }
}

/// The negated error number of the system call that just failed.
fn last() -> u64 {
    failed(std::io::Error::last_os_error().raw_os_error().unwrap_or(EINVAL as i32).into())
}

fn perform(kind: u64, word: u64, bytes: Vec<u8>, count: usize) -> (u64, Vec<u8>) {
    match kind {
        OPEN => {
            let mut name: Vec<u8> = bytes.split(|byte| *byte == 0).next().unwrap_or(&[]).to_vec();
            name.push(0);
            let (flags, mode) = (word as u32 as c_int, (word >> MODE_SHIFT) as c_uint);
            (retried(|| unsafe { open(name.as_ptr().cast(), flags, mode) } as isize), Vec::new())
        }
        READ => {
            let mut out = vec![0u8; count];
            let result = retried(|| unsafe { read(word as c_int, out.as_mut_ptr().cast(), count) });
            out.truncate(if (result as i64) < 0 { 0 } else { result as usize });
            (result, out)
        }
        _ => (retried(|| unsafe { write(word as c_int, bytes.as_ptr().cast(), bytes.len()) }), Vec::new()),
    }
}

/// The wake pipe, both ends closing on exec and nonblocking: its read end
/// and its write end, or the negated error number.
fn wake_pipe() -> Result<(u64, u64), u64> {
    let mut fds: [c_int; 2] = [-1, -1];
    if unsafe { pipe(fds.as_mut_ptr()) } != 0 {
        return Err(last());
    }
    for fd in fds {
        unsafe {
            fcntl(fd, F_SETFD, FD_CLOEXEC);
            fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
        }
    }
    Ok((fds[0] as u64, fds[1] as u64))
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
            pool.settled.notify_all();
        }
        // A full wake pipe already says results are waiting.
        let byte = [1u8];
        unsafe { write(pool.wake as c_int, byte.as_ptr().cast(), 1) };
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
        let (awake, wake) = wake_pipe()?;
        Ok(Pool { state: Mutex::default(), work: Condvar::new(), settled: Condvar::new(), awake, wake })
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

/// Settles exactly this entry-owned ticket, including a result already taken
/// from the completion queue. No other entry's completion is consumed. The
/// caller retains descriptors until all of its tickets have settled.
pub extern "C" fn pool_settle(ticket: u64) -> u64 {
    let Some(pool) = started() else { return failed(EINVAL) };
    let mut state = pool.state.lock().unwrap();
    loop {
        match state.jobs.get(&ticket) {
            None => return failed(EINVAL),
            Some(job) if job.done => break,
            _ => state = pool.settled.wait(state).unwrap(),
        }
    }
    state.finished.retain(|finished| *finished != ticket);
    state.jobs.remove(&ticket).unwrap().result
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
    static TEST_LOCK: Mutex<()> = Mutex::new(());

    unsafe extern "C" {
        fn close(fd: c_int) -> c_int;
        fn lseek(fd: c_int, offset: i64, whence: c_int) -> i64;
    }

    /// An open job's word for reading and writing a file it creates and
    /// truncates, as `hostfiles.poolFlags` makes it.
    const READ_WRITE_CREATE: u64 = if cfg!(target_os = "macos") { 0x2 | 0x200 | 0x400 } else { 0o2 | 0o100 | 0o1000 };
    const READ_ONLY: u64 = 0;
    const SHARED_MODE: u64 = 0o666 << MODE_SHIFT;

    /// The next `want` tickets to finish, as the reactor collects them.
    fn gather(want: usize) -> Vec<u64> {
        let mut tickets = Vec::new();
        while tickets.len() < want {
            match pool_take() {
                0 => std::thread::sleep(std::time::Duration::from_millis(1)),
                ticket => tickets.push(ticket),
            }
        }
        tickets
    }

    #[test]
    fn settlement_keeps_other_completions_and_spends_only_its_ticket() {
        let _serial = TEST_LOCK.lock().unwrap();
        let _awake = pool_start(2);
        let path = b"/dev/null";
        let first = unsafe { pool_submit(OPEN, READ_ONLY, path.as_ptr() as u64, path.len() as u64) };
        let second = unsafe { pool_submit(OPEN, READ_ONLY, path.as_ptr() as u64, path.len() as u64) };
        let first_fd = pool_settle(first);
        assert!((first_fd as i64) >= 0);
        assert_eq!(pool_settle(first) as i64, -EINVAL);
        assert_eq!(gather(1), [second]);
        let second_fd = unsafe { pool_finish(second, 0, 0) };
        assert!((second_fd as i64) >= 0);
        assert_eq!(pool_take(), 0);
        unsafe {
            assert_eq!(close(first_fd as c_int), 0);
            assert_eq!(close(second_fd as c_int), 0);
        }
    }

    #[test]
    fn settlement_waits_for_inflight_io_before_descriptor_release() {
        let _serial = TEST_LOCK.lock().unwrap();
        use std::io::Write;
        use std::os::fd::AsRawFd;
        use std::os::unix::net::UnixStream;
        let _awake = pool_start(2);
        let (reader, mut writer) = UnixStream::pair().unwrap();
        let ticket = unsafe { pool_submit(READ, reader.as_raw_fd() as u64, 0, 1) };
        let wait = std::thread::spawn(move || pool_settle(ticket));
        writer.write_all(b"x").unwrap();
        assert_eq!(wait.join().unwrap(), 1);
        assert_eq!(pool_settle(ticket) as i64, -EINVAL);
        assert_eq!(pool_take(), 0);
    }

    #[test]
    fn jobs_open_write_and_read_off_the_calling_thread() {
        let _serial = TEST_LOCK.lock().unwrap();
        let awake = pool_start(2);
        assert!((awake as i64) >= 0);
        assert_eq!(pool_start(8), awake);
        let path = std::env::temp_dir().join(format!("nupp-pool-{}", std::process::id()));
        let name = path.as_os_str().as_encoded_bytes();
        let open = unsafe { pool_submit(OPEN, READ_WRITE_CREATE | SHARED_MODE, name.as_ptr() as u64, name.len() as u64) };
        assert_eq!(gather(1), [open]);
        let fd = unsafe { pool_finish(open, 0, 0) };
        assert!((fd as i64) >= 0);
        assert_eq!(unsafe { pool_finish(open, 0, 0) } as i64, -EINVAL);
        let text = b"pooled";
        let write = unsafe { pool_submit(WRITE, fd, text.as_ptr() as u64, text.len() as u64) };
        assert_eq!(gather(1), [write]);
        assert_eq!(unsafe { pool_finish(write, 0, 0) }, 6);
        assert_eq!(unsafe { lseek(fd as c_int, 0, 0) }, 0);
        // Concurrent reads share the offset: each takes two of the bytes.
        let reads: Vec<_> = (0..3).map(|_| unsafe { pool_submit(READ, fd, 0, 2) }).collect();
        let mut tickets = gather(3);
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
