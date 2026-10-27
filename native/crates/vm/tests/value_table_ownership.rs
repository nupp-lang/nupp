#![cfg(feature = "native-runtime")]
use nupp_vm::interp::Interp;
use nupp_vm::persist::{self, Policies};
use nupp_vm::value::Value;

#[test]
fn restored_hash_backing_belongs_to_destination_after_source_destruction() {
    let bytes = {
        let mut source = Interp::new();
        let table = source.new_table();
        source.handles.push(table);
        for i in 0..2200 {
            let key = source.intern(&format!("field-{i}"));
            source.set_index(table, key, Value::inline_integer(i).unwrap());
        }
        for i in (0..2200).step_by(3) {
            let key = source.intern(&format!("field-{i}"));
            source.set_index(table, key, Value::NIL);
        }
        persist::save_graph(&mut source, &[table], &Policies::default()).unwrap()
    };
    let mut destination = Interp::new();
    let table =
        persist::load_graph(&mut destination, &bytes, &Policies::default(), None).unwrap()[0];
    destination.handles.push(table);
    destination.full_cycle();
    let keys = destination.table_keys(table);
    let expected: Vec<_> = (0..2200)
        .filter(|i| i % 3 != 0)
        .map(|i| format!("field-{i}"))
        .collect();
    assert_eq!(
        keys.iter()
            .map(|&key| String::from_utf8_lossy(destination.bytes_of(key)).into_owned())
            .collect::<Vec<_>>(),
        expected
    );
    for i in 2200..4500 {
        let key = destination.intern(&format!("field-{i}"));
        destination.set_index(table, key, Value::inline_integer(i).unwrap());
    }
    destination.full_cycle();
    for i in 0..4500 {
        let key = destination.intern(&format!("field-{i}"));
        assert_eq!(
            destination.get_index(table, key),
            if i < 2200 && i % 3 == 0 {
                Value::NIL
            } else {
                Value::inline_integer(i).unwrap()
            }
        );
    }
}
