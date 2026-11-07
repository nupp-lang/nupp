local parser = require("nupp.compiler.syntax.parser")
local checker = require("helpers.fragment")
local environment = require("nupp.compiler.project.env")
local cst = require("nupp.compiler.syntax.cst")
local program = require("program")
local env = environment.new(".", {cache = false, memoryOnly = true, nativeCompilerServices = false})
local M = {}

local function checked(source)
    local parsed = parser.parse(source, "=scalar_alias.nupp")
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local diagnostics = checker.check(parsed, "=scalar_alias.nupp", env, {moduleName = "scalar_alias", strict = false})
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end

    return parsed
end

local function namedcalls(parsed, name)
    local found = {}

    local function walk(node)
        if not node or cst.isToken(node) then
            return
        end
        if node.kind == "call" and node.obj.kind == "name" and node.obj.token.text == name then
            found[#found + 1] = node
        end
        for _, child in ipairs(node) do
            walk(child)
        end
    end

    walk(parsed.root)
    assert(#found > 0, "missing alias call")

    return found
end

function M.reassignedScalarAliasesUseTheirCurrentFunction()
    local parsed = checked(
        [[
local rotate = math.i32.rotateleft
local function invoke(value: int32, count: integer): int32 return rotate(value, count) end
rotate = math.i32.rotateright
return invoke(1, 1)
]]
    )
    assert(not namedcalls(parsed, "rotate")[1].scalarIntrinsic, "a later assignment left a stale scalar identity")
    assert(program.run(parsed, "scalar-alias-reassigned") == -2147483648)
end

function M.nestedWritesInvalidateCapturedScalarIdentities()
    local parsed = checked(
        [[
local rotate = math.i32.rotateleft
local function invoke(value: int32, count: integer): int32 return rotate(value, count) end
local function change() rotate = math.i32.rotateright end
change()
return invoke(1, 1)
]]
    )
    assert(not namedcalls(parsed, "rotate")[1].scalarIntrinsic, "a nested assignment left a stale scalar identity")
    assert(program.run(parsed, "scalar-alias-captured") == -2147483648)
end

function M.namespaceMemberWritesUseTheActualMember()
    local parsed = checked(
        [[
local widths = math.i32
const original = widths.rotateleft
local function invoke(value: int32, count: integer): int32 return widths.rotateleft(value, count) end
widths.rotateleft = math.i32.rotateright
local result = invoke(1, 1)
widths.rotateleft = original
return result
]]
    )
    local token = parsed.root.blocks[1].stats[1].names[1]
    assert(
        not token.namespacePath and not (token.definition and token.definition.namespacePath),
        "a written namespace kept its canonical path"
    )
    assert(program.run(parsed, "scalar-namespace-member") == -2147483648)
end

function M.namespaceRebindingDoesNotPublishAStaticPath()
    local parsed = checked(
        [[
local widths = math.i32
local function invoke(value: int32, count: integer): int32 return widths.rotateleft(value, count) end
local function change() widths = math.i32 end
change()
return invoke(1, 1)
]]
    )
    local token = parsed.root.blocks[1].stats[1].names[1]
    assert(
        not token.namespacePath and not (token.definition and token.definition.namespacePath),
        "a rebound namespace kept its canonical path"
    )
    assert(program.run(parsed, "scalar-namespace-rebound") == 2)
end

function M.unrelatedShadowWritesPreserveTheOuterIdentity()
    local parsed = checked([[
local rotate = math.i32.rotateleft
do local rotate = 0; rotate = 1 end
return rotate(1, 1)
]])
    assert(
        namedcalls(parsed, "rotate")[1].scalarIntrinsic == "i32.rotateLeft",
        "an unrelated shadow invalidated the alias"
    )
    assert(program.run(parsed, "scalar-alias-shadow") == 2)
end

return M
