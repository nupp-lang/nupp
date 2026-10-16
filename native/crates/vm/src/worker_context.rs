//! The module-level runtime state a worker body needs beside its graph.
//!
//! A worker loads the parent's code but runs none of its module bodies: its
//! modules arrive as the graph its body captures. Two things those bodies set
//! up live outside any module table, so the graph alone does not carry them:
//! the methods a record shape dispatches (`SetMethod` as a module loads) and
//! the cleanup registry modules fill in `_G` with their affine terminals. A
//! record a library creates inside the worker -- a span over a moved array --
//! would otherwise have no methods, and a `with` over it no terminal.
//!
//! `capture` finds what the body can reach: the objects its graph holds, the
//! functions those objects and their code name, the shapes those functions
//! create or test and the records the graph holds, and transitively the
//! methods of those shapes. It carries those shapes' methods and the registry
//! entries the functions name. The worker loads the same code, so shape ids
//! agree on both sides.
use crate::{
    heap::{Heap, KIND_CLOSURE, KIND_RECORD, KIND_TABLE},
    interp::{Interp, Op},
    value::Value,
};
use std::collections::HashSet;

const CLEANUP_REGISTRY: &str = "__nuppCleanupRegistry";

/// A table `{cleanups, methods}` -- registry entries by key, and method
/// tables by shape id -- or nil when the body needs neither.
pub(crate) fn capture(vm: &mut Interp, callee: Value, args: &[Value]) -> Value {
    let registry = vm
        .loaded
        .get("_G")
        .copied()
        .zip(vm.heap.interned_key(CLEANUP_REGISTRY))
        .map(|(globals, key)| vm.get_index(globals, key))
        .filter(|&r| vm.kind_of(r) == Some(KIND_TABLE));
    let mut objects: Vec<Value> = vec![callee];
    objects.extend_from_slice(args);
    let mut seen = HashSet::new();
    let mut functions = vec![];
    let mut visited = HashSet::new();
    let mut shapes = HashSet::new();
    let mut methods = vec![];
    let mut cleanups = vec![];
    let mut shape = |vm: &Interp, s: u32, objects: &mut Vec<Value>| {
        if (s as usize) < vm.heap.shapes.len() && shapes.insert(s) {
            let m = &vm.heap.shapes[s as usize].methods;
            if !m.is_empty() {
                methods.push(s);
                objects.extend(m.values().copied());
            }
        }
    };
    loop {
        if let Some(v) = objects.pop() {
            if let Some(f) = v.as_func() {
                functions.push(f);
                continue;
            }
            let Some(p) = v.as_obj() else { continue };
            if !seen.insert(v) {
                continue;
            }
            let h = unsafe { p.as_ref() };
            match h.kind {
                KIND_CLOSURE => functions.push(h.fid()),
                KIND_RECORD => shape(vm, h.shape(), &mut objects),
                _ => {}
            }
            Heap::each_child(h, &mut |c| objects.push(c));
            continue;
        }
        let Some(f) = functions.pop() else { break };
        if !visited.insert(f) || f as usize >= vm.funcs.len() {
            continue;
        }
        for &k in &vm.funcs[f as usize].consts {
            if let Some(g) = k.as_func() {
                functions.push(g);
            } else if let Some(r) = registry.filter(|_| vm.is_stringish(k)) {
                let entry = vm.get_index(r, k);
                if entry != Value::NIL {
                    cleanups.push((k, entry));
                    objects.push(entry);
                }
            }
        }
        for op in &vm.funcs[f as usize].code {
            match *op {
                Op::NewRecord(_, s) | Op::TagCheckRec(_, _, s) | Op::IsRec(_, _, s) => {
                    shape(vm, s, &mut objects)
                }
                Op::Call(g, ..) | Op::CallT(g, ..) | Op::NewClosure(_, g, ..) => functions.push(g),
                _ => {}
            }
        }
    }
    if methods.is_empty() && cleanups.is_empty() {
        return Value::NIL;
    }
    // Everything placed in these tables stays reachable from the shapes and
    // the registry, which are roots, while they are built.
    let scope = vm.open_scope();
    let context = vm.new_table();
    vm.handles.push(context);
    let registry = vm.new_table();
    vm.set_index(context, Value::num(1.0), registry);
    for (k, v) in cleanups {
        vm.set_index(registry, k, v);
    }
    let by_shape = vm.new_table();
    vm.set_index(context, Value::num(2.0), by_shape);
    for s in methods {
        let key = vm.intern(&s.to_string());
        vm.handles.push(key);
        let table = vm.new_table();
        vm.set_index(by_shape, key, table);
        let pairs: Vec<_> = vm.heap.shapes[s as usize].methods.iter().map(|(&k, &v)| (k, v)).collect();
        for (k, v) in pairs {
            vm.set_index(table, k, v);
        }
    }
    vm.close_scope(scope);
    context
}

/// Installs what `capture` carried, leaving anything the worker already has.
pub(crate) fn install(vm: &mut Interp, context: Value) {
    if vm.kind_of(context) != Some(KIND_TABLE) {
        return;
    }
    let root = vm.register(context);
    let registry = vm.get_index(context, Value::num(1.0));
    if let Some(&globals) = vm.loaded.get("_G") {
        let key = vm.intern(CLEANUP_REGISTRY);
        let existing = vm.get_index(globals, key);
        if existing == Value::NIL {
            vm.set_index(globals, key, registry);
        } else {
            let pairs: Vec<_> = vm.heap_table_pairs(registry);
            for (k, v) in pairs {
                if vm.get_index(existing, k) == Value::NIL {
                    vm.set_index(existing, k, v);
                }
            }
        }
    }
    let by_shape = vm.get_index(context, Value::num(2.0));
    for (s, table) in vm.heap_table_pairs(by_shape) {
        let Some(s) = std::str::from_utf8(vm.bytes_of(s)).ok().and_then(|t| t.parse::<u32>().ok()) else {
            continue;
        };
        if s as usize >= vm.heap.shapes.len() {
            continue;
        }
        for (k, v) in vm.heap_table_pairs(table) {
            if !vm.heap.shapes[s as usize].methods.contains_key(&k) {
                vm.set_method(s, k, v);
            }
        }
    }
    vm.release(root);
}

impl Interp {
    fn heap_table_pairs(&self, table: Value) -> Vec<(Value, Value)> {
        match table.as_obj() {
            Some(p) if unsafe { p.as_ref().kind } == KIND_TABLE => {
                unsafe { p.as_ref() }.table_ref().hash.iter().map(|(&k, &v)| (k, v)).collect()
            }
            _ => vec![],
        }
    }
}
