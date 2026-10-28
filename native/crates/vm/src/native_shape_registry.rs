//! Borrowed shape descriptors; Nupp owns registry movement and destruction.
use crate::heap::Shape;
use std::ffi::c_void;
use std::ops::{Deref, DerefMut};

#[repr(C)]
pub struct ShapeRegistry {
    owner: *mut c_void,
    base: *mut Shape,
    length: u64,
    capacity: u64,
}
const _: () = {
    assert!(std::mem::size_of::<Shape>() == 192);
    assert!(std::mem::align_of::<Shape>() == 8);
    assert!(std::mem::offset_of!(Shape, name) == 0);
    assert!(std::mem::offset_of!(Shape, structural) == 32);
    assert!(std::mem::offset_of!(Shape, names) == 40);
    assert!(std::mem::offset_of!(Shape, types) == 72);
    assert!(std::mem::offset_of!(Shape, table) == 104);
    assert!(std::mem::offset_of!(Shape, mask) == 136);
    assert!(std::mem::offset_of!(Shape, methods) == 144);
    assert!(std::mem::offset_of!(Shape, mm_cache) == 184);
    assert!(std::mem::size_of::<ShapeRegistry>() == 32);
    assert!(std::mem::offset_of!(ShapeRegistry, base) == 8);
    assert!(std::mem::offset_of!(ShapeRegistry, length) == 16);
    assert!(std::mem::offset_of!(ShapeRegistry, capacity) == 24);
};
#[cfg(feature = "native-runtime")]
unsafe extern "C" {
    fn nupp_shape_registry_initialize(
        registry: *mut ShapeRegistry,
        owner: *mut c_void,
        stride: u64,
    ) -> u64;
    pub(crate) fn nupp_shape_registry_reserve(registry: *mut ShapeRegistry, additional: u64)
    -> u64;
    pub(crate) fn nupp_shape_registry_push(registry: *mut ShapeRegistry, source: *mut Shape)
    -> u64;
    fn nupp_shape_registry_clear(registry: *mut ShapeRegistry);
    fn nupp_shape_registry_release(registry: *mut ShapeRegistry);
}
macro_rules! native {
    ($name:ident($($argument:expr),* $(,)?)) => {{
        #[cfg(feature = "native-runtime")]
        { unsafe { $name($($argument),*) } }
        #[cfg(not(feature = "native-runtime"))]
        { panic!("shape registry requires a linked Nupp core") }
    }};
}
impl ShapeRegistry {
    pub(crate) unsafe fn new(owner: *mut c_void) -> Self {
        let mut registry = Self {
            owner: std::ptr::null_mut(),
            base: std::ptr::null_mut(),
            length: 0,
            capacity: 0,
        };
        let status: u64 = native!(nupp_shape_registry_initialize(
            &mut registry,
            owner,
            std::mem::size_of::<Shape>() as u64
        ));
        assert_eq!(status, 0, "shape registry layout or owner refused");
        registry
    }
    pub(crate) fn push(&mut self, mut shape: Shape) -> u32 {
        let index: u64 = native!(nupp_shape_registry_push(self, &mut shape));
        assert_ne!(
            index,
            u64::MAX,
            "shape registry count, owner or backing refused"
        );
        // Nupp emptied the moved-from descriptor; its field drops own nothing.
        u32::try_from(index).expect("shape index")
    }
    pub fn clear(&mut self) {
        native!(nupp_shape_registry_clear(self));
    }
    // Heap calls release before its allocator dies. The eventual Rust Drop is
    // then a no-op over empty descriptors and never consults the old owner.
    pub(crate) fn release(&mut self) {
        native!(nupp_shape_registry_release(self));
    }
    fn pointer(&self) -> *mut Shape {
        if self.base.is_null() {
            std::ptr::NonNull::<Shape>::dangling().as_ptr()
        } else {
            self.base
        }
    }
}
impl Deref for ShapeRegistry {
    type Target = [Shape];
    fn deref(&self) -> &[Shape] {
        unsafe { std::slice::from_raw_parts(self.pointer(), self.length as usize) }
    }
}
impl DerefMut for ShapeRegistry {
    fn deref_mut(&mut self) -> &mut [Shape] {
        unsafe { std::slice::from_raw_parts_mut(self.pointer(), self.length as usize) }
    }
}
impl<'a> IntoIterator for &'a ShapeRegistry {
    type Item = &'a Shape;
    type IntoIter = std::slice::Iter<'a, Shape>;
    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}
impl Drop for ShapeRegistry {
    fn drop(&mut self) {
        self.release();
    }
}

#[cfg(all(test, feature = "native-runtime"))]
mod tests {
    use super::*;
    use crate::{heap::SlotTy, native_allocator::NativeAllocator, value::Value};

    #[test]
    fn shape_registry_refuses_layout_overflow_alias_and_foreign_ownership() {
        let owner = NativeAllocator::new();
        let other = NativeAllocator::new();
        let mut fresh = ShapeRegistry {
            owner: std::ptr::null_mut(),
            base: std::ptr::null_mut(),
            length: 0,
            capacity: 0,
        };
        assert_eq!(
            unsafe { nupp_shape_registry_initialize(&mut fresh, owner.heap_pointer(), 191) },
            1
        );
        assert!(fresh.owner.is_null());
        let mut registry = owner.shape_registry();
        let mut foreign = Shape::new(&other, "foreign", &[Value(16)], &[SlotTy::Num]);
        let before = (
            foreign.name.as_ptr(),
            foreign.names.as_ptr(),
            foreign.table.as_ptr(),
        );
        assert_eq!(
            unsafe { nupp_shape_registry_push(&mut registry, &mut foreign) },
            u64::MAX
        );
        assert!(registry.is_empty());
        assert_eq!(
            (
                foreign.name.as_ptr(),
                foreign.names.as_ptr(),
                foreign.table.as_ptr()
            ),
            before
        );
        assert_eq!(foreign.name, "foreign");
        let mut source = Shape::new(
            &owner,
            "struct:held",
            &[Value(16)],
            &[SlotTy::Record(u32::MAX)],
        );
        source.methods.insert(Value(32), Value::NIL);
        source.mm_cache = 0xaabbccdd;
        let pointer = source.name.as_ptr();
        assert_eq!(
            unsafe { nupp_shape_registry_push(&mut registry, &mut source) },
            0
        );
        assert!(
            source.name.is_empty()
                && source.names.is_empty()
                && source.types.is_empty()
                && source.table.is_empty()
                && source.methods.is_empty()
        );
        drop(source);
        let old_base = registry.base;
        assert_eq!(
            unsafe { nupp_shape_registry_push(&mut registry, old_base) },
            u64::MAX
        );
        for additional in [u64::MAX, u32::MAX as u64] {
            assert_eq!(
                unsafe { nupp_shape_registry_reserve(&mut registry, additional) },
                1
            );
            assert_eq!((registry.base, registry.length), (old_base, 1));
        }
        assert_eq!(registry[0].name.as_ptr(), pointer);
        assert!(registry[0].structural);
        assert_eq!(registry[0].mm_cache, 0xaabbccdd);
        assert_eq!(registry[0].types.at(0), SlotTy::Record(u32::MAX));
        assert_eq!(registry[0].methods.get(&Value(32)), Some(&Value::NIL));
        registry.clear();
        assert!(registry.is_empty());
        assert_eq!(registry.base, old_base);
        assert_eq!(registry.push(Shape::new(&owner, "reused", &[], &[])), 0);
        registry.release();
        assert!(registry.base.is_null());
        assert_eq!((registry.length, registry.capacity), (0, 0));
    }

    #[test]
    fn shape_registry_growth_preserves_every_owned_pointer_and_value() {
        let owner = NativeAllocator::new();
        let mut registry = owner.shape_registry();
        let mut pointers = Vec::new();
        let mut bases = std::collections::HashSet::new();
        for i in 0..1025u32 {
            let mut shape = Shape::new(
                &owner,
                &format!("shape-{i}\0é"),
                &[Value(16), Value(32)],
                &[SlotTy::Num, SlotTy::Record(i)],
            );
            shape.methods.insert(Value(64), Value::num(i as f64));
            pointers.push((
                shape.name.as_ptr(),
                shape.names.as_ptr(),
                shape.types.words().as_ptr(),
                shape.table.as_ptr(),
                shape.methods.get(&Value(64)).unwrap() as *const Value,
            ));
            assert_eq!(registry.push(shape), i);
            bases.insert(registry.base);
            for (index, s) in registry.iter().enumerate() {
                assert_eq!(
                    (
                        s.name.as_ptr(),
                        s.names.as_ptr(),
                        s.types.words().as_ptr(),
                        s.table.as_ptr(),
                        s.methods.get(&Value(64)).unwrap() as *const Value
                    ),
                    pointers[index]
                );
            }
        }
        assert!(bases.len() >= 8);
        for (i, s) in registry.iter().enumerate() {
            assert_eq!(s.name, format!("shape-{i}\0é"));
            assert_eq!(s.slot_of(Value(32)), Some(1));
            assert_eq!(s.types.at(1), SlotTy::Record(i as u32));
            assert_eq!(s.methods.get(&Value(64)), Some(&Value::num(i as f64)));
        }
        registry.clear();
        assert!(registry.is_empty());
        for i in 0..1025u32 {
            assert_eq!(registry.push(Shape::new(&owner, "again", &[], &[])), i);
        }
    }
    #[test]
    fn shape_registry_release_returns_each_backing_exactly_once() {
        let owner = NativeAllocator::new();
        let mut registry = owner.shape_registry();
        let mut shape = Shape::new(
            &owner,
            "held",
            &[Value(16), Value(32)],
            &[SlotTy::Any, SlotTy::Bool],
        );
        shape.methods.insert(Value(64), Value::NIL);
        let small = std::collections::HashSet::from([
            shape.name.as_ptr() as usize,
            shape.names.as_ptr() as usize,
            shape.types.words().as_ptr() as usize,
        ]);
        assert_eq!(small.len(), 3);
        let probes = shape.table.as_ptr() as usize;
        let methods = unsafe { *(&shape.methods as *const _ as *const u64).add(1) } as usize;
        registry.push(shape);
        let descriptors = registry.base as usize;
        registry.clear();
        let a = owner.value_array(4);
        let b = owner.value_array(4);
        let c = owner.value_array(4);
        assert_eq!(
            std::collections::HashSet::from([
                a.as_ptr() as usize,
                b.as_ptr() as usize,
                c.as_ptr() as usize
            ]),
            small
        );
        let table = owner.value_array(16);
        assert_eq!(table.as_ptr() as usize, probes);
        let map = owner.value_array(24);
        assert_eq!(map.as_ptr() as usize, methods);
        registry.release();
        let records = owner.value_array(96);
        assert_eq!(records.as_ptr() as usize, descriptors);
        // A second release and the eventual Drop must leave the reused slots alone.
        registry.release();
        let other = owner.value_array(96);
        assert_ne!(other.as_ptr(), records.as_ptr());
    }
}
