//! Monotonic host time with a checkpoint-relative origin.
use crate::{builtins::Outs, interp::Interp, value::Value};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub(crate) struct Clock {
    origin: Instant,
    base: f64,
}
impl Default for Clock {
    fn default() -> Self {
        Self {
            origin: Instant::now(),
            base: nupp_native_platform::monotonic_ns() as f64 / 1.0e6,
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
            if !value.is_num() || !value.as_num().is_finite() || value.as_num() < 0.0 {
                vm.err("sleep duration must be a finite non-negative number");
            }
            let duration = Duration::try_from_secs_f64(value.as_num() / 1000.0)
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
