local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local envMod = require("nupp.compiler.env")
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local M = {}

local function compile(source, opts)
    local result = parser.parse(source, "ownership-region.g.nupp")
    assert(#result.errors == 0, result.errors[1] and result.errors[1].msg)
    local diagnostics = check.check(result, "ownership-region.g.nupp", envMod.new(HERE .. "/.."), opts)
    assert(#diagnostics == 0, diagnostics[1] and diagnostics[1].msg)
    local code, generation = gen.generate(result, "ownershipregion")
    assert(#generation == 0, generation[1] and generation[1].msg)

    return code
end

local RESOURCE = [[
local closed: {integer} = {}
local record Resource
    id: integer
    function destroy(takes self): nil
        closed[#closed + 1] = self.id
        @unsafe do local released = @unsafe release self end
    end
end
local function create(id: integer): affine(Resource, Resource.destroy)
    if id < 0 then error("acquisition") end
    return new Resource(id = id)
end
]]

function M.cachedMultiOwnerRegionsKeepIndependentStateAndPartialAcquisitions()
    local code = compile(
        RESOURCE
        .. [[
local function run(value: integer, mode: integer): (integer, nil, integer)
    local first = create(value)
    local second = create(mode == 1 and -1 or value + 1)
    if mode == 2 then
        drop second
    elseif mode == 3 then
        error("body")
    elseif mode == 4 then
        run(value - 10, 0)
    end
    return first.id, nil, value + 2
end
return run, closed
]]
    )
    local bodies, calls = {}, 0
    local globals = setmetatable(
        {
            xpcall = function(body, handler, ...)
                bodies[body] = true
                calls = calls + 1
                return xpcall(body, handler, ...)
            end
        },
        {__index = _G}
    )
    local chunk = assert(loadstring(code))
    setfenv(chunk, globals)
    local run, closed = chunk()
    for _, value in ipairs({20, 40, 60}) do
        local first, hole, last = run(value, 0)
        assert(first == value and hole == nil and last == value + 2)
    end
    assert(table.concat(closed, ",") == "21,20,41,40,61,60")
    local unique = 0
    for _ in pairs(bodies) do
        unique = unique + 1
    end
    assert(calls == 3 and unique == 1, "the multi-owner body must be reused across invocations")
    local ok, why = pcall(run, 80, 1)
    assert(not ok and tostring(why):find("acquisition", 1, true))
    assert(closed[#closed] == 80)
    run(90, 2)
    assert(closed[#closed - 1] == 91 and closed[#closed] == 90)
    ok, why = pcall(run, 100, 3)
    assert(not ok and tostring(why):find("body", 1, true))
    assert(closed[#closed - 1] == 101 and closed[#closed] == 100)
    run(120, 4)
    assert(table.concat(closed, ","):match("111,110,121,120$"), "recursive invocation must retain each caller's owners")
    local coldRun, coldClosed = assert(loadstring(code))()
    coldRun(120, 4)
    assert(table.concat(coldClosed, ",") == "111,110,121,120", "the first invocation must support recursion")
end

function M.moduleOwnerWrappersHaveNoChildClosuresAndKeepBodyLines()
    local source = RESOURCE
        .. [[
local function run(value: integer, fail: boolean): integer
    local adjusted = value + 1
    local first = create(adjusted)
    local second = create(adjusted + 1)
    if fail then error("hoisted-body-line") end
    return first.id + second.id
end
return run, closed
]]
    local code = compile(source)
    local _, sourceLines = source:gsub("\n", "")
    local _, codeLines = code:gsub("\n", "")
    assert(codeLines == sourceLines, "hoisting must preserve generated source lines")
    local run, closed = assert(loadstring(code, "@hoisted-ownership.nupp"))()
    local util, names = require("jit.util"), require("jit.vmdef").bcnames
    local bit = require("bit")
    for pc = 1, util.funcinfo(run).bytecodes - 1 do
        local ins = util.funcbc(run, pc)
        local op = bit.band(ins, 255)
        local name = names:sub(op * 6 + 1, op * 6 + 6):gsub("%s+$", "")
        assert(name ~= "FNEW" and name ~= "UCLO", "hot owner wrapper retains " .. name)
    end
    assert(run(10, false) == 23 and run(20, false) == 43)
    local line = 1
    for text in source:gmatch("([^\n]*)\n") do
        if text:find('error("hoisted-body-line")', 1, true) then
            break
        end
        line = line + 1
    end
    local ok, why = pcall(run, 30, true)
    assert(not ok and tostring(why):find("hoisted-ownership.nupp:" .. line .. ":", 1, true), tostring(why))
    assert(table.concat(closed, ",") == "12,11,22,21,32,31")
end

function M.publishingAQualifiedWrapperCanCallItImmediately()
    local code = compile(
        RESOURCE
        .. [[
local observed = 0
local target: any = setmetatable({}, {
    __newindex = function(self: any, key: any, value: any): nil
        observed = value(10)
        rawset(self, key, value)
    end,
})
function target.run(value: integer): integer
    local first = create(value)
    local second = create(value + 1)
    return first.id + second.id
end
return target.run, observed, closed
]]
    )
    local run, observed, closed = assert(loadstring(code))()
    assert(observed == 21 and run(20) == 41)
    assert(table.concat(closed, ",") == "11,10,21,20")
end

function M.multiOwnerRegionsPreserveObservableCapturedWrites()
    local code = compile(
        RESOURCE
        .. [[
local observer: any
local function observe(): integer
    return observer()
end
local function run(value: integer): integer
    local result = value
    observer = function(): integer return result end
    do
        local first = create(value)
        local second = create(value + 1)
        result = first.id + second.id
        assert(observe() == result)
    end
    return result
end
return run
]]
    )
    local run = assert(loadstring(code))()
    assert(run(20) == 41)
    assert(run(40) == 81)
end

function M.cachedAcquisitionsReadEachCallsArguments()
    local code = compile(
        RESOURCE
        .. [[
local function run(value: integer): nil
    local first = create(value)
    local second = create(1)
end
return run, closed
]]
    )
    local run, closed = assert(loadstring(code))()
    run(20)
    run(40)
    assert(
        table.concat(closed, ",") == "1,20,1,40",
        "an acquisition-only argument must not retain the first invocation"
    )
end

function M.cachedRegionsDoNotSnapshotLocalsWrittenByOtherClosures()
    local code = compile(
        RESOURCE
        .. [[
local setter: any
local function change(): nil setter() end
local function run(value: integer): integer
    setter = function(): nil value = value + 10 end
    local first = create(1)
    local second = create(2)
    change()
    return value
end
return run
]]
    )
    local run = assert(loadstring(code))()
    assert(run(20) == 30)
    assert(run(40) == 50)
end

function M.portableMultiOwnerRegionsForwardTheStateFrame()
    local code = compile(
        RESOURCE
        .. [[
local function run(value: integer): integer
    local first = create(value)
    local second = create(1)
    drop second
    return first.id
end
return run, closed
]],
        {dialect = "lua51"}
    )
    local globals = setmetatable(
        {
            xpcall = function(body, handler)
                return xpcall(body, handler)
            end
        },
        {__index = _G}
    )
    local chunk = assert(loadstring(code))
    setfenv(chunk, globals)
    local run, closed = chunk()
    assert(run(20) == 20 and run(40) == 40)
    assert(table.concat(closed, ",") == "1,20,1,40")
end

function M.nestedCleanupBodiesReadTheCurrentOuterFrame()
    local code = compile(
        RESOURCE
        .. [[
local seen: {integer} = {}
local function run(value: integer): nil
    local first = create(1)
    local second = create(2)
    do
        local third = create(3)
        seen[#seen + 1] = value
    end
end
return run, seen
]]
    )
    local run, seen = assert(loadstring(code))()
    run(20)
    run(40)
    assert(table.concat(seen, ",") == "20,40", "nested cleanup must not retain an earlier outer frame")
end

function M.cachedMixedDeclarationsReadEveryInitializer()
    local code = compile(
        RESOURCE
        .. [[
local function run(value: integer): integer
    local first, label = create(1), value
    local second = create(2)
    return label
end
return run
]]
    )
    local run = assert(loadstring(code))()
    assert(run(20) == 20)
    assert(run(40) == 40, "non-owner initializer must use the current call's argument")
end

function M.cachedAcquisitionsForwardVarargs()
    local code = compile(
        RESOURCE
        .. [[
local function run(...: integer): integer
    local first = create((...))
    local second = create(1)
    return first.id
end
return run
]]
    )
    local run = assert(loadstring(code))()
    assert(run(20) == 20)
    assert(run(40) == 40)
end

function M.constructorCleanupReturnsEachNewInstance()
    for _, extra in ipairs({"", "local second = create(2)"}) do
        local code = compile(
            RESOURCE
            .. [[
local record Box
    id: integer = 0
    constructor(self)
        local first = create(1)
]]
            .. extra
            .. [[
        return
    end
end
return function(): Box return new Box() end
]]
        )
        local createBox = assert(loadstring(code))()
        local first, second = createBox(), createBox()
        assert(first ~= second, "a cached cleanup must not return an earlier constructor instance")
    end
end

function M.localTypeIdentitiesRemainPerInvocation()
    local code = compile(
        RESOURCE
        .. [[
local function run(value: integer): (any, any)
    local record R
        id: integer
    end
    local first = create(1)
    local second = create(2)
    return new R(id = value), R
end
return run
]]
    )
    local run = assert(loadstring(code))()
    for _, value in ipairs({20, 40}) do
        local instance, identity = run(value)
        assert(
            instance.id == value and getmetatable(instance) == identity,
            "construction must use this invocation's type identity"
        )
    end
    code = compile(
        RESOURCE
        .. [[
local function run(value: integer): boolean
    local record R
        id: integer
    end
    local object: any = new R(id = value)
    local first = create(1)
    local second = create(2)
    return object is R
end
return run
]]
    )
    run = assert(loadstring(code))()
    assert(run(20) and run(40), "type tests must use this invocation's type identity")
end

function M.functionDeclarationsMutateTheirActualCapturedBinding()
    for _, extra in ipairs({"", "local second = create(2)"}) do
        local code = compile(
            RESOURCE
            .. [[
local setter: any
local function change(): nil setter() end
local function run(value: any): any
    setter = function(): nil
        function value(): integer return 42 end
    end
    local first = create(1)
]]
            .. extra
            .. [[
    change()
    return value
end
return run
]]
        )
        local run = assert(loadstring(code))()
        local value = run(20)
        assert(
            type(value) == "function" and value() == 42,
            "a function declaration must update the original captured binding"
        )
    end
end

function M.bodyFunctionDeclarationsKeepLoopBindingWrites()
    -- The declaration is intentionally inside the loop: this tests its binding
    -- write, so only the corresponding closure-allocation lint is suppressed.
    for _, extra in ipairs({"", "local second = create(2)"}) do
        local code = compile(
            RESOURCE
            .. [[
local seen: {any} = {}
for i = 1, 2 do
    local value: any = i
    local first = create(1)
]]
            .. extra
            .. [[
    function value(): integer return 42 end
    seen[#seen + 1] = value
end
return seen
]],
            {lints = {["unused-binding"] = "off", ["discarded-result"] = "off", ["loop-invariant-closure"] = "off"}}
        )
        local seen = assert(loadstring(code))()
        assert(#seen == 2)
        for _, value in ipairs(seen) do
            assert(
                type(value) == "function" and value() == 42,
                "a declaration in the owner body must retain its loop binding"
            )
        end
    end
end

function M.unrelatedFunctionDeclarationsDoNotDisableOwnerHoisting()
    local code = compile(
        RESOURCE
        .. [[
local function replace(): nil
    local value: any = 0
    function value(): integer return 42 end
end
local function run(value: integer): integer
    local first = create(1)
    local second = create(2)
    replace()
    return value
end
return run
]]
    )
    local run = assert(loadstring(code))()
    assert(run(20) == 20 and run(40) == 40)
    local util, names, bit = require("jit.util"), require("jit.vmdef").bcnames, require("bit")
    for pc = 1, util.funcinfo(run).bytecodes - 1 do
        local instruction = util.funcbc(run, pc)
        local opcode = bit.band(instruction, 255)
        local name = names:sub(opcode * 6 + 1, opcode * 6 + 6):gsub("%s+$", "")
        assert(name ~= "FNEW" and name ~= "UCLO", "a shadowed binding wrongly disables hoisting")
    end
end

return M
