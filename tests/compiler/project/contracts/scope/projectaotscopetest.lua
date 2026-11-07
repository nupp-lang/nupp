local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local fs = fixture.fs
local write = fixture.write
local remove = fixture.remove
local AOT_SCOPE_MODEL = fixture.AOT_SCOPE_MODEL
local aotScopeFixture = fixture.aotScopeFixture

local M = {}

function M.aotScopeOmitsErasedTypeImportsWithoutIgnoringTheirErrors()
    local dir, session, scope, runtimeModules = aotScopeFixture(
        [[
module main
const {type Shape} = require("model")
export const value: Shape = {value = 1}
]]
    )
    local main = dir .. "/src/main.nupp"
    local model = dir .. "/src/model.nupp"
    assert(scope[fs.normalize(main)], "the selected entry remains executable")
    assert(
        not scope[fs.normalize(model)],
        "a type-only dependency's AOT body is not executable; entry runtime imports: " .. table.concat(
            runtimeModules,
            ", "
        )
    )
    local dependencies = session.inc.moduleDependencies(main)
    assert(table.concat(dependencies, " "):find("model", 1, true), "the checker still records the erased import")
    write(model, AOT_SCOPE_MODEL .. '\nlocal broken: integer = "not an integer"\nprint(broken)\n')
    local diagnostics = {}
    testAssert.eq(
        project.build(dir, {
            checkOnly = true,
            diagnostics = diagnostics
        }),
        1,
        "an error in the erased dependency is still refused by the normal module check"
    )
    local found = false
    for _, diagnostic in ipairs(diagnostics) do
        found = found or diagnostic.code == "NUPP2001"
    end
    assert(found, "the imported module's type mismatch remains visible")
    remove(dir)
end

function M.aotScopeKeepsValueImportsAndTheirRuntimeDependencies()
    local dir, session, scope = aotScopeFixture(
        [[
module main
local model = require("model")
export const value = model.doubled(2.0)
]]
    )
    assert(scope[fs.normalize(dir .. "/src/model.nupp")], "the value-imported AOT body is executable")
    for _, name in ipairs({"bytes", "serde.valuebuilder"}) do
        local path = session.inc.modulePath(name)
        assert(path and scope[fs.normalize(path)], name .. " remains in the actual runtime closure")
    end
    remove(dir)
end

return M
