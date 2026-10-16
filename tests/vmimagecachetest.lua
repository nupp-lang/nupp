-- The VM images `nupp run` keeps between processes.
--
-- A module the VM's own image does not carry is checked and lowered from source
-- whenever a program requires it. The cache in `nupp.compiler.vm.imagecache` keeps
-- what that produced, and these cases hold it to the one property a cache must
-- have: an entry is believed exactly while everything it was computed from is
-- unchanged, and anything wrong with an entry costs a compile and nothing else.
--
-- Each case makes a fresh environment where a new process would, because that is
-- the boundary the cache is for: within one environment the modules it loaded
-- are already its answer.
local compile = require("nupp.tools.cli.compile")
local imagecache = require("nupp.compiler.vm.imagecache")
local envMod = require("nupp.compiler.project.env")
local check = require("nupp.compiler.check")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local ROOT = assert(HERE:match("^(.*)/[^/]+$"), "tests directory has no parent")

local function write(path, text)
    local sub = path:match("^(.*)/[^/]+$")
    if sub then
        assert(os.execute("mkdir -p '" .. sub .. "'") == 0)
    end
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function read(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local text = file:read("*a")
    file:close()
    return text
end

local function tempProject(files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    for name, text in pairs(files) do
        write(dir .. "/" .. name, text)
    end
    return dir
end

local function remove(dir)
    os.execute("rm -rf '" .. dir .. "'")
end

local LIB = [[
module lib

local lib = {}

function lib.double(value: number): number
    return value * 2
end

export = lib
]]

local MAIN = [[
local lib = require("lib")
print(lib.double(21))
]]

local function project()
    return tempProject({
        ["nupp.lua"] = 'return {include = {"src"}}\n',
        ["src/lib.nupp"] = LIB,
        ["main.nupp"] = MAIN,
    })
end

-- A fresh environment over `dir`, the way the next process makes one, keeping its
-- stores where the case can find them.
local function environment(dir)
    return envMod.new(dir, {cacheDir = dir .. "/cache"})
end

-- Counts the checks run while `fn` does, which is what a hit is supposed to skip.
local function counting(fn)
    local original = check.check
    local count = 0
    check.check = function(...)
        count = count + 1
        return original(...)
    end
    local ok, a, b = pcall(fn)
    check.check = original
    assert(ok, tostring(a))
    return count, a, b
end

local function snapshot()
    local copy = {}
    for key, value in pairs(imagecache.stats) do
        copy[key] = value
    end
    return copy
end

local function delta(before, key)
    return imagecache.stats[key] - before[key]
end

local function entries(dir)
    local pipe = assert(io.popen("ls '" .. dir .. "/cache/vm-images' 2>/dev/null"))
    local names = {}
    for name in pipe:lines() do
        if name:match("%.buf$") then
            names[#names + 1] = dir .. "/cache/vm-images/" .. name
        end
    end
    pipe:close()
    return names
end

local M = {}

function M.aSecondEnvironmentReadsTheImageInsteadOfCheckingAgain()
    local dir = project()
    local main = dir .. "/main.nupp"
    local before = snapshot()
    local checks, first = counting(function()
        return compile.image(main, environment(dir), nil)
    end)
    assert(type(first) == "string" and first ~= "", "the program compiled")
    assert(checks > 0, "a cold compile checks")
    assert(delta(before, "stores") == 1, "the image was kept")

    before = snapshot()
    -- Made outside the count: an environment checks its prelude when it has no
    -- stored one, and that is not the module's check.
    local env = environment(dir)
    local again, second = counting(function()
        return compile.image(main, env, nil)
    end)
    assert(delta(before, "hits") == 1, "the kept image was found")
    assert(again == 0, "a hit checks nothing, but checked " .. again .. " times")
    assert(second == first, "the kept image is the image compiling produced")
    remove(dir)
end

function M.editingTheModuleItselfMisses()
    local dir = project()
    local main = dir .. "/main.nupp"
    compile.image(main, environment(dir), nil)
    write(main, MAIN .. "print(lib.double(1))\n")
    local before = snapshot()
    local checks, image = counting(function()
        return compile.image(main, environment(dir), nil)
    end)
    assert(delta(before, "hits") == 0, "an edited module is a different entry")
    assert(checks > 0 and image ~= nil, "the edit was compiled")
    remove(dir)
end

-- The case the key alone cannot see: the module's bytes are the same, and what
-- it was checked against is not.
function M.editingADependencyInvalidatesTheModulesThatRequireIt()
    local dir = project()
    local main = dir .. "/main.nupp"
    local first = compile.image(main, environment(dir), nil)
    assert(first, "the program compiled")
    write(dir .. "/src/lib.nupp", LIB:gsub("value %* 2", "value * 2 + 0"))
    local before = snapshot()
    local checks = counting(function()
        return compile.image(main, environment(dir), nil)
    end)
    assert(delta(before, "hits") == 0, "a changed dependency must not hit")
    assert(delta(before, "misses") == 1, "it is a miss")
    assert(checks > 0, "the module was checked again")

    -- And the rewritten entry is believed again once nothing changes.
    before = snapshot()
    counting(function()
        return compile.image(main, environment(dir), nil)
    end)
    assert(delta(before, "hits") == 1, "the recompiled entry is kept")
    remove(dir)
end

-- A dependency's type is part of what a check saw: changing it must reach the
-- module whose own text did not move, rather than serve an image checked against
-- the old interface.
function M.aDependencysInterfaceChangeReachesItsRequirers()
    local dir = project()
    local main = dir .. "/main.nupp"
    assert(compile.image(main, environment(dir), nil), "the program compiled")
    write(dir .. "/src/lib.nupp", LIB:gsub("value: number%): number", "value: string): string"):gsub("value %* 2", "value"))
    local before = snapshot()
    local image = compile.image(main, environment(dir), nil, {})
    assert(delta(before, "hits") == 0, "an image checked against the old interface was served")
    assert(image == nil, "the program no longer checks")
    remove(dir)
end

-- The checker asks the carried modules about names a project file also provides:
-- `nupp`, beside a project's own `nupp.lua`, is one. Such a name is still the same
-- name in the next process, and an entry that recorded it must still be believed.
function M.aCarriedLookupOfAProjectNameStillHits()
    local dir = project()
    local main = dir .. "/main.nupp"
    local env = environment(dir)
    assert(env.bundled["lib"] == false, "nothing carries lib")
    assert(compile.image(main, env, nil), "the program compiled")
    env = environment(dir)
    assert(env.bundled["lib"] == false, "nothing carries lib")
    local before = snapshot()
    compile.image(main, env, nil)
    assert(delta(before, "hits") == 1, "the same lookups in the next process must hit")
    remove(dir)
end

function M.aFileThatNowShadowsADependencyMisses()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"src"}}\n',
        ["src/lib/init.nupp"] = LIB,
        ["main.nupp"] = MAIN,
    })
    local main = dir .. "/main.nupp"
    assert(compile.image(main, environment(dir), nil), "the program compiled")
    -- `lib.nupp` comes before `lib/init.nupp` in the search, so the name now means it.
    write(dir .. "/src/lib.nupp", LIB)
    local before = snapshot()
    compile.image(main, environment(dir), nil)
    assert(delta(before, "hits") == 0, "the name resolves somewhere else now")
    remove(dir)
end

function M.aCorruptEntryIsCompiledAgainAndReplaced()
    local dir = project()
    local main = dir .. "/main.nupp"
    local first = compile.image(main, environment(dir), nil)
    local kept = entries(dir)
    assert(#kept == 1, "one entry was written, found " .. #kept)
    for _, damage in ipairs({
        "not an entry at all",
        "",
        (read(kept[1]):gsub("print", "PRINT")),
        read(kept[1]):sub(1, 40),
    }) do
        write(kept[1], damage)
        local before = snapshot()
        local checks, image = counting(function()
            return compile.image(main, environment(dir), nil)
        end)
        assert(delta(before, "hits") == 0, "a damaged entry was believed")
        assert(checks > 0 and image == first, "a damaged entry costs a compile and changes nothing")
    end
    local before = snapshot()
    compile.image(main, environment(dir), nil)
    assert(delta(before, "hits") == 1, "the compile replaced the damaged entry")
    remove(dir)
end

-- A hit says nothing, so a module whose check said something is not kept: its
-- warning would be reported once and then never again.
function M.aCheckThatReportedSomethingIsNotKept()
    local dir = project()
    write(dir .. "/main.nupp", MAIN .. "local unused = 1\n")
    local main = dir .. "/main.nupp"
    local before = snapshot()
    local diagnostics = {}
    assert(compile.image(main, environment(dir), nil, diagnostics), "a warning does not stop the compile")
    assert(#diagnostics > 0, "the fixture reports a warning")
    assert(delta(before, "stores") == 0, "a check with something to say was kept")
    remove(dir)
end

-- What the stamp is on the VM: the running image. A fresh instance of the module
-- believes it is running from an image, as it does on the VM, with the runtime's
-- answers in place of the runtime: `identity` for the whole image and `describe`,
-- when given, for its modules. `ask` receives the fresh module.
--
-- On the VM the instance is lowered from the module's source with those answers as
-- its globals (`providerstate`); under LuaJIT the module the build generated is
-- loaded under its source's chunk name with them set on `_G`.
local function onTheVm(identity, describe, ask)
    if rawget(_G, "__nupp_load_image") ~= nil then
        local name = "nupp.compiler.project.fingerprint"
        local fresh = require("providerstate").instance({[name] = true}, nil, nil, {
            __nupp_load_image = rawget(_G, "__nupp_load_image"),
            __nupp_image_identity = identity and function()
                return identity
            end or nil,
            __nupp_image_modules = describe,
        })(name)
        return ask(fresh)
    end
    local source = assert(read(ROOT .. "/build/nupp/compiler/project/fingerprint.lua"))
    local chunk = assert(loadstring(source, "@" .. ROOT .. "/src/nupp/compiler/project/fingerprint.nupp"))
    local names = {"__nupp_load_image", "__nupp_image_identity", "__nupp_image_modules"}
    local saved = {}
    for index, name in ipairs(names) do
        saved[index] = rawget(_G, name)
    end
    rawset(_G, "__nupp_load_image", function() end)
    rawset(_G, "__nupp_image_identity", identity and function()
        return identity
    end or nil)
    rawset(_G, "__nupp_image_modules", describe)
    local ok, answer = pcall(function()
        return ask(chunk())
    end)
    for index, name in ipairs(names) do
        rawset(_G, name, saved[index])
    end
    assert(ok, tostring(answer))
    return answer
end

local function vmFingerprint(identity)
    return onTheVm(identity, nil, function(fingerprint)
        return fingerprint.toolFingerprint()
    end)
end

function M.onTheVmTheCompilerIsStampedWithItsImage()
    local first = vmFingerprint("a")
    assert(vmFingerprint("a") == first, "one image is one stamp")
    assert(vmFingerprint("b") ~= first, "another image is another stamp")
    -- A runtime that cannot name its image shares a stamp with nobody.
    assert(vmFingerprint(nil) ~= vmFingerprint(nil), "an unidentified image must not reuse stamps")
end

-- An image as `vm.imageModules` describes one: the module build reaches the
-- checker, and a command reaches the module build. `digests` overrides a module's
-- digest, which is what rebuilding the image after an edit to it does.
local function describing(digests, unknown)
    return function()
        local graph = {
            digests = {
                ["nupp.tools.cli.explain"] = "explain",
                ["nupp.tools.build.modules"] = "modules",
                ["nupp.compiler.check"] = "check",
                ["nupp.compiler.types"] = "types",
            },
            edges = {
                ["nupp.tools.cli.explain"] = {"nupp.tools.build.modules"},
                ["nupp.tools.build.modules"] = {"nupp.compiler.check"},
                ["nupp.compiler.check"] = {"nupp.compiler.types"},
                ["nupp.compiler.types"] = {},
            },
            unknown = {},
        }
        for name in pairs(graph.digests) do
            graph.digests[name] = (digests or {})[name] or graph.digests[name]
            graph.unknown[name] = (unknown or {})[name] == true
        end
        return graph
    end
end

-- The stamp the module build's records are kept under, on an image described by
-- `describe` whose whole identity is `identity`.
local function recordStamp(identity, describe)
    return onTheVm(identity, describe, function(fingerprint)
        return fingerprint.subsystemFingerprint({"nupp.tools.build.modules"})
    end)
end

-- Stores a record under the stamp one image gives and asks whether the next image
-- still finds it, the way a check's records are kept between two CLIs.
local function survives(first, second)
    local store = require("nupp.compiler.project.store")
    local dir = tempProject({})
    local path = dir .. "/checks.buf"
    local written = store.openValue(path, recordStamp("first image", first))
    written.set({checked = true})
    written.save()
    local found = store.openValue(path, recordStamp("second image", second)).value
    remove(dir)
    return found ~= nil and found.checked == true
end

function M.anImageEditOutsideTheCheckerKeepsCheckRecords()
    assert(survives(describing(), describing({["nupp.tools.cli.explain"] = "explain, edited"})),
        "a command's edit went cold")
end

function M.anImageEditToTheCheckerDiscardsCheckRecords()
    assert(not survives(describing(), describing({["nupp.compiler.types"] = "types, edited"})),
        "a record outlived the checker that wrote it")
    assert(not survives(describing(), describing({["nupp.tools.build.modules"] = "modules, edited"})),
        "a record outlived the module build that wrote it")
end

function M.aRuntimeThatCannotDescribeItsImageStampsWithTheWholeImage()
    assert(recordStamp("a", nil) == vmFingerprint("a"), "the narrow stamp needs the description")
    assert(recordStamp("a", nil) ~= recordStamp("b", nil), "any image edit is a new stamp")
    assert(not survives(nil, nil), "two images shared a stamp without a description")
    -- A description that is not one is the same as none.
    local broken = function()
        return {digests = {["nupp.compiler.check"] = "check"}, edges = {["nupp.compiler.check"] = {"absent"}}, unknown = {}}
    end
    assert(recordStamp("a", broken) == vmFingerprint("a"), "a broken description was believed")
    assert(recordStamp("a", function()
        error("no image")
    end) == vmFingerprint("a"), "a failing description was believed")
end

-- A module that loads what its edges do not name could be running any code in the
-- image, so a subsystem reaching it is stamped with all of it.
function M.anIncompleteReachFallsBackToTheWholeImage()
    local incomplete = describing(nil, {["nupp.compiler.check"] = true})
    assert(recordStamp("a", incomplete) == vmFingerprint("a"), "an incomplete reach was narrowed")
    -- What does not reach it stays narrow.
    local typesOnly = onTheVm("a", incomplete, function(fingerprint)
        return fingerprint.subsystemFingerprint({"nupp.compiler.types"})
    end)
    assert(typesOnly ~= vmFingerprint("a"), "an unrelated incomplete module widened the stamp")
end

return M
