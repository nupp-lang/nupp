//! Borrowed access to canonical Nupp-owned hash descriptors.
use crate::value::Value;
use std::ffi::c_void;

#[repr(C)]
pub struct ValueTable {
    pub ptr: *mut u64,
    pub mask: u64,
    pub cap: u64,
    pub len: u64,
    pub(crate) order: *mut u32,
    pub(crate) rank: *mut u32,
    owner: *mut c_void,
}
#[cfg(feature = "native-runtime")]
unsafe extern "C" {
    fn nupp_table_owned_initialize(table: *mut ValueTable, owner: *mut c_void, wanted: u64) -> u64;
    fn nupp_table_owned_release(table: *mut ValueTable);
    fn nupp_table_owned_bytes(table: *const ValueTable) -> u64;
    fn nupp_table_owned_grow(table: *mut ValueTable) -> u64;
    fn nupp_table_owned_insert(table: *mut ValueTable, key: u64, value: u64) -> u64;
    fn nupp_table_owned_get_slot(table: *const ValueTable, key: u64) -> u64;
    fn nupp_table_owned_entry_bucket(table: *const ValueTable, position: u64) -> u64;
    fn nupp_table_owned_position(table: *const ValueTable, key: u64) -> u64;
    fn nupp_table_owned_next_position(table: *const ValueTable, start: u64) -> u64;
    fn nupp_table_owned_next_after(table: *const ValueTable, key: u64) -> u64;
}
macro_rules! native {
    ($name:ident($($argument:expr),* $(,)?)) => {{
        #[cfg(feature = "native-runtime")]
        { unsafe { $name($($argument),*) } }
        #[cfg(not(feature = "native-runtime"))]
        { panic!("hash tables require a linked Nupp core") }
    }};
}
impl ValueTable {
    // The stable native owner must outlive this descriptor and every borrow.
    pub(crate) unsafe fn new(owner: *mut c_void, wanted: usize) -> Self {
        let mut table = Self {
            ptr: std::ptr::null_mut(),
            mask: 0,
            cap: 0,
            len: 0,
            order: std::ptr::null_mut(),
            rank: std::ptr::null_mut(),
            owner,
        };
        Self::accept(native!(nupp_table_owned_initialize(
            &mut table,
            owner,
            wanted as u64
        )));
        table
    }
    fn accept(status: u64) {
        assert_eq!(
            status, 0,
            "hash table extent, backing or descriptor refused"
        );
    }
    pub fn get(&self, key: &Value) -> Option<&Value> {
        let pointer = native!(nupp_table_owned_get_slot(self, key.0)) as *const Value;
        unsafe { pointer.as_ref() }
    }
    pub fn insert(&mut self, key: Value, value: Value) {
        Self::accept(native!(nupp_table_owned_insert(self, key.0, value.0)));
    }
    pub(crate) fn grow(&mut self) {
        Self::accept(native!(nupp_table_owned_grow(self)));
    }
    pub fn len(&self) -> usize {
        self.len as usize
    }
    pub fn capacity(&self) -> usize {
        self.cap as usize
    }
    pub fn backing_bytes(&self) -> usize {
        native!(nupp_table_owned_bytes(self)) as usize
    }
    pub fn iter(&self) -> Iter<'_> {
        Iter {
            table: self,
            position: 0,
        }
    }
    pub fn keys(&self) -> impl Iterator<Item = &Value> {
        self.iter().map(|(key, _)| key)
    }
    fn entry_refs(&self, position: u64) -> Option<(&Value, &Value)> {
        let bucket: u64 = native!(nupp_table_owned_entry_bucket(self, position));
        if bucket == u64::MAX {
            return None;
        }
        unsafe {
            Some((
                &*self.ptr.add(2 * bucket as usize).cast::<Value>(),
                &*self.ptr.add(2 * bucket as usize + 1).cast::<Value>(),
            ))
        }
    }
    pub fn entry_at(&self, position: usize) -> Option<(Value, Value)> {
        self.entry_refs(position as u64)
            .map(|(&key, &value)| (key, value))
    }
    pub fn position_of(&self, key: Value) -> Option<usize> {
        let position: u64 = native!(nupp_table_owned_position(self, key.0));
        (position != u64::MAX).then_some(position as usize)
    }
    pub fn next_after(&self, key: Value) -> Option<(Value, Value)> {
        let position: u64 = native!(nupp_table_owned_next_after(self, key.0));
        self.entry_at(position as usize)
    }
}
impl Drop for ValueTable {
    fn drop(&mut self) {
        native!(nupp_table_owned_release(self));
    }
}
pub struct Iter<'a> {
    table: &'a ValueTable,
    position: u64,
}
impl<'a> Iterator for Iter<'a> {
    type Item = (&'a Value, &'a Value);
    fn next(&mut self) -> Option<Self::Item> {
        let position: u64 = native!(nupp_table_owned_next_position(self.table, self.position));
        let entry = self.table.entry_refs(position)?;
        self.position = position + 1;
        Some(entry)
    }
}

#[cfg(all(test, feature = "native-runtime"))]
mod tests {
    use super::*;
    use crate::native_allocator::NativeAllocator;

    #[test]
    fn owned_hash_refusal_preserves_descriptor_backing_and_live_order() {
        let owner = NativeAllocator::new();
        let mut table = owner.value_table(4);
        for i in 0..6 {
            table.insert(
                Value::inline_integer(i).unwrap(),
                Value::inline_integer(100 + i).unwrap(),
            );
        }
        let state = (
            table.ptr,
            table.mask,
            table.cap,
            table.len,
            table.order,
            table.rank,
            table.owner,
        );
        let entries: Vec<_> = table.iter().map(|(&k, &v)| (k, v)).collect();
        assert_eq!(
            unsafe { nupp_table_owned_initialize(&mut table, owner.heap_pointer(), u64::MAX) },
            1
        );
        assert_eq!(
            unsafe { nupp_table_owned_initialize(&mut table, owner.heap_pointer(), 4) },
            1,
            "initialization cannot replace live owned backing"
        );
        assert_eq!(
            (
                table.ptr,
                table.mask,
                table.cap,
                table.len,
                table.order,
                table.rank,
                table.owner
            ),
            state
        );
        let index = unsafe { *table.order };
        unsafe {
            *table.order = table.cap as u32;
        }
        assert_eq!(unsafe { nupp_table_owned_grow(&mut table) }, 1);
        assert_eq!(
            (
                table.ptr,
                table.mask,
                table.cap,
                table.len,
                table.order,
                table.rank,
                table.owner
            ),
            state
        );
        unsafe {
            *table.order = index;
        }
        assert_eq!(
            table.iter().map(|(&k, &v)| (k, v)).collect::<Vec<_>>(),
            entries
        );
        let borrowed_value = *table.get(&Value::inline_integer(0).unwrap()).unwrap();
        let before = table.ptr;
        table.insert(Value::inline_integer(9).unwrap(), borrowed_value);
        assert_ne!(
            table.ptr, before,
            "new backing must exist before old backing is released"
        );
        assert_eq!(
            table.get(&Value::inline_integer(9).unwrap()),
            Some(&borrowed_value)
        );
        assert_eq!(
            table.next_after(Value::inline_integer(0).unwrap()),
            Some((
                Value::inline_integer(1).unwrap(),
                Value::inline_integer(101).unwrap()
            ))
        );
    }

    #[test]
    fn owned_hash_packed_backing_reuses_pool_and_reinitializes_tombstones() {
        let owner = NativeAllocator::new();
        let mut table = owner.value_table(0);
        for (key, value) in [(Value::NIL, Value::TRUE), (Value::TRUE, Value::NIL)] {
            table.insert(key, value);
            assert!(table.ptr.is_null());
        }
        table.insert(Value::FALSE, Value::TRUE);
        table.insert(Value::num(0.0), Value::inline_integer(-1).unwrap());
        assert_eq!(
            table.order as usize,
            table.ptr as usize + table.cap as usize * 16
        );
        assert_eq!(
            table.rank as usize,
            table.ptr as usize + table.cap as usize * 20
        );
        assert_eq!(table.backing_bytes(), table.cap as usize * 24);
        table.insert(Value::FALSE, Value::NIL);
        assert_eq!(table.entry_at(0), Some((Value::FALSE, Value::NIL)));
        assert_eq!(
            table.next_after(Value::FALSE),
            Some((Value::num(0.0), Value::inline_integer(-1).unwrap()))
        );
        let base = table.ptr;
        drop(table);
        let fresh = owner.value_table(1);
        assert_eq!(fresh.ptr, base);
        assert!(fresh.iter().next().is_none());
        for bucket in 0..fresh.cap as usize {
            assert_eq!(unsafe { *fresh.ptr.add(bucket * 2) }, Value::NIL.0);
            assert_eq!(unsafe { *fresh.ptr.add(bucket * 2 + 1) }, 0);
            assert_eq!(unsafe { *fresh.order.add(bucket) }, 0);
            assert_eq!(unsafe { *fresh.rank.add(bucket) }, 0);
        }
    }
}
