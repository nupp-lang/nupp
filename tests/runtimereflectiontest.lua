-- First-class record type witnesses and lazy runtime descriptors.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function compile(source)
   local parsed = parser.parse(source, "runtime_reflection.g.nupp")
   assertEq(#parsed.errors, 0, "syntax errors")
   local diagnostics = check.check(parsed, "runtime_reflection.g.nupp", env)
   assertEq(#diagnostics, 0, "check: " .. (diagnostics[1] and diagnostics[1].msg or ""))
   local code, generated = gen.generate(parsed, "runtime_reflection")
   assertEq(#generated, 0, "generation diagnostics")
   return code
end

local function run(source)
   local code = compile(source)
   local chunk, why = loadstring(code, "@runtime_reflection")
   assert(chunk, why and (why .. "\n---\n" .. code))
   return chunk(), code
end

local M = {}

function M.recordsExposeTypeWitnessesAndLazyDescriptors()
   local result, code = run([[
local record User
    id: integer
    name: string = "anonymous"
end

local witness: Type<User> = User
local legacy: metatable<User> = User
local value: User = new User(id = 7)
local first = User.reflect()
local second = User.reflect()
return {
    witness = witness == User,
    legacy = legacy == User,
    distinct = User ~= value,
    cached = first == second,
    name = first.name,
    field = first.fields[1].name,
}
]])
   assertEq(result.witness, true, "Type<T> witness")
   assertEq(result.legacy, true, "Type<T> metatable coercion")
   assertEq(result.distinct, true, "type is not an instance")
   assertEq(result.cached, true, "reflect cache")
   assertEq(result.name, "User", "descriptor name")
   assertEq(result.field, "id", "descriptor fields")
   assert(code:find("_G.nupp.__reflect.register", 1, true), code)
end

function M.doesNotEmitReflectionForUnusedRecords()
   local code = compile([[
local record Quiet
    value: integer
end
local quiet = new Quiet(value = 1)
return quiet.value
]])
   assertEq(code:find("__nupp.__reflect", 1, true), nil, "unused reflection runtime")
end

function M.jsonCodecIsAllocatedByTheRuntimeExtensionCache()
   local User = run([[
@derive(nupp.derive.JSON)
local record User
    id: integer
end
return User
]])
   local entry = _G.nupp.__derive.types[rawget(User, "__nuppDeriveKey")]
   assertEq(entry.codec, nil, "derive eagerly allocated a JSON codec")
   local info = User:reflect()
   local first = info:extension(_G.nupp.__reflect.json)
   local second = info:extension(_G.nupp.__reflect.json)
   assertEq(first, second, "extension cache")
   assertEq(entry.codec, first, "JSON extension owns codec allocation")
end

function M.jsonUsesOneTypeWitness()
   local result = run([[
@derive(nupp.derive.JSON)
local record User
    id: integer
end
local user = new User(id = 7)
local text = nupp.data.json.encode(user)
local explicit = nupp.data.json.encodeAs(User, user)
local restored, problem = nupp.data.json.decode(User, text)
return {text = text, explicit = explicit, id = restored and restored.id, problem = problem}
]])
   assertEq(result.text, '{"id":7}', "inferred JSON encode")
   assertEq(result.explicit, result.text, "explicit JSON encode")
   assertEq(result.id, 7, "type witness decode")
   assertEq(result.problem, nil, "type witness decode error")
end

return M
