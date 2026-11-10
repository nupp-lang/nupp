-- Test-build catalog proof with only this caller/target's fixture exemptions
-- disabled after construction. No production catalog or export is changed.
local ROOT = assert(os.getenv("NUPP_COMPILER_ROOT"))
local STEP, MODE = arg[1] or "consumer", arg[2] or "normal"
local CLIENT, TARGET = "nupp.core.sharedlocalclient", "nupp.runtime.core.sharedbacking"
local KEY = TARGET .. ".releaselocal"
local OUT = ROOT .. "/build/core-units/shared-local-status"
local PATH = ROOT .. "/src/nupp/compiler/vm/nativeservice.nupp"
local compile = require("nupp.tools.cli.compile")
local env = require("nupp.compiler.project.env").new(ROOT, {cache = false})
local digest = require("nupp.compiler.project.fingerprint").contentDigest(true)
local json = require("serde.json")

local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function inject(source, anchor, replacement)
    local at = assert(source:find(anchor, 1, true), "strict hook anchor missing")
    assert(not source:find(anchor, at + #anchor, true), "strict hook anchor repeated")
    return source:sub(1, at - 1) .. replacement .. source:sub(at + #anchor)
end

local header = [[export function scopedCall(caller: any, node: any, dest: any, index: integer): any
    unit.call(caller, node, dest)
    unit.occurrence(caller, node)
]]
local hooks = [[local teststate: any = {}

export function teststrict(caller: string, dest: string, key: string, remove: boolean): nil
    need(teststate.caller == nil, "strict test context already active")
    teststate = {
        caller = caller, target = dest, key = key,
        callerunit = unitModules[caller], targetunit = unitModules[dest],
        policy = scopedPolicy[key], calls = 0
    }
    unitModules[caller], unitModules[dest] = nil, nil
    if remove then
        scopedPolicy[key] = nil
    end
end

export function teststrictcheck(): integer
    need(teststate.caller ~= nil, "strict test context missing")
    need(not unitModules[teststate.caller] and not unitModules[teststate.target], "strict test used unit exemption")
    return teststate.calls
end

export function teststrictrestore(): nil
    unitModules[teststate.caller] = teststate.callerunit
    unitModules[teststate.target] = teststate.targetunit
    scopedPolicy[teststate.key] = teststate.policy
    teststate = {}
end

]]
local check = [[    if teststate.caller == caller.scope.name
        and teststate.key == dest.scope.name .. "." .. dest.name
    then
        teststrictcheck()
        teststate.calls = teststate.calls + 1
    end
]]
local production = read(PATH)
local generated = inject(production, header, hooks .. header .. check)
os.execute("mkdir -p '" .. OUT .. "'")
if STEP == "prepare" then
    local diagnostics = {}
    local image = compile.image(PATH, env, "nupp.compiler.vm.nativeservice", diagnostics, generated)
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
    assert(image, "strict test override did not compile")
    write(OUT .. "/nativeservice.source", generated)
    write(OUT .. "/nativeservice.image", image)
    write(
        OUT .. "/preparation.json",
        json.encodevalue({
            production = digest(production),
            generated = digest(generated),
            image = digest(image),
            testBuildOnly = true,
            injectionAnchors = 1
        })
    )
    print("prepared exact test-only strict override")
    return
end
assert(read(OUT .. "/nativeservice.source") == generated, "strict override stale; run prepare")
local image = read(OUT .. "/nativeservice.image")
local preparation = json.decodevalue(read(OUT .. "/preparation.json"))
assert(preparation.production == digest(production) and preparation.generated == digest(generated))
assert(preparation.image == digest(image), "strict override image hash differs")
local service = require("nupp.compiler.vm.nativeservice")
local previous = service.scopedCall
local fresh = assert(__nupp_load_image(image))()
assert(fresh.scopedCall ~= previous and fresh.teststrict, "strict source override not installed")
for key, value in pairs(fresh) do
    service[key] = value
end
package.loaded["nupp.compiler.vm.nativeservice"] = service
local runner = require("nupp.core.unitrunner")
local unit = require("nupp.compiler.vm.nativeunit")
local lower = require("nupp.compiler.vm.lower")
local sink = require("nupp.compiler.s0.nativegraph")
local imports = require("nupp.compiler.vm.nativeos")
assert(imports.importCount() == 48, "current nativeos override required")
local active, captures, boundaryChecks = false, {}, 0

local function strict()
    if active then
        assert(not service.isUnitModule(CLIENT) and not service.isUnitModule(TARGET))
        service.teststrictcheck()
        boundaryChecks = boundaryChecks + 1
    end
end

local originalBuild = service.buildUnits
service.buildUnits = function(fixtures, roots, handlers)
    local build = originalBuild(fixtures, roots, handlers)
    if STEP ~= "producer" then
        service.teststrict(CLIENT, TARGET, KEY, STEP == "missing")
        active = true
        strict()
    end

    return build
end
local originalGraph = lower.functionGraph
lower.functionGraph = function(owner, options, profile)
    strict()
    local graph = originalGraph(owner, options, profile)
    strict()
    captures[owner.scope.name .. "." .. owner.name] = {graph = graph, owner = owner}

    return graph
end
local originalCompiler = sink.compilerGraph
sink.compilerGraph = function(...)
    strict()
    local result = originalCompiler(...)
    strict()
    return result
end
local module = STEP == "producer" and "nupp.core.sharedlocalproducer" or CLIENT
local fixtures = {
    {
        moduleName = module,
        path = ROOT .. "/tests/core/units/nupp/core/" .. module:match("[^.]+$") .. ".nupp",
        include = "tests/core/units"
    },
    {
        moduleName = "nupp.core.unitentry",
        path = ROOT .. "/tests/core/units/nupp/core/unitentry.nupp",
        include = "tests/core/units"
    }
}
local entries
if STEP == "producer" then
    entries = {{module, "produce", 1}}
elseif STEP == "wrong" then
    entries = {{CLIENT, "wrongpointee", 1}}
else
    entries = {{CLIENT, "success", 1}, {CLIENT, "failure", 1}, {CLIENT, "sticky", 1}}
end
-- No native code cache: each strict positive/negative must lower and verify.
local ok, result = pcall(runner.build, fixtures, entries, MODE, nil)
strict()
local calls = active and service.teststrictcheck() or 0
if STEP == "missing" or STEP == "wrong" then
    assert(not ok, "strict refusal unexpectedly compiled")
    local expected = STEP == "missing" and "plain call lacks reviewed scoped lifetime policy"
        or "local address must retain exact struct pointee"
    assert(tostring(result):find(expected, 1, true), tostring(result))
    if STEP == "missing" then
        assert(calls > 0, "missing policy did not reach strict call")
    end
else
    assert(ok, result)
    if STEP ~= "producer" then
        assert(calls >= 3, "strict scoped calls not observed")
        local allowed = {
            [CLIENT .. ".success"] = true,
            [CLIENT .. ".failure"] = true,
            [CLIENT .. ".sticky"] = true,
            [KEY] = true,
            [TARGET .. ".release"] = true,
            ["nupp.runtime.core.pagemappings.sharedscopevalid"] = true,
            ["nupp.runtime.core.pagemappings.sharedvalid"] = true,
            ["nupp.runtime.core.pagemappings.extent"] = true,
            ["nupp.runtime.core.pagemappings.overlap"] = true,
            ["nupp.runtime.core.pagemappings.sharedreferences"] = true,
            ["nupp.runtime.core.pagemappings.sharedcompare"] = true,
            ["nupp.runtime.core.pagemappings.releaseshared"] = true,
            ["nupp.runtime.core.servicescope.retain"] = true,
            ["nupp.runtime.core.servicescope.fail"] = true,
            ["nupp.runtime.core.servicescope.okay"] = true
        }
        local pending, seen = {CLIENT .. ".success", CLIENT .. ".failure", CLIENT .. ".sticky"}, {}
        while #pending > 0 do
            local name = table.remove(pending)
            if not seen[name] then
                seen[name] = true
                assert(allowed[name], "allocation/callback outside exact release closure: " .. name)
                local item = assert(captures[name], "uncaptured release graph: " .. name)
                local locals, released = 0, false
                for _, block in ipairs(item.graph.blocks) do
                    for at, op in ipairs(block.op) do
                        local args = block.args[at]
                        if op == "NativeLocal" then
                            locals = locals + 1
                            assert(item.owner.scope.name == CLIENT and block.id == 1 and args[1].layout.size == 56)
                            assert(not released, "status initialized after release")
                        elseif op == "NativeLeafCall" then
                            local declaration = args[1]
                            local target = declaration.moduleName .. "." .. declaration.name
                            if target == KEY then
                                assert(locals == 1, "release lacks preexisting local status")
                                released = true
                            end
                            pending[#pending + 1] = target
                        elseif op == "NativeHelperCall" then
                            local slot = imports.slot(args[1], item.owner)
                            assert(
                                slot == 1 or slot == 2 or slot == 46 or slot == 47,
                                "release closure allocates or calls unrelated OS"
                            )
                        end
                    end
                end
                if item.owner.scope.name == CLIENT then
                    assert(locals == 1 and released, "caller status ordering differs")
                end
            end
        end
        -- The reviewed adapter has one synchronous call and one plain formal cast.
        local adapter = assert(captures[KEY]).owner
        local count = 0
        for _, node in ipairs(unit.occurrences(adapter)) do
            if node.kind == "call" then
                local callee = assert(unit.callee(adapter, node))
                assert(callee.scope.name == TARGET and callee.name == "release")
                count = count + 1
            end
        end
        assert(count == 1, "adapter nonescape body changed")
    end
    write(OUT .. "/" .. STEP .. "-" .. MODE .. ".bundle", result.bundle)
end
local report = {
    step = STEP,
    mode = MODE,
    passed = true,
    testBuildCatalog = true,
    unitExemptionsDisabled = active,
    strictCalls = calls,
    strictBoundaryChecks = boundaryChecks,
    productionSource = digest(production),
    generatedSource = digest(generated),
    overrideImage = digest(image),
    bundle = ok and digest(result.bundle) or nil,
    refusal = not ok and tostring(result) or nil
}
if active then
    strict()
    service.teststrictrestore()
end
service.buildUnits, lower.functionGraph, sink.compilerGraph = originalBuild, originalGraph, originalCompiler
write(OUT .. "/" .. STEP .. "-" .. MODE .. ".json", json.encodevalue(report))
print(json.encodevalue(report))
