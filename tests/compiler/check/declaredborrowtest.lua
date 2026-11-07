local testAssert = require("assert")
local diagnosticMod = require("nupp.compiler.diagnostics")
local environment = require("nupp.compiler.project.env")
local generics = require("nupp.compiler.types.generics")
local T = require("nupp.compiler.types")
local HERE = require("helpers.paths").tests
local M, serial = {}, 0
local sharedEnv = environment.new(HERE .. "/..", {cache = false})

local function checked(source)
    serial = serial + 1
    local name = "declaredborrowcase" .. serial
    local root = HERE .. "/.."
    local path = root .. "/src/" .. name .. ".nupp"
    local env = sharedEnv
    local parsed, diagnostics, _, exports = environment.checkModuleSource(
        env,
        path,
        "module " .. name .. "\n" .. source,
        {moduleName = name}
    )
    testAssert.eq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg or "syntax")
    local codes = {}
    for _, diagnostic in ipairs(diagnostics) do
        if diagnosticMod.severityOf(diagnostic) == "error" then
            codes[#codes + 1] = diagnostic.code
        end
    end

    return table.concat(codes, " "), exports, name
end

function M.aDefinitionKeepsItsDeclaredSelfBorrow()
    local codes, exports = checked(
        [[
export record R
    value: integer
    view: function(borrows self: R): R borrows(self)
end
function R:view(): R
    return self
end
local function use(borrows value: R): R borrows(value)
    return value:view()
end
]]
    )
    testAssert.eq(codes, "")
    testAssert.eq(exports.types.R.byname.view.borrowsSelf, true)
    testAssert.eq(exports.types.R.byname.view.paramModes[1], "borrows")
end

function M.aDefinitionBorrowsItsRenamedExplicitArgument()
    local codes, exports = checked(
        [[
export record R
    value: integer
    pick: function(borrows self: R, borrows other: R): R borrows(other)
end
function R:pick(borrows selected: R): R
    return selected
end
local function use(borrows owner: R, borrows other: R): R borrows(other)
    return owner:pick(other)
end
]]
    )
    testAssert.eq(codes, "")
    local signature = exports.types.R.byname.pick
    testAssert.eq(signature.borrowsParam, 2)
    local bound = generics.dropSelf(signature)
    testAssert.eq(bound.borrowsParam, 1)
    testAssert.eq(bound.borrowsSelf or false, false)
end

function M.explicitAndDeclaredSourcesShareOneResultObligation()
    local codes, exports = checked(
        [[
export record R
    value: integer
    pair: function(borrows self: R, borrows other: R,
        scoped join: function(borrows left: R, borrows right: R): R borrows(left, right)): R borrows(self)
end
function R:pair(borrows other: R,
    scoped join: function(borrows left: R, borrows right: R): R borrows(left, right)): R borrows(other)
    return join(self, other)
end
]]
    )
    testAssert.eq(codes, "")
    local signature = generics.dropSelf(exports.types.R.byname.pair)
    testAssert.eq(signature.borrowsSelf, true)
    testAssert.eq(signature.borrowsParam, 1)
end

function M.aBorrowedResultKeepsItsNonfirstSlot()
    local codes, exports = checked(
        [[
export record R
    value: integer
    view: function(borrows self: R): (integer, R borrows(self))
end
function R:view(): (integer, R)
    return 7, self
end
]]
    )
    testAssert.eq(codes, "")
    testAssert.eq(exports.types.R.byname.view.borrowsResult, 2)
    testAssert.eq(generics.dropSelf(exports.types.R.byname.view).borrowsResult, 2)
end

function M.aDefinitionCannotMoveTheBorrowToAnotherResultSlot()
    local codes = checked(
        [[
export record R
    value: integer
    view: function(borrows self: R, borrows other: R): (R, R borrows(self))
end
function R:view(borrows other: R): (R borrows(other), R)
    return other, self
end
]]
    )
    assert(codes:find("NUPP2621", 1, true), codes)
end

function M.anUnrelatedOrFreshResultDoesNotSatisfyTheDeclaration()
    for _, expression in ipairs({"R(value = 1)", "other"}) do
        local codes = checked(
            [[
export record R
    value: integer
    view: function(borrows self: R, borrows other: R): R borrows(self)
end
function R:view(borrows other: R): R
    return ]]
            .. expression
            .. "\nend\n"
        )
        assert(codes:find("NUPP2619", 1, true), codes)
    end
end

function M.validDefinitionRefinementsRemainAccepted()
    local codes = checked(
        [[
local record R
    parse: function(text: string): integer
    close: function(takes self: R): nil
end
function R.parse(text: string, base: integer?): (integer, string)
    return 1, text
end
function R:close(): nil
end
export = R
]]
    )
    testAssert.eq(codes, "")
end

function M.addingAReceiverShiftsEveryExplicitBorrowSource()
    local signature = T.func(
        {T.string, T.string},
        {T.string},
        false,
        {"borrows", "borrows"},
        nil,
        nil,
        nil,
        nil,
        false,
        {1, 2}
    )
    local stored = generics.addSelf(signature, T.table_, "borrows")
    testAssert.eq(stored.borrowsParams[1], 2)
    testAssert.eq(stored.borrowsParams[2], 3)
    local bound = generics.dropSelf(stored)
    testAssert.eq(bound.borrowsParams[1], 1)
    testAssert.eq(bound.borrowsParams[2], 2)
end

function M.aDefinitionKeepsItsDeclaredExclusiveReceiver()
    local codes, exports = checked(
        [[
export record R
    value: integer
    view: function(exclusive self: R): R borrows(self)
end
function R:view(): R
    return self
end
]]
    )
    testAssert.eq(codes, "")
    testAssert.eq(exports.types.R.byname.view.paramModes[1], "exclusive")
end

function M.anExplicitBorrowCannotReplaceTheDeclaredSource()
    local codes = checked(
        [[
export record R
    value: integer
    view: function(borrows self: R, borrows other: R): R borrows(self)
end
function R:view(borrows other: R): R borrows(other)
    return other
end
]]
    )
    assert(codes:find("NUPP2619", 1, true), codes)
end

function M.anUnnamedVariadicSourceCannotEraseTheBorrowObligation()
    local codes = checked(
        [[
export record R
    value: integer
    view: function(borrows self: R, borrows other: R): R borrows(other)
end
function R:view(...): R
    return R(value = 1)
end
]]
    )
    assert(codes:find("NUPP2619", 1, true), codes)
end

function M.inlineMethodsBorrowTheExplicitArgumentAfterSelf()
    local codes, exports = checked(
        [[
export record R
    value: integer
    function pick(borrows self, borrows other: R): R borrows(other)
        return other
    end
end
local function use(borrows owner: R, borrows other: R): R borrows(other)
    return owner:pick(other)
end
]]
    )
    testAssert.eq(codes, "")
    testAssert.eq(exports.types.R.byname.pick.borrowsParam, 2)
end

function M.checkingAnImplementationKeepsTheCanonicalDeclarationBorrow()
    local codes, declarations, name = checked(
        [[
export record R
    value: integer
    view: function(borrows self: R): R borrows(self)
end
]]
    )
    testAssert.eq(codes, "")
    local original = declarations.types.R
    testAssert.eq(original.byname.view.borrowsSelf, true)
    local implementation, implemented = checked(
        (
            [[
local declared = require(%q)
export type R = declared.R
export const R = declared.R
function R:view(): R
    return self
end
]]
        ):format(name)
    )
    testAssert.eq(implementation, "")
    testAssert.eq(implemented.types.R, original)
    testAssert.eq(original.byname.view.borrowsSelf, true)
    local consumer = checked(
        (
            [[
local declared = require(%q)
export function use(borrows value: declared.R): declared.R borrows(value)
    return value:view()
end
]]
        ):format(name)
    )
    testAssert.eq(consumer, "")
end

function M.aBorrowedDeclarationAllowsAnOwnershipRefinement()
    local codes = checked(
        [[
local record R
    value: integer
    pick: function(borrows self: R, takes resource: R): R borrows(self)
end
local function cleanup(takes resource: R): nil
    local released = @unsafe own.release(resource)
end
function R:pick(takes resource: affine(R, cleanup)): R
    own.drop(resource)
    return self
end
export = R
]]
    )
    testAssert.eq(codes, "")
end

function M.aDefinitionKeepsEverySharedDeclaredBorrow()
    for _, result in ipairs({"(R, R)", "(R borrows(self), R borrows(self))"}) do
        local codes, exports = checked(
            [[
export record R
    value: integer
    pair: function(borrows self: R): (R borrows(self), R borrows(self))
end
function R:pair(): ]]
            .. result
            .. "\n    return self, self\nend\n"
        )
        testAssert.eq(codes, "")
        local signature = exports.types.R.byname.pair
        testAssert.eq(signature.borrowsResult, 0)
        testAssert.eq(signature.borrowsSelf, true)
        testAssert.eq(signature.rets[1].tag, "borrowed")
        testAssert.eq(signature.rets[2].tag, "borrowed")
    end
end

function M.everySharedDeclaredResultMustRetainItsSource()
    for _, returned in ipairs({"other, self", "self, other"}) do
        local codes = checked(
            [[
export record R
    value: integer
    pair: function(borrows self: R, borrows other: R): (R borrows(self), R borrows(self))
end
function R:pair(borrows other: R): (R, R)
    return ]]
            .. returned
            .. "\nend\n"
        )
        assert(codes:find("NUPP2619", 1, true), codes)
    end
end

return M
