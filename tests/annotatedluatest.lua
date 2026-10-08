local testAssert = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local annotated = require("nupp.compiler.annotatedlua")
local migrate = require("nupp.tools.migrate")
local T = require("nupp.compiler.types")
local envMod = require("nupp.compiler.project.env")

local M = {}

-- A LuaCATS library is written in stubs: `function love.window.fromPixels(v) end`
-- beside a `---@return number`. In a declaration tree the empty body is the
-- declaration, not a function that forgot to return, so it is taken rather than
-- refused.
function M.anEmptyStubInADeclarationTreeDeclaresItsResult()
    local source = [[
---@class stubs
stubs = {}

---@param pixels number
---@return number
function stubs.fromPixels(pixels) end
]]
    local parsed = parser.parse(source, "library/stubs.lua")
    local diagnostics = check.check(parsed, "library/stubs.lua", nil, {declareGlobals = true, declarationFile = true, strict = false})
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.code ~= "NUPP2002", "a stub is refused for not returning: " .. diagnostic.msg)
    end
    local ordinary = check.check(parser.parse(source, "stubs.lua"), "stubs.lua")
    local refused = false
    for _, diagnostic in ipairs(ordinary) do
        refused = refused or diagnostic.code == "NUPP2002"
    end
    assert(refused, "outside a declaration tree the same body still has to return")
end

function M.functionAndClassCommentsBecomeModuleFacts()
    local source = [[
---@alias UserId integer
---@class User
---@field id UserId
---@field name? string
local module = {}

---@param id UserId
---@return User
function module.find(id)
   return {id = id, name = "Ada"}
end

return module
]]
    local parsed = parser.parse(source, "users.lua")
    local diagnostics, moduleType, exports = check.check(parsed, "users.lua")
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    assert(moduleType and moduleType.tag == "shape", "annotated Lua did not export a shape")
    local find = moduleType.byname.find
    assert(find and find.tag == "func", "annotated function signature was not exported")
    testAssert.equal(T.tostring(find.params[1]), "integer", "alias-backed parameter")
    testAssert.equal(T.tostring(find.rets[1]), "User", "class-backed result")
    assert(exports.types.User and exports.types.User.tag == "nominal", "foreign class was not available as a type")
end

function M.malformedTypesRecoverAsWarningsAndAny()
    local source = [[
---@param value @@@
---@return string
local function keep(value)
   return value
end
return keep
]]
    local parsed = parser.parse(source, "broken.lua")
    local diagnostics, moduleType = check.check(parsed, "broken.lua")
    testAssert.equal(#diagnostics, 1, "one recoverable warning")
    testAssert.equal(diagnostics[1].code, "NUPP1008")
    testAssert.equal(diagnostics[1].severity, "warning")
    testAssert.equal(
        source:sub(diagnostics[1].offset, diagnostics[1].offset + diagnostics[1].length - 1),
        "@param value @@@",
        "warning range"
    )
    assert(moduleType and moduleType.tag == "func")
    testAssert.equal(T.tostring(moduleType.params[1]), "any", "recovered parameter")
end

function M.annotationTextInsideStringsIsNotIngested()
    local source = [=[
local example = [[
---@alias Phantom integer
]]
return example
]=]
    local parsed = parser.parse(source, "strings.lua")
    testAssert.equal(#annotated.tags(source, parsed.tokens), 0, "string contents are not comments")
    local diagnostics, _, exports = check.check(parsed, "strings.lua")
    testAssert.equal(#diagnostics, 0)
    assert(exports.types.Phantom == nil, "string text declared a type")
end

function M.annotationBlockCommentsAreIngested()
    local source = [==[
--[[
@alias BlockId integer
]]
--[=[
 * @param value BlockId
 * @return BlockId
]=]
local function keep(value)
   return value
end
return keep
]==]
    local parsed = parser.parse(source, "blocks.lua")
    local found = annotated.tags(source, parsed.tokens)
    testAssert.equal(#found, 3, "block annotation count")
    local diagnostics, moduleType = check.check(parsed, "blocks.lua")
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    assert(moduleType and moduleType.tag == "func")
    testAssert.equal(T.tostring(moduleType.params[1]), "integer")
    testAssert.equal(T.tostring(moduleType.rets[1]), "integer")
end

function M.migrationUsesTheSameRecoveredFacts()
    local source = [[
---@alias Id integer
local module = {}
---@param value Id
---@return Id
function module.keep(value)
   return value
end
return module
]]
    local plan, problem = migrate.plan(source, "identity.lua", "auto")
    assert(plan, problem)
    testAssert.equal(plan.destination, "identity.g.nupp")
    assert(plan.text:find("local type Id = integer", 1, true), "alias was not emitted")
    assert(plan.text:find("function module.keep(value: Id): Id", 1, true), "function annotations were not migrated")
    local migrated = parser.parse(plan.text, plan.destination)
    testAssert.equal(#migrated.errors, 0, migrated.errors[1] and migrated.errors[1].msg)
end

function M.genericOwnershipGapIsExplicitlyRecovered()
    local source = [[
---@generic T
---@param value T
---@return T
local function keep(value)
   return value
end
return keep
]]
    local parsed = parser.parse(source, "generic.lua")
    local diagnostics, moduleType = check.check(parsed, "generic.lua")
    testAssert.equal(#diagnostics, 1)
    testAssert.equal(diagnostics[1].severity, "warning")
    assert(diagnostics[1].msg:find("ownership", 1, true))
    assert(moduleType and moduleType.tag == "func")
    testAssert.equal(T.tostring(moduleType.params[1]), "any")
    testAssert.equal(T.tostring(moduleType.rets[1]), "any")
end

function M.unknownForeignNamesWarnInsteadOfFailingLua()
    local source = [[
---@param value other.Missing
local function keep(value)
   return value
end
return keep
]]
    local parsed = parser.parse(source, "unknown.lua")
    local diagnostics, moduleType = check.check(parsed, "unknown.lua")
    testAssert.equal(#diagnostics, 1)
    testAssert.equal(diagnostics[1].code, "NUPP1008")
    testAssert.equal(diagnostics[1].severity, "warning")
    assert(moduleType and moduleType.tag == "func")
    testAssert.equal(T.tostring(moduleType.params[1]), "any")
end

function M.typeOnlyExportsSurviveAnonymousModuleReturns()
    local source = [[
---@class Client
---@field request fun(self: Client, path: string): string|nil

---@return Client
local function connect()
   return {request = function(_, path) return path end}
end

return {connect = connect}
]]
    local parsed = parser.parse(source, "client.lua")
    local diagnostics, moduleType, exports = check.check(parsed, "client.lua")
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    assert(moduleType and moduleType.tag == "shape")
    assert(
        exports.types.Client and exports.types.Client.tag == "nominal",
        "anonymous module did not retain its type-only export"
    )
end

function M.castAndAssignmentTypesBecomeFactsAndMigrationSyntax()
    local source = [[
local value = unknown()
---@cast value string
use(value)

local assigned
---@type integer
assigned = unknown()
return assigned
]]
    local plan, problem = migrate.plan(source, "facts.lua", "auto")
    assert(plan, problem)
    assert(plan.text:find("value = value as string", 1, true), "positive cast was not migrated")
    assert(plan.text:find("assigned = assigned as integer", 1, true), "assignment type was not migrated")
    local migrated = parser.parse(plan.text, plan.destination)
    testAssert.equal(#migrated.errors, 0, migrated.errors[1] and migrated.errors[1].msg)
end

function M.blockAssignmentTypesInsertAfterTheWholeComment()
    local source = [=[
local assigned
--[[
@type integer
]]
assigned = unknown()
return assigned
]=]
    local plan, problem = migrate.plan(source, "block-facts.lua", "auto")
    assert(plan, problem)
    assert(plan.text:find("]]\nassigned = assigned as integer\nassigned = unknown()", 1, true), plan.text)
    local migrated = parser.parse(plan.text, plan.destination)
    testAssert.equal(#migrated.errors, 0, migrated.errors[1] and migrated.errors[1].msg)
end

function M.ambientLuaCATSRootsDeclareGlobalsWithoutBecomingModules()
    local root = os.tmpname()
    os.remove(root)
    assert(os.execute("mkdir -p '" .. root .. "/types'") == 0)
    local path = root .. "/types/host.lua"
    local f = assert(io.open(path, "wb"))
    f:write([[
---@class Host
---@field answer fun(): integer
---@type Host
host = {answer = function() return 42 end}
]])
    f:close()

    local env = envMod.new(root, {cache = false, ambientTypeRoots = {root .. "/types"}})
    local parsed = parser.parse("local answer: integer = host.answer()\n", root .. "/main.nupp")
    local diagnostics = check.check(parsed, root .. "/main.nupp", env)
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    assert(envMod.findRuntimeModulePath(env, "host") == nil, "an ambient type dependency became a runtime module")
    os.execute("rm -rf '" .. root .. "'")
end

-- Files are read in the order their names sort, which is not the order a tree
-- declares its types in: a.lua here uses a class b.lua declares.
function M.aDeclarationTreeMayNameATypeAFileReadLaterDeclares()
    local root = os.tmpname()
    os.remove(root)
    assert(os.execute("mkdir -p '" .. root .. "/types'") == 0)
    local function write(name, text)
        local f = assert(io.open(root .. "/types/" .. name, "wb"))
        f:write(text)
        f:close()
    end
    write("a.lua", [[
---@class game
game = {}

---@param shape game.Shape
---@return number
function game.area(shape) end
]])
    write("b.lua", [[
---@class game.Shape
---@field width number
local Shape = {}
]])
    local env = envMod.new(root, {cache = false, ambientTypeRoots = {root .. "/types"}})
    local parsed = parser.parse("local n: number = game.area({width = 2})\n", root .. "/main.nupp")
    local diagnostics = check.check(parsed, root .. "/main.nupp", env)
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    testAssert.equal(#(env.ambientTypeProblems or {}), 0, env.ambientTypeProblems and env.ambientTypeProblems[1]
        and env.ambientTypeProblems[1].msg)
    os.execute("rm -rf '" .. root .. "'")
end

function M.multipleLocalTypesAreMigratedPositionally()
    local source = [[
---@type string, integer
local name, count = "Ada", 1
return name, count
]]
    local plan, problem = migrate.plan(source, "locals.lua", "auto")
    assert(plan, problem)
    assert(plan.text:find("local name: string, count: integer", 1, true), "local types were not migrated positionally")
end

function M.typedLuaDocParameterOrderIsDetected()
    local source = [[
-- @tparam string value descriptive prose
-- @treturn string descriptive prose
local function keep(value)
   return value
end
return keep
]]
    local parsed = parser.parse(source, "luadoc.lua")
    local diagnostics, moduleType = check.check(parsed, "luadoc.lua")
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    testAssert.equal(T.tostring(moduleType.params[1]), "string")
    testAssert.equal(T.tostring(moduleType.rets[1]), "string")

    local plan, problem = migrate.plan(source, "luadoc.lua", "luadoc")
    assert(plan, problem)
    assert(plan.text:find("function keep(value: string): string", 1, true))
    local invalid, invalidProblem = migrate.plan(source, "luadoc.lua", "mystery")
    assert(invalid == nil and invalidProblem:find("unsupported", 1, true))
end

-- A trailing description after a field's type is prose, not a second statement
-- that happens to parse. The scope words and bracketed indexers LuaCATS allows in
-- front of a field name are read for what they are.
function M.describedScopedAndIndexedFieldsSurvive()
    local source = [[
---@class User
---@field id integer The identifier
---@field name string The user name
---@field private secret string
---@field [string] integer
local module = {}

return module
]]
    local parsed = parser.parse(source, "users.lua")
    local diagnostics, _, exports = check.check(parsed, "users.lua")
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    local user = exports.types.User
    assert(user and user.tag == "nominal", "described fields dropped the class")
    testAssert.equal(T.tostring(user.byname.id), "integer", "described field")
    testAssert.equal(T.tostring(user.byname.name), "string", "described field")
    testAssert.equal(T.tostring(user.byname.secret), "string", "scoped field")
    assert(
        user.byname["[string]"] == nil and user.byname["string"] == nil,
        "a bracketed field name was read as a field"
    )
    assert(user.indexReadValue, "a bracketed field name was not read as an indexer")
    testAssert.equal(T.tostring(user.indexReadKey), "string", "indexer key")
    testAssert.equal(T.tostring(user.indexReadValue), "integer", "indexer value")
end

-- A multi-line alias lists its members on `---|` lines; the declaration keeps the
-- alias's own name and becomes the union of those members.
function M.multiLineAliasBecomesAUnion()
    local source = [[
---@alias Mode
---| "fast" # the quick one
---| "slow"

---@param mode Mode
local function keep(mode)
   return mode
end
return keep
]]
    local parsed = parser.parse(source, "modes.lua")
    local diagnostics, moduleType, exports = check.check(parsed, "modes.lua")
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    assert(exports.types.Mode, "the alias kept a name nobody registered")
    testAssert.equal(T.tostring(moduleType.params[1]), '"fast" | "slow"')
end

-- `---@param ... T` types the vararg the same way `---@vararg T` does.
function M.paramTagTypesTheVararg()
    local source = [[
---@param first string
---@param ... integer the rest
local function keep(first, ...)
   return first, ...
end
return keep
]]
    local parsed = parser.parse(source, "vararg.lua")
    local diagnostics, moduleType = check.check(parsed, "vararg.lua")
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    testAssert.equal(T.tostring(moduleType.params[1]), "string")
    assert(moduleType.vararg, "the function lost its vararg")
    testAssert.equal(T.tostring(moduleType.varargType), "integer", "vararg")
end

-- A module field's type is every write the file makes to it, widened from the
-- literal, and not whichever write came last: a write inside a function body
-- runs after the module loaded, so it widens the field rather than replacing it,
-- and a field only a body writes is absent until that body runs.
function M.moduleFieldWritesWidenAcrossTheFile()
    local source = [[
local M = {}
M.count = "s"
M.limit = 10
function M.bump()
   M.count = 5
end
function M.init()
   M.late = 7
end
return M
]]
    local parsed = parser.parse(source, "widen.lua")
    local diagnostics, moduleType = check.check(parsed, "widen.lua")
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    assert(moduleType and moduleType.tag == "shape", "the module did not export a shape")
    testAssert.equal(T.tostring(moduleType.byname.count), "integer | string", "a body write widens")
    testAssert.equal(T.tostring(moduleType.byname.limit), "integer", "a literal widens to its type")
    testAssert.equal(T.tostring(moduleType.byname.late), "integer?", "a body-only write is absent at load")
end

return M
