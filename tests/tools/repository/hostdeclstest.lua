-- The Nupp sources the Rust VM's crate held, and who may still read them there.
--
-- `native/crates/vm/{lib,decls}` held two kinds of file. Declarations of what the
-- runtime supplies natively (`nupp.vm.files`, `nupp.vm.clock`, ...) are read by
-- code that outlives the crate: the core's providers require those modules, and
-- the core answers them with its own (`nupp.compiler.vm.graphcalls`). They live
-- under `src/nupp/compiler/hostdecls`. Everything else there is what only the
-- Rust VM supplies or implements, read only by code deleted with it, and stays
-- to be deleted with the crate.
--
-- The pinned stage-zero image and core seeds were built from sources that read
-- the crate's copies by path, so those copies stay, unchanged, until a seed built
-- from a commit that reads `src/nupp/compiler/hostdecls` is pinned. Until then an
-- edit to a relocated declaration is made to both copies, or stage one, which the
-- seed checks against the old one, disagrees with the tree.
local ROOT = require("helpers.paths").absoluteTests .. "/.."

local M = {}

local HOME = "src/nupp/compiler/hostdecls"
local CRATE = "native/crates/vm"
-- This suite, whose cases spell the readings it refuses.
local SELF = "tests/tools/repository/hostdeclstest.lua"

-- The declarations that moved, by their path under either root.
local RELOCATED = {
    "nupp/compiler/nativecdecl.d.nupp",
    "nupp/vm/clock.d.nupp",
    "nupp/vm/cryptobinding.d.nupp",
    "nupp/vm/files.d.nupp",
    "nupp/vm/foreign.d.nupp",
    "nupp/vm/http.d.nupp",
    "nupp/vm/net.d.nupp",
    "nupp/vm/persist.d.nupp",
    "nupp/vm/process.d.nupp",
    "nupp/vm/storagebinding.d.nupp",
    "nupp/vm/systembinding.d.nupp",
    "nupp/vm/tasks.d.nupp",
    "nupp/vm/uri.d.nupp",
}

-- What stays in the crate and goes with it, under `lib` or `decls`: the VM's
-- own implementations, the declarations of modules only it supplies, and those
-- whose module the tree implements everywhere else.
local VM_ONLY = {
    ["decls/nupp/cli/internal/terminalhost.d.nupp"] = true,
    ["decls/nupp/compiler/hostpid.d.nupp"] = true,
    ["decls/nupp/compiler/nativehash.d.nupp"] = true,
    ["decls/nupp/digest/internal/sha256.d.nupp"] = true,
    ["decls/nupp/generator.d.nupp"] = true,
    ["decls/nupp/runtime/provider/nativestorage.d.nupp"] = true,
    ["decls/nupp/tasks.d.nupp"] = true,
    ["decls/nupp/tools/bytecodecache.d.nupp"] = true,
    ["decls/nupp/vm.d.nupp"] = true,
    ["decls/nupp/vm/coroutine.d.nupp"] = true,
    ["decls/nupp/vm/ownedCoroutine.d.nupp"] = true,
    ["decls/nupp/vm/snapshot.d.nupp"] = true,
    ["decls/nupp/vm/taskScope.d.nupp"] = true,
    ["lib/nupp/array/internal/storage.lua"] = true,
    ["lib/nupp/generator.nupp"] = true,
    ["lib/nupp/io/internal/nativebuffer.lua"] = true,
    ["lib/nupp/snapshot.nupp"] = true,
    ["lib/nupp/suspension/internal/coroutines.nupp"] = true,
    ["lib/nupp/tasks.nupp"] = true,
    ["lib/nupp/vm/arraylayout.lua"] = true,
    ["lib/nupp/vm/cryptobinding.nupp"] = true,
    ["lib/nupp/vm/math.nupp"] = true,
    ["lib/nupp/vm/simdbinding.nupp"] = true,
    ["lib/nupp/vm/storagebinding.nupp"] = true,
    ["lib/nupp/vm/systembinding.nupp"] = true,
}

-- The files outside the crate that may still name its sources, each of them
-- code that runs only on the Rust VM, or the part of a file that does.
local VM_ONLY_READERS = {
    ["bin/nupp"] = "what a VM compiler is built from",
    ["nupp.lua"] = "carries the declarations only the Rust VM supplies",
    ["src/nupp/compiler/bundled.nupp"] = "maps those carried declarations to their source",
    ["src/nupp/compiler/project/env.nupp"] = "declares what only the Rust VM supplies",
    ["src/nupp/compiler/runtime/init.nupp"] = "the VM's own spelling of a standard module",
    ["src/nupp/compiler/vm/legacylower.nupp"] = "the frozen VM lowering",
    ["src/nupp/core/produceridentity.nupp"] = "what the VM-hosted private producer reads",
    ["src/nupp/tools/build/package.nupp"] = "what a VM program's image builder read",
    ["src/nupp/tools/vm/project.nupp"] = "the VM image builder",
    ["tests/helpers/providerstate.lua"] = "resolves as the VM image builder does",
    ["tests/program.lua"] = "resolves as the VM image builder does",
    ["tests/tools/repository/nativeproducertest.lua"] = "the private producer's inventory",
    ["tests/vmsimdbindingtest.lua"] = "the VM's SIMD binding",
    ["tests/vmstandardrootloadertest.lua"] = "the VM's standard root loader",
}

local function read(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local text = file:read("*a")
    file:close()

    return text
end

-- Tracked and untracked files under `ROOT`, relative to it, from `pathspec`.
local function listed(pathspec)
    local listing = assert(
        io.popen(("git -C %q ls-files --cached --others --exclude-standard -z -- %s"):format(ROOT, pathspec))
    )
    local paths = {}
    for path in listing:read("*a"):gmatch("[^%z]+") do
        paths[#paths + 1] = path
    end
    listing:close()
    table.sort(paths)

    return paths
end

local function set(list)
    local result = {}
    for _, value in ipairs(list) do
        result[value] = true
    end

    return result
end

function M.theRelocatedDeclarationsAreTheWholeHome()
    local relocated = set(RELOCATED)
    local found = {}
    for _, path in ipairs(listed(HOME)) do
        local relative = path:sub(#HOME + 2)
        assert(relocated[relative], path .. " is not a relocated declaration; name it in RELOCATED")
        found[relative] = true
    end
    for _, relative in ipairs(RELOCATED) do
        assert(found[relative], HOME .. "/" .. relative .. " is missing")
    end
end

function M.thePinnedSeedsCopyMatchesTheRelocatedOne()
    for _, relative in ipairs(RELOCATED) do
        local old = read(ROOT .. "/" .. CRATE .. "/decls/" .. relative)
        if old ~= nil then
            assert(
                old == read(ROOT .. "/" .. HOME .. "/" .. relative),
                CRATE .. "/decls/" .. relative .. " differs from " .. HOME .. "/" .. relative
                    .. ": the pinned seeds read the crate's copy, so edit both until one reads " .. HOME
            )
        end
    end
end

function M.everythingLeftInTheCrateIsVmOnlyOrAFrozenCopy()
    local relocated = set(RELOCATED)
    local paths = listed(CRATE .. "/lib " .. CRATE .. "/decls")
    assert(#paths > 0, "the crate's sources were not found under " .. ROOT)
    for _, path in ipairs(paths) do
        local relative = path:sub(#CRATE + 2)
        local declaration = relative:match("^decls/(.*)$")
        assert(
            VM_ONLY[relative] or declaration and relocated[declaration],
            path .. " is neither VM-only nor a relocated declaration's frozen copy"
        )
    end
end

-- What `line` of `path` reads of the crate's sources that it may not.
local function refusals(path, number, line, relocated)
    local found = {}
    for directory, rest in line:gmatch("native/crates/vm/(%a+)([%w_/%.%-]*)") do
        if directory == "lib" or directory == "decls" then
            local named = rest:match("^/(.+)$")
            if not VM_ONLY_READERS[path] then
                found[#found + 1] = ("%s:%d reads %s/%s"):format(path, number, CRATE, directory .. rest)
            elseif named and directory == "decls" and relocated[named] then
                found[#found + 1] = ("%s:%d reads %s's old copy"):format(path, number, named)
            end
        end
    end
    -- A path built into the crate: `"/native/crates/vm/" .. directory`.
    if line:find("native/crates/vm/[\"']%s*%.%.") and not VM_ONLY_READERS[path] then
        found[#found + 1] = ("%s:%d builds a path into %s"):format(path, number, CRATE)
    end

    return found
end

function M.onlyVmOnlyCodeReadsTheCrateSources()
    local relocated = set(RELOCATED)
    local listing = assert(
        io.popen(
            ('git -C %q grep -n -I --untracked --exclude-standard -e native/crates/vm/ -- . ":!%s" ":!%s"'):format(
                ROOT,
                CRATE,
                SELF
            )
        )
    )
    local found = {}
    local lines = 0
    for path, number, line in listing:read("*a"):gmatch("([^\n:]+):(%d+):([^\n]*)") do
        lines = lines + 1
        for _, refusal in ipairs(refusals(path, tonumber(number), line, relocated)) do
            found[#found + 1] = refusal
        end
    end
    listing:close()
    assert(lines > 0, "nothing outside the crate names it, so the search did not run")
    assert(#found == 0, "only VM-only code may read the crate's sources:\n  " .. table.concat(found, "\n  "))
end

local function resources(target)
    local manifest = assert(loadfile(ROOT .. "/nupp.lua"))()

    return manifest.build.targets[target].resources
end

function M.theCompilerCarriesTheRelocatedCopies()
    for _, target in ipairs({"dist", "testRunner"}) do
        local carried = {}
        for _, resource in ipairs(resources(target)) do
            if type(resource) == "table" then
                local output = resource.output or ""
                local host = output:match("^nupp/compiler/hostdecls/(.*)$")
                local vm = output:match("^nupp/compiler/vmdecls/(.*)$")
                if host then
                    assert(resource.source == HOME .. "/" .. host, output .. " is carried from " .. resource.source)
                    carried[host] = true
                elseif vm then
                    assert(VM_ONLY["decls/" .. vm], output .. " is not VM-only; carry it from " .. HOME)
                    assert(resource.source == CRATE .. "/decls/" .. vm, output .. " is carried from " .. resource.source)
                end
            end
        end
        for _, relative in ipairs(RELOCATED) do
            assert(carried[relative], target .. " does not carry " .. HOME .. "/" .. relative)
        end
    end
end

function M.aCarriedDeclarationMapsBackToItsHome()
    local bundled = require("nupp.compiler.bundled")
    local saved = debug.getinfo
    debug.getinfo = function()
        return {source = "@" .. ROOT .. "/build/nupp/compiler/bundled.lua"}
    end
    local ok, host = pcall(bundled.sourcePathFor, "/hostdecls/nupp/vm/files.d.nupp")
    local vmOk, vm = pcall(bundled.sourcePathFor, "/vmdecls/nupp/generator.d.nupp")
    debug.getinfo = saved
    assert(ok, host)
    assert(vmOk, vm)
    assert(host == ROOT .. "/" .. HOME .. "/nupp/vm/files.d.nupp", host)
    assert(vm == ROOT .. "/" .. CRATE .. "/decls/nupp/generator.d.nupp", vm)
end

function M.theCheckoutDeclaresTheRuntimeFromItsHomeFirst()
    local envMod = require("nupp.compiler.project.env")
    local root = envMod.compilerRoot()
    if root == nil then
        return
    end
    local env = envMod.new(root)
    local roots = assert(env.vmDeclarations, "a checkout compiler declares what the runtime supplies")
    assert(roots[1]:sub(-#HOME - 1) == "/" .. HOME, roots[1])
    local declared = envMod.moduleNameForPath(env, roots[1] .. "/nupp/vm/files.d.nupp")
    assert(declared == "nupp.vm.files", tostring(declared))
end

-- The reading above has to be able to say no, or its passing says nothing.
function M.theReadingRefusesAnUnlistedReader()
    local relocated = set(RELOCATED)
    assert(not VM_ONLY_READERS["src/nupp/runtime/provider/nativefiles.nupp"], "a provider is not VM-only")
    for _, relative in ipairs(RELOCATED) do
        assert(not VM_ONLY["decls/" .. relative], relative .. " is both relocated and VM-only")
    end
    for relative in pairs(VM_ONLY) do
        local declaration = relative:match("^decls/(.*)$")
        assert(not (declaration and relocated[declaration]), relative)
    end
    local old = 'local path = root .. "/native/crates/vm/decls/nupp/vm/files.d.nupp"'
    assert(#refusals("src/nupp/runtime/provider/nativefiles.nupp", 1, old, relocated) == 1, "an unlisted reader")
    assert(#refusals("src/nupp/tools/vm/project.nupp", 1, old, relocated) == 1, "a reader of an old copy")
    local vm = 'return root .. "/native/crates/vm/lib/nupp/vm/simdbinding.nupp"'
    assert(#refusals("src/nupp/tools/vm/project.nupp", 1, vm, relocated) == 0, "a VM-only reader of VM-only code")
    local built = 'fs.listFiles(root .. "/native/crates/vm/" .. directory)'
    assert(#refusals("src/nupp/runtime/provider/nativefiles.nupp", 1, built, relocated) == 1, "a built path")
    local other = 'see `native/crates/vm/src/payload.rs`'
    assert(#refusals("docs/reference/distribution.md", 1, other, relocated) == 0, "the crate's Rust is not read here")
end

return M
