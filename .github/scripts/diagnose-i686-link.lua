-- #71: the i686 browser-guest build does not finish on Windows. Each step of
-- it here, in one process, saying when it starts and ends, so the log names
-- the one that does not. Temporary, with windows-aot-diagnosis.yml.
local codegen = require("nupp.compiler.aot.llvm.codegen")
local profile = require("nupp.compiler.aot.llvm.profile")

local function say(...)
    io.stdout:write(os.date("!%H:%M:%S "), table.concat({...}, " "), "\n")
    io.stdout:flush()
end

local out = assert(os.getenv("NUPP_PROBE_OUT"), "NUPP_PROBE_OUT names an output directory")
local selected = assert(profile.of("i686-unknown-linux-gnu"))
local options = profile.options(selected, "baseline")
local text = assert(require("nupp.compiler.bundled").source(selected.linkedRuntime))
say("compiling the i686 runtime,", tostring(#text), "bytes of IR")
local compiled, err = codegen.compile(text, "runtime-i686", options)
say("compiled:", tostring(compiled ~= nil), tostring(err))
local object = out .. "/runtime.o"
local handle = assert(io.open(object, "wb"))
handle:write(compiled.object)
handle:close()
say("wrote", object, tostring(#compiled.object), "bytes")
local argv = profile.sharedLink(selected, out .. "/libprobe.so", {object}, "libprobe.so")
say("linking:", table.concat(argv, " "))
local messages, linkErr = codegen.link(argv)
say("linked:", tostring(messages ~= nil), tostring(linkErr))
say("done; exiting")
