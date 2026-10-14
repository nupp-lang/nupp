-- A suite owns its fixture store. Published fixtures remain immutable until
-- the suite ends; workers never share partially produced directories.
local files = require("nupp.io.files")
local digest = require("nupp.compiler.nativehash").digest
local json = require("nupp.codec.json")
local fixtures = {}

function fixtures.new()
    local owner, reason = files.createTemporaryDirectory({prefix = "nupp-vm-fixtures-"})
    assert(owner, reason)
    local base = owner:toString()
    local published, failures = {}, {}

    local function manifest(root)
        local entries = {}

        local function walk(directory, prefix)
            for _, entry in ipairs(assert(files.list(directory))) do
                local relative = prefix .. entry.name
                if entry.kind == "directory" then
                    entries[#entries + 1] = {path = relative, kind = "directory"}
                    walk(directory .. "/" .. entry.name, relative .. "/")
                else
                    assert(entry.kind == "file", "fixture artifacts must be regular files or directories")
                    entries[
                        #entries + 1
                    ] = {
                        path = relative,
                        kind = "file",
                        digest = digest(assert(files.read(directory .. "/" .. entry.name)))
                    }
                end
            end
        end

        walk(root, "")
        table.sort(entries, function(a, b)
            return a.path < b.path
        end)

        return json.encode(entries)
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
            return previous.path, json.decode(previous.value), true
        end
        local path = base .. "/" .. digest("nupp-test-fixture\0" .. key)
        assert(files.createDirectory(path))
        local ok, value = pcall(function()
            local value = produce(path)
            return {path = path, value = json.encode(value), manifest = manifest(path)}
        end)
        if not ok then
            files.remove(path, true)
            failures[key] = "fixture " .. key .. " failed: " .. tostring(value)
            error(failures[key], 0)
        end
        published[key] = value

        return path, json.decode(value.value), false
    end

    return {
        resolve = resolve,
        close = function()
            owner:close()
        end
    }
end

return fixtures
