-- What the compiler discovers and what it calls each thing.
--
-- Diagnostic only. It exists to compare one platform's answer against another's
-- when a build produces module surfaces that a passing platform does not, and it
-- writes rather than asserts: the comparison is the point, not a verdict.
--
-- Run it with the interpreter environment the launchers export, and redirect it
-- somewhere a CI job can upload.
local fs = require("nupp.compiler.fs")
local envMod = require("nupp.compiler.env")

local root = os.getenv("NUPP_COMPILER_ROOT") or "."
local lines = {}

local function say(...)
    lines[#lines + 1] = table.concat({...}, "\t")
end

say("root", root)
say("package.config-separator", package.config:sub(1, 1))
say("jit.os", (jit and jit.os) or "?")

local files = fs.listFiles(root .. "/src")
say("listFiles-count", tostring(#files))

-- Whether each file the failures name was discovered at all, and what module
-- name it was given. A missing name is how a file stops contributing its
-- exports without anything failing loudly.
local env = envMod.new(root)
local interesting = {
    "src/nupp/compiler/types.nupp",
    "src/nupp/compiler/cli/spec.nupp",
    "src/nupp/compiler/associated.nupp",
}
local present = {}
for _, file in ipairs(files) do present[file] = true end
for _, relative in ipairs(interesting) do
    local full = root .. "/" .. relative
    local named = envMod.moduleNameForPath and envMod.moduleNameForPath(env, full)
    say("target", relative, "discovered=" .. tostring(present[full] or false),
        "module=" .. tostring(named))
end

-- The whole list, so two platforms can be diffed rather than eyeballed.
for _, file in ipairs(files) do
    say("file", (file:gsub("^" .. root:gsub("%p", "%%%0"), "")))
end

io.write(table.concat(lines, "\n"), "\n")
