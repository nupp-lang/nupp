-- Whether the staged native provider loads, and under which spelling.
--
-- Diagnostic only, to be removed once the platforms agree.
--
-- `ffi.load` passes a name containing a path separator to the platform loader
-- unchanged and only decorates a bare name, so an extensionless staged path is
-- not by itself a reason for a load to fail. Windows error 126 also covers a
-- dependency that cannot be resolved, which is a different problem with the same
-- message. This tries each spelling and reports the runtime the library imports.
local ffi = require("ffi")
local root = os.getenv("NUPP_COMPILER_ROOT") or "."
local staged = root .. "/build/lib/nupp_native"

local function say(...)
    io.write(table.concat({...}, "\t"), "\n")
end

say("jit.os", jit.os)
say("staged", staged)

local handle = io.open(staged, "rb")
if not handle then
    say("staged-present", "false")
    os.exit(0)
end
local bytes = handle:read("*a")
handle:close()
say("staged-present", "true", "bytes=" .. #bytes)

-- A copy carrying the platform's own suffix, to separate "wrong name" from
-- "unresolvable dependency" without changing what is shipped.
local suffix = jit.os == "Windows" and ".dll" or (jit.os == "OSX" and ".dylib" or ".so")
local copied = staged .. suffix
local out = io.open(copied, "wb")
if out then
    out:write(bytes)
    out:close()
    say("copy", copied, "written")
else
    say("copy", copied, "failed")
end

local function attempt(label, name)
    local ok, err = pcall(ffi.load, name)
    say("load", label, name, ok and "ok" or "failed", ok and "" or tostring(err):sub(1, 150))
end

attempt("extensionless", staged)
attempt("suffixed", copied)
attempt("extensionless-backslash", (staged:gsub("/", "\\")))
attempt("suffixed-backslash", (copied:gsub("/", "\\")))

-- What a Rust cdylib needs beside it on Windows. A bare name is decorated by
-- ffi.load, which is the case the documentation describes.
if jit.os == "Windows" then
    for _, dependency in ipairs({"VCRUNTIME140", "ucrtbase", "kernel32"}) do
        attempt("dependency", dependency)
    end
end
