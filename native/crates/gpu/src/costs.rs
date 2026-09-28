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
#[cfg(test)]
pub(crate) static TEST_LOCK: Mutex<()> = Mutex::new(());
use std::time::Instant;

#[derive(Default)]
struct Output {
    initialized: bool,
    file: Option<File>,
    error: Option<String>,
    /// Numbers every record this process writes, across every destination.
    sequence: u64,
    /// The environment's destination has been opened once already. Restoring
    /// it later appends, where truncating would lose what it holds.
    environment_opened: bool,
}

fn output() -> &'static Mutex<Output> {
    static OUTPUT: OnceLock<Mutex<Output>> = OnceLock::new();
    OUTPUT.get_or_init(|| Mutex::new(Output::default()))
}

fn open(path: &str, truncate: bool) -> Result<File, GpuError> {
    OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(truncate)
        .append(!truncate)
        .open(path)
        .map_err(|error| GpuError::InvalidArgument(format!("GPU cost output {path}: {error}")))
}

/// A missing override restores the environment default. Each call closes the
/// previous output and switches to the new one, then reports any write failure
/// the previous output had: the switch happens either way, so a caller moving
/// away from a failing destination gets there.
pub fn configure(path: Option<&str>) -> Result<(), GpuError> {
    let mut state = output().lock().unwrap_or_else(|p| p.into_inner());
    let previous = state.error.take();
    let (file, failure) = match path.map(|path| open(path, true)).transpose() {
        Ok(file) => (file, None),
        Err(error) => (None, Some(error)),
    };
    ACTIVE.store(file.is_some(), Ordering::Release);
    CONFIGURED.store(path.is_some() && file.is_some(), Ordering::Release);
    *state = Output {
        initialized: path.is_some() && file.is_some(),
        file,
        error: None,
        sequence: state.sequence,
        environment_opened: state.environment_opened,
    };
    match (previous, failure) {
        (Some(previous), Some(error)) => Err(GpuError::CostOutput(format!("{previous}; {error}"))),
        (Some(previous), None) => Err(GpuError::CostOutput(previous)),
        (None, Some(error)) => Err(error),
        (None, None) => Ok(()),
    }
}

pub fn enabled() -> bool {
    if CONFIGURED.load(Ordering::Acquire) {
        return ACTIVE.load(Ordering::Acquire);
    }
    let mut state = output().lock().unwrap_or_else(|p| p.into_inner());
    if !state.initialized {
        state.initialized = true;
        if let Ok(path) = std::env::var("NUPP_GPU_COSTS") {
            open_environment(&mut state, &path);
        }
    }
    let active = state.file.is_some();
    ACTIVE.store(active, Ordering::Release);
    CONFIGURED.store(true, Ordering::Release);
    active
}

/// Opens the environment's destination: truncated the first time this process
/// opens it, appended to every time a caller restores it after that.
fn open_environment(state: &mut Output, path: &str) {
    if path.is_empty() {
        return;
    }
    match open(path, !state.environment_opened) {
        Ok(file) => {
            state.file = Some(file);
            state.environment_opened = true;
        }
        Err(error) => state.error = Some(error.to_string()),
    }
}

#[cfg(test)]
pub(crate) fn inject_failure(message: &str) {
    output().lock().unwrap_or_else(|p| p.into_inner()).error = Some(message.to_owned());
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
        Some(error) => Err(GpuError::CostOutput(error)),
        None => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn closing_after_a_write_error_preserves_the_error_and_resets_the_sink() {
        let _guard = TEST_LOCK.lock().unwrap();
        let path =
            std::env::temp_dir().join(format!("nupp-gpu-cost-close-{}.jsonl", std::process::id()));
        configure(Some(path.to_str().unwrap())).unwrap();
        {
            let mut state = output().lock().unwrap();
            state.error = Some("injected write failure".to_owned());
            state.sequence = 7;
        }
        let result = configure(None);
        assert!(
            matches!(result, Err(GpuError::CostOutput(error)) if error == "injected write failure")
        );
        {
            let state = output().lock().unwrap();
            assert!(
                state.file.is_none(),
                "failed close retained the output file"
            );
            assert!(state.error.is_none());
            assert!(!state.initialized);
            assert_eq!(
                state.sequence, 7,
                "the sequence runs on across destinations"
            );
        }
        assert!(!ACTIVE.load(Ordering::Acquire));
        assert!(!CONFIGURED.load(Ordering::Acquire));
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn a_failed_output_still_gives_way_to_the_next_one() {
        let _guard = TEST_LOCK.lock().unwrap();
        let next =
            std::env::temp_dir().join(format!("nupp-gpu-cost-next-{}.jsonl", std::process::id()));
        let _ = std::fs::remove_file(&next);
        inject_failure("injected write failure");
        let result = configure(Some(next.to_str().unwrap()));
        assert!(
            matches!(result, Err(GpuError::CostOutput(error)) if error == "injected write failure")
        );
        assert!(next.exists(), "the new destination was not opened");
        assert!(enabled());
        configure(None).unwrap();
        std::fs::remove_file(next).unwrap();
    }

    #[test]
    fn restoring_the_environment_destination_appends_to_it() {
        let _guard = TEST_LOCK.lock().unwrap();
        let path =
            std::env::temp_dir().join(format!("nupp-gpu-cost-env-{}.jsonl", std::process::id()));
        std::fs::write(&path, b"stale\n").unwrap();
        let path_text = path.to_str().unwrap();
        let mut state = Output::default();
        open_environment(&mut state, path_text);
        state.file.as_mut().unwrap().write_all(b"first\n").unwrap();
        state.file = None;
        open_environment(&mut state, path_text);
        state.file.as_mut().unwrap().write_all(b"second\n").unwrap();
        drop(state);
        assert_eq!(std::fs::read(&path).unwrap(), b"first\nsecond\n");
        std::fs::remove_file(path).unwrap();
    }

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
