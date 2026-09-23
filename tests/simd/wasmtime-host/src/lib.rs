use serde::Deserialize;
use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{CStr, CString, c_char};
use std::fs;
use std::path::Path;
use std::ptr;
use std::slice;
use wasmtime::{Config, Engine, Linker, Memory, Module, Store, TypedFunc};

const TRANSFER_LIMIT: usize = 2 * 1024 * 1024;

thread_local! {
    static OPEN_ERROR: RefCell<CString> = RefCell::new(CString::default());
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Manifest {
    schema_version: u32,
    target: String,
    units: Vec<UnitRecord>,
}

#[derive(Deserialize)]
struct UnitRecord {
    unit: Option<String>,
    wasm: Option<String>,
    bridge: Option<Bridge>,
    tier: Option<String>,
}

#[derive(Deserialize)]
struct Bridge {
    abi: u32,
    entries: Vec<EntryRecord>,
}

#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct EntryRecord {
    symbol: String,
    call: String,
    params: Vec<ParamRecord>,
    independent_counts: bool,
    results: Vec<String>,
    layouts: Vec<LayoutRecord>,
}

#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ParamRecord {
    kind: String,
    #[serde(rename = "type")]
    value_type: String,
    source_type: Option<String>,
}

#[derive(Clone, Deserialize)]
struct LayoutRecord {
    name: String,
    fields: Vec<String>,
    prefix: String,
}

struct Unit {
    memory: Memory,
    malloc: TypedFunc<i32, i32>,
    free: TypedFunc<i32, ()>,
    entries: HashMap<String, Entry>,
}

#[derive(Clone)]
struct Entry {
    record: EntryRecord,
    call: TypedFunc<(i32, i32), ()>,
    layouts: HashMap<String, Layout>,
}

#[derive(Clone)]
struct Layout {
    size: usize,
    fields: HashMap<String, Field>,
}

#[derive(Clone)]
struct Field {
    offset: usize,
    bytes: usize,
}

pub struct Host {
    store: Store<()>,
    units: HashMap<String, Unit>,
    error: CString,
}

#[repr(C)]
pub struct HostSpan {
    data: *mut u8,
    bytes: usize,
    stride: usize,
    count: usize,
    writable: u8,
    fields: *const HostField,
    fields_len: usize,
}

#[repr(C)]
pub struct HostField {
    name: *const c_char,
    offset: usize,
    bytes: usize,
}

fn message(value: impl std::fmt::Display) -> CString {
    CString::new(value.to_string().replace('\0', "\\0")).unwrap_or_default()
}

fn c_string(value: *const c_char, label: &str) -> Result<String, String> {
    if value.is_null() {
        return Err(format!("{label} is null"));
    }
    // SAFETY: Callers must supply a NUL-terminated string for every string parameter.
    let value = unsafe { CStr::from_ptr(value) };
    value
        .to_str()
        .map(str::to_owned)
        .map_err(|_| format!("{label} is not UTF-8"))
}

fn scalar_bytes(param: &ParamRecord) -> Option<usize> {
    match param.source_type.as_deref() {
        Some("uint8" | "int8") => return Some(1),
        Some("uint16" | "int16") => return Some(2),
        _ => {}
    }
    match param.value_type.as_str() {
        "bool" => Some(1),
        "f32" | "i32" | "u32" => Some(4),
        "f64" | "i64" | "u64" => Some(8),
        _ => None,
    }
}

fn checked_i32(value: usize, label: &str) -> Result<i32, String> {
    i32::try_from(value).map_err(|_| format!("{label} exceeds Wasm32"))
}

fn allocate(unit: &Unit, store: &mut Store<()>, bytes: usize) -> Result<i32, String> {
    let requested = checked_i32(bytes.max(1), "allocation")?;
    let pointer = unit
        .malloc
        .call(&mut *store, requested)
        .map_err(|error| format!("Wasm malloc failed: {error}"))?;
    if pointer <= 0 {
        return Err("Wasm malloc returned a null pointer".into());
    }
    let end = (pointer as usize)
        .checked_add(bytes)
        .ok_or_else(|| "Wasm allocation overflowed".to_string())?;
    if end > unit.memory.data_size(&mut *store) {
        return Err("Wasm allocation exceeds independent memory".into());
    }
    Ok(pointer)
}

impl Host {
    fn open(manifest_path: &Path, module_root: &Path) -> Result<Self, String> {
        let document = fs::read(manifest_path)
            .map_err(|error| format!("cannot read {}: {error}", manifest_path.display()))?;
        let manifest: Manifest = serde_json::from_slice(&document)
            .map_err(|error| format!("invalid units manifest: {error}"))?;
        if manifest.schema_version != 3 || manifest.target != "wasm32-unknown-emscripten" {
            return Err("Wasmtime host requires a schema-3 Emscripten Wasm manifest".into());
        }

        let mut config = Config::new();
        config.wasm_simd(true);
        let engine = Engine::new(&config).map_err(|error| error.to_string())?;
        let mut store = Store::new(&engine, ());
        let mut units = HashMap::new();

        for record in manifest.units {
            let UnitRecord {
                unit,
                wasm,
                bridge,
                tier,
            } = record;
            let (Some(name), Some(wasm), Some(bridge)) = (unit, wasm, bridge) else {
                continue;
            };
            if tier.as_deref() != Some("simd128") || bridge.abi != 1 || units.contains_key(&name) {
                return Err(format!("invalid independent Wasm unit {name}"));
            }
            let path = module_root.join(wasm);
            let module = Module::from_file(&engine, &path)
                .map_err(|error| format!("cannot compile {}: {error}", path.display()))?;
            for import in module.imports() {
                let allowed = (import.module() == "env"
                    && import.name() == "emscripten_notify_memory_growth")
                    || (import.module() == "wasi_snapshot_preview1"
                        && import.name() == "proc_exit");
                if !allowed || import.ty().func().is_none() {
                    return Err(format!(
                        "unexpected independent Wasm import {}.{}",
                        import.module(),
                        import.name()
                    ));
                }
            }
            let mut linker = Linker::new(&engine);
            linker
                .func_wrap("env", "emscripten_notify_memory_growth", |_page: i32| {})
                .map_err(|error| error.to_string())?;
            linker
                .func_wrap(
                    "wasi_snapshot_preview1",
                    "proc_exit",
                    |code: i32| -> Result<(), wasmtime::Error> {
                        Err(wasmtime::Error::msg(format!(
                            "Wasm kernel aborted ({code})"
                        )))
                    },
                )
                .map_err(|error| error.to_string())?;
            let instance = linker
                .instantiate(&mut store, &module)
                .map_err(|error| format!("cannot instantiate {}: {error}", path.display()))?;
            if let Some(initialize) = instance.get_func(&mut store, "_initialize") {
                initialize
                    .typed::<(), ()>(&store)
                    .map_err(|error| error.to_string())?
                    .call(&mut store, ())
                    .map_err(|error| format!("Wasm initialization failed: {error}"))?;
            }
            let memory = instance
                .get_memory(&mut store, "memory")
                .ok_or_else(|| format!("independent Wasm unit {name} exports no memory"))?;
            let malloc = instance
                .get_typed_func::<i32, i32>(&mut store, "malloc")
                .map_err(|error| {
                    format!("independent Wasm unit {name} exports no malloc: {error}")
                })?;
            let free = instance
                .get_typed_func::<i32, ()>(&mut store, "free")
                .map_err(|error| {
                    format!("independent Wasm unit {name} exports no free: {error}")
                })?;
            let mut entries = HashMap::new();
            for entry in bridge.entries {
                let mut layouts = HashMap::new();
                for layout in &entry.layouts {
                    let size = instance
                        .get_typed_func::<(), i32>(&mut store, &format!("{}_size", layout.prefix))
                        .map_err(|error| {
                            format!("missing layout size for {}: {error}", layout.name)
                        })?
                        .call(&mut store, ())
                        .map_err(|error| {
                            format!("cannot read layout size for {}: {error}", layout.name)
                        })?;
                    let size = usize::try_from(size)
                        .map_err(|_| format!("invalid layout size for {}", layout.name))?;
                    let mut fields = HashMap::new();
                    for name in &layout.fields {
                        let offset = instance
                            .get_typed_func::<(), i32>(
                                &mut store,
                                &format!("{}_offset_{name}", layout.prefix),
                            )
                            .map_err(|error| {
                                format!("missing layout field {}.{name}: {error}", layout.name)
                            })?
                            .call(&mut store, ())
                            .map_err(|error| {
                                format!("cannot read layout field {}.{name}: {error}", layout.name)
                            })?;
                        let bytes = instance
                            .get_typed_func::<(), i32>(
                                &mut store,
                                &format!("{}_size_{name}", layout.prefix),
                            )
                            .map_err(|error| {
                                format!("missing layout field size {}.{name}: {error}", layout.name)
                            })?
                            .call(&mut store, ())
                            .map_err(|error| {
                                format!(
                                    "cannot read layout field size {}.{name}: {error}",
                                    layout.name
                                )
                            })?;
                        let offset = usize::try_from(offset).map_err(|_| {
                            format!("invalid layout field offset {}.{name}", layout.name)
                        })?;
                        let bytes = usize::try_from(bytes).map_err(|_| {
                            format!("invalid layout field size {}.{name}", layout.name)
                        })?;
                        if offset.checked_add(bytes).is_none_or(|end| end > size)
                            || fields
                                .insert(name.clone(), Field { offset, bytes })
                                .is_some()
                        {
                            return Err(format!("invalid layout field {}.{name}", layout.name));
                        }
                    }
                    if layouts
                        .insert(layout.name.clone(), Layout { size, fields })
                        .is_some()
                    {
                        return Err(format!("duplicate layout {}", layout.name));
                    }
                }
                let call = instance
                    .get_typed_func::<(i32, i32), ()>(&mut store, &entry.call)
                    .map_err(|error| format!("missing bridge {}: {error}", entry.call))?;
                if entries
                    .insert(
                        entry.symbol.clone(),
                        Entry {
                            record: entry,
                            call,
                            layouts,
                        },
                    )
                    .is_some()
                {
                    return Err(format!("duplicate Wasm symbol in {name}"));
                }
            }
            units.insert(
                name,
                Unit {
                    memory,
                    malloc,
                    free,
                    entries,
                },
            );
        }
        if units.is_empty() {
            return Err("units manifest contains no independent Wasm kernels".into());
        }
        Ok(Self {
            store,
            units,
            error: CString::default(),
        })
    }

    fn call(
        &mut self,
        unit_name: &str,
        symbol: &str,
        arguments: &mut [u8],
        results: &mut [u8],
        spans: &mut [HostSpan],
    ) -> Result<(), String> {
        let unit = self
            .units
            .get(unit_name)
            .ok_or_else(|| format!("unknown Wasm unit {unit_name}"))?;
        let entry = unit
            .entries
            .get(symbol)
            .ok_or_else(|| format!("unknown Wasm entry {unit_name}.{symbol}"))?
            .clone();
        let span_params: Vec<(usize, &ParamRecord)> = entry
            .record
            .params
            .iter()
            .enumerate()
            .filter(|(_, param)| param.kind.ends_with("_span"))
            .collect();
        let count_count = if entry.record.independent_counts {
            span_params.len()
        } else {
            1
        };
        let expected_arguments = (entry.record.params.len() + count_count) * 8;
        let expected_results = entry.record.results.len() * 8;
        if arguments.len() != expected_arguments
            || results.len() != expected_results
            || spans.len() != span_params.len()
        {
            return Err(format!("bridge extent mismatch for {unit_name}.{symbol}"));
        }

        let mut allocated = Vec::new();
        let answer = (|| {
            let args_pointer = allocate(unit, &mut self.store, arguments.len())?;
            allocated.push(args_pointer);
            let result_pointer = allocate(unit, &mut self.store, results.len())?;
            allocated.push(result_pointer);
            unit.memory
                .write(&mut self.store, args_pointer as usize, arguments)
                .map_err(|error| format!("cannot write Wasm arguments: {error}"))?;

            let mut wasm_spans = Vec::new();
            let mut transferred = 0usize;
            for (span_index, ((param_index, param), span)) in
                span_params.iter().zip(spans.iter()).enumerate()
            {
                let layout_name = param.value_type.strip_prefix("struct:");
                let layout = layout_name.and_then(|name| entry.layouts.get(name));
                if layout_name.is_some() && layout.is_none() {
                    return Err(format!("unknown Wasm span layout {}", param.value_type));
                }
                let target_stride = if let Some(layout) = layout {
                    layout.size
                } else {
                    scalar_bytes(param)
                        .ok_or_else(|| format!("unknown scalar span type {}", param.value_type))?
                };
                let count_slot = entry.record.params.len()
                    + if entry.record.independent_counts {
                        span_index
                    } else {
                        0
                    };
                let count = u32::from_le_bytes(
                    arguments[count_slot * 8..count_slot * 8 + 4]
                        .try_into()
                        .expect("validated argument slot"),
                ) as usize;
                if span.count != count
                    || span.count.checked_mul(span.stride) != Some(span.bytes)
                    || span.bytes > TRANSFER_LIMIT
                    || span.writable > 1
                    || span.data.is_null()
                {
                    return Err(format!(
                        "invalid scalar span for parameter {}",
                        param_index + 1
                    ));
                }
                transferred = transferred
                    .checked_add(span.bytes)
                    .ok_or_else(|| "Wasm span transfer overflowed".to_string())?;
                if transferred > TRANSFER_LIMIT {
                    return Err("Wasm span transfer exceeds two MiB".into());
                }
                if count
                    .checked_mul(target_stride.max(span.stride))
                    .is_none_or(|bytes| bytes > TRANSFER_LIMIT)
                {
                    return Err("Wasm span exceeds the transfer budget".into());
                }
                let mappings = if let Some(layout) = layout {
                    if span.fields_len > 256 || (span.fields_len > 0 && span.fields.is_null()) {
                        return Err("invalid guest struct fields".into());
                    }
                    // SAFETY: The caller owns this field array for the synchronous call.
                    let supplied = if span.fields_len == 0 {
                        &[]
                    } else {
                        unsafe { slice::from_raw_parts(span.fields, span.fields_len) }
                    };
                    let mut by_name = HashMap::new();
                    for field in supplied {
                        let name = c_string(field.name, "guest field name")?;
                        if field
                            .offset
                            .checked_add(field.bytes)
                            .is_none_or(|end| end > span.stride)
                            || by_name.insert(name.clone(), field).is_some()
                        {
                            return Err(format!("invalid guest struct field {name}"));
                        }
                    }
                    let mut mappings = Vec::new();
                    for (name, target) in &layout.fields {
                        let source = by_name
                            .get(name)
                            .ok_or_else(|| format!("missing guest struct field {name}"))?;
                        if source.bytes != target.bytes {
                            return Err(format!("Wasm span field size mismatch for {name}"));
                        }
                        mappings.push((source.offset, target.offset, target.bytes));
                    }
                    mappings
                } else {
                    if span.stride != target_stride || span.fields_len != 0 {
                        return Err("Wasm scalar span layout mismatch".into());
                    }
                    vec![(0, 0, target_stride)]
                };
                let target_bytes = count * target_stride;
                let pointer = allocate(unit, &mut self.store, target_bytes)?;
                allocated.push(pointer);
                // SAFETY: The FFI caller guarantees `data` covers `bytes` for this call.
                let source = if span.bytes == 0 {
                    &[]
                } else {
                    unsafe { slice::from_raw_parts(span.data, span.bytes) }
                };
                let mut target = vec![0; target_bytes];
                for row in 0..count {
                    for &(source_offset, target_offset, bytes) in &mappings {
                        target[row * target_stride + target_offset
                            ..row * target_stride + target_offset + bytes]
                            .copy_from_slice(
                                &source[row * span.stride + source_offset
                                    ..row * span.stride + source_offset + bytes],
                            );
                    }
                }
                unit.memory
                    .write(&mut self.store, pointer as usize, &target)
                    .map_err(|error| format!("cannot write Wasm span: {error}"))?;
                arguments[*param_index * 8..*param_index * 8 + 4]
                    .copy_from_slice(&(pointer as u32).to_le_bytes());
                wasm_spans.push((pointer, span, target_stride, mappings));
            }
            unit.memory
                .write(&mut self.store, args_pointer as usize, arguments)
                .map_err(|error| format!("cannot write Wasm bridge arguments: {error}"))?;
            entry
                .call
                .call(&mut self.store, (args_pointer, result_pointer))
                .map_err(|error| format!("Wasm bridge trapped: {error}"))?;
            unit.memory
                .read(&self.store, result_pointer as usize, results)
                .map_err(|error| format!("cannot read Wasm results: {error}"))?;
            for (pointer, span, target_stride, mappings) in wasm_spans {
                if span.writable == 1 {
                    // SAFETY: The FFI caller guarantees writable `data` covers `bytes`.
                    let target = if span.bytes == 0 {
                        &mut []
                    } else {
                        unsafe { slice::from_raw_parts_mut(span.data, span.bytes) }
                    };
                    let mut source = vec![0; span.count * target_stride];
                    unit.memory
                        .read(&self.store, pointer as usize, &mut source)
                        .map_err(|error| format!("cannot read Wasm span: {error}"))?;
                    for row in 0..span.count {
                        for &(target_offset, source_offset, bytes) in &mappings {
                            target[row * span.stride + target_offset
                                ..row * span.stride + target_offset + bytes]
                                .copy_from_slice(
                                    &source[row * target_stride + source_offset
                                        ..row * target_stride + source_offset + bytes],
                                );
                        }
                    }
                }
            }
            Ok(())
        })();
        for pointer in allocated.into_iter().rev() {
            if let Err(error) = unit.free.call(&mut self.store, pointer) {
                if answer.is_ok() {
                    return Err(format!("Wasm free failed: {error}"));
                }
            }
        }
        answer
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn nupp_wasmtime_host_open(
    manifest_path: *const c_char,
    module_root: *const c_char,
) -> *mut Host {
    let answer = std::panic::catch_unwind(|| {
        let manifest = c_string(manifest_path, "manifest path")?;
        let root = c_string(module_root, "module root")?;
        Host::open(Path::new(&manifest), Path::new(&root))
    });
    match answer {
        Ok(Ok(host)) => Box::into_raw(Box::new(host)),
        Ok(Err(error)) => {
            OPEN_ERROR.with(|slot| *slot.borrow_mut() = message(error));
            ptr::null_mut()
        }
        Err(_) => {
            OPEN_ERROR
                .with(|slot| *slot.borrow_mut() = message("Wasmtime host panicked while opening"));
            ptr::null_mut()
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn nupp_wasmtime_host_call(
    host: *mut Host,
    unit: *const c_char,
    symbol: *const c_char,
    arguments: *mut u8,
    arguments_len: usize,
    results: *mut u8,
    results_len: usize,
    spans: *mut HostSpan,
    spans_len: usize,
) -> i32 {
    if host.is_null()
        || arguments.is_null()
        || (results_len > 0 && results.is_null())
        || (spans_len > 0 && spans.is_null())
    {
        return 0;
    }
    // SAFETY: The caller owns the host and buffers for the duration of this call.
    let host = unsafe { &mut *host };
    let answer = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let unit = c_string(unit, "unit")?;
        let symbol = c_string(symbol, "symbol")?;
        // SAFETY: Extents are validated by the ABI caller and remain borrowed synchronously.
        let arguments = unsafe { slice::from_raw_parts_mut(arguments, arguments_len) };
        let results = if results_len == 0 {
            &mut []
        } else {
            // SAFETY: Non-null was checked above.
            unsafe { slice::from_raw_parts_mut(results, results_len) }
        };
        let spans = if spans_len == 0 {
            &mut []
        } else {
            // SAFETY: Non-null was checked above.
            unsafe { slice::from_raw_parts_mut(spans, spans_len) }
        };
        host.call(&unit, &symbol, arguments, results, spans)
    }));
    match answer {
        Ok(Ok(())) => 1,
        Ok(Err(error)) => {
            host.error = message(error);
            0
        }
        Err(_) => {
            host.error = message("Wasmtime host panicked during a kernel call");
            0
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn nupp_wasmtime_host_error(host: *mut Host) -> *const c_char {
    if host.is_null() {
        return OPEN_ERROR.with(|slot| slot.borrow().as_ptr());
    }
    // SAFETY: A non-null handle came from `nupp_wasmtime_host_open`.
    unsafe { (*host).error.as_ptr() }
}

#[unsafe(no_mangle)]
pub extern "C" fn nupp_wasmtime_host_close(host: *mut Host) {
    if !host.is_null() {
        // SAFETY: Each successful open handle is closed exactly once by the Lua owner.
        unsafe { drop(Box::from_raw(host)) };
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn nupp_wasmtime_host_abi() -> u32 {
    1
}
