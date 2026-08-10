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
   local shape = T.shape({{name = "name", read = T.string}})
   assertEq(members.fingerprint(shape, function(t) return "<" .. t.id .. ">" end),
      "name:r=<string>:w=-")
end

return M
