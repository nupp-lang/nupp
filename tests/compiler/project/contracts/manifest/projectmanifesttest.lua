local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local process = fixture.process
local write = fixture.write
local read = fixture.read
local tempProject = fixture.tempProject
local remove = fixture.remove

local M = {}

function M.manifestValidationRejectsInvalidReferencesAndCycles()
    local missing = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   dependencies = {native = {kind = "c", sources = {"native.c"}}},
   build = {entries = {"main"}, dependencies = {"missing"}},
}
]],
    })
    local config, err = project.loadManifest(missing)
    testAssert.eq(config, nil, "unknown target dependency rejects the manifest")
    assert(err:find("references unknown dependency missing", 1, true), err)
    remove(missing)

    local cyclic = tempProject({
        [
            "nupp.lua"
        ] = [[
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
    testAssert.eq(config, nil, "dependency cycles reject the manifest")
    assert(err:find("dependency cycle involving", 1, true), err)
    remove(cyclic)
end

function M.manifestAcceptsSeveralPkgConfigPackages()
    local valid = tempProject({
        [
            "nupp.lua"
        ] = [[
return {dependencies = {native = {kind = "c",
   pkgConfig = {"simdjson", "luajit"}}}, build = {entries = {"main"}}}
]]
    })
    local config, err = project.loadManifest(valid)
    assert(config, err)
    testAssert.eq(table.concat(config.dependencies.native.pkgConfig, ","), "simdjson,luajit")
    remove(valid)

    local invalid = tempProject({
        [
            "nupp.lua"
        ] = [[
return {dependencies = {native = {kind = "c", pkgConfig = {"simdjson", ""}}},
   build = {entries = {"main"}}}
]]
    })
    config, err = project.loadManifest(invalid)
    testAssert.eq(config, nil, "an empty package name rejects the manifest")
    assert(err:find("pkgConfig%[2%] must be a non%-empty string"), err)
    remove(invalid)
end

function M.manifestValidatesCDependencyLinkage()
    for _, linkage in ipairs({"shared", "static", "both"}) do
        local valid = tempProject({
            [
                "nupp.lua"
            ] = (
                [[
return {dependencies = {native = {kind = "c", linkage = %q}},
   build = {entries = {"main"}}}
]]
            ):format(linkage)
        })
        local config, err = project.loadManifest(valid)
        assert(config, err)
        testAssert.eq(config.dependencies.native.linkage, linkage)
        remove(valid)
    end

    local invalid = tempProject({
        [
            "nupp.lua"
        ] = [[
return {dependencies = {native = {kind = "c", linkage = "dynamic"}},
   build = {entries = {"main"}}}
]]
    })
    local config, err = project.loadManifest(invalid)
    testAssert.eq(config, nil, "an unknown C linkage rejects the manifest")
    assert(err:find('linkage must be "shared", "static", or "both"', 1, true), err)
    remove(invalid)

    local strayOutput = tempProject({
        [
            "nupp.lua"
        ] = [[
return {dependencies = {native = {kind = "c", staticOutput = "native.a"}},
   build = {entries = {"main"}}}
]]
    })
    config, err = project.loadManifest(strayOutput)
    testAssert.eq(config, nil, "a static output without static linkage rejects the manifest")
    assert(err:find('staticOutput requires linkage = "static" or "both"', 1, true), err)
    remove(strayOutput)
end

function M.manifestValidatesStandaloneTargetsAndPrebuiltArtifacts()
    local host = require("nupp.compiler.targetlayout").hostKey()
    local valid = tempProject({
        [
            "nupp.lua"
        ] = (
            [=[
return {
   dependencies = {native = {kind = "c", linkage = "static", artifacts = {
      [%q] = {static = {path = "native.a", sha256 = %q, size = 8}},
   }}},
   build = {kind = "binary", stub = "nupp", standalone = true,
      entries = {"main"}, dependencies = {"native"}},
}
]=]
        ):format(host, ("0"):rep(64))
    })
    local config, err = project.loadManifest(valid)
    assert(config, err)
    testAssert.eq(config.build.standalone, true)
    remove(valid)

    local invalid = tempProject({
        ["nupp.lua"] = [[
return {build = {kind = "bundle", standalone = true, entries = {"main"}}}
]]
    })
    config, err = project.loadManifest(invalid)
    testAssert.eq(config, nil, "standalone is restricted to compiler-owned binaries")
    assert(err:find("standalone is only valid for a binary target", 1, true), err)
    remove(invalid)
end

function M.manifestValidatesTypeDependenciesSeparatelyFromTargets()
    local valid = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   dependencies = {
      host = {
         kind = "types",
         format = "luacats",
         source = {
            git = "https://example.invalid/host.git",
            rev = "0123456789012345678901234567890123456789",
         },
         path = "library",
      },
   },
   build = {entries = {"main"}},
}
]],
        ["main.nupp"] = "local value = 1\n"
    })
    assert(project.loadManifest(valid), "a pinned LuaCATS dependency is valid")
    remove(valid)

    local invalid = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   dependencies = {
      host = {kind = "types", format = "teal", source = {git = "https://example.invalid/host.git", rev = "short"}},
   },
}
]]
    })
    local _, err = project.loadManifest(invalid)
    assert(err and err:find("format", 1, true), "the importer format is validated")
    remove(invalid)
end

function M.manifestValidatesTheCompileTimeLayoutTarget()
    local valid = tempProject({
        ["nupp.lua"] = [[
return {build = {entries = {"main"},
   layoutTarget = "aarch64-apple-darwin"}}
]]
    })
    local config, err = project.loadManifest(valid)
    assert(config, "a supported layout target is accepted: " .. tostring(err))
    testAssert.eq(config.build.layoutTarget, "aarch64-apple-darwin")
    local described = assert(project.describeTasks(valid, "default"))
    testAssert.eq(described.layoutTarget, "aarch64-apple-darwin", "task discovery reports the effective layout target")
    remove(valid)

    local invalid = tempProject({
        ["nupp.lua"] = [[
return {build = {entries = {"main"}, layoutTarget = "mystery-cpu"}}
]]
    })
    config, err = project.loadManifest(invalid)
    testAssert.eq(config, nil, "an unknown layout target rejects the manifest")
    assert(err:find("layoutTarget names unsupported target mystery-cpu", 1, true), err)
    assert(err:find("x86_64%-unknown%-linux%-gnu"), err)
    remove(invalid)
end

function M.manifestValidatesCrossTargetBinaryPlatforms()
    local validDir = tempProject({
        [
            "nupp.lua"
        ] = [[return {build = {kind = "binary", stub = "nupp",
         entries = {"main"}, platforms = {"x86_64-unknown-linux-gnu",
         "aarch64-apple-darwin", "x86_64-pc-windows-msvc"}}}]],
    })
    local config, err = project.loadManifest(validDir)
    assert(config, err)
    testAssert.eq(#config.build.platforms, 3, "all catalog platforms are retained")
    remove(validDir)

    local cases = {
        {platforms = "{}", message = "must not be empty"},
        {
            platforms = '{"x86_64-unknown-linux-gnu", "x86_64-unknown-linux-gnu"}',
            message = "duplicates x86_64-unknown-linux-gnu",
        },
        {platforms = '{"aarch64-unknown-linux-gnu"}', message = "unsupported binary platform"},
    }
    for _, case in ipairs(cases) do
        local dir = tempProject({
            [
                "nupp.lua"
            ] = (
                'return {build = {kind = "binary", stub = "nupp", entries = {"main"}, platforms = %s}}'
            ):format(case.platforms),
        })
        local rejected, why = project.loadManifest(dir)
        testAssert.eq(rejected, nil, "invalid cross-target manifest is rejected")
        assert(why:find(case.message, 1, true), why)
        remove(dir)
    end
end

function M.browserHostsCannotSelectNativeDistributionPlatforms()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {kind = "binary", stub = "nupp",
            host = "browser", entries = {"main"}, outDir = "out",
            platforms = {"aarch64-apple-darwin"}}}]],
        ["src/main.nupp"] = "return 42\n",
    })
    local rejected, why = project.loadManifest(dir)
    testAssert.eq(rejected, nil, "a browser host cannot use native distribution stubs")
    assert(why:find('platforms selects native binary hosts', 1, true), why)
    write(dir .. "/nupp.lua", read(dir .. "/nupp.lua"):gsub('host = "browser"', 'host = "native"'))
    local accepted, problem = project.loadManifest(dir)
    assert(accepted, problem)
    testAssert.eq(
        project.check(dir, {
            host = "browser"
        }),
        1,
        "a check rejects the resolved host before applying a native layout"
    )

    local root = assert(require("io.internal.path").cwd()):tostring()
    local status, output = process.capture({root .. "/bin/nupp", "build", "--host", "browser"}, {cwd = dir})
    testAssert.eq(status, 1, "the command-line host override is also rejected\n" .. output)
    assert(output:find('platforms selects native binary hosts', 1, true), output)
    assert(require("io.internal.files").stat(dir .. "/out") ~= "directory", "rejection writes no build output")
    remove(dir)
end

function M.browserBundlesKeepWasmAndGuestNativeAotPolicies()
    for _, policy in ipairs({"require-wasm", "require"}) do
        local dir = tempProject({
            [
                "nupp.lua"
            ] = (
                [[return {include = {"src"}, build = {kind = "bundle",
                host = "browser", entries = {"main"}, outDir = "out",
                output = "out/app.lua", aot = %q}}]]
            ):format(policy),
            ["src/main.nupp"] = "return 42\n",
        })
        local config, problem = project.loadManifest(dir)
        assert(config, problem)
        testAssert.eq(project.check(dir), 0, "a browser bundle still accepts " .. policy)
        remove(dir)
    end
end

function M.manifestRestrictsPortablePayloadOutputsToBinaryTargets()
    local validDir = tempProject({
        [
            "nupp.lua"
        ] = [[return {build = {kind = "binary", stub = "host",
         entries = {"main"}, output = "app", payloadOutput = "app.lua"}}]],
    })
    local config, err = project.loadManifest(validDir)
    assert(config, err)
    testAssert.eq(config.build.payloadOutput, "app.lua")
    remove(validDir)

    local invalidDir = tempProject({
        ["nupp.lua"] = [[return {build = {kind = "bundle", entries = {"main"},
         payloadOutput = "app.lua"}}]],
    })
    local rejected, why = project.loadManifest(invalidDir)
    testAssert.eq(rejected, nil, "a bundle cannot claim a separately stamped payload")
    assert(why:find("payloadOutput is only valid for a binary target", 1, true), why)
    remove(invalidDir)
end

function M.taskDescriptionsUseEffectiveTargetConfiguration()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
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
    testAssert.eq(task.name, "default", "named default task is queried literally")
    testAssert.eq(task.default, false, "query reports the configured default accurately")
    testAssert.eq(task.outDir, "out", "task inherits the output directory")
    testAssert.eq(task.entries[1], "shared.main", "task inherits shared entries")
    remove(dir)
end

-- The generator reads a dozen keys the build's own validation knows nothing
-- about, so a misspelling used to configure nothing and say nothing about it.
function M.aMisspelledDocsKeyIsRejectedWithTheNameItMeant()
    local function reject(target, wanted)
        local dir = tempProject({
            ["nupp.lua"] = "return {include = {\"src\"}, build = {targets = {site = " .. target .. "}}}\n"
        })
        local config, err = project.loadManifest(dir)
        testAssert.eq(config, nil, "a key that configures nothing is refused")
        assert(err:find(wanted, 1, true), wanted .. " not in: " .. tostring(err))
        remove(dir)
    end

    reject('{kind = "docs", sources = {"src"}, titel = "x"}', 'has no key "titel"; did you mean "title"?')
    reject(
        '{kind = "docs", sources = {"src"}, pages = {{titel = "x"}}}',
        'pages[1] has no key "titel"; did you mean "title"?'
    )
    reject(
        '{kind = "docs", sources = {"src"}, pages = {{glob = "docs/**.md", ' .. 'exlude = {"docs/style.md"}}}}',
        'pages[1] has no key "exlude"; did you mean "exclude"?'
    )
    -- A page names what it publishes one way or the other, and one that names
    -- neither a route nor a pattern is a page nothing can place.
    reject('{kind = "docs", sources = {"src"}, pages = {{source = "docs/x.md"}}}', 'pages[1].path must be a string')
    reject('{kind = "docs", sources = {"src"}, pages = {{glob = 1}}}', 'pages[1].glob must be an array')
    -- Nothing near enough to guess at is still named, without one.
    reject('{kind = "docs", sources = {"src"}, wibble = 1}', 'has no key "wibble"')
end

-- Retired keys are not refused by name: each fails as any key nothing reads does.
function M.retiredManifestKeysFailAsUnknownKeys()
    local function reject(manifestSource, wanted)
        local dir = tempProject({["nupp.lua"] = manifestSource})
        local config, err = project.loadManifest(dir)
        testAssert.eq(config, nil, manifestSource)
        assert(err and err:find(wanted, 1, true), wanted .. " not in: " .. tostring(err))
        remove(dir)
    end

    reject('return {include = {"src"}, strict = true}\n', 'nupp.lua has no key "strict"')
    reject(
        'return {include = {"src"}, build = {targets = {app = {kind = "modules", aotCflags = {"-O2"}}}}}\n',
        'has no key "aotCflags"'
    )
    -- One spelling for a tier range: the string form read as an exact tier and meant
    -- a maximum.
    reject(
        'return {include = {"src"}, build = {targets = {app = {kind = "modules", aot = "require", '
        .. 'aotFeatures = "avx2"}}}}\n',
        "aotFeatures must be a table"
    )
    reject(
        'return {include = {"src"}, build = {targets = {app = {kind = "modules", dialect = "luajit"}}}}\n',
        'has no key "dialect"'
    )
    reject(
        'return {include = {"src"}, build = {targets = {site = {kind = "docs", sources = {"src"}, dialect = "luajit"}}}}\n',
        'has no key "dialect"'
    )
    -- A produced path is `output` everywhere a manifest names one.
    reject(
        'return {include = {"src"}, dependencies = {native = {kind = "c", out = "lib/native.so"}}}\n',
        'has no key "out"'
    )
    reject(
        'return {include = {"src"}, dependencies = {native = {kind = "c", bindings = '
        .. '{header = "native.h", out = "src/native.nupp"}}}}\n',
        'has no key "out"'
    )
    reject(
        'return {include = {"src"}, dependencies = {native = {kind = "rust"}}}\n',
        'kind must be "c", "cargo", "luarocks", or "types"'
    )
    reject(
        'return {include = {"src"}, build = {targets = {site = {kind = "docs", sources = {"src"}, all = true}}}}\n',
        'has no key "all"'
    )
end

function M.deliverableTargetsStillRequireAnEntry()
    local cases = {
        bundle = '{kind = "bundle"}',
        binary = '{kind = "binary", stub = "nupp"}',
        component = '{kind = "component", exports = {"app.run"}}',
    }
    for kind, target in pairs(cases) do
        local dir = tempProject({["nupp.lua"] = 'return {include = {"src"}, build = ' .. target .. '}\n',})
        local config, err = project.loadManifest(dir)
        testAssert.eq(config, nil, kind .. " without an entry is refused")
        assert(err and err:find("build.entries is required", 1, true), tostring(err))
        remove(dir)
    end
end

-- `fmt` gets the same treatment as any other manifest table: a typo names
-- itself rather than configuring nothing.
function M.fmtManifestKeyIsValidated()
    local function loadFmt(fmt)
        local dir = tempProject({["nupp.lua"] = 'return {include = {"src"}, fmt = ' .. fmt .. '}\n'})
        local config, err = project.loadManifest(dir)
        remove(dir)
        return config, err
    end

    local config = loadFmt('{methodParens = false}')
    assert(config, "a valid fmt table is accepted")
    testAssert.eq(config.fmt.methodParens, false, "and its value survives")

    local _, err = loadFmt('"off"')
    assert(err and err:find("fmt must be a table", 1, true), err)

    local _, typeErr = loadFmt('{methodParens = "no"}')
    assert(typeErr and typeErr:find("fmt.methodParens must be a boolean", 1, true), typeErr)

    local _, nameErr = loadFmt('{methodParen = false}')
    assert(nameErr and nameErr:find('fmt has no key "methodParen"; did you mean "methodParens"?', 1, true), nameErr)
end

-- A docs target is still a build target, so what any target takes belongs on
-- one too. This project's declares the rocks `nupp doc` renders with.
function M.aDocsTargetKeepsTheKeysEveryTargetTakes()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {lunamark = {kind = "luarocks", rock = "lunamark",
      version = "0.6.0-1"}},
   build = {targets = {site = {
      kind = "docs", sources = {"src"}, dependencies = {"lunamark"},
      format = "both", name = "N", github = "https://example.com",
      logo = "l.svg", public = "p", customCss = "c.css", lexers = "lx",
      includePrivate = true,
      pages = {{path = "", title = "H", layout = "home", source = "i.md",
         redirects = {"old"}}, {glob = {"docs/**.md"}, base = "docs",
         exclude = {"docs/style.md"}}},
   }}},
}
]]
    })
    local config, err = project.loadManifest(dir)
    assert(config, "every documented key is accepted: " .. tostring(err))
    remove(dir)
end

function M.nativeFeatureOverridesAreValidatedAndReported()
    local function load(features)
        local dir = tempProject({
            [
                "nupp.lua"
            ] = [[
return {include = {"src"}, build = {targets = {app = {
   entries = {"main"}, nativeFeatures = ]]
            .. features
            .. [[
}}}}
]]
        })
        local config, err = project.loadManifest(dir)
        local task = config and project.describeTasks(dir, "app") or nil
        remove(dir)

        return config, err, task
    end

    local config, err, task = load("{lpeg = true, path = true, uuid = false}")
    assert(config, "boolean native feature overrides are accepted: " .. tostring(err))
    testAssert.eq(task.nativeFeatures.lpeg, true, "task reports forced inclusion")
    testAssert.eq(task.nativeFeatures.path, true, "new native providers can be forced in")
    testAssert.eq(task.nativeFeatures.uuid, false, "new native providers can be forced out")

    local _, unknown = load("{jsoon = true}")
    assert(unknown and unknown:find("nativeFeatures names no feature jsoon", 1, true), tostring(unknown))
    local _, wrongType = load("{lpeg = 'yes'}")
    assert(wrongType and wrongType:find("nativeFeatures.lpeg must be true or false", 1, true), tostring(wrongType))
end

function M.manifestValidatesReloadComponents()
    local valid = tempProject({
        [
            "nupp.lua"
        ] = [[
return {build = {kind = "component", entries = {"main"}, exports = {"main.run"}, reload = true}}
]]
    })
    local config, err = project.loadManifest(valid)
    assert(config, err)
    testAssert.eq(config.build.reload, true)
    remove(valid)

    local wrongKind = tempProject({
        ["nupp.lua"] = [[
return {build = {kind = "bundle", entries = {"main"}, reload = true}}
]]
    })
    config, err = project.loadManifest(wrongKind)
    testAssert.eq(config, nil, "only a component carries the slots a session patches")
    assert(err:find("reload is only valid for a component target", 1, true), err)
    remove(wrongKind)

    local optimized = tempProject({
        ["nupp.lua"] = [[
return {build = {kind = "component", entries = {"main"}, reload = true, optimize = 2}}
]]
    })
    config, err = project.loadManifest(optimized)
    testAssert.eq(config, nil, "watch generation is development generation")
    assert(err:find("reload builds at optimize = 0", 1, true), err)
    remove(optimized)

    local compiled = tempProject({
        ["nupp.lua"] = [[
return {build = {kind = "component", entries = {"main"}, reload = true, aot = "require"}}
]]
    })
    config, err = project.loadManifest(compiled)
    testAssert.eq(config, nil, "a patched Lua body is not a rebuilt kernel")
    assert(err:find("reload cannot be combined with aot", 1, true), err)
    remove(compiled)
end

return M
