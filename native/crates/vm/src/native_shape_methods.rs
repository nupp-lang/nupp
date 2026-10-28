//! Borrowed exact-key method entries in Nupp-owned backing.
use crate::value::Value;
use std::ffi::c_void;

#[repr(C)]
pub struct ShapeMethods {
    owner: *mut c_void,
    base: *mut u64,
    capacity: u64,
    length: u64,
    deleted: u64,
}
const _: () = {
    assert!(std::mem::size_of::<ShapeMethods>() == 40);
};
#[cfg(feature = "native-runtime")]
unsafe extern "C" {
    fn nupp_shape_methods_initialize(map: *mut ShapeMethods, owner: *mut c_void) -> u64;
    pub(crate) fn nupp_shape_methods_insert(
        map: *mut ShapeMethods,
        key: u64,
        value: u64,
        old: *mut u64,
    ) -> u64;
    fn nupp_shape_methods_get(map: *const ShapeMethods, key: u64) -> u64;
    fn nupp_shape_methods_remove(map: *mut ShapeMethods, key: u64, old: *mut u64) -> u64;
    fn nupp_shape_methods_next(map: *const ShapeMethods, start: u64) -> u64;
    fn nupp_shape_methods_clear(map: *mut ShapeMethods);
    fn nupp_shape_methods_release(map: *mut ShapeMethods);
}
macro_rules! native {
    ($name:ident($($argument:expr),* $(,)?)) => {{
        #[cfg(feature = "native-runtime")]
        { unsafe { $name($($argument),*) } }
        #[cfg(not(feature = "native-runtime"))]
        { panic!("shape methods require a linked Nupp core") }
    }};
}
impl ShapeMethods {
    // Heap drops its shape registry before destroying this stable owner.
    pub(crate) unsafe fn new(owner: *mut c_void) -> Self {
        let mut map = Self {
            owner: std::ptr::null_mut(),
            base: std::ptr::null_mut(),
            capacity: 0,
            length: 0,
            deleted: 0,
        };
        let status: u64 = native!(nupp_shape_methods_initialize(&mut map, owner));
        assert_eq!(status, 0, "invalid method map owner");
        map
    }
    pub fn len(&self) -> usize {
        self.length as usize
    }
    pub fn is_empty(&self) -> bool {
        self.length == 0
    }
    pub fn get(&self, key: &Value) -> Option<&Value> {
        let pointer = native!(nupp_shape_methods_get(self, key.0)) as *const Value;
        unsafe { pointer.as_ref() }
    }
    pub fn contains_key(&self, key: &Value) -> bool {
        self.get(key).is_some()
    }
    pub fn insert(&mut self, key: Value, value: Value) -> Option<Value> {
        let mut old = 0;
        let status: u64 = native!(nupp_shape_methods_insert(self, key.0, value.0, &mut old));
        assert!(
            status < 2,
            "method map extent, descriptor or backing refused"
        );
        (status == 1).then_some(Value(old))
    }
    pub fn remove(&mut self, key: &Value) -> Option<Value> {
        let mut old = 0;
        let status: u64 = native!(nupp_shape_methods_remove(self, key.0, &mut old));
        (status == 1).then_some(Value(old))
    }
    pub fn clear(&mut self) {
        native!(nupp_shape_methods_clear(self));
    }
    pub fn iter(&self) -> Iter<'_> {
        Iter { map: self, next: 0 }
    }
    pub fn keys(&self) -> impl Iterator<Item = &Value> {
        self.iter().map(|(key, _)| key)
    }
    pub fn values(&self) -> impl Iterator<Item = &Value> {
        self.iter().map(|(_, value)| value)
    }
}
impl Drop for ShapeMethods {
    fn drop(&mut self) {
        native!(nupp_shape_methods_release(self));
    }
}
pub struct Iter<'a> {
    map: &'a ShapeMethods,
    next: u64,
}
impl<'a> Iterator for Iter<'a> {
    type Item = (&'a Value, &'a Value);
    fn next(&mut self) -> Option<Self::Item> {
        let bucket: u64 = native!(nupp_shape_methods_next(self.map, self.next));
        if bucket == u64::MAX {
            return None;
        }
        self.next = bucket + 1;
        unsafe {
            Some((
                &*self.map.base.add(bucket as usize * 3).cast::<Value>(),
                &*self.map.base.add(bucket as usize * 3 + 1).cast::<Value>(),
            ))
        }
    }
}

#[cfg(all(test, feature = "native-runtime"))]
mod tests {
    use super::*;
    use crate::native_allocator::NativeAllocator;
    use std::collections::BTreeMap;
    unsafe extern "C" {
        fn nupp_shape_methods_reserve(map: *mut ShapeMethods, additional: u64) -> u64;
    }
    fn entries(map: &ShapeMethods) -> BTreeMap<u64, u64> {
        map.iter().map(|(k, v)| (k.0, v.0)).collect()
    }

    #[test]
    fn shape_methods_keep_presence_nil_and_all_key_bits() {
        let owner = NativeAllocator::new();
        let mut map = owner.shape_methods();
        let keys = [
            Value::NIL,
            Value(0),
            Value(1 << 63),
            Value(u64::MAX),
            Value(0x7ff0000000000001),
            Value(0xfff8000000000123),
        ];
        for key in keys {
            assert_eq!(map.insert(key, Value::NIL), None);
        }
        assert_eq!(map.len(), keys.len());
        for key in keys {
            assert!(map.contains_key(&key));
            assert_eq!(map.get(&key), Some(&Value::NIL));
            assert_eq!(map.insert(key, Value::TRUE), Some(Value::NIL));
            assert_eq!(map.remove(&key), Some(Value::TRUE));
            assert_eq!(map.remove(&key), None);
            assert_eq!(map.get(&key), None);
        }
        assert!(map.is_empty());
        assert_eq!(map.iter().count(), 0);
        assert_eq!(map.insert(Value::NIL, Value::NIL), None);
        assert_eq!(map.remove(&Value::NIL), Some(Value::NIL));
    }

    #[test]
    fn shape_methods_collision_removal_and_churn_match_an_independent_map() {
        let owner = NativeAllocator::new();
        let mut map = owner.shape_methods();
        let mut reference = BTreeMap::new();
        let mut keys = Vec::new();
        for bits in 0u64.. {
            let mixed = bits.wrapping_mul(0x9e3779b97f4a7c15);
            if (mixed ^ (mixed >> 29)) & 255 == 0 {
                keys.push(bits);
            }
            if keys.len() == 128 {
                break;
            }
        }
        let mut random = 0x87654321abcdef09u64;
        for step in 0..6000 {
            random ^= random << 13;
            random ^= random >> 7;
            random ^= random << 17;
            let key = keys[random as usize % keys.len()];
            if step % 3 == 0 {
                assert_eq!(map.remove(&Value(key)).map(|v| v.0), reference.remove(&key));
            } else {
                let value = if step % 5 == 0 { Value::NIL.0 } else { random };
                assert_eq!(
                    map.insert(Value(key), Value(value)).map(|v| v.0),
                    reference.insert(key, value)
                );
            }
            assert_eq!(map.len(), reference.len());
            if step % 31 == 0 {
                assert_eq!(entries(&map), reference);
            }
        }
        assert_eq!(entries(&map), reference);
        map.clear();
        assert!(map.is_empty());
        assert_eq!(map.iter().count(), 0);
        // Cross the pooled backing limit and retain exact values on rehash.
        for key in 0..10000 {
            map.insert(Value(key), Value(key ^ u64::MAX));
        }
        for key in 0..10000 {
            assert_eq!(map.get(&Value(key)), Some(&Value(key ^ u64::MAX)));
        }
    }

    #[test]
    fn shape_methods_refusal_preserves_descriptors_entries_and_iteration() {
        let owner = NativeAllocator::new();
        let mut map = owner.shape_methods();
        map.insert(Value::NIL, Value::NIL);
        map.insert(Value::TRUE, Value::FALSE);
        let state = (map.owner, map.base, map.capacity, map.length, map.deleted);
        let before: Vec<_> = map.iter().map(|(&k, &v)| (k, v)).collect();
        assert_eq!(unsafe { nupp_shape_methods_reserve(&mut map, u64::MAX) }, 1);
        assert_eq!(
            unsafe { nupp_shape_methods_initialize(&mut map, owner.heap_pointer()) },
            1
        );
        assert_eq!(
            (map.owner, map.base, map.capacity, map.length, map.deleted),
            state
        );
        assert_eq!(
            map.iter().map(|(&k, &v)| (k, v)).collect::<Vec<_>>(),
            before
        );
        map.clear();
        assert_eq!(
            (map.owner, map.base, map.capacity),
            (state.0, state.1, state.2)
        );
        assert_eq!((map.length, map.deleted), (0, 0));
    }
}
