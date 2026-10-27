//! The VM's filesystem provider primitives: `nupp.runtime.provider.nativefiles`
//! on the VM is Nupp over these, as on LuaJIT it is Nupp over the same crate's
//! C ABI. Paths arrive as text; results are plain values the provider shapes
//! into the standard library's records.
use crate::{builtins::Outs, interp::Interp, value::Value};
use nupp_native_files::{self as files, FileKind, OpenFile, OpenMode, SeekOrigin};
use std::path::{Path, PathBuf};

/// Open files by handle number; a handle is spent by `fileClose`.
#[derive(Default)]
pub struct Files {
    pub(crate) next: u64,
    pub(crate) open: std::collections::HashMap<u64, OpenFile>,
    /// What a checkpoint needs to reopen each handle (`crate::snapshot`).
    pub(crate) snapshot: crate::snapshot::FileTracking,
}

fn text(it: &Interp, v: Value) -> PathBuf {
    let bytes = if it.is_stringish(v) { it.bytes_of(v).to_vec() } else { Vec::new() };
    files::path_from_bytes(&bytes).unwrap_or_else(|_| PathBuf::from(String::from_utf8_lossy(&bytes).into_owned()))
}
fn failed(it: &mut Interp, problem: std::io::Error) -> Outs {
    let message = it.heap_new_string(&problem.to_string());
    let mut outs = Outs::new(); outs.push(Value::NIL); outs.push(message); outs
}
fn done(it: &mut Interp, result: std::io::Result<()>) -> Outs {
    match result {
        Ok(()) => { let mut o = Outs::new(); o.push(Value::TRUE); o }
        Err(problem) => { let message = it.heap_new_string(&problem.to_string()); let mut o = Outs::new(); o.push(Value::FALSE); o.push(message); o }
    }
}
fn bytes(it: &mut Interp, result: std::io::Result<Vec<u8>>) -> Outs {
    match result { Ok(b) => { let mut o = Outs::new(); o.push(it.new_string_bytes(&b)); o } Err(e) => failed(it, e) }
}
fn kind(k: FileKind) -> &'static str {
    match k { FileKind::File => "file", FileKind::Directory => "directory", FileKind::Symlink => "symlink", FileKind::Other => "other" }
}
fn arg(args: &[Value], i: usize) -> Value { args.get(i).copied().unwrap_or(Value::NIL) }
fn write_atomic(path: &Path, contents: &[u8]) -> std::io::Result<()> {
    let parent = path.parent().filter(|p| !p.as_os_str().is_empty()).unwrap_or(Path::new("."));
    let temporary = files::path_from_bytes(&files::create_temporary(Some(parent), ".nupp-", ".tmp", files::TemporaryKind::File)?)?;
    let written = (|| {
        use std::io::Write;
        let mut file = std::fs::OpenOptions::new().write(true).truncate(true).open(&temporary)?;
        file.write_all(contents)?;
        if let Ok(existing) = std::fs::metadata(path) { file.set_permissions(existing.permissions())?; }
        file.sync_all()
    })();
    match written.and_then(|()| files::rename(&temporary, path)) {
        Ok(()) => Ok(()),
        Err(problem) => { let _ = std::fs::remove_file(&temporary); Err(problem) }
    }
}

pub fn call(it: &mut Interp, name: &str, args: &[Value]) -> Outs {
    let op = name.strip_prefix("nfiles.").unwrap_or(name);
    match op {
        "info" => match files::info(&text(it, arg(args, 0)), arg(args, 1).truthy()) {
            Ok(info) => {
                let scope = it.open_scope();
                let t = it.new_table(); it.handles.push(t);
                let modified = info.modified.and_then(|m| m.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_secs_f64() * 1000.0).unwrap_or(0.0);
                let size = crate::numeric::unsigned(it, info.size); it.handles.push(size);
                for (key, value) in [("size", size), ("modified", Value::num(modified)), ("readOnly", Value::boolean(info.read_only))] { let k = it.intern(key); it.set_index(t, k, value); }
                let v = it.intern(kind(info.kind)); it.handles.push(v); let k = it.intern("kind"); it.set_index(t, k, v);
                it.close_scope(scope);
                let mut o = Outs::new(); o.push(t); o
            }
            Err(e) => failed(it, e),
        },
        "readLink" => { let r = files::read_link(&text(it, arg(args, 0))); bytes(it, r) }
        "createSymlink" => { let r = files::create_symlink(&text(it, arg(args, 0)), &text(it, arg(args, 1)), arg(args, 2).truthy()); done(it, r) }
        "setReadOnly" => { let r = files::set_read_only(&text(it, arg(args, 0)), arg(args, 1).truthy()); done(it, r) }
        "createDirectory" => { let r = files::create_directory(&text(it, arg(args, 0))); done(it, r) }
        "remove" => { let r = files::remove(&text(it, arg(args, 0)), arg(args, 1).truthy()); done(it, r) }
        "rename" => { let r = files::rename(&text(it, arg(args, 0)), &text(it, arg(args, 1))); done(it, r) }
        "list" => match files::list(&text(it, arg(args, 0))) {
            Ok(entries) => {
                let scope = it.open_scope();
                let list = it.new_table(); it.handles.push(list);
                for (i, entry) in entries.iter().enumerate() {
                    let e = it.new_table(); it.handles.push(e);
                    let v = it.new_string_bytes(&entry.name); it.handles.push(v); let k = it.intern("name"); it.set_index(e, k, v);
                    let v = it.intern(kind(entry.kind)); it.handles.push(v); let k = it.intern("kind"); it.set_index(e, k, v);
                    it.set_index(list, Value::num((i + 1) as f64), e);
                }
                it.close_scope(scope);
                let mut o = Outs::new(); o.push(list); o
            }
            Err(e) => failed(it, e),
        },
        "glob" => {
            let pattern = String::from_utf8_lossy(&it.bytes_of(arg(args, 0)).to_vec()).into_owned();
            match files::glob(&pattern) {
                Ok(paths) => {
                    let scope = it.open_scope();
                    let list = it.new_table(); it.handles.push(list);
                    for (i, p) in paths.iter().enumerate() { let v = it.new_string_bytes(p); it.set_index(list, Value::num((i + 1) as f64), v); }
                    it.close_scope(scope);
                    let mut o = Outs::new(); o.push(list); o
                }
                Err(e) => failed(it, e),
            }
        }
        "read" => { let r = std::fs::read(text(it, arg(args, 0))); bytes(it, r) }
        "write" | "append" | "writeAtomic" => {
            let path = text(it, arg(args, 0));
            let contents = it.bytes_of(arg(args, 1)).to_vec();
            let result = match op {
                "write" => std::fs::write(&path, &contents),
                "append" => { use std::io::Write; std::fs::OpenOptions::new().append(true).create(true).open(&path).and_then(|mut f| f.write_all(&contents)) }
                _ => write_atomic(&path, &contents),
            };
            done(it, result)
        }
        "copy" => { let r = std::fs::copy(text(it, arg(args, 0)), text(it, arg(args, 1))).map(drop); done(it, r) }
        "open" => {
            let mode = match it.bytes_of(arg(args, 1)) { b"r" => OpenMode::Read, b"w" => OpenMode::Write, b"a" => OpenMode::Append, b"r+" => OpenMode::ReadWrite, b"w+" => OpenMode::ReadWriteTruncate, b"a+" => OpenMode::ReadAppend, _ => { let m = it.intern("invalid file mode"); let mut o = Outs::new(); o.push(Value::NIL); o.push(m); return o; } };
            let path = text(it, arg(args, 0));
            match OpenFile::open(&path, mode) {
                Ok(file) => { let id = it.nfiles.next; it.nfiles.next += 1; it.nfiles.open.insert(id, file); it.nfiles.snapshot.opened(id, &path, mode); let mut o = Outs::new(); o.push(crate::numeric::unsigned(it, id)); o }
                Err(e) => failed(it, e),
            }
        }
        "fileRead" | "fileWrite" | "fileSeek" | "filePosition" | "fileSize" | "fileFlush" | "fileClose" => {
            let id = crate::numeric::word(it, arg(args, 0), true);
            if op == "fileClose" { it.nfiles.open.remove(&id); it.nfiles.snapshot.closed(id); return Outs::new(); }
            let Some(file) = it.nfiles.open.get(&id) else { let m = it.intern("the file is closed"); let mut o = Outs::new(); o.push(Value::NIL); o.push(m); return o; };
            match op {
                "fileRead" => {
                    let count = crate::numeric::bits(it, arg(args, 1), true);
                    let mut buffer = vec![0u8; usize::try_from(count).unwrap_or_else(|_| it.err("file read count out of range"))];
                    let r = file.read(&mut buffer).map(|n| { buffer.truncate(n); buffer });
                    bytes(it, r)
                }
                "fileWrite" => { let data = it.bytes_of(arg(args, 1)).to_vec(); match it.nfiles.open[&id].write(&data) { Ok(n) => { let mut o = Outs::new(); o.push(crate::numeric::unsigned(it, n as u64)); o } Err(e) => failed(it, e) } }
                "fileSeek" => {
                    let origin = match it.bytes_of(arg(args, 2)) { b"current" => SeekOrigin::Current, b"end" => SeekOrigin::End, _ => SeekOrigin::Start };
                    let offset = crate::numeric::bits(it, arg(args, 1), false) as i64;
                    match it.nfiles.open[&id].seek(offset, origin) { Ok(p) => { let mut o = Outs::new(); o.push(crate::numeric::unsigned(it, p)); o } Err(e) => failed(it, e) }
                }
                "filePosition" => { let mut o = Outs::new(); let position = file.position(); o.push(crate::numeric::unsigned(it, position)); o }
                "fileSize" => match file.size() { Ok(n) => { let mut o = Outs::new(); o.push(crate::numeric::unsigned(it, n as u64)); o } Err(e) => failed(it, e) },
                _ => { let r = file.flush(); done(it, r) }
            }
        }
        "createTemporary" => {
            let root = it.bytes_of(arg(args, 0)).to_vec();
            let root = if root.is_empty() { None } else { files::path_from_bytes(&root).ok() };
            let prefix = String::from_utf8_lossy(it.bytes_of(arg(args, 1))).into_owned();
            let suffix = String::from_utf8_lossy(it.bytes_of(arg(args, 2))).into_owned();
            let kind = if arg(args, 3).truthy() { files::TemporaryKind::Directory } else { files::TemporaryKind::File };
            let r = files::create_temporary(root.as_deref(), &prefix, &suffix, kind);
            bytes(it, r)
        }
        "currentDirectory" => { let r = files::current_directory(); bytes(it, r) }
        "canonicalize" => { let r = files::canonicalize(&text(it, arg(args, 0))); bytes(it, r) }
        "userFolder" => { let r = files::user_folder(crate::numeric::word(it, arg(args, 0), true) as u32); bytes(it, r) }
        "applicationBase" => { let r = files::application_base(crate::numeric::word(it, arg(args, 0), true) as u32); bytes(it, r) }
        "executablePath" => { let r = files::executable_path(); bytes(it, r) }
        _ => it.err(&format!("unknown filesystem operation {name}")),
    }
}
