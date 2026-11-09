-- The compiler may not depend on the tools built on it.
--
-- `nupp.tools` holds the command line, the build system, the language server, the
-- formatter and the rest of what `nupp` does beyond compiling. Each of them uses the
-- compiler; none of them is something the compiler can use back, because the
-- compiler is also what the portable bootstrap carries, and that does not carry the
-- tools. The move that separated the two found the edges that had
-- crept in through a computed name -- `require("nupp.compiler.build." .. name)` --
-- which no reading of the literal requires shows, so this reads the computed ones too.
--
-- It is a reading of the source rather than of a run. A dependency that only a rarely
-- taken branch reaches is a dependency all the same, and a run would not find it.
local lexer = require("nupp.compiler.syntax.lexer")
local fs = require("nupp.compiler.fs")

local HERE = require("helpers.paths").tests
local ROOT = HERE:match("^(.*)/[^/]+$") or "."

local M = {}

-- Requires whose name no literal can state, because it is the project's rather than
-- the compiler's: a module a generator was declared with, and one a stored prelude
-- image recorded. Each names code the compiler was handed, never code it is built on.
local REFLECTIVE = {
    ["src/nupp/compiler/comptime/generatorworker.nupp"] = "a generator's provider entry, named by the project",
    ["src/nupp/compiler/project/preludecache.nupp"] = "a module a stored prelude image recorded",
    ["src/nupp/compiler/runtime/reflect.nupp"] = "an application declaration named by its runtime type graph",
}

local function names(value)
    return value == "nupp.tools" or value:sub(1, 11) == "nupp.tools."
end

-- Whether a computed name starting with `prefix` could be a tools module.
local function couldName(prefix)
    return names(prefix) or ("nupp.tools."):sub(1, #prefix) == prefix
end

local function literal(token)
    if not token or token.kind ~= "string" then
        return nil
    end
    local chunk = loadstring("return " .. token.text)
    local ok, value = pcall(chunk)

    return ok and type(value) == "string" and value or nil
end

--- Every way `text` reaches past the compiler, as readable lines.
local function reaches(text, path, forbidden, computedName)
    forbidden, computedName = forbidden or names, computedName or couldName
    local found = {}
    local tokens = lexer.lex(text, path)
    for index, token in ipairs(tokens) do
        local value = literal(token)
        if value and forbidden(value) then
            found[#found + 1] = ("%s:%d names %s"):format(path, token.line or 0, value)
        end
        local previous, following = tokens[index - 1], tokens[index + 1]
        if token.kind == "name"
            and token.text == "require"
            and not (previous and (previous.text == "." or previous.text == ":" or previous.text == "function"))
            and following
            and (following.text == "(" or following.text == ",")
        then
            local argument = tokens[index + 2]
            local closing = tokens[index + 3]
            local direct = literal(argument)
            local computed = not (direct and closing and (closing.text == ")" or closing.text == ","))
            if computed then
                -- The name is built. Its leading literal, if it has one, says how far
                -- it can reach: `"nupp.compiler." .. name` stays inside, `"nupp." ..
                -- name` and a bare variable do not.
                local prefix = direct
                if prefix == nil then
                    if not REFLECTIVE[path] then
                        found[
                            #found + 1
                        ] = ("%s:%d requires a name with no literal prefix"):format(path, token.line or 0)
                    end
                elseif computedName(prefix) then
                    found[#found + 1] = ("%s:%d requires %q .. something"):format(path, token.line or 0, prefix)
                end
            end
        end
    end

    return found
end

local function compilerSources()
    local sources = {}
    for _, path in ipairs(fs.listFiles(ROOT .. "/src/nupp/compiler")) do
        if path:match("%.nupp$") and not path:match("%.d%.nupp$") then
            sources[#sources + 1] = path
        end
    end
    table.sort(sources)

    return sources
end

function M.noCompilerModuleReachesTheTools()
    local sources = compilerSources()
    assert(#sources > 100, "the compiler's sources were not found under " .. ROOT)
    local found = {}
    for _, path in ipairs(sources) do
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        local relative = path:match("(src/nupp/compiler/.*)$")
        for _, line in ipairs(reaches(text, relative)) do
            found[#found + 1] = line
        end
    end
    assert(#found == 0, "the compiler reaches into nupp.tools:\n  " .. table.concat(found, "\n  "))
end

-- The reading above has to be able to say no, or its passing says nothing.
function M.theReadingFindsEachShapeOfEdge()
    local function count(text)
        return #reaches(text, "src/nupp/compiler/example.nupp")
    end

    assert(count('local cli = require("nupp.tools.cli")') > 0, "a literal require")
    assert(count('local ok = pcall(require, "nupp.tools.fmt")') > 0, "a protected require")
    assert(count('const {type Config} = require("nupp.tools.build.manifest")') > 0, "a type-only import")
    assert(count('return require("nupp.tools." .. name)') > 0, "a computed name inside the tools")
    assert(count('return require("nupp." .. name)') > 0, "a computed name that could reach them")
    assert(count("return require(name)") > 0, "a name with no literal at all")
    assert(count('local stamp = {"nupp.tools.fmt"}') > 0, "a module named as data")
    assert(count('return require("nupp.compiler." .. name)') == 0, "a computed name inside the compiler")
    assert(count('local check = require("nupp.compiler.check")') == 0, "an edge inside the compiler")
    assert(count('local worker = "/build/nupp/tools/main.lua"') == 0, "a path is not a module")
end

-- Core sources may use the checked graph frontend, but never the frozen tools.
local FROZEN_PREFIXES = {"nupp.compiler.vm.legacy", "nupp.compiler.clif.legacy", "nupp.compiler.vm.convert"}

local function frozenName(value)
    for _, prefix in ipairs(FROZEN_PREFIXES) do
        if value:sub(1, #prefix) == prefix then
            return true
        end
    end

    return false
end

local function couldNameFrozen(prefix)
    if frozenName(prefix) then
        return true
    end
    for _, family in ipairs(FROZEN_PREFIXES) do
        if family:sub(1, #prefix) == prefix then
            return true
        end
    end

    return false
end

local function coreReaches(text, path)
    local found = reaches(text, path, frozenName, couldNameFrozen)
    local tokens = lexer.lex(text, path)
    local aliases, declarations = {}, {}
    for index, token in ipairs(tokens) do
        if literal(token) == "nupp.compiler.vm.lower" then
            local binding, keyword = tokens[index - 4], tokens[index - 5]
            local call, open, equal = tokens[index - 2], tokens[index - 1], tokens[index - 3]
            local close, nextToken = tokens[index + 1], tokens[index + 2]
            if binding
                and binding.kind == "name"
                and keyword
                and (keyword.text == "local" or keyword.text == "const")
                and equal
                and equal.text == "="
                and call
                and call.text == "require"
                and open
                and open.text == "("
                and close
                and close.text == ")"
                and not (nextToken and (nextToken.text == "." or nextToken.text == "["))
            then
                aliases[binding.text], declarations[index - 4] = true, true
            else
                found[
                    #found + 1
                ] = ("%s:%d must bind vm.lower explicitly to use only functionGraph"):format(path, token.line or 0)
            end
        end
    end
    for index, token in ipairs(tokens) do
        local previous, following, member = tokens[index - 1], tokens[index + 1], tokens[index + 2]
        if token.kind == "name"
            and aliases[token.text]
            and not declarations[index]
            and not (previous and (previous.text == "." or previous.text == ":"))
            and not (following and following.text == "." and member and member.text == "functionGraph")
        then
            found[#found + 1] = ("%s:%d may only access vm.lower.functionGraph"):format(path, token.line or 0)
        end
    end

    return found
end

function M.noCoreModuleReachesFrozenLowering()
    local sources, found = 0, {}
    for _, path in ipairs(fs.listFiles(ROOT .. "/native/core")) do
        -- The guest programs the core runs (`tests/catalog-*`) are programs,
        -- not the core: one may require a computed name on purpose.
        local guest = path:match("native/core/tests/catalog%-[^/]*$") ~= nil
        if not guest and (path:match("%.nupp$") or path:match("%.lua$")) then
            sources = sources + 1
            local file = assert(io.open(path, "rb"))
            local text = file:read("*a")
            file:close()
            for _, line in ipairs(coreReaches(text, path)) do
                found[#found + 1] = line
            end
        end
    end
    assert(sources > 20, "the core's sources were not found under " .. ROOT)
    assert(#found == 0, "the core reaches the frozen toolchain:\n  " .. table.concat(found, "\n  "))
end

function M.theCoreBoundaryReadingRejectsFrozenImportsAndEmitAliases()
    local function count(text)
        return #coreReaches(text, "native/core/example.nupp")
    end

    for _, name in ipairs({
        "legacylower",
        "legacyemit",
        "legacyimage",
        "legacygraph",
        "legacynativegraph",
        "convert"
    }) do
        assert(count('local tool = require("nupp.compiler.vm.' .. name .. '")') > 0, name)
    end
    assert(count('return require("nupp.compiler.clif.legacygraph")') > 0, "frozen CLIF adapter")
    assert(count('return pcall(require, "nupp.compiler.vm.legacylower")') > 0, "protected import")
    assert(count('return require("nupp.compiler.vm." .. name)') > 0, "computed compiler module")
    assert(count('return require(name)') > 0, "unproven dynamic import")
    assert(count('const {type Tool} = require("nupp.compiler.vm.legacylower")') > 0, "type-only import")
    local import = 'local compiler = require("nupp.compiler.vm.lower"); '
    assert(count(import .. 'return compiler.emit(...)') > 0, "legacy emission")
    assert(count(import .. 'local emit = compiler.emit; return emit(...)') > 0, "aliased emission")
    assert(count(import .. 'local other = compiler; return other.emit(...)') > 0, "aliased lowerer")
    assert(count(import .. 'return compiler[method](...)') > 0, "computed lowerer member")
    assert(count('local emit = require("nupp.compiler.vm.lower").emit') > 0, "direct member import")
    assert(count(import .. 'return compiler.functionGraph(...)') == 0, "shared frontend")
    assert(count('const graph = require("nupp.compiler.vm.graph")') == 0, "shared graph")
    assert(count('local arm = require("nupp.compiler.s0.arm64")') == 0, "owned backend")
    assert(count('-- require("nupp.compiler.vm.legacylower")') == 0, "comments are not imports")
end

return M
