local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local compilerEnv = fixture.compilerEnv
local tempProject = fixture.tempProject

local M = {}

function M.moduleSourceChecksReuseOnlyMatchingSourceAndContext()
    local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n'})
    local env = compilerEnv.new(dir, {cache = false})
    local path = dir .. "/sample.nupp"
    local source = "module sample\nexport const value: integer = 1\n"
    local first, diagnostics, firstType, firstExports = compilerEnv.checkModuleSource(env, path, source)
    testAssert.eq(#diagnostics, 0)
    local again, _, againType, againExports = compilerEnv.checkModuleSource(env, path, source)
    assert(
        first == again and firstType == againType and firstExports == againExports,
        "a source-identical check in one environment owns one parse and export graph"
    )
    local strict = compilerEnv.checkModuleSource(env, path, source, {strict = false})
    assert(strict ~= first, "changed strictness must not reuse the earlier check")
    local declared = compilerEnv.checkModuleSource(env, path, source, {strict = false, declarationFile = true})
    assert(declared ~= strict, "a declaration check must not reuse an implementation check")
    local implemented = compilerEnv.checkModuleSource(env, path, source, {strict = false})
    assert(implemented ~= declared, "an implementation check must not reuse declaration mode")
    local compatible, compatDiagnostics = compilerEnv.checkModuleSource(env, path, source, {
        strict = false,
        compat = "lua51"
    })
    testAssert.eq(#compatDiagnostics, 1)
    testAssert.eq(compatDiagnostics[1].code, "NUPP3013", "the changed profile refuses runtime const")
    assert(compatible ~= strict, "changed compatibility must not reuse the earlier check")
    local named, namedDiagnostics = compilerEnv.checkModuleSource(env, dir .. "/context.nupp", "return 1\n", {
        moduleName = "first"
    })
    testAssert.eq(#namedDiagnostics, 0)
    local renamed, renamedDiagnostics = compilerEnv.checkModuleSource(env, dir .. "/context.nupp", "return 1\n", {
        moduleName = "second"
    })
    testAssert.eq(#renamedDiagnostics, 0)
    assert(renamed ~= named, "changed module ownership must not reuse the earlier check")
    local changed, changedDiagnostics = compilerEnv.checkModuleSource(env, path, source .. "export const other = 2\n")
    assert(changed ~= strict and #changedDiagnostics == 0, "changed source gets its own completed check")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.bundledSourcesShareTheirPendingAndCompletedExports()
    local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n'})
    local env = compilerEnv.new(dir, {cache = false})
    local loaded = assert(env.bundled.types, "the types facade checks through its bundled dependency cycle")
    assert(loaded == env.loadedPaths.types, "the bundled cache and lifecycle share one completed record")
    assert(not loaded.inProgress and loaded.exports.types.Key and loaded.exports.types.Debug)
    assert(loaded.result == nil, "completed bundled interfaces do not retain their parsed implementation")
    assert(loaded.source and loaded.checkContext, "source inspection and check context remain available")
    testAssert.eq(env.bundled.types, loaded, "a repeated bundled lookup retains the exact export graph")
    local reflection = assert(env.bundled["nupp.compiler.runtime.reflect"])
    assert(
        reflection == env.loadedPaths["nupp.compiler.runtime.reflect"],
        "recursive reflection retains one export graph"
    )
    assert(not reflection.inProgress and reflection.source and reflection.resource)
    assert(reflection.result == nil, "recursive bundled implementations also release their parse result")
    testAssert.eq(loaded.resource, "/types/init.nupp")
    testAssert.eq(loaded.declarationOnly, false)
    local declared = assert(env.bundled.bit)
    assert(declared.declarationOnly and not declared.inProgress, "declaration modules retain their checking mode")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.warmingBundledMetadataPreservesProjectModulePrecedence()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"."}}\n',
        ["bit.nupp"] = 'module bit\nexport const projectOnly = "project"\n',
    })
    local env = compilerEnv.new(dir, {cache = false})
    local bundled = assert(env.bundled.bit)
    assert(env.loaded.bit == nil, "reading bundled metadata does not select it over project source")
    local resolved = assert(env.resolveModule(env, "bit"))
    local selected = assert(env.loaded.bit)
    assert(selected ~= bundled and selected.path == dir .. "/bit.nupp")
    assert(selected.type == resolved and selected.exports.values.projectOnly)
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.malformedBundledDeclarationsAreRefusedInBothProfiles()
    local parser = require("nupp.compiler.syntax.parser")
    local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n'})
    local environments = {
        compilerEnv.new(dir, {
            cache = false
        }),
        compilerEnv.new(dir, {
            cache = false,
            compat = "lua51"
        }),
    }
    local original = parser.parse
    parser.parse = function(source, filename, ...)
        return original(filename == "bit" and "local =" or source, filename, ...)
    end
    local ok, reason = pcall(function()
        for _, env in ipairs(environments) do
            testAssert.eq(env.bundled.bit, false, "syntax errors cannot become unknown-but-accepted modules")
            assert(env.loaded.bit == nil and env.loadedPaths.bit == nil, "a refused bundle leaves no selected record")
        end
    end)
    parser.parse = original
    os.execute("rm -rf " .. string.format("%q", dir))
    assert(ok, reason)
end

function M.moduleSourceCheckFailuresReleaseTheirPendingEntry()
    local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n'})
    local env = compilerEnv.new(dir, {cache = false})
    local path = dir .. "/sample.nupp"
    local source = "module sample\nexport const value: integer = 1\n"
    local checker = require("nupp.compiler.check")
    local original = checker.check
    checker.check = function()
        error("check failed deliberately", 0)
    end
    local ok, problem = pcall(compilerEnv.checkModuleSource, env, path, source, {moduleName = "sample"})
    checker.check = original
    assert(not ok and tostring(problem):find("check failed deliberately", 1, true))
    assert(env.loadedPaths[path] == nil and env.loaded.sample == nil, "a thrown check leaves no pending module")
    local _, diagnostics = compilerEnv.checkModuleSource(env, path, source, {moduleName = "sample"})
    testAssert.eq(#diagnostics, 0)
    assert(env.loaded.sample ~= nil and not env.loaded.sample.inProgress, "the entry can be checked after a failure")
    local completed = env.loaded.sample
    checker.check = function()
        error("replacement failed deliberately", 0)
    end
    local replaced = pcall(compilerEnv.checkModuleSource, env, path, source .. "\n", {moduleName = "sample"})
    checker.check = original
    assert(
        not replaced and env.loaded.sample == completed and env.loadedPaths[path] == completed,
        "a thrown replacement restores the completed record it temporarily owned"
    )
    local _, broken = compilerEnv.checkModuleSource(env, path, "module sample\nexport const value: integer = 'bad'\n", {
        moduleName = "sample"
    })
    assert(#broken > 0 and not env.loaded.sample.inProgress, "diagnostic failures complete their module record")
    local _, recovered = compilerEnv.checkModuleSource(env, path, source, {moduleName = "sample"})
    testAssert.eq(#recovered, 0, "corrected source can replace the failed check")
    os.execute("rm -rf " .. string.format("%q", dir))
end

return M
