//! `nupp.vm.markdown`, the renderer `nupp doc` hands Markdown to: CommonMark
//! with pipe tables, under the collector's stress modes.

#![cfg(feature = "markdown")]

use nupp_vm::{builtins, interp::Interp, value::Value};

fn render(vm: &mut Interp, text: &str) -> String {
    render_bytes(vm, text.as_bytes())
}

fn render_bytes(vm: &mut Interp, text: &[u8]) -> String {
    let source = vm.new_string_bytes(text);
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
    assert_eq!(render(&mut vm, "Term\n: first\n\n    second\n"), "<dl>\n<dt>Term</dt>\n<dd>\n<p>first</p>\n<p>second</p>\n</dd>\n</dl>\n");
    assert_eq!(render(&mut vm, "[**x**](a\0b)\n"), "<p>[<strong>x</strong>](a\0b)</p>\n");
    assert_eq!(render(&mut vm, "[r]: a\0b\n\n[x][r]\n"), "<p>[r]: a\0b</p>\n<p>[x][r]</p>\n");
    assert_eq!(render(&mut vm, "<a href=a\0b>\nnext\n"), "<a href=a\0b>\nnext\n");
    assert_eq!(render(&mut vm, "[x](<a\0b>)\n"), "<p><a href=\"a%00b\">x</a></p>\n");
    assert_eq!(render(&mut vm, "\u{feff}# title\n"), "<p>\u{feff}# title</p>\n");
    assert_eq!(render(&mut vm, "~~strike~~ a^b\n\n\"quote\" -- ...\n"), "<p>~~strike~~ a^b</p>\n<p>\"quote\" -- ...</p>\n");
    assert_eq!(render(&mut vm, "[x](javascript:alert(1))\n"), "<p><a href=\"javascript:alert(1)\">x</a></p>\n");
    assert_eq!(render_bytes(&mut vm, b"\xe2\x82 \xed\xa0\x80 \xf0\x80\x80\x80"), "<p>\u{fffd} \u{fffd}\u{fffd}\u{fffd} \u{fffd}\u{fffd}\u{fffd}\u{fffd}</p>\n");
    assert_eq!(render_bytes(&mut vm, b"\xf0\x90\x80"), "<p>\u{fffd}</p>\n");
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
