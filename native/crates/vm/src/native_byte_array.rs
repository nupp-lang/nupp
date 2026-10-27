//! Rust borrows and scoped ownership for canonical Nupp byte backing.
use std::ffi::c_void;
use std::ops::{Deref, DerefMut};

#[repr(C)]
pub struct ByteArray {
    owner: *mut c_void,
    base: *mut u8,
    length: u64,
    capacity: u64,
}
const _: () = {
    assert!(std::mem::size_of::<ByteArray>() == 32);
    assert!(std::mem::align_of::<ByteArray>() == 8);
    assert!(std::mem::offset_of!(ByteArray, base) == 8);
    assert!(std::mem::offset_of!(ByteArray, length) == 16);
    assert!(std::mem::offset_of!(ByteArray, capacity) == 24);
};
#[cfg(feature = "native-runtime")]
unsafe extern "C" {
    fn nupp_byte_array_initialize(
        a: *mut ByteArray,
        owner: *mut c_void,
        length: u64,
        capacity: u64,
    ) -> u64;
    fn nupp_byte_array_extend(a: *mut ByteArray, source: *const u8, count: u64) -> u64;
    fn nupp_byte_array_take(target: *mut ByteArray, source: *mut ByteArray) -> u64;
    fn nupp_byte_array_release(a: *mut ByteArray);
}
macro_rules! native {
    ($name:ident($($argument:expr),* $(,)?)) => {{
        #[cfg(feature = "native-runtime")]
        { unsafe { $name($($argument),*) } }
        #[cfg(not(feature = "native-runtime"))]
        { panic!("byte arrays require a linked Nupp core") }
    }};
}
impl ByteArray {
    // The Heap drops every descriptor before destroying the stable owner.
    pub(crate) unsafe fn new(owner: *mut c_void, length: usize, capacity: usize) -> Self {
        let mut array = Self::fresh();
        Self::accept(native!(nupp_byte_array_initialize(
            &mut array,
            owner,
            length as u64,
            capacity as u64
        )));
        array
    }
    fn fresh() -> Self {
        Self {
            owner: std::ptr::null_mut(),
            base: std::ptr::null_mut(),
            length: 0,
            capacity: 0,
        }
    }
    fn accept(status: u64) {
        assert_eq!(
            status, 0,
            "byte array capacity overflow or backing allocation refused"
        );
    }
    pub fn capacity(&self) -> usize {
        self.capacity as usize
    }
    pub fn extend_from_slice(&mut self, bytes: &[u8]) {
        Self::accept(native!(nupp_byte_array_extend(
            self,
            bytes.as_ptr(),
            bytes.len() as u64
        )));
    }
    pub(crate) fn take(&mut self) -> Self {
        let mut target = Self::fresh();
        Self::accept(native!(nupp_byte_array_take(&mut target, self)));
        target
    }
    fn pointer(&self) -> *mut u8 {
        if self.base.is_null() {
            std::ptr::NonNull::<u8>::dangling().as_ptr()
        } else {
            self.base
        }
    }
}
impl Deref for ByteArray {
    type Target = [u8];
    fn deref(&self) -> &[u8] {
        unsafe { std::slice::from_raw_parts(self.pointer(), self.length as usize) }
    }
}
impl DerefMut for ByteArray {
    fn deref_mut(&mut self) -> &mut [u8] {
        unsafe { std::slice::from_raw_parts_mut(self.pointer(), self.length as usize) }
    }
}
impl Drop for ByteArray {
    fn drop(&mut self) {
        native!(nupp_byte_array_release(self));
    }
}

#[cfg(all(test, feature = "native-runtime"))]
mod tests {
    use super::*;
    use crate::native_allocator::NativeAllocator;

    #[test]
    fn byte_array_alias_growth_and_consume_keep_ownership_exact() {
        let owner = NativeAllocator::new();
        for count in [1, 7, 32, 32768, 32769, 65536] {
            let mut array = owner.byte_array(count, count);
            let expected: Vec<u8> = (0..count).map(|i| (i % 251) as u8).collect();
            array.copy_from_slice(&expected);
            let before = array.base;
            assert_eq!(
                native!(nupp_byte_array_extend(&mut array, before, count as u64)),
                0
            );
            assert_ne!(array.base, before);
            assert_eq!(&array[..count], &expected);
            assert_eq!(&array[count..], &expected);
            let pointer = array.base;
            let moved = array.take();
            assert_eq!(moved.base, pointer);
            assert_eq!(array.owner, moved.owner);
            assert_eq!(array.capacity(), 0);
            assert!(array.is_empty());
            array.extend_from_slice(b"reuse");
            assert_eq!(&*array, b"reuse");
            assert_eq!(&moved[..count], &expected);
            drop(array);
            let mut peers: Vec<_> = (0..32).map(|_| owner.byte_array(count, count)).collect();
            for peer in &mut peers {
                peer.fill(0xDD);
            }
            assert_eq!(&moved[..count], &expected);
            drop(moved);
        }
    }

    #[test]
    fn byte_array_refusals_do_not_mutate_source_or_live_backing() {
        let owner = NativeAllocator::new();
        let mut array = owner.byte_array(8, 16);
        array.copy_from_slice(b"all bits");
        let before = (array.owner, array.base, array.length, array.capacity);
        for (pointer, count) in [
            (array.base, u64::MAX),
            (unsafe { array.base.add(7) }, 2),
            (unsafe { array.base.add(16) }, 1),
            (std::ptr::null_mut(), 1),
        ] {
            assert_eq!(
                native!(nupp_byte_array_extend(&mut array, pointer, count)),
                1
            );
            assert_eq!(
                (array.owner, array.base, array.length, array.capacity),
                before
            );
            assert_eq!(&*array, b"all bits");
        }
        assert_eq!(
            native!(nupp_byte_array_initialize(
                &mut array,
                owner.heap_pointer(),
                0,
                u64::MAX
            )),
            1
        );
        assert_eq!(
            (array.owner, array.base, array.length, array.capacity),
            before
        );
        let mut target = owner.byte_array(1, 1);
        assert_eq!(native!(nupp_byte_array_take(&mut target, &mut array)), 1);
        assert_eq!(
            (array.owner, array.base, array.length, array.capacity),
            before
        );
        let same = &mut array as *mut ByteArray;
        assert_eq!(native!(nupp_byte_array_take(same, same)), 1);
        assert_eq!(
            native!(nupp_byte_array_extend(&mut array, std::ptr::null(), 0)),
            0
        );
        assert_eq!(&*array, b"all bits");
    }

    #[test]
    fn consumed_byte_array_releases_backing_when_string_creation_unwinds() {
        let owner = NativeAllocator::new();
        let mut array = owner.byte_array(16, 16);
        let pointer = array.base;
        let unwound = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let consumed = array.take();
            assert_eq!(consumed.base, pointer);
            panic!("simulate a failing string allocation");
        }));
        assert!(unwound.is_err());
        assert!(array.is_empty());
        let reused = owner.byte_array(16, 16);
        assert_eq!(reused.base, pointer);
        assert!(reused.iter().all(|byte| *byte == 0));
        array.extend_from_slice(b"after refusal");
        assert_eq!(&*array, b"after refusal");
    }
}
