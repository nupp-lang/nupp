//! `include/nupp_extension.h` and the Rust ABI in `nupp-extension` describe
//! one layout: libclang reads the header, and every struct's size and every
//! field's offset must equal the Rust definition's.
#![cfg(feature = "c-headers")]
use nupp_extension::abi;
use nupp_vm::cdecl::Registry;
use serde_json::{json, Value};
use std::mem::{offset_of, size_of};

fn header() -> String {
    let text = include_str!("../include/nupp_extension.h");
    // Parsed in memory with no system headers: the fixed-width types are
    // declared here for the LP64 targets the VM runs on.
    let prelude = "typedef unsigned long size_t; typedef int int32_t; typedef unsigned int uint32_t; \
                   typedef long long int64_t; typedef unsigned long long uint64_t;\n";
    let body: String = text.lines().filter(|l| !l.starts_with("#include")).map(|l| format!("{l}\n")).collect();
    format!("{prelude}{body}")
}

fn layout(registry: &mut Registry, name: &str) -> (usize, Vec<(String, usize)>) {
    let ty = registry.execute(&json!({"operation":"type","text":name})).unwrap();
    let declaration = registry.execute(&json!({"operation":"struct","id":ty["id"]})).unwrap();
    let fields = declaration["fields"]
        .as_array()
        .unwrap()
        .iter()
        .map(|f: &Value| (f["name"].as_str().unwrap().to_string(), f["offset"].as_u64().unwrap() as usize))
        .collect();
    (ty["size"].as_u64().unwrap() as usize, fields)
}

#[test]
fn the_header_and_the_rust_abi_agree() {
    assert_eq!(size_of::<usize>(), 8, "the header check assumes an LP64 target");
    let mut registry = Registry::new().unwrap();
    registry.execute(&json!({"operation":"declare","text":header()})).unwrap();

    let expect = |registry: &mut Registry, name: &str, size: usize, fields: &[(&str, usize)]| {
        let (c_size, c_fields) = layout(registry, name);
        assert_eq!(c_size, size, "sizeof({name})");
        let names: Vec<_> = c_fields.iter().map(|(n, _)| n.as_str()).collect();
        let rust: Vec<_> = fields.iter().map(|(n, _)| *n).collect();
        assert_eq!(names, rust, "{name}'s fields");
        for ((field, offset), (_, rust_offset)) in c_fields.iter().zip(fields) {
            assert_eq!(offset, rust_offset, "offsetof({name}, {field})");
        }
    };
    expect(&mut registry, "nupp_string", size_of::<abi::Str>(), &[("bytes", offset_of!(abi::Str, bytes)), ("length", offset_of!(abi::Str, length))]);
    expect(
        &mut registry,
        "nupp_slot",
        size_of::<abi::Slot>(),
        &[("kind", offset_of!(abi::Slot, kind)), ("reserved", offset_of!(abi::Slot, reserved)), ("as", offset_of!(abi::Slot, value))],
    );
    expect(
        &mut registry,
        "nupp_function_entry",
        size_of::<abi::FunctionEntry>(),
        &[
            ("name", offset_of!(abi::FunctionEntry, name)),
            ("signature", offset_of!(abi::FunctionEntry, signature)),
            ("function", offset_of!(abi::FunctionEntry, function)),
            ("data", offset_of!(abi::FunctionEntry, data)),
            ("flags", offset_of!(abi::FunctionEntry, flags)),
            ("reserved", offset_of!(abi::FunctionEntry, reserved)),
        ],
    );
    expect(
        &mut registry,
        "nupp_resource_type",
        size_of::<abi::ResourceType>(),
        &[
            ("name", offset_of!(abi::ResourceType, name)),
            ("type_data", offset_of!(abi::ResourceType, type_data)),
            ("drop", offset_of!(abi::ResourceType, drop)),
            ("save", offset_of!(abi::ResourceType, save)),
            ("restore", offset_of!(abi::ResourceType, restore)),
        ],
    );
    expect(
        &mut registry,
        "nupp_extension",
        size_of::<abi::Extension>(),
        &[
            ("abi_version", offset_of!(abi::Extension, abi_version)),
            ("size", offset_of!(abi::Extension, size)),
            ("module", offset_of!(abi::Extension, module)),
            ("target", offset_of!(abi::Extension, target)),
            ("functions", offset_of!(abi::Extension, functions)),
            ("function_count", offset_of!(abi::Extension, function_count)),
            ("resource_types", offset_of!(abi::Extension, resource_types)),
            ("resource_type_count", offset_of!(abi::Extension, resource_type_count)),
            ("init", offset_of!(abi::Extension, init)),
            ("shutdown", offset_of!(abi::Extension, shutdown)),
        ],
    );
    expect(
        &mut registry,
        "nupp_host",
        size_of::<abi::Host>(),
        &[
            ("abi_version", offset_of!(abi::Host, abi_version)),
            ("size", offset_of!(abi::Host, size)),
            ("raise", offset_of!(abi::Host, raise)),
            ("retain", offset_of!(abi::Host, retain)),
            ("release", offset_of!(abi::Host, release)),
            ("invoke", offset_of!(abi::Host, invoke)),
            ("suspend", offset_of!(abi::Host, suspend)),
            ("complete", offset_of!(abi::Host, complete)),
            ("fail", offset_of!(abi::Host, fail)),
            ("new_resource", offset_of!(abi::Host, new_resource)),
            ("resource", offset_of!(abi::Host, resource)),
            ("close_resource", offset_of!(abi::Host, close_resource)),
            ("vm", offset_of!(abi::Host, vm)),
        ],
    );
}
