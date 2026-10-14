//! Temporary filesystem owners share the native filesystem implementation.
use crate::{builtins::Outs, interp::Interp, value::Value};
use std::path::PathBuf;

pub(crate) struct Owner(pub Option<PathBuf>);
impl Drop for Owner {
    fn drop(&mut self) {
        if let Some(path) = &self.0 {
            let _ = nupp_native_files::remove(path, true);
        }
    }
}
fn field(vm: &mut Interp, object: Value, name: &str) -> Value {
    let key = vm.intern(name);
    vm.get_index_any(object, key)
}
fn option(vm: &mut Interp, options: Value, name: &str) -> Option<String> {
    if options == Value::NIL {
        return None;
    }
    let mut value = field(vm, options, name);
    if name == "directory" && value != Value::NIL && !vm.is_stringish(value) {
        value = field(vm, value, "_text");
    }
    if value == Value::NIL {
        return None;
    }
    if !vm.is_stringish(value) {
        vm.err(&format!("temporary {name} must be a string"));
    }
    Some(String::from_utf8_lossy(vm.bytes_of(value)).into_owned())
}
pub(crate) fn create(vm: &mut Interp, directory: bool, options: Value) -> Outs {
    let root = option(vm, options, "directory").map(PathBuf::from);
    let prefix = option(vm, options, "prefix").unwrap_or_default();
    let suffix = option(vm, options, "suffix").unwrap_or_default();
    let kind = if directory {
        nupp_native_files::TemporaryKind::Directory
    } else {
        nupp_native_files::TemporaryKind::File
    };
    let bytes = match nupp_native_files::create_temporary(root.as_deref(), &prefix, &suffix, kind) {
        Ok(bytes) => bytes,
        Err(error) => {
            return [Value::NIL, vm.heap_new_string(&error.to_string())]
                .into_iter()
                .collect();
        }
    };
    let owner = Owner(Some(nupp_native_files::path_from_bytes(&bytes).unwrap()));
    let object = vm.new_table();
    let handle = vm.register(object);
    let text = vm.new_string_bytes(&bytes);
    let text_root = vm.register(text);
    let key = vm.intern("_text");
    vm.set_index(object, key, text);
    vm.release(text_root);
    for method in ["toString", "close", "isReleased", "persist"] {
        let key = vm.intern(method);
        let builtin = crate::builtins::id_of(&format!("temporary.{method}")).unwrap();
        vm.set_index(object, key, Value::builtin(builtin));
    }
    vm.temporary_paths.insert(object, owner);
    vm.resources.insert(object, "nupp.io.temporaryPath".into());
    vm.release(handle);
    [object].into_iter().collect()
}
pub(crate) fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Outs {
    let object = args.first().copied().unwrap_or(Value::NIL);
    match name {
        "temporary.toString" => [field(vm, object, "_text")].into_iter().collect(),
        "temporary.isReleased" => [Value::boolean(!vm.temporary_paths.contains_key(&object))]
            .into_iter()
            .collect(),
        "temporary.close" => {
            if vm.temporary_paths.remove(&object).is_some() {
                vm.resources.remove(&object);
            }
            Outs::new()
        }
        "temporary.persist" => {
            let Some(owner) = vm.temporary_paths.get(&object) else {
                return [Value::FALSE, vm.intern("the temporary path is released")]
                    .into_iter()
                    .collect();
            };
            let destination = args.get(1).copied().unwrap_or(Value::NIL);
            if !vm.is_stringish(destination) {
                vm.err("temporary destination must be a string");
            }
            let destination =
                PathBuf::from(String::from_utf8_lossy(vm.bytes_of(destination)).into_owned());
            match nupp_native_files::rename(owner.0.as_ref().unwrap(), &destination) {
                Ok(()) => {
                    vm.temporary_paths.remove(&object).unwrap().0.take();
                    vm.resources.remove(&object);
                    [Value::TRUE].into_iter().collect()
                }
                Err(error) => [Value::FALSE, vm.heap_new_string(&error.to_string())]
                    .into_iter()
                    .collect(),
            }
        }
        _ => unreachable!(),
    }
}
