-- The home page's code samples, held to the compiler that claims them.
--
-- Every other example in the project is checked by something: the reference
-- chapters by referencetest, the documentation site by doctest. The home page's
-- feature cards were the one place a sample could stop compiling in silence,
-- which is the most expensive place to be wrong, since it is the first Nupp
-- most readers ever see.
--
-- A card is a fragment rather than a program, so each is checked as `.g.nupp`:
-- the strict floor would demand context a card deliberately leaves out, while
-- gradual checking still resolves every name the card does spell out. Warnings
-- are allowed for the same reason -- a card declares things to show the syntax
-- and is not obliged to use them.

local json = require("testjson")
local home = require("nupp.compiler.doc.home")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local ROOT = HERE .. "/.."
local NUPP = ROOT .. "/bin/nupp"

local M = {}

function M.crlfFencesKeepTheirLanguage()
   local parsed = home.features(table.concat({
      "## Portable",
      "",
      "The checkout decides its line endings.",
      "",
      "```nupp",
      "local answer: number = 42",
      "```",
   }, "\r\n"))

   assert(#parsed == 1)
   assert(parsed[1].codeLanguage == "nupp", parsed[1].codeLanguage)
   assert(parsed[1].code == "local answer: number = 42", parsed[1].code)
end

--- The home page's feature cards, read from the page they are written on.
local function features()
   local file = assert(io.open(ROOT .. "/docs/index.md", "rb"), "the home page")
   local markdown = file:read("*a")
   file:close()

   return assert(home.parse(markdown).features, "the home page's features")
end

--- Every diagnostic one card's sample reports, as a project of its own.
local function diagnosticsFor(code)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write('return {include = {"."}}\n')
   manifest:close()
   local file = assert(io.open(dir .. "/sample.g.nupp", "wb"))
   file:write(code .. "\n")
   file:close()
   local pipe = assert(io.popen(("cd '%s' && '%s' check --json sample.g.nupp 2>/dev/null")
      :format(dir, NUPP)))
   local out = pipe:read("*a")
   pipe:close()
   os.execute("rm -rf '" .. dir .. "'")
   local ok, decoded = pcall(json.decode, out)
   assert(ok, "check --json did not produce JSON: " .. out)
   return decoded.diagnostics or {}
end

function M.everyHomePageSampleChecks()
   local checked = 0
   for index, feature in ipairs(features()) do
      if feature.code and (feature.codeLanguage or "nupp") == "nupp" then
         checked = checked + 1
         for _, diagnostic in ipairs(diagnosticsFor(feature.code)) do
            if diagnostic.severity == "error" then
               error(("the %q sample reports %s: %s\n%s"):format(
                  feature.title or index, diagnostic.code or "?",
                  diagnostic.message or "", feature.code), 2)
            end
         end
      end
   end
   assert(checked >= 5, "expected the home page to carry five samples")
end

return M
