--[[
Produces a browser-safe copy of bootstrap/nupp.lua: real LuaJIT parses the
file as-is (`bin/nupp` runs it every day), but fengari — a plain Lua 5.3 VM,
used because there is no such thing as "LuaJIT.wasm" (see
editors/playground/README.md) — rejects two things the file's own
implementation uses, not just code it generates for a checked program:

  - `const NAME = value`, LuaJIT's backported immutable-local declaration
  - `0x...ULL`-style 64-bit cdata integer literals, in the content-hash
    function nupp.compiler.build.hash uses for incremental build caching
  - Nupp's `? :` and `??` expressions, in nupp.data.Bitset
  - Nupp's `?.` safe navigation, when generated type tests inspect records

These are found with the bootstrap compiler's OWN lexer — loaded from the very
file being patched — rather than regexes, because a regex can't tell "real
`const` keyword" from "the five characters c-o-n-s-t inside a string that
happens to hold generated-code *text* for a program this compiler is
building" (nupp.compiler.gen's ffi/array-cache templates in nupp.compiler.gen do exactly that:
`code = 'const __nuppFfi = require("ffi"); ' .. code`, which must NOT be
touched — that `const` needs to reach the real LuaJIT that runs the program
being compiled). The lexer already resolves that correctly, since string
contents are never re-tokenized.

`const` and `local` are the same length, so that substitution can't shift
any later byte offset. The ULL suffix strip changes length, so edits are
applied in one pass, in ascending offset order, same as a diff hunk.

Usage: luajit patch-bootstrap-for-browser.lua <input.lua> <output.lua>
Run with this project's .rocks on LUA_PATH/LUA_CPATH (see bin/nupp).
]]

local inputPath = arg[1]
local outputPath = arg[2]
if not inputPath or not outputPath then
    io.stderr:write("usage: patch-bootstrap-for-browser.lua <input.lua> <output.lua>\n")
    os.exit(1)
end

-- Loading the bootstrap compiler to reach its lexer also runs it (it ends by
-- calling its own CLI's main()) — arg={} keeps that to a harmless no-op
-- "help" invocation, with output silenced so it doesn't land on our stdout.
arg = {}
local realExit, realPrint, realWrite = os.exit, print, io.write
os.exit = function(...) end
print = function(...) end
io.write = function(...) end
local ok, loadErr = pcall(dofile, inputPath)
os.exit, print, io.write = realExit, realPrint, realWrite
if not ok then
    io.stderr:write("loading " .. inputPath .. " under real LuaJIT failed: "
        .. tostring(loadErr) .. "\n")
    os.exit(1)
end

local lexer = require("nupp.compiler.lexer")

local f, openErr = io.open(inputPath, "rb")
if not f then
    io.stderr:write("cannot open " .. inputPath .. ": " .. tostring(openErr) .. "\n")
    os.exit(1)
end
local source = f:read("*a")
f:close()

local tokens, errors = lexer.lex(source, inputPath)
if errors and #errors > 0 then
    io.stderr:write(inputPath .. " has " .. #errors .. " lex error(s):\n")
    for _, e in ipairs(errors) do
        io.stderr:write("  " .. (e.line or "?") .. ": " .. (e.msg or "?") .. "\n")
    end
    os.exit(1)
end

-- `const` is a soft keyword (README: "LuaJIT's soft-keyword `const`
-- declaration"), parsed contextually rather than reserved outright — so a
-- table field or plain variable can be named `const` too, exactly as
-- happens a few lines into decodeType's CT_PTR case here:
--     return { kind = "pointer", to = ..., const = pointee and ... }
-- A real declaration is always `const NAME ...` or `const function NAME`;
-- that field is `const = value` with nothing between the keyword-shaped
-- token and `=`. Checking the next token is enough to tell them apart
-- without a real parser.
local function isConstDeclaration(tokens, i)
    local nextTok = tokens[i + 1]
    if not nextTok or nextTok.missing then return false end
    if nextTok.text == "function" then return true end
    return nextTok.kind == "name"
end

local edits, constCount, ullCount = {}, 0, 0
for i, tok in ipairs(tokens) do
    if tok.text == "const" and isConstDeclaration(tokens, i) then
        edits[#edits + 1] = {offset = tok.offset, length = 5, replacement = "local"}
        constCount = constCount + 1
    elseif tok.kind == "number" and (tok.text:match("^0[xX][0-9A-Fa-f]+U?LL$")
        or tok.text:match("^[0-9]+U?LL$")) then
        edits[#edits + 1] = {offset = tok.offset, length = #tok.text,
            replacement = (tok.text:gsub("U?LL$", ""))}
        ullCount = ullCount + 1
    end
end
local function applyEdits(text, changes)
    table.sort(changes, function(a, b) return a.offset < b.offset end)
    local parts, pos = {}, 1
    for _, e in ipairs(changes) do
        parts[#parts + 1] = text:sub(pos, e.offset - 1)
        parts[#parts + 1] = e.replacement
        pos = e.offset + e.length
    end
    parts[#parts + 1] = text:sub(pos)
    return table.concat(parts)
end

local patched = applyEdits(source, edits)

-- The bundled compiler is ordinary Nupp source emitted as LuaJIT source, so
-- its private bitset implementation can use Nupp conditional expressions too.
-- Fengari is plain Lua and must parse the whole bundle before it can reach the
-- compiler's lexer. The bundle has one statement per line, which makes these
-- expression-only lowerings deliberately small and lets the lexer keep strings
-- and comments out of the rewrite just as it does for const above.
local plainTokens, plainErrors = lexer.lex(patched, inputPath)
if plainErrors and #plainErrors > 0 then
    io.stderr:write("patched " .. inputPath .. " has " .. #plainErrors .. " lex error(s):\n")
    os.exit(1)
end

local function lineBounds(text, offset)
    local before = text:sub(1, offset - 1)
    local start = (before:match(".*()\n") or 0) + 1
    local ending = text:find("\n", offset, true) or (#text + 1)
    return start, ending
end

local function failUnsupported(token)
    io.stderr:write("cannot lower browser-incompatible " .. token.text
        .. " expression at byte " .. token.offset
        .. "; update patch-bootstrap-for-browser.lua\n")
    os.exit(1)
end

local syntaxEdits, ternaryCount, coalesceCount, safeNavigationCount = {}, 0, 0, 0
for i, token in ipairs(plainTokens) do
    if token.text == "?." then
        local closing = plainTokens[i - 1]
        local member = plainTokens[i + 1]
        local openingIndex
        if closing and closing.text == ")" then
            local depth = 0
            for j = i - 1, 1, -1 do
                local candidate = plainTokens[j]
                if candidate.text == ")" then
                    depth = depth + 1
                elseif candidate.text == "(" then
                    depth = depth - 1
                    if depth == 0 then
                        openingIndex = j
                        break
                    end
                end
            end
        end
        local callee = openingIndex and plainTokens[openingIndex - 1] or nil
        if not callee or callee.kind ~= "name" or not member or member.kind ~= "name" then
            failUnsupported(token)
        end
        local receiver = patched:sub(callee.offset, token.offset - 1)
        syntaxEdits[#syntaxEdits + 1] = {
            offset = callee.offset,
            length = member.offset + #member.text - callee.offset,
            replacement = "(function(__nuppBrowserValue) if __nuppBrowserValue ~= nil then return "
                .. "__nuppBrowserValue." .. member.text .. " end end)(" .. receiver .. ")",
        }
        safeNavigationCount = safeNavigationCount + 1
    end
end

for i, token in ipairs(plainTokens) do
    if token.text == "?" or token.text == "??" then
        local lineStart, lineEnd = lineBounds(patched, token.offset)
        local earlier, later
        for j = i - 1, 1, -1 do
            local candidate = plainTokens[j]
            if candidate.offset < lineStart then break end
            if candidate.text == "return" or candidate.text == "=" then
                earlier = candidate
                break
            end
        end
        for j = i + 1, #plainTokens do
            local candidate = plainTokens[j]
            if candidate.offset >= lineEnd then break end
            if token.text == "?" and candidate.text == ":" then
                later = candidate
                break
            elseif token.text == "??" and candidate.text == ")" then
                later = candidate
                break
            end
        end

        if token.text == "?" then
            if not earlier or not later then failUnsupported(token) end
            local expressionAt = earlier.offset + #earlier.text
            local condition = patched:sub(expressionAt + 1, token.offset - 1)
            local whenTrue = patched:sub(token.offset + 1, later.offset - 1)
            local whenFalse = patched:sub(later.offset + 1, lineEnd - 1)
            local prefix = patched:sub(lineStart, expressionAt)
            syntaxEdits[#syntaxEdits + 1] = {
                offset = lineStart,
                length = lineEnd - lineStart,
                replacement = prefix .. " (function() if (" .. condition
                    .. ") then return (" .. whenTrue .. ") else return ("
                    .. whenFalse .. ") end end)()",
            }
            ternaryCount = ternaryCount + 1
        else
            -- A nil-coalescing expression in this bundle is parenthesized as
            -- an argument. Keep a false left side intact and evaluate it once.
            local opening
            for j = i - 1, 1, -1 do
                local candidate = plainTokens[j]
                if candidate.offset < lineStart then break end
                if candidate.text == "(" then
                    opening = candidate
                    break
                end
            end
            if not opening or not later then failUnsupported(token) end
            local left = patched:sub(opening.offset + 1, token.offset - 1)
            local right = patched:sub(token.offset + 2, later.offset - 1)
            syntaxEdits[#syntaxEdits + 1] = {
                offset = opening.offset + 1,
                length = later.offset - opening.offset - 1,
                replacement = "(function(__nuppBrowserValue) if __nuppBrowserValue ~= nil then return "
                    .. "__nuppBrowserValue else return " .. right .. " end end)(" .. left .. ")",
            }
            coalesceCount = coalesceCount + 1
        end
    end
end

local lambdaCount = 0
for i, token in ipairs(plainTokens) do
    if token.text == "|" then
        local closing, arrow, opening, openingIndex, bodyEnd
        for j = i + 1, #plainTokens do
            local candidate = plainTokens[j]
            if candidate.text == "|" then
                closing = candidate
                arrow = plainTokens[j + 1]
                opening = plainTokens[j + 2]
                openingIndex = j + 2
                break
            end
        end
        if closing and arrow and arrow.text == "->" and opening and opening.text == "(" then
            local depth = 0
            for j = openingIndex + 1, #plainTokens do
                local candidate = plainTokens[j]
                if candidate.text == "(" then
                    depth = depth + 1
                elseif candidate.text == ")" then
                    if depth == 0 then
                        bodyEnd = candidate
                        break
                    end
                    depth = depth - 1
                end
            end
            if not bodyEnd then failUnsupported(token) end
            local parameters = patched:sub(token.offset + 1, closing.offset - 1)
            local body = patched:sub(opening.offset, bodyEnd.offset + #bodyEnd.text - 1)
            syntaxEdits[#syntaxEdits + 1] = {
                offset = token.offset,
                length = bodyEnd.offset + #bodyEnd.text - token.offset,
                replacement = "function(" .. parameters .. ") return " .. body .. " end",
            }
            lambdaCount = lambdaCount + 1
        end
    end
end
patched = applyEdits(patched, syntaxEdits)

-- The file ends by running the full CLI
-- (os.exit(require("nupp.compiler.cli").main(arg))), which eagerly requires every
-- subcommand — including ones (like nupp.compiler.cli.lsp) that need `jsonNative`, a C
-- extension unavailable in the browser. The playground drives the checker
-- and compiler directly (see src/worker.js), so this call is dropped
-- entirely rather than satisfying the whole CLI's dependency graph.
local trailer = 'os . exit ( require ( "nupp.compiler.cli" ) . main ( arg ) )'
local trailerAt = patched:find(trailer, 1, true)
if not trailerAt then
    io.stderr:write("expected trailing CLI invocation not found; "
        .. "bootstrap/nupp.lua's shape has changed — update this trailer "
        .. "and the const/ULL assumptions above it\n")
    os.exit(1)
end
patched = patched:sub(1, trailerAt - 1) .. patched:sub(trailerAt + #trailer)

local out, writeErr = io.open(outputPath, "wb")
if not out then
    io.stderr:write("cannot write " .. outputPath .. ": " .. tostring(writeErr) .. "\n")
    os.exit(1)
end
out:write(patched)
out:close()

io.stderr:write(string.format(
    "patched %s -> %s (%d const, %d ULL-literal, %d ternary, %d coalescing, "
        .. "%d safe-navigation, %d lambda edits)\n",
    inputPath, outputPath, constCount, ullCount, ternaryCount, coalesceCount,
    safeNavigationCount, lambdaCount))
