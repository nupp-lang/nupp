local unit = require("nupp.compiler.vm.nativeunit")
local physical = require("nupp.compiler.vm.nativephysical")
local cleanup = require("nupp.compiler.vm.functioncleanup")
local M = {}
local TARGET = "aarch64-apple-darwin"
local SOURCE = [[
module model
export struct Word
    value: uint64
end
local function release(takes value: Word*): nil end
local function acquire(value: Word*): affine(Word*, release) return value end
local function read(borrows value: Word*): uint64 return value.value end
export function locals(value: Word*): uint64
    local left = acquire(value)
    local right = acquire(value)
    read(left)
    return right.value
end
export function scoped(value: Word*): uint64
    do
        local owner = acquire(value)
        return owner.value
    end
end
]]

local function refuses(action, text)
    local ok, message = pcall(action)
    assert(not ok, "unissued owner permission accepted")
    if text then
        assert(tostring(message):find(text, 1, true), tostring(message))
    end
end

local function fixture(action)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local path = dir .. "/src/model.nupp"
    local file = assert(io.open(path, "wb"));
    file:write(SOURCE);
    file:close()
    local ok, problem = pcall(function()
        local s = unit.session(dir, {{path = path, moduleName = "model"}}, TARGET, {"src"})
        action(s, s.module("model").functions)
    end)
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then
        error(problem, 0)
    end
end

function M.checkedOwningLocalsRetainDistinctOccurrences()
    fixture(function(s, owners)
        local f = owners.locals
        local left = cleanup.localOwner(f.body.body.stats[1], 1)
        local right = cleanup.localOwner(f.body.body.stats[2], 1)
        assert(left ~= right and left.type == right.type)
        local call = f.body.body.stats[3].expr
        assert(call.args.exprs[1].inferredType == left.type)
        assert(call.args.exprs[1].token.definition == left.entry.definition)
        local access = f.body.body.stats[4].exprs[1]
        assert(access.obj.inferredType == right.type)
        local stat = owners.scoped.body.body.stats[1].body.stats[1]
        local owner = cleanup.localOwner(stat, 1)
        assert(owner.type.tag == "affine")
        assert(stat.names[1].definition.type == owner.type)
        assert(owner.expr == stat.exprs[1])
        assert(owners.release.parameterTypes[1].tag == "affine")
        assert(owners.release.parameterModes[1] == "takes")
        assert(s.validate())
    end)
end

function M.equalLocalTypesDoNotIssueAcquisitionOrigins()
    fixture(function(s, owners)
        local f = owners.locals
        local left = cleanup.localOwner(f.body.body.stats[1], 1)
        local right = cleanup.localOwner(f.body.body.stats[2], 1)
        local source = physical.describe(unit.ownerContext(f), left.type)
        local access = f.body.body.stats[4].exprs[1]
        -- Public type descriptors do not prove which call produced the owner.
        refuses(
            function()
                physical.bindOwner(f, source, f.body.body.stats[1], left.entry.definition)
            end,
            "acquisition origin"
        )
        refuses(
            function()
                physical.ownerView(f, source, access.obj)
            end,
            "acquisition origin"
        )
        local saved = right.entry.definition
        right.entry.definition = left.entry.definition
        refuses(
            function()
                physical.ownerView(f, source, access.obj)
            end,
            "checked binding"
        )
        right.entry.definition = saved
        assert(s.validate())
    end)
end

function M.localsCannotBorrowAPlainOrUnissuedAcquisition()
    fixture(function(s, owners)
        local f = owners.scoped
        local stat = f.body.body.stats[1].body.stats[1]
        local owner = cleanup.localOwner(stat, 1)
        local access = f.body.body.stats[1].body.stats[2].exprs[1]
        local context = unit.ownerContext(f)
        refuses(
            function()
                physical.ownerView(f, physical.describe(context, owner.type.inner), access.obj)
            end,
            "affine pointer"
        )
        refuses(
            function()
                physical.ownerView(f, physical.describe(context, owner.type), access.obj)
            end,
            "acquisition origin"
        )
        assert(s.validate())
    end)
end

return M
