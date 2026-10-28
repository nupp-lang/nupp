//! Borrowed probe buckets and transport for Nupp-owned immutable shape backing.
use crate::native_value_array::ValueArray;
use crate::value::Value;
use std::ffi::c_void;
use std::ops::Deref;

#[repr(transparent)]
pub struct ShapeTable(ValueArray);

#[cfg(feature = "native-runtime")]
unsafe extern "C" {
    pub(crate) fn nupp_shape_owned_initialize(
        names: *mut ValueArray,
        probes: *mut ValueArray,
        source: *const Value,
        count: u64,
    ) -> u64;
}

// The Heap clears its shape registry before destroying the backing owner.
pub(crate) unsafe fn initialize(
    owner: *mut c_void,
    source: &[Value],
) -> (ValueArray, ShapeTable, u64) {
    let mut names = unsafe { ValueArray::new(owner, 0) };
    let mut probes = unsafe { ValueArray::new(owner, 0) };
    #[cfg(feature = "native-runtime")]
    let mask = unsafe {
        nupp_shape_owned_initialize(
            &mut names,
            &mut probes,
            source.as_ptr(),
            source.len() as u64,
        )
    };
    #[cfg(not(feature = "native-runtime"))]
    let mask: u64 = panic!("shape construction requires a linked Nupp core");
    assert_ne!(
        mask,
        u64::MAX,
        "shape extent, descriptor or backing refused"
    );
    (names, ShapeTable(probes), mask)
}
impl Deref for ShapeTable {
    type Target = [[u64; 2]];
    fn deref(&self) -> &[[u64; 2]] {
        let words: &[Value] = &self.0;
        unsafe { std::slice::from_raw_parts(words.as_ptr().cast(), words.len() / 2) }
    }
}

#[cfg(all(test, feature = "native-runtime"))]
mod tests {
    use super::*;
    use crate::native_allocator::NativeAllocator;

    #[test]
    fn shape_backing_refuses_without_replacing_descriptors() {
        let owner = NativeAllocator::new();
        let mut names = owner.value_array(0);
        let mut probes = owner.value_array(0);
        let source = [Value::TRUE, Value::FALSE];
        for (pointer, count) in [(source.as_ptr(), u64::MAX), (std::ptr::null(), 1)] {
            assert_eq!(
                unsafe { nupp_shape_owned_initialize(&mut names, &mut probes, pointer, count) },
                u64::MAX
            );
            assert_eq!(
                (
                    names.len(),
                    names.capacity(),
                    probes.len(),
                    probes.capacity()
                ),
                (0, 0, 0, 0)
            );
        }
        let same = &mut names as *mut ValueArray;
        assert_eq!(
            unsafe { nupp_shape_owned_initialize(same, same, source.as_ptr(), 2) },
            u64::MAX
        );
        assert_eq!(
            unsafe { nupp_shape_owned_initialize(&mut names, &mut probes, source.as_ptr(), 2) },
            7
        );
        let state = (
            names.as_ptr(),
            names.len(),
            names.capacity(),
            probes.as_ptr(),
            probes.len(),
            probes.capacity(),
        );
        let table = probes.to_vec();
        assert_eq!(
            unsafe { nupp_shape_owned_initialize(&mut names, &mut probes, source.as_ptr(), 2) },
            u64::MAX
        );
        assert_eq!(
            (
                names.as_ptr(),
                names.len(),
                names.capacity(),
                probes.as_ptr(),
                probes.len(),
                probes.capacity()
            ),
            state
        );
        assert_eq!(&names[..], &source);
        assert_eq!(&probes[..], &table);
    }
}
