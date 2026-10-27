//! Borrowed access and teardown transport for a canonical Nupp record tail.
use crate::heap::RecordExtra;
use crate::native_value_array::ValueArray;

#[repr(C)]
pub struct RecordTail {
    pub array: ValueArray,
    pub(crate) extra: *mut RecordExtra,
}
#[cfg(feature = "native-runtime")]
unsafe extern "C" {
    fn nupp_record_ensure_extra(tail: *mut RecordTail) -> *mut RecordExtra;
    fn nupp_record_release_extra(tail: *mut RecordTail) -> u64;
}
impl RecordTail {
    pub fn extra(&self) -> Option<&RecordExtra> {
        unsafe { self.extra.as_ref() }
    }
    pub fn extra_mut(&mut self) -> Option<&mut RecordExtra> {
        unsafe { self.extra.as_mut() }
    }
    pub fn ensure_extra(&mut self) -> &mut RecordExtra {
        #[cfg(feature = "native-runtime")]
        {
            let pointer = unsafe { nupp_record_ensure_extra(self) };
            unsafe { pointer.as_mut() }.expect("record overflow backing allocation refused")
        }
        #[cfg(not(feature = "native-runtime"))]
        panic!("record tails require a linked Nupp core");
    }
    pub fn clear_extra(&mut self) {
        #[cfg(feature = "native-runtime")]
        assert_eq!(
            unsafe { nupp_record_release_extra(self) },
            0,
            "invalid record overflow release"
        );
        #[cfg(not(feature = "native-runtime"))]
        panic!("record tails require a linked Nupp core");
    }
}
impl Drop for RecordTail {
    fn drop(&mut self) {
        self.clear_extra();
        // Rust subsequently drops array; the Nupp allocator outlives both.
    }
}

#[cfg(all(test, feature = "native-runtime"))]
mod tests {
    use super::*;
    use crate::heap::{Header, HEADER, KIND_RECORD};
    use crate::native_allocator::NativeAllocator;
    use crate::value::Value;

    unsafe extern "C" {
        fn nupp_object_constructor_payload(kind: u64, count: u64) -> u64;
        fn nupp_object_record_initialize(
            header: *mut Header,
            owner: *mut std::ffi::c_void,
            shape: u64,
            count: u64,
        ) -> u64;
    }

    #[test]
    fn record_extent_and_initializer_refuse_before_writing() {
        let owner = NativeAllocator::new();
        let maximum = (u32::MAX as u64 - HEADER as u64 - 40) / 8;
        unsafe {
            assert_eq!(
                nupp_object_constructor_payload(KIND_RECORD as u64, maximum),
                maximum * 8 + 40
            );
            assert_eq!(
                nupp_object_constructor_payload(KIND_RECORD as u64, maximum + 1),
                u64::MAX
            );
            assert_eq!(
                nupp_object_constructor_payload(KIND_RECORD as u64, u64::MAX),
                u64::MAX
            );
        }
        let mut words = [0xa5a5_a5a5_a5a5_a5a5u64; 12];
        let header = words.as_mut_ptr().cast::<Header>();
        unsafe {
            (*header).kind = KIND_RECORD;
            (*header).size = (HEADER + 40 + 8) as u32;
            (*header).aux_ptr = header.cast::<u8>().add(HEADER);
        }
        let before = words;
        for (owner_ptr, shape, count) in [
            (std::ptr::null_mut(), 0, 1),
            (owner.heap_pointer(), u64::MAX, 1),
            (owner.heap_pointer(), 0, 2),
            (owner.heap_pointer(), 0, u64::MAX),
        ] {
            assert_eq!(
                unsafe { nupp_object_record_initialize(header, owner_ptr, shape, count) },
                1
            );
            assert_eq!(words, before);
        }
        assert_eq!(
            unsafe { nupp_object_record_initialize(header, owner.heap_pointer(), 7, 1) },
            0
        );
        unsafe {
            assert_eq!((*header).slots(), &[Value::NIL]);
            assert_eq!((*header).shape(), 7);
            let tail = (*header).record_tail();
            assert!(tail.array.is_empty());
            assert_eq!(tail.array.capacity(), 0);
            assert!(tail.extra().is_none());
            let extra = tail.ensure_extra() as *mut RecordExtra;
            (*extra).fields.insert(Value::TRUE, Value::FALSE);
            assert_eq!(
                nupp_record_release_extra(tail),
                0,
                "Nupp releases owned hash backing before recycling"
            );
            assert!(tail.extra.is_null());
            tail.clear_extra();
            assert!(tail.extra().is_none());
            assert_eq!(tail.ensure_extra() as *mut RecordExtra, extra);
            assert!(tail.extra().unwrap().fields.iter().next().is_none());
            assert_eq!(tail.extra().unwrap().meta, Value::NIL);
            std::ptr::drop_in_place(tail);
        }
    }
}
