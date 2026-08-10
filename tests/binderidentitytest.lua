local types = require("nupp.compiler.types")
local modules = require("nupp.compiler.build.modules")

local M = {}

-- Two binders that shadow each other are two types with one name. The module
-- fingerprint decides whether a dependent rebuilds, so rendering both by name is
-- how an interface that changed compares unchanged and nothing downstream is told.
function M.shadowedBindersDoNotCollide()
   local outer = types.typevar("T", "m.nupp:10:generic")
   local inner = types.typevar("T", "m.nupp:40:generic")
   assert(outer ~= inner, "distinct binders should intern distinctly")
   local returnsOuter = types.func({outer, inner}, {outer})
   local returnsInner = types.func({outer, inner}, {inner})
   assert(returnsOuter ~= returnsInner, "the two signatures should be two types")
   local a = modules.typeFingerprint(returnsOuter)
   local b = modules.typeFingerprint(returnsInner)
   assert(a ~= b, "two signatures fingerprinted alike: " .. tostring(a))
end

-- The mirror. A binder's name is not its identity, so renaming one leaves every
-- dependent's compiled boundary exactly as it was. The two binders here carry
-- distinct identities because interning keys on identity and would otherwise hand
-- back the first type again, comparing it with itself.
function M.renamingABinderIsNotAChange()
   local named = types.func({types.typevar("T", "before:10:generic")},
      {types.typevar("T", "before:10:generic")})
   local renamed = types.func({types.typevar("Element", "after:10:generic")},
      {types.typevar("Element", "after:10:generic")})
   assert(named ~= renamed, "the two signatures should be two types")
   assert(modules.typeFingerprint(named) == modules.typeFingerprint(renamed),
      "renaming a binder read as a changed interface: "
      .. modules.typeFingerprint(named) .. " vs "
      .. modules.typeFingerprint(renamed))
end

-- A binder is one type wherever it appears, so a signature using one twice numbers
-- it once and a signature using two numbers both.
function M.bindersNumberByFirstEncounter()
   local first = types.typevar("T", "m.nupp:10:generic")
   local second = types.typevar("U", "m.nupp:20:generic")
   local one = modules.typeFingerprint(types.func({first, first}, {first}))
   local two = modules.typeFingerprint(types.func({first, second}, {second}))
   assert(one:find("typevar#1", 1, true), "no binder numbered: " .. one)
   assert(not one:find("typevar#2", 1, true), "one binder numbered twice: " .. one)
   assert(two:find("typevar#2", 1, true), "second binder unnumbered: " .. two)
end

return M
