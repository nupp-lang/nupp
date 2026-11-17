//! Markdown for `nupp doc`: CommonMark with pipe tables and definition lists,
//! rendered to HTML by pinned cmark-gfm, installed as `nupp.vm.markdown` (the
//! `nmarkdown.` builtins). The documentation generator owns everything around the
//! rendering -- fenced blocks, containers, heading ids -- and hands this only
//! the Markdown left once those are lifted out.
use crate::{
    builtins::{type_name, Outs},
    interp::Interp,
    value::Value,
};
use std::ffi::{c_char, c_void};

unsafe extern "C" {
    fn nupp_markdown_new() -> *mut c_void;
    fn nupp_markdown_render(document: *mut c_void, text: *const c_char, count: usize, budget: usize) -> i32;
    fn nupp_markdown_text(document: *const c_void) -> *const u8;
    fn nupp_markdown_size(document: *const c_void) -> usize;
    fn nupp_markdown_free(document: *mut c_void);
}
struct Document(*mut c_void);
impl Drop for Document {
    fn drop(&mut self) { unsafe { nupp_markdown_free(self.0) } }
}

fn arg(args: &[Value], i: usize) -> Value { args.get(i).copied().unwrap_or(Value::NIL) }

/// `render(text)`: the HTML for a Markdown document. Text that is not UTF-8
/// is read with each invalid sequence replaced, since HTML output is UTF-8.
fn render(it: &mut Interp, args: &[Value]) -> Outs {
    let v = arg(args, 0);
    if !it.is_stringish(v) { it.err(&format!("bad argument #1 to 'render' (string expected, got {})", type_name(it, v))); }
    if it.bytes_of(v).len() > 8 * 1024 * 1024 { it.err("Markdown input exceeds 8 MiB"); }
    let text = String::from_utf8_lossy(it.bytes_of(v)).into_owned();
    if text.len() > 8 * 1024 * 1024 { it.err("Markdown decoded input exceeds 8 MiB"); }
    let document = Document(unsafe { nupp_markdown_new() });
    if document.0.is_null() { it.err("Markdown allocation failed"); }
    let status = unsafe { nupp_markdown_render(document.0, text.as_ptr().cast(), text.len(), 128 * 1024 * 1024) };
    if status != 0 { it.err("Markdown resource limit or allocation failure"); }
    let size = unsafe { nupp_markdown_size(document.0) };
    if size > 32 * 1024 * 1024 { it.err("Markdown output exceeds 32 MiB"); }
    let out = unsafe { std::slice::from_raw_parts(nupp_markdown_text(document.0), size) };
    let result = it.string_of(out);
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
