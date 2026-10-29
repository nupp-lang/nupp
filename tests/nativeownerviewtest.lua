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
    with owner = acquire(value) do
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

function M.checkedOwnerAndWithOccurrencesRemainDistinct()
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
        local binding = owners.scoped.body.body.stats[1].bindings[1]
        assert(cleanup.acquisition(binding).tag == "affine")
        assert(binding.name.definition.type.tag == "borrowed")
        assert(binding.name.definition.type.inner == binding.acquiredType.inner)
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

function M.WithCannotBorrowAPlainOrUnissuedAcquisition()
    fixture(function(s, owners)
        local f = owners.scoped
        local binding = f.body.body.stats[1].bindings[1]
        local context = unit.ownerContext(f)
        refuses(
            function()
                physical.binding(
                    f,
                    physical.describe(context, binding.acquiredType.inner),
                    binding,
                    binding.name.definition
                )
            end,
            "affine pointer"
        )
        refuses(
            function()
                physical.binding(f, physical.describe(context, binding.acquiredType), binding, binding.name.definition)
            end,
            "acquisition origin"
        )
        assert(s.validate())
    end)
end

return M
