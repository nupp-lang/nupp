//! Opt-in, process-local JSONL cost output. GPU timestamps are reported separately
//! from host API durations; neither is silently substituted for the other.
use crate::GpuError;
use serde_json::{Value, json};
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};
static CONFIGURED: AtomicBool = AtomicBool::new(false);
static ACTIVE: AtomicBool = AtomicBool::new(false);
use std::time::Instant;

#[derive(Default)]
struct Output {
    initialized: bool,
    file: Option<File>,
    error: Option<String>,
    sequence: u64,
}

fn output() -> &'static Mutex<Output> {
    static OUTPUT: OnceLock<Mutex<Output>> = OnceLock::new();
    OUTPUT.get_or_init(|| Mutex::new(Output::default()))
}

fn open(path: &str) -> Result<File, GpuError> {
    OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(path)
        .map_err(|error| GpuError::InvalidArgument(format!("GPU cost output {path}: {error}")))
}

/// A missing override restores the environment default. Each call closes the
/// previous output, surfacing any write failure before changing destinations.
pub fn configure(path: Option<&str>) -> Result<(), GpuError> {
    let mut state = output().lock().unwrap_or_else(|p| p.into_inner());
    if let Some(error) = state.error.take() {
        return Err(GpuError::InvalidArgument(error));
    }
    let file = match path {
        Some(path) => Some(open(path)?),
        None => None,
    };
    ACTIVE.store(file.is_some(), Ordering::Release);
    CONFIGURED.store(path.is_some(), Ordering::Release);
    *state = Output {
        initialized: path.is_some(),
        file,
        ..Output::default()
    };
    Ok(())
}

pub fn enabled() -> bool {
    if CONFIGURED.load(Ordering::Acquire) {
        return ACTIVE.load(Ordering::Acquire);
    }
    let mut state = output().lock().unwrap_or_else(|p| p.into_inner());
    if !state.initialized {
        state.initialized = true;
        if let Ok(path) = std::env::var("NUPP_GPU_COSTS") {
            if !path.is_empty() {
                match open(&path) {
                    Ok(file) => state.file = Some(file),
                    Err(error) => state.error = Some(error.to_string()),
                }
            }
        }
    }
    let active = state.file.is_some();
    ACTIVE.store(active, Ordering::Release);
    CONFIGURED.store(true, Ordering::Release);
    active
}

pub fn clock() -> Option<Instant> {
    enabled().then(Instant::now)
}
pub fn elapsed(start: Option<Instant>) -> Value {
    start.map_or(Value::Null, |start| {
        json!(start.elapsed().as_secs_f64() * 1000.0)
    })
}

fn encode_record(context: u64, operation: &str, mut values: Value, sequence: u64) -> Vec<u8> {
    values["schemaVersion"] = json!(1);
    values["processId"] = json!(std::process::id());
    values["sequence"] = json!(sequence);
    values["context"] = json!(context);
    values["operation"] = json!(operation);
    values["target"] = json!("gpu");
    let mut bytes = serde_json::to_vec(&values).expect("JSON values serialize");
    bytes.push(b'\n');
    bytes
}

pub fn record(context: u64, operation: &str, values: Value) {
    if !enabled() {
        return;
    }
    let mut state = output().lock().unwrap_or_else(|p| p.into_inner());
    state.sequence += 1;
    let bytes = encode_record(context, operation, values, state.sequence);
    if let Some(file) = state.file.as_mut() {
        if let Err(error) = file.write_all(&bytes) {
            state.error = Some(format!("GPU cost output: {error}"));
        }
    }
}

pub fn cleanup(start: Option<Instant>) -> Value {
    json!({"hostMs": elapsed(start)})
}

pub fn check() -> Result<(), GpuError> {
    let mut state = output().lock().unwrap_or_else(|p| p.into_inner());
    match state.error.take() {
        Some(error) => Err(GpuError::InvalidArgument(error)),
        None => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn records_are_json_and_keep_host_and_gpu_times_distinct() {
        let bytes = encode_record(
            7,
            "kernel",
            json!({"sourceFile": "a\"b\\c.nupp", "hostMs": 1.0, "gpuMs": null, "gpuTiming": "unavailable"}),
            1,
        );
        let row: Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(row["sourceFile"], "a\"b\\c.nupp");
        assert!(row["gpuMs"].is_null());
        assert_eq!(row["hostMs"], 1.0);
        assert_eq!(row["sequence"], 1);
    }
}
