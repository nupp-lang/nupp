-- The playground runner is checked source carried by the application VM, not
-- source assembled in JavaScript. Exercise it independently under stock 5.1.

dofile(assert(arg[1], "the checked application runtime bundle is required"))

local result = __nuppPlaygroundRun([[print("hello", 42)]])
assert(result:find('"stdout":"hello\\t42"', 1, true), result)

local ok, problem = pcall(__nuppPlaygroundRun, [[
print(string.rep("x", 1048577))
]])
assert(not ok, "oversized playground output was accepted")
assert(tostring(problem):find("output exceeded 1048576 bytes", 1, true), tostring(problem))

-- A materialized PEG matcher whose graph no specialization template covers runs
-- on LPeg, which a browser has to link into its host rather than load from a
-- file. Build one through the general backend and match with it: the bundle
-- carrying the PEG runtime and the host carrying an engine are two halves of
-- one answer, and either half alone makes the playground's PEG example compile
-- and then fail to run.
local peg = require("nupp.compiler.runtime.peg")
local matcher = peg.codegen({
   actions = {},
   captureful = true,
   graph = {
      nodes = {
         {"collect", 2},
         {"sequence", 3, 5},
         {"capture", 4},
         {"oneOrMore", 7},
         {"zeroOrMore", 6},
         {"sequence", 8, 3},
         {"set", "abcdefghijklmnopqrstuvwxyz"},
         {"literal", ","},
      },
      root = 1,
   },
   search = {plain = false, value = "[abcdefghijklmnopqrstuvwxyz]"},
   sets = {},
}, nil)
local fields = matcher("red,green")
assert(type(fields) == "table", "the general PEG backend returned " .. type(fields))
assert(table.concat(fields, "/") == "red/green", table.concat(fields, "/"))
