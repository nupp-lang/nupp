local json = require("serde.json")
local documents = require("nupp.serde.internal.document")
local core = require("nupp.serde.internal.value")
local contexts = require("nupp.serde.internal.context")
local key = require("types").Key()
local builder = contexts.builder({}, {})
builder:set(key, "schema context")
local parent = builder:freeze()
local value = json.decodedocument(documents.documentAdapter(), '{"child":[null,18446744073709551615]}', parent)
local child = assert(value:get("child"))
assert(value:context():get(key) == "schema context")
assert(child:at(2):context():get(key) == "schema context")
assert(child:at(2):numbertoken() == "18446744073709551615")
assert(json.encodedocument(documents.documentAdapter(), value) == '{"child":[null,18446744073709551615]}')

local result, retained = {}, nil
local disposed = 0
local adapter = {
    readcontents = function(_, reader)
        retained = reader;
        return result
    end,
    discard = function(_, value)
        assert(value == result);
        disposed = disposed + 1
    end,
}
for _, bytes in ipairs({"", "null", "true"}) do
    local ok, problem = pcall(json.decodedocument, adapter, bytes)
    assert(not ok and tostring(problem):find("incomplete root value", 1, true), tostring(problem))
    assert(not pcall(retained.kind, retained), "root document reader escaped")
end
assert(disposed == 3, "a rejected owned document was not disposed exactly once")
local original = {}
adapter.readcontents = function(_, reader)
    retained = reader;
    error(original, 0)
end
local ok, problem = pcall(json.decodedocument, adapter, "null")
assert(not ok and problem.cause == original and disposed == 3)
assert(not pcall(retained.kind, retained))
print("document facade preserves exact contents, inherited context, expiry, and failed-result disposal")
