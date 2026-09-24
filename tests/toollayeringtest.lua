-- The compiler may not depend on the tools built on it.
--
-- `nupp.tools` holds the command line, the build system, the language server, the
-- formatter and the rest of what `nupp` does beyond compiling. Each of them uses the
-- compiler; none of them is something the compiler can use back, because the
-- compiler is also what the browser playground and the portable bootstrap carry, and
-- neither carries the tools. The move that separated the two found the edges that had
-- crept in through a computed name -- `require("nupp.compiler.build." .. name)` --
-- which no reading of the literal requires shows, so this reads the computed ones too.
--
-- It is a reading of the source rather than of a run. A dependency that only a rarely
-- taken branch reaches is a dependency all the same, and a run would not find it.
local lexer = require("nupp.compiler.lexer")
local fs = require("nupp.compiler.fs")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE:match("^(.*)/[^/]+$") or "."

local M = {}

-- Requires whose name no literal can state, because it is the project's rather than
-- the compiler's: a module a generator was declared with, and one a stored prelude
-- image recorded. Each names code the compiler was handed, never code it is built on.
local REFLECTIVE = {
    ["src/nupp/compiler/generatorworker.nupp"] = "a generator's provider entry, named by the project",
    ["src/nupp/compiler/preludecache.nupp"] = "a module a stored prelude image recorded",
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
local function reaches(text, path)
    local found = {}
    local tokens = lexer.lex(text, path)
    for index, token in ipairs(tokens) do
        local value = literal(token)
        if value and names(value) then
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
                        found[#found + 1] = ("%s:%d requires a name with no literal prefix"):format(
                            path,
                            token.line or 0
                        )
                    end
                elseif couldName(prefix) then
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

return M
