local fixture = require("helpers.templatefixture")
local testAssert = fixture.testAssert
local exists = fixture.exists
local planWhileTampered = fixture.planWhileTampered

local M = {}

function M.aTemplateCannotRebindThePlannersLibraries()
    -- The planner runs after `template.lua` does, so a template that could reach
    -- the live `string` table could answer the planner's own path check. This one
    -- blinds every string primitive that check could use to `..`, then asks for it.
    local blind = [[
      local real = {}
      for _, name in ipairs({"gmatch", "find", "match", "sub", "byte"}) do
        real[name] = string[name]
      end
      local function hides(s)
        return type(s) == "string" and real.find(s, "..", 1, true) ~= nil
      end
      string.gmatch = function(s, p)
        if hides(s) then return function() return nil end end
        return real.gmatch(s, p)
      end
      string.find = function(s, ...)
        if hides(s) then return nil end
        return real.find(s, ...)
      end
      string.match = function(s, ...)
        if hides(s) then return nil end
        return real.match(s, ...)
      end
      string.sub = function(s, i, j)
        if hides(s) then return "" end
        return real.sub(s, i, j)
      end
      string.byte = function(s, ...)
        if hides(s) then return 120 end
        return real.byte(s, ...)
      end
      table.sort = function() end
      math.floor = function() return 1 end
      return {variables = {up = {default = ".."}}}
    ]]
    local plan, err, into, changed = planWhileTampered({["template.lua"] = blind, ["${up}/escaped.txt"] = "x"})
    testAssert.eq(table.concat(changed, ", "), "", "what the template changed in the host's libraries")
    testAssert.eq(plan, nil, "a template blinding the string library produces no plan")
    assert(err:find("leaves the destination", 1, true), err)
    assert(not exists(into), "and the destination was left alone")
end

function M.thePathCheckDoesNotAskTheSharedStringLibrary()
    -- The check is the last word on where a file goes, so it answers from
    -- primitives captured before any template ran rather than whatever a
    -- string's metatable reaches when it runs.
    local plan, err, into = planWhileTampered(
        {["template.lua"] = [[return {variables = {up = {default = ".."}}}]], ["a/${up}/${up}/escaped.txt"] = "x"},
        function()
            local real = {gmatch = string.gmatch, find = string.find, match = string.match, sub = string.sub}

            local function hides(s)
                return type(s) == "string" and real.find(s, "/..", 1, true) ~= nil
            end

            string.gmatch = function(s, p)
                if hides(s) then
                    return function()
                        return nil
                    end
                end

                return real.gmatch(s, p)
            end
            string.find = function(s, ...)
                if hides(s) then
                    return nil
                end
                return real.find(s, ...)
            end
            string.match = function(s, ...)
                if hides(s) then
                    return nil
                end
                return real.match(s, ...)
            end
            string.sub = function(s, i, j)
                if hides(s) then
                    return ""
                end
                return real.sub(s, i, j)
            end
        end
    )
    testAssert.eq(plan, nil, "a path check asking a blinded string library produces no plan")
    assert(err:find("leaves the destination", 1, true), err)
    assert(not exists(into), "and the destination was left alone")
end

return M
