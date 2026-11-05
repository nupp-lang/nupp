-- A suite owns its fixture store. Published fixtures remain immutable until
-- the suite ends; workers never share partially produced directories.
local digest = require("nupp.compiler.nativehash").digest
local json = require("serde.json")
local fixtures = {}

local function readall(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("a")
    file:close()
    return text
end

function fixtures.new()
    local owner, reason = os.mktempdir("nupp-vm-fixtures-")
    assert(owner, reason)
    local base = owner:tostring()
    local published, failures = {}, {}

    local function manifest(root)
        local entries = {}

        local function walk(directory, prefix)
            for name, kind in os.list(directory) do
                local relative = prefix .. name
                if kind == "directory" then
                    entries[#entries + 1] = {path = relative, kind = "directory"}
                    walk(directory .. "/" .. name, relative .. "/")
                else
                    assert(kind == "file", "fixture artifacts must be regular files or directories")
                    entries[
                        #entries + 1
                    ] = {
                        path = relative,
                        kind = "file",
                        digest = digest(readall(directory .. "/" .. name))
                    }
                end
            end
        end

        walk(root, "")
        table.sort(entries, function(a, b)
            return a.path < b.path
        end)

        return json.encodevalue(entries)
    end

    local function resolve(key, produce)
        assert(type(key) == "string" and key ~= "" and key:match("^[A-Za-z0-9._-]+$"), "invalid fixture key")
        assert(type(produce) == "function", "fixture producer must be a function")
        if failures[key] then
            error(failures[key], 0)
        end
        local previous = published[key]
        if previous then
            assert(manifest(previous.path) == previous.manifest, "immutable fixture was modified: " .. key)
            return previous.path, json.decodevalue(previous.value), true
        end
        local path = base .. "/" .. digest("nupp-test-fixture\0" .. key)
        assert(os.mkdir(path))
        local ok, value = pcall(function()
            local value = produce(path)
            return {path = path, value = json.encodevalue(value), manifest = manifest(path)}
        end)
        if not ok then
            os.remove(path, true)
            failures[key] = "fixture " .. key .. " failed: " .. tostring(value)
            error(failures[key], 0)
        end
        published[key] = value

        return path, json.decodevalue(value.value), false
    end

    return {
        resolve = resolve,
        close = function()
            owner:close()
        end
    }
end

return fixtures
