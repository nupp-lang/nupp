-- The open-binding prerequisite is a separate project. None of its models can
-- reach the compiler's reflection/derive tables or the existing serde schema.
local json = require("testjson")
local process = require("nupp.compiler.process")
local fs = require("nupp.compiler.fs")

local HERE = require("helpers.paths").tests
local NUPP = fs.absolute(HERE .. "/../bin/nupp")
local PROJECT = fs.absolute(HERE .. "/../bench/serde-spike/contracts")
local project = require("helpers.contractproject").open(PROJECT)

local function call(args)
    -- This case deliberately removes the 64-bit carrier. Its answer depends
    -- on a cold runtime capability lookup, so it retains a process boundary.
    if args[1] == "run" and args[2] ~= "declaration_capabilities.nupp" and args[2] ~= "erasure.nupp" then
        local ok, problem = pcall(project.run, args[2])
        return ok and 0 or 1, ok and "" or tostring(problem)
    elseif args[1] == "check" and args[2] == "--json" then
        local files = {}
        for i = 3, #args do
            files[#files + 1] = args[i]
        end
        local ok, diagnostics = project.check(files)
        return ok and 0 or 1, json.encode({ok = ok, diagnostics = diagnostics})
    end
    local argv = {NUPP}
    for _, arg in ipairs(args) do
        argv[#argv + 1] = arg
    end

    return process.capture(argv, {cwd = PROJECT})
end

return {call = call}
