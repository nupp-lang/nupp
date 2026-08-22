local parser = require("nupp.compiler.parser")
local check = require("fragment")
local annotated = require("nupp.compiler.annotatedlua")
local migrate = require("nupp.compiler.migrate")
local T = require("nupp.compiler.types")
local envMod = require("nupp.compiler.env")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s: want %s, got %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local M = {}

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
   assertEq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
   assert(moduleType and moduleType.tag == "shape", "annotated Lua did not export a shape")
   local find = moduleType.byname.find
   assert(find and find.tag == "func", "annotated function signature was not exported")
   assertEq(T.tostring(find.params[1]), "integer", "alias-backed parameter")
   assertEq(T.tostring(find.rets[1]), "User", "class-backed result")
   assert(exports.types.User and exports.types.User.tag == "nominal",
      "foreign class was not available as a type")
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
   assertEq(#diagnostics, 1, "one recoverable warning")
   assertEq(diagnostics[1].code, "NUPP1008")
   assertEq(diagnostics[1].severity, "warning")
   assert(moduleType and moduleType.tag == "func")
   assertEq(T.tostring(moduleType.params[1]), "any", "recovered parameter")
end

function M.annotationTextInsideStringsIsNotIngested()
   local source = [=[
local example = [[
---@alias Phantom integer
]]
return example
]=]
   local parsed = parser.parse(source, "strings.lua")
   assertEq(#annotated.tags(source, parsed.tokens), 0, "string contents are not comments")
   local diagnostics, _, exports = check.check(parsed, "strings.lua")
   assertEq(#diagnostics, 0)
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
   assertEq(#found, 3, "block annotation count")
   local diagnostics, moduleType = check.check(parsed, "blocks.lua")
   assertEq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
   assert(moduleType and moduleType.tag == "func")
   assertEq(T.tostring(moduleType.params[1]), "integer")
   assertEq(T.tostring(moduleType.rets[1]), "integer")
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
   assertEq(plan.destination, "identity.g.nupp")
   assert(plan.text:find("local type Id = integer", 1, true), "alias was not emitted")
   assert(plan.text:find("function module.keep(value: Id): Id", 1, true),
      "function annotations were not migrated")
   local migrated = parser.parse(plan.text, plan.destination)
   assertEq(#migrated.errors, 0, migrated.errors[1] and migrated.errors[1].msg)
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
   assertEq(#diagnostics, 1)
   assertEq(diagnostics[1].severity, "warning")
   assert(diagnostics[1].msg:find("ownership", 1, true))
   assert(moduleType and moduleType.tag == "func")
   assertEq(T.tostring(moduleType.params[1]), "any")
   assertEq(T.tostring(moduleType.rets[1]), "any")
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
   assertEq(#diagnostics, 1)
   assertEq(diagnostics[1].code, "NUPP1008")
   assertEq(diagnostics[1].severity, "warning")
   assert(moduleType and moduleType.tag == "func")
   assertEq(T.tostring(moduleType.params[1]), "any")
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
   assertEq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
   assert(moduleType and moduleType.tag == "shape")
   assert(exports.types.Client and exports.types.Client.tag == "nominal",
      "anonymous module did not retain its type-only export")
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
   assert(plan.text:find("value = value as string", 1, true),
      "positive cast was not migrated")
   assert(plan.text:find("assigned = assigned as integer", 1, true),
      "assignment type was not migrated")
   local migrated = parser.parse(plan.text, plan.destination)
   assertEq(#migrated.errors, 0, migrated.errors[1] and migrated.errors[1].msg)
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
   assertEq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
   assert(envMod.findRuntimeModulePath(env, "host") == nil,
      "an ambient type dependency became a runtime module")
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
   assert(plan.text:find("local name: string, count: integer", 1, true),
      "local types were not migrated positionally")
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
   assertEq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
   assertEq(T.tostring(moduleType.params[1]), "string")
   assertEq(T.tostring(moduleType.rets[1]), "string")

   local plan, problem = migrate.plan(source, "luadoc.lua", "luadoc")
   assert(plan, problem)
   assert(plan.text:find("function keep(value: string): string", 1, true))
   local invalid, invalidProblem = migrate.plan(source, "luadoc.lua", "mystery")
   assert(invalid == nil and invalidProblem:find("unsupported", 1, true))
end

return M
