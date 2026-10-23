//! VM handles for the shared native child-process transport.
use crate::{builtins::Outs, interp::Interp, value::Value};
use nupp_native_process as native;
use std::{collections::HashMap, ffi::OsString, sync::Arc, time::Duration};

#[derive(Default)]
pub(crate) struct State {
    children: HashMap<Value, Arc<native::ChildProcess>>,
    streams: HashMap<Value, Arc<native::ProcessStream>>,
    peeked: HashMap<Value, u8>,
}
impl Drop for State {
    fn drop(&mut self) {
        for stream in self.streams.values() {
            stream.close();
        }
        for child in self.children.values() {
            let _ = child.kill(true);
        }
    }
}
fn field(vm: &mut Interp, value: Value, name: &str) -> Value {
    let key = vm.intern(name);
    vm.get_index_any(value, key)
}
fn text(vm: &Interp, value: Value) -> String {
    if !vm.is_stringish(value) {
        vm.err("process argument must be a string");
    }
    String::from_utf8_lossy(vm.bytes_of(value)).into_owned()
}
fn options(vm: &mut Interp, value: Value) -> native::SpawnOptions {
    let argv = field(vm, value, "args");
    let args = (1..=vm.array_len(argv))
        .map(|index| OsString::from(text(vm, vm.get_index(argv, Value::num(index as f64)))))
        .collect();
    let env = field(vm, value, "env");
    let env = if env == Value::NIL {
        Vec::new()
    } else {
        vm.table_keys(env)
            .into_iter()
            .map(|key| {
                (
                    OsString::from(text(vm, key)),
                    OsString::from(text(vm, vm.get_index(env, key))),
                )
            })
            .collect()
    };
    let cwd = field(vm, value, "cwd");
    // A working directory may be a path value, which names itself through tostring.
    let cwd = (cwd != Value::NIL).then(|| if vm.is_stringish(cwd) { OsString::from(text(vm, cwd)) } else { OsString::from(String::from_utf8_lossy(&crate::builtins::tostring(vm, cwd)).into_owned()) });
    let clear_env = field(vm, value, "clearEnv").truthy();
    let modes = ["stdin", "stdout", "stderr"].map(|name| {
        let mode = field(vm, value, name);
        match if mode == Value::NIL {
            "pipe".to_owned()
        } else {
            text(vm, mode)
        }
        .as_str()
        {
            "pipe" => native::StdioMode::Pipe,
            "inherit" => native::StdioMode::Inherit,
            "null" => native::StdioMode::Null,
            "stdout" if name == "stderr" => native::StdioMode::Stdout,
            _ => vm.err("invalid process stream mode"),
        }
    });
    native::SpawnOptions {
        args,
        env,
        clear_env,
        cwd,
        modes,
        raw_last: false,
    }
}
fn spawn(vm: &mut Interp, options: native::SpawnOptions) -> Outs {
    match native::spawn(options) {
        Err(problem) => [
            Value::NIL,
            Value::NIL,
            Value::NIL,
            Value::NIL,
            Value::num(0.0),
            vm.heap_new_string(&problem),
        ]
        .into_iter()
        .collect(),
        Ok(spawned) => {
            let child = vm.new_table();
            vm.resources.insert(child, "nupp.io.process.child".into());
            let pid = spawned.child.id();
            vm.processes.children.insert(child, spawned.child);
            let mut output = vec![child];
            for stream in spawned.streams {
                output.push(if let Some(stream) = stream {
                    let handle = vm.new_table();
                    vm.resources.insert(handle, "nupp.io.process.stream".into());
                    vm.processes.streams.insert(handle, stream);
                    handle
                } else {
                    Value::NIL
                });
            }
            output.extend([Value::num(pid as f64), Value::NIL]);
            output.into_iter().collect()
        }
    }
}
fn stream(vm: &Interp, handle: Value) -> Arc<native::ProcessStream> {
    vm.processes
        .streams
        .get(&handle)
        .cloned()
        .unwrap_or_else(|| vm.err("process stream is closed"))
}
fn child(vm: &Interp, handle: Value) -> Arc<native::ChildProcess> {
    vm.processes
        .children
        .get(&handle)
        .cloned()
        .unwrap_or_else(|| vm.err("process child is released"))
}
fn wait_exit(child: &Arc<native::ChildProcess>) -> native::Exit {
    loop {
        if let Some(exit) = child.collect_exit() {
            return exit;
        }
        native::wait_ready(Some(child), &[], Duration::from_secs(1));
    }
}
fn shell(command: &str) -> native::SpawnOptions {
    #[cfg(unix)]
    let args = vec!["/bin/sh".into(), "-c".into(), command.into()];
    #[cfg(windows)]
    let args = vec![
        std::env::var_os("COMSPEC").unwrap_or("cmd.exe".into()),
        "/d".into(),
        "/s".into(),
        "/c".into(),
        command.into(),
    ];
    native::SpawnOptions {
        args,
        env: Vec::new(),
        clear_env: false,
        cwd: None,
        modes: [native::StdioMode::Inherit; 3],
        raw_last: true,
    }
}
pub(crate) fn execute(vm: &mut Interp, args: &[Value]) -> Outs {
    let command = args.first().copied().unwrap_or(Value::NIL);
    let command = if command == Value::NIL {
        String::new()
    } else {
        text(vm, command)
    };
    match native::spawn(shell(&command)) {
        Ok(spawned) => {
            let exit = wait_exit(&spawned.child);
            let _ = spawned.child.reap();
            // Lua 5.1's os.execute returns a numeric shell status.
            #[cfg(unix)]
            let code = if exit.killed {
                exit.code.saturating_sub(128)
            } else {
                exit.code << 8
            };
            #[cfg(not(unix))]
            let code = exit.code;
            [Value::num(code as f64)].into_iter().collect()
        }
        Err(problem) => [Value::NIL, vm.heap_new_string(&problem)]
            .into_iter()
            .collect(),
    }
}
/// What a text-mode read on Windows answers for `bytes`: every CRLF a newline.
fn text_mode(bytes: Vec<u8>) -> Vec<u8> {
    if !bytes.contains(&b'\r') {
        return bytes;
    }
    let mut out = Vec::with_capacity(bytes.len());
    let mut at = 0;
    while at < bytes.len() {
        if bytes[at] == b'\r' && bytes.get(at + 1) == Some(&b'\n') {
            at += 1;
            continue;
        }
        out.push(bytes[at]);
        at += 1;
    }
    out
}

pub(crate) fn popen(vm: &mut Interp, args: &[Value]) -> Outs {
    let command = text(vm, args.first().copied().unwrap_or(Value::NIL));
    let mode = args.get(1).copied().unwrap_or(Value::NIL);
    let mode = if mode == Value::NIL {
        "r".to_owned()
    } else {
        text(vm, mode)
    };
    if mode != "r" && mode != "w" {
        return [Value::NIL, vm.intern("invalid popen mode")]
            .into_iter()
            .collect();
    }
    let mut options = shell(&command);
    let direction = if mode == "r" { 1 } else { 0 };
    options.modes[direction] = native::StdioMode::Pipe;
    match native::spawn(options) {
        Err(problem) => [Value::NIL, vm.heap_new_string(&problem)]
            .into_iter()
            .collect(),
        Ok(mut spawned) => {
            let handle = vm.new_table();
            let root = vm.register(handle);
            for (name, builtin) in [
                ("read", "process.pipeRead"),
                ("write", "process.pipeWrite"),
                ("close", "process.pipeClose"),
                ("lines", "file.lines"),
            ] {
                let key = vm.intern(name);
                vm.set_index(
                    handle,
                    key,
                    Value::builtin(crate::builtins::id_of(builtin).unwrap()),
                );
            }
            let key = vm.intern("_processPipe");
            vm.set_index(handle, key, Value::TRUE);
            vm.resources.insert(handle, "nupp.io.process.pipe".into());
            vm.processes.children.insert(handle, spawned.child);
            vm.processes
                .streams
                .insert(handle, spawned.streams[direction].take().unwrap());
            vm.release(root);
            [handle].into_iter().collect()
        }
    }
}
pub(crate) fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Outs {
    let handle = args.first().copied().unwrap_or(Value::NIL);
    match name {
        "process.spawn" => {
            let options = options(vm, handle);
            spawn(vm, options)
        }
        "process.poll" => match child(vm, handle).collect_exit() {
            Some(exit) => [Value::num(exit.code as f64), Value::boolean(exit.killed)]
                .into_iter()
                .collect(),
            None => [Value::NIL, Value::FALSE].into_iter().collect(),
        },
        "process.kill" => {
            child(vm, handle)
                .kill(args.get(1).copied().unwrap_or(Value::FALSE).truthy())
                .unwrap_or_else(|e| vm.err(&e));
            Outs::new()
        }
        "process.read" => {
            let count = args.get(1).copied().unwrap_or(Value::num(65536.0)).as_num();
            if count < 1.0 || count.fract() != 0.0 || count > 0x7fff_ffff as f64 {
                vm.err("invalid process read size");
            }
            let mut buffer = vec![0; (count as usize).min(65536)];
            match stream(vm, handle)
                .try_read(&mut buffer)
                .unwrap_or_else(|e| vm.err(&e))
            {
                native::Read::Data(n) => [vm.new_string_bytes(&buffer[..n])].into_iter().collect(),
                native::Read::WouldBlock => [vm.intern("")].into_iter().collect(),
                native::Read::Gone => [Value::NIL].into_iter().collect(),
            }
        }
        "process.write" => {
            let bytes = args.get(1).copied().unwrap_or(Value::NIL);
            if !vm.is_stringish(bytes) {
                vm.err("process write requires bytes");
            }
            let (n, gone) = match stream(vm, handle)
                .try_write(vm.bytes_of(bytes))
                .unwrap_or_else(|e| vm.err(&e))
            {
                native::Write::Accepted(n) => (n, false),
                native::Write::WouldBlock => (0, false),
                native::Write::Gone => (0, true),
            };
            [Value::num(n as f64), Value::boolean(gone)]
                .into_iter()
                .collect()
        }
        "process.closeStream" => {
            if let Some(stream) = vm.processes.streams.remove(&handle) {
                stream.close();
                vm.resources.remove(&handle);
            }
            [Value::TRUE].into_iter().collect()
        }
        "process.reap" => {
            if let Some(child) = vm.processes.children.get(&handle) {
                if let Err(error) = child.reap() {
                    return [Value::FALSE, vm.heap_new_string(&error)]
                        .into_iter()
                        .collect();
                }
            }
            if vm.processes.children.remove(&handle).is_some() {
                vm.resources.remove(&handle);
            }
            [Value::TRUE].into_iter().collect()
        }
        "process.waitReady" => {
            let child_handle = field(vm, handle, "child");
            let child = vm.processes.children.get(&child_handle).cloned();
            let mut streams = Vec::new();
            for name in ["read", "write"] {
                let list = field(vm, handle, name);
                for index in 1..=vm.array_len(list) {
                    streams.push(stream(vm, vm.get_index(list, Value::num(index as f64))));
                }
            }
            let ms = args.get(1).copied().unwrap_or(Value::num(0.0)).as_num();
            if !ms.is_finite() || ms < 0.0 {
                vm.err("invalid process wait duration");
            }
            let count = native::wait_ready(
                child.as_ref(),
                &streams,
                Duration::from_secs_f64(ms.min(2147483647.0) / 1000.0),
            );
            [Value::num(count as f64)].into_iter().collect()
        }
        "process.pipeClose" => {
            vm.processes.peeked.remove(&handle);
            if let Some(stream) = vm.processes.streams.remove(&handle) {
                stream.close();
            }
            let Some(child) = vm.processes.children.remove(&handle) else {
                return [Value::NIL, vm.intern("pipe is closed")]
                    .into_iter()
                    .collect();
            };
            let exit = wait_exit(&child);
            let _ = child.reap();
            vm.resources.remove(&handle);
            [
                if exit.code == 0 && !exit.killed {
                    Value::TRUE
                } else {
                    Value::NIL
                },
                vm.intern(if exit.killed { "signal" } else { "exit" }),
                Value::num(if exit.killed {
                    exit.code.saturating_sub(128)
                } else {
                    exit.code
                } as f64),
            ]
            .into_iter()
            .collect()
        }
        "process.pipeRead" => {
            let pipe = stream(vm, handle);
            let format = args.get(1).copied().unwrap_or(Value::NIL);
            let numeric = format.is_num();
            let spec = if numeric || format == Value::NIL {
                String::new()
            } else {
                text(vm, format)
            };
            let all = spec == "*a" || spec == "a";
            let line = !numeric && !all;
            if line && !matches!(spec.as_str(), "" | "l" | "*l" | "L" | "*L") {
                vm.err("unsupported pipe read format");
            }
            let limit = if numeric {
                let n = format.as_num();
                if n < 0.0 || n.fract() != 0.0 {
                    vm.err("invalid read count");
                }
                n as usize
            } else {
                usize::MAX
            };
            if limit == 0 {
                if vm.processes.peeked.contains_key(&handle) {
                    return [vm.intern("")].into_iter().collect();
                }
                loop {
                    let mut byte = [0];
                    match pipe.try_read(&mut byte).unwrap_or_else(|e| vm.err(&e)) {
                        native::Read::Data(_) => {
                            vm.processes.peeked.insert(handle, byte[0]);
                            return [vm.intern("")].into_iter().collect();
                        }
                        native::Read::Gone => return [Value::NIL].into_iter().collect(),
                        native::Read::WouldBlock => {
                            native::wait_ready(None, &[pipe.clone()], Duration::from_secs(1));
                        }
                    }
                }
            }
            let mut output = Vec::new();
            while output.len() < limit {
                let mut buffer = vec![
                    0;
                    if line {
                        1
                    } else {
                        65536.min(limit - output.len())
                    }
                ];
                let read = if let Some(byte) = vm.processes.peeked.remove(&handle) {
                    buffer[0] = byte;
                    native::Read::Data(1)
                } else {
                    pipe.try_read(&mut buffer).unwrap_or_else(|e| vm.err(&e))
                };
                match read {
                    native::Read::Data(n) => {
                        if line && buffer[0] == b'\n' {
                            // A popen pipe is text, as C's is: on Windows the
                            // child's CRLF reads as one newline.
                            if cfg!(windows) && output.last() == Some(&b'\r') {
                                output.pop();
                            }
                            if spec.ends_with('L') {
                                output.push(b'\n');
                            }
                            return [vm.new_string_bytes(&output)].into_iter().collect();
                        }
                        output.extend_from_slice(&buffer[..n]);
                    }
                    native::Read::WouldBlock => {
                        native::wait_ready(None, &[pipe.clone()], Duration::from_secs(1));
                    }
                    native::Read::Gone => break,
                }
            }
            if cfg!(windows) && !line {
                output = text_mode(output);
            }
            if output.is_empty() && !all && limit != 0 {
                [Value::NIL].into_iter().collect()
            } else {
                [vm.new_string_bytes(&output)].into_iter().collect()
            }
        }
        "process.pipeWrite" => {
            let pipe = stream(vm, handle);
            for &value in &args[1..] {
                let bytes = if value.is_num() {
                    crate::builtins::num_text(value.as_num()).into_bytes()
                } else {
                    text(vm, value).into_bytes()
                };
                let mut at = 0;
                while at < bytes.len() {
                    match pipe.try_write(&bytes[at..]).unwrap_or_else(|e| vm.err(&e)) {
                        native::Write::Accepted(n) => at += n,
                        native::Write::WouldBlock => {
                            native::wait_ready(None, &[pipe.clone()], Duration::from_secs(1));
                        }
                        native::Write::Gone => {
                            return [Value::NIL, vm.intern("broken pipe")].into_iter().collect();
                        }
                    }
                }
            }
            [handle].into_iter().collect()
        }
        _ => unreachable!(),
    }
}
