require("nupp.runtime.backend.lunajson"):install()
local json = require("jsonNative")
local parser = require("nupp.compiler.parser")

-- The native compiler parses its private `%?` logging-format extension with
-- LPeg. Fengari cannot load native LPeg, but the syntax this one module needs is
-- deliberately only Lua's flags, width, precision and conversion byte. Supply
-- the same analysis directly so environment startup does not need a C module.
-- This is installed before `check` loads callexpr and asks for the module.
package.loaded["nupp.compiler.luaformat"] = nil
package.preload["nupp.compiler.luaformat"] = function()
    local luaFormat = {}
    local FLAGS = "-+ #0"
    local DIGITS = "0123456789"
    local CONVERSIONS = "aAcdiouxXeEfgGpqs?"

    local function contains(haystack, byte)
        return byte ~= "" and haystack:find(byte, 1, true) ~= nil
    end

    function luaFormat.analyze(format)
        local debugArguments = {}
        local rewritten = {}
        local copiedFrom = 1
        local index = 1
        while index <= #format do
            if format:sub(index, index) ~= "%" then
                index = index + 1
            elseif format:sub(index + 1, index + 1) == "%" then
                index = index + 2
            else
                local directive = index
                index = index + 1
                while contains(FLAGS, format:sub(index, index)) do
                    index = index + 1
                end

                local width = index
                while contains(DIGITS, format:sub(index, index)) do
                    index = index + 1
                end
                if index - width > 2 then
                    return nil, 'invalid string.format directive starting at "'
                        .. format:sub(directive, width + 2) .. '"'
                end

                if format:sub(index, index) == "." then
                    local precision = index
                    index = index + 1
                    while contains(DIGITS, format:sub(index, index)) do
                        index = index + 1
                    end
                    if index - precision > 3 then
                        return nil, 'invalid string.format directive starting at "'
                            .. format:sub(directive, precision + 3) .. '"'
                    end
                end

                local conversion = format:sub(index, index)
                if not contains(CONVERSIONS, conversion) then
                    local ending = format:find("%", index + 1, true)
                    ending = ending and ending - 1 or #format
                    return nil, 'invalid string.format directive starting at "'
                        .. format:sub(directive, ending) .. '"'
                end
                local debug = conversion == "?"
                debugArguments[#debugArguments + 1] = debug
                if debug then
                    rewritten[#rewritten + 1] = format:sub(copiedFrom, index - 1)
                    rewritten[#rewritten + 1] = "s"
                    copiedFrom = index + 1
                end
                index = index + 1
            end
        end
        rewritten[#rewritten + 1] = format:sub(copiedFrom)
        return {format = table.concat(rewritten), debugArguments = debugArguments}
    end

    return luaFormat
end

-- Documentation parsing is the other compiler-internal LPeg user loaded by a
-- check. Its grammar is a fixed set of line recognizers, so mirror those
-- recognizers without exposing a pretend general-purpose LPeg implementation.
package.loaded["nupp.compiler.doc.syntax"] = nil
package.preload["nupp.compiler.doc.syntax"] = function()
    local syntax = {}
    local function matcher(match)
        return {match = function(_, subject) return match(subject) end}
    end
    local function boundary(subject, after)
        local byte = subject:sub(after, after)
        return byte == "" or not byte:match("[A-Za-z0-9_-]")
    end

    syntax.fence = matcher(function(line)
        local prefix, marker, rest = line:match("^(%s*)(```+)(.*)$")
        if marker then return prefix, marker, rest end
        return line:match("^(%s*)(~~~+)(.*)$")
    end)
    syntax.markdownFence = matcher(function(line)
        local prefix = line:match("^( ? ? ?)") or ""
        local rest = line:sub(#prefix + 1)
        local marker, trailing = rest:match("^(```+)(.*)$")
        if not marker then marker, trailing = rest:match("^(~~~+)(.*)$") end
        if marker then return prefix, marker, trailing end
    end)
    syntax.tag = matcher(function(line)
        return line:match("^@([A-Za-z0-9_-]+)%s*(.*)$")
    end)
    syntax.heading = matcher(function(line)
        return line:match("^(#+)%s+(.+)$")
    end)
    syntax.directive = matcher(function(line)
        return line:match("^%s*:::%s+([A-Za-z0-9_-]+)%s*(.*)$")
    end)
    syntax.comment = matcher(function(line)
        return line:match("^%-%-%-* ?(.*)$")
    end)
    syntax.docComment = matcher(function(line)
        return line:match("^%-%-%- ?(.*)$")
    end)
    syntax.nameValue = matcher(function(line)
        return line:match("^(%S+)%s*(.*)$")
    end)
    syntax.blank = matcher(function(line)
        if line:match("^%s*$") then return #line + 1 end
    end)
    syntax.indented = matcher(function(line)
        if line:match("^%s") then return 2 end
    end)
    syntax.codeIndented = matcher(function(line)
        if line:match("^    %S") then return 6 end
    end)
    syntax.fenceInfo = matcher(function(line)
        return line:match("^%s*([A-Za-z0-9_+%-]*)%s*(.*)$")
    end)
    syntax.caption = matcher(function(line)
        return line:match("%[([^%]]+)%]")
    end)
    syntax.lineNumber = matcher(function(line)
        local from = 1
        while true do
            local first, last = line:find(":line-numbers", from, true)
            if not first then return nil end
            local digits = line:sub(last + 1):match("^=(%d+)")
            local after = digits and last + #digits + 2 or last + 1
            if boundary(line, after) then return digits or "1" end
            from = first + 1
        end
    end)
    syntax.playground = matcher(function(line)
        local from = 1
        while true do
            local first, last = line:find(":playground", from, true)
            if not first then return nil end
            if boundary(line, last + 1) then return last + 1 end
            from = first + 1
        end
    end)
    syntax.lines = matcher(function(text)
        local lines, from = {}, 1
        while true do
            local newline = text:find("\n", from, true)
            if not newline then
                lines[#lines + 1] = text:sub(from)
                return lines
            end
            lines[#lines + 1] = text:sub(from, newline - 1)
            from = newline + 1
        end
    end)

    function syntax.closes(opened, marker, rest)
        return marker ~= nil and marker:sub(1, 1) == opened:sub(1, 1)
            and #marker >= #opened and syntax.blank:match(rest or "") ~= nil
    end
    function syntax.fenceState(line, opened, markdown)
        local _, marker, rest = (markdown and syntax.markdownFence or syntax.fence):match(line)
        if marker and not opened then
            opened = marker
        elseif marker and syntax.closes(opened, marker, rest) then
            opened = nil
        end
        return opened, marker, rest
    end

    return syntax
end

-- C-header checking imports the native build syntax helpers even when a source
-- declares no C header. None of those parsers can be reached in the browser's
-- empty filesystem, so keep module initialization independent of LPeg and fail
-- specifically if that native-only path ever becomes reachable.
package.loaded["nupp.compiler.build.syntax"] = nil
package.preload["nupp.compiler.build.syntax"] = function()
    local function unavailable()
        error("native build syntax is not available in the browser playground", 0)
    end
    local matcher = setmetatable({match = unavailable}, {__call = unavailable})
    return {glob = unavailable, shellWords = matcher, depfile = matcher}
end

local check = require("nupp.compiler.check")
local tree = require("nupp.compiler.lsp.tree")
local T = require("nupp.compiler.types")

-- The browser has no filesystem, so its cache cannot persist. Disabling it
-- also keeps environment startup from reaching the compiler fingerprint's
-- process-backed directory walk. Supplying the host target and the empty type
-- roots also avoids discovering either through build files that do not exist
-- in the browser.
local env = require("nupp.compiler.env").new(".", {
    cache = false,
    config = {_target = {layoutTarget = "x86_64-unknown-linux-gnu"}},
    typeRoots = {},
})

-- Set at the end of a successful __playground_check, read by
-- __playground_hover. Hover reuses the last check rather than
-- reparsing/rechecking the whole buffer on every mouse movement -- the
-- same tradeoff a real editor makes reusing its last diagnostics pass
-- for hover, and one debounced check (see app.js) behind besides.
local lastResult = nil

-- Marked as an array so that a clean program's empty list crosses as [] and
-- not as {}: an unmarked empty Lua table is indistinguishable from an empty
-- object, and the JS side filters and maps whatever it is handed.
local function diagList(diags)
    local out = json.asArray({})
    for i, d in ipairs(diags) do
        out[i] = {
            code = d.code, msg = d.msg, severity = d.severity,
            line = d.line, col = d.col, offset = d.offset, length = d.length,
            help = d.help, notes = d.notes, related = d.related,
        }
    end
    return out
end

-- Every entry point below returns one JSON string: {diagnostics=...}
-- for a check, {code=..., reason=..., diagnostics=...} for a compile.
-- Crossing the JS boundary as one encoded string, rather than a raw Lua
-- table walked field-by-field from JS, is what host-runtime.lua's JSON
-- shim exists for.

-- The third argument is what the Options panel set, as name=0/1 pairs:
-- "strict=1,optimize=0". Not JSON, though everything else here crosses as
-- JSON, because host-runtime.lua's JSON shim implements encode and not
-- decode -- nothing in the playground had needed to read JSON back until
-- now, and two booleans do not justify a parser. One argument still, so a
-- third setting is a field on each side and nothing in between.
local function settingsOf(options)
    local out = {}
    for name, value in tostring(options or ""):gmatch("([%w_]+)=([01])") do
        out[name] = value == "1"
    end
    return out
end

__playground_check = function(source, filename, options)
    local settings = settingsOf(options)
    local result = parser.parse(source, filename)
    local diags
    if #result.errors > 0 then
        diags = result.errors
    else
        local ok, checked = pcall(check.check, result, filename, env,
            {strict = settings.strict == true})
        if not ok then error(checked, 0) end
        diags = checked
        lastResult = result
    end
    return json.encode({diagnostics = diagList(diags)})
end

-- What textDocument/hover in nupp.compiler.lsp answers with, minus the parts
-- (nupp.compiler.lsp.navigate's documentationFor, doc comments) that need a live
-- LSP session rather than just a checked parse result. offset is a
-- 1-based byte offset, same as every other position in this codebase.
__playground_hover = function(offset)
    if not lastResult then return json.encode({found = false}) end
    local tok = tree.tokenAt(lastResult, offset)
    if not tok then return json.encode({found = false}) end
    local def = tok.definition
    -- At a declaration's own name token, inferredType is left as plain
    -- "any" (inference marks usages, not the binding's own name) even
    -- though def.type already holds the real declared signature -- the
    -- gap this fixes. At a usage token inferredType is the better
    -- answer, since it can be narrower than the declared type (an "if"
    -- that proved a union down to one branch), so it stays first there.
    local t = tok.inferredType
    if (t == nil or t == T.any) and def and def.type then t = def.type end
    if not t then return json.encode({found = false}) end
    local name = def and def.name or tok.text
    local prefix = def and def.cdef and "cdef "
        or def and def.constant and "const " or ""
    return json.encode({
        found = true,
        name = name,
        signature = prefix .. name .. ": " .. T.tostring(t),
        offset = tok.offset,
        length = #tok.text,
    })
end

-- Mirrors nupp.compiler.cli.compile's compile.module, taking source text directly
-- instead of reading a path off disk.
__playground_compile = function(source, filename, options)
    local settings = settingsOf(options)
    local result = parser.parse(source, filename)
    if #result.errors > 0 then
        return json.encode({reason = "syntax errors",
            diagnostics = diagList(result.errors)})
    end
    local ok, diags = pcall(check.check, result, filename, env,
        {strict = settings.strict == true})
    if not ok then error(diags, 0) end
    for _, d in ipairs(diags) do
        if d.severity == "error" then
            return json.encode({reason = "type errors", diagnostics = diagList(diags)})
        end
    end
    -- Every pass nupp.compiler.optimize registers runs at level 1, so the Options
    -- panel's one switch is the whole of the distinction there is: -O2 is
    -- accepted by the CLI and reserved for a stronger tier, but selects the
    -- same passes today and would compile byte-identically.
    local optimize = require("nupp.compiler.optimize")
    local okOpt, optErr = pcall(optimize.run, result,
        {level = settings.optimize == true and 1 or 0, filename = filename,
         disabled = {}, relaxed = {}})
    if not okOpt then error(optErr, 0) end
    -- Match build/modules: feature selection follows the tree codegen will
    -- actually emit, so a folded branch cannot keep its runtime installer.
    result.effects = optimize.liveEffects(result)
    local gen = require("nupp.compiler.gen")
    local okGen, code, genDiags = pcall(gen.generate, result, filename)
    if not okGen then error(code, 0) end
    if genDiags and #genDiags > 0 then
        return json.encode({reason = "code generation errors",
            diagnostics = diagList(genDiags)})
    end
    return json.encode({code = code, diagnostics = diagList(diags)})
end
