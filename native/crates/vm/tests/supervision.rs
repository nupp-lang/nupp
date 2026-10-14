use nupp_vm::{
    image,
    interp::Interp,
    persist::{self, Policies},
    scheduler::Status,
    supervision::Game,
    value::Value,
};
const PROGRAM: &str = r#"
function count 0 1 7 1 v:v
const 0 num 0
const 1 num 1
K 2 0
K 3 1
K 4 0
Add 2 2 3
Sub 1 1 3
Le 5 1 4
JmpIfNot 5 -4
Ret 2
end
entry 0
"#;
fn game() -> Game {
    let mut vm = Interp::new();
    image::load(&mut vm, PROGRAM).unwrap();
    vm.install_globals();
    Game::spawn(&mut vm, Value::func(0), &[Value::num(30000.0)]).unwrap()
}
fn finish(game: &mut Game) -> f64 {
    let generation = game.generation();
    for _ in 0..4000 {
        game.step(generation, 0).unwrap();
        if let Some(progress) = game.poll(generation).unwrap() {
            if progress.status != Status::Active {
                assert_eq!(progress.status, Status::Completed);
                let mut vm = Interp::new();
                return persist::load_graph(
                    &mut vm,
                    &progress.values.unwrap(),
                    &Policies::default(),
                    None,
                )
                .unwrap()[0]
                    .as_num();
            }
        }
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
    panic!("game did not finish");
}
#[test]
fn preparation_failure_and_discard_resume_original_without_running_candidate() {
    let mut game = game();
    let generation = game.generation();
    let bytes = game.capture().unwrap();
    assert!(game.prepare_restore(vec![1, 2, 3]).is_err());
    assert!(game
        .prepare_validated(bytes.clone(), |_| Err("validation rejected".into()))
        .is_err());
    assert!(game.accepts(generation));
    {
        let prepared = game.prepare_restore(bytes).unwrap();
        assert!(!game.accepts(generation));
        assert!(game.step(generation, 0).is_err());
        assert!(game.capture().is_err());
        prepared.close();
    }
    assert!(game.accepts(generation));
    assert_eq!(finish(&mut game), 30000.0);
}
#[test]
fn replacement_advances_routing_without_rewinding_and_rejects_old_completions() {
    let mut game = game();
    let bytes = game.capture().unwrap();
    let old = game.generation();
    game.step(old, 0).unwrap();
    let report = game
        .prepare_restore(bytes.clone())
        .unwrap()
        .replace()
        .unwrap();
    assert_eq!(report.retirement_error, None);
    assert_ne!(old, report.generation);
    assert!(!game.accepts(old));
    assert!(game.poll(old).is_err());
    assert!(game.step(old, 0).is_err());
    let next = game
        .prepare_restore(bytes)
        .unwrap()
        .replace()
        .unwrap()
        .generation;
    assert_ne!(next, report.generation);
    assert!(!game.accepts(report.generation));
    assert_eq!(finish(&mut game), 30000.0);
}
#[test]
fn fork_has_an_independent_route_and_lifetime() {
    let mut source = game();
    let bytes = source.capture().unwrap();
    let mut branch = source.fork(bytes).unwrap();
    assert_ne!(source.generation(), branch.generation());
    assert!(!branch.accepts(source.generation()));
    drop(source);
    assert_eq!(finish(&mut branch), 30000.0);
}
#[test]
fn closing_game_invalidates_its_prepared_candidate() {
    let mut source = game();
    let bytes = source.capture().unwrap();
    let prepared = source.prepare_restore(bytes).unwrap();
    drop(source);
    assert!(prepared.replace().is_err());
}

#[test]
fn different_code_requires_migration_before_attaching_native_entries() {
    let mut original = game();
    let mut other_vm = Interp::new();
    image::load(
        &mut other_vm,
        &PROGRAM.replace("const 1 num 1", "const 1 num 2"),
    )
    .unwrap();
    other_vm.install_globals();
    let mut other = Game::spawn(&mut other_vm, Value::func(0), &[Value::num(30000.0)]).unwrap();
    let checkpoint = other.capture().unwrap();
    assert!(original
        .prepare_restore(checkpoint.clone())
        .err()
        .unwrap()
        .contains("migration"));
    assert!(original
        .fork(checkpoint)
        .err()
        .unwrap()
        .contains("migration"));
    assert_eq!(finish(&mut original), 30000.0);
}
