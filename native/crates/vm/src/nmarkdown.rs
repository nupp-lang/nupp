//! Markdown for `nupp doc`: CommonMark with pipe tables, rendered to HTML by
//! `pulldown-cmark`, installed as `nupp.vm.markdown` (the `nmarkdown.`
//! builtins). The documentation generator owns everything around the
//! rendering -- fenced blocks, containers, heading ids -- and hands this only
//! the Markdown left once those are lifted out.
use crate::{
    builtins::{type_name, Outs},
    interp::Interp,
    value::Value,
};
use pulldown_cmark::{html, Options, Parser};

fn arg(args: &[Value], i: usize) -> Value { args.get(i).copied().unwrap_or(Value::NIL) }

/// `render(text)`: the HTML for a Markdown document. Text that is not UTF-8
/// is read with each invalid sequence replaced, since HTML output is UTF-8.
fn render(it: &mut Interp, args: &[Value]) -> Outs {
    let v = arg(args, 0);
    if !it.is_stringish(v) { it.err(&format!("bad argument #1 to 'render' (string expected, got {})", type_name(it, v))); }
    let text = String::from_utf8_lossy(it.bytes_of(v)).into_owned();
    let mut out = String::with_capacity(text.len() + text.len() / 2);
    html::push_html(&mut out, Parser::new_ext(&text, Options::ENABLE_TABLES));
    let result = it.string_of(out.as_bytes());
    [result].into_iter().collect()
}

pub fn call(it: &mut Interp, name: &str, args: &[Value]) -> Outs {
    let mark = it.open_scope();
    it.handles.extend_from_slice(args);
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| match name {
        "nmarkdown.render" => render(it, args),
        _ => it.err(&format!("unknown Markdown operation {name}")),
    }));
    it.close_scope(mark);
    match result { Ok(out) => out, Err(e) => std::panic::resume_unwind(e) }
}
