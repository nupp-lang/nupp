local compile = require("nupp.tools.cli.compile")
local fs = require("nupp.compiler.fs")
local process = require("nupp.compiler.process")

local M = {}

function M.rawExecutionOwnsAndReapsAChildWithoutATaskScheduler()
    local env = require("nupp.compiler.project.env").new(".", {cache = false})
    local adapter = assert(compile.image("src/nupp/tools/vm/emitprocess.nupp", env, "nupp.tools.vm.emitprocess"))
    local source = [[
local p = require("nupp.tools.vm.emitprocess")
return {run = function()
    local child = assert(p.start({assert(os.getenv("NUPP_VM_BINARY")), "run", assert(os.getenv("NUPP_VM_CLI_IMAGE")), "nupp.tools.vm.emitparallel", "jobs", "3"}, {cwd = ".", env = {NO_JIT = "1"}}))
    local out = {}
    while child:isrunning() do
        local text = child.stdout:poll(65536, 5)
        if text then out[#out + 1] = text end
    end
    while true do
        local text = child.stdout:poll()
        if not text then break end
        out[#out + 1] = text
    end
    local exit = child:wait()
    child:close()
    child:close()
    return table.concat(out):gsub("%s+", "") .. ":" .. exit.exitcode
end}
]]
    local probe = assert(
        compile.image("src/nupp/tools/vm/rawprobe.lua", env, "nupp.tools.vm.rawprobe", nil, source, false)
    )
    local prefix = os.tmpname()
    os.remove(prefix)
    assert(fs.writeFile(prefix .. ".adapter", adapter))
    assert(fs.writeFile(prefix .. ".probe", probe))
    local ok, code, output = pcall(
        process.captureIsolated,
        {
            assert(os.getenv("NUPP_VM_BINARY")),
            "run",
            assert(os.getenv("NUPP_VM_CLI_IMAGE")),
            "nupp.tools.vm.rawprobe",
            "run",
            "--load",
            prefix .. ".adapter",
            "--load",
            prefix .. ".probe",
        },
        {timeoutMs = 30000}
    )
    os.remove(prefix .. ".adapter")
    os.remove(prefix .. ".probe")
    assert(ok, code)
    assert(code == 0 and output:find("3:0", 1, true), output)
end

return M
