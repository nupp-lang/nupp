//! The C ABI of `nupp_extension.h`, field for field. Both the VM and every
//! extension use these definitions; the VM's `c-headers` test holds them to
//! the header's sizes and offsets.
#![allow(non_camel_case_types)]
use std::ffi::{c_char, c_void};

pub const ABI_VERSION: u32 = 1;
/// The symbol the VM looks up, NUL-terminated.
pub const ENTRY_SYMBOL: &[u8] = b"nupp_extension_v1\0";

pub const NIL: u32 = 0;
pub const BOOLEAN: u32 = 1;
pub const INTEGER: u32 = 2;
pub const NUMBER: u32 = 3;
pub const STRING: u32 = 4;
pub const HANDLE: u32 = 5;

pub type Status = i32;
pub const OK: Status = 0;
pub const ERROR: Status = 1;
pub const SUSPENDED: Status = 2;

pub type Handle = u64;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Str {
    pub bytes: *const c_char,
    pub length: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union SlotValue {
    pub boolean: i32,
    pub integer: i64,
    pub number: f64,
    pub string: Str,
    pub handle: Handle,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Slot {
    pub kind: u32,
    pub reserved: u32,
    pub value: SlotValue,
}
impl Slot {
    pub const NIL: Slot = Slot { kind: NIL, reserved: 0, value: SlotValue { integer: 0 } };
    pub fn boolean(b: bool) -> Slot {
        Slot { kind: BOOLEAN, reserved: 0, value: SlotValue { boolean: b as i32 } }
    }
    pub fn integer(i: i64) -> Slot {
        Slot { kind: INTEGER, reserved: 0, value: SlotValue { integer: i } }
    }
    pub fn number(n: f64) -> Slot {
        Slot { kind: NUMBER, reserved: 0, value: SlotValue { number: n } }
    }
    /// The bytes are borrowed: they must outlive the slot's use.
    pub fn string(bytes: &[u8]) -> Slot {
        Slot {
            kind: STRING,
            reserved: 0,
            value: SlotValue { string: Str { bytes: bytes.as_ptr() as *const c_char, length: bytes.len() } },
        }
    }
    pub fn handle(h: Handle) -> Slot {
        Slot { kind: HANDLE, reserved: 0, value: SlotValue { handle: h } }
    }
}

/// Opaque: the VM an extension instance belongs to.
#[repr(C)]
pub struct Vm {
    _private: [u8; 0],
}
/// Opaque: one call of a host function.
#[repr(C)]
pub struct Call {
    _private: [u8; 0],
}
/// Opaque: a suspended call's completion.
#[repr(C)]
pub struct Request {
    _private: [u8; 0],
}

pub type Function = unsafe extern "C" fn(
    host: *const Host,
    call: *mut Call,
    instance: *mut c_void,
    data: *mut c_void,
    args: *const Slot,
    nargs: usize,
    results: *mut Slot,
    nresults: usize,
) -> Status;

pub type Write = unsafe extern "C" fn(sink: *mut c_void, bytes: *const c_void, length: usize);

#[repr(C)]
pub struct FunctionEntry {
    pub name: *const c_char,
    pub signature: *const c_char,
    pub function: Function,
    pub data: *mut c_void,
    pub flags: u32,
    pub reserved: u32,
}

#[repr(C)]
pub struct ResourceType {
    pub name: *const c_char,
    pub type_data: *mut c_void,
    pub drop: Option<unsafe extern "C" fn(instance: *mut c_void, type_data: *mut c_void, data: *mut c_void)>,
    pub save: Option<
        unsafe extern "C" fn(instance: *mut c_void, type_data: *mut c_void, data: *mut c_void, write: Write, sink: *mut c_void) -> Status,
    >,
    pub restore: Option<
        unsafe extern "C" fn(
            instance: *mut c_void,
            type_data: *mut c_void,
            bytes: *const c_void,
            length: usize,
            data: *mut *mut c_void,
        ) -> Status,
    >,
}

#[repr(C)]
pub struct Extension {
    pub abi_version: u32,
    pub size: u32,
    pub module: *const c_char,
    pub target: *const c_char,
    pub functions: *const FunctionEntry,
    pub function_count: usize,
    pub resource_types: *const ResourceType,
    pub resource_type_count: usize,
    pub init: Option<unsafe extern "C" fn(host: *const Host, vm: *mut Vm, instance: *mut *mut c_void) -> Status>,
    pub shutdown: Option<unsafe extern "C" fn(host: *const Host, instance: *mut c_void)>,
}

pub type Entry = unsafe extern "C" fn() -> *const Extension;

#[repr(C)]
pub struct Host {
    pub abi_version: u32,
    pub size: u32,
    pub raise: unsafe extern "C" fn(call: *mut Call, message: *const c_char, length: usize) -> Status,
    pub retain: unsafe extern "C" fn(call: *mut Call, handle: Handle) -> Handle,
    pub release: unsafe extern "C" fn(vm: *mut Vm, handle: Handle),
    pub invoke: unsafe extern "C" fn(
        call: *mut Call,
        function: Handle,
        args: *const Slot,
        nargs: usize,
        results: *mut Slot,
        nresults: usize,
    ) -> Status,
    pub suspend: unsafe extern "C" fn(call: *mut Call) -> *mut Request,
    pub complete: unsafe extern "C" fn(request: *mut Request, results: *const Slot, nresults: usize),
    pub fail: unsafe extern "C" fn(request: *mut Request, message: *const c_char, length: usize),
    pub new_resource: unsafe extern "C" fn(call: *mut Call, kind: u32, data: *mut c_void) -> Handle,
    pub resource: unsafe extern "C" fn(call: *mut Call, handle: Handle, kind: u32) -> *mut c_void,
    pub close_resource: unsafe extern "C" fn(call: *mut Call, handle: Handle, kind: u32) -> Status,
    pub vm: unsafe extern "C" fn(call: *mut Call) -> *mut Vm,
}

/// The target string a VM compares, `<arch>-<os>` as `std::env::consts` spells
/// them and as the header's `NUPP_EXTENSION_TARGET` does.
pub fn target() -> String {
    format!("{}-{}", std::env::consts::ARCH, std::env::consts::OS)
}
