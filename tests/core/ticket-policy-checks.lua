-- Test-build catalog proof with only this caller/target's fixture exemptions
-- disabled after construction. No production catalog or export is changed.
local ROOT = assert(os.getenv("NUPP_COMPILER_ROOT"))
local STEP, MODE, OP = arg[1] or "consumer", arg[2] or "normal", arg[3] or "acquire"
local CLIENT, TARGET = "nupp.core.ticketstrict", "nupp.runtime.core.sharedbacking"
local KEY = TARGET .. ".ticket" .. OP
local OUT = ROOT .. "/build/core-units/ticket-strict"
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

export function teststrict(caller: string, dest: string, key: string): nil
    need(teststate.caller == nil, "strict test context already active")
    teststate = {
        caller = caller, target = dest, key = key,
        callerunit = unitModules[caller], targetunit = unitModules[dest],
        calls = 0
    }
    unitModules[caller], unitModules[dest] = nil, nil
end

export function teststrictcheck(): integer
    need(teststate.caller ~= nil, "strict test context missing")
    need(not unitModules[teststate.caller] and not unitModules[teststate.target], "strict test used unit exemption")
    return teststate.calls
end

export function teststrictrestore(): nil
    unitModules[teststate.caller] = teststate.callerunit
    unitModules[teststate.target] = teststate.targetunit
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
local active, captures, boundaryChecks, tampered = false, {}, 0, false

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
        service.teststrict(CLIENT, TARGET, KEY)
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
    if STEP == "tamper" and owner.scope.name == CLIENT and owner.name == OP then
        for _, block in ipairs(graph.blocks) do
            for at, op in ipairs(block.op) do
                local target = op == "NativeLeafCall" and block.args[at][1]
                if target and target.moduleName .. "." .. target.name == KEY then
                    local parameter = assert(target.physical.params[1])
                    assert(#parameter.ownership == 1 and parameter.ownership[1].tag == "borrowed")
                    parameter.ownership = {}
                    tampered = true
                end
            end
        end
    end

    return graph
end
local originalCompiler = sink.compilerGraph
sink.compilerGraph = function(...)
    strict()
    local result = originalCompiler(...)
    strict()
    return result
end
local module = CLIENT
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
local entries = {{CLIENT, STEP == "wrong" and "wrong" .. OP or OP, 1}}
-- No native code cache: each strict positive/negative must lower and verify.
local ok, result = pcall(runner.build, fixtures, entries, MODE, nil)
strict()
local calls = active and service.teststrictcheck() or 0
if STEP == "wrong" or STEP == "tamper" then
    assert(not ok, "strict refusal unexpectedly compiled")
    local expected = STEP == "wrong" and "local address must retain exact struct pointee" or "ownership changed"
    assert(tostring(result):find(expected, 1, true), tostring(result))
    assert(STEP ~= "tamper" or tampered, "borrow relation was not removed")
else
    assert(ok, result)
    if STEP ~= "producer" then
        assert(calls == 0, "checked borrow unexpectedly used a plain-formal exception")
        local item = assert(captures[CLIENT .. "." .. OP])
        local graph = item.graph
        local physical = require("nupp.compiler.vm.nativephysical")
        local initialized, call = false, false
        for _, block in ipairs(graph.blocks) do
            for at, op in ipairs(block.op) do
                if op == "NativeLocal" then
                    assert(block.id == 1 and not call, "local result/status created after ownership operation")
                    initialized = true
                elseif op == "NativeLeafCall" then
                    local target = block.args[at][1]
                    if target.moduleName .. "." .. target.name == KEY then
                        assert(initialized, "exact typed local missing before scoped call")
                        local signature = assert(target.physical)
                        local descriptor = assert(graph.nativePhysical.values[block.args[at][2]])
                        local origin = assert(physical.localOrigin(descriptor), "local origin was erased")
                        assert(origin.owner == item.owner, "local pointer belongs to another caller")
                        assert(physical.borrowingParameter(signature, 1), "checked parameter authority changed")
                        assert(physical.validateLocalCall(signature, 1, descriptor), "issued local relation lost")
                        call = true
                    end
                end
            end
        end
        assert(call, "scoped call not in client graph")
    end
    write(OUT .. "/" .. STEP .. "-" .. OP .. "-" .. MODE .. ".bundle", result.bundle)
end
local report = {
    step = STEP,
    operation = OP,
    removedBorrow = tampered,
    mode = MODE,
    passed = true,
    authority = "checked borrowed parameter",
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
write(OUT .. "/" .. STEP .. "-" .. OP .. "-" .. MODE .. ".json", json.encodevalue(report))
print(json.encodevalue(report))
