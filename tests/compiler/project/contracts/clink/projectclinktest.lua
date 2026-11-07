local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local process = fixture.process
local read = fixture.read
local exists = fixture.exists
local tempProject = fixture.tempProject
local remove = fixture.remove
local elsewhere = fixture.elsewhere
local libraryName = fixture.libraryName
local answerFrom = fixture.answerFrom
local callingProject = fixture.callingProject

local hostSystem = require("helpers.projectfixture").hostSystem
local compiledRuntimeSources = require("helpers.projectfixture").compiledRuntimeSources

local M = {}

function M.cDependencyLinksAStaticClosureIntoItsSharedLibrary()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      base = {kind = "c", linkage = "static", sources = {"native/base.c"}},
      core = {kind = "c", linkage = "static", dependencies = {"base"},
         sources = {"native/core.c"}},
      tiny = {kind = "c", dependencies = {"core"}, sources = {"native/tiny.c"},
         bindings = {header = "native/tiny.h"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
        ["src/main.nupp"] = "local tiny = require('tiny')\nreturn tiny.tiny_add(2, 3)\n",
        ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
        ["native/base.c"] = "int base_add(int a, int b) { return a + b; }\n",
        [
            "native/core.c"
        ] = table.concat(
            {"int base_add(int a, int b);", "int core_add(int a, int b) { return base_add(a, b); }",},
            "\n"
        ),
        [
            "native/tiny.c"
        ] = table.concat(
            {"int core_add(int a, int b);", "int tiny_add(int a, int b) { return core_add(a, b); }",},
            "\n"
        ),
    })
    testAssert.eq(project.build(dir), 0)
    testAssert.eq(answerFrom(dir), "5", "the shared parent contains its transitive static implementation")
    remove(dir)
end

-- A C dependency's library is the other thing a build produces and ships, and
-- it used to be named by the path the build wrote: absolute, which runs on one
-- machine, or relative to where the build ran, which runs from one directory.
-- It is now marked the way `@aot` code has always marked its library.
function M.cDependencyNamesItsLibraryRelativeToTheModuleThatLoadsIt()
    local dir = callingProject()
    testAssert.eq(project.build(dir), 0)

    local binding = read(dir .. "/out/generated/tiny.nupp")
    assert(
        binding:find('from "@lib/' .. libraryName("tiny") .. '"', 1, true),
        "the binding names the library relative to the output tree: " .. binding
    )
    assert(not binding:find(dir, 1, true), "and the build directory does not appear in it: " .. binding)

    -- The ordinary case first: a project built and run where it was built has to
    -- go on loading, since this changes how every existing one names its library.
    testAssert.eq(answerFrom(dir), "5", "an ordinary C dependency loads where the build left it")
    remove(dir)
end

-- A bundle is one file someone moves somewhere. The library its binding names
-- lives in the build directory the bundle was assembled in, which is not where
-- the bundle ends up, so the build puts a copy beside it -- exactly as it
-- already does for compiled `@aot` code.

-- A library the build did not put in the output tree is not part of what
-- travels with it, so it keeps the name it was given. `load` names a library
-- for the platform loader to find, and marking that would send the runtime
-- looking for a file beside a module instead.
function M.aPreexistingLibraryKeepsTheNameItWasGiven()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", load = "m", bindings = {header = "native/tiny.h"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
        ["src/main.nupp"] = "return true\n",
        ["native/tiny.h"] = "double tiny_scale(double value);\n",
    })
    testAssert.eq(project.build(dir), 0)
    local binding = read(dir .. "/out/generated/tiny.nupp")
    assert(binding:find('from "m"', 1, true), "a platform library name is left exactly as it was: " .. binding)
    remove(dir)
end

function M.cDependencyBuildsHeaderOnlyBridges()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", cppflags = {"-DTINY_SCALE=3"}, bindings = {
         header = "native/tiny.h",
         bridge = true,
         macros = {
            TINY_CLAMP = {parameters = {"int32", "int32", "int32"},
               result = "int32"},
            TINY_IGNORE = {parameters = {"int32"}},
         },
      }},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
        [
            "src/main.nupp"
        ] = table.concat(
            {
                "local tiny = require('tiny')",
                "local tripled: int32 = tiny.tiny_triple(14)",
                "local clamped: int32 = tiny.TINY_CLAMP(20, 2, 8)",
                "tiny.TINY_IGNORE(clamped)",
                "return tripled",
            },
            "\n"
        ),
        [
            "native/tiny.h"
        ] = [[
#include <stdint.h>
#ifndef TINY_SCALE
#define TINY_SCALE 1
#endif
static inline int32_t tiny_triple(int32_t value) { return value * TINY_SCALE; }
#define TINY_CLAMP(value, low, high) \
   ((value) < (low) ? (low) : ((value) > (high) ? (high) : (value)))
#define TINY_IGNORE(value) ((void)(value))
]],
    })
    testAssert.eq(project.build(dir), 0)
    local library = dir .. "/out/lib/" .. libraryName("tiny")
    assert(exists(library), "header-only bridge shared library emitted")
    assert(exists(dir .. "/out/generated/tiny_bridge.c"), "deterministic bridge source emitted")
    local binding = read(dir .. "/out/generated/tiny.nupp")
    assert(binding:find("local tiny_triple = __nupp_bridge_", 1, true), "inline exported under its logical name")
    assert(binding:find("local TINY_CLAMP = __nupp_bridge_", 1, true), "macro exported under its logical name")
    assert(binding:find("local TINY_IGNORE = __nupp_bridge_", 1, true), "void macro exported under its logical name")

    local triple = binding:match("cdef function (__nupp_bridge_[%da-f]+)%(value: int32%)")
    assert(triple, "physical inline symbol recorded")
    local clamp = binding:match("cdef function (__nupp_bridge_[%da-f]+)%(arg0: int32, arg1: int32, arg2: int32%)")
    assert(clamp, "physical macro symbol recorded")
    testAssert.eq(answerFrom(dir), "42", "bridge compilation receives the dependency's preprocessor flags")
    remove(dir)
end

function M.cDependencyRejectsInvalidMacroBridgeRecipes()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", bindings = {
         header = "native/tiny.h",
         macros = {
            TINY_ADD = {parameters = {"int32"}, result = "int32"},
         },
      }},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
        ["src/main.nupp"] = "return true\n",
        ["native/tiny.h"] = "#define TINY_ADD(a, b) ((a) + (b))\n",
    })
    assert(project.build(dir) ~= 0, "a requested macro with the wrong arity must fail the dependency build")
    assert(not exists(dir .. "/out/generated/tiny.nupp"), "an invalid recipe is not installed as a partial binding")
    remove(dir)
end

return M
