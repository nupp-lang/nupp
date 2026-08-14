local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local cabi = require("nupp.compiler.cabi")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(
         label or "mismatch", tostring(want), tostring(got)), 2)
   end
end

local function checked(source)
   local result = parser.parse(source, "src/game.nupp")
   assertEq(#result.errors, 0, "parse errors")
   local env = envMod.new(HERE .. "/..", {cache = false})
   local diagnostics, _, exports = check.check(
      result, "src/game.nupp", env, {moduleName = "game"})
   for _, diagnostic in ipairs(diagnostics) do
      if diagnostic.severity == "error" then
         error(diagnostic.code .. ": " .. diagnostic.msg, 2)
      end
   end
   return assert(exports), result
end

local SOURCE = [[
local game = {}

struct game.Position
    x: float
    y: float
end

struct game.Motion
    position: game.Position
    flags: uint32
end

return game
]]

local TARGET = "x86_64-unknown-linux-gnu"
local M = {}

function M.canonicalIdentityIsNominalAndModuleQualified()
   local exports = checked(SOURCE)
   local position = assert(exports.types.Position)
   local motion = assert(exports.types.Motion)
   assertEq(cabi.identity(position), "game.Position")
   assertEq(cabi.identity(motion), "game.Motion")
   local a = assert(cabi.aggregate(position, TARGET))
   local b = assert(cabi.aggregate(motion, TARGET))
   assert(a.typedef ~= b.typedef, "distinct declarations keep distinct C names")
   assertEq(a.typedef, "nupp_4_game_8_Position")
end

function M.descriptionCarriesTargetLayoutAndSemanticFingerprints()
   local exports = checked(SOURCE)
   local description = assert(cabi.aggregate(exports.types.Motion, TARGET))
   assertEq(description.schema, cabi.ABI)
   assertEq(description.target, TARGET)
   assertEq(description.size, 12)
   assertEq(description.alignment, 4)
   assertEq(description.fields[1].offset, 0)
   assertEq(description.fields[2].offset, 8)
   assert(#description.semanticFingerprint == 64, "semantic SHA-256")
   assert(#description.layoutFingerprint == 64, "layout SHA-256")
end

function M.headerOrdersByValueDependenciesAndAssertsEveryOffset()
   local exports = checked(SOURCE)
   local position = assert(cabi.aggregate(exports.types.Position, TARGET))
   local motion = assert(cabi.aggregate(exports.types.Motion, TARGET))
   local header = assert(cabi.header({position, motion}, {}, "GAME_NUPP_H"))
   local positionAt = assert(header:find("struct " .. position.tag, 1, true))
   local motionAt = assert(header:find("struct " .. motion.tag, 1, true))
   assert(positionAt < motionAt, "an embedded dependency is defined first")
   assert(header:find("offsetof(" .. motion.typedef .. ", position) == 0", 1, true))
   assert(header:find("offsetof(" .. motion.typedef .. ", flags) == 8", 1, true))
   local repeated = assert(cabi.header({position, motion}, {}, "GAME_NUPP_H"))
   assertEq(repeated, header, "header output is deterministic")
end

function M.oneFunctionRecordRendersTypedAndErasedPointers()
   local exports = checked(SOURCE)
   local position = exports.types.Position
   local pointer = require("nupp.compiler.types").ptr(position)
   local signature = cabi.functionRecord("integrate", {
      {name = "position", type = pointer, mode = "exclusive"},
      {name = "dt", type = require("nupp.compiler.types").float, mode = "plain"},
   }, nil)
   assertEq(assert(cabi.prototype(signature, false)),
      "void integrate(nupp_4_game_8_Position *position, float dt);")
   assertEq(assert(cabi.prototype(signature, true)),
      "void integrate(void *, float);")
end

function M.hostRuntimeLayoutAgreesWithTheCanonicalRecord()
   local exports, parsed = checked(SOURCE)
   local host = assert(require("nupp.compiler.target_layout").hostKey())
   local description = assert(cabi.aggregate(exports.types.Motion, host))
   local generated = require("nupp.compiler.gen").generate(parsed, "src/game.nupp")
   local game = assert(loadstring(generated, "@generated-game"))()
   local ffi = require("ffi")
   assertEq(ffi.sizeof(game.Motion), description.size, "host size")
   assertEq(ffi.alignof(game.Motion), description.alignment, "host alignment")
   for _, field in ipairs(description.fields) do
      assertEq(ffi.offsetof(game.Motion, field.name), field.offset,
         "host offset for " .. field.name)
   end
end

function M.layoutAndSemanticChangesAlterThePublishedFingerprints()
   local first = checked(SOURCE)
   local changed = checked(SOURCE:gsub("flags: uint32", "flags: uint16"))
   local a = assert(cabi.aggregate(first.types.Motion, TARGET))
   local b = assert(cabi.aggregate(changed.types.Motion, TARGET))
   assert(a.semanticFingerprint ~= b.semanticFingerprint, "field width is semantic")
   assert(a.layoutFingerprint ~= b.layoutFingerprint, "field width changes the ABI")

   local wide = checked(SOURCE:gsub("flags: uint32", "flags: number"))
   local lp64 = assert(cabi.aggregate(wide.types.Motion, TARGET))
   local ilp32 = assert(cabi.aggregate(wide.types.Motion, "i686-unknown-linux-gnu"))
   assert(lp64.layoutFingerprint ~= ilp32.layoutFingerprint, "target is fingerprinted")
   assert(lp64.alignment ~= ilp32.alignment or lp64.size ~= ilp32.size,
      "the 32- and 64-bit models produce observably distinct layouts")
end

function M.pointerRecursionUsesForwardDeclarations()
   local exports = checked([[
local game = {}
struct game.Node
    value: int32
    next: game.Node*
end
return game
]])
   local node = assert(cabi.aggregate(exports.types.Node, TARGET))
   assertEq(#node.dependencies, 0, "a pointer is not a by-value dependency")
   assertEq(node.pointerDependencies[1], exports.types.Node, "the recursive pointer is recorded")
   local header = assert(cabi.header({node}, {}, "NODE_H"))
   local forward = assert(header:find("typedef struct " .. node.tag, 1, true))
   local body = assert(header:find("struct " .. node.tag .. " {", 1, true))
   assert(forward < body, "the recursive tag is declared before its pointer field")
end

function M.byValueCyclesAreRejectedBeforeEmission()
   local source = [[
local game = {}
struct game.Left
    right: game.Right
end
struct game.Right
    left: game.Left
end
return game
]]
   local parsed = parser.parse(source, "src/game.nupp")
   local diagnostics = check.check(parsed, "src/game.nupp",
      envMod.new(HERE .. "/..", {cache = false}), {moduleName = "game"})
   assertEq(diagnostics[1] and diagnostics[1].code, "NUPP2201")
   assert(diagnostics[1].msg:find("contain itself", 1, true),
      "the source diagnostic explains why the layout is impossible")
end

return M
