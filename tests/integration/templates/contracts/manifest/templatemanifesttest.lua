local fixture = require("helpers.templatefixture")
local testAssert = fixture.testAssert
local template = fixture.template

local M = {}

function M.aManifestDeclaresVariablesWithPatterns()
    local manifest = assert(
        template.manifest(
            [[
      return {description = "d", variables = {who = {default = "world"}}}
   ]],
            "template.lua"
        )
    )
    testAssert.eq(manifest.description, "d", "the description came through")
    testAssert.eq(manifest.variables.who.default, "world", "and the default")
end

function M.theSandboxRefusesEveryWayOut()
    local reaches = {
        io = [[return {description = io.open("/etc/passwd") and "x"}]],
        os = [[return {description = tostring(os.execute("true"))}]],
        require = [[require("nupp.compiler.fs") return {}]],
        loadstring = [[loadstring("return 1") return {}]],
        package = [[return {description = tostring(package.path)}]],
    }
    for name, text in pairs(reaches) do
        local manifest, err = template.manifest(text, "template.lua")
        testAssert.eq(manifest, nil, name .. " is not reachable from a template")
        assert(err, "and the refusal says so for " .. name)
    end
end

function M.aTemplateThatLoopsIsRefusedRatherThanWaitedFor()
    local manifest, err = template.manifest("while true do end", "template.lua")
    testAssert.eq(manifest, nil, "a loop returns no manifest")
    assert(err:find("too long", 1, true), err)
end

function M.loadingATemplateLeavesTheHostHookInPlace()
    local function hostHook()
    end

    local before = {debug.gethook()}
    debug.sethook(hostHook, "r")
    local manifest = template.manifest([[return {description = "d"}]], "template.lua")
    local hook, mask = debug.gethook()
    debug.sethook(before[1], before[2], before[3])
    assert(manifest, "the template loaded")
    testAssert.eq(hook, hostHook, "the host's hook survives a template load")
    testAssert.eq(mask, "r", "with its mask")
end

function M.anUnknownFieldIsRefusedByName()
    local _, err = template.manifest([[return {hooks = {"rm -rf /"}}]], "template.lua")
    assert(err:find("hooks", 1, true), err)
    assert(err:find("not a template field", 1, true), err)
end

function M.manifestFieldsKeepTheirDeclaredTypes()
    for _, case in ipairs({
        {text = [[return {description = 7}]], field = "description", kind = "string"},
        {text = [[return {variables = {x = {default = false}}}]], field = "variables.x.default", kind = "string"},
        {text = [[return {variables = {x = {required = "yes"}}}]], field = "variables.x.required", kind = "boolean"},
    }) do
        local manifest, err = template.manifest(case.text, "template.lua")
        testAssert.eq(manifest, nil, case.field .. " is refused")
        assert(err:find(case.field, 1, true), err)
        assert(err:find(case.kind, 1, true), err)
    end
end

function M.manifestListsMustBeDense()
    for _, field in ipairs({"raw", "after"}) do
        local manifest, err = template.manifest("return {" .. field .. " = {[2] = 'x'}}", "template.lua")
        testAssert.eq(manifest, nil, field .. " with a hole is refused")
        assert(err:find("dense list", 1, true), err)
    end
end

function M.anUnknownStepIsRefusedWithTheStepsThereAre()
    local _, err = template.manifest([[return {after = {"deploy"}}]], "template.lua")
    assert(err:find("deploy", 1, true), err)
    assert(err:find("build", 1, true), "the complaint lists the steps: " .. err)
end

function M.derivedVariablesCannotBeDeclared()
    local _, err = template.manifest([[return {variables = {moduleName = {}}}]], "template.lua")
    assert(err:find("derived", 1, true), err)
end

function M.nameCannotBeGivenADefault()
    local _, err = template.manifest([[return {variables = {name = {default = "x"}}}]], "template.lua")
    assert(err:find("cannot have a default", 1, true), err)
end

return M
