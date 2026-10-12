-- Stage-zero driver for the Nupp image emitter. Project loading stays on the
-- host; all lowering and image writing live in nupp.compiler.vm.lower.
local envMod = require("nupp.compiler.project.env")
local compile = require("nupp.tools.cli.compile")
local lower = require("nupp.compiler.vm.lower")
local root = assert(arg[1], "project root")
local entryName = assert(arg[2], "entry module name")
local env = envMod.new(root)

local function modulePath(name)
    local rel = name:gsub("%.", "/")
    for _, cand in ipairs({
        root .. "/src/" .. rel .. "/init.nupp",
        root .. "/src/" .. rel .. ".nupp",
        root .. "/" .. rel .. ".nupp",
        rel .. ".nupp"
    }) do
        local fh = io.open(cand, "r")
        if fh then
            fh:close();
            return cand
        end
    end

    return nil
end

local function checkedModule(name, path)
    local collected = {}
    local tree = compile.check(path, env, {}, collected)
    for _, d in ipairs(collected) do
        if d.severity == "error" or not d.severity then
            io.stderr:write(name, ": ", tostring(d.code), " ", tostring(d.msg), "\n")
        end
    end

    return assert(tree, "check failed for " .. path)
end

local extras = {}
for i = 3, #arg do
    extras[#extras + 1] = arg[i]
end
io.write(lower.emit(entryName, extras, modulePath, checkedModule))
