use nupp_vm::builtins::pattern::{find, Cap};

fn span(s: &str, p: &str) -> Option<(usize, usize)> {
    find(s.as_bytes(), p.as_bytes(), 0).map(|(a, b, _)| (a, b))
}

#[test]
fn frontiers_match_set_transitions_with_nul_ends() {
    assert_eq!(span("THE (quick) fox", "%f[%a]%a+%f[%A]"), Some((0, 3)));
    assert_eq!(span("fun()", "%f[%a]fun%f[^%w_]"), Some((0, 3)));
    assert_eq!(span("funny()", "%f[%a]fun%f[^%w_]"), None);
    assert_eq!(span("fun", "%f[%a]fun%f[^%w_]"), Some((0, 3)));
}

#[test]
fn balanced_runs_nest() {
    assert_eq!(span("x = f(a(b)c) + 1", "%b()"), Some((5, 12)));
    assert_eq!(span("(open", "%b()"), None);
}

#[test]
fn back_references_repeat_a_closed_capture() {
    assert_eq!(span("hello hello world", "(%a+) %1"), Some((0, 11)));
    let (a, b, caps) = find(b"abcabc", b"(a)(b)c%1%2", 0).unwrap();
    assert_eq!((a, b), (0, 5));
    assert!(matches!(caps[..], [Cap::Span(0, 1), Cap::Span(1, 2)]));
}
