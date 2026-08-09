-- Curated diagnostic messages are reviewed as one artifact. Codes alone catch
-- behavior; this corpus catches wording, spans, help, and fix titles.
local parser = require("nupp.parser")
local check = require("fragment")
local envMod = require("nupp.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."
local FIXTURES = HERE .. "/fixtures/diagnostics"
local env = envMod.new(ROOT)

local function readFile(path)
   local file = assert(io.open(path, "rb"))
   local text = file:read("*a")
   file:close()
   return text
end

local function diagnostics(name, strict)
   local path = FIXTURES .. "/" .. name .. ".nupp"
   local parsed = parser.parse(readFile(path), path)
   if #parsed.errors > 0 then return parsed.errors end
   return check.check(parsed, path, env, {strict = strict})
end

local function render(name, values)
   local out = {"[" .. name .. "]"}
   for _, diagnostic in ipairs(values) do
      out[#out + 1] = ("%s %s %d:%d+%d"):format(
         diagnostic.code or "?", diagnostic.severity or "error",
         diagnostic.line, diagnostic.col, diagnostic.length or 0)
      out[#out + 1] = diagnostic.msg
      if diagnostic.help then out[#out + 1] = "help: " .. diagnostic.help end
      for _, fix in ipairs(diagnostic.fixes or {}) do
         out[#out + 1] = "fix: " .. fix.title
      end
   end
   return table.concat(out, "\n")
end

local EXPECTED = [[[syntax]
NUPP1004 error 2:1+5
expression expected; found "local"
NUPP1004 error 2:21+1
expression expected; found ")"
NUPP1002 error 5:1+0
'end' expected to close 'if'; found end of file
[checker]
NUPP2004 error 2:21+9
no field "horizonal" in {horizontal: number}
help: use the suggested field spelling
fix: change to `horizontal`
NUPP2002 error 5:12+5
return 1: string is not a number
NUPP2007 error 8:1+5
too many arguments (expected 1, got 2)
help: compare the call with the declared parameter list
NUPP2006 error 8:7+3
argument 1: string is not a number
help: compare the call with the declared parameter list
[lints]
NUPP2107 warning 4:5+2
every branch returns, so this handles "blue" | "green" | "red" and leaves "blue", "green" unhandled
help: add branches for "blue", "green" or add an else clause
NUPP2503 warning 10:22+4
number does not fit every int32; cast if the narrowing is intended
fix: cast to `int32`]]

-- The checker threads its context through a local named `c`, so `c.result` and
-- its neighbours are ordinary expressions in code and a rename artifact inside a
-- string. Four messages shipped reading "owned call c.result is ignored" after
-- one ran through the literals. Reading the sources catches the next one whether
-- or not a test happens to exercise that diagnostic.
local function stringLiteralsMentioningContext()
   local found = {}
   local list = io.popen("find '" .. ROOT .. "/src/nupp' -name '*.nupp'")
   for path in list:lines() do
      local line = 0
      for text in io.lines(path) do
         line = line + 1
         for literal in text:gmatch('"([^"]*)"') do
            if literal:find("%f[%w]c%.%a") then
               found[#found + 1] = ("%s:%d: %s"):format(
                  path:gsub("^.*/src/nupp/", ""), line, literal)
            end
         end
      end
   end
   list:close()
   return found
end

local M = {}

function M.noDiagnosticMessageQuotesTheCheckerContext()
   local found = stringLiteralsMentioningContext()
   if #found > 0 then
      error("a checker context expression leaked into a string literal:\n  "
         .. table.concat(found, "\n  "), 2)
   end
end

function M.curatedBadCodeMessagesStayUseful()
   local actual = table.concat({
      render("syntax", diagnostics("syntax")),
      render("checker", diagnostics("checker", true)),
      render("lints", diagnostics("lints", true)),
   }, "\n")
   if actual ~= EXPECTED then
      error("diagnostic golden changed:\n" .. actual, 2)
   end
end

return M
