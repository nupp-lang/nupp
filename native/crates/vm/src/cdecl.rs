//! Optional compiler-host service over libclang's stable C declaration API.
//! It parses in memory and never starts a compiler or executes C declarations.
//! ABI definitions: https://clang.llvm.org/doxygen/group__CINDEX.html
use libloading::Library;
use serde_json::{Value as Json, json};
use std::{
    collections::HashMap,
    ffi::{CStr, CString, c_char, c_int, c_uint, c_ulong, c_void},
};

type Handle = *mut c_void;
#[repr(C)]
#[derive(Clone, Copy)]
struct Type {
    kind: c_uint,
    data: [Handle; 2],
}
#[repr(C)]
#[derive(Clone, Copy)]
struct Cursor {
    kind: c_uint,
    xdata: c_int,
    data: [*const c_void; 3],
}
#[repr(C)]
struct Text {
    data: *const c_void,
    flags: c_uint,
}
#[repr(C)]
struct Unsaved {
    filename: *const c_char,
    contents: *const c_char,
    length: c_ulong,
}
type Visitor = unsafe extern "C" fn(Cursor, Cursor, Handle) -> c_uint;

macro_rules! api {
    ($($name:ident($($arg:ty),*) -> $ret:ty;)*) => {
        #[allow(non_snake_case)]
        struct Api { _library: Library, $($name: unsafe extern "C" fn($($arg),*) -> $ret,)* }
        impl Api {
            #[allow(non_snake_case)]
            unsafe fn from_library(library: Library) -> Result<Self, String> {
                $(let $name = *unsafe { library.get::<unsafe extern "C" fn($($arg),*) -> $ret>(concat!(stringify!($name), "\0").as_bytes()) }.map_err(|e| e.to_string())?;)*
                Ok(Self { _library: library, $($name,)* })
            }
        }
    }
}
api! {
    clang_getClangVersion() -> Text;
    clang_createIndex(c_int, c_int) -> Handle;
    clang_disposeIndex(Handle) -> ();
    clang_parseTranslationUnit(Handle, *const c_char, *const *const c_char, c_int, *mut Unsaved, c_uint, c_uint) -> Handle;
    clang_disposeTranslationUnit(Handle) -> ();
    clang_getTranslationUnitCursor(Handle) -> Cursor;
    clang_visitChildren(Cursor, Visitor, Handle) -> c_uint;
    clang_getCursorSpelling(Cursor) -> Text;
    clang_getCursorUSR(Cursor) -> Text;
    clang_getCString(Text) -> *const c_char;
    clang_disposeString(Text) -> ();
    clang_getCursorType(Cursor) -> Type;
    clang_getCanonicalType(Type) -> Type;
    clang_getTypedefDeclUnderlyingType(Cursor) -> Type;
    clang_getTypeDeclaration(Type) -> Cursor;
    clang_getTypeSpelling(Type) -> Text;
    clang_getPointeeType(Type) -> Type;
    clang_isConstQualifiedType(Type) -> c_uint;
    clang_Type_getSizeOf(Type) -> i64;
    clang_Type_getAlignOf(Type) -> i64;
    clang_Cursor_getOffsetOfField(Cursor) -> i64;
    clang_Cursor_isBitField(Cursor) -> c_uint;
    clang_getFieldDeclBitWidth(Cursor) -> c_int;
    clang_getArrayElementType(Type) -> Type;
    clang_getArraySize(Type) -> i64;
    clang_getElementType(Type) -> Type;
    clang_getNumElements(Type) -> i64;
    clang_getNumArgTypes(Type) -> c_int;
    clang_getArgType(Type, c_uint) -> Type;
    clang_getResultType(Type) -> Type;
    clang_isFunctionTypeVariadic(Type) -> c_uint;
    clang_getEnumDeclIntegerType(Cursor) -> Type;
    clang_getEnumConstantDeclValue(Cursor) -> i64;
    clang_getNumDiagnostics(Handle) -> c_uint;
    clang_getDiagnostic(Handle, c_uint) -> Handle;
    clang_getDiagnosticSeverity(Handle) -> c_uint;
    clang_getDiagnosticSpelling(Handle) -> Text;
    clang_disposeDiagnostic(Handle) -> ();
}
impl Api {
    fn load() -> Result<Self, String> {
        let mut candidates = Vec::new();
        if let Some(path) = std::env::var_os("NUPP_LIBCLANG") {
            candidates.push(path);
        } else {
            #[cfg(target_os = "macos")]
            candidates.extend(["/Library/Developer/CommandLineTools/usr/lib/libclang.dylib", "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/libclang.dylib", "libclang.dylib"].map(Into::into));
            #[cfg(target_os = "windows")]
            candidates.push("libclang.dll".into());
            #[cfg(not(any(target_os = "macos", target_os = "windows")))]
            candidates.extend(
                [
                    "libclang.so",
                    "libclang.so.1",
                    "libclang-20.so.1",
                    "libclang-19.so.1",
                    "libclang-18.so.1",
                ]
                .map(Into::into),
            );
        }
        let mut errors = Vec::new();
        for path in candidates {
            match unsafe {
                Library::new(&path)
                    .map_err(|e| e.to_string())
                    .and_then(|lib| Self::from_library(lib))
            } {
                Ok(api) => return Ok(api),
                Err(error) => errors.push(error),
            }
        }
        Err(format!(
            "C declaration service requires libclang; set NUPP_LIBCLANG to its library path: {}",
            errors.join("; ")
        ))
    }
    unsafe fn text(&self, text: Text) -> String {
        let value = (self.clang_getCString)(Text {
            data: text.data,
            flags: text.flags,
        });
        let result = if value.is_null() {
            String::new()
        } else {
            CStr::from_ptr(value).to_string_lossy().into_owned()
        };
        (self.clang_disposeString)(text);
        result
    }
    unsafe fn children(&self, cursor: Cursor) -> Vec<Cursor> {
        unsafe extern "C" fn collect(cursor: Cursor, _: Cursor, data: Handle) -> c_uint {
            (*(data as *mut Vec<Cursor>)).push(cursor);
            1 // CXChildVisit_Continue
        }
        let mut children = Vec::new();
        (self.clang_visitChildren)(cursor, collect, &mut children as *mut _ as Handle);
        children
    }
}

struct Unit<'a> {
    api: &'a Api,
    index: Handle,
    unit: Handle,
}
impl Drop for Unit<'_> {
    fn drop(&mut self) {
        unsafe {
            (self.api.clang_disposeTranslationUnit)(self.unit);
            (self.api.clang_disposeIndex)(self.index);
        }
    }
}
impl Api {
    fn parse(&self, source: &str) -> Result<Unit<'_>, String> {
        self.parse_probe(source, "", 0)
    }
    fn parse_probe(&self, source: &str, probe: &str, identity: u64) -> Result<Unit<'_>, String> {
        let contents = CString::new(source).map_err(|_| "C declarations contain a NUL byte")?;
        let directory = std::env::current_dir().map_err(|error| error.to_string())?;
        let filename = CString::new(
            directory
                .join(format!("nupp-probe-{identity}.c"))
                .to_string_lossy()
                .as_bytes(),
        )
        .unwrap();
        let header = CString::new(
            directory
                .join("nupp-declarations.h")
                .to_string_lossy()
                .as_bytes(),
        )
        .unwrap();
        let main = CString::new(format!("#include \"nupp-declarations.h\"\n{probe}\n"))
            .map_err(|_| "C type contains a NUL byte")?;
        let arguments = [
            c"-x".as_ptr(),
            c"c".as_ptr(),
            c"-std=gnu11".as_ptr(),
            c"-fno-builtin".as_ptr(),
            c"-Wno-everything".as_ptr(),
        ];
        // Declaration locations stay in one virtual header. Anonymous probe types
        // live in distinct virtual files, so libclang's cursor identities cannot
        // alias two different layouts at the same byte offset.
        let mut files = [
            Unsaved {
                filename: header.as_ptr(),
                contents: contents.as_ptr(),
                length: source.len() as c_ulong,
            },
            Unsaved {
                filename: filename.as_ptr(),
                contents: main.as_ptr(),
                length: main.as_bytes().len() as c_ulong,
            },
        ];
        unsafe {
            let index = (self.clang_createIndex)(0, 0);
            let unit = (self.clang_parseTranslationUnit)(
                index,
                filename.as_ptr(),
                arguments.as_ptr(),
                arguments.len() as c_int,
                files.as_mut_ptr(),
                files.len() as c_uint,
                0,
            );
            if unit.is_null() {
                (self.clang_disposeIndex)(index);
                return Err("libclang could not parse C declarations".into());
            }
            let unit = Unit {
                api: self,
                index,
                unit,
            };
            let mut errors = Vec::new();
            for i in 0..(self.clang_getNumDiagnostics)(unit.unit) {
                let diagnostic = (self.clang_getDiagnostic)(unit.unit, i);
                if (self.clang_getDiagnosticSeverity)(diagnostic) >= 3 {
                    errors.push(self.text((self.clang_getDiagnosticSpelling)(diagnostic)));
                }
                (self.clang_disposeDiagnostic)(diagnostic);
            }
            if !errors.is_empty() {
                return Err(errors.join("; "));
            }
            Ok(unit)
        }
    }
}

// Match the standard C names accepted by the old compiler's declaration service.
// Widths and layout come from libclang's target, including long and size_t.
const PRELUDE: &str = "typedef _Bool bool; typedef __SIZE_TYPE__ size_t; typedef __PTRDIFF_TYPE__ ptrdiff_t; typedef __INTPTR_TYPE__ intptr_t; typedef __UINTPTR_TYPE__ uintptr_t; typedef __INT8_TYPE__ int8_t; typedef __UINT8_TYPE__ uint8_t; typedef __INT16_TYPE__ int16_t; typedef __UINT16_TYPE__ uint16_t; typedef __INT32_TYPE__ int32_t; typedef __UINT32_TYPE__ uint32_t; typedef __INT64_TYPE__ int64_t; typedef __UINT64_TYPE__ uint64_t;\n";

#[derive(Clone, Default)]
struct Model {
    ids: HashMap<String, u64>,
    structs: HashMap<u64, Json>,
}
impl Model {
    unsafe fn id(&mut self, api: &Api, cursor: Cursor) -> u64 {
        let key = api.text((api.clang_getCursorUSR)(cursor));
        let next = self.ids.len() as u64 + 1;
        *self.ids.entry(key).or_insert(next)
    }
    unsafe fn ty(&mut self, api: &Api, ty: Type, depth: u32) -> Result<Json, String> {
        if depth > 100 {
            return Err("C type nesting exceeds 100".into());
        }
        let ty = (api.clang_getCanonicalType)(ty);
        let size = (api.clang_Type_getSizeOf)(ty);
        let align = (api.clang_Type_getAlignOf)(ty);
        let mut value = match ty.kind {
            2 => json!({"kind":"void"}),
            3 => json!({"kind":"boolean"}),
            4..=20 => json!({"kind":"integer","bits":size * 8,"unsigned":ty.kind <= 12}),
            21..=23 | 30..=32 | 39 => json!({"kind":"float","bits":size * 8}),
            101 => {
                let pointee = (api.clang_getPointeeType)(ty);
                json!({"kind":"pointer", "to":self.ty(api,pointee,depth+1)?, "const":(api.clang_isConstQualifiedType)(pointee) != 0})
            }
            105 => {
                let cursor = (api.clang_getTypeDeclaration)(ty);
                let id = self.id(api, cursor);
                let name = api.text((api.clang_getCursorSpelling)(cursor));
                let kind = if cursor.kind == 3 { "union" } else { "struct" };
                // Register before members so recursive pointers terminate.
                if !self.structs.contains_key(&id)
                    || self.structs[&id].get("size").is_none() && size >= 0
                {
                    let mut placeholder = json!({"kind":kind,"id":id,"name":name,"fields":[]});
                    if size >= 0 {
                        placeholder["size"] = json!(size);
                    }
                    self.structs.insert(id, placeholder);
                    let mut fields = Vec::new();
                    let mut anonymous = 0;
                    let mut unnamed = 0;
                    for field in api.children(cursor) {
                        if field.kind != 6 {
                            continue;
                        } // CXCursor_FieldDecl
                        let name = api.text((api.clang_getCursorSpelling)(field));
                        if name.is_empty() {
                            if (api.clang_Cursor_isBitField)(field) != 0 {
                                unnamed += 1;
                            } else {
                                anonymous += 1;
                            }
                            continue;
                        }
                        let offset = (api.clang_Cursor_getOffsetOfField)(field);
                        let field_type =
                            self.ty(api, (api.clang_getCursorType)(field), depth + 1)?;
                        let mut data = json!({"name":name,"type":field_type});
                        if offset >= 0 {
                            data["offset"] = json!(offset / 8);
                        }
                        if (api.clang_Cursor_isBitField)(field) != 0 {
                            data["bitWidth"] = json!((api.clang_getFieldDeclBitWidth)(field));
                            data["bitPos"] = json!(offset % 8);
                        }
                        fields.push(data);
                    }
                    let mut declaration = json!({"kind":kind,"id":id,"name":name,"fields":fields,"anonymous":anonymous,"unnamed":unnamed});
                    if size >= 0 {
                        declaration["size"] = json!(size);
                    }
                    if align >= 0 {
                        declaration["align"] = json!(align);
                    }
                    self.structs.insert(id, declaration);
                }
                let name = if name.is_empty() {
                    self.structs[&id]["name"].as_str().unwrap_or("").to_owned()
                } else {
                    name
                };
                json!({"kind":kind,"id":id,"name":name})
            }
            106 => {
                let cursor = (api.clang_getTypeDeclaration)(ty);
                let integer =
                    self.ty(api, (api.clang_getEnumDeclIntegerType)(cursor), depth + 1)?;
                json!({"kind":"enum","id":self.id(api,cursor),"name":api.text((api.clang_getCursorSpelling)(cursor)),"bits":integer["bits"],"unsigned":integer["unsigned"]})
            }
            110 | 111 => {
                let mut params = Vec::new();
                for i in 0..(api.clang_getNumArgTypes)(ty).max(0) {
                    params.push(
                        json!({"type":self.ty(api,(api.clang_getArgType)(ty,i as u32),depth+1)?}),
                    );
                }
                json!({"kind":"function","params":params,"returns":self.ty(api,(api.clang_getResultType)(ty),depth+1)?,"vararg":(api.clang_isFunctionTypeVariadic)(ty)!=0})
            }
            112 | 114 | 115 | 116 => {
                let count = (api.clang_getArraySize)(ty);
                let mut array = json!({"kind":"array","of":self.ty(api,(api.clang_getArrayElementType)(ty),depth+1)?});
                if count >= 0 {
                    array["count"] = json!(count);
                }
                if size >= 0 {
                    array["bytes"] = json!(size);
                }
                array
            }
            100 | 113 | 176 => {
                json!({"kind":if ty.kind==100 {"complex"} else {"vector"},"of":self.ty(api,(api.clang_getElementType)(ty),depth+1)?,"count":(api.clang_getNumElements)(ty)})
            }
            _ => {
                return Err(format!(
                    "unsupported C type {}",
                    api.text((api.clang_getTypeSpelling)(ty))
                ));
            }
        };
        if size >= 0 {
            value["size"] = json!(size);
        }
        if align >= 0 {
            value["align"] = json!(align);
        }
        Ok(value)
    }
}

pub struct Registry {
    api: Api,
    declarations: String,
    blocks: HashMap<String, Json>,
    types: HashMap<String, Json>,
    functions: HashMap<String, Json>,
    model: Model,
    next_probe: u64,
}
impl Registry {
    pub fn new() -> Result<Self, String> {
        Ok(Self {
            api: Api::load()?,
            declarations: PRELUDE.into(),
            blocks: HashMap::new(),
            types: HashMap::new(),
            functions: HashMap::new(),
            model: Model::default(),
            next_probe: 1,
        })
    }
    fn declare(&mut self, text: &str) -> Result<Json, String> {
        if let Some(hit) = self.blocks.get(text) {
            return Ok(hit.clone());
        }
        let source = format!("{}\n{text}\n", self.declarations);
        let unit = self.api.parse(&source)?;
        let mut names = serde_json::Map::new();
        let mut model = self.model.clone();
        let mut functions = self.functions.clone();
        unsafe {
            for cursor in self
                .api
                .children((self.api.clang_getTranslationUnitCursor)(unit.unit))
            {
                if cursor.kind == 8 {
                    // CXCursor_FunctionDecl
                    let name = self.api.text((self.api.clang_getCursorSpelling)(cursor));
                    let mut function =
                        model.ty(&self.api, (self.api.clang_getCursorType)(cursor), 0)?;
                    function["name"] = json!(name);
                    functions.insert(name.clone(), function);
                    // Token membership claims repeated declarations, as the old service does.
                    if text
                        .split(|c: char| !c.is_ascii_alphanumeric() && c != '_')
                        .any(|word| word == name)
                    {
                        names.insert(name, json!(true));
                    }
                } else if matches!(cursor.kind, 2 | 3 | 5 | 20) {
                    let ty = if cursor.kind == 20 {
                        (self.api.clang_getTypedefDeclUnderlyingType)(cursor)
                    } else {
                        (self.api.clang_getCursorType)(cursor)
                    };
                    let value = model.ty(&self.api, ty, 0)?;
                    if cursor.kind == 20
                        && matches!(value["kind"].as_str(), Some("struct" | "union"))
                    {
                        let declaration = model
                            .structs
                            .get_mut(&value["id"].as_u64().unwrap())
                            .unwrap();
                        if declaration["name"].as_str() == Some("") {
                            declaration["name"] =
                                json!(self.api.text((self.api.clang_getCursorSpelling)(cursor)));
                            declaration["typedefName"] = json!(true);
                        }
                    }
                }
            }
        }
        let names = Json::Object(names);
        self.model = model;
        self.functions = functions;
        self.declarations = source;
        self.types.clear();
        self.blocks.insert(text.into(), names.clone());
        Ok(names)
    }
    fn type_from_string(&mut self, spec: &str) -> Result<Json, String> {
        if let Some(hit) = self.types.get(spec) {
            return Ok(hit.clone());
        }
        // [?] is the legacy FFI's variable array notation; an incomplete C array
        // has the same declaration model (element known, extent absent).
        let spec_c = spec.replace("[?]", "[]");
        let source = format!("typedef __typeof__({spec_c}) __nupp_probe;");
        let identity = self.next_probe;
        self.next_probe += 1;
        let unit = self
            .api
            .parse_probe(&self.declarations, &source, identity)?;
        unsafe {
            for cursor in self
                .api
                .children((self.api.clang_getTranslationUnitCursor)(unit.unit))
            {
                if cursor.kind == 20
                    && self.api.text((self.api.clang_getCursorSpelling)(cursor)) == "__nupp_probe"
                {
                    let value = self.model.ty(
                        &self.api,
                        (self.api.clang_getTypedefDeclUnderlyingType)(cursor),
                        0,
                    )?;
                    self.types.insert(spec.into(), value.clone());
                    return Ok(value);
                }
            }
        }
        Err(format!("not a C type: {spec}"))
    }
    fn inspect(&mut self, input: &Json) -> Result<Json, String> {
        fn units(value: &Json) -> Vec<String> {
            if let Some(text) = value.as_str() {
                vec![text.into()]
            } else {
                value
                    .as_array()
                    .map(|items| {
                        items
                            .iter()
                            .filter_map(|item| item.as_str().map(String::from))
                            .collect()
                    })
                    .unwrap_or_default()
            }
        }
        for prelude in units(&input["prelude"]) {
            let _ = self.declare(&prelude);
        }
        let units = units(&input["text"]);
        let partial = input["text"].is_array();
        let mut rejected = Vec::new();
        let mut structures = Vec::new();
        let mut functions = Vec::new();
        let mut enums = Vec::new();
        for (index, text) in units.iter().enumerate() {
            if let Err(error) = self.declare(text) {
                if !partial {
                    return Err(error);
                }
                rejected.push(json!({"text":text,"reason":error,"unit":index+1}));
                continue;
            }
            let mentioned = |name: &str| {
                !name.is_empty()
                    && text
                        .split(|c: char| !c.is_ascii_alphanumeric() && c != '_')
                        .any(|word| word == name)
            };
            for declaration in self.model.structs.values() {
                if declaration["name"].as_str().is_some_and(&mentioned) {
                    let mut declaration = declaration.clone();
                    declaration["unit"] = json!(index + 1);
                    structures.push(declaration);
                }
            }
            for (name, declaration) in &self.functions {
                if mentioned(name) {
                    let mut declaration = declaration.clone();
                    declaration["unit"] = json!(index + 1);
                    functions.push(declaration);
                }
            }
            let unit = self.api.parse(&self.declarations)?;
            unsafe {
                for cursor in self
                    .api
                    .children((self.api.clang_getTranslationUnitCursor)(unit.unit))
                {
                    if cursor.kind != 5 {
                        continue;
                    }
                    let name = self.api.text((self.api.clang_getCursorSpelling)(cursor));
                    let mut values = Vec::new();
                    for child in self.api.children(cursor) {
                        if child.kind == 7 {
                            values.push(json!({"name":self.api.text((self.api.clang_getCursorSpelling)(child)),"value":(self.api.clang_getEnumConstantDeclValue)(child)}));
                        }
                    }
                    if mentioned(&name)
                        || values
                            .iter()
                            .any(|value| mentioned(value["name"].as_str().unwrap_or("")))
                    {
                        let mut value =
                            self.model
                                .ty(&self.api, (self.api.clang_getCursorType)(cursor), 0)?;
                        value["values"] = json!(values);
                        value["unit"] = json!(index + 1);
                        enums.push(value);
                    }
                }
            }
        }
        structures.sort_by_key(|v| v["id"].as_u64());
        functions.sort_by(|a, b| a["name"].as_str().cmp(&b["name"].as_str()));
        Ok(
            json!({"structs":structures,"functions":functions,"enums":enums,"rejected":rejected,"declared":units.len()}),
        )
    }
    pub fn execute(&mut self, request: &Json) -> Result<Json, String> {
        let text = request["text"].as_str().unwrap_or("");
        match request["operation"].as_str().unwrap_or("") {
            "declare" => self.declare(text),
            "type" => self.type_from_string(text),
            "struct" => Ok(self
                .model
                .structs
                .get(&request["id"].as_u64().unwrap_or(0))
                .cloned()
                .unwrap_or(Json::Null)),
            "functions" => Ok(json!(self.functions)),
            "float32" => text
                .parse::<f64>()
                .map(|number| json!((number as f32) as f64))
                .map_err(|e| e.to_string()),
            "inspect" => self.inspect(&serde_json::from_str(text).map_err(|e| e.to_string())?),
            "abi" => Ok(json!(format!(
                "{}-{}-{}-{}",
                unsafe { self.api.text((self.api.clang_getClangVersion)()) },
                std::env::consts::ARCH,
                std::env::consts::OS,
                std::mem::size_of::<usize>()
            ))),
            _ => Err("unknown C declaration operation".into()),
        }
    }
}

pub fn request(registry: &mut Option<Box<Registry>>, request: &str) -> String {
    let result = (|| {
        let input: Json = serde_json::from_str(request).map_err(|e| e.to_string())?;
        if registry.is_none() {
            *registry = Some(Box::new(Registry::new()?));
        }
        registry.as_mut().unwrap().execute(&input)
    })();
    match result {
        Ok(value) => json!({"ok":true,"value":value}),
        Err(error) => json!({"ok":false,"error":error}),
    }
    .to_string()
}
