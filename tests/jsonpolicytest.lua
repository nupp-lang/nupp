-- The public JSON policy is fixed by Nupp rather than inherited from a provider's
-- build options. These checks exercise the native boundary directly.

local open = assert(package.loadlib(assert(os.getenv("NUPP_JSON_LIBRARY")),
   "luaopen_jsonNative"))
local json = open()

local M = {}

function M.emptyContainersAreExplicit()
   assert(json.encode({}) == "{}", "a plain empty table is an object")
   assert(json.encode(json.asArray({})) == "[]", "asArray marks an empty array")
   assert(json.encode(json.asObject({})) == "{}", "asObject marks an empty object")
   assert(json.encode(json.EMPTY_ARRAY) == "[]", "EMPTY_ARRAY is serializable")
   assert(json.encode(json.EMPTY_OBJECT) == "{}", "EMPTY_OBJECT is serializable")
end

function M.nullDropsOrUsesTheSuppliedValue()
   local dropped = json.decode([[{"items":[1,null,2],"missing":null}]])
   assert(dropped.missing == nil and #dropped.items == 2 and dropped.items[2] == 2)
   local kept = json.decode([[{"items":[1,null,2],"missing":null}]], json.NULL)
   assert(kept.missing == json.NULL and kept.items[2] == json.NULL)
   assert(json.encode(kept) == [[{"items":[1,null,2],"missing":null}]]
      or json.encode(kept) == [[{"missing":null,"items":[1,null,2]}]])
end

function M.invalidNumbersAreAlwaysRejected()
   assert(not pcall(json.decode, "[NaN]"), "the decoder accepted NaN")
   assert(not pcall(json.decode, "[Infinity]"), "the decoder accepted Infinity")
   assert(not pcall(json.encode, 0 / 0), "the encoder accepted NaN")
end

return M
