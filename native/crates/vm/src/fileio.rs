//! Writable file handles used by compiler caches and Lua source tests.
//! Open handles are external resources: snapshots require an explicit codec.
use crate::{builtins::Outs, interp::Interp, value::Value};
use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};

fn result(values: &[Value]) -> Outs {
    values.iter().copied().collect()
}
fn failure(vm: &mut Interp, problem: std::io::Error) -> Outs {
    let message = vm.heap_new_string(&problem.to_string());
    result(&[
        Value::NIL,
        message,
        Value::num(problem.raw_os_error().unwrap_or(0) as f64),
    ])
}

pub fn open(vm: &mut Interp, path: &str, mode: &str) -> Outs {
    if !matches!(
        mode,
        "w" | "wb"
            | "a"
            | "ab"
            | "r+"
            | "r+b"
            | "rb+"
            | "w+"
            | "w+b"
            | "wb+"
            | "a+"
            | "a+b"
            | "ab+"
    ) {
        return result(&[Value::NIL, vm.intern("invalid file mode")]);
    }
    let append = mode.starts_with('a');
    let opened = OpenOptions::new()
        .read(mode.contains('+'))
        .write(true)
        .create(mode.starts_with('w') || append)
        .truncate(mode.starts_with('w'))
        .append(append)
        .open(path);
    let file = match opened {
        Ok(file) => file,
        Err(error) => return failure(vm, error),
    };
    let object = vm.new_table();
    let root = vm.register(object);
    for (key, builtin) in [
        ("read", "file.read"),
        ("write", "file.write"),
        ("close", "file.close"),
        ("lines", "file.lines"),
        ("setvbuf", "file.setvbuf"),
        ("flush", "file.flush"),
    ] {
        let key = vm.intern(key);
        vm.set_index(
            object,
            key,
            Value::builtin(crate::builtins::id_of(builtin).unwrap()),
        );
    }
    let key = vm.intern("_nativeFile");
    vm.set_index(object, key, Value::TRUE);
    vm.resources.insert(object, "nupp.io.file".into());
    vm.native_files.insert(object, file);
    vm.release(root);
    result(&[object])
}

pub fn is_native(vm: &mut Interp, object: Value) -> bool {
    let key = vm.intern("_nativeFile");
    vm.get_index(object, key) == Value::TRUE
}

pub fn close(vm: &mut Interp, object: Value) -> Outs {
    if let Some(mut file) = vm.native_files.remove(&object) {
        vm.resources.remove(&object);
        if let Err(error) = file.flush() {
            return failure(vm, error);
        }
        drop(file);
        result(&[Value::TRUE])
    } else {
        result(&[Value::NIL, vm.intern("file is already closed")])
    }
}

pub fn write(vm: &mut Interp, args: &[Value]) -> Outs {
    let object = args[0];
    if !vm.native_files.contains_key(&object) {
        vm.err("attempt to write a closed or non-writable file");
    }
    for &value in &args[1..] {
        let bytes = if value.is_num() {
            crate::builtins::num_text(value.as_num()).into_bytes()
        } else if vm.is_stringish(value) {
            vm.bytes_of(value).to_vec()
        } else {
            vm.err("file:write expects strings or numbers")
        };
        if let Err(error) = vm.native_files.get_mut(&object).unwrap().write_all(&bytes) {
            return failure(vm, error);
        }
    }
    result(&[object])
}

pub fn read(vm: &mut Interp, object: Value, format: Value) -> Outs {
    let count = if format.is_num() {
        let number = format.as_num();
        if !number.is_finite() || number < 0.0 || number.fract() != 0.0 {
            vm.err("invalid file read count");
        }
        Some(number as u64)
    } else {
        None
    };
    let format = if format == Value::NIL {
        b"*l".to_vec()
    } else if count.is_some() {
        Vec::new()
    } else {
        vm.bytes_of(format).to_vec()
    };
    let file = match vm.native_files.get_mut(&object) {
        Some(file) => file,
        None => vm.err("attempt to read a closed file"),
    };
    if count == Some(0) {
        let checked = (|| {
            let position = file.stream_position()?;
            let found = file.read(&mut [0])?;
            file.seek(SeekFrom::Start(position))?;
            Ok::<_, std::io::Error>(found != 0)
        })();
        return match checked {
            Ok(true) => result(&[vm.new_string_bytes(b"")]),
            Ok(false) => result(&[Value::NIL]),
            Err(error) => failure(vm, error),
        };
    }
    let mut bytes = Vec::new();
    let read = if let Some(count) = count {
        file.take(count).read_to_end(&mut bytes).map(|_| ())
    } else if format == b"*a" || format == b"a" {
        file.read_to_end(&mut bytes).map(|_| ())
    } else if format == b"*l" || format == b"l" || format == b"*L" || format == b"L" {
        read_line(file, &mut bytes)
    } else {
        vm.err("unsupported file read format")
    };
    if let Err(error) = read {
        return failure(vm, error);
    }
    if bytes.is_empty() && count != Some(0) && format != b"*a" && format != b"a" {
        return result(&[Value::NIL]);
    }
    if (format == b"*l" || format == b"l") && bytes.last() == Some(&b'\n') {
        bytes.pop();
    }
    result(&[vm.new_string_bytes(&bytes)])
}

fn read_line(file: &mut File, bytes: &mut Vec<u8>) -> std::io::Result<()> {
    let mut byte = [0];
    while file.read(&mut byte)? != 0 {
        bytes.push(byte[0]);
        if byte[0] == b'\n' {
            break;
        }
    }
    Ok(())
}

/// Reserve a fresh path atomically; Lua's os.tmpname leaves an empty file.
pub fn temporary_name(vm: &mut Interp) -> Outs {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    for _ in 0..64 {
        let serial = NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let path =
            std::env::temp_dir().join(format!("nupp-{}-{nonce}-{serial}", std::process::id()));
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        match options.open(&path) {
            Ok(file) => {
                drop(file);
                return result(&[vm.heap_new_string(&path.to_string_lossy())]);
            }
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => vm.err(&format!("os.tmpname: {error}")),
        }
    }
    vm.err("os.tmpname: could not reserve a unique path")
}
