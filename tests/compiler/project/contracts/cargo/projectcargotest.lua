local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local read = fixture.read
local exists = fixture.exists
local requireCargo = fixture.requireCargo
local tempProject = fixture.tempProject
local remove = fixture.remove
local elsewhere = fixture.elsewhere
local libraryName = fixture.libraryName
local answerFrom = fixture.answerFrom

local hostSystem = require("helpers.projectfixture").hostSystem
local compiledRuntimeSources = require("helpers.projectfixture").compiledRuntimeSources

local M = {}

function M.cargoDependencyBuildsCdylib()
    requireCargo()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny_rust = {kind = "cargo", manifest = "native/Cargo.toml",
         library = "tiny_rust", locked = false},
   },
   build = {outDir = "out", entries = {"main"},
      dependencies = {"tiny_rust"}},
}
]],
        ["src/main.nupp"] = "return true\n",
        [
            "native/Cargo.toml"
        ] = [[
[package]
name = "tiny_rust"
version = "0.0.0"
edition = "2021"
[lib]
crate-type = ["cdylib"]
]],
        ["native/src/lib.rs"] = [[
#[no_mangle]
pub extern "C" fn tiny_double(value: i32) -> i32 { value * 2 }
]],
    })
    testAssert.eq(project.build(dir), 0)
    assert(exists(dir .. "/out/lib/" .. libraryName("tiny_rust")), "Cargo cdylib copied into output")
    remove(dir)
end

function M.cargoCbindgenBindingsPreserveExplicitOwnership()
    requireCargo()
    local command, cbindgen
    if hostSystem == "windows" then
        command = "cbindgen.cmd"
        -- One redirect per line rather than one around a block: `cmd` ends a
        -- parenthesised block at the first unescaped `)`, and every line here has
        -- one, so the block closed inside the first declaration and the rest went
        -- to the console instead of the file. Leading redirects also keep the
        -- space before `>` out of what is written.
        cbindgen = [[
@echo off
if not "%1"=="--output" exit /b 2
> "%2" echo typedef struct TinyBox { int value; } TinyBox;
>> "%2" echo void tiny_destroy(TinyBox *value);
>> "%2" echo TinyBox *tiny_create(int value);
>> "%2" echo int tiny_drops(void);
]]
    else
        command = "./cbindgen"
        cbindgen = [[#!/bin/sh
if [ "$1" != "--output" ] || [ -z "$2" ]; then exit 2; fi
printf '%s\n' \
  'typedef struct TinyBox { int value; } TinyBox;' \
  'void tiny_destroy(TinyBox *value);' \
  'TinyBox *tiny_create(int value);' \
  'int tiny_drops(void);' > "$2"
]]
    end
    local manifest = (
        [[
return {
   include = {"src"},
   dependencies = {
      tinyrust = {kind = "cargo", manifest = "native/Cargo.toml",
         library = "tiny_rust", locked = false,
         bindings = {
            cbindgen = true,
            command = %q,
            ownership = {
               returns = {tiny_create = "tiny_destroy"},
               takes = {tiny_destroy = {1}},
            },
         },
      },
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tinyrust"}},
}
]]
    ):format(command)
    local dir = tempProject({
        ["nupp.lua"] = manifest,
        [
            "src/main.nupp"
        ] = [[
local tiny = require("tinyrust")
do
   local _box = tiny.tiny_create(41)
end
return tiny.tiny_drops()
]],
        ["native/" .. command:gsub("^%./", "")] = cbindgen,
        [
            "native/Cargo.toml"
        ] = [[
[package]
name = "tiny_rust"
version = "0.0.0"
edition = "2021"
[lib]
crate-type = ["cdylib"]
]],
        [
            "native/src/lib.rs"
        ] = [[
use std::sync::atomic::{AtomicI32, Ordering};

#[repr(C)]
pub struct TinyBox { value: i32 }

static DROPS: AtomicI32 = AtomicI32::new(0);

#[no_mangle]
pub extern "C" fn tiny_create(value: i32) -> Box<TinyBox> {
    Box::new(TinyBox { value })
}

#[no_mangle]
pub extern "C" fn tiny_destroy(value: *mut TinyBox) {
    if !value.is_null() {
        DROPS.fetch_add(1, Ordering::SeqCst);
        unsafe { drop(Box::from_raw(value)); }
    }
}

#[no_mangle]
pub extern "C" fn tiny_drops() -> i32 { DROPS.load(Ordering::SeqCst) }
]],
    })
    if hostSystem ~= "windows" then
        testAssert.eq(os.execute(("chmod +x %q"):format(dir .. "/native/cbindgen")), 0)
    end
    testAssert.eq(project.build(dir), 0)
    assert(exists(dir .. "/out/generated/tinyrust.h"), "the configured cbindgen command wrote its header")
    local binding = read(dir .. "/out/generated/tinyrust.nupp")
    assert(
        binding:find("cdef function tiny_destroy(takes ", 1, true),
        "the configured terminal consumes its pointer: " .. binding
    )
    assert(
        binding:find("affine(TinyBox*, tiny_destroy)", 1, true),
        "the configured constructor returns a non-null affine pointer: " .. binding
    )
    assert(
        binding:find('from "@lib/' .. libraryName("tiny_rust") .. '"', 1, true),
        "the cbindgen import names the copied cdylib relatively: " .. binding
    )
    testAssert.eq(answerFrom(dir), "1", "leaving the returned Box at scope end calls its Rust destructor once")
    remove(dir)
end

-- A crate's cdylib is copied into the same `lib/` a C dependency's library is
-- built into, so it travels with the build and is named the same way.
function M.cargoDependencyNamesItsLibraryRelativeToTheModuleThatLoadsIt()
    requireCargo()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tinyrust = {kind = "cargo", manifest = "native/Cargo.toml",
         library = "tiny_rust", locked = false,
         bindings = {header = "tiny_rust.h"}},
   },
   build = {outDir = "out", entries = {"main"},
      dependencies = {"tinyrust"}},
}
]],
        ["src/main.nupp"] = "local tiny = require('tinyrust')\n" .. "return tiny.tiny_double(21)\n",
        ["native/tiny_rust.h"] = "int tiny_double(int value);\n",
        [
            "native/Cargo.toml"
        ] = [[
[package]
name = "tiny_rust"
version = "0.0.0"
edition = "2021"
[lib]
crate-type = ["cdylib"]
]],
        ["native/src/lib.rs"] = [[
#[no_mangle]
pub extern "C" fn tiny_double(value: i32) -> i32 { value * 2 }
]],
    })
    testAssert.eq(project.build(dir), 0)

    local binding = read(dir .. "/out/generated/tinyrust.nupp")
    assert(
        binding:find('from "@lib/' .. libraryName("tiny_rust") .. '"', 1, true),
        "the binding names the cdylib relative to the output tree: " .. binding
    )
    assert(not binding:find(dir, 1, true), "and the build directory does not appear in it: " .. binding)

    testAssert.eq(answerFrom(dir), "42", "a Cargo dependency loads where the build left it")
    remove(dir)
end

return M
