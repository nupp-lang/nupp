//! The CLI's standard streams, including bounded reads for framed protocols.
use crate::{builtins::Outs, interp::Interp, value::Value};
use std::io::{BufRead, Read, Write};

pub(crate) fn read(vm: &mut Interp, format: Value) -> Outs {
    let mut stdin = std::io::stdin().lock();
    let mut bytes = Vec::new();
    let count = if format.is_num() {
        let count = format.as_num();
        if !count.is_finite() || count < 0.0 || count.fract() != 0.0 {
            vm.err("invalid stdin read count");
        }
        Some(count as u64)
    } else {
        None
    };
    let spec = if format == Value::NIL {
        b"*l".to_vec()
    } else if count.is_some() {
        Vec::new()
    } else {
        vm.bytes_of(format).to_vec()
    };
    let all = spec == b"*a" || spec == b"a";
    let result = if let Some(0) = count {
        return match stdin.fill_buf() {
            Ok(bytes) if bytes.is_empty() => [Value::NIL].into_iter().collect(),
            Ok(_) => [vm.intern("")].into_iter().collect(),
            Err(error) => [Value::NIL, vm.heap_new_string(&error.to_string())]
                .into_iter()
                .collect(),
        };
    } else if let Some(count) = count {
        stdin.take(count).read_to_end(&mut bytes)
    } else if all {
        stdin.read_to_end(&mut bytes)
    } else if matches!(spec.as_slice(), b"*l" | b"l" | b"*L" | b"L") {
        stdin.read_until(b'\n', &mut bytes)
    } else {
        vm.err("unsupported stdin read format")
    };
    match result {
        Err(error) => [Value::NIL, vm.heap_new_string(&error.to_string())]
            .into_iter()
            .collect(),
        Ok(0) if !all => [Value::NIL].into_iter().collect(),
        Ok(_) => {
            if matches!(spec.as_slice(), b"*l" | b"l") && bytes.last() == Some(&b'\n') {
                bytes.pop();
            }
            [vm.new_string_bytes(&bytes)].into_iter().collect()
        }
    }
}
pub(crate) fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Outs {
    match name {
        "io.stdin.read" => read(vm, args.get(1).copied().unwrap_or(Value::NIL)),
        "io.stdout.flush" | "io.flush" | "io.stderr.flush" => {
            let result = if name == "io.stderr.flush" {
                std::io::stderr().flush()
            } else {
                std::io::stdout().flush()
            };
            match result {
                Ok(()) => [Value::TRUE].into_iter().collect(),
                Err(error) => [Value::NIL, vm.heap_new_string(&error.to_string())]
                    .into_iter()
                    .collect(),
            }
        }
        "io.stdout.setvbuf" | "io.stderr.setvbuf" => {
            // Stream writes flush before returning, which is the CLI's unbuffered mode.
            if args.get(1).map(|value| vm.bytes_of(*value)) != Some(b"no") {
                return [
                    Value::NIL,
                    vm.intern("standard streams support unbuffered mode"),
                ]
                .into_iter()
                .collect();
            }
            [Value::TRUE].into_iter().collect()
        }
        _ => unreachable!(),
    }
}
