local testAssert = require("nupp.test")
local T = require("nupp.compiler.types")
local members = require("nupp.compiler.types.members")

local M = {}

function M.semanticViewKeepsReadAndWriteCapabilitiesSeparate()
   local cell = T.shape({
      {name = "value", read = T.string, write = T.union({T.string, T.integer})},
      {name = "status", read = T.literal("ready", T.string)},
   }, {
      readKey = T.string,
      readValue = T.string,
      writeKey = T.string,
      writeValue = T.union({T.string, T.integer}),
   })
   local view = members.view(cell)
   testAssert.equal(#view.ordered, 2)
   testAssert.equal(view.ordered[1].name, "status")
   testAssert.equal(view.ordered[2].name, "value")
   testAssert.equal(view.byname.value.readType, T.string)
   testAssert.equal(view.byname.value.writeType, T.union({T.string, T.integer}))
   testAssert.equal(view.readIndexer.keyType, T.string)
   testAssert.equal(view.writeIndexer.valueType, T.union({T.string, T.integer}))
end

function M.constViewRemovesEveryWriteCapability()
   local cell = T.shape({{name = "value", type = T.string}}, {
      readKey = T.string,
      readValue = T.string,
      writeKey = T.string,
      writeValue = T.string,
   })
   local view = members.view(T.constOf(cell))
   testAssert.equal(view.byname.value.readType, T.string)
   testAssert.equal(view.byname.value.writeType, nil)
   testAssert.equal(view.readIndexer.valueType, T.string)
   testAssert.equal(view.writeIndexer, nil)
end

function M.intersectionViewComposesCapabilitiesOnce()
   local left = T.shape({{name = "value", read = T.string, write = T.string}})
   local right = T.shape({{name = "value", read = T.literal("ready", T.string), write = T.integer}})
   local view = members.view(T.intersection({left, right}))
   testAssert.equal(view.byname.value.readType,
      T.intersection({T.string, T.literal("ready", T.string)}))
   testAssert.equal(view.byname.value.writeType, T.union({T.string, T.integer}))
end

function M.unionViewExposesOnlySharedCapabilities()
   local left = T.shape({
      {name = "read", read = T.string},
      {name = "write", write = T.string},
   })
   local right = T.shape({
      {name = "read", read = T.integer},
      {name = "write", write = T.integer},
   })
   local view = members.view(T.union({left, right}))
   testAssert.equal(view.byname.read.readType, T.union({T.string, T.integer}))
   testAssert.equal(view.byname.read.writeType, nil)
   testAssert.equal(view.byname.write.readType, nil)
   testAssert.equal(view.byname.write.writeType, T.intersection({T.string, T.integer}))
end

local function method(receiver, mode, overrides)
   local base = T.func({receiver, T.string}, {T.string}, false, {"takes", mode})
   local fields = overrides or {}
   fields.paramNames = {"self", "value"}
   return T.funcWith(base, fields)
end

function M.unionMethodJoinKeepsTheSharedInvocationContract()
   local leftMethod = method(T.string, "takes", {noYield = true, sendable = true})
   local rightMethod = method(T.integer, "takes", {noYield = true, sendable = true})
   local left = T.shape({{name = "apply", read = leftMethod}})
   local right = T.shape({{name = "apply", read = rightMethod}})
   local joined = members.view(T.union({left, right})).byname.apply.readType
   testAssert.equal(joined.tag, "func")
   testAssert.equal(joined.paramModes[1], "takes", "receiver ownership mode")
   testAssert.equal(joined.paramModes[2], "takes", "argument ownership mode")
   testAssert.equal(joined.noYield, true, "shared suspension guarantee")
   testAssert.equal(joined.sendable, true, "shared sendability guarantee")
end

function M.unionMethodJoinRefusesDifferentOwnershipContracts()
   local left = T.shape({{name = "apply", read = method(T.string, "takes")}})
   local right = T.shape({{name = "apply", read = method(T.integer, "plain")}})
   local read = members.view(T.union({left, right})).byname.apply.readType
   testAssert.equal(read.tag, "union", "different ownership modes stay separate")
end

function M.unionMethodJoinRefusesCapabilityRelationsItCannotCompose()
   local left = T.shape({{name = "borrow", read = method(T.string, "plain", {borrowsParam = 1})}})
   local right = T.shape({{name = "borrow", read = method(T.integer, "plain", {borrowsParam = 1})}})
   local read = members.view(T.union({left, right})).byname.borrow.readType
   testAssert.equal(read.tag, "union", "borrow relations stay attached to their alternatives")
end

function M.semanticFingerprintUsesTheCallersTypeVocabulary()
   -- A vocabulary that describes the type, which is what the parameter is for. Not
   -- `t.id`: an id identifies an interned type without saying anything about it.
   local shape = T.shape({{name = "name", read = T.string}})
   testAssert.equal(members.fingerprint(shape, function(t) return "<" .. T.tostring(t) .. ">" end),
      "name:r=<string>:w=-")
end

-- `members.lookup` answers for one name what `members.view` answers for all of them, by
-- walking the same shapes separately. Nothing keeps the two in step but this: every
-- shape the view composes differently is asked both ways, for a name it has and a name
-- it does not.
function M.lookupAgreesWithTheViewItSkipsBuilding()
   local left = T.shape({
      {name = "read", read = T.string},
      {name = "both", read = T.string, write = T.string},
   })
   local right = T.shape({
      {name = "read", read = T.integer},
      {name = "both", read = T.integer, write = T.integer},
      {name = "onlyRight", read = T.string},
   })
   local indexed = T.shape({{name = "kept", read = T.string}},
      {readKey = T.string, readValue = T.string})

   local subjects = {
      left,
      right,
      indexed,
      T.constOf(left),
      T.intersection({left, right}),
      T.union({left, right}),
      T.optional(left),
      T.ptr(left),
      T.map(T.string, T.integer),
      T.string,
   }
   local names = {"read", "both", "onlyRight", "kept", "absent"}

   for _, subject in ipairs(subjects) do
      local view = members.view(subject)
      for _, name in ipairs(names) do
         local want, got = view.byname[name], members.lookup(subject, name)
         local label = ("%s . %s"):format(T.tostring(subject), name)
         if want == nil then
            testAssert.equal(got, nil, label .. " (view has no member)")
         else
            assert(got ~= nil, label .. ": the view has it and lookup does not")
            testAssert.equal(got.name, want.name, label .. " name")
            testAssert.equal(got.readType, want.readType, label .. " readType")
            testAssert.equal(got.writeType, want.writeType, label .. " writeType")
            testAssert.equal(got.declarationKind, want.declarationKind, label .. " declarationKind")
            testAssert.equal(got.definition, want.definition, label .. " definition")
            testAssert.equal(got.definitions and #got.definitions or 0,
               want.definitions and #want.definitions or 0, label .. " definitions")
         end
      end
   end
end

return M
