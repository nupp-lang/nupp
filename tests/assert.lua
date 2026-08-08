-- Assertions for the dependency-free test runner.  They deliberately stay
-- small, but name the values that differed instead of making a reader infer
-- them from a bare boolean expression.
local M = {}

local function show(value, seen, depth)
   depth = depth or 0
   local kind = type(value)
   if kind == "string" then return string.format("%q", value) end
   if kind ~= "table" then return tostring(value) end
   if depth >= 2 then return "{...}" end
   seen = seen or {}
   if seen[value] then return "<cycle>" end
   seen[value] = true
   local parts = {}
   for key, item in pairs(value) do
      parts[#parts + 1] = "[" .. show(key, seen, depth + 1) .. "]="
         .. show(item, seen, depth + 1)
   end
   table.sort(parts)
   seen[value] = nil
   return "{" .. table.concat(parts, ", ") .. "}"
end

local function fail(message, level)
   error(message, (level or 1) + 1)
end

function M.assert(value, message, ...)
   if value then return value, message, ... end
   local detail = "expected a truthy value, got " .. show(value)
   if message ~= nil then detail = detail .. ": " .. tostring(message) end
   fail(detail, 2)
end

function M.equal(actual, expected, message)
   if actual == expected then return actual end
   local detail = "expected " .. show(expected) .. ", got " .. show(actual)
   if message ~= nil then detail = detail .. ": " .. tostring(message) end
   fail(detail, 2)
end

function M.notEqual(actual, unwanted, message)
   if actual ~= unwanted then return actual end
   local detail = "did not expect " .. show(unwanted)
   if message ~= nil then detail = detail .. ": " .. tostring(message) end
   fail(detail, 2)
end

function M.matches(value, pattern, message)
   if type(value) == "string" and value:find(pattern) then return value end
   local detail = "expected " .. show(value) .. " to match " .. show(pattern)
   if message ~= nil then detail = detail .. ": " .. tostring(message) end
   fail(detail, 2)
end

function M.raises(fn, pattern)
   local ok, err = pcall(fn)
   if ok then fail("expected function to raise an error", 2) end
   if pattern and not tostring(err):find(pattern) then
      fail("expected error " .. show(err) .. " to match " .. show(pattern), 2)
   end
   return err
end

local skipped = {}

function M.skip(reason)
   error({skip = skipped, reason = reason}, 0)
end

function M.isSkip(value)
   return type(value) == "table" and value.skip == skipped
end

function M.skipReason(value)
   if M.isSkip(value) then return value.reason end
end

return M
