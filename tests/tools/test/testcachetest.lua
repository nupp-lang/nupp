local test = require("assert")
local json = require("testjson")
local fs = require("nupp.compiler.fs")
local cacheModule = dofile("tests/cache.lua")
local M = {}

local function fixture(run)
    local root = os.tmpname()
    os.remove(root)
    fs.mkdir(root .. "/tests/one/nested")
    fs.mkdir(root .. "/tests/helpers")
    fs.writeFile(
        root .. "/tests/one/alphatest.lua",
        'local h = require("helpers.helper")\nreturn {passes = function() assert(h) end}\n'
    )
    fs.writeFile(root .. "/tests/one/fixture", "first")
    fs.writeFile(root .. "/tests/helpers/helper.lua", "return true\n")
    fs.writeFile(root .. "/shared", "shared first")
    local options = {
        root = root .. "/tests",
        build = root .. "/build",
        json = json,
        policies = {one = {cache = true, inputs = {root .. "/shared"}}},
        catalog = {{name = "alphatest", path = "one/alphatest.lua"}},
        selected = {{name = "alphatest"}},
        runner = "runner",
        flags = "flags",
    }
    local results = {{suite = "alphatest", name = "passes", id = "alphatest/passes", status = "passed", durationMs = 1}}
    local suites = {{suite = "alphatest", tests = 1}}
    local clock, originalGetenv, originalPopen = os.time, os.getenv, io.popen
    os.time = function()
        return clock() + 10
    end
    local ok, problem = pcall(run, root, options, results, suites)
    os.time, os.getenv, io.popen = clock, originalGetenv, originalPopen
    os.remove(root, true)
    assert(ok, problem)
end

local function opened(options)
    local cache = assert(cacheModule.open(options))
    return cache, assert(cache.packages.one)
end

function M.unchangedPassingPackagesHitAndContentChangesMiss()
    fixture(function(root, options, results, suites)
        local cache, entry = opened(options)
        test.eq(entry.hit, nil)
        cache.save(results, suites)
        local _, reused = opened(options)
        assert(reused.hit)
        for _, path in ipairs({"tests/one/fixture", "tests/helpers/helper.lua", "shared", "tests/one/alphatest.lua"}) do
            local original = assert(fs.readFile(root .. "/" .. path))
            fs.writeFile(root .. "/" .. path, original .. "\n-- changed")
            local _, changed = opened(options)
            test.eq(changed.hit, nil, path)
            fs.writeFile(root .. "/" .. path, original)
        end
        for _, name in ipairs({"runner", "flags"}) do
            local original = options[name]
            options[name] = "changed"
            local _, changed = opened(options)
            test.eq(changed.hit, nil, name)
            options[name] = original
        end
    end)
end

function M.partialFailedSkippedAndRecentRunsCannotPopulateTheStore()
    fixture(function(_, options, results, suites)
        local cache = opened(options)
        for _, status in ipairs({"failed", "skipped", "not-executed"}) do
            results[1].status = status
            cache.save(results, suites)
            local _, entry = opened(options)
            test.eq(entry.hit, nil)
        end
        results[1].status = "passed"
        options.selected = {}
        test.eq(next(assert(cacheModule.open(options)).packages), nil)
        options.selected = {{name = "alphatest"}}
        local clock = os.time
        os.time = function()
            return clock() - 10
        end
        local recent, entry = opened(options)
        test.eq(entry.recent, true)
        recent.save(results, suites)
        test.eq(fs.readFile(entry.path), nil)
        os.time = clock
    end)
end

function M.opaqueInputsStayUncachedAndNestedPackagesAreIndependent()
    fixture(function(root, options)
        options.catalog[2] = {name = "betatest", path = "one/nested/betatest.lua"}
        fs.writeFile(root .. "/tests/one/nested/betatest.lua", "return {}\n")
        local _, first = opened(options)
        fs.writeFile(root .. "/tests/one/nested/betatest.lua", "return {changed = true}\n")
        local _, second = opened(options)
        test.eq(first.key, second.key)
        for _, source in ipairs({
            'require("helper" .. "name")',
            'local r = require; r("helper")',
            'os.execute("false")',
            'io.popen("env")',
            'dofile("another.lua")'
        }) do
            fs.writeFile(root .. "/tests/one/alphatest.lua", source)
            test.eq(next(assert(cacheModule.open(options)).packages), nil, source)
        end
        options.policies.one.cache = false
        test.eq(next(assert(cacheModule.open(options)).packages), nil)
    end)
end

function M.corruptAndTruncatedEntriesAreMisses()
    fixture(function(_, options, results, suites)
        local cache, entry = opened(options)
        cache.save(results, suites)
        local original = assert(fs.readFile(entry.path))
        for _, contents in ipairs({"broken JSON", json.encode({key = entry.key, tests = {false}, suites = suites})}) do
            fs.writeFile(entry.path, contents)
            local _, corrupt = opened(options)
            test.eq(corrupt.hit, nil)
        end
        fs.writeFile(entry.path, original)
        local _, restored = opened(options)
        assert(restored.hit)
    end)
end

function M.environmentAndRuntimeArtifactChangesInvalidateResults()
    fixture(function(root, options, results, suites)
        local getenv, popen = os.getenv, io.popen
        local setting = "before"
        local binary = root .. "/runtime"
        fs.writeFile(binary, "runtime one")
        os.getenv = function(name)
            if name == "NUPP_VM_BINARY" then
                return binary
            end
            return getenv(name)
        end
        io.popen = function(command, ...)
            if command == "env -0" then
                return {
                    read = function()
                        return "NUPP_TEST_INPUT=" .. setting .. "\0"
                    end,
                    close = function()
                    end
                }
            end

            return popen(command, ...)
        end
        local cache = opened(options)
        cache.save(results, suites)
        local _, unchanged = opened(options)
        assert(unchanged.hit)
        setting = "after"
        local _, changed = opened(options)
        test.eq(changed.hit, nil)
        setting = "before"
        fs.writeFile(binary, "runtime two")
        local _, runtime = opened(options)
        test.eq(runtime.hit, nil)
    end)
end

return M
