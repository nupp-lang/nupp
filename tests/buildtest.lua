-- `nupp build` and `nupp run` over multi-file projects, driven through the
-- real binary so the CLI, the runtime loader, and the generator are all in
-- the loop.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local NUPP = HERE .. "/../bin/nupp"
local json = require("testjson")

local function assertEq(got, want, label)
    if got ~= want then
        error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch", tostring(want), tostring(got)), 2)
    end
end

local function tempProject(files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    for name, text in pairs(files) do
        local sub = name:match("^(.*)/[^/]+$")
        if sub then
            assert(os.execute("mkdir -p '" .. dir .. "/" .. sub .. "'") == 0)
        end
        local f = assert(io.open(dir .. "/" .. name, "wb"))
        f:write(text)
        f:close()
    end

    return dir
end

local function capture(cmd)
    local p = assert(io.popen(cmd .. " 2>&1"))
    local out = p:read("*a")
    p:close()
    return out
end

-- See lspclitest: a JSON capture reads stdout alone, because the launcher's
-- cold-cache progress line goes to stderr and would arrive in front of it.
local function captureJson(cmd)
    local p = assert(io.popen(cmd))
    local out = p:read("*a")
    p:close()
    return out
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end

    return false
end

local function read(path)
    local file = assert(io.open(path, "rb"))
    local contents = file:read("*a")
    file:close()
    return contents
end

local M = {}

local LIB = table.concat(
    {"local function double(n: number): number", "    return n * 2", "end", "return {double = double}",},
    "\n"
)

local APP = table.concat({"local lib = require('lib')", "print(lib.double(21))",}, "\n")

function M.buildEmitsTheDependencyClosure()
    local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n', ["lib.nupp"] = LIB, ["main.nupp"] = APP,})
    local out = capture(("cd '%s' && '%s' build main.nupp"):format(dir, NUPP))
    assertEq(out, "", "build is quiet on success: " .. out)
    assert(exists(dir .. "/main.lua"), "entry compiled")
    assert(exists(dir .. "/lib.lua"), "required module compiled too")
    assert(exists(dir .. "/nupp/runtime/managed.lua"), "generated ownership runtime is carried")
    -- and the result runs on plain LuaJIT, with no toolchain present
    local ran = capture(("cd '%s' && LUA_PATH='./?.lua;;' luajit main.lua"):format(dir))
    assertEq(ran, "42\n", "built output runs standalone")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.buildCarriesThePublicTestModule()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "build", entries = {"main"}},
}
]],
        ["src/main.nupp"] = [[
local test = require("nupp.test")
test.equal(42, 42)
return true
]],
    })
    local out = capture(("cd %q && %q build"):format(dir, NUPP))
    assertEq(out, "", "the public assertion module builds: " .. out)
    assert(exists(dir .. "/build/nupp/test.lua"), "the compiler-carried assertion module is linked into the project")
    local ran = capture(
        ("cd %q && LUA_PATH='./build/?.lua;;' luajit -e " .. "%q"):format(dir, "assert(require('main'))")
    )
    assertEq(ran, "", "the linked assertion module runs under plain LuaJIT")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.explicitBuildCreatesItsOutputDirectory()
    local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n', ["main.nupp"] = "return 42\n",})
    local out = capture(("cd '%s' && '%s' build -o nested/out main.nupp"):format(dir, NUPP))
    assertEq(out, "", "explicit build creates its output directory: " .. out)
    assert(exists(dir .. "/nested/out/main.lua"), "explicit build writes beneath the requested directory")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.explicitBuildPreservesModulePathsAndNormalizesDuplicates()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"."}}\n',
        ["a/init.nupp"] = "return {name = 'a'}\n",
        ["b/init.nupp"] = "return {name = 'b'}\n",
        [
            "main.nupp"
        ] = table.concat(
            {"local a = require('a.init')", "local b = require('b.init')", "return a.name .. b.name", "",},
            "\n"
        ),
    })
    local out = captureJson(("cd %q && %q build --json -o out ./main.nupp main.nupp"):format(dir, NUPP))
    local report = json.decode(out)
    assert(report.ok, "the explicit dependency build succeeds: " .. out)
    assert(
        #report.written == 4,
        "the normalized entry, its dependencies and ownership runtime are each emitted once: " .. out
    )
    assert(exists(dir .. "/out/main.lua"), "the normalized entry has one output")
    assert(
        exists(dir .. "/out/a/init.lua") and exists(dir .. "/out/b/init.lua"),
        "same-named dependencies retain their module directories"
    )
    local ran = capture(
        ("cd %q && LUA_PATH='./out/?.lua;;' luajit -e %q"):format(dir, "assert(require('main') == 'ab')")
    )
    assertEq(ran, "", "the mirrored output tree is directly requireable")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.runLoadsModulesFromSource()
    local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n', ["lib.nupp"] = LIB, ["main.nupp"] = APP,})
    -- no build step: the runtime loader compiles requires on demand
    local ran = capture(("cd '%s' && '%s' run main.nupp"):format(dir, NUPP))
    assertEq(ran, "42\n", "multi-file program runs straight from source")
    assert(not exists(dir .. "/lib.lua"), "running leaves no artifacts")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.buildReportsErrorsInDependencies()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"."}}\n',
        [
            "lib.nupp"
        ] = "local function double(n: number): string\n"
        .. "    return n * 2\n"
        .. "end\n"
        .. "return {double = double}\n",
        ["main.nupp"] = APP,
    })
    local out = capture(("cd '%s' && '%s' build main.nupp"):format(dir, NUPP))
    assert(out:find("NUPP2002", 1, true), "a type error inside a dependency is reported: " .. out)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.declarationFilesEmitNoArtifact()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"."}}\n',
        ["shape.d.nupp"] = "local area: function(r: number): number\n" .. "return {area = area}\n",
        ["main.nupp"] = "local shape = require('shape')\n" .. "local n: number = shape.area(2)\nreturn n\n",
    })
    local out = capture(("cd '%s' && '%s' build main.nupp"):format(dir, NUPP))
    assertEq(out, "", "declaration-backed build succeeds: " .. out)
    assert(exists(dir .. "/main.lua"), "entry compiled")
    assert(not exists(dir .. "/shape.lua"), "a declaration file describes an interface and emits nothing")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.declarationFilesPreservePropertyCapabilities()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"."}}\n',
        [
            "cell.d.nupp"
        ] = table.concat(
            {
                "local cell: {",
                "    readonly value: string,",
                "    writeonly value: string | integer,",
                "    readonly [string]: string,",
                "    writeonly [string]: string | integer",
                "}",
                "return cell",
            },
            "\n"
        ),
        [
            "main.nupp"
        ] = table.concat(
            {
                "local cell = require('cell')",
                "cell.value = 42",
                "local value: string = cell.value",
                "cell['answer'] = 42",
                "local indexed: string? = cell['answer']",
                "local input: {readonly value: string | integer} = cell",
                "local output: {writeonly value: string} = cell",
                "return {value, indexed, input, output}",
            },
            "\n"
        ),
    })
    local out = capture(("cd '%s' && '%s' build main.nupp"):format(dir, NUPP))
    assertEq(out, "", "property capabilities survive declaration files: " .. out)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.importCWritesAModule()
    -- import-c output carries cdef statements, which generate bindings at
    -- runtime, so it is a module and must be built like one
    local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n'})
    local out = capture(("cd '%s' && '%s' import-c '%s/fixtures/mini.h' --lib mini"):format(dir, NUPP, HERE))
    assert(out:find("mini.nupp", 1, true), "names the module it wrote: " .. out)
    assert(exists(dir .. "/mini.nupp"), "output is a module, not a .d.nupp")
    assert(not exists(dir .. "/mini.d.nupp"), "no declaration file written")
    os.execute("rm -rf '" .. dir .. "'")
end

-- A positional is a source file and a target is named with `--target`, so a manifest
-- target's name in first position is a mistake the report has to name. It used to reach
-- the compiler as a path, and a directory that does not read as a module was all that
-- was left to say about it.
function M.cliTellsATargetNameFromASourceFile()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {
   include = {"src"},
   build = {targets = {docs = {kind = "docs", sources = {"src"}, outDir = "site"}}},
}]],
        ["src/mini.nupp"] = "function value(): number return 1 end\n",
        ["docs/home.md"] = "# Home\n",
    })

    local named = capture(("cd '%s' && '%s' build docs"):format(dir, NUPP))
    assert(
        named:find("docs names a build target rather than a source file", 1, true),
        "a target name in first position is named as one: " .. named
    )
    assert(named:find("--target docs", 1, true), "the report says how to build it: " .. named)
    assert(named:find("nupp help build", 1, true), "validation errors point to command help: " .. named)
    os.execute("rm -rf '" .. dir .. "'")
end

-- Every failure carries a reason. A directory opens on POSIX and reads as nothing, so
-- the read used to fail with no second result and the command printed the word "nil"
-- where the path belonged.
function M.readingSomethingThatIsNotAFileSaysWhy()
    local dir = tempProject({["src/mini.nupp"] = "function value(): number return 1 end\n"})

    local directory = capture(("cd '%s' && '%s' check src"):format(dir, NUPP))
    assert(directory:find("src is a directory", 1, true), "a directory says it is one: " .. directory)
    assert(not directory:find("nupp: nil", 1, true), "no failure reports itself as nil: " .. directory)

    local missing = capture(("cd '%s' && '%s' check nosuch.nupp"):format(dir, NUPP))
    assert(missing:find("nosuch.nupp", 1, true), "a missing file is named: " .. missing)
    assert(not missing:find("nupp: nil", 1, true), "no failure reports itself as nil: " .. missing)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.cliProvidesCommandHelpAndValidatesOptions()
    local help = capture(("'%s' help build"):format(NUPP))
    assert(help:find("Build source files", 1, true), "build help has a command summary: " .. help)
    assert(help:find("--target NAME", 1, true), "build help documents target selection: " .. help)
    assert(help:find("--standalone", 1, true), "build help documents self-contained native linking: " .. help)

    local missing = capture(("'%s' build --target"):format(NUPP))
    assert(missing:find("option --target requires a value", 1, true), "missing option values are rejected: " .. missing)
    assert(missing:find("nupp help build", 1, true), "validation errors point to command help: " .. missing)

    local unknown = capture(("'%s' check --wat"):format(NUPP))
    assert(unknown:find("unknown option --wat", 1, true), "unknown options are rejected: " .. unknown)
end

function M.buildAndCheckResolveTheSameDialectOption()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"."}, build = {entries = {"main"}, ' .. 'dialect = "lua51"}}\n',
        ["main.nupp"] = "return 42\n",
    })
    local native = require("testjson").decode(captureJson(("cd '%s' && '%s' build main.nupp --json"):format(dir, NUPP)))
    assertEq(native.dialect, "luajit", "an explicit build defaults to LuaJIT")
    local nativeCode = read(dir .. "/main.lua")

    local explicitNative = require(
        "testjson"
    ).decode(captureJson(("cd '%s' && '%s' build --dialect luajit main.nupp --json"):format(dir, NUPP)))
    assertEq(explicitNative.dialect, "luajit", "LuaJIT may be selected explicitly")
    assertEq(read(dir .. "/main.lua"), nativeCode, "omitted and explicit LuaJIT dialects generate byte-identically")

    local portable = require(
        "testjson"
    ).decode(captureJson(("cd '%s' && '%s' build --dialect lua51 main.nupp --json"):format(dir, NUPP)))
    assertEq(portable.dialect, "lua51", "an explicit build reports its dialect")
    local portableCode = read(dir .. "/main.lua")
    assert(portableCode ~= nativeCode, "the portable dialect carries its compatibility floor")
    assert(
        portableCode:find("_G.loadstring or _G.load", 1, true),
        "portable prelude loading works across the stock Lua versions"
    )
    assert(
        not nativeCode:find("_G.loadstring or _G.load", 1, true),
        "the compatibility lookup costs nothing in native output"
    )

    local checked = require(
        "testjson"
    ).decode(captureJson(("cd '%s' && '%s' check --dialect lua51 main.nupp --json"):format(dir, NUPP)))
    assertEq(checked.dialect, "lua51", "check reports the same resolved dialect")

    local configuredBuild = require("testjson").decode(captureJson(("cd '%s' && '%s' build --json"):format(dir, NUPP)))
    assertEq(configuredBuild.dialect, "lua51", "build inherits the manifest dialect")
    local configuredCheck = require("testjson").decode(captureJson(("cd '%s' && '%s' check --json"):format(dir, NUPP)))
    assertEq(configuredCheck.dialect, "lua51", "check inherits the manifest dialect")

    local rejected = capture(("cd '%s' && '%s' check --dialect lua54 main.nupp"):format(dir, NUPP))
    assert(
        rejected:find("option --dialect does not take lua54; expected luajit, luajit-compat, lua51", 1, true),
        "the command grammar rejects unsupported dialects: " .. rejected
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.cliProvidesHelpForMainAndEverySubcommand()
    local main = capture(("'%s' --help"):format(NUPP))
    assert(main:find("Usage:\n  nupp <command>", 1, true), "--help prints main help: " .. main)
    assert(main:find("Commands:", 1, true), "main help lists commands: " .. main)

    local commands = {
        "ast",
        "check",
        "fmt",
        "build",
        "clean",
        "tasks",
        "test",
        "doc",
        "fixpoint",
        "run",
        "import-c",
        "rock",
        "lsp",
        "help",
    }
    for _, command in ipairs(commands) do
        local out = capture(("'%s' %s --help"):format(NUPP, command))
        assert(out:find("Usage:", 1, true), command .. " --help did not print command help: " .. out)
        assert(not out:find("No such file", 1, true), command .. " --help was interpreted as an input: " .. out)
    end
end

function M.astCommandDumpsTextAndJsonSyntaxTrees()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"."}}\n',
        ["sample.nupp"] = "local answer: number = 20 + 22\nreturn answer\n",
    })
    local text = capture(("cd '%s' && '%s' ast sample.nupp"):format(dir, NUPP))
    assert(text:find("chunk\n  block\n    localStmt\n", 1, true), "text dump indents nested nodes: " .. text)
    assert(text:find('      local "local"\n', 1, true), "text dump identifies and quotes tokens: " .. text)
    assert(text:find("      binop\n", 1, true), "text dump includes indented expressions: " .. text)

    local encoded = capture(("cd '%s' && '%s' ast sample.nupp --json"):format(dir, NUPP))
    local decoded = require("testjson").decode(encoded)
    assertEq(decoded.file, "sample.nupp", "JSON identifies the input")
    assertEq(decoded.root.tag, "node", "JSON distinguishes nodes")
    assertEq(decoded.root.kind, "chunk", "JSON includes the root production")
    assertEq(#decoded.errors, 0, "valid input has no parse errors")

    local function containsKind(value, kind)
        if value.kind == kind then
            return true
        end
        for _, child in ipairs(value.children or {}) do
            if containsKind(child, kind) then
                return true
            end
        end

        return false
    end

    assert(containsKind(decoded.root, "binop"), "JSON includes structural expression children")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.astCommandDumpsRecoveredTreesOnParseErrors()
    local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n', ["broken.nupp"] = "local = 1\nreturn 2\n",})
    local out = capture(("cd '%s' && '%s' ast broken.nupp"):format(dir, NUPP))
    assert(out:find("chunk\n  block", 1, true), "recovered tree is printed: " .. out)
    assert(out:find("error:", 1, true), "parse diagnostics are reported: " .. out)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.cleanRemovesConfiguredOutputsSafely()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   build = {
      default = "app",
      targets = {
         app = {kind = "modules", entries = {"app.main"}, outDir = "out"},
         docs = {kind = "docs", sources = {"src"}, outDir = "site"},
      },
   },
   test = {build = "app", argv = {"luajit", "tests/run.lua"},
      env = {MODE = "test"}},
   selfHost = {target = "app", bootstrap = "bootstrap/project.lua"},
}
]],
        ["out/app/main.lua"] = "return true\n",
        ["site/index.html"] = "<h1>API</h1>\n",
    })
    local dry = capture(("cd '%s' && '%s' clean --target docs --dry-run"):format(dir, NUPP))
    assertEq(dry, "would remove site\n", "dry run reports the selected output")
    assert(exists(dir .. "/site/index.html"), "dry run preserves the output")

    local one = capture(("cd '%s' && '%s' clean --target docs"):format(dir, NUPP))
    assertEq(one, "removed site\n", "target clean reports the removed output")
    assert(not exists(dir .. "/site/index.html"), "target clean removes its output")
    assert(exists(dir .. "/out/app/main.lua"), "target clean preserves other outputs")

    local all = capture(("cd '%s' && '%s' clean"):format(dir, NUPP))
    assert(all:find("removed out", 1, true), "clean reports all outputs: " .. all)
    assert(not exists(dir .. "/out/app/main.lua"), "clean removes module outputs")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.cleanRefusesPathsOutsideTheProject()
    local dir = tempProject({["nupp.lua"] = [[
return {build = {entries = {"main"}, outDir = "../outside"}}
]],})
    local out = capture(("cd '%s' && '%s' clean"):format(dir, NUPP))
    assert(out:find("refusing to clean unsafe build output path", 1, true), "clean rejects parent traversal: " .. out)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.cliListsAndDescribesBuildTasks()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {
      outDir = "out",
      default = "app",
      targets = {
         tools = {kind = "modules", entries = {"tools.main"}},
         app = {kind = "modules", description = "Build the application",
            entries = {"app.main"}, resources = {"src/app/*.d.nupp"}},
      },
   },
   test = {build = "app", argv = {"luajit", "tests/run.lua"},
      env = {MODE = "test"}},
   selfHost = {target = "app", bootstrap = "bootstrap/project.lua"},
}
]],
    })
    local listed = capture(("cd '%s' && '%s' tasks"):format(dir, NUPP))
    assert(
        listed:find("app (default) - Build the application", 1, true),
        "text listing marks the default and includes its description: " .. listed
    )
    assert(listed:find("tools", 1, true), "text listing includes every task: " .. listed)
    assert(listed:find("test - Build and run", 1, true), "text listing includes the configured test task: " .. listed)
    assert(listed:find("fixpoint - Verify", 1, true), "text listing includes the configured self-host task: " .. listed)
    assert(
        listed:find("app", 1, true) < listed:find("tools", 1, true),
        "text listing is sorted by task name: " .. listed
    )

    local detail = capture(("cd '%s' && '%s' tasks app --text"):format(dir, NUPP))
    assert(detail:find("Output directory: out", 1, true), "text detail includes inherited configuration: " .. detail)
    assert(detail:find("  - app.main", 1, true), "text detail includes entries: " .. detail)

    local encoded = capture(("cd '%s' && '%s' tasks app --json"):format(dir, NUPP))
    local decoded = require("testjson").decode(encoded)
    assertEq(decoded.name, "app", "JSON detail identifies the task")
    assertEq(decoded.outDir, "out", "JSON detail includes effective defaults")
    assertEq(decoded.entries[1], "app.main", "JSON detail includes entries")

    encoded = capture(("cd '%s' && '%s' tasks test --json"):format(dir, NUPP))
    decoded = require("testjson").decode(encoded)
    assertEq(decoded.kind, "test", "JSON identifies the configured action kind")
    assertEq(decoded.buildTarget, "app", "JSON includes the prerequisite target")
    assertEq(decoded.argv[2], "tests/run.lua", "JSON includes the configured argv")
    assertEq(decoded.env.MODE, "test", "JSON includes the configured environment")

    local fixpoint = capture(("cd '%s' && '%s' tasks fixpoint --text"):format(dir, NUPP))
    assert(
        fixpoint:find("Bootstrap: bootstrap/project.lua", 1, true),
        "text detail includes self-host configuration: " .. fixpoint
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.cliListsTheDefaultTestAction()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {entries = {"main"}},
}
]],
        ["src/main.nupp"] = "return true\n",
    })
    local encoded = capture(("cd '%s' && '%s' tasks test --json"):format(dir, NUPP))
    local decoded = require("testjson").decode(encoded)
    assertEq(decoded.kind, "test", "JSON identifies the default test action")
    assertEq(decoded.argv[1], "nupp", "the default test action uses Nupp")
    assertEq(decoded.argv[2], "test-runner", "the default test action uses the bundled runner")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.cliReportsManifestValidationErrorsWhenListingTasks()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   build = {
      default = "missing",
      targets = {app = {entries = {"app.main"}}},
   },
}
]],
    })
    local out = capture(("cd '%s' && '%s' tasks"):format(dir, NUPP))
    assert(
        out:find("build.default references unknown target missing", 1, true),
        "task discovery validates the manifest: " .. out
    )
    os.execute("rm -rf '" .. dir .. "'")
end

-- A build compiles the project's source set, not the closure of its entries.
--
-- The two things reachability got wrong, kept honest here: a module nothing
-- requires is still checked, and a module reached only through a computed
-- `require` is still in the build for it to find.

local SOURCE_SET_MANIFEST = [[
return {
   include = { "src" },
   build = {
      outDir = "build",
      default = "app",
      targets = { app = {} },
   },
}
]]

function M.modulesBuildNeedsNoEntry()
    local dir = tempProject({
        ["nupp.lua"] = SOURCE_SET_MANIFEST,
        ["src/app/first.nupp"] = "return 'first'\n",
        ["src/app/second.nupp"] = "return 'second'\n",
    })
    local out = capture(("cd '%s' && '%s' build"):format(dir, NUPP))
    assert(exists(dir .. "/build/app/first.lua"), "an entryless modules build compiles the first source: " .. out)
    assert(exists(dir .. "/build/app/second.lua"), "an entryless modules build compiles the second source: " .. out)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.compilesModulesNothingRequires()
    local dir = tempProject({
        ["nupp.lua"] = SOURCE_SET_MANIFEST,
        ["src/app/main.g.nupp"] = "print('main')\n",
        -- Required by nothing at all.
        ["src/app/orphan.g.nupp"] = "local orphan = {}\nreturn orphan\n",
    })
    local out = capture(("cd '%s' && '%s' build"):format(dir, NUPP))
    assert(exists(dir .. "/build/app/orphan.lua"), "a module nothing requires is still compiled: " .. out)
    os.execute("rm -rf '" .. dir .. "'")
end

-- The one that used to fail in front of a user rather than at build time.
function M.aComputedRequireFindsItsModule()
    local dir = tempProject({
        ["nupp.lua"] = SOURCE_SET_MANIFEST,
        ["src/app/main.g.nupp"] = 'local which = "app.plugin"\nprint(require(which).hi())\n',
        [
            "src/app/plugin.g.nupp"
        ] = "local plugin = {}\n\nfunction plugin.hi(): string\n" .. '    return "found"\nend\n\nreturn plugin\n',
    })
    assert(select(1, capture(("cd '%s' && '%s' build"):format(dir, NUPP))))
    assert(exists(dir .. "/build/app/plugin.lua"), "the module named only by a computed require is in the build")
    local ran = capture(("cd '%s' && '%s' run src/app/main.g.nupp"):format(dir, NUPP))
    assert(ran:find("found", 1, true), "and the program finds it at run time: " .. ran)
    os.execute("rm -rf '" .. dir .. "'")
end

-- Checking is the same source set, so an unrequired module cannot hide a type
-- error. This is the half that makes `nupp check` mean what it says.
function M.checksModulesNothingRequires()
    local dir = tempProject({
        ["nupp.lua"] = SOURCE_SET_MANIFEST,
        ["src/app/main.g.nupp"] = "print('main')\n",
        [
            "src/app/orphan.g.nupp"
        ] = "local orphan = {}\n\nfunction orphan.wrong(): string\n" .. "    return 42\nend\n\nreturn orphan\n",
    })
    local out = capture(("cd '%s' && '%s' check"):format(dir, NUPP))
    assert(out:find("NUPP2002", 1, true), "the orphan's type error is reported: " .. out)
    assert(out:find("orphan.g.nupp", 1, true), "and named: " .. out)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.targetSourcesSelectARecursiveModuleSet()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {targets = {app = {
      kind = "modules", entries = {"app.main"}, sources = {"src/app"},
   }}},
}
]],
        ["src/app/main.g.nupp"] = "return require('shared.answer')\n",
        ["src/app/plugin.g.nupp"] = "return {name = 'selected'}\n",
        -- A static dependency is part of the target even when its file sits outside the
        -- selected directory.
        ["src/shared/answer.g.nupp"] = "return 42\n",
        ["src/other/orphan.g.nupp"] = "local value: string = 42\nreturn value\n",
    })
    local out = capture(("cd '%s' && '%s' build --target app"):format(dir, NUPP))
    assertEq(out, "", "a scoped target ignores source outside its set: " .. out)
    assert(
        exists(dir .. "/build/app/plugin.lua"),
        "a recursively selected module is compiled even when nothing requires it"
    )
    assert(exists(dir .. "/build/shared/answer.lua"), "a static dependency outside the selected directory is compiled")
    assert(not exists(dir .. "/build/other/orphan.lua"), "unselected and unreachable source is absent")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.targetSourcesRejectEmptyAndEscapingSelections()
    local missing = tempProject({
        ["nupp.lua"] = [[return {include = {"src"}, build = {
   entries = {"main"}, sources = {"src/missing"},
}}]],
        ["src/main.nupp"] = "return 1\n",
    })
    local missingOut = capture(("cd '%s' && '%s' build"):format(missing, NUPP))
    assert(
        missingOut:find("build.sources matched nothing: src/missing", 1, true),
        "a misspelled source set fails: " .. missingOut
    )
    os.execute("rm -rf '" .. missing .. "'")

    local escaping = tempProject({
        ["nupp.lua"] = [[return {include = {"src"}, build = {
   entries = {"main"}, sources = {"../outside"},
}}]],
        ["src/main.nupp"] = "return 1\n",
    })
    local escapingOut = capture(("cd '%s' && '%s' build"):format(escaping, NUPP))
    assert(
        escapingOut:find("build.sources must stay inside the project", 1, true),
        "a source set cannot escape its project: " .. escapingOut
    )
    os.execute("rm -rf '" .. escaping .. "'")
end

function M.jsonBuildReportsColdAndWarmDeriveObservations()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"."}}\n',
        [
            "model.g.nupp"
        ] = [[
@derive(nupp.derive.Debug, nupp.derive.JSON)
local record Model
    value: integer = 0
end
return new Model()
]],
    })
    local first = require(
        "testjson"
    ).decode(captureJson(("cd '%s' && '%s' build model.g.nupp --json"):format(dir, NUPP)))
    assert(first.ok and #first.derives == 2, "cold build reports all derives")
    local byProvider = {}
    for _, observation in ipairs(first.derives) do
        byProvider[observation.provider] = observation
    end
    assert(byProvider["nupp.derive.Debug"] and byProvider["nupp.derive.JSON"], "build observations name every provider")
    local json = byProvider["nupp.derive.JSON"]
    assert(
        json.generatedMembers == 3 and json.canonicalBytes > 0 and json.renderedBytes > 0,
        "build observations expose bounded generation facts"
    )
    local coldBytes = read(dir .. "/model.lua")

    local second = require(
        "testjson"
    ).decode(captureJson(("cd '%s' && '%s' build model.g.nupp --json"):format(dir, NUPP)))
    assert(second.ok and #second.derives == 2, "cached build preserves derive observations")
    for index, observation in ipairs(first.derives) do
        assertEq(
            second.derives[index].semanticFingerprint,
            observation.semanticFingerprint,
            "cached/cold derive fingerprint"
        )
        assertEq(second.derives[index].canonicalBytes, observation.canonicalBytes, "cached/cold derive size")
    end
    assertEq(read(dir .. "/model.lua"), coldBytes, "cached and cold derived output bytes")
    os.execute("rm -rf '" .. dir .. "'")
end

return M
