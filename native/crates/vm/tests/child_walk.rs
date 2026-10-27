use nupp_vm::{
    heap::{Header, Heap, IterPayload, Roots, SlotTy, UserdataPayload, HEADER},
    value::Value,
};

struct NoRoots;
impl Roots for NoRoots {
    fn each_root(&self, _: &mut dyn FnMut(Value)) {}
}

fn integer(n: i64) -> Value {
    Value::inline_integer(n).unwrap()
}
fn heap() -> Heap {
    let mut heap = Heap::new();
    heap.automatic_collection = false;
    heap
}
fn children(value: Value) -> Vec<Value> {
    let mut values = Vec::new();
    Heap::each_child(unsafe { value.as_obj().unwrap().as_ref() }, &mut |v| {
        values.push(v)
    });
    values
}

#[repr(C)]
struct Cursor {
    phase: u64,
    index: u64,
    value: u64,
}
unsafe extern "C" {
    fn nupp_object_child_next(header: *const Header, cursor: *mut Cursor) -> u64;
}

#[test]
fn canonical_child_prefixes_and_cursor_layouts_match() {
    assert_eq!(std::mem::size_of::<Cursor>(), 24);
    assert_eq!(std::mem::align_of::<Cursor>(), 8);
    assert_eq!(std::mem::offset_of!(Cursor, phase), 0);
    assert_eq!(std::mem::offset_of!(Cursor, index), 8);
    assert_eq!(std::mem::offset_of!(Cursor, value), 16);
    assert_eq!(std::mem::offset_of!(IterPayload, obj), 0);
    assert_eq!(std::mem::offset_of!(IterPayload, pattern), 8);
    assert_eq!(std::mem::offset_of!(UserdataPayload, meta), 0);
    assert_eq!(std::mem::offset_of!(UserdataPayload, uservalue), 8);
    assert_eq!(std::mem::size_of::<UserdataPayload>(), 40);
    assert_eq!(std::mem::align_of::<UserdataPayload>(), 8);
}

#[test]
fn slot_and_inline_edges_include_every_scalar_and_nil_in_order() {
    let mut heap = heap();
    let source = heap.new_string("source", &NoRoots);
    let slots = [Value::NIL, integer(0), Value::FALSE, source, source];
    let closure = heap.new_closure(0, &slots, &NoRoots);
    assert_eq!(children(closure), slots);
    let cell = heap.new_cell(Value::NIL, &NoRoots);
    assert_eq!(children(cell), [Value::NIL]);
    let slice = heap.new_slice(source, 1, 3, &NoRoots);
    assert_eq!(children(slice), [source]);
    let iter = heap.new_iter(1, source, Value::NIL, slots.to_vec(), &NoRoots);
    assert_eq!(
        children(iter),
        [vec![source, Value::NIL], slots.to_vec()].concat()
    );
    let userdata = heap.new_userdata(Box::new(17u64), Value::NIL, source, 8, &NoRoots);
    assert_eq!(children(userdata), [Value::NIL, source]);
    let values = [
        source,
        heap.box_integer(
            nupp_vm::numeric::Integer {
                bits: i64::MAX as u64,
                unsigned: false,
            },
            &NoRoots,
        ),
        heap.new_bytes(8, &NoRoots),
        heap.new_storage(1, &NoRoots),
    ];
    for value in values {
        assert!(children(value).is_empty());
    }
    let mut cursor = Cursor {
        phase: 0,
        index: 0,
        value: 123,
    };
    let header = cell.as_obj().unwrap().as_ptr();
    unsafe {
        assert_eq!(nupp_object_child_next(header, &mut cursor), 1);
        assert_eq!(cursor.value, Value::NIL.0);
        for _ in 0..3 {
            assert_eq!(nupp_object_child_next(header, &mut cursor), 0);
            assert_eq!(cursor.phase, 4);
            assert_eq!(cursor.value, Value::NIL.0);
        }
    }
}

#[test]
fn table_children_follow_live_insertion_order_after_growth_and_tombstones() {
    let mut heap = heap();
    let table = heap.new_table(&NoRoots);
    let meta = heap.new_table(&NoRoots);
    let array = [Value::NIL, Value::FALSE, integer(7)];
    let mut expected = array.to_vec();
    unsafe {
        let header = &mut *table.as_obj().unwrap().as_ptr();
        let body = header.table();
        for value in array {
            body.array.push(value);
        }
        for n in 0..40 {
            body.hash.insert(integer(n * 73 + 2), integer(1000 + n));
        }
        for n in [0, 6, 21, 39] {
            body.hash.insert(integer(n * 73 + 2), Value::NIL);
        }
        body.hash.insert(integer(6 * 73 + 2), Value::TRUE);
        for n in 0..40 {
            if [0, 21, 39].contains(&n) {
                continue;
            }
            expected.push(integer(n * 73 + 2));
            expected.push(if n == 6 {
                Value::TRUE
            } else {
                integer(1000 + n)
            });
        }
        header.refresh();
        assert_eq!(children(table), expected);
        header.table().meta = meta;
    }
    expected.push(meta);
    assert_eq!(children(table), expected);
}

#[test]
fn record_children_keep_slots_array_metadata_and_overflow_order() {
    let mut heap = heap();
    let name = heap.intern("field", &NoRoots);
    let shape = heap.shape("ChildWalk", &[name], &[SlotTy::Any]);
    let record = heap.new_record(shape, &NoRoots);
    assert_eq!(children(record), [Value::NIL]);
    unsafe {
        let header = &mut *record.as_obj().unwrap().as_ptr();
        header.slots_mut()[0] = Value::FALSE;
        for value in [Value::NIL, integer(8)] {
            header.record_array().push(value);
        }
        assert_eq!(children(record), [Value::FALSE, Value::NIL, integer(8)]);
        let extra = header.ensure_record_extra();
        extra.fields.insert(integer(71), Value::TRUE);
        extra.fields.insert(integer(33), Value::FALSE);
        extra.fields.insert(integer(9), integer(10));
        extra.fields.insert(integer(33), Value::NIL);
        assert_eq!(
            children(record),
            [
                Value::FALSE,
                Value::NIL,
                integer(8),
                Value::NIL,
                integer(71),
                Value::TRUE,
                integer(9),
                integer(10)
            ]
        );
        header.record_tail().clear_extra();
        assert_eq!(children(record), [Value::FALSE, Value::NIL, integer(8)]);
        assert_eq!(
            header.payload() as usize,
            header as *const Header as usize + HEADER
        );
    }
}
