//! Calendar formatting through the executing host's C time implementation.
use crate::{builtins::Outs, interp::Interp, value::Value};
use std::ffi::CString;

unsafe extern "C" {
    fn strftime(
        out: *mut libc::c_char,
        size: usize,
        format: *const libc::c_char,
        time: *const libc::tm,
    ) -> usize;
}

pub(crate) fn date(vm: &mut Interp, args: &[Value]) -> Outs {
    let format = args.first().copied().unwrap_or(Value::NIL);
    let format = if format == Value::NIL {
        b"%c".to_vec()
    } else {
        if !vm.is_stringish(format) {
            vm.err("date format must be a string");
        }
        vm.bytes_of(format).to_vec()
    };
    let stamp = args.get(1).copied().unwrap_or(Value::NIL);
    let seconds = if stamp == Value::NIL {
        nupp_native_platform::wall_ms() as f64 / 1000.0
    } else {
        if !stamp.is_num() {
            vm.err("date timestamp must be a number");
        }
        stamp.as_num()
    };
    if !seconds.is_finite()
        || seconds < libc::time_t::MIN as f64
        || seconds >= libc::time_t::MAX as f64
    {
        vm.err("date timestamp is outside the host range");
    }
    let timestamp = seconds as libc::time_t;
    let utc = format.first() == Some(&b'!');
    let format = if utc { &format[1..] } else { &format[..] };
    let mut time: libc::tm = unsafe { std::mem::zeroed() };
    #[cfg(not(windows))]
    let valid = unsafe {
        !(if utc {
            libc::gmtime_r(&timestamp, &mut time)
        } else {
            libc::localtime_r(&timestamp, &mut time)
        })
        .is_null()
    };
    #[cfg(windows)]
    let valid = unsafe {
        (if utc {
            libc::gmtime_s(&mut time, &timestamp)
        } else {
            libc::localtime_s(&mut time, &timestamp)
        }) == 0
    };
    if !valid {
        vm.err("date timestamp cannot be represented");
    }
    if format == b"*t" {
        let table = vm.new_table();
        let root = vm.register(table);
        for (name, value) in [
            ("sec", time.tm_sec),
            ("min", time.tm_min),
            ("hour", time.tm_hour),
            ("day", time.tm_mday),
            ("month", time.tm_mon + 1),
            ("year", time.tm_year + 1900),
            ("wday", time.tm_wday + 1),
            ("yday", time.tm_yday + 1),
        ] {
            let key = vm.intern(name);
            vm.set_index(table, key, Value::num(value as f64));
        }
        if time.tm_isdst >= 0 {
            let key = vm.intern("isdst");
            vm.set_index(table, key, Value::boolean(time.tm_isdst != 0));
        }
        vm.release(root);
        return [table].into_iter().collect();
    }
    let mut index = 0;
    while index < format.len() {
        if format[index] == b'%' {
            index += 1;
            if index >= format.len() || !b"aAbBcdHIjmMpSUwWxXyYzZ%".contains(&format[index]) {
                vm.err("invalid date format conversion");
            }
        }
        index += 1;
    }
    // A prefix distinguishes a valid empty expansion from a short output buffer.
    let mut marked = vec![b'x'];
    marked.extend_from_slice(format);
    let format =
        CString::new(marked).unwrap_or_else(|_| vm.err("date format contains a zero byte"));
    let mut size = 128;
    while size <= 1 << 20 {
        let mut bytes = vec![0; size];
        let count = unsafe { strftime(bytes.as_mut_ptr().cast(), size, format.as_ptr(), &time) };
        if count > 0 {
            return [vm.new_string_bytes(&bytes[1..count])]
                .into_iter()
                .collect();
        }
        size *= 2;
    }
    vm.err("formatted date exceeds the host buffer limit")
}
