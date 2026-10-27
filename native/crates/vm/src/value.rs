//! The value word (contracts 1.1): a double is itself; everything else lives
//! in the quiet-NaN space with a 3-bit tag at bits 48..50 and a 48-bit payload.
//! A computed NaN is canonicalised to the bare quiet NaN so it never aliases a
//! tag. A function handle carries an image id in its high 16 payload bits and
//! an image-local index below (3.1a); image `RUNTIME_IMAGE` is the runtime's
//! own table of builtins and host services.

use std::hash::Hasher;
use std::ptr::NonNull;

use crate::heap::Header;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(transparent)]
pub struct Value(pub u64);

pub const QNAN: u64 = 0x7ff8_0000_0000_0000;
pub const TAG_SHIFT: u64 = 48;
pub const TAG_MASK: u64 = 0x7 << TAG_SHIFT;
pub const PAYLOAD: u64 = (1 << 48) - 1;
pub const T_NIL: u64 = 1 << TAG_SHIFT;
pub const T_FALSE: u64 = 2 << TAG_SHIFT;
pub const T_TRUE: u64 = 3 << TAG_SHIFT;
pub const T_FUNC: u64 = 4 << TAG_SHIFT;
pub const T_OBJ: u64 = 5 << TAG_SHIFT;
pub const T_PARKED: u64 = 6 << TAG_SHIFT;
pub const T_INTEGER: u64 = 7 << TAG_SHIFT;

/// The image id of the runtime's own functions: builtins and host services.
pub const RUNTIME_IMAGE: u16 = 0xffff;

impl std::hash::Hash for Value {
    fn hash<H: Hasher>(&self, h: &mut H) { h.write_u64(self.0) }
}

impl Value {
    pub const NIL: Value = Value(QNAN | T_NIL);
    pub const FALSE: Value = Value(QNAN | T_FALSE);
    pub const TRUE: Value = Value(QNAN | T_TRUE);
    /// What a resumable activation returns when it parked (contracts 6.2).
    pub const PARKED: Value = Value(QNAN | T_PARKED);
    /// What a helper or a compiled function returns when a raise is
    /// propagating: the value itself waits in `Interp::pending_error`, and
    /// the nearest catch point (a `pcall`, or the runner) takes it up.
    /// Raises unwind VM frames, never native ones (contracts 6.4, 6.5).
    pub const ERROR: Value = Value(QNAN | T_PARKED | 1);

    #[inline]
    pub fn num(x: f64) -> Value {
        let b = x.to_bits();
        if b & QNAN == QNAN { Value(QNAN) } else { Value(b) }
    }
    #[inline]
    pub fn boolean(b: bool) -> Value { if b { Value::TRUE } else { Value::FALSE } }
    /// A function of the main image.
    #[inline]
    pub fn func(index: u32) -> Value { Value::func_in(0, index) }
    #[inline]
    pub fn func_in(image: u16, index: u32) -> Value { Value(QNAN | T_FUNC | ((image as u64) << 32) | index as u64) }
    /// A runtime function: a builtin or a host service, by id.
    #[inline]
    pub fn builtin(id: u32) -> Value { Value::func_in(RUNTIME_IMAGE, id) }
    #[inline]
    pub fn obj(p: NonNull<Header>) -> Value { Value(QNAN | T_OBJ | (p.as_ptr() as u64 & PAYLOAD)) }

    #[inline]
    pub fn is_float(self) -> bool { self.0 & QNAN != QNAN || self.0 == QNAN }
    #[inline]
    pub fn is_num(self) -> bool { self.is_float() || self.as_inline_integer().is_some() }
    #[inline]
    pub fn as_num(self) -> f64 { self.as_inline_integer().map_or_else(|| f64::from_bits(self.0), |n| n as f64) }
    /// A signed integer whose two's-complement payload fits in 48 bits.
    #[inline]
    pub fn inline_integer(n: i64) -> Option<Value> {
        (-(1i64 << 47)..(1i64 << 47)).contains(&n)
            .then_some(Value(QNAN | T_INTEGER | (n as u64 & PAYLOAD)))
    }
    #[inline]
    pub fn as_inline_integer(self) -> Option<i64> {
        ((self.0 & !PAYLOAD) == (QNAN | T_INTEGER))
            .then_some(((self.0 << 16) as i64) >> 16)
    }
    #[inline]
    pub fn is_nil(self) -> bool { self == Value::NIL }
    #[inline]
    pub fn truthy(self) -> bool { self != Value::NIL && self != Value::FALSE }
    #[inline]
    fn tag(self) -> u64 { self.0 & TAG_MASK }
    /// (image, index) of a function handle.
    #[inline]
    pub fn as_func_in(self) -> Option<(u16, u32)> {
        if !self.is_num() && self.tag() == T_FUNC { Some((((self.0 & PAYLOAD) >> 32) as u16, (self.0 & 0xffff_ffff) as u32)) } else { None }
    }
    /// The index of a function of the main image.
    #[inline]
    pub fn as_func(self) -> Option<u32> { match self.as_func_in() { Some((0, i)) => Some(i), _ => None } }
    #[inline]
    pub fn as_builtin(self) -> Option<u32> { match self.as_func_in() { Some((RUNTIME_IMAGE, i)) => Some(i), _ => None } }
    #[inline]
    pub fn as_obj(self) -> Option<NonNull<Header>> {
        if !self.is_num() && self.tag() == T_OBJ { NonNull::new((self.0 & PAYLOAD) as *mut Header) } else { None }
    }
}

/// Keys are value bits, interned strings by pointer: a multiply-shift mix is
/// all a table needs.
#[derive(Default)]
pub struct BitsHasher(u64);
impl Hasher for BitsHasher {
    fn finish(&self) -> u64 { self.0 }
    fn write(&mut self, bytes: &[u8]) { for &b in bytes { self.0 = (self.0 ^ b as u64).wrapping_mul(0x9E3779B97F4A7C15); } }
    fn write_u64(&mut self, v: u64) { let x = v.wrapping_mul(0x9E3779B97F4A7C15); self.0 = x ^ (x >> 29); }
    fn write_usize(&mut self, v: usize) { self.write_u64(v as u64) }
}
/// Hashed by bits: addresses and value words, never attacker-chosen bytes.
pub type BitsBuild = std::hash::BuildHasherDefault<BitsHasher>;
pub type ValueMap = std::collections::HashMap<Value, Value, std::hash::BuildHasherDefault<BitsHasher>>;

/// FNV-1a over bytes: the intern table's hasher and the string hash.
#[derive(Default)]
pub struct StrHasher(u64);
impl Hasher for StrHasher {
    fn finish(&self) -> u64 { self.0 }
    fn write(&mut self, bytes: &[u8]) { self.0 = string_hash(bytes, self.0); }
}
#[cfg(feature = "native-runtime")]
unsafe extern "C" { fn nupp_object_string_hash(bytes: *const u8, count: u64, state: u64) -> u64; }
#[cfg(feature = "native-runtime")]
const _: () = assert!(crate::dispatch::OBJECT_ABI == 3);
fn string_hash(bytes: &[u8], state: u64) -> u64 {
    #[cfg(feature = "native-runtime")]
    { unsafe { nupp_object_string_hash(bytes.as_ptr(), bytes.len() as u64, state) } }
    #[cfg(not(feature = "native-runtime"))]
    { let _ = (bytes, state); panic!("string hashing requires a linked Nupp core") }
}
pub fn fnv1a(bytes: &[u8]) -> u64 { string_hash(bytes, 0) }

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn tags_do_not_alias_numbers() {
        assert!(Value::num(1.5).is_num());
        assert!(Value::num(f64::NAN).is_num());
        assert_eq!(Value::num(f64::NAN).0, QNAN);
        assert!(!Value::NIL.is_num());
        assert_eq!(Value::func_in(3, 7).as_func_in(), Some((3, 7)));
        assert_eq!(Value::builtin(9).as_builtin(), Some(9));
        assert_eq!(Value::builtin(9).as_func(), None);
        assert!(!Value::FALSE.truthy() && Value::num(0.0).truthy());
    }
    #[test]
    fn inline_integer_preserves_subtype_and_signed_payload() {
        for n in [-(1i64 << 47), -1, 0, 1, (1i64 << 47) - 1] {
            let v = Value::inline_integer(n).unwrap();
            assert_eq!(v.as_inline_integer(), Some(n));
            assert!(v.is_num() && !v.is_float() && v.truthy());
            assert_eq!(v.as_num(), n as f64);
            assert!(v.as_obj().is_none() && v.as_func_in().is_none());
            assert_ne!(v, Value::num(n as f64));
        }
        assert!(Value::inline_integer(-(1i64 << 47) - 1).is_none());
        assert!(Value::inline_integer(1i64 << 47).is_none());
        for v in [Value::NIL, Value::FALSE, Value::TRUE, Value::PARKED,
                  Value::ERROR, Value::func(0), Value::num(f64::NAN),
                  Value::num(f64::NEG_INFINITY), Value::num(-0.0)] {
            assert_eq!(v.as_inline_integer(), None);
        }
    }
}
