//! The AOT code generator's C ABI: LLVM IR text in, objects and linked
//! artifacts out. Results are byte handles the caller copies and releases.

use nupp_native_abi::Status;
use nupp_native_codegen as codegen;

fn text<'a>(data: *const u8, length: usize, what: &str) -> Result<&'a str, i32> {
    let bytes = super::input(data, length)?;
    std::str::from_utf8(bytes).map_err(|_| super::failed(Status::InvalidArgument, &format!("{what} is not UTF-8")))
}

fn output(slot: *mut u64, value: Option<Vec<u8>>) -> Result<(), i32> {
    if slot.is_null() {
        return Ok(());
    }
    let handle = match value {
        Some(bytes) => super::store_bytes(bytes)?,
        None => 0,
    };
    // SAFETY: a non-null slot is writable storage for one u64 by contract.
    unsafe { slot.write(handle) };
    Ok(())
}

fn status(result: Result<(), i32>) -> i32 {
    match result {
        Ok(()) => Status::Ok.code(),
        Err(code) => code,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppCodegenAvailable() -> u32 {
    codegen::available() as u32
}

#[unsafe(no_mangle)]
/// # Safety
/// `output` must be writable storage for one u64.
pub unsafe extern "C" fn nuppCodegenVersion(result: *mut u64) -> i32 {
    status(output(result, Some(codegen::version().into_bytes())))
}

#[unsafe(no_mangle)]
/// Compiles one LLVM IR module. `options` is `key=value` lines (see
/// `CompileOptions::parse`). Each non-null output slot receives a byte handle,
/// or 0 when that output was not asked for.
///
/// # Safety
/// Each input range must be readable for its length; each non-null output
/// must be writable storage for one u64.
pub unsafe extern "C" fn nuppCodegenCompile(
    ir: *const u8,
    ir_length: usize,
    name: *const u8,
    name_length: usize,
    options: *const u8,
    options_length: usize,
    object: *mut u64,
    report: *mut u64,
    assembly: *mut u64,
    optimized_ir: *mut u64,
) -> i32 {
    status((|| {
        let ir = text(ir, ir_length, "LLVM IR")?;
        let name = text(name, name_length, "module name")?;
        let options = codegen::CompileOptions::parse(text(options, options_length, "codegen options")?)
            .map_err(|e| super::failed(Status::InvalidArgument, &e))?;
        let compiled = codegen::compile(ir, name, &options).map_err(|e| super::failed(Status::InvalidArgument, &e))?;
        let report_text = compiled.report();
        output(object, Some(compiled.object))?;
        output(report, Some(report_text.into_bytes()))?;
        output(assembly, compiled.assembly.map(String::into_bytes))?;
        output(optimized_ir, compiled.optimized_ir.map(String::into_bytes))
    })())
}

#[unsafe(no_mangle)]
/// Runs lld in process over NUL-separated arguments (argv[0] picks the
/// flavor). `messages` receives lld's output on success.
///
/// # Safety
/// `argv` must be readable for `length` bytes; `messages` null or writable.
pub unsafe extern "C" fn nuppCodegenLink(argv: *const u8, length: usize, messages: *mut u64) -> i32 {
    status((|| {
        let argv: Vec<String> = text(argv, length, "linker arguments")?
            .split('\0')
            .filter(|a| !a.is_empty())
            .map(str::to_string)
            .collect();
        let out = codegen::link(&argv).map_err(|e| super::failed(Status::InvalidArgument, &e))?;
        output(messages, Some(out.into_bytes()))
    })())
}

#[unsafe(no_mangle)]
/// Writes a MinGW import library. `names` is NUL-separated entries, each
/// `name` or `name\texport`.
///
/// # Safety
/// Each input range must be readable for its length.
pub unsafe extern "C" fn nuppCodegenImportLibrary(
    dll: *const u8,
    dll_length: usize,
    path: *const u8,
    path_length: usize,
    names: *const u8,
    names_length: usize,
) -> i32 {
    status((|| {
        let dll = text(dll, dll_length, "DLL name")?;
        let path = text(path, path_length, "import library path")?;
        let names: Vec<(String, String)> = text(names, names_length, "import names")?
            .split('\0')
            .filter(|n| !n.is_empty())
            .map(|n| match n.split_once('\t') {
                Some((name, export)) => (name.to_string(), export.to_string()),
                None => (n.to_string(), String::new()),
            })
            .collect();
        codegen::import_library(dll, path, &names).map_err(|e| super::failed(Status::InvalidArgument, &e))
    })())
}

#[unsafe(no_mangle)]
/// Writes a static archive. `members` is NUL-separated object paths; `kind`
/// is 0 GNU, 1 BSD, 2 Darwin, 3 COFF.
///
/// # Safety
/// Each input range must be readable for its length.
pub unsafe extern "C" fn nuppCodegenArchive(
    path: *const u8,
    path_length: usize,
    members: *const u8,
    members_length: usize,
    kind: i32,
) -> i32 {
    status((|| {
        let path = text(path, path_length, "archive path")?;
        let members: Vec<String> = text(members, members_length, "archive members")?
            .split('\0')
            .filter(|m| !m.is_empty())
            .map(str::to_string)
            .collect();
        codegen::archive(path, &members, kind).map_err(|e| super::failed(Status::InvalidArgument, &e))
    })())
}

#[unsafe(no_mangle)]
/// Compiles IR files to objects, `width` at a time, each isolated from this
/// process where the platform can fork. `jobs` is NUL-separated records of
/// `irPath \x1f objectPath \x1f options`; `results` receives one record per
/// job, in order, of `ok \x1f report` or `error \x1f message`, NUL-separated.
///
/// # Safety
/// `jobs` must be readable for `length` bytes; `results` writable for one u64.
pub unsafe extern "C" fn nuppCodegenCompileFiles(jobs: *const u8, length: usize, width: u32, results: *mut u64) -> i32 {
    status((|| {
        let mut parsed = Vec::new();
        for record in text(jobs, length, "compile jobs")?.split('\0').filter(|r| !r.is_empty()) {
            let mut fields = record.splitn(3, '\u{1f}');
            let (Some(ir), Some(object), Some(options)) = (fields.next(), fields.next(), fields.next()) else {
                return Err(super::failed(Status::InvalidArgument, "a compile job needs an IR path, an object path and options"));
            };
            let options = codegen::CompileOptions::parse(options).map_err(|e| super::failed(Status::InvalidArgument, &e))?;
            parsed.push(codegen::Job { ir: ir.into(), object: object.into(), options });
        }
        let answers = codegen::compile_files(&parsed, width as usize);
        let mut out = String::new();
        for answer in answers {
            match answer {
                Ok(report) => out.push_str(&format!("ok\u{1f}{report}")),
                Err(error) => out.push_str(&format!("error\u{1f}{error}")),
            }
            out.push('\0');
        }
        output(results, Some(out.into_bytes()))
    })())
}
