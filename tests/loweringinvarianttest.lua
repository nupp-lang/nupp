-- The rule that a lowering may not build a function inside a loop without saying why.
--
-- LuaJIT has no recording for the bytecode that builds a function, so a loop containing
-- one aborts recording, is blacklisted, and never compiles -- while the answers stay
-- right and every other test passes. That is how six lowerings got it wrong before
-- anyone looked. `nupp bc --check` reads the bytecode afterwards; the choke point in
-- `gen` catches it as the code is generated, so every test that compiles a loop is
-- already the corpus.
--
-- What is left to hold is the inventory. A reason is a declaration that this particular
-- body writes a local of its own site and therefore cannot be declared once for the
-- module -- not a licence, and not something to add without deciding to.

local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local env = envMod.new(HERE .. "/..")

local M = {}

local function generate(src)
   local result = parser.parse(src, "test.g.nupp")
   assert(#result.errors == 0, "syntax errors")
   local diags = check.check(result, "test.g.nupp", env)
   assert(#diags == 0, "check: " .. (diags[1] and diags[1].msg or ""))
   local code, genDiags = gen.generate(result, "test")
   assert(#genDiags == 0, "gen diagnostics")
   return code
end

local OWNED = table.concat({
   "cdef function free(takes value: voidptr)",
   "cdef function malloc(size: uint64): voidptr",
   "local function ownedMalloc(size: uint64): affine(voidptr, free)",
   "   return malloc(size)",
   "end",
}, "\n")

-- Every reason `gen` accepts today, and what each is. Adding a case here is the decision
-- this test exists to make deliberate: a new reason is a new loop that will never
-- compile, so it should not be possible to add one quietly.
local EXPECTED_REASONS = {
   capture = "the body sets this site's own capture flags",
   reinit = "the body sets this site's own reinit flag",
   move = "the body clears this site's own move flag",
   cheader = "a C header is declared once where it is imported",
   region = "the protected body reads and writes this region's own owners and flags",
   lazy = "the body defers an operand until the test that guards it has passed",
}

function M.theInventoryOfReasonsIsExactlyWhatIsExpected()
   local path = HERE .. "/../src/nupp/compiler/gen.nupp"
   local handle = assert(io.open(path, "rb"), "gen.nupp is missing")
   local source = handle:read("*a")
   handle:close()

   local block = assert(source:match("\n%s*reasons = {(.-)\n%s*},"),
      "gen.nupp no longer declares a `reasons` table; this test reads it")
   local found = {}
   for name, text in block:gmatch("(%w+)%s*=%s*\"([^\"]*)\"") do
      found[name] = text
   end

   for name, text in pairs(found) do
      assert(EXPECTED_REASONS[name],
         "a lowering gained a new reason to build a function inside a loop:\n  "
         .. name .. " = " .. text
         .. "\nThat loop will never compile. If it is genuinely unavoidable, add it here "
         .. "with why; otherwise declare the function once for the module with "
         .. "pluck.declareHelper and call it.")
      assert(EXPECTED_REASONS[name] == text,
         ("the reason for `%s` changed:\n  was: %s\n  now: %s"):format(
            name, EXPECTED_REASONS[name], text))
   end
   for name in pairs(EXPECTED_REASONS) do
      assert(found[name], "`" .. name .. "` is gone and should be dropped from this list")
   end
end

-- A reason is a declaration, not a licence to be broken: the constructs carrying one
-- still have to generate.
function M.theConstructsCarryingAReasonStillGenerate()
   local sources = {
      moveInALoop = OWNED .. "\n" .. table.concat({
         "local n = 0",
         "for i = 1, 4 do",
         "   local value = ownedMalloc(8)",
         "   n = n + 1",
         "   drop(value)",
         "end",
         "return n",
      }, "\n"),
      rawRoundTripInALoop = OWNED .. "\n" .. table.concat({
         "local n = 0",
         "for i = 1, 4 do",
         "   local value = ownedMalloc(8)",
         "   local raw",
         "   unsafe do",
         "      raw = unsafe release value",
         "      drop(unsafe adopt raw as affine(voidptr, free))",
         "   end",
         "   n = n + 1",
         "end",
         "return n",
      }, "\n"),
   }
   for name, source in pairs(sources) do
      local ok, code = pcall(generate, source)
      assert(ok, name .. " no longer generates: " .. tostring(code))
      assert(loadstring(code, "@" .. name), name .. " generated code that does not load")
   end
end

-- The control: a loop with nothing to lower builds nothing, so the rule is not simply
-- never reached.
function M.aPlainLoopBuildsNoFunctionAtAll()
   local code = generate(table.concat({
      "local n = 0",
      "for i = 1, 4 do",
      "   n = n + 1",
      "end",
      "return n",
   }, "\n"))
   local body = assert(code:match("for i = 1(.-)\nreturn n"), "the loop:\n" .. code)
   assert(not body:find("function", 1, true), "a counting loop built a function:\n" .. body)
end

return M
