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

local M = {}

local function nativeProject(body, build, extra)
    return tempProject({
        [
            "nupp.lua"
        ] = [[return {
include = {"src"},
dependencies = {tiny = {kind = "c", sources = {"native/tiny.c"}}},
build = ]]
        .. (
            build or '{outDir="out", entries={"main"}, dependencies={"tiny"}}'
        ) .. "}\n",
        ["src/main.nupp"] = body or "return true\n",
        ["native/tiny.c"] = "int tiny_add(int a, int b) { return a + b + " .. tostring(extra or 0) .. "; }\n",
    })
end

local LOGICAL_CALL = [[cdef function tiny_add(a: int32, b: int32): int32 from "tiny"
return tiny_add(20, 21)
]]

local RELOAD_CALL = [[module main
cdef function tiny_add(a: int32, b: int32): int32 from "tiny"
local M = {}
function M.answer(): int32
    return tiny_add(20, 21)
end
export = M
]]

local function reloadAnswer(dir)
    local away = elsewhere()
    fixture.write(
        away .. "/run.lua",
        (
            '_G.__nuppHost={hostAbi=1,hostFeatures={}}\npackage.path,package.cpath="",""\nlocal d=assert(loadfile(%q))()\nlocal c=d.install()\nprint("RELOAD " .. tostring(c.exports["main.answer"]()))\n'
        ):format(dir .. "/dist/app.nuppc")
    )
    local code, text = process.capture({"luajit", away .. "/run.lua"}, {cwd = away})
    remove(away)
    testAssert.eq(code, 0, text)
    assert(text:find("RELOAD 41", 1, true), text)
end

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
    testAssert.eq(
        answerFrom(dir .. "/out", dir),
        "5",
        "the shared parent contains its transitive static implementation"
    )
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
    testAssert.eq(answerFrom(dir .. "/out", dir), "5", "an ordinary C dependency loads where the build left it")
    remove(dir)
end

function M.cDependencyOutputTreeRunsWhereverItIsCopied()
    local dir = callingProject()
    testAssert.eq(project.build(dir), 0)

    local moved = dir .. "/moved"
    testAssert.eq(os.execute(("cp -r %q %q"):format(dir .. "/out", moved)), 0)
    -- Run from a directory that is neither the project nor the copy. Naming the
    -- library the way the build did answered here only from the project root.
    local away = elsewhere()
    testAssert.eq(answerFrom(moved, away), "5", "a copied output tree runs from anywhere")
    remove(away)
    remove(dir)
end

-- A bundle is one file someone moves somewhere. The library its binding names
-- lives in the build directory the bundle was assembled in, which is not where
-- the bundle ends up, so the build puts a copy beside it -- exactly as it
-- already does for compiled `@aot` code.
function M.aBundleCarriesTheLibraryItsBindingNames()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", sources = {"native/tiny.c"},
         bindings = {header = "native/tiny.h"}},
   },
   build = {
      targets = {
         app = {
            kind = "bundle",
            entries = {"main"},
            outDir = "out",
            output = "dist/app.lua",
            dependencies = {"tiny"},
         },
      },
   },
}
]],
        ["src/main.nupp"] = "local tiny = require('tiny')\n" .. "print('VALUE ' .. tostring(tiny.tiny_add(2, 3)))\n",
        ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
        ["native/tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
    })
    testAssert.eq(project.build(dir, {target = "app"}), 0)
    assert(
        exists(dir .. "/dist/lib/" .. libraryName("tiny")),
        "the library went with the bundle rather than staying in the build directory"
    )

    -- A bundle runs with nothing beside it but the library, and from anywhere.
    local away = elsewhere()
    local code, out = process.capture({"luajit", dir .. "/dist/app.lua"}, {cwd = away})
    testAssert.eq(code, 0, out)
    assert(out:find("VALUE 5", 1, true), "the bundle called through its binding: " .. out)
    remove(away)
    remove(dir)
end

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
    local ffi = require("ffi")
    ffi.cdef(("int32_t %s(int32_t); int32_t %s(int32_t, int32_t, int32_t);"):format(triple, clamp))
    local native = ffi.load(library)
    testAssert.eq(native[triple](4), 12, "bridge compilation receives the dependency's preprocessor flags")
    testAssert.eq(native[clamp](20, 2, 8), 8)
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

function M.aLogicalCDependencyNeedsNoGeneratedBinding()
    local dir = nativeProject(LOGICAL_CALL)
    testAssert.eq(project.build(dir), 0)
    assert(read(dir .. "/out/main.lua"):find("@lib/" .. libraryName("tiny"), 1, true))
    assert(not exists(dir .. "/out/generated/tiny.nupp"), "handwritten declarations need no generated binding")
    testAssert.eq(answerFrom(dir .. "/out", dir), "41")
    local moved = dir .. "/moved"
    assert(fixture.fs.mkdir(moved))
    assert(fixture.fs.copyFile(dir .. "/out/main.lua", moved .. "/main.lua"))
    assert(fixture.fs.copyFile(dir .. "/out/lib/" .. libraryName("tiny"), moved .. "/lib/" .. libraryName("tiny")))
    local away = elsewhere()
    testAssert.eq(answerFrom(moved, away), "41", "a copied output tree resolves its logical library")
    remove(away)
    remove(dir)
end

function M.logicalLibrariesStageTheirUsedClosureAndRefreshChangedFiles()
    local first, second = nativeProject(), nativeProject(nil, nil, 1)
    testAssert.eq(project.build(first), 0)
    testAssert.eq(project.build(second), 0)
    local filename = libraryName("tiny")
    local helper = libraryName("helper")
    assert(fixture.fs.copyFile(first .. "/out/lib/" .. filename, first .. "/vendor/" .. filename))
    assert(fixture.fs.copyFile(first .. "/out/lib/" .. filename, first .. "/vendor/" .. helper))
    fixture.write(
        first .. "/nupp.lua",
        [[return {
include={"src"},
libraries={physics={name="tiny", search={"vendor"}, dependencies={"helper"}},
helper={name="helper", search={"vendor"}, dependencies={"physics"}},
unused={name="absent", search={"not-built"}}},
build={kind="modules",outDir="out",entries={"main"}}
}]]
    )
    fixture.write(first .. "/src/main.nupp", LOGICAL_CALL:gsub('from "tiny"', 'from "physics"'))
    testAssert.eq(project.build(first), 0)
    assert(exists(first .. "/out/lib/" .. helper), "a used companion is staged through a cyclic dependency closure")
    assert(not exists(first .. "/out/lib/" .. libraryName("absent")), "an unused unresolved library is not staged")
    testAssert.eq(answerFrom(first .. "/out", first), "41")

    local function build()
        local produced = {}
        testAssert.eq(project.build(first, {testBuild = true, produced = produced}), 0)
        return produced
    end

    build()
    assert(build().testBuildReused, "an unchanged native input reuses its completed test build")
    assert(fixture.fs.copyFile(second .. "/out/lib/" .. filename, first .. "/vendor/" .. filename))
    assert(not build().testBuildReused, "changed native bytes invalidate a completed test artifact")
    testAssert.eq(answerFrom(first .. "/out", first), "42", "the staged copy does not shadow its updated source")
    assert(build().testBuildReused)
    remove(second)
    remove(first)
end

function M.logicalLibrariesTravelBesideBundlesAndComponents()
    for _, kind in ipairs({"bundle", "component"}) do
        local artifact = kind == "bundle" and "app.lua" or "app.nuppc"
        local build = (
            '{kind=%q,outDir="out",output=%q,entries={"main"},dependencies={"tiny"}}'
        ):format(kind, "dist/" .. artifact)
        local source = LOGICAL_CALL:gsub("return tiny_add%(20, 21%)", 'print("VALUE " .. tostring(tiny_add(20, 21)))')
        local dir = nativeProject(source, build)
        testAssert.eq(project.build(dir), 0)
        assert(
            exists(dir .. "/dist/lib/" .. libraryName("tiny")),
            kind .. " carries a library without a generated binding"
        )
        local away = elsewhere()
        assert(fixture.fs.copyFile(dir .. "/dist/" .. artifact, away .. "/" .. artifact))
        assert(fixture.fs.copyFile(dir .. "/dist/lib/" .. libraryName("tiny"), away .. "/lib/" .. libraryName("tiny")))
        local command = {"luajit", away .. "/" .. artifact}
        if kind == "component" then
            fixture.write(
                away .. "/run.lua",
                (
                    '_G.__nuppHost={hostAbi=1,hostFeatures={}}\nlocal d=assert(loadfile(%q))()\nlocal c=d.install()\nc.start()\n'
                ):format(away .. "/" .. artifact)
            )
            command = {"luajit", away .. "/run.lua"}
        end
        local code, text = process.capture(command, {cwd = away})
        testAssert.eq(code, 0, text)
        assert(text:find("VALUE 41", 1, true), text)
        remove(away)
        remove(dir)
    end
end

function M.logicalLibraryDestinationCollisionsAreRefused()
    local filename = libraryName("tiny")
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include={"src"},libraries={
first={name="tiny",search={"one"}},second={name="tiny",search={"two"}}},
build={outDir="out",entries={"main"}}}]],
        [
            "src/main.nupp"
        ] = [[cdef function first_value(): int32 from "first"
cdef function second_value(): int32 from "second"
return true
]],
        ["one/" .. filename] = "first library",
        ["two/" .. filename] = "second library",
    })
    local diagnostics = {}
    testAssert.eq(project.build(dir, {diagnostics = diagnostics}), 1)
    assert(fixture.json.encode(diagnostics):find("different contents", 1, true), fixture.json.encode(diagnostics))
    remove(dir)
end

function M.standaloneLogicalLibrariesUseStaticDependencies()
    local build = '{kind="binary",stub="nupp",standalone=true,outDir="out",output="out/app",entries={"main"},dependencies={"tiny"}}'
    local source = LOGICAL_CALL:gsub("return tiny_add%(20, 21%)", "print(tiny_add(20, 21))")
    local dir = nativeProject(source, build)
    testAssert.eq(project.build(dir), 0)
    assert(not exists(dir .. "/out/lib/" .. libraryName("tiny")))
    local code, text = process.capture({fixture.executableName(dir .. "/out/app")})
    testAssert.eq(code, 0, text)
    testAssert.eq(text:match("[^\r\n]+"), "41")
    remove(dir)
end

function M.logicalLibraryCollisionsFollowTheTargetFileSystem()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include={"src"},libraries={
upper={name="Tiny",search={"one"}},lower={name="tiny",search={"two"}}},
build={outDir="out",entries={"main"},layoutTarget="x86_64-pc-windows-msvc"}}]],
        [
            "src/main.nupp"
        ] = [[cdef function upper_value(): int32 from "upper"
cdef function lower_value(): int32 from "lower"
return true
]],
        ["one/Tiny.dll"] = "upper library",
        ["two/tiny.dll"] = "lower library",
    })
    local diagnostics = {}
    testAssert.eq(project.build(dir, {diagnostics = diagnostics}), 1)
    assert(fixture.json.encode(diagnostics):find("different contents", 1, true), fixture.json.encode(diagnostics))
    remove(dir)
end

function M.standaloneLogicalLibrariesRefuseSharedSidecars()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include={"src"},libraries={physics={name="tiny",search={"vendor"}}},
build={kind="binary",stub="nupp",standalone=true,outDir="out",output="out/app",entries={"main"}}}]],
        ["src/main.nupp"] = [[cdef function tiny_value(): int32 from "physics"
return true
]],
        ["vendor/" .. libraryName("tiny")] = "shared library",
    })
    local diagnostics = {}
    testAssert.eq(project.build(dir, {diagnostics = diagnostics}), 1)
    assert(fixture.json.encode(diagnostics):find("standalone", 1, true), fixture.json.encode(diagnostics))
    assert(not exists(dir .. "/out/lib/" .. libraryName("tiny")), "a standalone target never stages the sidecar")
    remove(dir)
end

function M.removingACaseAliasKeepsTheLibraryTheTargetStillOwns()
    local upper, lower = libraryName("Tiny"), libraryName("tiny")
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include={"src"},libraries={
upper={name="Tiny",search={"one"}},lower={name="tiny",search={"two"}}},
build={outDir="out",entries={"main"}}}]],
        [
            "src/main.nupp"
        ] = [[cdef function upper_value(): int32 from "upper"
cdef function lower_value(): int32 from "lower"
return true
]],
        ["one/" .. upper] = "same library",
        ["two/" .. lower] = "same library",
    })
    testAssert.eq(project.build(dir), 0)
    local kept = dir .. "/out/lib/" .. lower
    local configured, removeFile = package.config, os.remove
    -- A Windows deletion through either case names the same file. Model that
    -- one filesystem operation so the actual output-pruning path runs on POSIX.
    package.config = "\\" .. configured:sub(2)
    os.remove = function(path)
        if fixture.fs.absolute(path):lower() == fixture.fs.absolute(kept):lower() then
            return removeFile(kept)
        end
        return removeFile(path)
    end
    local ok, problem = pcall(function()
        fixture.write(
            dir .. "/nupp.lua",
            [[return {include={"src"},
libraries={lower={name="tiny",search={"two"}}},build={outDir="out",entries={"main"}}}]]
        )
        fixture.write(dir .. "/src/main.nupp", [[cdef function lower_value(): int32 from "lower"
return true
]])
        testAssert.eq(project.build(dir), 0)
        assert(exists(kept), "removing an alias deleted the library the target still owns")
    end)
    package.config, os.remove = configured, removeFile
    remove(dir)
    assert(ok, problem)
end

function M.reloadComponentsStageTheirConfiguredLogicalLibrary()
    local dir = nativeProject()
    testAssert.eq(project.build(dir), 0)
    local filename = libraryName("tiny")
    local selected = dir .. "/vendor/" .. filename
    assert(fixture.fs.copyFile(dir .. "/out/lib/" .. filename, selected))
    fixture.write(
        dir .. "/nupp.lua",
        [[return {include={"src"},
libraries={physics={name="tiny",search={"vendor"}}},
build={kind="component",reload=true,outDir="out",output="dist/app.nuppc",
entries={"main"},exports={"main.answer"}}}]]
    )
    fixture.write(dir .. "/src/main.nupp", RELOAD_CALL:gsub('from "tiny"', 'from "physics"'))
    testAssert.eq(project.build(dir), 0)
    testAssert.eq(
        read(dir .. "/dist/lib/" .. filename),
        read(selected),
        "the reload component carries its selected library"
    )
    reloadAnswer(dir)
    remove(dir)
end

function M.reloadComponentsPinFreshNativeProducers()
    local dir = nativeProject(
        RELOAD_CALL,
        '{kind="component",reload=true,outDir="out",output="dist/app.nuppc",entries={"main"},exports={"main.answer"},dependencies={"tiny"}}'
    )
    local selected = dir .. "/out/lib/" .. libraryName("tiny")
    assert(not exists(selected), "the producer has not built yet")
    testAssert.eq(project.build(dir), 0)
    local pinned = ("%q"):format(fixture.fs.canonical(selected))
    assert(
        read(dir .. "/out/main.lua"):find(pinned, 1, true),
        "the first reload generation pins its newly built producer"
    )
    testAssert.eq(read(dir .. "/dist/lib/" .. libraryName("tiny")), read(selected))
    reloadAnswer(dir)
    remove(dir)
end

return M
