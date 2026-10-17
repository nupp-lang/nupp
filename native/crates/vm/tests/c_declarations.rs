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
#[test]
fn type_strings_cannot_introduce_tags() {
    let mut registry = Registry::new().unwrap();
    let error = registry
        .execute(&json!({"operation":"type","text":"struct Missing"}))
        .unwrap_err();
    assert!(
        error.contains("undeclared or implicit tag 'Missing'"),
        "{error}"
    );
    assert!(
        registry
            .execute(&json!({"operation":"type","text":"struct Missing *"}))
            .is_err()
    );
    request(&mut registry, "declare", "struct Present { int x; };");
    assert_eq!(
        request(&mut registry, "type", "struct Present")["name"],
        "Present"
    );
}

const COMPLETE_UNITS: [&str; 6] = [
    "typedef void (*nupp_complete_callback)(int value);",
    "typedef struct { float matrix[2][3]; nupp_complete_callback callback; } nupp_complete_context;",
    "void nupp_complete_use_context(nupp_complete_context *context);",
    "nupp_complete_callback nupp_complete_get_callback(void);",
    "void nupp_complete_set_callbacks(nupp_complete_callback callbacks[4]);",
    "int (*nupp_complete_get_row(void))[4];",
];
fn inspect(registry: &mut Registry, text: Value, prelude: Value) -> Value {
    request(
        registry,
        "inspect",
        &json!({"text":text,"prelude":prelude}).to_string(),
    )
}
fn complete_model(registry: &mut Registry, result: &Value, split: bool) -> u64 {
    assert_eq!(result["rejected"], json!([]), "{result}");
    assert_eq!(result["structs"].as_array().unwrap().len(), 1, "{result}");
    let context = &result["structs"][0];
    assert_eq!(context["name"], "nupp_complete_context");
    assert_eq!(context["unit"], if split { 2 } else { 1 });
    assert_eq!(context["fields"][0]["type"]["count"], 2);
    assert_eq!(context["fields"][0]["type"]["of"]["count"], 3);
    assert_eq!(context["fields"][0]["type"]["of"]["of"]["kind"], "float");
    assert_eq!(context["fields"][1]["type"]["to"]["kind"], "function");
    assert_eq!(result["functions"].as_array().unwrap().len(), 4, "{result}");
    for (name, unit) in [
        ("use_context", 3),
        ("get_callback", 4),
        ("set_callbacks", 5),
        ("get_row", 6),
    ] {
        let name = format!("nupp_complete_{name}");
        let f = result["functions"]
            .as_array()
            .unwrap()
            .iter()
            .find(|f| f["name"] == name)
            .unwrap();
        assert_eq!(f["unit"], if split { unit } else { 1 });
    }
    let id = context["id"].as_u64().unwrap();
    assert_eq!(request(registry, "type", "nupp_complete_context")["id"], id);
    id
}
#[test]
fn whole_split_whole_reclaims_owned_models() {
    let mut registry = Registry::new().unwrap();
    let whole = COMPLETE_UNITS.join("\n");
    let first = inspect(&mut registry, json!(whole), Value::Null);
    let id = complete_model(&mut registry, &first, false);
    let split = inspect(&mut registry, json!(COMPLETE_UNITS), Value::Null);
    assert_eq!(complete_model(&mut registry, &split, true), id);
    let repeat = inspect(&mut registry, json!(whole), Value::Null);
    assert_eq!(complete_model(&mut registry, &repeat, false), id);
}
#[test]
fn split_whole_split_preserves_ids() {
    let mut registry = Registry::new().unwrap();
    let first = inspect(&mut registry, json!(COMPLETE_UNITS), Value::Null);
    let id = complete_model(&mut registry, &first, true);
    let whole = inspect(&mut registry, json!(COMPLETE_UNITS.join("\n")), Value::Null);
    assert_eq!(complete_model(&mut registry, &whole, false), id);
    let repeat = inspect(&mut registry, json!(COMPLETE_UNITS), Value::Null);
    assert_eq!(complete_model(&mut registry, &repeat, true), id);
}

#[test]
fn replay_ignores_trivia_but_preserves_literal_qualifier_and_attribute_tokens() {
    let mut registry = Registry::new().unwrap();
    let original = "typedef struct { int values[3]; } Trivia;";
    let first = inspect(&mut registry, json!(original), Value::Null);
    let replay = inspect(
        &mut registry,
        json!("/* outer */ typedef struct { int /* member */ values [ 3 ] ; } Trivia ; // tail"),
        Value::Null,
    );
    assert_eq!(first, replay);
    let before = request(&mut registry, "type", "Trivia");
    // Equal evaluated bounds still differ lexically. A new anonymous type must
    // reach Clang rather than being deduplicated by its layout or integer value.
    for changed in [
        "typedef struct { int values[03]; } Trivia;",
        "typedef struct { int values[4]; } Trivia;",
        "typedef struct { unsigned int values[3]; } Trivia;",
        "typedef struct { const int values[3]; } Trivia;",
        "typedef struct { int values[3]; } __attribute__((aligned(16))) Trivia;",
    ] {
        let error = registry
            .execute(&json!({"operation":"declare","text":changed}))
            .unwrap_err();
        assert!(error.contains("redefinition"), "{error}");
        assert_eq!(request(&mut registry, "type", "Trivia"), before);
    }
    assert_eq!(inspect(&mut registry, json!(original), Value::Null), first);
    request(&mut registry, "declare", "typedef void (*Callback)(int);");
    assert!(
        registry
            .execute(&json!({"operation":"declare","text":"typedef void (*Callback)(double);"}))
            .is_err()
    );
}

#[test]
fn changed_file_scope_bindings_invalidate_identifier_absence() {
    for new_binding in ["typedef int future;", "struct future { int n; };"] {
        let mut registry = Registry::new().unwrap();
        request(
            &mut registry,
            "declare",
            "typedef struct { int future; } HasMember;",
        );
        request(&mut registry, "declare", new_binding);
        // The member spelling originally had no ordinary OR tag binding. This
        // unrelated addition deliberately over-invalidates its certificate.
        let error = registry.execute(&json!({"operation":"declare","text":"typedef struct { int /* changed trivia */ future; } HasMember;"})).unwrap_err();
        assert!(error.contains("redefinition"), "{error}");
    }
}

#[test]
fn changed_macro_and_pack_context_do_not_enable_new_token_replay() {
    let mut macro_registry = Registry::new().unwrap();
    let text = "#define WIDTH 2\ntypedef struct { int values[WIDTH]; } MacroSized;";
    request(&mut macro_registry, "declare", text);
    let before = request(&mut macro_registry, "type", "MacroSized");
    request(
        &mut macro_registry,
        "declare",
        "#undef WIDTH\n#define WIDTH 3",
    );
    let error = macro_registry.execute(&json!({"operation":"declare","text":"typedef struct { int values [ WIDTH ]; } MacroSized;"})).unwrap_err();
    assert!(error.contains("redefinition"), "{error}");
    assert_eq!(request(&mut macro_registry, "type", "MacroSized"), before);
    // Preserve the legacy exact-block policy, which this repair does not make
    // context-sensitive. Only the differently partitioned token path is new.
    request(&mut macro_registry, "declare", text);

    let mut pack_registry = Registry::new().unwrap();
    request(
        &mut pack_registry,
        "declare",
        "typedef struct { char c; int n; } PackedContext;",
    );
    let before = request(&mut pack_registry, "type", "PackedContext");
    request(&mut pack_registry, "declare", "#pragma pack(push, 1)");
    let error = pack_registry.execute(&json!({"operation":"declare","text":"typedef struct { char c; int /* trivia */ n; } PackedContext;"})).unwrap_err();
    assert!(error.contains("redefinition"), "{error}");
    assert_eq!(request(&mut pack_registry, "type", "PackedContext"), before);
}

#[test]
fn failed_chunks_preserve_context_and_atomic_blobs_do_not_salvage_suffixes() {
    let mut registry = Registry::new().unwrap();
    request(
        &mut registry,
        "declare",
        "typedef struct { int n; } Atomic;",
    );
    let before = request(&mut registry, "type", "Atomic");
    // A failed directive does not close the accepted replay context.
    assert!(
        registry
            .execute(&json!({"operation":"declare","text":"#define BROKEN 1\nint malformed(;"}))
            .is_err()
    );
    let replay = inspect(
        &mut registry,
        json!("typedef struct { int /* ok */ n; } Atomic;"),
        Value::Null,
    );
    assert_eq!(replay["structs"][0]["id"], before["id"]);
    // Mixed old/new input cannot delete the duplicate and accept its suffix.
    assert!(registry.execute(&json!({"operation":"declare","text":"typedef struct { int n; } Atomic; int not_published(void);"})).is_err());
    assert!(
        request(&mut registry, "functions", "")
            .get("not_published")
            .is_none()
    );
    let partial = inspect(
        &mut registry,
        json!([
            "typedef struct { int /* replay */ n; } Atomic;",
            "typedef struct { unsigned int n; } Atomic;",
            "double survives(int n);"
        ]),
        Value::Null,
    );
    assert_eq!(partial["declared"], 3);
    assert_eq!(partial["rejected"].as_array().unwrap().len(), 1);
    assert_eq!(partial["rejected"][0]["unit"], 2);
    assert!(
        partial["rejected"][0]["reason"]
            .as_str()
            .unwrap()
            .contains("redefinition")
    );
    assert_eq!(partial["functions"][0]["name"], "survives");
    assert_eq!(partial["functions"][0]["unit"], 3);
    assert_eq!(request(&mut registry, "type", "Atomic"), before);
}

#[test]
fn target_ownership_excludes_preludes_references_and_comments() {
    let mut registry = Registry::new().unwrap();
    let prelude = "typedef struct Vocabulary Vocabulary; int neighbor(void); enum Pre { PRE = 1 };";
    let first = inspect(
        &mut registry,
        json!("struct Owned { Vocabulary *value; }; // neighbor PRE"),
        json!(prelude),
    );
    assert_eq!(first["structs"].as_array().unwrap().len(), 1);
    assert_eq!(first["structs"][0]["name"], "Owned");
    assert_eq!(first["functions"], json!([]));
    assert_eq!(first["enums"], json!([]));
    assert_eq!(
        inspect(
            &mut registry,
            json!("struct Owned { Vocabulary *value; }; // neighbor PRE"),
            json!(prelude)
        ),
        first
    );
    let explicit = inspect(
        &mut registry,
        json!(["int neighbor(void);", "enum Pre { PRE = 1 };"]),
        Value::Null,
    );
    assert_eq!(explicit["functions"][0]["unit"], 1);
    assert_eq!(explicit["enums"][0]["unit"], 2);
    let bad_prelude = inspect(
        &mut registry,
        json!("struct Kept { int n; };"),
        json!(["typedef int Word;", "typedef unknown_type Broken;"]),
    );
    assert_eq!(bad_prelude["rejected"], json!([]));
    assert_eq!(bad_prelude["structs"][0]["name"], "Kept");
}

#[test]
fn completed_forward_claims_read_the_current_recursive_model() {
    let mut registry = Registry::new().unwrap();
    let prelude = "typedef struct Forward Forward;";
    request(&mut registry, "declare", prelude);
    let incomplete = request(&mut registry, "type", "Forward");
    let definition = "struct Forward { int value; Forward *next; };";
    let completed = inspect(&mut registry, json!(definition), json!(prelude));
    assert_eq!(completed["structs"].as_array().unwrap().len(), 1);
    let current = &completed["structs"][0];
    assert_eq!(current["id"], incomplete["id"]);
    assert_eq!(current["fields"][1]["type"]["to"]["id"], incomplete["id"]);
    for target in [
        prelude,
        definition,
        "struct Forward { int value; Forward * next; }; /* replay */",
    ] {
        let result = inspect(&mut registry, json!(target), Value::Null);
        assert_eq!(result["structs"][0], *current);
    }
}

#[test]
fn top_level_range_groups_do_not_replay_interior_fields() {
    let mut registry = Registry::new().unwrap();
    let text = "typedef struct { int a; int b; } Pair, *PairPtr; enum Mode2 { MODE2 = -2 }; int pair_use(PairPtr);";
    let first = inspect(&mut registry, json!(text), Value::Null);
    assert_eq!(first["structs"].as_array().unwrap().len(), 1);
    assert_eq!(first["enums"][0]["values"][0]["value"], -2);
    for _ in 0..12 {
        let replay = inspect(
            &mut registry,
            json!(
                "typedef struct { int a ; int b ; } Pair , * PairPtr ; enum Mode2 { MODE2 = -2 }; int pair_use ( PairPtr );"
            ),
            Value::Null,
        );
        assert_eq!(replay, first);
    }
    // New variables must parse normally; they are not anonymous record fields.
    request(&mut registry, "declare", "int a; int b;");
    assert_eq!(
        request(&mut registry, "type", "PairPtr")["to"]["id"],
        first["structs"][0]["id"]
    );
}

#[test]
fn unsupported_roots_and_pragma_operators_close_only_new_replay() {
    for context in [
        "int global_value = 1;",
        "int body(void) { return 1; }",
        "_Pragma(\"pack(push,1)\")",
    ] {
        let mut registry = Registry::new().unwrap();
        let text = "typedef struct { int n; } BeforeContext;";
        request(&mut registry, "declare", text);
        request(&mut registry, "declare", context);
        // The old exact text remains idempotent. A nonexact request must use
        // normal Clang diagnostics once any uncertified construct was accepted.
        request(&mut registry, "declare", text);
        let error = registry.execute(&json!({"operation":"declare","text":"typedef struct { int /* nonexact */ n; } BeforeContext;"})).unwrap_err();
        assert!(error.contains("redefinition"), "{context}: {error}");
    }
}

#[test]
fn whole_fixture_replay_uses_the_actual_guard_stripped_header() {
    let mut registry = Registry::new().unwrap();
    let whole = include_str!("../../../../tests/fixtures/complete_c_interop.h")
        .lines()
        .filter(|line| !line.trim_start().starts_with('#'))
        .collect::<Vec<_>>()
        .join("\n");
    let first = inspect(&mut registry, json!(whole), Value::Null);
    let id = complete_model(&mut registry, &first, false);
    let split = inspect(&mut registry, json!(COMPLETE_UNITS), Value::Null);
    assert_eq!(complete_model(&mut registry, &split, true), id);
    let repeat = inspect(&mut registry, json!(whole), Value::Null);
    assert_eq!(complete_model(&mut registry, &repeat, false), id);
}

#[test]
fn anonymous_enum_and_explicit_alias_replay_keep_owned_values() {
    let mut registry = Registry::new().unwrap();
    let original = "typedef enum { ANON_NEG = -1, ANON_LAST = 7 } AnonEnum;";
    let first = inspect(&mut registry, json!(original), Value::Null);
    assert_eq!(first["enums"].as_array().unwrap().len(), 1);
    assert_eq!(first["enums"][0]["name"], Value::Null);
    assert_eq!(
        first["enums"][0]["values"][0],
        json!({"name":"ANON_NEG","value":-1})
    );
    assert_eq!(
        inspect(
            &mut registry,
            json!("typedef enum { ANON_NEG=-1, ANON_LAST=7 } AnonEnum ;"),
            Value::Null
        ),
        first
    );
    let alias = inspect(
        &mut registry,
        json!("typedef AnonEnum AnonAlias;"),
        Value::Null,
    );
    assert_eq!(alias["enums"][0], first["enums"][0]);
    assert_eq!(
        request(&mut registry, "type", "AnonAlias")["id"],
        first["enums"][0]["id"]
    );
}

#[test]
fn replay_does_not_hide_lexical_errors() {
    let mut registry = Registry::new().unwrap();
    let original = "typedef struct { int value; } Lexical;";
    request(&mut registry, "declare", original);
    let before = request(&mut registry, "type", "Lexical");
    for suffix in ["/* unterminated", "\"unterminated", "'x"] {
        let text = format!("/* nonexact trivia */ {original}\n{suffix}");
        assert!(
            registry
                .execute(&json!({"operation":"declare","text":text}))
                .is_err(),
            "accepted lexical error: {suffix}"
        );
        assert_eq!(request(&mut registry, "type", "Lexical"), before);
    }
    let replay = inspect(
        &mut registry,
        json!("typedef struct { int /* valid trivia */ value; } Lexical;"),
        Value::Null,
    );
    assert_eq!(replay["structs"][0]["id"], before["id"]);
}

#[test]
fn replay_does_not_hide_nested_tag_rebinding() {
    let mut registry = Registry::new().unwrap();
    request(&mut registry, "declare", "int visit(struct Hidden *value);");
    let before = request(&mut registry, "functions", "");
    request(
        &mut registry,
        "declare",
        "struct Wrapper { struct Hidden { int n; } h; };",
    );
    assert!(
        registry
            .execute(&json!({"operation":"declare","text":"int visit (struct Hidden *value);"}))
            .is_err(),
        "replayed a prototype after a nested declaration changed the file-scope tag binding"
    );
    assert_eq!(request(&mut registry, "functions", ""), before);
}
#[test]
fn anonymous_aggregate_members_keep_unrelated_replay_available() {
    let mut registry = Registry::new().unwrap();
    let whole = COMPLETE_UNITS.join("\n");
    let first = inspect(&mut registry, json!(whole), Value::Null);
    let id = complete_model(&mut registry, &first, false);
    let aggregate =
        "struct layout_tagged { int32_t tag; union { int32_t i; double d; }; int32_t after; };";
    let aggregate_model = inspect(&mut registry, json!(aggregate), Value::Null);
    assert_eq!(aggregate_model["structs"][0]["anonymous"], 1);
    let before = request(&mut registry, "type", "struct layout_tagged");
    let split = inspect(&mut registry, json!(COMPLETE_UNITS), Value::Null);
    assert_eq!(complete_model(&mut registry, &split, true), id);
    assert_eq!(
        request(&mut registry, "type", "struct layout_tagged"),
        before
    );
}

#[test]
fn anonymous_members_do_not_hide_nested_namespace_changes() {
    for member in [
        "union { struct Hidden { int n; } h; };",
        "struct { struct Hidden { int n; } h; };",
    ] {
        let mut registry = Registry::new().unwrap();
        request(&mut registry, "declare", "int visit(struct Hidden *value);");
        request(
            &mut registry,
            "declare",
            &format!("struct AnonymousWrapper {{ {member} }};"),
        );
        assert!(
            registry
                .execute(
                    &json!({"operation":"declare", "text":"int visit (struct Hidden *value);"})
                )
                .is_err(),
            "anonymous member hid a file-scope tag: {member}"
        );
    }
    let mut registry = Registry::new().unwrap();
    request(
        &mut registry,
        "declare",
        "typedef struct { int FUTURE_ENUM; } BeforeNestedEnum;",
    );
    request(
        &mut registry,
        "declare",
        "struct NestedEnumWrapper { enum { FUTURE_ENUM = 1 } value; };",
    );
    assert!(registry.execute(&json!({"operation":"declare", "text":"typedef struct { int /* replay */ FUTURE_ENUM; } BeforeNestedEnum;"})).is_err(), "nested enum bindings must still close replay");
}

#[test]
fn trailing_type_attributes_keep_unrelated_replay_available() {
    let mut registry = Registry::new().unwrap();
    let first = inspect(&mut registry, json!(COMPLETE_UNITS.join("\n")), Value::Null);
    let id = complete_model(&mut registry, &first, false);
    request(
        &mut registry,
        "declare",
        "typedef int32_t layout_wide_int __attribute__((aligned(8)));",
    );
    let before = request(&mut registry, "type", "layout_wide_int");
    let split = inspect(&mut registry, json!(COMPLETE_UNITS), Value::Null);
    assert_eq!(complete_model(&mut registry, &split, true), id);
    assert_eq!(request(&mut registry, "type", "layout_wide_int"), before);
}

#[test]
fn trailing_attributes_belong_to_their_declaration_group() {
    let mut registry = Registry::new().unwrap();
    let declaration = "typedef struct { int value; } Attributed __attribute__((aligned(8)));";
    let function = "int attr_use(Attributed *value);";
    let first = inspect(
        &mut registry,
        json!(format!("{declaration} {function}")),
        Value::Null,
    );
    assert_eq!(first["rejected"], json!([]));
    let id = first["structs"][0]["id"].clone();
    let split = inspect(
        &mut registry,
        json!([
            "typedef struct { int /* trivia */ value; } Attributed __attribute__ ((aligned (8)));",
            function
        ]),
        Value::Null,
    );
    assert_eq!(split["rejected"], json!([]));
    assert_eq!(split["structs"][0]["id"], id);
    assert_eq!(split["structs"][0]["unit"], 1);
    assert_eq!(split["functions"][0]["unit"], 2);
    assert!(registry.execute(&json!({"operation":"declare", "text":"typedef struct { int value; } Attributed __attribute__((aligned(16)));"})).is_err(), "changed attribute tokens must use Clang diagnostics");
    let repeated = inspect(&mut registry, json!(declaration), Value::Null);
    assert_eq!(repeated["rejected"], json!([]));
    assert_eq!(repeated["structs"][0]["id"], id);
    assert_eq!(repeated["functions"], json!([]));
}
