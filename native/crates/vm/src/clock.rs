//! Monotonic host time with a checkpoint-relative origin.
use crate::{builtins::Outs, interp::Interp, value::Value};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
#[cfg(any(target_vendor = "apple", target_os = "windows"))]
use std::sync::OnceLock;

pub(crate) struct Clock {
    origin: Instant,
    base: f64,
}
impl Default for Clock {
    fn default() -> Self {
        Self {
            origin: Instant::now(),
            base: monotonic_ns() as f64 / 1.0e6,
        }
    }
}
impl Clock {
    pub(crate) fn now(&self) -> f64 {
        self.base + self.origin.elapsed().as_secs_f64() * 1000.0
    }
    pub(crate) fn restore(&mut self, base: f64) {
        self.base = base;
        self.origin = Instant::now();
    }
}
pub(crate) fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Outs {
    match name {
        "vm.clockNow" => [Value::num(vm.clock.now())].into_iter().collect(),
        "vm.clockWall" => [Value::num(
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs_f64()
                * 1000.0,
        )]
        .into_iter()
        .collect(),
        "vm.clockSleep" => {
            let value = args.first().copied().unwrap_or(Value::NIL);
            if !crate::numeric::is_numeric(value) {
                vm.err("sleep duration must be a finite non-negative number");
            }
            let number = crate::numeric::double(vm, value);
            if !number.is_finite() || number < 0.0 {
                vm.err("sleep duration must be a finite non-negative number");
            }
            let duration = Duration::try_from_secs_f64(number / 1000.0)
                .unwrap_or_else(|_| vm.err("sleep duration is too large"));
            std::thread::sleep(duration);
            Outs::new()
        }
        _ => unreachable!(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::persist::{self, Policies, ResourceCodecs};

    #[test]
    fn checkpoint_restores_the_monotonic_origin_but_not_wall_time() {
        let mut vm = Interp::new();
        vm.install_globals();
        vm.clock.restore(100_000.0);
        let before = call(&mut vm, "vm.clockNow", &[])[0].as_num();
        let bytes = persist::save_vm(
            &mut vm,
            &Policies::default(),
            &mut ResourceCodecs::default(),
        )
        .unwrap();
        vm.clock.restore(9_000_000.0);
        let mut restored =
            persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::default()).unwrap();
        let after = call(&mut restored, "vm.clockNow", &[])[0].as_num();
        assert!(after >= before && after < 200_000.0);
        let wall = call(&mut restored, "vm.clockWall", &[])[0].as_num();
        assert!(wall > 1.7e12);
    }
}

/// The operating system's monotonic clock, in nanoseconds: where a fresh
/// VM's clock starts.
fn monotonic_ns() -> u64 {
    platform_monotonic_ns()
}

#[cfg(target_vendor = "apple")]
#[repr(C)]
struct MachTimebaseInfo {
    numer: u32,
    denom: u32,
}

#[cfg(target_vendor = "apple")]
unsafe extern "C" {
    fn mach_absolute_time() -> u64;
    fn mach_timebase_info(info: *mut MachTimebaseInfo) -> i32;
}

#[cfg(target_vendor = "apple")]
fn platform_monotonic_ns() -> u64 {
    static TIMEBASE: OnceLock<(u64, u64)> = OnceLock::new();
    let (numer, denom) = *TIMEBASE.get_or_init(|| {
        let mut info = MachTimebaseInfo { numer: 0, denom: 0 };
        // SAFETY: `info` is writable and the Darwin function fills this fixed
        // record without retaining the pointer.
        let status = unsafe { mach_timebase_info(&mut info) };
        assert_eq!(status, 0, "mach_timebase_info failed");
        assert_ne!(
            info.denom, 0,
            "mach_timebase_info returned a zero denominator"
        );
        (u64::from(info.numer), u64::from(info.denom))
    });
    // SAFETY: this has no arguments and returns the kernel's monotonic ticks.
    let ticks = unsafe { mach_absolute_time() };
    (u128::from(ticks) * u128::from(numer) / u128::from(denom)).min(u128::from(u64::MAX)) as u64
}

#[cfg(all(unix, not(target_vendor = "apple")))]
#[repr(C)]
struct Timespec {
    seconds: std::os::raw::c_long,
    nanoseconds: std::os::raw::c_long,
}

#[cfg(all(unix, not(target_vendor = "apple")))]
unsafe extern "C" {
    fn clock_gettime(clock: i32, time: *mut Timespec) -> i32;
}

#[cfg(all(unix, not(target_vendor = "apple")))]
fn platform_monotonic_ns() -> u64 {
    const CLOCK_MONOTONIC: i32 = 1;
    let mut time = Timespec {
        seconds: 0,
        nanoseconds: 0,
    };
    // SAFETY: `time` is writable and clock_gettime does not retain it.
    let status = unsafe { clock_gettime(CLOCK_MONOTONIC, &mut time) };
    assert_eq!(status, 0, "clock_gettime(CLOCK_MONOTONIC) failed");
    let seconds = u64::try_from(time.seconds).expect("monotonic seconds are non-negative");
    let nanoseconds =
        u64::try_from(time.nanoseconds).expect("monotonic nanoseconds are non-negative");
    seconds
        .saturating_mul(1_000_000_000)
        .saturating_add(nanoseconds)
}

#[cfg(target_os = "windows")]
#[link(name = "kernel32")]
unsafe extern "system" {
    fn QueryPerformanceCounter(value: *mut i64) -> i32;
    fn QueryPerformanceFrequency(value: *mut i64) -> i32;
}

#[cfg(target_os = "windows")]
fn platform_monotonic_ns() -> u64 {
    static FREQUENCY: OnceLock<u64> = OnceLock::new();
    let frequency = *FREQUENCY.get_or_init(|| {
        let mut value = 0_i64;
        // SAFETY: `value` is writable and the Windows API does not retain it.
        let status = unsafe { QueryPerformanceFrequency(&mut value) };
        assert_ne!(status, 0, "QueryPerformanceFrequency failed");
        u64::try_from(value).expect("performance-counter frequency is positive")
    });
    let mut value = 0_i64;
    // SAFETY: `value` is writable and the Windows API does not retain it.
    let status = unsafe { QueryPerformanceCounter(&mut value) };
    assert_ne!(status, 0, "QueryPerformanceCounter failed");
    let ticks = u64::try_from(value).expect("performance-counter reading is non-negative");
    (u128::from(ticks) * 1_000_000_000 / u128::from(frequency)).min(u128::from(u64::MAX)) as u64
}
