#![cfg(feature = "c-headers")]
use nupp_vm::cdecl::Registry;
use serde_json::{Value, json};
fn request(registry: &mut Registry, operation: &str, text: &str) -> Value {
    registry
        .execute(&json!({"operation":operation,"text":text}))
        .unwrap()
}
#[test]
fn c_headers_preserve_recursive_identity_layout_and_function_types() {
    let mut registry = Registry::new().unwrap();
    let names = request(
        &mut registry,
        "declare",
        "typedef struct Node { int value; struct Node *next; } Node; const char *label(Node *value, size_t index);",
    );
    assert_eq!(names, json!({"label":true}));
    let node = request(&mut registry, "type", "Node");
    let declaration = registry
        .execute(&json!({"operation":"struct","id":node["id"]}))
        .unwrap();
    assert_eq!(declaration["fields"][0]["offset"], 0);
    assert_eq!(declaration["fields"][1]["type"]["to"]["id"], node["id"]);
    assert_eq!(
        declaration["fields"][1]["offset"],
        std::mem::size_of::<usize>()
    );
    assert_eq!(node["size"], 2 * std::mem::size_of::<usize>());
    let functions = request(&mut registry, "functions", "");
    assert_eq!(functions["label"]["returns"]["const"], true);
    assert_eq!(
        functions["label"]["params"][0]["type"]["to"]["id"],
        node["id"]
    );
    assert_eq!(
        functions["label"]["params"][1]["type"]["size"],
        std::mem::size_of::<usize>()
    );
    assert_eq!(
        request(&mut registry, "type", "uint8_t[?]")["kind"],
        "array"
    );
    request(
        &mut registry,
        "declare",
        "typedef struct { double x; } Coordinate;",
    );
    assert_eq!(
        request(&mut registry, "type", "Coordinate")["name"],
        "Coordinate"
    );
    assert_eq!(
        request(&mut registry, "type", "int (*)(double)")["to"]["params"][0]["type"]["bits"],
        64
    );
}
#[test]
fn rejected_c_declarations_do_not_poison_the_registry() {
    let mut registry = Registry::new().unwrap();
    assert!(
        registry
            .execute(&json!({"operation":"declare","text":"int broken( ;"}))
            .is_err()
    );
    assert!(
        registry
            .execute(&json!({"operation":"type","text":"not_a_type"}))
            .is_err()
    );
    assert_eq!(
        request(&mut registry, "declare", "int valid(void);"),
        json!({"valid":true})
    );
    assert_eq!(
        request(&mut registry, "declare", "int valid(void);"),
        json!({"valid":true})
    );
    assert_eq!(request(&mut registry, "type", "int")["bits"], 32);
}
#[test]
fn inspection_reports_rejected_units_and_enumerators() {
    let mut registry = Registry::new().unwrap();
    let input = json!({"text":["enum Mode { FIRST = 3, LAST = 9 };", "not C;", "double accepted(int);"],"prelude":null});
    let result = request(&mut registry, "inspect", &input.to_string());
    assert_eq!(result["declared"], 3);
    assert_eq!(result["rejected"][0]["unit"], 2);
    assert_eq!(
        result["enums"][0]["values"][1],
        json!({"name":"LAST","value":9})
    );
    assert_eq!(result["functions"][0]["name"], "accepted");
    assert_eq!(result["functions"][0]["unit"], 3);
}

#[test]
fn anonymous_layout_probes_have_distinct_member_identity() {
    let mut registry = Registry::new().unwrap();
    let first = request(&mut registry, "type", "struct { int first; }");
    let second = request(&mut registry, "type", "struct { double second; }");
    assert_ne!(first["id"], second["id"]);
    let declaration = registry
        .execute(&json!({"operation":"struct", "id":second["id"]}))
        .unwrap();
    assert_eq!(declaration["fields"][0]["name"], "second");
    assert_eq!(declaration["size"], 8);
}
