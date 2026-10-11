//! The host services on the parking surface (contracts 6.3): a task that
//! calls one submits a request, parks on its key, and is resumed with the
//! completion by whoever drives the scheduler. The requests are plain data,
//! so the host threads never see a heap value, and the completions are
//! turned into values on the interpreter's thread.
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex};

pub const HOST_BASE: u32 = 1000;
/// Service names, in id order from `HOST_BASE`. The first four park; the
/// rest answer at once.
pub const HOST_NAMES: &[&str] = &["readFile", "writeFile", "sleep", "run", "listDir", "now", "getenv"];
pub const PARKING: usize = 4;

pub enum Req { ReadFile(String), WriteFile(String, Vec<u8>), Sleep(u64), Run(String, Vec<String>), ListDir(String) }
pub enum Done { Text(Result<String, String>), Unit(Result<(), String>), Exit(Result<(i64, String), String>), List(Result<Vec<String>, String>) }

pub struct Host {
    tx: Sender<(u64, Req)>,
    rx: Receiver<(u64, Done)>,
    next: u64,
    pub outstanding: usize,
}

impl Host {
    /// `threads` workers over one request queue; a request is served by
    /// whichever is free, so independent reads overlap.
    pub fn start(threads: usize) -> Host {
        let (tx, req_rx) = channel::<(u64, Req)>();
        let (done_tx, rx) = channel::<(u64, Done)>();
        let req_rx = Arc::new(Mutex::new(req_rx));
        for _ in 0..threads {
            let req_rx = req_rx.clone(); let done_tx = done_tx.clone();
            std::thread::spawn(move || loop {
                let next = { let guard = req_rx.lock().unwrap(); guard.recv() };
                let (key, req) = match next { Ok(x) => x, Err(_) => return };
                let done = match req {
                    Req::ReadFile(p) => Done::Text(std::fs::read_to_string(&p).map_err(|e| e.to_string())),
                    Req::WriteFile(p, data) => Done::Unit(std::fs::write(&p, data).map_err(|e| e.to_string())),
                    Req::Sleep(ms) => { std::thread::sleep(std::time::Duration::from_millis(ms)); Done::Unit(Ok(())) }
                    Req::Run(cmd, args) => Done::Exit(std::process::Command::new(&cmd).args(&args).output().map(|o| (o.status.code().unwrap_or(-1) as i64, String::from_utf8_lossy(&o.stdout).into_owned())).map_err(|e| e.to_string())),
                    Req::ListDir(p) => Done::List(std::fs::read_dir(&p).map_err(|e| e.to_string()).and_then(|d| d.map(|e| e.map(|e| e.file_name().to_string_lossy().into_owned()).map_err(|e| e.to_string())).collect())),
                };
                if done_tx.send((key, done)).is_err() { return; }
            });
        }
        Host { tx, rx, next: 1, outstanding: 0 }
    }
    pub fn submit(&mut self, req: Req) -> u64 { let key = self.next; self.next += 1; self.outstanding += 1; self.tx.send((key, req)).expect("host thread"); key }
    /// A completion if one has arrived.
    pub fn poll(&mut self) -> Option<(u64, Done)> { let r = self.rx.try_recv().ok(); if r.is_some() { self.outstanding -= 1; } r }
    /// Blocks for the next completion; `None` when nothing is outstanding.
    pub fn wait(&mut self) -> Option<(u64, Done)> { if self.outstanding == 0 { return None; } let r = self.rx.recv().ok(); if r.is_some() { self.outstanding -= 1; } r }
}
