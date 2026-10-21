-- Existing VM call contracts, independent of any inlining experiment.
local test = require("nupp.test")
local compile = require("nupp.tools.cli.compile")
local envMod = require("nupp.compiler.project.env")
local lower = require("nupp.compiler.vm.lower")
local program = require("program")

local COUNTER = "__nuppVmPredicateCallInitialization"
local serial = 0
local PROVIDER = [[
module PROVIDER
export function present(value: any): boolean
    return value.tag ~= nil
end
]]
local QUALIFIED = [[
module QUALIFIED
local global: any = _G
global.__nuppVmPredicateCallInitialization = (global.__nuppVmPredicateCallInitialization or 0) + 1
export function present(value: any): boolean
    return value.tag ~= nil
end
]]
local CONSUMER = [[
module ENTRY
const P = require("PROVIDER")
local main = {}
local record Tagged
    tag: any
end
local record Other
    other: integer
end
function main.present(value: any): boolean
    local result = P.present(value)
    return result
end
function main.recordPresent(): boolean
    local value = new Tagged(tag = false)
    local result = P.present(value)
    return result
end
function main.recordMissing(): boolean
    local value = new Other(other = 1)
    local result = P.present(value)
    return result
end
function main.recordMetatable(): boolean
    local value = new Tagged(tag = nil)
    setmetatable(value as any, {__index = {tag = false}})
    local result = P.present(value)
    return result
end
function main.qualified(value: any): boolean
    local result = QUALIFIED.present(value)
    return result
end
export = main
]]

local function write(path, source)
    local file = assert(io.open(path, "wb"))
    file:write(source)
    file:close()
end

local function withProject(callback, separateProvider)
    serial = serial + 1
    local names = {
        PROVIDER = "vmpredicatecallprovider" .. serial,
        QUALIFIED = "vmpredicatecallqualified" .. serial,
        ENTRY = "vmpredicatecallentry" .. serial,
    }

    local function expand(source)
        return (source:gsub("PROVIDER", names.PROVIDER):gsub("QUALIFIED", names.QUALIFIED):gsub("ENTRY", names.ENTRY))
    end

    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/src")) == 0)
    write(dir .. "/nupp.lua", 'return {include = {"src"}}\n')
    local paths = {}
    for key, source in pairs({PROVIDER = PROVIDER, QUALIFIED = QUALIFIED, ENTRY = CONSUMER}) do
        paths[names[key]] = dir .. "/src/" .. names[key] .. ".nupp"
        write(paths[names[key]], expand(source))
    end
    local originalCounter = rawget(_G, COUNTER)
    local originalProvider = package.loaded[names.PROVIDER]
    local originalQualified = package.loaded[names.QUALIFIED]
    local originalPreload = package.preload[names.QUALIFIED]
    rawset(_G, COUNTER, 0)
    local ok, problem = pcall(function()
        local function checkedGraph(entry, selected)
            local env = envMod.new(dir, {cacheDir = dir .. "/cache"})
            local parses = {}

            local function parsed(name, path)
                if not parses[name] then
                    local diagnostics = {}
                    local result = compile.check(path, env, {moduleName = name}, diagnostics)
                    assert(result, tostring(diagnostics[1] and diagnostics[1].msg))
                    result.root.vmModuleExports = result.moduleExports
                    parses[name] = result
                end

                return parses[name].root
            end

            parsed(entry, paths[entry])
            local listing = {}
            -- The image's record layouts and function count, from the
            -- header and functions the lowering hands its image.
            local layout
            lower.graphSink = function(emitted, functions, header)
                if emitted == entry then
                    local shapes = {}
                    for _, shape in ipairs(header.shapes) do
                        local slots = {}
                        for _, slot in ipairs(shape.slots) do
                            slots[#slots + 1] = slot.name .. ":" .. tostring(slot.ty)
                        end
                        shapes[#shapes + 1] = tostring(shape.name) .. " " .. table.concat(slots, " ")
                    end
                    layout = {shapes = table.concat(shapes, "\n"), functions = #functions}
                end
            end
            local ok, image = pcall(
                lower.emit,
                entry,
                {},
                function(name)
                    return (not selected or selected[name]) and paths[name] or nil
                end,
                parsed,
                nil,
                listing
            )
            lower.graphSink = nil
            assert(ok, image)

            return image, parses, listing, layout
        end

        local providerImage, _, _, providerLayout = checkedGraph(names.PROVIDER, {[names.PROVIDER] = true})
        -- Body patches track layouts for images loaded one module at a time.
        -- Leave the provider outside the consumer image in that fixture so its
        -- standalone registration remains the baseline for the later patch.
        local selected = separateProvider and {[names.ENTRY] = true, [names.QUALIFIED] = true} or nil
        local image, parses, listing = checkedGraph(names.ENTRY, selected)
        local api
        if program.onVm() then
            local loadImage = assert(rawget(_G, "__nupp_load_image"))
            if separateProvider then
                assert(loadImage(providerImage))()
            end
            api = assert(loadImage(image))()
        else
            -- Lua is an oracle for the ordinary call semantics. Its generator
            -- may bind a qualified module earlier than the VM does.
            package.loaded[names.PROVIDER] = program.run(parses[names.PROVIDER], names.PROVIDER, paths[names.PROVIDER])
            package.loaded[names.QUALIFIED] = nil
            package.preload[names.QUALIFIED] = function()
                return program.run(parses[names.QUALIFIED], names.QUALIFIED, paths[names.QUALIFIED])
            end
            api = program.run(parses[names.ENTRY], names.ENTRY, paths[names.ENTRY])
        end
        callback(api, {
            names = names,
            paths = paths,
            listing = listing,
            initialProviderImage = providerImage,
            initialProviderLayout = providerLayout,
            providerSource = expand(PROVIDER),
            rebuildProvider = function(source)
                write(paths[names.PROVIDER], source)
                local image, _, _, layout = checkedGraph(names.PROVIDER, {[names.PROVIDER] = true})
                return image, layout
            end,
        })
    end)
    package.loaded[names.PROVIDER] = originalProvider
    package.loaded[names.QUALIFIED] = originalQualified
    package.preload[names.QUALIFIED] = originalPreload
    rawset(_G, COUNTER, originalCounter)
    assert(os.execute("rm -rf " .. string.format("%q", dir)) == 0)
    assert(ok, problem)
end

local M = {}

function M.importedPredicatePreservesFieldsAndObservableProviderFrame()
    withProject(function(api, state)
        test.equal(api.present({}), false)
        for _, value in ipairs({false, 0, "", true}) do
            test.equal(api.present({tag = value}), true)
        end
        test.equal(api.recordPresent(), true)
        test.equal(api.recordMissing(), false)
        test.equal(api.recordMetatable(), true)
        local calls, observed = 0, nil
        local receiver = setmetatable({}, {
            __index = function(_, key)
                test.equal(key, "tag")
                calls = calls + 1
                observed = debug.getinfo(2, "S").source
                return false
            end
        })
        test.equal(api.present(receiver), true)
        test.equal(calls, 1)
        assert(observed:find(state.names.PROVIDER, 1, true), "the provider frame remains visible: " .. observed)
        receiver.tag = 0
        test.equal(api.present(receiver), true)
        test.equal(calls, 1, "a stored field suppresses __index")
    end)
end

function M.qualifiedModuleInitializesExactlyOnce()
    withProject(function(api, state)
        local caller
        for _, fn in ipairs(state.listing) do
            if fn.name == "main.qualified" then
                caller = fn
            end
        end
        assert(caller, "qualified caller listing")
        local requires, calls = 0, 0
        for _, instruction in ipairs(caller.instructions) do
            if instruction.op == "Require" then
                requires = requires + 1
            end
            if instruction.op == "CallDyn" or instruction.op == "CallK" then
                calls = calls + 1
            end
        end
        assert(requires > 0 and calls > 0, "the caller retains its implicit require and function call")
        test.equal(api.qualified({tag = false}), true)
        test.equal(rawget(_G, COUNTER), 1)
        test.equal(api.qualified({}), false)
        test.equal(rawget(_G, COUNTER), 1, "a cached require does not repeat initialization")
    end)
end

function M.providerBodyPatchReachesAnAlreadyLoadedCaller()
    if not program.onVm() then
        -- The Lua runner has no in-process VM function-body patch surface.
        return require("assert").skip("provider body patching requires the VM")
    end
    local hotPatch = assert(rawget(_G, "__nupp_hot_patch"), "the VM exposes its body-patch API")
    withProject(
        function(api, state)
            local retainedCaller = api.present
            local retainedProvider = assert(package.loaded[state.names.PROVIDER]).present
            local receiver = {tag = false}
            test.equal(retainedCaller(receiver), true)
            local nextImage, nextLayout = state.rebuildProvider((state.providerSource:gsub("value%.tag", "value.other")))
            test.equal(
                nextLayout.shapes,
                state.initialProviderLayout.shapes,
                "a field-only body edit preserves every provider layout"
            )
            local count = nextLayout.functions
            test.equal(
                count,
                state.initialProviderLayout.functions,
                "a field-only body edit preserves function positions"
            )
            local map = {}
            for index = 0, count - 1 do
                map[#map + 1] = tostring(index)
            end
            local patch = "patch " .. state.names.PROVIDER .. "\nmap " .. table.concat(map, " ") .. "\n" .. nextImage
            local validation, reason = hotPatch(patch, true)
            assert(validation, reason)
            test.equal(retainedCaller(receiver), true, "validation leaves the current body running")
            local report, failure = hotPatch(patch)
            assert(report, failure)
            test.equal(report.changed, 1)
            test.equal(api.present, retainedCaller, "the consumer is not rebuilt")
            test.equal(
                package.loaded[state.names.PROVIDER].present,
                retainedProvider,
                "the provider retains its callable identity"
            )
            test.equal(retainedCaller(receiver), false, "the loaded caller enters the replacement body")
            receiver.other = 0
            test.equal(retainedCaller(receiver), true)
        end,
        true
    )
end

return M
