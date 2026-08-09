--[[
Produces a browser-safe copy of bootstrap/nupp.lua: real LuaJIT parses the
file as-is (`bin/nupp` runs it every day), but fengari — a plain Lua 5.3 VM,
used because there is no such thing as "LuaJIT.wasm" (see
editors/playground/README.md) — rejects two things the file's own
implementation uses, not just code it generates for a checked program:

  - `const NAME = value`, LuaJIT's backported immutable-local declaration
  - `0x...ULL`-style 64-bit cdata integer literals, in the content-hash
    function compiler.build.hash uses for incremental build caching

Both are found with the bootstrap compiler's OWN lexer — loaded from the very
file being patched — rather than regexes, because a regex can't tell "real
`const` keyword" from "the five characters c-o-n-s-t inside a string that
happens to hold generated-code *text* for a program this compiler is
building" (compiler.gen's ffi/array-cache templates in compiler.gen do exactly that:
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

local lexer = require("compiler.lexer")

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
table.sort(edits, function(a, b) return a.offset < b.offset end)

local parts, pos = {}, 1
for _, e in ipairs(edits) do
    parts[#parts + 1] = source:sub(pos, e.offset - 1)
    parts[#parts + 1] = e.replacement
    pos = e.offset + e.length
end
parts[#parts + 1] = source:sub(pos)
local patched = table.concat(parts)

-- The file ends by running the full CLI
-- (os.exit(require("compiler.cli").main(arg))), which eagerly requires every
-- subcommand — including ones (like compiler.cli.lsp) that need `cjson`, a C
-- extension unavailable in the browser. The playground drives the checker
-- and compiler directly (see src/worker.js), so this call is dropped
-- entirely rather than satisfying the whole CLI's dependency graph.
local trailer = 'os . exit ( require ( "compiler.cli" ) . main ( arg ) )'
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
    "patched %s -> %s (%d const, %d ULL-literal edits)\n",
    inputPath, outputPath, constCount, ullCount))
