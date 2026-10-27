//! Borrowed Rust access to a canonical Nupp-owned table array.
use crate::value::Value;
use std::ffi::c_void;
use std::ops::{Deref, DerefMut};

#[repr(C)]
pub struct ValueArray {
    owner: *mut c_void,
    base: *mut Value,
    length: u64,
    capacity: u64,
}
#[cfg(feature = "native-runtime")]
unsafe extern "C" {
    fn nupp_array_initialize(array: *mut ValueArray, owner: *mut c_void, capacity: u64) -> u64;
    fn nupp_array_reserve(array: *mut ValueArray, wanted: u64) -> u64;
    fn nupp_array_push(array: *mut ValueArray, value: u64) -> u64;
    fn nupp_array_extend(array: *mut ValueArray, source: *const Value, count: u64) -> u64;
    fn nupp_array_resize(array: *mut ValueArray, length: u64, value: u64) -> u64;
    fn nupp_array_truncate(array: *mut ValueArray, length: u64);
    fn nupp_array_trim(array: *mut ValueArray);
    fn nupp_array_release(array: *mut ValueArray);
}
macro_rules! native {
    ($name:ident($($argument:expr),* $(,)?)) => {{
        #[cfg(feature = "native-runtime")]
        { unsafe { $name($($argument),*) } }
        #[cfg(not(feature = "native-runtime"))]
        { panic!("table arrays require a linked Nupp core") }
    }};
}
impl ValueArray {
    // The owning Heap drops every payload before destroying this stable owner.
    pub(crate) unsafe fn new(owner: *mut c_void, capacity: usize) -> Self {
        let mut array = Self {
            owner,
            base: std::ptr::null_mut(),
            length: 0,
            capacity: 0,
        };
        Self::accept(native!(nupp_array_initialize(
            &mut array,
            owner,
            capacity as u64
        )));
        array
    }
    fn accept(status: u64) {
        assert_eq!(
            status, 0,
            "table array capacity overflow or backing allocation refused"
        );
    }
    pub fn capacity(&self) -> usize {
        self.capacity as usize
    }
    pub fn as_ptr(&self) -> *const Value {
        self.base
    }
    pub fn as_mut_ptr(&mut self) -> *mut Value {
        self.base
    }
    pub fn push(&mut self, value: Value) {
        Self::accept(native!(nupp_array_push(self, value.0)));
    }
    pub fn reserve(&mut self, additional: usize) {
        Self::accept(native!(nupp_array_reserve(self, additional as u64)));
    }
    pub fn extend(&mut self, values: impl AsRef<[Value]>) {
        let slice = values.as_ref();
        Self::accept(native!(nupp_array_extend(
            self,
            slice.as_ptr(),
            slice.len() as u64
        )));
    }
    pub fn resize(&mut self, length: usize, value: Value) {
        Self::accept(native!(nupp_array_resize(self, length as u64, value.0)));
    }
    pub fn truncate(&mut self, length: usize) {
        native!(nupp_array_truncate(self, length as u64));
    }
    pub fn trim(&mut self) {
        native!(nupp_array_trim(self));
    }
}
impl Deref for ValueArray {
    type Target = [Value];
    fn deref(&self) -> &[Value] {
        let base = if self.base.is_null() {
            std::ptr::NonNull::<Value>::dangling().as_ptr()
        } else {
            self.base
        };
        unsafe { std::slice::from_raw_parts(base, self.length as usize) }
    }
}
impl DerefMut for ValueArray {
    fn deref_mut(&mut self) -> &mut [Value] {
        let base = if self.base.is_null() {
            std::ptr::NonNull::<Value>::dangling().as_ptr()
        } else {
            self.base
        };
        unsafe { std::slice::from_raw_parts_mut(base, self.length as usize) }
    }
}
impl<'a> IntoIterator for &'a ValueArray {
    type Item = &'a Value;
    type IntoIter = std::slice::Iter<'a, Value>;
    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}
impl Drop for ValueArray {
    fn drop(&mut self) {
        native!(nupp_array_release(self));
    }
}

#[cfg(all(test, feature = "native-runtime"))]
mod tests {
    use super::*;
    use crate::native_allocator::NativeAllocator;

    #[test]
    fn owned_array_keeps_exact_reservations_and_reuses_pool_slots() {
        let owner = NativeAllocator::new();
        let mut array = owner.value_array(1);
        assert_eq!(array.capacity(), 1);
        array.push(Value::TRUE);
        assert_eq!(array.capacity(), 1);
        array.push(Value::NIL);
        assert_eq!(array.capacity(), 4);
        let pointer = array.as_ptr();
        array.trim();
        assert_eq!(&*array, &[Value::TRUE]);
        array.resize(4, Value::FALSE);
        assert_eq!(
            &*array,
            &[Value::TRUE, Value::FALSE, Value::FALSE, Value::FALSE]
        );
        drop(array);
        let mut reused = owner.value_array(4);
        assert_eq!(reused.as_ptr(), pointer);
        assert!(
            reused.is_empty(),
            "old slot contents are outside the initialized extent"
        );
        reused.resize(4, Value::NIL);
        assert_eq!(&*reused, &[Value::NIL; 4]);
    }

    #[test]
    fn owned_array_extends_aliased_words_across_pool_and_mapping_growth() {
        let owner = NativeAllocator::new();
        for count in [4, 4096, 8192] {
            let mut array = owner.value_array(count);
            let expected: Vec<_> = (0..count)
                .map(|i| Value::inline_integer(i as i64).unwrap())
                .collect();
            array.extend(&expected);
            let before = array.as_ptr();
            let status = native!(nupp_array_extend(&mut array, before, count as u64));
            assert_eq!(status, 0);
            assert_ne!(array.as_ptr(), before);
            assert_eq!(&array[..count], &expected);
            assert_eq!(&array[count..], &expected);
            array.truncate(1);
            array.push(Value::num(-0.0));
            array.push(Value::num(f64::NAN));
            assert_eq!(array[1].0, Value::num(-0.0).0);
            assert_eq!(array[2].0, Value::num(f64::NAN).0);
        }
    }

    #[test]
    fn owned_array_refuses_overflow_without_mutating_existing_words() {
        let owner = NativeAllocator::new();
        let mut array = owner.value_array(4);
        array.extend([Value::TRUE, Value::NIL, Value::inline_integer(-1).unwrap()]);
        let state = (array.owner, array.base, array.length, array.capacity);
        let content = array.to_vec();
        assert_eq!(native!(nupp_array_reserve(&mut array, u64::MAX)), 1);
        assert_eq!(
            native!(nupp_array_resize(&mut array, u64::MAX, Value::FALSE.0)),
            1
        );
        assert_eq!(
            native!(nupp_array_initialize(
                &mut array,
                owner.heap_pointer(),
                u64::MAX
            )),
            1
        );
        assert_eq!(
            (array.owner, array.base, array.length, array.capacity),
            state
        );
        assert_eq!(&*array, &content);
        array.push(Value::FALSE);
        assert_eq!(array.last(), Some(&Value::FALSE));
    }
}
