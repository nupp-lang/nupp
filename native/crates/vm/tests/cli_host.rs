use nupp_vm::{interp::Interp, value::Value};
use std::io::IsTerminal;

#[test]
fn cli_host_modules_are_available_before_loading_an_image() {
    let mut vm = Interp::new();
    vm.install_globals();

    let io = vm.require("io");
    let stdin = vm.intern("stdin");
    assert_ne!(vm.get_index(io, stdin), Value::NIL);

    let terminal = vm.require("nupp.cli.internal.terminalhost");
    let is_terminal = vm.intern("isTerminal");
    let is_terminal = vm.get_index(terminal, is_terminal);
    let answer = vm.call_value(is_terminal, &[Value::num(1.0)]);
    assert_eq!(answer, vec![Value::boolean(std::io::stdout().is_terminal())]);

    let clock = vm.require("nupp.tools.build.clockhost");
    let now = vm.intern("now");
    let now = vm.get_index(clock, now);
    let before = vm.call_value(now, &[])[0].as_num();
    let after = vm.call_value(now, &[])[0].as_num();
    assert!(before > 1_400_000_000_000.0 && after >= before);
}
