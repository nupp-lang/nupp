-- Lua twin of catalog-derive.nupp, written as main generates the record: its
-- table, the recipe registered under its key, and each forwarding member
-- calling its helper through require with fresh constants.
package.preload["nupp.core.catalogderivehelpers"] = function()
    local exports = {}
    function exports.greetWith(name, other)
        return name .. " greets " .. other
    end
    function exports.describe(entry, prefix, tags)
        tags[#tags + 1] = "seen"
        return prefix .. ":" .. tostring(#tags) .. ":" .. tostring(entry.schema.data.label)
    end
    return exports
end
local Friend = {}
Friend.__index = Friend
local entry = {key = "Friend", mt = Friend, schema = {data = {label = "pal"}}}
Friend.greet = function(self, other)
    return require("nupp.core.catalogderivehelpers").greetWith(self.name, other)
end
Friend.describe = function(self)
    return require("nupp.core.catalogderivehelpers").describe(entry, "pal", {"a"})
end
local friend = setmetatable({name = "ann", mood = "calm"}, Friend)
local first = friend:describe()
local second = friend:describe()
return (friend:greet("bob") == "ann greets bob" and 1 or 0)
    + (first == "pal:2:pal" and 2 or 0)
    + (second == first and 4 or 0)
    + (friend.mood == "calm" and 8 or 0)
