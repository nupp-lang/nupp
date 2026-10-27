use nupp_vm::heap::{Heap, ValueTable};
use std::ops::{Deref, DerefMut};

pub struct TableFixture {
    table: ValueTable,
    _owner: Heap,
}
impl TableFixture {
    pub fn new(capacity: usize) -> Self {
        let owner = Heap::new();
        let table = unsafe { owner.value_table(capacity) };
        Self {
            table,
            _owner: owner,
        }
    }
}
impl Deref for TableFixture {
    type Target = ValueTable;
    fn deref(&self) -> &ValueTable {
        &self.table
    }
}
impl DerefMut for TableFixture {
    fn deref_mut(&mut self) -> &mut ValueTable {
        &mut self.table
    }
}
