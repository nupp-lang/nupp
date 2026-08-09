-- Exhaustiveness: a chain that dispatches on a union of literals and leaves
-- through every branch is claiming to handle every member.
local parser = require("nupp.parser")
local check = require("fragment")
local envMod = require("nupp.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function diagsOf(src)
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local out = {}
   for j, d in ipairs(check.check(result, "test", env)) do out[j] = d.code end
   return table.concat(out, " ")
end

local function messageOf(src)
   local result = parser.parse(src, "test")
   local d = check.check(result, "test", env)[1]
   return d and d.msg or ""
end

local COLOR = "local type Color = 'red' | 'green' | 'blue'"

local M = {}

function M.aDispatchMissingAMemberIsReported()
   local src = COLOR .. table.concat({
      "",
      "local function name(c: Color): string",
      "    if c == 'red' then",
      "        return 'r'",
      "    elseif c == 'green' then",
      "        return 'g'",
      "    end",
      "end",
   }, "\n")
   assertEq(diagsOf(src), "NUPP2107")
   local msg = messageOf(src)
   assert(msg:find('"blue"', 1, true), "names the member: " .. msg)
   assert(msg:find('"green"', 1, true), "names the set: " .. msg)
end

function M.everyMissingMemberIsNamed()
   local msg = messageOf(COLOR .. table.concat({
      "",
      "local function name(c: Color): string",
      "    if c == 'red' then",
      "        return 'r'",
      "    end",
      "end",
   }, "\n"))
   assert(msg:find('"blue"', 1, true) and msg:find('"green"', 1, true),
      "both remaining members: " .. msg)
end

function M.aCompleteDispatchIsSilent()
   assertEq(diagsOf(COLOR .. table.concat({
      "",
      "local function name(c: Color): string",
      "    if c == 'red' then",
      "        return 'r'",
      "    elseif c == 'green' then",
      "        return 'g'",
      "    elseif c == 'blue' then",
      "        return 'b'",
      "    end",
      "end",
   }, "\n")), "")
end

function M.partialHandlingIsNotADispatch()
   -- the branch does not leave, so the chain is not claiming to be total
   assertEq(diagsOf(COLOR .. table.concat({
      "",
      "local function paint(c: Color): nil",
      "    if c == 'red' then",
      "        print('red!')",
      "    end",
      "end",
   }, "\n")), "")
end

function M.anElseBranchCoversTheRest()
   assertEq(diagsOf(COLOR .. table.concat({
      "",
      "local function name(c: Color): string",
      "    if c == 'red' then",
      "        return 'r'",
      "    else",
      "        return '?'",
      "    end",
      "end",
   }, "\n")), "")
end

function M.errorCountsAsLeaving()
   assertEq(diagsOf(COLOR .. table.concat({
      "",
      "local function name(c: Color): string",
      "    if c == 'red' then",
      "        return 'r'",
      "    elseif c == 'green' then",
      "        error('no')",
      "    end",
      "end",
   }, "\n")), "NUPP2107", "a raising branch still leaves")
end

function M.chainsOverDifferentSubjectsAreLeftAlone()
   assertEq(diagsOf(COLOR .. table.concat({
      "",
      "local function pick(a: Color, b: Color): string",
      "    if a == 'red' then",
      "        return 'a'",
      "    elseif b == 'green' then",
      "        return 'b'",
      "    end",
      "end",
   }, "\n")), "")
end

function M.nonEnumChainsAreUnaffected()
   assertEq(diagsOf(table.concat({
      "local function f(s: string): string",
      "    if s == 'a' then",
      "        return '1'",
      "    elseif s == 'b' then",
      "        return '2'",
      "    end",
      "end",
   }, "\n")), "", "an open type has no members to exhaust")
end

function M.theRemainingMembersNarrowInLaterBranches()
   -- subtraction composes, so a later branch sees only what is left
   assertEq(diagsOf(COLOR .. table.concat({
      "",
      "local c: Color",
      "if c == 'red' then",
      "else",
      "    local still: Color = c",
      "end",
   }, "\n")), "")
end

return M
