-- Table-driven capability laundering matrix. Each row is a language transport, not a
-- diagnostic spelling: accepted rows must keep the obligation usable exactly once;
-- rejected rows must stop weakening at the first unsafe boundary.
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")
local T = require("nupp.compiler.types")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

-- A terminal named in a type is resolved where the type is, so it has to be
-- declared above the result that names it.
local RESOURCE = table.concat(
    {
        "cdef struct flow_resource value: int32 end",
        "cdef function flow_close(takes value: flow_resource*)",
        "cdef function flow_open(): affine(flow_resource*, flow_close)",
    },
    "\n"
)

local function diagnostics(source)
    local result = parser.parse(RESOURCE .. "\n" .. source, "ownership-flow.g.nupp")
    assert(#result.errors == 0, result.errors[1] and result.errors[1].msg)
    return check.check(result, "ownership-flow.g.nupp", env)
end

local ROWS = {
    {"local move", true, [[
local value = flow_open()
local forwarded = value
nupp.drop(forwarded)
]]},
    {"local duplication", false, [[
local value = flow_open()
local forwarded = value
print(value)
nupp.drop(forwarded)
]]},
    {"optional narrowing", true, [[
local value = assert(flow_open() as flow_resource*?)
nupp.drop(value)
]]},
    {
        "scalar generic",
        true,
        [[
local function id<T>(takes value: T): T preserves value return value end
local value = id(flow_open())
nupp.drop(value)
]]
    },
    {
        "inferred scalar generic",
        true,
        [[
local function id<T>(value: T): T return value end
local value = id(flow_open())
nupp.drop(value)
]]
    },
    {"parenthesized projection", true, [[
local value = (flow_open())
nupp.drop(value)
]]},
    {"anonymous table storage", false, [[
local value = flow_open()
local stored = {value}
]]},
    {"map write", false, [[
local value = flow_open()
local stored: {string: flow_resource*} = {}
stored.value = value
]]},
    {
        "borrowed closure capture",
        true,
        [[
local value = flow_open()
local function scoped() print(value.value) end
scoped()
nupp.drop(value)
]]
    },
    {
        "borrowed closure escape",
        false,
        [[
local function leak()
   local value = flow_open()
   return function() print(value.value) end
end
]]
    },
    {"unknown call", false, [[
local value = flow_open()
local sink: any = print
sink(value)
]]},
    {"raw coroutine", false, [[
local value = flow_open()
coroutine.yield()
nupp.drop(value)
]]},
    {"unsafe does not erase", false, [[
local value = flow_open()
@unsafe do local raw: any = value end
]]},
    {
        "nominal affine field",
        true,
        [[
local record Box item: affine(flow_resource*, flow_close) end
local box = new Box(item = flow_open())
nupp.drop(box)
]]
    },
    {
        "partial move and residual cleanup",
        true,
        [[
local record Box item: affine(flow_resource*, flow_close) end
local box = new Box(item = flow_open())
local item = box.item
nupp.drop(item)
nupp.drop(box)
]]
    },
}

local M = {}

function M.everyTransportEitherPreservesOrRejectsCapability()
    for _, row in ipairs(ROWS) do
        local found = diagnostics(row[3])
        if row[2] then
            assert(#found == 0, row[1] .. " unexpectedly rejected: " .. tostring(found[1] and found[1].code))
        else
            assert(#found > 0, row[1] .. " laundered an obligation")
        end
    end
end

-- Stable test-only fixture shape for the semantic ValueSlot carrier. This deliberately
-- is not a reflection API available to programs.
function M.capabilityFixtureKeepsPayloadAndOrderedDischargeSeparate()
    local first = T.functionCleanup("flow:first", "first")
    local second = T.functionCleanup("flow:second", "second")
    local owner = T.affine(T.string, {first, second})
    local narrowed = T.withOwnershipPayload(owner, T.literal("ready"))
    local fixture = {
        payload = T.unwrapOwnership(narrowed),
        obligation = narrowed.tag,
        cleanup = {narrowed.cleanups[1].id, narrowed.cleanups[2].id},
        roots = {},
        retention = "unretained",
    }
    -- Interned identity rather than the payload's id spelled out: the same literal is
    -- the same object, which is the stronger claim and does not depend on how an id
    -- happens to read.
    assert(fixture.payload == T.literal("ready"))
    assert(fixture.obligation == "affine")
    assert(fixture.cleanup[1] == first.id and fixture.cleanup[2] == second.id)
end

function M.ordinaryCapabilityKeepsCanonicalIdentityAndIgnoresNonflowFacts()
    local empty = T.capability(T.string)
    local facts = {}
    assert(T.capability(T.integer, facts) == empty)
    assert(T.capability(T.boolean, {exclusive = false, capturedBorrowRoots = false}) == empty)
    assert(T.capability(T.any, {loans = {}, roots = {}, anchors = {}, retentions = {}, regionRoot = false,}) == empty)
    assert(T.interned("capabilities", empty.id) == empty)
    assert(not empty.obligation and #empty.loans == 0 and #empty.anchors == 0 and #empty.retentions == 0)
    assert(next(facts) == nil, "reading capability must not add facts")
end

function M.capabilityRechecksAliasedAndInheritedFlowFacts()
    local facts, root = {}, {}
    local alias = facts
    local empty = T.capability(T.string, facts)
    alias.roots = {root}
    local borrowed = T.capability(T.string, facts)
    assert(borrowed ~= empty and #borrowed.loans == 1)
    assert(borrowed.loans[1].roots[1] == root)
    assert(T.capability(T.string, setmetatable({}, {__index = facts})) == borrowed)
    alias.roots = nil
    assert(T.capability(T.string, facts) == empty)
    alias.retention = root
    local retained = T.capability(T.string, facts)
    assert(retained ~= empty and retained.retentions[1].identity == root)
    alias.retention = nil
    alias.anchors = {{root = root}}
    assert(T.capability(T.string, facts).anchors[1].root == root)
    assert(#empty.loans == 0 and #empty.anchors == 0 and #empty.retentions == 0)
end

function M.emptyFactsPreserveOwnershipQualifiers()
    local empty = T.capability(T.string)
    local borrowed = T.capability(T.borrowed(T.string), {})
    local pinned = T.capability(T.pinned(T.string), {})
    local owner = T.capability(T.affine(T.string, {T.functionCleanup("flow:close", "close")}), {})
    assert(borrowed ~= empty and #borrowed.loans == 1)
    assert(pinned ~= empty and #pinned.anchors == 1)
    assert(owner ~= empty and owner.obligation)
end

return M
