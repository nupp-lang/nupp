-- Acceptance workloads for the closed derive result model. These are deliberately
-- larger than unit recipes: compiler configuration, manifest-cache
-- JSON corpora, and the external Tecs MCP request shape.

local parser = require("nupp.compiler.syntax.parser")

local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local program = require("program")

local function run(source)
    source = [[local byteapi = require("bytes")
local serde = require("serde")
local typedJSON = require("serde.json")
local function decode<T>(binding: serde.Binding<T>, bytes: string): (T?, string?)
    local ok, value = pcall(typedJSON.decode, binding, bytes)
    if not ok then return nil, tostring(value) end
    return value as T, nil
end
]]
        .. source
    local parsed = parser.parse(source, "derive_acceptance.nupp")
    assert(#parsed.errors == 0, "acceptance fixture parses")
    local diagnostics = check.check(parsed, "derive_acceptance.nupp", env)
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
            error(diagnostic.code .. ": " .. diagnostic.msg, 2)
        end
    end

    return program.run(parsed, "derive_acceptance")
end

return {parser = parser, check = check, envMod = envMod, HERE = HERE, env = env, run = run, program = program,}
