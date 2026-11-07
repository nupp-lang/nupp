//! The system calls under the guest's process layer: a pipe for a child's
//! standard stream, posix_spawn with the child's descriptors and directory
//! set and in a process group of its own, the status of a child that has
//! exited, a signal to a child's whole group, and the end of this process.
//! The poller watches a child's exit (`poll::process_watch`); the streams,
//! the waiting and Lua's results are the guest's. Each call answers a value
//! or the negated error number.
use std::ffi::{c_char, c_int, c_short};

/// Storage for the C library's spawn attributes, file actions and signal
/// sets, which are a pointer on macOS and a structure of up to a few hundred
/// bytes in glibc.
#[repr(C, align(8))]
struct Opaque([u8; 512]);

impl Opaque {
    fn new() -> Self {
        Opaque([0; 512])
    }
}

unsafe extern "C" {
    fn posix_spawn(
        pid: *mut c_int,
        path: *const c_char,
        actions: *const Opaque,
        attributes: *const Opaque,
        argv: *const *const c_char,
        envp: *const *const c_char,
    ) -> c_int;
    fn posix_spawnp(
        pid: *mut c_int,
        file: *const c_char,
        actions: *const Opaque,
        attributes: *const Opaque,
        argv: *const *const c_char,
        envp: *const *const c_char,
    ) -> c_int;
    fn posix_spawn_file_actions_init(actions: *mut Opaque) -> c_int;
    fn posix_spawn_file_actions_destroy(actions: *mut Opaque) -> c_int;
    fn posix_spawn_file_actions_adddup2(actions: *mut Opaque, fd: c_int, target: c_int) -> c_int;
    fn posix_spawn_file_actions_addchdir_np(actions: *mut Opaque, path: *const c_char) -> c_int;
    fn posix_spawnattr_init(attributes: *mut Opaque) -> c_int;
    fn posix_spawnattr_destroy(attributes: *mut Opaque) -> c_int;
    fn posix_spawnattr_setflags(attributes: *mut Opaque, flags: c_short) -> c_int;
    fn posix_spawnattr_setpgroup(attributes: *mut Opaque, group: c_int) -> c_int;
    fn posix_spawnattr_setsigdefault(attributes: *mut Opaque, signals: *const Opaque) -> c_int;
    fn posix_spawnattr_setsigmask(attributes: *mut Opaque, signals: *const Opaque) -> c_int;
    fn sigemptyset(signals: *mut Opaque) -> c_int;
    fn sigaddset(signals: *mut Opaque, signal: c_int) -> c_int;
    fn waitpid(pid: c_int, status: *mut c_int, options: c_int) -> c_int;
    fn kill(pid: c_int, signal: c_int) -> c_int;
}

#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn _NSGetEnviron() -> *mut *const *const c_char;
}

#[cfg(target_os = "linux")]
unsafe extern "C" {
    static environ: *const *const c_char;
}

/// This process's environment, as `environ` holds it.
fn inherited() -> *const *const c_char {
    #[cfg(target_os = "macos")]
    return unsafe { *_NSGetEnviron() };
    #[cfg(target_os = "linux")]
    return unsafe { environ };
}

/// The spawn attributes' flags, the same on macOS and in glibc.
const POSIX_SPAWN_SETPGROUP: c_short = 0x02;
const POSIX_SPAWN_SETSIGDEF: c_short = 0x04;
const POSIX_SPAWN_SETSIGMASK: c_short = 0x08;
/// The bridge ignores SIGPIPE, as a Rust program does, and an ignored signal
/// stays ignored across exec: a child gets it back at its default.
const SIGPIPE: c_int = 13;
const WNOHANG: c_int = 1;
const EINVAL: i64 = 22;

/// A spawn's description, as the guest writes it: entries of a tag byte and
/// the entry's bytes, each ended by a NUL.
const PROGRAM: u8 = b'x';
const ARGUMENT: u8 = b'a';
const ENVIRONMENT: u8 = b'e';
const DIRECTORY: u8 = b'd';
/// A child descriptor (standard input, output or error) and, in decimal,
/// the descriptor of this process it is a copy of.
const STANDARD: [u8; 3] = [b'0', b'1', b'2'];

/// A spawn's flags: look the program up on PATH; give the child only the
/// environment entries, not this process's environment; or give it this
/// process's environment with the entries set over it.
const SEARCH: u64 = 1;
const ENVIRONMENT_GIVEN: u64 = 2;
const ENVIRONMENT_OVERLAY: u64 = 4;

/// Which end of a child's pipe this process keeps, nonblocking.
const KEEP_READ_END: u64 = 0;
const KEEP_WRITE_END: u64 = 1;

/// A reaped child's status, as the guest reads it: a reason above the
/// code, 1 for an exit with its status and 2 for a signal with its number;
/// 0 for a child still running.
const RUNNING: u64 = 0;
const REASON_EXIT: u64 = 1;
const REASON_SIGNAL: u64 = 2;
const REASON_BITS: u64 = 8;
/// What wait's status keeps of a terminating signal, and its stopped value.
const SIGNAL_MASK: c_int = 0x7f;
const STOPPED: c_int = 0x7f;
const CODE_MASK: c_int = 0xff;
const CODE_SHIFT: c_int = 8;

fn failed(code: i64) -> u64 {
    (-code) as u64
}

fn last() -> u64 {
    failed(std::io::Error::last_os_error().raw_os_error().unwrap_or(EINVAL as i32).into())
}

/// A pipe for one of a child's standard streams, closing on exec: the end
/// `keep` names (0 the read end, 1 the write end) is nonblocking for this
/// process, and the child's end blocks, as a program expects of its
/// standard streams. The read end's descriptor, and the write end's above it
/// from bit 32; or the negated error number.
pub extern "C" fn process_pipe(keep: u64) -> u64 {
    match keep {
        KEEP_READ_END => crate::poll::pipe_with([true, false]),
        KEEP_WRITE_END => crate::poll::pipe_with([false, true]),
        _ => failed(EINVAL),
    }
}

/// The name of the environment entry at `entry`, a C string: its bytes up to
/// the first `=`.
unsafe fn entry_name<'a>(entry: *const c_char) -> &'a [u8] {
    let bytes = unsafe { std::ffi::CStr::from_ptr(entry) }.to_bytes();
    bytes.split(|byte| *byte == b'=').next().unwrap_or(bytes)
}

/// This process's environment with `given` set over it: each of its entries
/// whose name no given entry has, then the given entries, then a null.
fn overlaid(given: &[*const c_char]) -> Vec<*const c_char> {
    let names: Vec<&[u8]> = given.iter().map(|&entry| unsafe { entry_name(entry) }).collect();
    let mut entries = Vec::new();
    let mut at = inherited();
    while !at.is_null() && !unsafe { *at }.is_null() {
        let entry = unsafe { *at };
        if !names.contains(&unsafe { entry_name(entry) }) {
            entries.push(entry);
        }
        at = unsafe { at.add(1) };
    }
    entries.extend_from_slice(given);
    entries.push(std::ptr::null());
    entries
}

/// What a spawn's description asks for.
#[derive(Default)]
struct Spawn {
    program: Option<usize>,
    arguments: Vec<usize>,
    environment: Vec<usize>,
    directory: Option<usize>,
    standard: [Option<c_int>; 3],
}

/// Reads the description in `bytes`, whose every entry ends in a NUL: the
/// offset of each entry's text, which runs to its NUL.
fn describe(bytes: &[u8]) -> Option<Spawn> {
    let mut spawn = Spawn::default();
    let mut at = 0;
    while at < bytes.len() {
        let end = at + bytes[at..].iter().position(|byte| *byte == 0)?;
        let (tag, text) = (bytes[at], at + 1);
        match tag {
            PROGRAM => spawn.program = Some(text),
            ARGUMENT => spawn.arguments.push(text),
            ENVIRONMENT => spawn.environment.push(text),
            DIRECTORY => spawn.directory = Some(text),
            _ => {
                let stream = STANDARD.iter().position(|named| *named == tag)?;
                let digits = std::str::from_utf8(&bytes[text..end]).ok()?;
                spawn.standard[stream] = Some(digits.parse().ok()?);
            }
        }
        at = end + 1;
    }
    if spawn.arguments.is_empty() { None } else { Some(spawn) }
}

/// Starts the child the `length` bytes at `spec` describe, in a process
/// group of its own, with `flags` (1 search PATH, 2 the given environment
/// only, 4 the given environment over this process's): its process id, or
/// the negated error number.
pub unsafe extern "C" fn process_spawn(spec: u64, length: u64, flags: u64) -> u64 {
    if spec == 0 && length != 0 {
        return failed(EINVAL);
    }
    let bytes = if length == 0 { Vec::new() } else { unsafe { std::slice::from_raw_parts(spec as *const u8, length as usize) }.to_vec() };
    let Some(spawn) = describe(&bytes) else {
        return failed(EINVAL);
    };
    let at = |offset: usize| bytes[offset..].as_ptr() as *const c_char;
    let mut argv: Vec<*const c_char> = spawn.arguments.iter().map(|&offset| at(offset)).collect();
    argv.push(std::ptr::null());
    let mut given: Vec<*const c_char> = spawn.environment.iter().map(|&offset| at(offset)).collect();
    let merged = if flags & ENVIRONMENT_OVERLAY != 0 { overlaid(&given) } else { Vec::new() };
    given.push(std::ptr::null());
    let envp = if flags & ENVIRONMENT_OVERLAY != 0 {
        merged.as_ptr()
    } else if flags & ENVIRONMENT_GIVEN != 0 {
        given.as_ptr()
    } else {
        inherited()
    };
    let program = at(spawn.program.unwrap_or(spawn.arguments[0]));

    let mut actions = Opaque::new();
    let mut attributes = Opaque::new();
    let (mut defaults, mut mask) = (Opaque::new(), Opaque::new());
    let mut pid: c_int = -1;
    let status = unsafe {
        posix_spawn_file_actions_init(&mut actions);
        posix_spawnattr_init(&mut attributes);
        sigemptyset(&mut defaults);
        sigaddset(&mut defaults, SIGPIPE);
        sigemptyset(&mut mask);
        let mut status = posix_spawnattr_setflags(
            &mut attributes,
            POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK,
        );
        // Group 0: the child leads a group of its own, numbered as it is.
        status = if status == 0 { posix_spawnattr_setpgroup(&mut attributes, 0) } else { status };
        status = if status == 0 { posix_spawnattr_setsigdefault(&mut attributes, &defaults) } else { status };
        status = if status == 0 { posix_spawnattr_setsigmask(&mut attributes, &mask) } else { status };
        for (target, source) in spawn.standard.iter().enumerate() {
            if let (0, Some(source)) = (status, source) {
                status = posix_spawn_file_actions_adddup2(&mut actions, *source, target as c_int);
            }
        }
        if let (0, Some(directory)) = (status, spawn.directory) {
            status = posix_spawn_file_actions_addchdir_np(&mut actions, at(directory));
        }
        if status == 0 {
            let start = if flags & SEARCH != 0 { posix_spawnp } else { posix_spawn };
            status = start(&mut pid, program, &actions, &attributes, argv.as_ptr(), envp);
        }
        posix_spawn_file_actions_destroy(&mut actions);
        posix_spawnattr_destroy(&mut attributes);
        status
    };
    if status != 0 { failed(status.into()) } else { pid as u64 }
}

/// Collects child `pid` if it has exited, without waiting: its reason (1 an
/// exit, 2 a signal) above eight bits of its exit status or signal number;
/// 0 while it runs; or the negated error number.
pub extern "C" fn process_reap(pid: u64) -> u64 {
    let mut status: c_int = 0;
    loop {
        let got = unsafe { waitpid(pid as c_int, &mut status, WNOHANG) };
        if got > 0 {
            break;
        }
        if got == 0 {
            return RUNNING;
        }
        if std::io::Error::last_os_error().kind() != std::io::ErrorKind::Interrupted {
            return last();
        }
    }
    let signal = status & SIGNAL_MASK;
    if signal == 0 {
        REASON_EXIT << REASON_BITS | ((status >> CODE_SHIFT) & CODE_MASK) as u64
    } else if signal != STOPPED {
        REASON_SIGNAL << REASON_BITS | signal as u64
    } else {
        RUNNING
    }
}

/// Sends `signal` to every process in child `pid`'s group, which the child
/// leads: zero, or the negated error number.
pub extern "C" fn process_kill(pid: u64, signal: u64) -> u64 {
    if pid as c_int <= 0 {
        return failed(EINVAL);
    }
    if unsafe { kill(-(pid as c_int), signal as c_int) } != 0 { last() } else { 0 }
}

/// Sends `signal` to the direct child only: zero or the negated system error.
/// Reject wide IDs before the C conversion so they cannot target another PID.
pub extern "C" fn process_signal(pid: u64, signal: u64) -> u64 {
    if pid == 0 || pid > c_int::MAX as u64 || signal > c_int::MAX as u64 {
        return failed(EINVAL);
    }
    if unsafe { kill(pid as c_int, signal as c_int) } != 0 {
        last()
    } else {
        0
    }
}

/// Ends this process with status `code`, as C's exit does. Everything the
/// guest wrote has reached its file already.
pub extern "C" fn process_exit(code: u64) -> u64 {
    use std::io::Write;
    let _ = std::io::stdout().flush();
    std::process::exit(code as c_int)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::poll;

    fn spawn(entries: &[(u8, &str)], flags: u64) -> u64 {
        let mut spec = Vec::new();
        for (tag, text) in entries {
            spec.push(*tag);
            spec.extend_from_slice(text.as_bytes());
            spec.push(0);
        }
        unsafe { process_spawn(spec.as_ptr() as u64, spec.len() as u64, flags) }
    }

    fn shell(command: &str, standard: &[(u8, &str)]) -> u64 {
        let mut entries = vec![(ARGUMENT, "/bin/sh"), (ARGUMENT, "-c"), (ARGUMENT, command)];
        entries.extend_from_slice(standard);
        spawn(&entries, 0)
    }

    /// Waits for `pid`'s exit through the poller, then reaps it.
    fn finish(pid: u64) -> u64 {
        let poller = poll::poll_open();
        let watched = poll::process_watch(poller, pid);
        if watched == 0 {
            assert_eq!(poll::poll_wait(poller, u64::MAX), pid << poll::EVENT_BITS | poll::EXITED);
        } else {
            // It exited before it was watched.
            assert_eq!(watched as i64, -3);
        }
        let status = process_reap(pid);
        assert_eq!(poll::process_unwatch(poller, pid), 0);
        unsafe { close(poller as c_int) };
        status
    }

    unsafe extern "C" {
        fn close(fd: c_int) -> c_int;
    }

    struct OwnedFd(u64);

    impl Drop for OwnedFd {
        fn drop(&mut self) {
            if (self.0 as i64) >= 0 {
                unsafe { close(self.0 as c_int) };
            }
        }
    }

    // Keep the direct child unreaped until its whole test-owned group is
    // cleaned, so its PID cannot be reused underneath the fallback guard.
    struct OwnedChild {
        pid: u64,
        reaped: bool,
    }

    impl Drop for OwnedChild {
        fn drop(&mut self) {
            const KILL: u64 = 9;
            if self.reaped || (self.pid as i64) <= 0 {
                return;
            }
            process_kill(self.pid, KILL);
            let mut status = 0;
            loop {
                if unsafe { waitpid(self.pid as c_int, &mut status, 0) } >= 0 {
                    break;
                }
                if std::io::Error::last_os_error().kind() != std::io::ErrorKind::Interrupted {
                    break;
                }
            }
        }
    }

    fn pipe_text(fd: u64, marker: &[u8]) -> Vec<u8> {
        const MAX_ATTEMPTS: usize = 500;
        const WAIT_MILLIS: u64 = 10;
        const AGAIN_MACOS: i64 = -35;
        const AGAIN_LINUX: i64 = -11;
        let mut received = Vec::new();
        for _ in 0..MAX_ATTEMPTS {
            let mut bytes = [0u8; 64];
            let count = unsafe {
                crate::files::file_read(fd, bytes.as_mut_ptr() as u64, bytes.len() as u64)
            } as i64;
            if count > 0 {
                received.extend_from_slice(&bytes[..count as usize]);
                if received.windows(marker.len()).any(|part| part == marker) {
                    return received;
                }
            } else {
                assert!(
                    count == AGAIN_MACOS || count == AGAIN_LINUX,
                    "pipe read ended before marker: {count}"
                );
            }
            std::thread::sleep(std::time::Duration::from_millis(WAIT_MILLIS));
        }
        panic!("pipe did not produce marker: {received:?}");
    }

    #[test]
    fn direct_signal_leaves_descendant_alive_and_group_cleanup_still_works() {
        const KILL: u64 = 9;
        const EXIT_TIMEOUT_NANOS: u64 = 5_000_000_000;
        assert_eq!(process_signal(0, KILL) as i64, -EINVAL);
        assert_eq!(process_signal(c_int::MAX as u64 + 1, KILL) as i64, -EINVAL);
        let output = process_pipe(KEEP_READ_END);
        assert!((output as i64) >= 0);
        let output_read = OwnedFd(output & poll::READ_END);
        let output_write = OwnedFd(output >> poll::WRITE_END);
        let input = process_pipe(KEEP_WRITE_END);
        assert!((input as i64) >= 0);
        let input_read = OwnedFd(input & poll::READ_END);
        let input_write = OwnedFd(input >> poll::WRITE_END);
        let input_fd = input_read.0.to_string();
        let output_fd = output_write.0.to_string();
        let command =
            r#"sh -c 'IFS= read -r token; printf alive; sleep 30' <&0 & printf '%s\n' "$!"; wait"#;
        let pid = shell(command, &[(b'0', &input_fd), (b'1', &output_fd)]);
        let mut child = OwnedChild { pid, reaped: false };
        assert!((pid as i64) > 0);
        drop(input_read);
        drop(output_write);
        let announced = pipe_text(output_read.0, b"\n");
        let descendant = std::str::from_utf8(&announced)
            .unwrap()
            .trim()
            .parse::<u64>()
            .unwrap();
        assert!(descendant > 0 && descendant != pid);
        let poller = OwnedFd(poll::poll_open());
        assert!((poller.0 as i64) >= 0);
        assert_eq!(poll::process_watch(poller.0, pid), 0);
        assert_eq!(process_signal(pid, 0), 0);
        assert_eq!(process_signal(pid, KILL), 0);
        assert_eq!(
            poll::poll_wait(poller.0, EXIT_TIMEOUT_NANOS),
            pid << poll::EVENT_BITS | poll::EXITED
        );
        // The descendant must execute after the parent's confirmed death;
        // kill(pid, 0) alone could mistake an already-dead zombie for survival.
        let token = b"continue\n";
        assert_eq!(
            unsafe {
                crate::files::file_write(input_write.0, token.as_ptr() as u64, token.len() as u64)
            },
            token.len() as u64
        );
        assert!(pipe_text(output_read.0, b"alive").ends_with(b"alive"));
        assert_eq!(process_kill(pid, KILL), 0);
        let status = process_reap(pid);
        if status != RUNNING && (status as i64) >= 0 {
            child.reaped = true;
        }
        assert_eq!(status, REASON_SIGNAL << REASON_BITS | KILL);
        assert_eq!(poll::process_unwatch(poller.0, pid), 0);
    }

    #[test]
    fn exits_and_signals_are_reported_apart() {
        let pid = shell("exit 3", &[]);
        assert!((pid as i64) > 0);
        assert_eq!(finish(pid), REASON_EXIT << REASON_BITS | 3);
        let pid = shell("kill -TERM $$", &[]);
        assert_eq!(finish(pid), REASON_SIGNAL << REASON_BITS | 15);
        // Reaped already: nothing to collect.
        assert_eq!(process_reap(pid) as i64, -10);
    }

    #[test]
    fn a_missing_program_or_bad_description_fails_to_spawn() {
        assert_eq!(spawn(&[(ARGUMENT, "/nonexistent/program")], 0) as i64, -2);
        assert_eq!(spawn(&[(ARGUMENT, "no-such-program-anywhere")], SEARCH) as i64, -2);
        assert_eq!(spawn(&[(PROGRAM, "/bin/sh")], 0) as i64, -EINVAL);
        assert_eq!(spawn(&[(ARGUMENT, "/bin/sh"), (b'7', "1")], 0) as i64, -EINVAL);
    }

    #[test]
    fn a_child_writes_through_its_pipe_in_its_directory_and_environment() {
        let ends = process_pipe(KEEP_READ_END);
        let (reader, writer) = (ends & poll::READ_END, ends >> poll::WRITE_END);
        let out = writer.to_string();
        let pid = spawn(
            &[
                (ARGUMENT, "sh"),
                (ARGUMENT, "-c"),
                (ARGUMENT, "printf '%s:%s' \"$PWD\" \"$GREETING\""),
                (ENVIRONMENT, "GREETING=hi"),
                (DIRECTORY, "/"),
                (b'1', &out),
            ],
            SEARCH | ENVIRONMENT_GIVEN,
        );
        assert!((pid as i64) > 0);
        unsafe { close(writer as c_int) };
        assert_eq!(finish(pid), REASON_EXIT << REASON_BITS);
        let mut room = [0u8; 16];
        let count = unsafe { crate::files::file_read(reader, room.as_mut_ptr() as u64, 16) };
        assert_eq!(&room[..count as usize], b"/:hi");
        unsafe { close(reader as c_int) };
    }

    #[test]
    fn an_overlay_sets_entries_over_this_environment() {
        let ends = process_pipe(KEEP_READ_END);
        let (reader, writer) = (ends & poll::READ_END, ends >> poll::WRITE_END);
        let out = writer.to_string();
        let pid = spawn(
            &[
                (ARGUMENT, "/bin/sh"),
                (ARGUMENT, "-c"),
                (ARGUMENT, "printf '%s:%s' \"$HOME\" \"$PATH\""),
                (ENVIRONMENT, "PATH=/overlaid"),
                (b'1', &out),
            ],
            ENVIRONMENT_OVERLAY,
        );
        unsafe { close(writer as c_int) };
        assert_eq!(finish(pid), REASON_EXIT << REASON_BITS);
        let mut room = [0u8; 256];
        let count = unsafe { crate::files::file_read(reader, room.as_mut_ptr() as u64, 256) };
        let expected = format!("{}:/overlaid", std::env::var("HOME").unwrap());
        assert_eq!(&room[..count as usize], expected.as_bytes());
        unsafe { close(reader as c_int) };
    }

    #[test]
    fn a_child_killed_as_it_is_watched_is_always_collected() {
        // Whenever the watch comes, during the exit or after it, either the
        // exit is reported or the status is there to collect.
        for _ in 0..200 {
            let pid = shell("sleep 30", &[]);
            assert_eq!(process_kill(pid, 9), 0);
            assert_eq!(finish(pid), REASON_SIGNAL << REASON_BITS | 9);
        }
    }

    #[test]
    fn a_kill_ends_the_whole_group() {
        let ends = process_pipe(KEEP_READ_END);
        let (reader, writer) = (ends & poll::READ_END, ends >> poll::WRITE_END);
        let out = writer.to_string();
        // The shell's background child holds the pipe too: the pipe ends
        // only when both are gone.
        let pid = shell("sleep 30 & echo started; wait", &[(b'1', &out)]);
        unsafe { close(writer as c_int) };
        let poller = poll::poll_open();
        let mut room = [0u8; 16];
        assert_eq!(poll::poll_arm(poller, reader, poll::READABLE), 0);
        assert_eq!(poll::poll_wait(poller, u64::MAX) >> poll::EVENT_BITS, reader);
        assert_eq!(unsafe { crate::files::file_read(reader, room.as_mut_ptr() as u64, 16) }, 8);
        assert_eq!(process_kill(pid, 9), 0);
        assert_eq!(finish(pid), REASON_SIGNAL << REASON_BITS | 9);
        assert_eq!(poll::poll_arm(poller, reader, poll::READABLE), 0);
        assert_eq!(poll::poll_wait(poller, 5_000_000_000) >> poll::EVENT_BITS, reader);
        assert_eq!(unsafe { crate::files::file_read(reader, room.as_mut_ptr() as u64, 16) }, 0);
        unsafe {
            close(reader as c_int);
            close(poller as c_int);
        }
    }
}
