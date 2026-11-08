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
        local setting, transport = "before", "first-call"
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
                        return "NUPP_TEST_INPUT=" .. setting .. "\0CODEX_TOOL_CALL_ID=" .. transport .. "\0"
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
        transport = "another-call"
        assert(select(2, opened(options)).hit, "tool-call bookkeeping does not invalidate a pass")
        options.selected[1].path = options.catalog[1].path
        local restore = cache.audit()
        local messages, stderr = {}, io.stderr
        io.stderr = {
            write = function(_, message)
                messages[#messages + 1] = message
            end
        }
        local active = rawget(_G, "__NUPP_TEST_AUDIT_ACTIVE")
        rawset(_G, "__NUPP_TEST_AUDIT_ACTIVE", true)
        os.getenv("CODEX_TOOL_CALL_ID")
        rawset(_G, "__NUPP_TEST_AUDIT_ACTIVE", active)
        restore()
        io.stderr = stderr
        assert(table.concat(messages):find("audit: environment lookup CODEX_TOOL_CALL_ID", 1, true))
        setting = "after"
        local _, changed = opened(options)
        test.eq(changed.hit, nil)
        setting = "before"
        fs.writeFile(binary, "runtime two")
        local _, runtime = opened(options)
        test.eq(runtime.hit, nil)
    end)
end

function M.selectionAndPresentationDoNotChangePackageKeys()
    test.eq(
        cacheModule.flags({
            "alphatest",
            "--json",
            "--jobs=2",
            "--group=pair",
            "--scope=all",
            "--verbose",
            "--timings=5",
            "--no-color"
        }),
        ""
    )
    test.eq(cacheModule.flags({"betatest", "--exclude=gamma", "--exclude-group=external", "--color=always"}), "")
    test.eq(cacheModule.flags({"--lane=shared", "--future-result-option=1"}), "--lane=shared\0--future-result-option=1")
end

function M.closedContractsInvalidateFixturesGeneratedArtifactsAndChildPrograms()
    fixture(function(root, options, results, suites)
        fs.mkdir(root .. "/src")
        fs.mkdir(root .. "/build")
        fs.writeFile(root .. "/src/model.nupp", "return 1\n")
        fs.writeFile(root .. "/build/model.lua", "return 1\n")
        fs.writeFile(root .. "/child", "#!/bin/sh\nprintf first\n")
        assert(os.execute("chmod +x '" .. root .. "/child'") == 0)
        fs.writeFile(
            root .. "/tests/one/alphatest.lua",
            'return {passes = function() local child = io.popen("child"); assert(child) end}\n'
        )
        local policy = options.policies.one
        policy.closed, policy.compiled = true, root .. "/src"
        policy.inputs = {root .. "/src", root .. "/shared"}
        policy.optionalInputs = {root .. "/optional"}
        policy.commands = {root .. "/child"}
        local cache = opened(options)
        cache.save(results, suites)
        assert(select(2, opened(options)).hit, "closed child-process contract must reuse a pass")
        for _, path in ipairs({"src/model.nupp", "build/model.lua", "child", "shared"}) do
            local original = assert(fs.readFile(root .. "/" .. path))
            fs.writeFile(root .. "/" .. path, original .. "\n-- changed")
            test.eq(select(2, opened(options)).hit, nil, path)
            fs.writeFile(root .. "/" .. path, original)
        end
        os.remove(root .. "/build/model.lua")
        fs.mkdir(root .. "/build/model.lua")
        test.eq(
            next(assert(cacheModule.open(options)).packages),
            nil,
            "an unreadable compiled artifact is not a missing file"
        )
        os.remove(root .. "/build/model.lua", true)
        fs.writeFile(root .. "/build/model.lua", "return 1\n")
        fs.writeFile(root .. "/optional", "now present")
        test.eq(select(2, opened(options)).hit, nil, "new optional input")
        os.remove(root .. "/optional")
        policy.commands = {root .. "/not-installed"}
        test.eq(select(2, opened(options)).hit, nil, "changed program availability")
        policy.commands = {}
        test.eq(next(assert(cacheModule.open(options)).packages), nil, "opaque execution requires a complete contract")
    end)
end

function M.compiledImagesAreExplicitPackageInputs()
    fixture(function(root, options, results, suites)
        fs.mkdir(root .. "/src")
        fs.writeFile(root .. "/src/model.nupp", "return 1\n")
        fs.writeFile(root .. "/compiler.image", "first image")
        local policy = options.policies.one
        policy.closed, policy.compiled = true, root .. "/src"
        policy.inputs = {root .. "/src", root .. "/shared"}
        policy.commands = {"sh"}
        policy.images = {root .. "/compiler.image"}
        local cache = opened(options)
        cache.save(results, suites)
        assert(select(2, opened(options)).hit, "unchanged image reuses the package")
        fs.writeFile(root .. "/compiler.image", "second image")
        test.eq(select(2, opened(options)).hit, nil, "changed image invalidates the package")
        os.remove(root .. "/compiler.image")
        test.eq(next(assert(cacheModule.open(options)).packages), nil, "missing image disables reuse")
    end)
end

function M.postRunChangesCannotPublishPassingResults()
    fixture(function(root, options, results, suites)
        local cache, entry = opened(options)
        fs.writeFile(root .. "/shared", "edited while tests ran")
        cache.save(results, suites)
        test.eq(fs.readFile(entry.path), nil, "post-run snapshot must read input bytes again")
    end)
end

function M.sourceMembershipIncludesUntrackedFilesAndExcludesGeneratedOutput()
    fixture(function(root, options, results, suites)
        assert(os.execute("git -C '" .. root .. "' init -q") == 0)
        fs.mkdir(root .. "/src")
        fs.writeFile(root .. "/src/model.nupp", "return 1\n")
        fs.writeFile(root .. "/.gitignore", "generated/\n")
        options.policies.one.sources = {"src"}
        local cache, entry = opened(options)
        cache.save(results, suites)
        assert(select(2, opened(options)).hit)
        fs.mkdir(root .. "/generated")
        fs.writeFile(root .. "/generated/output", "not source")
        assert(select(2, opened(options)).hit, "ignored build output must not invalidate source membership")
        fs.writeFile(root .. "/src/another.nupp", "return 2\n")
        test.eq(select(2, opened(options)).hit, nil, "new untracked source must invalidate")
        os.remove(root .. "/src/another.nupp")
        assert(select(2, opened(options)).hit)
        os.remove(root .. "/src/model.nupp")
        test.eq(next(assert(cacheModule.open(options)).packages), nil, "missing source root must refuse reuse")
    end)
end

function M.provisionedToolchainArtifactsInvalidateClosedContracts()
    fixture(function(root, options, results, suites)
        local getenv = os.getenv
        local prefix = root .. "/tools"
        fs.mkdir(root .. "/src")
        fs.mkdir(prefix .. "/luajit/bin")
        fs.writeFile(root .. "/src/model.nupp", "return 1\n")
        fs.writeFile(prefix .. "/luajit/bin/luajit", "interpreter one")
        os.getenv = function(name)
            if name == "NUPP_LAUNCHER_TOOLCHAIN_PREFIX" then
                return prefix
            end
            return getenv(name)
        end
        local policy = options.policies.one
        policy.closed, policy.toolchain, policy.compiled = true, true, root .. "/src"
        policy.inputs, policy.commands = {root .. "/src"}, {"sh", "pwd"}
        local cache = opened(options)
        cache.save(results, suites)
        assert(select(2, opened(options)).hit)
        fs.writeFile(prefix .. "/luajit/bin/luajit", "interpreter two")
        test.eq(select(2, opened(options)).hit, nil, "provisioned executable bytes")
        fs.writeFile(prefix .. "/luajit/bin/luajit", "interpreter one")
        assert(select(2, opened(options)).hit)
        fs.mkdir(prefix .. "/lpeg")
        fs.writeFile(prefix .. "/lpeg/module.so", "new native module")
        test.eq(select(2, opened(options)).hit, nil, "new provisioned native module")
    end)
end

function M.realRunnerReusesPackagesAcrossSelectionsAndRerunsOnlyChangedPackages()
    fixture(function(root)
        local process = require("nupp.compiler.process")
        local nupp = require("helpers.paths").root .. "/bin/nupp"
        fs.mkdir(root .. "/tests/two")
        fs.writeFile(root .. "/tests/cache.lua", assert(fs.readFile("tests/cache.lua")))
        fs.writeFile(root .. "/tests/one/alphatest.lua", "return {passes = function() assert(true) end}\n")
        fs.writeFile(root .. "/tests/two/betatest.lua", "return {passes = function() assert(true) end}\n")
        fs.writeFile(
            root .. "/tests/groups.lua",
            'return {pair = {"alphatest", "betatest"}}, {packages = {one = {cache = true}, two = {cache = true}}}\n'
        )

        local function age(path)
            assert(os.execute("touch -t 200001010000 '" .. path .. "'") == 0)
        end

        age(root .. "/tests/one/alphatest.lua")
        age(root .. "/tests/one/fixture")
        age(root .. "/tests/two/betatest.lua")

        local function run(arguments)
            local argv = {nupp, "test", "--internal-runner", "--json"}
            for _, value in ipairs(arguments) do
                argv[#argv + 1] = value
            end
            local output, errors = root .. "/report.json", root .. "/stderr"
            local command = process.command(argv, {
                cwd = root,
                env = {NUPP_TEST_BUILD = root .. "/build"}
            }) .. " >" .. process.quote(output) .. " 2>" .. process.quote(errors)
            local status = os.execute(command)
            assert(status == 0 or status == true, fs.readFile(errors))

            return json.decode(assert(fs.readFile(output)))
        end

        local cold = run({"--group=pair", "--jobs=1"})
        test.eq(cold.passed, 2)
        test.eq(cold.cached, 0)
        local hit = run({"betatest", "alphatest", "--jobs=4", "--verbose"})
        test.eq(hit.passed, 0)
        test.eq(hit.cached, 2)
        test.eq(hit.cachedPackages, 2)
        fs.writeFile(root .. "/tests/two/betatest.lua", "return {passes = function() assert(1 + 1 == 2) end}\n")
        age(root .. "/tests/two/betatest.lua")
        local changed = run({"--group=pair", "--jobs=1"})
        test.eq(changed.passed, 1)
        test.eq(changed.cached, 1)
        test.eq(changed.cachedPackages, 1)
        local fresh = run({"--group=pair", "--jobs=1", "--fresh"})
        test.eq(fresh.passed, 2)
        test.eq(fresh.cached, 0)
    end)
end

function M.ignoredRuntimeSourcesStillInvalidateExplicitInputRoots()
    fixture(function(root, options, results, suites)
        assert(os.execute("git -C '" .. root .. "' init -q") == 0)
        fs.mkdir(root .. "/src")
        fs.writeFile(root .. "/src/model.nupp", "return 1\n")
        fs.writeFile(root .. "/src/runtime.lua", "return 1\n")
        fs.writeFile(root .. "/.gitignore", "src/*.lua\n")
        options.policies.one.sources = {"src"}
        options.policies.one.inputs = {root .. "/src"}
        local cache = opened(options)
        cache.save(results, suites)
        assert(select(2, opened(options)).hit)
        fs.writeFile(root .. "/src/runtime.lua", "return 2\n")
        test.eq(select(2, opened(options)).hit, nil, "Git ignores must not hide executed source inputs")
    end)
end

function M.repositoryPackagesHaveExplicitContractsOrExclusions()
    local _, policy = assert(loadfile("tests/groups.lua"))()
    local catalog, selected, directories = {}, {}, {}
    for _, path in ipairs(
        fs.listFiles("tests", function(name)
            return name == "fixtures" or name == "helpers"
        end)
    ) do
        if path:match("test%.lua$") or path:match("test%.nupp$") then
            local relative = path:sub(#"tests/" + 1)
            local name = path:match("([^/]+)%.[^.]+$")
            local directory = relative:match("^(.*)/") or "."
            assert(policy.packages[directory], "missing package policy: " .. directory)
            local contract = policy.packages[directory]
            assert(contract.cache or type(contract.reason) == "string", "missing exclusion reason: " .. directory)
            directories[directory] = true
            catalog[#catalog + 1] = {name = name, path = relative}
            selected[#selected + 1] = {name = name}
        end
    end
    local cache = assert(
        cacheModule.open({
            root = "tests",
            build = "build",
            json = json,
            catalog = catalog,
            selected = selected,
            policies = policy.packages,
            runner = "contract-validation",
            flags = ""
        })
    )
    local enabled, unresolved = 0, {}
    for directory in pairs(directories) do
        if policy.packages[directory].cache then
            if not cache.packages[directory] then
                unresolved[#unresolved + 1] = directory .. ": " .. tostring(cache.reasons[directory])
            end
            enabled = enabled + 1
        end
    end
    table.sort(unresolved)
    assert(#unresolved == 0, table.concat(unresolved, "\n"))
    assert(enabled > 100, "repository cache rollout must cover ordinary packages, not only a pilot")
end

function M.sourceAnalysisIsReusedByContentWhilePackagesInvalidateIndependently()
    fixture(function(root, options, results, suites)
        fs.mkdir(root .. "/tests/two")
        fs.writeFile(root .. "/tests/two/betatest.lua", 'return {passes = function() end}\n')
        options.catalog[2] = {name = "betatest", path = "two/betatest.lua"}
        options.selected[2] = {name = "betatest"}
        -- Share one declared input contract, keeping separate package results.
        options.policies.two = options.policies.one
        results[2] = {suite = "betatest", name = "passes", id = "betatest/passes", status = "passed", durationMs = 1}
        suites[2] = {suite = "betatest", tests = 1}
        local cache = assert(cacheModule.open(options))
        cache.save(results, suites)
        local parser = require("nupp.compiler.syntax.parser")
        local original, parses = parser.parse, 0
        parser.parse = function(...)
            parses = parses + 1
            return original(...)
        end
        local ok, why = pcall(function()
            local warm = assert(cacheModule.open(options))
            assert(warm.packages.one.hit and warm.packages.two.hit)
            test.eq(parses, 0, "unchanged source analysis comes from the content store")
            fs.writeFile(root .. "/tests/one/alphatest.lua", 'require("helpers.missing")\nreturn {}\n')
            local changed = assert(cacheModule.open(options))
            assert(parses > 0, "changed source must be analyzed again")
            test.eq(changed.packages.one, nil, "an unresolved new dependency cannot reuse a passing result")
            assert(changed.packages.two.hit, "another package retains its own fingerprint")
            fs.writeFile(root .. "/shared", "changed shared input")
            local shared = assert(cacheModule.open(options))
            assert(not shared.packages.two.hit, "a shared contract change invalidates its readers")
        end)
        parser.parse = original
        assert(ok, why)
    end)
end

return M
