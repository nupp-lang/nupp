-- `scripts/c-library-paths` and the standard bindings that ask it
-- (`nupp.compiler.project.libraries`) build only the library a program binds.
--
-- Each standard library is provisioned the first time something binds it. Asking
-- for every one at once made binding zlib compile ISA-L too, and would make it
-- compile the SQLite amalgamation once SQLite is a standard library. These run
-- the real script over a synthetic toolchain driver that only records what it
-- was asked to build, so nothing is compiled.
local libraries = require("nupp.compiler.project.libraries")

local ROOT = require("helpers.paths").root

local M = {}

-- The synthetic driver makes POSIX libraries; on Windows the script asks for
-- DLLs under `bin`, which are provisioned for real where they are used.
local WINDOWS = package.config:sub(1, 1) == "\\"
local POSIX_ONLY = "the synthetic toolchain driver is POSIX"

local function succeeded(...)
    local first, _, code = ...

    return first == true or first == 0 or code == 0
end

local function run(command)
    assert(succeeded(os.execute(command)), "failed: " .. command)
end

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function read(path)
    local file = io.open(path, "rb")
    if file == nil then
        return ""
    end
    local text = file:read("*a")
    file:close()

    return text
end

local function quote(text)
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

-- A checkout of the script alone, beside a toolchain driver that records each
-- component it is asked for in `calls`, makes an empty library for it, and
-- fails for a component named in `failing`.
local function checkout()
    local directory = os.tmpname()
    os.remove(directory)
    run("mkdir -p " .. quote(directory .. "/scripts"))
    run("cp " .. quote(ROOT .. "/scripts/c-library-paths") .. " " .. quote(directory .. "/scripts/c-library-paths"))
    write(directory .. "/scripts/toolchain.pins", "ZLIB_VERSION=test\nISAL_VERSION=test\nOTHER_VERSION=test\n")
    write(directory .. "/scripts/toolchain", [[#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
printf '%s\n' "$1" >> "$here/calls"
if grep -qx "$1" "$here/failing" 2>/dev/null; then
    echo "test toolchain: $1 does not build" >&2
    exit 1
fi
prefix="$here/artifacts/$1"
mkdir -p "$prefix/lib" "$prefix/notices"
for base in z nupp_crc nupp_yaml; do
    : > "$prefix/lib/lib$base.dylib"
    : > "$prefix/lib/lib$base.so"
done
: > "$prefix/notices/zlib-LICENSE.txt"
printf '%s\n' "$prefix"
]])
    run("chmod +x " .. quote(directory .. "/scripts/toolchain"))

    return directory
end

local function calls(directory)
    local found = {}
    for line in read(directory .. "/calls"):gmatch("[^\n]+") do
        found[#found + 1] = line
    end

    return table.concat(found, ",")
end

local function capture(command)
    local pipe = assert(io.popen(command .. " 2>&1"))
    local text = pipe:read("*a")
    pipe:close()

    return text
end

function M.aNamedVariableBuildsOnlyItsLibrary()
    if WINDOWS then
        return require("assert").suite.skip(POSIX_ONLY)
    end
    local directory = checkout()
    local text = capture("sh " .. quote(directory .. "/scripts/c-library-paths") .. " NUPP_ZLIB_LIBRARY")
    assert(text:match("NUPP_ZLIB_LIBRARY=[^\n]*/artifacts/zlib/lib/libz%."), text)
    assert(not text:find("NUPP_CRC_LIBRARY", 1, true), text)
    assert(calls(directory) == "zlib", "asking for zlib built " .. calls(directory))
    run("rm -rf " .. quote(directory))
end

function M.noVariableKeepsPrintingEveryLibrary()
    if WINDOWS then
        return require("assert").suite.skip(POSIX_ONLY)
    end
    local directory = checkout()
    local text = capture("sh " .. quote(directory .. "/scripts/c-library-paths"))
    assert(text:find("NUPP_ZLIB_LIBRARY=", 1, true) and text:find("NUPP_CRC_LIBRARY=", 1, true) and text:find("NUPP_YAML_LIBRARY=", 1, true), text)
    assert(calls(directory) == "zlib,isal,libyaml", calls(directory))
    run("rm -rf " .. quote(directory))
end

function M.anUnknownVariableIsRefused()
    if WINDOWS then
        return require("assert").suite.skip(POSIX_ONLY)
    end
    local directory = checkout()
    local text = capture("(sh " .. quote(directory .. "/scripts/c-library-paths") .. " NUPP_NONE_LIBRARY 2>&1 || echo refused)")
    assert(text:find("no pinned library is named NUPP_NONE_LIBRARY", 1, true) and text:find("refused", 1, true), text)
    assert(calls(directory) == "", calls(directory))
    run("rm -rf " .. quote(directory))
end

local function resolve(directory)
    return libraries.resolve(directory, {}, {
        getenv = function()
            return nil
        end,
        script = directory .. "/scripts/c-library-paths",
        packaged = true,
    }).bindings
end

function M.bindingZlibBuildsNothingElseAndOnlyOnce()
    if WINDOWS then
        return require("assert").suite.skip(POSIX_ONLY)
    end
    local directory = checkout()
    local bindings = resolve(directory)
    assert(calls(directory) == "", "resolving built " .. calls(directory) .. " before anything was bound")
    local zlib = bindings.nuppzlib
    assert(zlib and zlib.error == nil and zlib.path ~= nil, zlib and zlib.error)
    assert(zlib.reference:match("^@lib/libz%."), zlib.reference)
    assert(calls(directory) == "zlib", "binding zlib built " .. calls(directory))
    -- Its notice is the one its artifact carries.
    assert(#zlib.notices == 1 and zlib.notices[1]:find("/artifacts/zlib/notices/zlib-LICENSE.txt", 1, true))
    assert(bindings.nuppzlib == zlib)
    -- A second resolution in the same process asks nothing again.
    local again = resolve(directory)
    assert(again.nuppzlib.path == zlib.path)
    assert(calls(directory) == "zlib", "binding zlib again built " .. calls(directory))
    run("rm -rf " .. quote(directory))
end

function M.oneLibraryFailingLeavesTheOthersBindable()
    if WINDOWS then
        return require("assert").suite.skip(POSIX_ONLY)
    end
    local directory = checkout()
    write(directory .. "/failing", "isal\n")
    local bindings = resolve(directory)
    local crc = bindings.nuppcrc
    assert(crc.path == nil and crc.error:find("isal does not build", 1, true), tostring(crc.error))
    local zlib = bindings.nuppzlib
    assert(zlib.error == nil and zlib.path ~= nil, zlib.error)
    assert(calls(directory) == "isal,zlib", calls(directory))
    run("rm -rf " .. quote(directory))
end

function M.theFingerprintReadsOnlyTheStandardLibrariesPins()
    if WINDOWS then
        return require("assert").suite.skip(POSIX_ONLY)
    end
    local directory = checkout()
    local text = libraries.fingerprint(resolve(directory))
    assert(text:find("ZLIB_VERSION=test", 1, true) and text:find("ISAL_VERSION=test", 1, true), text)
    assert(not text:find("OTHER_VERSION", 1, true), text)
    run("rm -rf " .. quote(directory))
end

return M
