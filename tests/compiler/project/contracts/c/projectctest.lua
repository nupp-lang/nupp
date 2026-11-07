local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local hash = fixture.hash
local process = fixture.process
local write = fixture.write
local read = fixture.read
local exists = fixture.exists
local tempProject = fixture.tempProject
local remove = fixture.remove
local libraryName = fixture.libraryName
local staticLibraryName = fixture.staticLibraryName
local answerFrom = fixture.answerFrom

local M = {}

function M.cDependencyBuildsSharedLibraryAndBindings()
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
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
        ["src/main.nupp"] = "return true\n",
        ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
        ["native/tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
    })
    testAssert.eq(project.build(dir), 0)
    assert(exists(dir .. "/out/lib/" .. libraryName("tiny")), "C shared library emitted")
    local binding = read(dir .. "/out/generated/tiny.nupp")
    assert(binding:find("module tiny", 1, true), "C binding is a declared module")
    assert(binding:find("export = {", 1, true), "C binding exports its collected declarations")
    assert(binding:find("cdef function tiny_add", 1, true), "typed binding generated")
    write(dir .. "/native/tiny.h", table.concat({"int tiny_add(int a, int b);", "int tiny_sub(int a, int b);",}, "\n"))
    write(
        dir .. "/native/tiny.c",
        table.concat(
            {"int tiny_add(int a, int b) { return a + b; }", "int tiny_sub(int a, int b) { return a - b; }",},
            "\n"
        )
    )
    testAssert.eq(project.build(dir), 0, "changed native input rebuilds")
    assert(
        read(dir .. "/out/generated/tiny.nupp"):find("cdef function tiny_sub", 1, true),
        "header change reimports bindings"
    )
    remove(dir)
end

function M.cDependencyBuildsStaticArchive()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", linkage = "static", sources = {"native/tiny.c"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
        ["src/main.nupp"] = "return true\n",
        ["native/tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
        [
            "native/main.c"
        ] = table.concat(
            {"int tiny_add(int a, int b);", "int main(void) { return tiny_add(2, 3) == 5 ? 0 : 1; }",},
            "\n"
        ),
    })
    testAssert.eq(project.build(dir), 0)
    local archive = dir .. "/out/lib/" .. staticLibraryName("tiny")
    assert(exists(archive), "C static archive emitted")
    assert(not exists(dir .. "/out/lib/" .. libraryName("tiny")), "a static dependency does not emit a shared library")

    local executable = dir .. "/native/static-consumer" .. (jit.os == "Windows" and ".exe" or "")
    testAssert.eq(
        process.run({
            "cc",
            dir .. "/native/main.c",
            archive,
            "-o",
            executable
        }),
        0,
        "the emitted archive links into a C executable"
    )
    testAssert.eq(process.run({executable}), 0, "the linked archive supplies its symbols")
    remove(dir)
end

function M.cDependencyBuildsSharedAndStaticArtifactsTogether()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", linkage = "both", sources = {"native/tiny.c"},
         bindings = {header = "native/tiny.h"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
        ["src/main.nupp"] = "local tiny = require('tiny')\nreturn tiny.tiny_add(2, 3)\n",
        ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
        ["native/tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
    })
    testAssert.eq(project.build(dir), 0)
    local shared = dir .. "/out/lib/" .. libraryName("tiny")
    local archive = dir .. "/out/lib/" .. staticLibraryName("tiny")
    assert(exists(shared), "both linkage emits the shared library")
    assert(exists(archive), "both linkage emits the static archive")
    testAssert.eq(answerFrom(dir .. "/out", dir), "5", "the generated binding loads the shared artifact")

    os.remove(archive)
    testAssert.eq(project.build(dir), 0, "a missing static half is rebuilt")
    assert(exists(archive), "the rebuilt dependency restores its static archive")
    remove(dir)
end

function M.cDependencyUsesTargetIndexedPrebuiltStaticArtifact()
    local producer = tempProject({
        [
            "nupp.lua"
        ] = [[return {dependencies = {tiny = {kind = "c", linkage = "static",
         sources = {"tiny.c"}}}, build = {entries = {"main"}, dependencies = {"tiny"}}}]],
        ["main.nupp"] = "return true\n",
        ["tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
    })
    testAssert.eq(project.build(producer), 0)
    local archive = producer .. "/build/lib/" .. staticLibraryName("tiny")
    local bytes = read(archive)
    local host = assert(require("nupp.compiler.targetlayout").hostKey())
    local consumer = tempProject({
        [
            "nupp.lua"
        ] = (
            [=[
return {
   include = {"src"},
   dependencies = {tiny = {kind = "c", linkage = "static",
      bindings = {header = "native/tiny.h"}, artifacts = {
         [%q] = {static = {path = %q, sha256 = %q, size = %d}},
      }}},
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]=]
        ):format(host, archive, hash.sha256(bytes), #bytes),
        ["src/main.nupp"] = "local tiny = require('tiny')\nreturn tiny.tiny_add\n",
        ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
    })
    testAssert.eq(project.build(consumer), 0, "a verified prebuilt artifact is selected for this target")
    testAssert.eq(
        read(consumer .. "/out/lib/" .. staticLibraryName("tiny")),
        bytes,
        "the selected target artifact is staged byte-for-byte"
    )
    write(archive, ("x"):rep(#bytes))
    testAssert.eq(project.build(consumer), 1, "a digest-valid manifest refuses changed prebuilt bytes")
    remove(consumer)
    remove(producer)
end

return M
