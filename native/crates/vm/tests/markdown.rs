//! `nupp.vm.markdown`, the renderer `nupp doc` hands Markdown to: CommonMark
//! with pipe tables, under the collector's stress modes.

#![cfg(feature = "markdown")]

use nupp_vm::{builtins, interp::Interp, value::Value};

fn render(vm: &mut Interp, text: &str) -> String {
    let source = vm.new_string_bytes(text.as_bytes());
    vm.register(source);
    let callee = Value::builtin(builtins::id_of("nmarkdown.render").unwrap());
    let out = vm.pcall_values(callee, &[source]);
    assert_eq!(out[0], Value::TRUE, "render raised");
    String::from_utf8(vm.bytes_of(out[1]).to_vec()).unwrap()
}

fn suite(stress: bool) {
    let mut vm = Box::new(Interp::new());
    if stress {
        vm.heap.stress = true;
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
    }
    vm.install_globals();
    assert_eq!(render(&mut vm, "# Title\n\nSome *emphasis* and `code`.\n"), "<h1>Title</h1>\n<p>Some <em>emphasis</em> and <code>code</code>.</p>\n");
    assert_eq!(
        render(&mut vm, "| a | b |\n| --- | --- |\n| 1 | 2 |\n"),
        "<table><thead><tr><th>a</th><th>b</th></tr></thead><tbody>\n<tr><td>1</td><td>2</td></tr>\n</tbody></table>\n"
    );
    // The generator lifts its own blocks out and leaves a comment where each
    // was; the renderer must hand a comment back untouched.
    assert_eq!(render(&mut vm, "Before.\n\n<!--nuppdoc-block-1-->\n\nAfter.\n"), "<p>Before.</p>\n<!--nuppdoc-block-1-->\n<p>After.</p>\n");
    assert_eq!(render(&mut vm, "[a link](https://example.com/a(b)) & <tag>\n"), "<p><a href=\"https://example.com/a(b)\">a link</a> &amp; <tag></p>\n");
    let source = vm.new_string_bytes(b"bad \xff byte");
    vm.register(source);
    let callee = Value::builtin(builtins::id_of("nmarkdown.render").unwrap());
    let out = vm.pcall_values(callee, &[source]);
    assert_eq!(vm.bytes_of(out[1]), "<p>bad \u{fffd} byte</p>\n".as_bytes());
    let out = vm.pcall_values(callee, &[Value::num(1.0)]);
    assert_eq!(out[0], Value::FALSE, "a number is not a document");
}

#[test]
fn markdown_renders_commonmark_with_tables() {
    suite(false);
    suite(true);
}
