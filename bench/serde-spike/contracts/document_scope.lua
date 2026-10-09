local documents = require("nupp.serde.document")
local readers = require("nupp.serde.documentreader")
local map = documents.map({{key = documents.string("key"), value = documents.null()}})
local retainedKey, retainedValue
local input = readers.reader(map)
local ok, problem = pcall(input.readMap, input, {}, {
    apply = function(_, _, key, value)
        retainedKey, retainedValue = key, value
        key:readString()
    end,
})
assert(not ok and tostring(problem):find("consume both", 1, true), tostring(problem))
for _, view in ipairs({retainedKey, retainedValue}) do
    local live, expired = pcall(view.kind, view)
    assert(not live and tostring(expired):find("expired", 1, true), tostring(expired))
end
input:close()

local child
local root = readers.reader(documents.list({documents.string("one")}))
local ok = pcall(root.readList, root, {}, {
    apply = function(_, _, _, value)
        child = value
        error("stop", 0)
    end,
})
assert(not ok)
local live, expired = pcall(child.readString, child)
assert(not live and tostring(expired):find("expired", 1, true), tostring(expired))
root:close()
print("in-memory document readers expire on partial consumption and callback failure")
