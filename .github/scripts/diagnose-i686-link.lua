-- #71: an i686 build on Windows compiles and links, and then its process
-- never exits. NUPP_PROBE_MODE picks one step per process -- `compile` (and
-- write the object), `link` (the object the compile wrote), `coff` (a Windows
-- DLL link of an x86-64 object) or `both` -- so which one leaves the process
-- unable to exit is the one whose run is killed. Temporary, with
-- windows-aot-diagnosis.yml.
local codegen = require("nupp.compiler.aot.llvm.codegen")
local profile = require("nupp.compiler.aot.llvm.profile")

local function say(...)
    io.stdout:write(os.date("!%H:%M:%S "), table.concat({...}, " "), "\n")
    io.stdout:flush()
end

local out = assert(os.getenv("NUPP_PROBE_OUT"), "NUPP_PROBE_OUT names an output directory")
local mode = os.getenv("NUPP_PROBE_MODE") or "both"
local i686 = assert(profile.of("i686-unknown-linux-gnu"))
local object = out .. "/runtime.o"

if mode == "compile" or mode == "both" then
    local text = assert(require("nupp.compiler.bundled").source(i686.linkedRuntime))
    local compiled, err = codegen.compile(text, "runtime-i686", profile.options(i686, "baseline"))
    say("compiled:", tostring(compiled ~= nil), tostring(err))
    local handle = assert(io.open(object, "wb"))
    handle:write(compiled.object)
    handle:close()
end
if mode == "link" or mode == "both" then
    local messages, err = codegen.link(profile.sharedLink(i686, out .. "/libprobe.so", {object}, "libprobe.so"))
    say("linked ELF:", tostring(messages ~= nil), tostring(err))
end
if mode == "coff" then
    local windows = assert(profile.of("x86_64-pc-windows-msvc"))
    local ir = 'target triple = "' .. windows.llvmTriple .. '"\ndefine dllexport i32 @probe() {\n  ret i32 7\n}\n'
    local compiled, err = codegen.compile(ir, "probe", profile.options(windows, "baseline"))
    say("compiled COFF:", tostring(compiled ~= nil), tostring(err))
    local coffObject = out .. "/probe.obj"
    local handle = assert(io.open(coffObject, "wb"))
    handle:write(compiled.object)
    handle:close()
    local messages, linkErr = codegen.link(profile.sharedLink(windows, out .. "/probe.dll", {coffObject}, "probe.dll"))
    say("linked COFF:", tostring(messages ~= nil), tostring(linkErr))
end
say("done; exiting")
