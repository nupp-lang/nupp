//! The clocks and calendar under the guest's `os.time`, `os.clock` and
//! `os.date`: the wall clock, the processor time used, C's broken-down time
//! (gmtime_r, localtime_r and mktime) and strftime for one conversion. The
//! conversions Lua accepts, the fields' Lua meanings and every error are the
//! guest's.
use std::ffi::{c_char, c_int, c_long};

/// C's `struct tm`, laid out alike on macOS and glibc.
#[repr(C)]
struct Tm {
    sec: c_int,
    min: c_int,
    hour: c_int,
    mday: c_int,
    mon: c_int,
    year: c_int,
    wday: c_int,
    yday: c_int,
    isdst: c_int,
    gmtoff: c_long,
    zone: *const c_char,
}

impl Default for Tm {
    fn default() -> Self {
        Tm { sec: 0, min: 0, hour: 0, mday: 0, mon: 0, year: 0, wday: 0, yday: 0, isdst: 0, gmtoff: 0, zone: std::ptr::null() }
    }
}

unsafe extern "C" {
    fn time(out: *mut i64) -> i64;
    fn clock() -> c_long;
    fn gmtime_r(t: *const i64, out: *mut Tm) -> *mut Tm;
    fn localtime_r(t: *const i64, out: *mut Tm) -> *mut Tm;
    fn mktime(tm: *mut Tm) -> i64;
    fn strftime(out: *mut c_char, room: usize, format: *const c_char, tm: *const Tm) -> usize;
}

/// C's CLOCKS_PER_SEC, which POSIX fixes at a million.
const CLOCKS_PER_SEC: f64 = 1_000_000.0;

/// The fields the guest reads and writes, in `struct tm`'s order: seconds,
/// minutes, hours, day of the month, month from 0, years since 1900, day of
/// the week from 0 (Sunday), day of the year from 0, and the daylight-saving
/// flag (negative when unknown).
const FIELDS: usize = 9;

/// The `flags` bit asking for UTC rather than local time.
const UTC: u64 = 1;

/// The one-byte conversions strftime is given, and the two-byte ones after
/// `E` and `O`: C99's, as Lua's LUA_STRFTIMEOPTIONS lists them.
const SINGLE: &[u8] = b"aAbBcCdDeFgGhHIjmMnprRStTuUVwWxXyYzZ%";
const AFTER_E: &[u8] = b"cCxXyY";
const AFTER_O: &[u8] = b"deHImMSuUVwWy";

/// The most bytes one conversion writes, as Lua's SIZETIMEFMT.
const ITEM: usize = 250;

/// The wall clock in whole seconds since the epoch, C's time(NULL). The
/// guest's `os.time()`.
pub extern "C" fn wall_clock() -> u64 {
    (unsafe { time(std::ptr::null_mut()) }) as u64
}

/// The processor time this process has used, in seconds, as Lua's os.clock
/// computes it from C's clock: the binary64 bits.
pub extern "C" fn cpu_clock() -> u64 {
    ((unsafe { clock() }) as f64 / CLOCKS_PER_SEC).to_bits()
}

/// `t` broken down in UTC (`flags` UTC) or local time, or None when the
/// system cannot represent it.
fn broken(t: u64, flags: u64) -> Option<Tm> {
    let seconds = t as i64;
    let mut tm = Tm::default();
    let done = if flags & UTC != 0 {
        unsafe { gmtime_r(&seconds, &mut tm) }
    } else {
        unsafe { localtime_r(&seconds, &mut tm) }
    };
    if done.is_null() { None } else { Some(tm) }
}

/// Writes the FIELDS of `t` broken down, in UTC when `flags` says so, as
/// int64 words at `out`: 0, or -1 when the system cannot represent it.
pub unsafe extern "C" fn time_parts(t: u64, flags: u64, out: u64) -> u64 {
    let Some(tm) = broken(t, flags) else { return u64::MAX };
    let fields = [tm.sec, tm.min, tm.hour, tm.mday, tm.mon, tm.year, tm.wday, tm.yday, tm.isdst];
    let words = unsafe { std::slice::from_raw_parts_mut(out as *mut i64, FIELDS) };
    for (word, field) in words.iter_mut().zip(fields) {
        *word = i64::from(field);
    }
    0
}

/// C's mktime of the FIELDS at `fields` (int64 words, each within an int),
/// writing them back normalized: the time, -1 when mktime failed (or the
/// time is the second before the epoch, which Lua refuses alike).
pub unsafe extern "C" fn time_make(fields: u64) -> u64 {
    let words = unsafe { std::slice::from_raw_parts_mut(fields as *mut i64, FIELDS) };
    let mut tm = Tm {
        sec: words[0] as c_int,
        min: words[1] as c_int,
        hour: words[2] as c_int,
        mday: words[3] as c_int,
        mon: words[4] as c_int,
        year: words[5] as c_int,
        isdst: words[8] as c_int,
        ..Tm::default()
    };
    let t = unsafe { mktime(&mut tm) };
    let fields = [tm.sec, tm.min, tm.hour, tm.mday, tm.mon, tm.year, tm.wday, tm.yday, tm.isdst];
    for (word, field) in words.iter_mut().zip(fields) {
        *word = i64::from(field);
    }
    t as u64
}

/// Whether `spec` is one conversion strftime is given: `%` and an option
/// LUA_STRFTIMEOPTIONS lists.
fn conversion(spec: &[u8]) -> bool {
    match spec {
        [b'%', option] => SINGLE.contains(option),
        [b'%', b'E', option] => AFTER_E.contains(option),
        [b'%', b'O', option] => AFTER_O.contains(option),
        _ => false,
    }
}

/// strftime of the one conversion in the `bytes` bytes at `spec` for `t`
/// broken down as time_parts breaks it, into `out`, at most `room` bytes:
/// the text's length (0 when the conversion is not one), or -1 when the
/// system cannot represent the time.
pub unsafe extern "C" fn time_format(t: u64, flags: u64, spec: u64, bytes: u64, out: u64, room: u64) -> u64 {
    let Some(tm) = broken(t, flags) else { return u64::MAX };
    let spec = unsafe { std::slice::from_raw_parts(spec as *const u8, bytes as usize) };
    if !conversion(spec) {
        return 0;
    }
    let mut format = [0u8; 4];
    format[..spec.len()].copy_from_slice(spec);
    let mut text = [0u8; ITEM];
    let length = unsafe { strftime(text.as_mut_ptr() as *mut c_char, ITEM, format.as_ptr() as *const c_char, &tm) };
    let count = length.min(room as usize);
    unsafe { std::ptr::copy_nonoverlapping(text.as_ptr(), out as *mut u8, count) };
    length as u64
}

#[cfg(test)]
mod tests {
    use super::*;

    fn format(t: i64, spec: &str) -> String {
        let mut out = [0u8; ITEM];
        let length = unsafe {
            time_format(t as u64, UTC, spec.as_ptr() as u64, spec.len() as u64, out.as_mut_ptr() as u64, ITEM as u64)
        };
        String::from_utf8(out[..length as usize].to_vec()).unwrap()
    }

    #[test]
    fn epoch_in_utc() {
        let mut fields = [0i64; FIELDS];
        assert_eq!(unsafe { time_parts(0, UTC, fields.as_mut_ptr() as u64) }, 0);
        assert_eq!(fields, [0, 0, 0, 1, 0, 70, 4, 0, 0]);
        assert_eq!(format(0, "%Y-%m-%d %H:%M:%S"), "");
        assert_eq!(format(0, "%Y"), "1970");
        assert_eq!(format(86400 * 365, "%j"), "001");
        assert_eq!(format(0, "%Q"), "");
    }

    #[test]
    fn make_normalizes() {
        // 2020-13-32 is 2021-02-01.
        let mut fields = [0i64, 0, 12, 32, 12, 120, 0, 0, -1];
        let t = unsafe { time_make(fields.as_mut_ptr() as u64) } as i64;
        assert_ne!(t, -1);
        assert_eq!(&fields[3..6], &[1, 1, 121]);
    }

    #[test]
    fn clocks_move() {
        assert!(wall_clock() > 1_600_000_000);
        assert!(f64::from_bits(cpu_clock()) >= 0.0);
    }
}
