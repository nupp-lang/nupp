//! Transactional ownership of worker VMs. Checkpoint bytes and routing epochs
//! belong to the supervisor and are never captured inside the game.
use crate::{
    interp::Interp,
    value::Value,
    workers::{Progress, Worker},
};
use std::{
    cell::RefCell,
    collections::HashMap,
    rc::Rc,
    sync::atomic::{AtomicU64, Ordering},
};
type Result<T> = std::result::Result<T, String>;
static NEXT_GAME: AtomicU64 = AtomicU64::new(1);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Generation {
    game: u64,
    epoch: u64,
}
impl std::fmt::Display for Generation {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}:{}", self.game, self.epoch)
    }
}
struct Inner {
    active: Option<Worker>,
    generation: Generation,
    preparing: bool,
}
pub struct Game {
    inner: Rc<RefCell<Inner>>,
}
/// Dropping an uncommitted preparation discards it and permits the original VM
/// to run again. Neither worker runs while this handle remains prepared.
pub struct PreparedVm {
    inner: Rc<RefCell<Inner>>,
    candidate: Option<Worker>,
    next: Generation,
}
#[derive(Debug)]
pub struct Replacement {
    pub generation: Generation,
    pub retirement_error: Option<String>,
}
impl Game {
    pub fn spawn(parent: &mut Interp, body: Value, args: &[Value]) -> Result<Self> {
        if parent.affine_meta(body) != Value::NIL {
            return Err("supervised bodies cannot transfer VM-local affine capabilities".into());
        }
        Self::from_worker(Worker::spawn(parent, body, args)?)
    }
    fn from_worker(worker: Worker) -> Result<Self> {
        let game = NEXT_GAME
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |id| id.checked_add(1))
            .map_err(|_| "supervisor routing identity exhausted")?;
        Ok(Self {
            inner: Rc::new(RefCell::new(Inner {
                active: Some(worker),
                generation: Generation { game, epoch: 1 },
                preparing: false,
            })),
        })
    }
    pub fn generation(&self) -> Generation {
        self.inner.borrow().generation
    }
    pub fn accepts(&self, generation: Generation) -> bool {
        let inner = self.inner.borrow();
        inner.active.is_some() && !inner.preparing && inner.generation == generation
    }
    fn active<'a>(inner: &'a mut Inner, generation: Generation) -> Result<&'a mut Worker> {
        if inner.generation != generation {
            return Err("retired VM routing generation".into());
        }
        if inner.preparing {
            return Err("game is paused for replacement".into());
        }
        inner.active.as_mut().ok_or_else(|| "game is closed".into())
    }
    pub fn step(&mut self, generation: Generation, now: u64) -> Result<()> {
        Self::active(&mut self.inner.borrow_mut(), generation)?.step(now)
    }
    pub fn poll(&mut self, generation: Generation) -> Result<Option<Progress>> {
        Self::active(&mut self.inner.borrow_mut(), generation)?.poll()
    }
    pub fn capture(&mut self) -> Result<Vec<u8>> {
        let generation = self.generation();
        Self::active(&mut self.inner.borrow_mut(), generation)?.snapshot()
    }
    pub fn prepare_restore(&mut self, bytes: Vec<u8>) -> Result<PreparedVm> {
        self.prepare_validated(bytes, |_| Ok(()))
    }
    pub fn prepare_validated(
        &mut self,
        bytes: Vec<u8>,
        validate: impl FnOnce(&Interp) -> Result<()> + Send + 'static,
    ) -> Result<PreparedVm> {
        let mut inner = self.inner.borrow_mut();
        let generation = inner.generation;
        let next = Generation {
            game: generation.game,
            epoch: generation
                .epoch
                .checked_add(1)
                .ok_or("VM routing generation exhausted")?,
        };
        Self::active(&mut inner, generation)?.quiesce()?;
        let candidate = Self::active(&mut inner, generation)?.restore_bound(bytes, validate)?;
        inner.preparing = true;
        Ok(PreparedVm {
            inner: self.inner.clone(),
            candidate: Some(candidate),
            next,
        })
    }
    pub fn fork(&self, bytes: Vec<u8>) -> Result<Self> {
        let inner = self.inner.borrow();
        let active = inner.active.as_ref().ok_or("game is closed")?;
        Self::from_worker(active.restore_bound(bytes, |_| Ok(()))?)
    }
}
impl Drop for Game {
    fn drop(&mut self) {
        self.inner.borrow_mut().active.take();
    }
}
impl PreparedVm {
    pub fn replace(mut self) -> Result<Replacement> {
        let old = {
            let mut inner = self.inner.borrow_mut();
            if inner.active.is_none() {
                return Err("game is closed".into());
            }
            let old = inner
                .active
                .replace(self.candidate.take().unwrap())
                .unwrap();
            inner.generation = self.next;
            inner.preparing = false;
            old
        };
        // Publication has completed. Retirement failure cannot roll it back.
        Ok(Replacement {
            generation: self.next,
            retirement_error: old.close().err(),
        })
    }
    pub fn close(self) {
        drop(self);
    }
}
impl Drop for PreparedVm {
    fn drop(&mut self) {
        if self.candidate.take().is_some() {
            self.inner.borrow_mut().preparing = false;
        }
    }
}

// Native capability owners are held outside checkpointed game state. Their
// affine Nupp handles explicitly close them; dropping the host drops all owners.
#[derive(Default)]
pub(crate) struct Registry {
    next: u64,
    games: HashMap<u64, Game>,
    prepared: HashMap<u64, PreparedVm>,
    handles: HashMap<u64, (Value, usize, bool)>,
}
impl Registry {
    pub(crate) fn is_empty(&self) -> bool {
        self.games.is_empty() && self.prepared.is_empty()
    }
    fn id(&mut self) -> Result<u64> {
        self.next = self
            .next
            .checked_add(1)
            .filter(|id| *id <= (1u64 << 53))
            .ok_or("VM capability identity exhausted")?;
        Ok(self.next)
    }
}
pub(crate) fn install(vm: &mut Interp) {
    let module = vm.new_table();
    vm.registered.push(module);
    crate::task_api::put(
        vm,
        module,
        "spawn",
        Value::builtin(crate::builtins::id_of("tasks.vmSpawn").unwrap()),
    );
    vm.loaded.insert("nupp.vm".into(), module);
}
fn handle(vm: &mut Interp, id: u64, prepared: bool) -> Value {
    let object = vm.new_table();
    let root = vm.register(object);
    crate::task_api::put(vm, object, "_id", Value::num(id as f64));
    let methods: &[(&str, &str)] = if prepared {
        &[("close", "tasks.vmDiscard")]
    } else {
        &[
            ("capture", "tasks.vmCapture"),
            ("prepareRestore", "tasks.vmPrepare"),
            ("replace", "tasks.vmReplace"),
            ("fork", "tasks.vmFork"),
            ("step", "tasks.vmStep"),
            ("poll", "tasks.vmPoll"),
            ("generation", "tasks.vmGeneration"),
            ("close", "tasks.vmClose"),
        ]
    };
    for &(name, builtin) in methods {
        crate::task_api::put(
            vm,
            object,
            name,
            Value::builtin(crate::builtins::id_of(builtin).unwrap()),
        );
    }
    vm.resources.insert(
        object,
        if prepared {
            "nupp.vm.PreparedVm"
        } else {
            "nupp.vm.Game"
        }
        .into(),
    );
    vm.supervised.handles.insert(id, (object, root, prepared));
    object
}
fn id(vm: &mut Interp, object: Value, prepared: bool) -> Result<u64> {
    let value = crate::task_api::field(vm, object, "_id");
    if !value.is_num() || value.as_num() < 1.0 || value.as_num().fract() != 0.0 {
        return Err("invalid VM capability".into());
    }
    let id = value.as_num() as u64;
    if !vm
        .supervised
        .handles
        .get(&id)
        .is_some_and(|&(canonical, _, kind)| canonical == object && kind == prepared)
    {
        return Err("invalid or closed VM capability".into());
    }
    Ok(id)
}
fn release_handle(vm: &mut Interp, id: u64) {
    if let Some((object, root, _)) = vm.supervised.handles.remove(&id) {
        vm.resources.remove(&object);
        vm.release(root);
    }
}
fn bytes(vm: &mut Interp, value: Value) -> Result<Vec<u8>> {
    if !vm.is_stringish(value) {
        return Err("VM checkpoint must be bytes".into());
    }
    Ok(vm.bytes_of(value).to_vec())
}
pub(crate) fn call(vm: &mut Interp, name: &str, args: &[Value]) -> crate::task_api::Answer {
    use crate::task_api::Answer::Values;
    let arg = |i| args.get(i).copied().unwrap_or(Value::NIL);
    if name == "tasks.vmSpawn" {
        let id = vm.supervised.id().unwrap_or_else(|e| vm.err(&e));
        let game = Game::spawn(vm, arg(0), args.get(1..).unwrap_or_default())
            .unwrap_or_else(|e| vm.err(&e));
        vm.supervised.games.insert(id, game);
        return Values(vec![handle(vm, id, false)]);
    }
    let object = arg(0);
    let key = id(vm, object, name == "tasks.vmDiscard").unwrap_or_else(|e| vm.err(&e));
    if name == "tasks.vmDiscard" {
        vm.supervised.prepared.remove(&key);
        release_handle(vm, key);
        return Values(vec![]);
    }
    if name == "tasks.vmClose" {
        vm.supervised.games.remove(&key);
        release_handle(vm, key);
        return Values(vec![]);
    }
    let Some(mut game) = vm.supervised.games.remove(&key) else {
        vm.err("game is closed");
    };
    // Keep error propagation outside the detached owner interval: pcall uses a
    // VM exception and must leave the original game available after failure.
    let result: Result<Vec<Value>> = (|| match name {
        "tasks.vmGeneration" => Ok(vec![vm.intern(&game.generation().to_string())]),
        "tasks.vmCapture" => Ok(vec![vm.intern_bytes(&game.capture()?)]),
        "tasks.vmPrepare" => {
            let data = bytes(vm, arg(1))?;
            let prepared = game.prepare_restore(data)?;
            let id = vm.supervised.id()?;
            vm.supervised.prepared.insert(id, prepared);
            let owner = handle(vm, id, true);
            crate::task_api::put(vm, owner, "_game", object);
            Ok(vec![owner])
        }
        "tasks.vmReplace" => {
            let prepared_object = arg(1);
            let prepared_id = id(vm, prepared_object, true)?;
            let prepared = vm
                .supervised
                .prepared
                .remove(&prepared_id)
                .ok_or("preparation is closed")?;
            release_handle(vm, prepared_id);
            if !Rc::ptr_eq(&game.inner, &prepared.inner) {
                // `replace` consumes a valid candidate even when this game is
                // the wrong destination. Drop rolls back its original owner.
                return Err("preparation belongs to another game".into());
            }
            let report = prepared.replace()?;
            let generation = vm.intern(&report.generation.to_string());
            let root = vm.register(generation);
            let error = report
                .retirement_error
                .map(|e| vm.intern(&e))
                .unwrap_or(Value::NIL);
            vm.release(root);
            Ok(vec![generation, error])
        }
        "tasks.vmFork" => {
            let id = vm.supervised.id()?;
            let fork = game.fork(bytes(vm, arg(1))?)?;
            vm.supervised.games.insert(id, fork);
            Ok(vec![handle(vm, id, false)])
        }
        "tasks.vmStep" | "tasks.vmPoll" => {
            let token = arg(1);
            if !vm.is_stringish(token)
                || vm.bytes_of(token) != game.generation().to_string().as_bytes()
            {
                return Err("retired VM routing generation".into());
            }
            let generation = game.generation();
            if name == "tasks.vmStep" {
                let now = arg(2);
                if !now.is_num()
                    || !now.as_num().is_finite()
                    || now.as_num() < 0.0
                    || now.as_num().fract() != 0.0
                    || now.as_num() > (1u64 << 53) as f64
                {
                    return Err("VM clock must be a nonnegative exact integer".into());
                }
                game.step(generation, now.as_num() as u64)?;
                Ok(vec![])
            } else if let Some(progress) = game.poll(generation)? {
                let status = match progress.status {
                    crate::scheduler::Status::Active => "active",
                    crate::scheduler::Status::Completed => "done",
                    crate::scheduler::Status::Cancelled => "cancelled",
                    crate::scheduler::Status::Failed(_) => "failed",
                };
                let status = vm.intern(status);
                let root = vm.register(status);
                let values = progress
                    .values
                    .map(|b| vm.intern_bytes(&b))
                    .unwrap_or(Value::NIL);
                vm.release(root);
                Ok(vec![status, values])
            } else {
                Ok(vec![Value::NIL, Value::NIL])
            }
        }
        _ => unreachable!(),
    })();
    vm.supervised.games.insert(key, game);
    Values(result.unwrap_or_else(|e| vm.err(&e)))
}

#[cfg(test)]
mod ownership_tests {
    use super::*;
    #[test]
    fn forged_and_mutated_handles_cannot_select_native_owners() {
        let mut vm = Interp::new();
        vm.install_globals();
        let first_id = vm.supervised.id().unwrap();
        let first = handle(&mut vm, first_id, false);
        let second_id = vm.supervised.id().unwrap();
        let second = handle(&mut vm, second_id, false);
        let fake = vm.new_table();
        crate::task_api::put(&mut vm, fake, "_id", Value::num(first_id as f64));
        assert!(id(&mut vm, fake, false).is_err());
        crate::task_api::put(&mut vm, first, "_id", Value::num(second_id as f64));
        assert!(id(&mut vm, first, false).is_err());
        assert_eq!(id(&mut vm, second, false).unwrap(), second_id);
        assert!(id(&mut vm, second, true).is_err());
        release_handle(&mut vm, first_id);
        release_handle(&mut vm, second_id);
        assert!(vm.supervised.handles.is_empty());
    }
    #[test]
    fn wrong_destination_consumes_candidate_and_resumes_its_owner() {
        fn values(answer: crate::task_api::Answer) -> Vec<Value> {
            match answer {
                crate::task_api::Answer::Values(values) => values,
                _ => panic!("unexpected suspension"),
            }
        }
        let mut vm = Interp::new();
        crate::image::load(
            &mut vm,
            "function value 0 0 2 1 :v\nconst 0 num 42\nK 1 0\nRet 1\nend\nentry 0\n",
        )
        .unwrap();
        vm.install_globals();
        let first = values(call(&mut vm, "tasks.vmSpawn", &[Value::func(0)]))[0];
        let second = values(call(&mut vm, "tasks.vmSpawn", &[Value::func(0)]))[0];
        let snapshot = values(call(&mut vm, "tasks.vmCapture", &[first]))[0];
        let prepared = values(call(&mut vm, "tasks.vmPrepare", &[first, snapshot]))[0];
        let rejected = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            call(&mut vm, "tasks.vmReplace", &[second, prepared])
        }));
        assert!(rejected.is_err());
        assert!(vm.supervised.prepared.is_empty());
        let first_id = id(&mut vm, first, false).unwrap();
        let game = &vm.supervised.games[&first_id];
        assert!(game.accepts(game.generation()));
        assert!(!vm.resources.contains_key(&prepared));
        call(&mut vm, "tasks.vmClose", &[first]);
        call(&mut vm, "tasks.vmClose", &[second]);
        assert!(vm.supervised.is_empty());
        assert!(vm.supervised.handles.is_empty());
    }
}
