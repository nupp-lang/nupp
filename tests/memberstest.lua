local T = require("nupp.compiler.types")
local members = require("nupp.compiler.members")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

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
   assertEq(#view.ordered, 2)
   assertEq(view.ordered[1].name, "status")
   assertEq(view.ordered[2].name, "value")
   assertEq(view.byname.value.readType, T.string)
   assertEq(view.byname.value.writeType, T.union({T.string, T.integer}))
   assertEq(view.readIndexer.keyType, T.string)
   assertEq(view.writeIndexer.valueType, T.union({T.string, T.integer}))
end

function M.constViewRemovesEveryWriteCapability()
   local cell = T.shape({{name = "value", type = T.string}}, {
      readKey = T.string,
      readValue = T.string,
      writeKey = T.string,
      writeValue = T.string,
   })
   local view = members.view(T.constOf(cell))
   assertEq(view.byname.value.readType, T.string)
   assertEq(view.byname.value.writeType, nil)
   assertEq(view.readIndexer.valueType, T.string)
   assertEq(view.writeIndexer, nil)
end

function M.intersectionViewComposesCapabilitiesOnce()
   local left = T.shape({{name = "value", read = T.string, write = T.string}})
   local right = T.shape({{name = "value", read = T.literal("ready", T.string), write = T.integer}})
   local view = members.view(T.intersection({left, right}))
   assertEq(view.byname.value.readType,
      T.intersection({T.string, T.literal("ready", T.string)}))
   assertEq(view.byname.value.writeType, T.union({T.string, T.integer}))
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
   assertEq(view.byname.read.readType, T.union({T.string, T.integer}))
   assertEq(view.byname.read.writeType, nil)
   assertEq(view.byname.write.readType, nil)
   assertEq(view.byname.write.writeType, T.intersection({T.string, T.integer}))
end

function M.semanticFingerprintUsesTheCallersTypeVocabulary()
   -- A vocabulary that describes the type, which is what the parameter is for. Not
   -- `t.id`: an id identifies an interned type without saying anything about it.
   local shape = T.shape({{name = "name", read = T.string}})
   assertEq(members.fingerprint(shape, function(t) return "<" .. T.tostring(t) .. ">" end),
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
            assertEq(got, nil, label .. " (view has no member)")
         else
            assert(got ~= nil, label .. ": the view has it and lookup does not")
            assertEq(got.name, want.name, label .. " name")
            assertEq(got.readType, want.readType, label .. " readType")
            assertEq(got.writeType, want.writeType, label .. " writeType")
            assertEq(got.declarationKind, want.declarationKind, label .. " declarationKind")
            assertEq(got.definition, want.definition, label .. " definition")
            assertEq(got.definitions and #got.definitions or 0,
               want.definitions and #want.definitions or 0, label .. " definitions")
         end
      end
   end
end

return M
