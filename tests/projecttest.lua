local project = require("nupp.build.project")
local deps = require("nupp.build.deps")
local hash = require("nupp.build.hash")
local process = require("nupp.build.process")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function write(path, text)
   local dir = path:match("^(.*)/[^/]+$")
   if dir then os.execute("mkdir -p '" .. dir .. "'") end
   local f = assert(io.open(path, "wb"))
   f:write(text)
   f:close()
end

local function read(path)
   local f = assert(io.open(path, "rb"))
   local text = f:read("*a")
   f:close()
   return text
end

local function exists(path)
   local f = io.open(path, "rb")
   if not f then return false end
   f:close()
   return true
end

local function tempProject(files)
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   for name, text in pairs(files) do write(dir .. "/" .. name, text) end
   return dir
end

local function remove(dir)
   os.execute("rm -rf '" .. dir .. "'")
end

local function libraryName(name)
   if jit.os == "Windows" then return name .. ".dll" end
   if jit.os == "OSX" then return "lib" .. name .. ".dylib" end
   return "lib" .. name .. ".so"
end

local M = {}

function M.sha256KnownVectors()
   assertEq(hash.sha256(""),
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
   assertEq(hash.sha256("abc"),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
end

function M.windowsMkdirUsesNativePathAndIsIdempotent()
   local command = process.mkdirCommand("build/nupp", true)
   assertEq(table.concat(command, " "),
      "cmd /d /c if not exist build\\nupp mkdir build\\nupp")

   local posix = process.mkdirCommand("build/nupp", false)
   assertEq(table.concat(posix, " "), "mkdir -p build/nupp")
end

function M.manifestValidationRejectsInvalidReferencesAndCycles()
   local missing = tempProject({
      ["nupp.lua"] = [[
return {
   dependencies = {native = {kind = "c", sources = {"native.c"}}},
   build = {entries = {"main"}, dependencies = {"missing"}},
}
]],
   })
   local config, err = project.loadManifest(missing)
   assertEq(config, nil, "unknown target dependency rejects the manifest")
   assert(err:find("references unknown dependency missing", 1, true), err)
   remove(missing)

   local cyclic = tempProject({
      ["nupp.lua"] = [[
return {
   dependencies = {
      first = {kind = "c", dependencies = {"second"}},
      second = {kind = "c", dependencies = {"first"}},
   },
   build = {entries = {"main"}},
}
]],
   })
   config, err = project.loadManifest(cyclic)
   assertEq(config, nil, "dependency cycles reject the manifest")
   assert(err:find("dependency cycle involving", 1, true), err)
   remove(cyclic)
end

function M.taskDescriptionsUseEffectiveTargetConfiguration()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   build = {
      outDir = "out",
      entries = {"shared.main"},
      default = "other",
      targets = {
         default = {description = "The task named default"},
         other = {entries = {"other.main"}},
      },
   },
}
]],
   })
   local task, err = project.describeTasks(dir, "default")
   assert(task, err)
   assertEq(task.name, "default", "named default task is queried literally")
   assertEq(task.default, false, "query reports the configured default accurately")
   assertEq(task.outDir, "out", "task inherits the output directory")
   assertEq(task.entries[1], "shared.main", "task inherits shared entries")
   remove(dir)
end

function M.strictProjectChecksReachTheIncrementalChecker()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {entries = {"main"}}}
]],
      ["src/main.nupp"] = "return unknown_project_value\n",
   })
   local errorPath = os.tmpname()
   local originalStderr = io.stderr
   io.stderr = assert(io.open(errorPath, "wb"))
   local gradual = project.check(dir)
   local strict = project.check(dir, {strict = true})
   io.stderr:close()
   io.stderr = originalStderr
   os.remove(errorPath)
   assertEq(gradual, 0, "gradual project check permits unknown globals")
   assertEq(strict, 1,
      "strict project check rejects unknown globals")
   remove(dir)
end

function M.manifestStrictnessIsTheProjectAndEditorDefault()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, strict = true, build = {entries = {"main"}}}
]],
      ["src/main.nupp"] = "return unknown_project_value\n",
   })
   local errorPath = os.tmpname()
   local originalStderr = io.stderr
   io.stderr = assert(io.open(errorPath, "wb"))
   local status = project.check(dir)
   io.stderr:close()
   io.stderr = originalStderr
   os.remove(errorPath)
   assertEq(status, 1, "manifest strict mode reaches project checking")
   remove(dir)

   local invalid = tempProject({
      ["nupp.lua"] = [[return {strict = "yes", build = {entries = {"main"}}}]],
      ["main.nupp"] = "return true\n",
   })
   local config, err = project.loadManifest(invalid)
   assertEq(config, nil, "non-boolean strictness is rejected")
   assert(err:find("strict must be a boolean", 1, true), err)
   remove(invalid)
end

function M.manifestBuildDiscoversModulesAndPreservesPaths()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"app.main"},
      resources = {"src/app/*.d.nupp"}},
}
]],
      ["src/app/main.nupp"] = "local lib = require('lib.util')\nreturn lib\n",
      ["src/lib/util.nupp"] = "return { answer = 42 }\n",
      ["src/app/data.d.nupp"] = "return { ok: boolean }\n",
   })
   assertEq(project.build(dir), 0)
   assert(exists(dir .. "/out/app/main.lua"), "entry output keeps module path")
   assert(exists(dir .. "/out/lib/util.lua"), "dependency closure is emitted")
   assert(exists(dir .. "/out/app/data.d.nupp"), "resources keep include-relative path")
   assert(exists(dir .. "/out/.nupp-state.json"), "persistent state is written")
   assert(exists(dir .. "/out/.nupp-complete"), "completion marker is written last")
   local before = read(dir .. "/out/lib/util.lua")
   assertEq(project.build(dir), 0, "warm build succeeds")
   assertEq(read(dir .. "/out/lib/util.lua"), before, "warm artifact is unchanged")
   write(dir .. "/out/.nupp-state.json", "not json")
   assertEq(project.build(dir), 0, "corrupt state degrades to a cold build")
   assertEq(read(dir .. "/out/lib/util.lua"), before,
      "cold rebuild preserves identical artifacts")
   remove(dir)
end

-- Advice about a program is not a reason to refuse to compile it. A note and a
-- warning are said and stepped over; only an error withholds the generated Lua
-- and fails the build.
function M.onlyAnErrorStopsAManifestBuild()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"app.main"}},
}
]],
      ["src/app/main.nupp"] = table.concat({
         "local enum Color 'red' 'green' 'blue' end",
         "local function name(c: Color): string",
         "    if c == 'red' then",
         "        return 'r'",
         "    end",
         "end",
         "return { name = name }",
      }, "\n") .. "\n",
   })
   assertEq(project.build(dir), 0, "a warning does not fail the build")
   assert(exists(dir .. "/out/app/main.lua"),
      "a warning does not withhold the generated Lua")

   -- the same lint, turned up by the project, does stop it
   write(dir .. "/nupp.lua", [[
return {
   include = {"src"},
   lints = {["enum-exhaustiveness"] = "error"},
   build = {outDir = "out", entries = {"app.main"}},
}
]])
   remove(dir .. "/out")
   assert(project.build(dir) ~= 0, "raised to an error, it stops the build")
   assert(not exists(dir .. "/out/app/main.lua"),
      "and the generated Lua is withheld")
   remove(dir)
end

function M.moduleBuildCacheUsesDependencyInterfaces()
   local depV1 = table.concat({
      "local function answer(): number",
      "   return 1",
      "end",
      "return { answer = answer }",
   }, "\n")
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
      ["src/main.nupp"] = table.concat({
         "local lib = require('lib')",
         "local value: number = lib.answer()",
         "return value",
      }, "\n"),
      ["src/lib.nupp"] = depV1,
   })

   local cold = {}
   assertEq(project.build(dir, {stats = cold}), 0)
   assertEq(cold.checkedModules, 2, "cold build checks the closure")

   local warm = {}
   assertEq(project.build(dir, {stats = warm}), 0)
   assertEq(warm.checkedModules, 0, "warm build checks no modules")
   assertEq(warm.generatedModules, 0, "warm build generates no modules")
   assertEq(warm.reusedModules, 2, "warm build reuses the closure")

   write(dir .. "/src/lib.nupp", depV1:gsub("return 1", "return 2"))
   local bodyEdit = {}
   assertEq(project.build(dir, {stats = bodyEdit}), 0)
   assertEq(bodyEdit.checkedModules, 1,
      "body edit checks only the changed dependency")
   assertEq(bodyEdit.reusedModules, 1,
      "body edit reuses the dependent after interface cutoff")

   write(dir .. "/src/lib.nupp", table.concat({
      depV1:gsub("return 1", "return 2"),
      "-- Change the returned module interface without breaking consumers.",
   }, "\n"):gsub("return { answer = answer }",
      "return { answer = answer, label = 'answer' }"))
   local interfaceEdit = {}
   assertEq(project.build(dir, {stats = interfaceEdit}), 0)
   assertEq(interfaceEdit.checkedModules, 2,
      "interface edit rechecks the dependency and dependent")
   assertEq(interfaceEdit.reusedModules, 0,
      "changed interface invalidates the dependent record")
   remove(dir)
end

function M.ownershipContractsInvalidateIncrementalInterfaces()
   local function library(mode)
      return table.concat({
         "cdef function inspect(" .. mode .. " value: cstring)",
         "return { inspect = inspect }",
      }, "\n")
   end
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
      ["src/main.nupp"] = "local lib = require('lib')\nreturn lib\n",
      ["src/lib.nupp"] = library("borrows"),
   })

   assertEq(project.build(dir), 0)
   write(dir .. "/src/lib.nupp", library("takes"))
   local changed = {}
   assertEq(project.build(dir, {stats = changed}), 0)
   assertEq(changed.checkedModules, 2,
      "ownership-mode interface changes recheck dependents")
   remove(dir)
end

function M.ownCleanupListsInvalidateIncrementalInterfaces()
   local function library(cleanup)
      return table.concat({
         "@owned(" .. cleanup .. ")",
         "cdef function create(): voidptr",
         "return { create = create }",
      }, "\n")
   end
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
      ["src/main.nupp"] = "local lib = require('lib')\nreturn lib\n",
      ["src/lib.nupp"] = library("first_cleanup"),
   })

   assertEq(project.build(dir), 0)
   write(dir .. "/src/lib.nupp", library("second_cleanup"))
   local changed = {}
   assertEq(project.build(dir, {stats = changed}), 0)
   assertEq(changed.checkedModules, 2,
      "@owned cleanup changes recheck dependents")
   remove(dir)
end

function M.cDependencyBuildsSharedLibraryAndBindings()
   local dir = tempProject({
      ["nupp.lua"] = [[
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
   assertEq(project.build(dir), 0)
   assert(exists(dir .. "/out/lib/" .. libraryName("tiny")), "C shared library emitted")
   local binding = read(dir .. "/out/generated/tiny.nupp")
   assert(binding:find("cdef function tiny_add", 1, true), "typed binding generated")
   write(dir .. "/native/tiny.h", table.concat({
      "int tiny_add(int a, int b);",
      "int tiny_sub(int a, int b);",
   }, "\n"))
   write(dir .. "/native/tiny.c", table.concat({
      "int tiny_add(int a, int b) { return a + b; }",
      "int tiny_sub(int a, int b) { return a - b; }",
   }, "\n"))
   assertEq(project.build(dir), 0, "changed native input rebuilds")
   assert(read(dir .. "/out/generated/tiny.nupp")
      :find("cdef function tiny_sub", 1, true), "header change reimports bindings")
   remove(dir)
end

function M.cargoDependencyBuildsCdylib()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      tiny_rust = {kind = "cargo", manifest = "native/Cargo.toml",
         library = "tiny_rust", locked = false},
   },
   build = {outDir = "out", entries = {"main"},
      dependencies = {"tiny_rust"}},
}
]],
      ["src/main.nupp"] = "return true\n",
      ["native/Cargo.toml"] = [[
[package]
name = "tiny_rust"
version = "0.0.0"
edition = "2021"
[lib]
crate-type = ["cdylib"]
]],
      ["native/src/lib.rs"] = [[
#[no_mangle]
pub extern "C" fn tiny_double(value: i32) -> i32 { value * 2 }
]],
   })
   assertEq(project.build(dir), 0)
   assert(exists(dir .. "/out/lib/" .. libraryName("tiny_rust")),
      "Cargo cdylib copied into output")
   remove(dir)
end

-- A rock that is already in the source tree, so what is proved here is the
-- provider rather than the network: `luarocks make` builds what is there.
local TINY_ROCKSPEC = [[
package = "tinyrock"
version = "1.0-1"
source = { url = "file://tinyrock.lua" }
description = { summary = "A rock that ships with the project." }
dependencies = { "lua >= 5.1" }
build = { type = "builtin", modules = { tinyrock = "tinyrock.lua" } }
]]

local function tinyRockFiles()
   return {
      ["vendor/tinyrock/tinyrock.lua"] = "return {answer = 42}\n",
      ["vendor/tinyrock/tinyrock-1.0-1.rockspec"] = TINY_ROCKSPEC,
      ["src/main.nupp"] = "return true\n",
   }
end

function M.luarocksDependencyInstallsIntoTheProjectTree()
   local files = tinyRockFiles()
   files["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "luarocks", rock = "tinyrock", path = "vendor/tinyrock",
         rockspec = "vendor/tinyrock/tinyrock-1.0-1.rockspec"},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]]
   local dir = tempProject(files)
   assertEq(project.build(dir), 0)
   assert(exists(dir .. "/.rocks/share/lua/5.1/tinyrock.lua"),
      "the rock is installed into a tree the project owns")
   -- And into the running process's search path: a build that installs a
   -- renderer is a build that may render with it a moment later.
   assert(package.path:find(dir .. "/.rocks/share/lua/5.1/?.lua", 1, true),
      "the tree is added to the search path this process is using")

   -- A rock already in the tree at the version asked for is left alone, which
   -- is what keeps a warm build from reaching for the network.
   assertEq(project.build(dir), 0, "an installed rock rebuilds")
   remove(dir)
end

function M.rockDependenciesAreRefusedUnlessTheyArePinned()
   local loose = tempProject({
      ["nupp.lua"] = [[
return {
   dependencies = {lunamark = {kind = "luarocks"}},
   build = {entries = {"main"}},
}
]],
   })
   local config, err = project.loadManifest(loose)
   assertEq(config, nil, "a rock naming no version is refused")
   assert(err:find("must pin the rock", 1, true), err)
   remove(loose)

   local nested = tempProject({
      ["nupp.lua"] = [[
return {
   dependencies = {
      native = {kind = "c", sources = {"native.c"}},
      lunamark = {kind = "luarocks", version = "0.6.0-1",
         dependencies = {"native"}},
   },
   build = {entries = {"main"}},
}
]],
   })
   config, err = project.loadManifest(nested)
   assertEq(config, nil, "a rock does not declare what LuaRocks resolves")
   assert(err:find("LuaRocks resolves", 1, true), err)
   remove(nested)
end

-- A version in the manifest and a version in the rockspec are two claims about
-- one rock, and a build that installed whichever it read last would be pinned
-- to neither.
function M.rockVersionMustAgreeWithItsRockspec()
   local files = tinyRockFiles()
   files["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "luarocks", rock = "tinyrock", version = "2.0-1",
         path = "vendor/tinyrock",
         rockspec = "vendor/tinyrock/tinyrock-1.0-1.rockspec"},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]]
   local dir = tempProject(files)
   assertEq(project.build(dir), 1, "a disagreeing version fails the build")
   assert(not exists(dir .. "/.rocks"), "and installs nothing")
   remove(dir)
end

-- A bundle carries modules, not files, so what a rock's files are called on the
-- way in is what `require` calls them on the way out.
function M.bundledRockModulesAreNamedTheWayRequireFindsThem()
   local dir = tempProject({
      [".rocks/share/lua/5.1/lunamark.lua"] = "return {}\n",
      [".rocks/share/lua/5.1/lunamark/util.lua"] = "return {}\n",
      [".rocks/share/lua/5.1/lunamark/writer/html.lua"] = "return {}\n",
      [".rocks/share/lua/5.1/cosmo/init.lua"] = "return {}\n",
      [".rocks/share/lua/5.1/unasked.lua"] = "return {}\n",
   })
   local config = {
      dependencies = {
         lunamark = {
            kind = "luarocks", version = "0.6.0-1",
            bundle = {"lunamark.lua", "lunamark/**.lua", "cosmo/init.lua"},
         },
      },
   }
   local carried = deps.rockModules(dir, config, {dependencies = {"lunamark"}})
   local names = {}
   for _, module in ipairs(carried) do names[#names + 1] = module.name end
   assertEq(table.concat(names, " "),
      "cosmo lunamark lunamark.util lunamark.writer.html",
      "a directory module keeps its init, a nested one keeps its path")

   assertEq(deps.rockModules(dir, config, {dependencies = {}})[1], nil,
      "a target that asks for no rock carries none")
   local unasked = {
      dependencies = {lunamark = {kind = "luarocks", version = "0.6.0-1"}},
   }
   assertEq(deps.rockModules(dir, unasked, {dependencies = {"lunamark"}})[1], nil,
      "and a rock with no bundle globs is installed rather than carried")
   remove(dir)
end

-- What a test command has to be told, since it is a fresh interpreter that has
-- never heard of the tree the build installed into.
function M.rockPathsNameTheTreesATargetDependsOn()
   local config = {
      dependencies = {
         tiny = {kind = "luarocks", version = "1.0-1", tree = "vendor/rocks"},
         native = {kind = "c", sources = {"native.c"}},
      },
   }
   local paths = deps.rockPaths("/project", config,
      {dependencies = {"tiny", "native"}})
   assertEq(paths.path, "/project/vendor/rocks/share/lua/5.1/?.lua;"
      .. "/project/vendor/rocks/share/lua/5.1/?/init.lua",
      "the tree's Lua templates, in the order require reads them")
   assertEq(paths.cpath, "/project/vendor/rocks/lib/lua/5.1/"
      .. (jit.os == "Windows" and "?.dll" or "?.so"))
   assertEq(deps.rockPaths("/project", config, {dependencies = {"native"}}), nil,
      "a target with no rocks needs nothing added to its path")
end

function M.testCommandBuildsThenRunsArgv()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
   test = {argv = {"luajit", "test.lua"}},
}
]],
      ["src/main.nupp"] = "return true\n",
      ["test.lua"] = "local f=assert(io.open('test-ran','wb')); f:write('yes'); f:close()\n",
   })
   assertEq(project.test(dir), 0)
   assertEq(read(dir .. "/test-ran"), "yes")
   assert(exists(dir .. "/out/main.lua"), "test builds first")
   remove(dir)
end

return M
