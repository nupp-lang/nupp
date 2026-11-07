local fixture = require("helpers.templatefixture")
local testAssert = fixture.testAssert
local template = fixture.template

local M = {}

function M.aDeclaredPatternIsEnforcedInTheTemplatesOwnWords()
    local manifest = assert(
        template.manifest(
            [[
      return {variables = {name = {pattern = "^[a-z]+$", invalid = "lowercase only, please"}}}
   ]],
            "template.lua"
        )
    )
    local values, err = template.values(manifest, "Not Lower", "d")
    testAssert.eq(values, nil, "a value outside the pattern is refused")
    testAssert.eq(err, "lowercase only, please", "in the template's own sentence")
    assert(template.values(manifest, "fine", "d"), "and a matching one is not")
end

function M.moduleNameIsTheProjectNameInLuacase()
    local manifest = assert(template.manifest("return {}", "template.lua"))
    local values = assert(template.values(manifest, "my-lib", "somewhere/my-lib"))
    testAssert.eq(values.name, "my-lib", "the name is as given")
    testAssert.eq(values.moduleName, "mylib", "the module name is canonical luacase")
    testAssert.eq(values.directory, "somewhere/my-lib", "the directory is the destination")
end

function M.settingADerivedNameIsRefusedRatherThanIgnored()
    local manifest = assert(template.manifest("return {}", "template.lua"))
    local _, err = template.values(manifest, "x", "d", {name = "other"})
    assert(err:find("derived from the project name", 1, true), err)
end

function M.aRequiredVariableWithNoValueSaysWhatItIsFor()
    local manifest = assert(
        template.manifest(
            [[
      return {variables = {author = {required = true, description = "who wrote it"}}}
   ]],
            "template.lua"
        )
    )
    local _, err = template.values(manifest, "x", "d")
    assert(err:find("who wrote it", 1, true), err)
    assert(err:find("--set author=", 1, true), err)
end

return M
