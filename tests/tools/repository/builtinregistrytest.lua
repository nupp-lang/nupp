-- The builtin registry (`nupp.compiler.project.builtins`) against the lists a
-- builtin's modules and libraries have to be in, and against the rest of `src/`.
--
-- A builtin module missing from one of the three standard-library lists resolves
-- with every export typed as unknown, or is missing from a released compiler, and
-- nothing else catches it. A module outside a builtin that requires one of its
-- modules would make every user of that module carry the builtin, which is the
-- whole cost stripping exists to avoid: `serde` requiring `serde.yaml` would put
-- YAML in every program that decodes JSON. Both are read from source, so the
-- reading is tested on seeded fixtures too: a check that cannot fail proves
-- nothing.
local lexer = require("nupp.compiler.syntax.lexer")
local fs = require("nupp.compiler.fs")
local builtins = require("nupp.compiler.project.builtins")
local libraries = require("nupp.compiler.project.libraries")
local surface = require("nupp.compiler.standardsurface")

local ROOT = require("helpers.paths").root
local FIXTURES = require("helpers.paths").absoluteTests .. "/tools/repository/fixtures/builtinregistry"

local M = {}

local function read(path)
    local file = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = file:read("*a")
    file:close()

    return text
end

local function literal(token)
    if not token or token.kind ~= "string" then
        return nil
    end
    local chunk = loadstring("return " .. token.text)
    local ok, value = pcall(chunk)

    return ok and type(value) == "string" and value or nil
end

-- The lists a registered module has to be in, as sets of module names.
local function standardLists(root)
    local envText = read(root .. "/src/nupp/compiler/project/env.nupp")
    local pathMap = {}
    for name in envText:gmatch('%["([%w_%.]+)"%]%s*=%s*"/') do
        pathMap[name] = true
    end
    local manifest = assert(loadfile(root .. "/nupp.lua"))()
    local pack = {}
    for _, resource in ipairs(manifest.build.targets.dist.resources) do
        if type(resource) == "table" and type(resource.source) == "string" then
            local name = resource.source:match("^src/(.+)%.nupp$")
            if name then
                name = name:gsub("/init$", ""):gsub("/", ".")
                pack[name] = true
            end
        end
    end
    local classified = {}
    for name in pairs(surface.all()) do
        classified[name] = true
    end

    return {
        {label = "the env.nupp module path map", names = pathMap},
        {label = "the nupp.lua compiler pack", names = pack},
        {label = "standardsurface.nupp", names = classified},
    }
end

-- The concrete modules a pattern names: itself, or every module under it in
-- `src/`.
local function concrete(root, pattern)
    if pattern:sub(-2) ~= ".*" then
        return {pattern}
    end
    local prefix = pattern:sub(1, -3)
    local directory = root .. "/src/" .. prefix:gsub("%.", "/")
    local found = {}
    for _, path in ipairs(fs.listFiles(directory)) do
        local relative = path:match("^.*/src/(.+)%.nupp$")
        if relative and not relative:match("%.d$") then
            local name = relative:gsub("/init$", ""):gsub("/", ".")
            if name ~= prefix then
                found[#found + 1] = name
            end
        end
    end
    table.sort(found)

    return found
end

--- Every way `registry` disagrees with the standard lists and `STANDARD`.
local function listProblems(registry, root, standard)
    local lists = standardLists(root)
    local problems = {}
    local names = {}
    for name in pairs(registry) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local builtin = registry[name]
        for _, group in ipairs({builtin.modules or {}, builtin.owned or {}}) do
            for _, pattern in ipairs(group) do
                local modules = concrete(root, pattern)
                if #modules == 0 then
                    problems[#problems + 1] = ("%s: %s names no module under src/"):format(name, pattern)
                end
                for _, module in ipairs(modules) do
                    for _, list in ipairs(lists) do
                        if not list.names[module] then
                            problems[#problems + 1] = ("%s: %s is missing from %s"):format(name, module, list.label)
                        end
                    end
                end
            end
        end
        for _, library in ipairs(builtin.libraries or {}) do
            local bound = standard[library.name]
            if bound == nil then
                problems[#problems + 1] = ("%s: library %s is missing from libraries.STANDARD"):format(
                    name,
                    library.name
                )
            elseif bound.name ~= library.file then
                problems[#problems + 1] = ("%s: library %s is file %s in libraries.STANDARD, not %s"):format(
                    name,
                    library.name,
                    bound.name,
                    tostring(library.file)
                )
            end
        end
    end

    return problems
end

-- The module a source file is, from its declaration or its path under src/.
local function moduleOf(text, path)
    local declared = text:match("\nmodule ([%w_%.]+)") or text:match("^module ([%w_%.]+)")
    if declared then
        return declared
    end
    local relative = path:match("/src/(.+)%.nupp$") or path:match("/src/(.+)%.lua$")

    return relative and (relative:gsub("/init$", ""):gsub("/", ".")) or path
end

local function ownerOf(registry, module)
    for name, builtin in pairs(registry) do
        if builtins.owns(builtin, module) then
            return name
        end
    end

    return nil
end

local function libraryOwnerOf(registry, library)
    for name, builtin in pairs(registry) do
        for _, bound in ipairs(builtin.libraries or {}) do
            if bound.name == library then
                return name
            end
        end
    end

    return nil
end

--- Every place `text` reaches a builtin it is not part of, as `path:line` lines:
--- a require of one of its modules, static or literal dynamic, a qualified path
--- through one, an `@requires-dynamically` naming one, and a `cdef` binding one
--- of its libraries.
local function reaches(registry, text, path, display)
    local own = ownerOf(registry, moduleOf(text, path))
    local found = {}

    local function report(line, what, builtin)
        if builtin ~= nil and builtin ~= own then
            found[#found + 1] = ("%s:%d %s, which is builtin %s's"):format(display, line, what, builtin)
        end
    end

    local tokens = lexer.lex(text, path)
    for index, token in ipairs(tokens) do
        local previous, following = tokens[index - 1], tokens[index + 1]
        if token.kind == "name" and token.text == "require" and following then
            local argument = following.text == "(" and tokens[index + 2] or following
            local name = literal(argument)
            if name then
                report(token.line or 0, "requires " .. name, ownerOf(registry, name))
            end
        elseif token.kind == "name" and token.text == "from" then
            local name = literal(following)
            if name then
                report(token.line or 0, "binds " .. name, libraryOwnerOf(registry, name))
            end
        elseif token.kind == "name"
            and not (previous and (previous.text == "." or previous.text == ":" or previous.text == "local"))
            and following
            and following.text == "."
        then
            -- A dotted path, as long as it goes: the shortest prefix a builtin
            -- owns is the module it reaches.
            local parts, at = {token.text}, index
            while tokens[at + 1] and tokens[at + 1].text == "." and tokens[at + 2] and tokens[at + 2].kind == "name" do
                parts[#parts + 1] = tokens[at + 2].text
                at = at + 2
            end
            for count = 1, #parts do
                local name = table.concat(parts, ".", 1, count)
                local builtin = ownerOf(registry, name)
                if builtin then
                    report(token.line or 0, "reaches " .. name, builtin)
                    break
                end
            end
        end
    end
    local line = 0
    for text in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = line + 1
        local list = text:match("@requires%-dynamically ([%w%._, ]+)")
        for name in (list or ""):gmatch("[%w%._]+") do
            report(line, "requires " .. name .. " dynamically", ownerOf(registry, name))
        end
    end

    return found
end

local function sources(directory)
    local found = {}
    for _, path in ipairs(fs.listFiles(directory)) do
        if (path:match("%.nupp$") or path:match("%.lua$")) and not path:match("%.d%.nupp$") then
            found[#found + 1] = path
        end
    end
    table.sort(found)

    return found
end

local function scan(registry, directory)
    local found = {}
    for _, path in ipairs(sources(directory)) do
        local display = path:match("(src/.*)$") or path
        for _, line in ipairs(reaches(registry, read(path), path, display)) do
            found[#found + 1] = line
        end
    end

    return found
end

function M.everyBuiltinIsInTheStandardLists()
    local problems = listProblems(builtins.REGISTRY, ROOT, libraries.STANDARD)
    assert(#problems == 0, "the builtin registry disagrees with the standard lists:\n  " .. table.concat(problems, "\n  "))
end

function M.noModuleOutsideABuiltinReachesIt()
    local paths = sources(ROOT .. "/src")
    assert(#paths > 500, "the standard library's sources were not found under " .. ROOT)
    local found = scan(builtins.REGISTRY, ROOT .. "/src")
    assert(#found == 0, "modules outside a builtin reach it:\n  " .. table.concat(found, "\n  "))
end

function M.everyRegisteredLibraryIsOnOneLineForTheBridgeCheck()
    -- scripts/core-bridge reads the registry's `file = "..."` and `notices`
    -- names line by line to refuse staging one beside the bridge.
    local text = read(ROOT .. "/src/nupp/compiler/project/builtins.nupp")
    local body = assert(text:match("\nexport const REGISTRY(.*)$"), "the registry table is named REGISTRY")
    local files = 0
    for _ in body:gmatch('file = "[^"]+"') do
        files = files + 1
    end
    local expected = 0
    for _, builtin in pairs(builtins.REGISTRY) do
        expected = expected + #builtin.libraries
    end
    assert(files == expected, ("the bridge check reads %d library files, the registry has %d"):format(files, expected))
end

-- A registry that names a module and a library the lists do not have.
local SEEDED = {
    seeded = {
        modules = {"seededbuiltin", "seededbuiltin.*"},
        owned = {"nupp.runtime.provider.seeded"},
        libraries = {{name = "nuppseeded", file = "nupp_seeded", notices = {"seeded-LICENSE.txt"}}},
        hosts = {"native"},
    },
}

function M.theListCheckReportsWhatIsMissing()
    local problems = listProblems(SEEDED, FIXTURES, {nuppseeded = {name = "seeded"}})
    local text = table.concat(problems, "\n")
    assert(text:find("seededbuiltin is missing from the env.nupp module path map", 1, true), text)
    assert(text:find("seededbuiltin.reader is missing from standardsurface.nupp", 1, true), text)
    assert(text:find("nupp.runtime.provider.seeded is missing from the nupp.lua compiler pack", 1, true), text)
    assert(text:find("library nuppseeded is file seeded in libraries.STANDARD, not nupp_seeded", 1, true), text)
    local missing = listProblems(SEEDED, FIXTURES, {})
    assert(table.concat(missing, "\n"):find("library nuppseeded is missing from libraries.STANDARD", 1, true))
    -- What every list has is not reported.
    assert(not text:find("seededbuiltin.reader is missing from the env.nupp", 1, true), text)
end

function M.theScanReportsEachWayOfReachingABuiltin()
    local found = scan(SEEDED, FIXTURES .. "/src")
    local text = table.concat(found, "\n")
    local expected = {
        "src/facade/init.nupp:3 requires seededbuiltin, which is builtin seeded's",
        "src/facade/init.nupp:4 requires seededbuiltin.reader, which is builtin seeded's",
        "src/facade/init.nupp:7 reaches seededbuiltin, which is builtin seeded's",
        "src/facade/init.nupp:10 requires nupp.runtime.provider.seeded dynamically, which is builtin seeded's",
        "src/facade/init.nupp:13 binds nuppseeded, which is builtin seeded's",
    }
    for _, line in ipairs(expected) do
        assert(text:find(line, 1, true), "the scan missed " .. line .. ":\n" .. text)
    end
    -- The builtin's own modules may reach each other and bind its library.
    assert(not text:find("src/seededbuiltin/", 1, true), text)
    assert(#found == #expected, text)
end

return M
