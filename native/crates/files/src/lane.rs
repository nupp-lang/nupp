use crate::platform;
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;

pub const MAX_REQUESTS: usize = 128;
pub const MAX_BYTES: usize = 256 * 1024 * 1024;
pub const MAX_REQUEST_BYTES: usize = 256 * 1024 * 1024;
const READ_CHUNK: usize = 64 * 1024;
const TEMPORARY_ATTEMPTS: usize = 64;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum WriteMode {
    Replace,
    Append,
    Atomic,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TransferStatus {
    Pending,
    Ready,
    Failed,
    Canceled,
}

enum Outcome {
    Pending,
    Ready(Option<Box<[u8]>>),
    Failed(String),
    Canceled,
}

struct TransferShared {
    outcome: Mutex<Outcome>,
}

impl TransferShared {
    fn settle(&self, answer: io::Result<Option<Box<[u8]>>>) -> bool {
        let mut outcome = self
            .outcome
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if !matches!(*outcome, Outcome::Pending) {
            return false;
        }
        *outcome = match answer {
            Ok(value) => Outcome::Ready(value),
            Err(error) => Outcome::Failed(error.to_string()),
        };
        true
    }
}

struct Activity {
    generation: Mutex<u64>,
    changed: Condvar,
}

impl Activity {
    fn generation(&self) -> u64 {
        *self
            .generation
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }

    fn notify(&self) {
        let mut generation = self
            .generation
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        *generation = generation.wrapping_add(1);
        self.changed.notify_all();
    }

    fn wait(&self, seen: u64, timeout: Duration) -> u64 {
        let generation = self
            .generation
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let generation = if *generation == seen {
            self.changed
                .wait_timeout(generation, timeout)
                .unwrap_or_else(|error| error.into_inner())
                .0
        } else {
            generation
        };
        *generation
    }
}

#[derive(Default)]
struct Admission {
    requests: usize,
    bytes: usize,
}

struct LaneShared {
    admission: Mutex<Admission>,
    public_requests: AtomicUsize,
    settled: AtomicUsize,
    activity: Activity,
}

struct AdmissionGuard {
    lane: Arc<LaneShared>,
    bytes: usize,
}

impl AdmissionGuard {
    fn grow_to(&mut self, bytes: usize) -> io::Result<()> {
        if bytes <= self.bytes {
            return Ok(());
        }
        if bytes > MAX_REQUEST_BYTES {
            return Err(io::Error::new(
                io::ErrorKind::FileTooLarge,
                format!("the transfer is larger than the {MAX_REQUEST_BYTES}-byte limit"),
            ));
        }
        let additional = bytes - self.bytes;
        let mut admission = self
            .lane
            .admission
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let Some(total) = admission.bytes.checked_add(additional) else {
            return Err(io::Error::other("file transfer byte accounting overflowed"));
        };
        if total > MAX_BYTES {
            return Err(io::Error::other(format!(
                "transfers in flight would hold more than {MAX_BYTES} bytes"
            )));
        }
        admission.bytes = total;
        self.bytes = bytes;
        Ok(())
    }
}

impl Drop for AdmissionGuard {
    fn drop(&mut self) {
        let mut admission = self
            .lane
            .admission
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        admission.requests -= 1;
        admission.bytes -= self.bytes;
    }
}

/// A caller-owned transfer. Dropping it releases the public pending count,
/// while its blocking worker retains admission until the operating-system work
/// has actually stopped.
pub struct Transfer {
    shared: Arc<TransferShared>,
    lane: Arc<LaneShared>,
}

impl Transfer {
    pub fn status(&self) -> TransferStatus {
        match &*self
            .shared
            .outcome
            .lock()
            .unwrap_or_else(|error| error.into_inner())
        {
            Outcome::Pending => TransferStatus::Pending,
            Outcome::Ready(_) => TransferStatus::Ready,
            Outcome::Failed(_) => TransferStatus::Failed,
            Outcome::Canceled => TransferStatus::Canceled,
        }
    }

    pub fn cancel(&self) -> bool {
        let mut outcome = self
            .shared
            .outcome
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if !matches!(*outcome, Outcome::Pending) {
            return false;
        }
        *outcome = Outcome::Canceled;
        drop(outcome);
        self.lane.activity.notify();
        true
    }

    pub fn error(&self) -> Option<String> {
        match &*self
            .shared
            .outcome
            .lock()
            .unwrap_or_else(|error| error.into_inner())
        {
            Outcome::Failed(error) => Some(error.clone()),
            _ => None,
        }
    }

    pub fn data_len(&self) -> Option<usize> {
        match &*self
            .shared
            .outcome
            .lock()
            .unwrap_or_else(|error| error.into_inner())
        {
            Outcome::Ready(Some(bytes)) => Some(bytes.len()),
            Outcome::Ready(None) => Some(0),
            _ => None,
        }
    }

    pub fn copy_data(&self, output: &mut [u8]) -> io::Result<usize> {
        match &*self
            .shared
            .outcome
            .lock()
            .unwrap_or_else(|error| error.into_inner())
        {
            Outcome::Ready(Some(bytes)) => {
                if output.len() < bytes.len() {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidInput,
                        "the transfer output is too small",
                    ));
                }
                output[..bytes.len()].copy_from_slice(bytes);
                Ok(bytes.len())
            }
            Outcome::Ready(None) => Ok(0),
            Outcome::Failed(error) => Err(io::Error::other(error.clone())),
            Outcome::Canceled => Err(io::Error::new(
                io::ErrorKind::Interrupted,
                "the transfer was canceled",
            )),
            Outcome::Pending => Err(io::Error::new(
                io::ErrorKind::WouldBlock,
                "the transfer is still pending",
            )),
        }
    }

    /// Takes ownership of a completed read result. A successful write or copy
    /// answers `None`; a read answers `Some`, including an empty boxed slice.
    pub fn take_bytes(&self) -> io::Result<Option<Box<[u8]>>> {
        let mut outcome = self
            .shared
            .outcome
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        match &mut *outcome {
            Outcome::Ready(bytes) => Ok(bytes.take()),
            Outcome::Failed(error) => Err(io::Error::other(error.clone())),
            Outcome::Canceled => Err(io::Error::new(
                io::ErrorKind::Interrupted,
                "the transfer was canceled",
            )),
            Outcome::Pending => Err(io::Error::new(
                io::ErrorKind::WouldBlock,
                "the transfer is still pending",
            )),
        }
    }
}

impl Drop for Transfer {
    fn drop(&mut self) {
        self.lane.public_requests.fetch_sub(1, Ordering::AcqRel);
    }
}

/// A bounded whole-file lane using Nupp's shared Tokio executor.
#[derive(Clone)]
pub struct FileLane {
    shared: Arc<LaneShared>,
}

impl FileLane {
    pub fn new() -> Self {
        Self {
            shared: Arc::new(LaneShared {
                admission: Mutex::new(Admission::default()),
                public_requests: AtomicUsize::new(0),
                settled: AtomicUsize::new(0),
                activity: Activity {
                    generation: Mutex::new(0),
                    changed: Condvar::new(),
                },
            }),
        }
    }

    pub fn submit_read(&self, path: PathBuf) -> io::Result<Arc<Transfer>> {
        let metadata = fs::metadata(&path)?;
        let charge = usize::try_from(metadata.len()).unwrap_or(usize::MAX);
        let admission = self.admit(charge)?;
        self.spawn(admission, move |admission| {
            read_whole(&path, admission).map(|bytes| Some(bytes.into_boxed_slice()))
        })
    }

    pub fn submit_write(
        &self,
        path: PathBuf,
        contents: Vec<u8>,
        mode: WriteMode,
    ) -> io::Result<Arc<Transfer>> {
        let admission = self.admit(contents.len())?;
        self.spawn(admission, move |_admission| {
            match mode {
                WriteMode::Replace => fs::write(path, contents),
                WriteMode::Append => OpenOptions::new()
                    .append(true)
                    .create(true)
                    .open(path)
                    .and_then(|mut file| file.write_all(&contents)),
                WriteMode::Atomic => write_atomic(&path, &contents),
            }
            .map(|()| None)
        })
    }

    pub fn submit_copy(&self, from: PathBuf, to: PathBuf) -> io::Result<Arc<Transfer>> {
        let admission = self.admit(0)?;
        self.spawn(admission, move |_admission| {
            fs::copy(from, to).map(|_| None)
        })
    }

    pub fn pending(&self) -> usize {
        self.shared.public_requests.load(Ordering::Acquire)
    }

    pub fn generation(&self) -> u64 {
        self.shared.activity.generation()
    }

    pub fn wait(&self, generation: u64, timeout: Duration) -> u64 {
        self.shared.activity.wait(generation, timeout)
    }

    pub fn admitted(&self) -> (usize, usize) {
        let admission = self
            .shared
            .admission
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        (admission.requests, admission.bytes)
    }

    pub fn poll(&self) -> usize {
        self.shared.settled.swap(0, Ordering::AcqRel)
    }

    pub fn wait_for_transfer(&self, timeout: Duration) -> usize {
        let generation = self.generation();
        if self.shared.settled.load(Ordering::Acquire) == 0 {
            self.wait(generation, timeout);
        }
        self.poll()
    }

    fn admit(&self, bytes: usize) -> io::Result<AdmissionGuard> {
        if bytes > MAX_REQUEST_BYTES {
            return Err(io::Error::new(
                io::ErrorKind::FileTooLarge,
                format!("the transfer is larger than the {MAX_REQUEST_BYTES}-byte limit"),
            ));
        }
        let mut admission = self
            .shared
            .admission
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if admission.requests == MAX_REQUESTS {
            return Err(io::Error::other(format!(
                "more than {MAX_REQUESTS} transfers are in flight"
            )));
        }
        let Some(total) = admission.bytes.checked_add(bytes) else {
            return Err(io::Error::other("file transfer byte accounting overflowed"));
        };
        if total > MAX_BYTES {
            return Err(io::Error::other(format!(
                "transfers in flight would hold more than {MAX_BYTES} bytes"
            )));
        }
        admission.requests += 1;
        admission.bytes = total;
        drop(admission);
        Ok(AdmissionGuard {
            lane: Arc::clone(&self.shared),
            bytes,
        })
    }

    fn spawn(
        &self,
        admission: AdmissionGuard,
        work: impl FnOnce(&mut AdmissionGuard) -> io::Result<Option<Box<[u8]>>> + Send + 'static,
    ) -> io::Result<Arc<Transfer>> {
        let executor = nupp_native_runtime::executor().map_err(io::Error::other)?;
        let shared = Arc::new(TransferShared {
            outcome: Mutex::new(Outcome::Pending),
        });
        let task = Arc::clone(&shared);
        let lane = Arc::clone(&self.shared);
        self.shared.public_requests.fetch_add(1, Ordering::AcqRel);
        executor.spawn_blocking(move || {
            let mut admission = admission;
            let settled = task.settle(work(&mut admission));
            drop(admission);
            if settled {
                lane.settled.fetch_add(1, Ordering::AcqRel);
                lane.activity.notify();
            }
        });
        Ok(Arc::new(Transfer {
            shared,
            lane: Arc::clone(&self.shared),
        }))
    }
}

impl Default for FileLane {
    fn default() -> Self {
        Self::new()
    }
}

fn read_whole(path: &Path, admission: &mut AdmissionGuard) -> io::Result<Vec<u8>> {
    let mut file = platform::open_read_nonblocking(path)?;
    let size = usize::try_from(file.metadata()?.len()).unwrap_or(usize::MAX);
    admission.grow_to(size)?;
    let mut bytes = Vec::new();
    if size != 0 {
        bytes.try_reserve_exact(size).map_err(|error| {
            io::Error::other(format!("cannot reserve file transfer storage: {error}"))
        })?;
        let mut remaining = size;
        let mut chunk = [0u8; READ_CHUNK];
        while remaining != 0 {
            let count = file.read(&mut chunk[..remaining.min(READ_CHUNK)])?;
            if count == 0 {
                break;
            }
            bytes.extend_from_slice(&chunk[..count]);
            remaining -= count;
        }
        return Ok(bytes);
    }

    let mut chunk = [0u8; READ_CHUNK];
    loop {
        if bytes.len() == MAX_REQUEST_BYTES {
            let mut extra = [0u8; 1];
            if file.read(&mut extra)? != 0 {
                return Err(io::Error::new(
                    io::ErrorKind::FileTooLarge,
                    format!("the transfer is larger than the {MAX_REQUEST_BYTES}-byte limit"),
                ));
            }
            break;
        }
        let next = bytes
            .len()
            .saturating_add(READ_CHUNK)
            .min(MAX_REQUEST_BYTES);
        admission.grow_to(next)?;
        bytes
            .try_reserve_exact(next - bytes.capacity())
            .map_err(|error| {
                io::Error::other(format!("cannot reserve file transfer storage: {error}"))
            })?;
        let count = file.read(&mut chunk[..next - bytes.len()])?;
        if count == 0 {
            break;
        }
        bytes.extend_from_slice(&chunk[..count]);
    }
    Ok(bytes)
}

fn write_atomic(path: &Path, contents: &[u8]) -> io::Result<()> {
    let directory = path.parent().unwrap_or_else(|| Path::new("."));
    let preserved = fs::metadata(path)
        .ok()
        .map(|metadata| metadata.permissions());
    let mut last_collision = None;
    for _ in 0..TEMPORARY_ATTEMPTS {
        let mut stamp = [0u8; 8];
        getrandom::fill(&mut stamp).map_err(|error| {
            io::Error::other(format!("cannot create a temporary name: {error}"))
        })?;
        let temporary = directory.join(format!(".nupp-write-{:016x}", u64::from_le_bytes(stamp)));
        let mut file = match platform::create_private_file(&temporary) {
            Ok(file) => file,
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
                last_collision = Some(error);
                continue;
            }
            Err(error) => return Err(error),
        };
        let written = (|| {
            if let Some(permissions) = preserved.clone() {
                file.set_permissions(permissions)?;
            }
            file.write_all(contents)?;
            file.sync_all()?;
            drop(file);
            platform::replace(&temporary, path)?;
            platform::sync_parent(path)
        })();
        if written.is_err() {
            let _ = fs::remove_file(&temporary);
        }
        return written;
    }
    Err(last_collision.unwrap_or_else(|| {
        io::Error::new(
            io::ErrorKind::AlreadyExists,
            "no unused atomic-write name was found",
        )
    }))
}

fn global_lane() -> &'static FileLane {
    use std::sync::OnceLock;
    static LANE: OnceLock<FileLane> = OnceLock::new();
    LANE.get_or_init(FileLane::new)
}

pub fn submit_read(path: PathBuf) -> io::Result<Arc<Transfer>> {
    global_lane().submit_read(path)
}

pub fn submit_write(
    path: PathBuf,
    contents: Vec<u8>,
    mode: WriteMode,
) -> io::Result<Arc<Transfer>> {
    global_lane().submit_write(path, contents, mode)
}

pub fn submit_copy(from: PathBuf, to: PathBuf) -> io::Result<Arc<Transfer>> {
    global_lane().submit_copy(from, to)
}

pub fn transfer_poll() -> usize {
    global_lane().poll()
}

pub fn transfer_wait(timeout: Duration) -> usize {
    global_lane().wait_for_transfer(timeout)
}

pub fn transfer_pending() -> usize {
    global_lane().pending()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Barrier};
    use std::time::{Duration, Instant};

    fn root(name: &str) -> PathBuf {
        let mut random = [0u8; 8];
        getrandom::fill(&mut random).unwrap();
        let path = std::env::temp_dir().join(format!(
            "nupp-files-lane-{name}-{:016x}",
            u64::from_le_bytes(random)
        ));
        fs::create_dir_all(&path).unwrap();
        path
    }

    fn await_transfer(lane: &FileLane, transfer: &Transfer) {
        let deadline = Instant::now() + Duration::from_secs(10);
        let mut generation = lane.generation();
        while transfer.status() == TransferStatus::Pending {
            assert!(Instant::now() < deadline, "file transfer timed out");
            generation = lane.wait(generation, Duration::from_millis(100));
        }
    }

    #[test]
    fn whole_file_operations_run_on_the_shared_executor() {
        let root = root("whole");
        let lane = FileLane::new();
        let path = root.join("value.bin");
        let written = lane
            .submit_write(path.clone(), b"a\0b".to_vec(), WriteMode::Replace)
            .unwrap();
        await_transfer(&lane, &written);
        assert_eq!(written.status(), TransferStatus::Ready);
        drop(written);

        let read = lane.submit_read(path.clone()).unwrap();
        await_transfer(&lane, &read);
        let mut bytes = vec![0; read.data_len().unwrap()];
        assert_eq!(read.copy_data(&mut bytes).unwrap(), 3);
        assert_eq!(bytes, b"a\0b");
        drop(read);

        let copied = lane.submit_copy(path, root.join("copy.bin")).unwrap();
        await_transfer(&lane, &copied);
        assert_eq!(copied.status(), TransferStatus::Ready);
        drop(copied);
        assert_eq!(lane.pending(), 0);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn canceled_work_keeps_admission_until_the_worker_finishes() {
        let lane = FileLane::new();
        let barrier = Arc::new(Barrier::new(2));
        let worker_barrier = Arc::clone(&barrier);
        let admission = lane.admit(1024).unwrap();
        let transfer = lane
            .spawn(admission, move |_admission| {
                worker_barrier.wait();
                Ok(None)
            })
            .unwrap();
        assert_eq!(lane.admitted(), (1, 1024));
        assert!(transfer.cancel());
        drop(transfer);
        assert_eq!(lane.pending(), 0);
        assert_eq!(lane.admitted(), (1, 1024));
        barrier.wait();
        let deadline = Instant::now() + Duration::from_secs(10);
        while lane.admitted() != (0, 0) {
            assert!(
                Instant::now() < deadline,
                "canceled worker did not release admission"
            );
            std::thread::yield_now();
        }
    }

    #[test]
    fn request_and_byte_limits_are_enforced() {
        let lane = FileLane::new();
        let mut held = Vec::new();
        for _ in 0..MAX_REQUESTS {
            held.push(lane.admit(0).unwrap());
        }
        assert!(lane.admit(0).is_err());
        drop(held);
        assert_eq!(lane.admitted(), (0, 0));
        assert!(lane.admit(MAX_REQUEST_BYTES + 1).is_err());
    }

    #[test]
    fn atomic_write_preserves_permissions_and_replaces_contents() {
        let root = root("atomic");
        let path = root.join("value.bin");
        fs::write(&path, b"old").unwrap();
        let permissions = fs::metadata(&path).unwrap().permissions();
        write_atomic(&path, b"new").unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"new");
        assert_eq!(
            platform::read_only(&fs::metadata(&path).unwrap().permissions()),
            platform::read_only(&permissions)
        );
        assert!(fs::read_dir(&root).unwrap().all(|entry| {
            !entry
                .unwrap()
                .file_name()
                .to_string_lossy()
                .starts_with(".nupp-write-")
        }));
        fs::remove_dir_all(root).unwrap();
    }
}
