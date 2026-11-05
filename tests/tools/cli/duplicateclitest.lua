local json = require("testjson")
local fs = require("nupp.compiler.fs")
local text = require("nupp.tools.lsp.text")
local NUPP = require("helpers.paths").absoluteTests .. "/../bin/nupp"
local M = {}

local BODY = "local total = value + 1\nlocal twice = total * 2\nreturn twice\n"

local function source(name)
    return "local function " .. name .. "(value)\n" .. BODY .. "end\n"
end

local function project()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src' '" .. dir .. "/build'") == 0)

    local function write(path, body)
        local file = assert(io.open(dir .. "/" .. path, "wb"))
        file:write(body)
        file:close()
    end

    write("nupp.lua", 'return {include = {"src"}, outDir = "build"}\n')
    write("src/first.nupp", source("first"))
    write("src/second.nupp", source("second"))
    write("build/third.nupp", source("third"))
    write("outside.nupp", source("outside"))

    return fs.canonical(dir)
end

local function capture(dir, command)
    local pipe = assert(io.popen("cd '" .. dir .. "' && '" .. NUPP .. "' " .. command))
    local output = pipe:read("*a")
    pipe:close()
    return output
end

function M.projectAuditUsesIncludeRootsAndProducesNavigableJSON()
    local dir = project()
    local report = json.decode(capture(dir, "duplicates --json --min-tokens=10 --min-lines=2"))
    assert(report.ok and report.complete and not report.truncated)
    assert(report.filesScanned == 2 and #report.groups == 1)
    local occurrence = report.groups[1].occurrences[1]
    assert(occurrence.file == dir .. "/src/first.nupp")
    local original = assert(fs.readFile(occurrence.file))
    assert(original:sub(occurrence.range.start.offset, occurrence.range["end"].offset - 1) == report.groups[1].snippet)
end

function M.explicitFilesRestrictTheComparisonCorpus()
    local dir = project()
    local report = json.decode(
        capture(dir, "duplicates --json --min-tokens=10 --min-lines=2 src/first.nupp outside.nupp")
    )
    assert(report.filesScanned == 2 and #report.groups == 1)
    assert(report.groups[1].occurrences[1].file == dir .. "/outside.nupp")
end

function M.schemaAndEmptyResultsAreMachineReadable()
    local dir = project()
    local schema = json.decode(capture(dir, "duplicates --schema"))
    assert(schema.properties.groups.items.properties.occurrences.items.properties.range)
    local output = capture(dir, "duplicates --json --min-tokens=1000")
    local report = json.decode(output)
    assert(report.ok and #report.groups == 0)
    assert(output:match('"groups"%s*:%s*%[%s*%]'))
    assert(output:match('"diagnostics"%s*:%s*%[%s*%]'))
end

function M.invalidOptionsAndIncompleteAuditsFail()
    local dir = project()

    local function status(args)
        return capture(dir, args .. " >/dev/null 2>/dev/null; printf '%s' $?")
    end

    assert(status("duplicates --min-tokens=0") == "2")
    local invalid = json.decode(capture(dir, "duplicates --json --min-tokens=0"))
    assert(not invalid.ok and not invalid.complete and invalid.diagnostics[1].severity == "error")
    assert(status("duplicates --budget=1") == "1")
    assert(status("duplicates missing.nupp") == "1")
    assert(status("duplicates --min-tokens=10 --min-lines=2") == "0")
end

local function session(dir, host)
    local messages = {}
    local server = require("nupp.tools.lsp").newSession(
        dir,
        function(message)
            messages[#messages + 1] = message
        end,
        host
    )

    local function dispatch(id, method, params)
        if host then
            host.currentId = id
        end
        server.dispatch({jsonrpc = "2.0", id = id, method = method, params = params})
        if host then
            host.currentId = nil
        end
        if id then
            for i = #messages, 1, -1 do
                if messages[i].id == id then
                    return messages[i]
                end
            end
            error("missing response")
        end
    end

    local initialized = dispatch(1, "initialize", {rootUri = text.pathToUri(dir), capabilities = {}})
    assert(initialized.result.capabilities.experimental.nuppDuplicates)

    return dispatch
end

function M.lspUsesUnsavedBuffersAndAddsUTF16Locations()
    local dir = project()
    local dispatch = session(dir)
    local uri = text.pathToUri(dir .. "/src/second.nupp")
    -- The non-ASCII comment tests that locations come from the current buffer.
    local changed = '-- heading\n' .. source("second"):gsub("local total", "--[[😀]] local total", 1)
    dispatch(nil, "textDocument/didOpen", {
        textDocument = {uri = uri, languageId = "nupp", version = 1, text = changed}
    })
    local reply = dispatch(2, "nupp/duplicates", {options = {minTokens = 10, minLines = 2}})
    assert(reply.result, reply.error and reply.error.message)
    assert(reply.result.filesScanned == 2 and #reply.result.groups == 1)
    local occurrence = reply.result.groups[1].occurrences[2]
    assert(occurrence.location.uri == uri)
    assert(occurrence.range.start.line == 3)
    assert(occurrence.location.range.start.line == 2)
    assert(occurrence.range.start.column == 12)
    assert(occurrence.location.range.start.character == 9)
    dispatch(nil, "textDocument/didChange", {
        textDocument = {uri = uri, version = 2},
        contentChanges = {{text = "local unrelated = 1\n"}}
    })
    assert(#dispatch(3, "nupp/duplicates", {options = {minTokens = 10, minLines = 2}}).result.groups == 0)
    assert(dispatch(4, "nupp/duplicates", {options = {minTokens = 0}}).error.code == -32602)
end

function M.lspCanCancelTheWorkspaceAudit()
    local dir = project()
    local host = {cancellation = {}, currentId = nil}
    local cancelled = false
    host.pump = function()
        if host.currentId == 2 then
            cancelled = true
        end
    end
    host.cancelled = function()
        return cancelled
    end
    host.isCancelled = function()
        return false
    end
    host.clearCancelled = function()
        cancelled = false
    end
    host.documentVersion = function()
        return nil
    end
    host.cancel = function()
        cancelled = true
    end
    local dispatch = session(dir, host)
    assert(dispatch(2, "nupp/duplicates", {}).error.code == -32800)
end

return M
