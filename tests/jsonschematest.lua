-- What `--schema` promises against what `--json` actually writes.
--
-- A schema is a second description of something the code already describes, which
-- is the arrangement that always drifts. So every command that declares one is
-- run for real and its output validated against it. A field that goes away, or
-- changes type, or stops being written, fails here.
local json = require("testjson")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local NUPP = HERE .. "/../bin/nupp"

local M = {}

--- A JSON Schema validator covering exactly the keywords the schemas use:
--- type, properties, required, items, enum, oneOf, anyOf, and $ref into #/definitions.
--- Returns nil and the path of the first thing wrong.
local function validate(value, schema, root, path)
    root, path = root or schema, path or "$"
    local ref = schema["$ref"]
    if ref then
        local name = ref:match("^#/definitions/(.+)$")
        assert(name, "unsupported $ref " .. ref)
        local target = (root.definitions or {})[name]
        assert(target, "no definition named " .. name)
        return validate(value, target, root, path)
    end
    if schema.oneOf then
        local matched, reasons = 0, {}
        for _, branch in ipairs(schema.oneOf) do
            local ok, err = validate(value, branch, root, path)
            if ok then
                matched = matched + 1
            else
                reasons[#reasons + 1] = err
            end
        end
        if matched ~= 1 then
            return nil, ("%s: matches %d of the oneOf branches (%s)"):format(path, matched, table.concat(reasons, "; "))
        end
    end
    if schema.anyOf then
        local reasons = {}
        local matched = false
        for _, branch in ipairs(schema.anyOf) do
            local ok, err = validate(value, branch, root, path)
            if ok then
                matched = true
            else
                reasons[#reasons + 1] = err
            end
        end
        if not matched then
            return nil, ("%s: matches none of the anyOf branches (%s)"):format(path, table.concat(reasons, "; "))
        end
    end
    local wanted = schema.type
    if wanted then
        local actual
        if type(value) == "table" then
            actual = json.isArray(value) and "array" or "object"
        elseif type(value) == "number" then
            actual = (value % 1 == 0) and "integer" or "number"
        else
            actual = type(value)
        end
        local fits = actual == wanted
            or (wanted == "number" and actual == "integer")
            or (wanted == "object" and actual == "array" and next(value) == nil)
        if not fits then
            return nil, ("%s: expected %s, got %s"):format(path, wanted, actual)
        end
    end
    if schema.enum then
        local found = false
        for _, allowed in ipairs(schema.enum) do
            if value == allowed then
                found = true
            end
        end
        if not found then
            return nil, ("%s: %s is not one of the listed values"):format(path, tostring(value))
        end
    end
    if wanted == "object" and schema.properties and type(value) == "table" then
        for _, name in ipairs(schema.required or {}) do
            if value[name] == nil then
                return nil, ("%s: missing required property %q"):format(path, name)
            end
        end
        for name, child in pairs(value) do
            local property = schema.properties[name]
            if property then
                local ok, err = validate(child, property, root, path .. "." .. name)
                if not ok then
                    return nil, err
                end
            end
        end
    end
    if wanted == "array" and schema.items and type(value) == "table" then
        for index, item in ipairs(value) do
            local ok, err = validate(item, schema.items, root, ("%s[%d]"):format(path, index))
            if not ok then
                return nil, err
            end
        end
    end

    return true
end

local function capture(dir, argv)
    local prefix = dir and ("cd '" .. dir .. "' && ") or ""
    local pipe = assert(io.popen(prefix .. ("'%s' %s 2>/dev/null"):format(NUPP, argv)))
    local out = pipe:read("*a")
    pipe:close()

    return out
end

--- Runs a command twice: once for its schema, once for real output, and checks
--- the second against the first.
-- `alreadyJson` is for a command whose only report is JSON, so there is no
-- `--json` to ask for and passing one would be a usage error.
local function agrees(dir, argv, alreadyJson)
    local schemaText = capture(dir, argv .. " --schema")
    local ok, schema = pcall(json.decode, schemaText)
    assert(ok and type(schema) == "table", argv .. " --schema did not produce a schema: " .. schemaText)
    local outputText = capture(dir, alreadyJson and argv or argv .. " --json")
    local decoded
    ok, decoded = pcall(json.decode, outputText)
    assert(ok, argv .. " --json did not produce JSON: " .. outputText)
    local valid, err = validate(decoded, schema)
    assert(valid, argv .. " --json does not match its own --schema: " .. tostring(err) .. "\noutput: " .. outputText)

    return decoded
end

local function tempProject(files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    for name, text in pairs(files) do
        local file = assert(io.open(dir .. "/" .. name, "wb"))
        file:write(text)
        file:close()
    end

    return dir
end

local BAD = 'local x: number = "text"\nreturn x\n'
local UGLY = "local  y   =  1\nreturn y\n"
local GOOD = "local z: integer = 1\nreturn z\n"

function M.checkOutputMatchesItsSchema()
    local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n', ["bad.nupp"] = BAD})
    local decoded = agrees(dir, "check bad.nupp")
    assert(#decoded.diagnostics == 1, "the diagnostic is reported")
    assert(decoded.diagnostics[1].docs, "and carries the reference anchor explain uses")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.buildOutputMatchesItsSchemaWhenItFailsAndWhenItDoesNot()
    local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n', ["bad.nupp"] = BAD, ["good.nupp"] = GOOD})
    local failed = agrees(dir, "build bad.nupp")
    assert(failed.ok == false, "a build that reported an error is not ok")
    assert(#failed.written == 0, "and wrote nothing")

    local built = agrees(dir, "build good.nupp")
    assert(built.ok == true, "a build that worked says so")
    assert(
        #built.written == 2,
        "and names the entry and ownership runtime it wrote: " .. table.concat(built.written, ", ")
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.fmtOutputMatchesItsSchemaAndSeparatesFailureFromUnformatted()
    local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n', ["ugly.nupp"] = UGLY})
    local decoded = agrees(dir, "fmt ugly.nupp")
    assert(#decoded.unformatted == 1, "the unformatted file is listed")
    assert(#decoded.failed == 0, "and is not confused with a failure")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.lintsOutputMatchesItsSchema()
    local decoded = agrees(nil, "lints")
    assert(#decoded.lints > 0, "the lints are listed")
    for _, lint in ipairs(decoded.lints) do
        assert(lint.code and lint.name and lint.default, "each carries its code, name and default level")
    end
end

function M.taskListOutputMatchesItsSchema()
    local decoded = agrees(HERE .. "/..", "task --list")
    assert(#decoded.tasks > 0, "the tasks are listed")
end

function M.astOutputMatchesItsSchema()
    local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n', ["good.nupp"] = GOOD})
    agrees(dir, "ast good.nupp", true)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aotOutputMatchesItsSchema()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"."}}\n',
        [
            "rules.nupp"
        ] = [[
@aot
local function identity(value: number): number
    return value
end

@aot
local function simplified(value: number): number
    return (value + -0.0) * 1.0
end

return {identity = identity, simplified = simplified}
]],
    })
    local decoded = agrees(dir, "aot rules.nupp")
    assert(#decoded.functions == 2, "one record per @aot function")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.cleanOutputMatchesItsSchema()
    local dir = tempProject({["nupp.lua"] = 'return {include = {"."}, build = {outDir = "out"}}\n'})
    local decoded = agrees(dir, "clean --dry-run")
    assert(decoded.dryRun == true, "a dry run says so")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.docOutputMatchesItsSchema()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"."}}\n',
        ["good.nupp"] = "--- A point in the plane.\nglobal record Point\n" .. "    x: number\nend\n"
    })
    local decoded = agrees(dir, "doc --kind markdown -o out/api.md")
    assert(decoded.kind == "markdown", "what was produced is reported")
    assert(#decoded.files > 0, "and every path it wrote")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.initListsAndScaffoldsAgainstOneSchema()
    local dir = tempProject({})
    local listed = agrees(dir, "init --list")
    local names = {}
    for _, entry in ipairs(listed.templates) do
        names[entry.name] = entry.kind
        assert(entry.description ~= "", entry.name .. " describes itself")
    end
    assert(names.app == "builtin" and names.lib == "builtin", "the listing names the built-ins")
    local planned = agrees(dir, "init --dry-run app greeter")
    assert(planned.dryRun and #planned.written > 0, "a dry run is the scaffold shape")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.lspOperationsMatchTheirOwnSchemas()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"."}}\n',
        [
            "lib.nupp"
        ] = "local lib = {}\n\n--- Double a value.\n"
        .. "function lib.double(n: integer): integer\n    return n * 2\nend\n\n"
        .. "return lib\n",
        ["main.nupp"] = 'local lib = require("lib")\nreturn lib.double(21)\n'
    })
    -- Each operation carries its own grammar and so its own schema; the group
    -- has none of its own to give.
    agrees(dir, "lsp inspect lib.nupp 4 16")
    agrees(dir, "lsp definition main.nupp 2 12")
    agrees(dir, "lsp references lib.nupp 4 16")
    agrees(dir, "lsp symbols")
    agrees(dir, "lsp actions lib.nupp 4 16")
    local renamed = agrees(dir, "lsp rename lib.nupp 4 16 twice")
    assert(renamed.written == false, "rename previews by default")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.versionOutputMatchesItsSchema()
    local decoded = agrees(nil, "version")
    assert(
        decoded.version == require("nupp.tools.version").VERSION,
        "the version reported is the one the compiler carries"
    )
end

function M.explainOutputMatchesItsSchema()
    local decoded = agrees(nil, "explain NUPP2119")
    assert(decoded.code == "NUPP2119", "the code is echoed")
    assert(decoded.docs, "and its reference given")

    local listed = agrees(nil, "explain --list")
    assert(#listed.codes > 0, "the list contains dedicated explanations")
    for index = 2, #listed.codes do
        assert(listed.codes[index - 1] < listed.codes[index], "the list is sorted without duplicates")
    end
end

-- The uniform `--json` failure contract, held against every command that has one.
--
-- Exit 2 is a usage error and writes nothing to stdout. Exit 0 or 1 writes exactly one
-- document, valid against the command's own `--schema`, whose `ok` says which, and a
-- document with `ok` false carries at least one error with a code: a failure before
-- the work started -- a missing file, a manifest that does not load, a name that
-- names nothing -- is still a coded diagnostic rather than a line on stderr.

-- Runs a command and returns what it wrote to stdout and its exit status.
local function statusOf(dir, argv)
    local prefix = dir and ("cd '" .. dir .. "' && ") or ""
    local pipe = assert(io.popen(prefix .. ("'%s' %s 2>/dev/null; echo \"__exit__:$?\""):format(NUPP, argv)))
    local out = pipe:read("*a")
    pipe:close()
    local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")), "no exit status in:\n" .. out)

    return (out:gsub("__exit__:%d+%s*$", "")), code
end

-- `jsonFlag` false is for a command whose only report is JSON. `runner` marks `test`,
-- which answers a failure before its tests started with its own record rather than
-- with diagnostics.
local function holdsTheContract(dir, argv, options)
    options = options or {}
    local schemaArgv = options.schema or argv
    local full = options.alreadyJson and argv or (argv .. " --json")
    local out, code = statusOf(dir, full)
    local label = full .. " (in " .. tostring(options.where or dir) .. ")"
    assert(code == 0 or code == 1, label .. " exits " .. code .. ", which is neither an answer nor a failure:\n" .. out)
    assert(select(2, out:gsub("\n", "")) == 1 and out:sub(-1) == "\n", label .. " writes one line of JSON:\n" .. out)
    local ok, decoded = pcall(json.decode, out)
    assert(ok and type(decoded) == "table", label .. " writes no JSON document:\n" .. out)
    local schemaText = capture(dir, schemaArgv .. " --schema")
    local schema = json.decode(schemaText)
    local valid, err = validate(decoded, schema)
    assert(valid, label .. " does not match its own --schema: " .. tostring(err) .. "\noutput: " .. out)
    assert(decoded.ok == (code == 0), label .. " says ok = " .. tostring(decoded.ok) .. " and exits " .. code)
    if options.expectOk ~= nil then
        assert(decoded.ok == options.expectOk, label .. " should answer ok = " .. tostring(options.expectOk) .. ":\n" .. out)
    end
    if not decoded.ok then
        if options.runner then
            local failedRecord = false
            for _, record in ipairs(decoded.tests or {}) do
                failedRecord = failedRecord or (record.status == "failed" and record.failure and record.failure.message ~= "")
            end
            assert(failedRecord, label .. " answers a failure with a failed record:\n" .. out)
        else
            local coded = nil
            for _, diagnostic in ipairs(decoded.diagnostics or {}) do
                if diagnostic.severity == "error" and type(diagnostic.code) == "string" and diagnostic.code:match("^NUPP%d%d%d%d$") then
                    coded = coded or diagnostic
                end
            end
            assert(coded, label .. " fails without a coded error diagnostic:\n" .. out)
            if options.code then
                assert(coded.code == options.code, label .. " should report " .. options.code .. ":\n" .. out)
            end
        end
    end

    return decoded
end

local function failureProjects()
    local good = tempProject({
        ["nupp.lua"] = 'return {include = {"."}, build = {default = "app", targets = {app = {kind = "modules"}}}}\n',
        ["good.nupp"] = GOOD,
        ["kernel.nupp"] = "@aot\nlocal function twice(x: number): number\n    return x * 2.0\nend\n\nreturn {twice = twice}\n",
    })
    local broken = tempProject({["nupp.lua"] = "return { build = { targets = 5 }, nope = \n", ["good.nupp"] = GOOD})
    local none = tempProject({["good.nupp"] = GOOD})

    return good, broken, none
end

function M.everyCommandReportsAMissingFileAsACodedFailure()
    local good, broken, none = failureProjects()
    for _, argv in ipairs({
        "check nosuch.nupp",
        "build nosuch.nupp",
        "fmt nosuch.nupp",
        "bc nosuch.nupp",
        "aot nosuch.nupp",
        "doc nosuch.nupp",
        "import-c nosuch.h",
        "migrate nosuch.lua",
        "ownership-audit nosuch.nupp",
        "lsp inspect nosuch.nupp 1 1",
        "lsp definition nosuch.nupp 1 1",
        "lsp implementation nosuch.nupp 1 1",
        "lsp references nosuch.nupp 1 1",
        "lsp rename nosuch.nupp 1 1 other",
        "lsp actions nosuch.nupp 1 1",
        "lsp trace-check nosuch.nupp 1 1",
        "lsp artifacts nosuch.nupp 1 1",
        "lsp artifact --kind lua nosuch.nupp",
        "lsp symbols --file nosuch.nupp",
    }) do
        holdsTheContract(good, argv, {code = "NUPP0001", where = "a project"})
    end
    holdsTheContract(good, "ast nosuch.nupp", {alreadyJson = true, code = "NUPP0001", where = "a project"})
    holdsTheContract(good, "lsp inspect good.nupp 99 1", {code = "NUPP0003", where = "a project"})
    holdsTheContract(good, "bench --list --file nosuch.bench.nupp", {code = "NUPP0001", where = "a project"})
    holdsTheContract(good, "bench --file nosuch.bench.nupp", {where = "a project"})
    holdsTheContract(good, "bench --list --case nosuch", {code = "NUPP0003", where = "a project"})
    os.execute("rm -rf '" .. good .. "' '" .. broken .. "' '" .. none .. "'")
end

function M.everyCommandReportsABrokenManifestAsACodedFailure()
    local good, broken, none = failureProjects()
    for _, argv in ipairs({
        "check",
        "check good.nupp",
        "build",
        "clean",
        "task --list",
        "lints",
        "doc",
        "fixpoint",
        "export-c -o out.h good.nupp good.Missing",
        "lsp symbols",
        "lsp inspect good.nupp 1 7",
    }) do
        holdsTheContract(broken, argv, {code = "NUPP0002", where = "a broken manifest"})
    end
    -- `task` stops reading options at its first argument, which is the task's name.
    holdsTheContract(broken, "task --list --json app", {alreadyJson = true, schema = "task", code = "NUPP0002"})
    holdsTheContract(broken, "test", {runner = true, where = "a broken manifest"})
    os.execute("rm -rf '" .. good .. "' '" .. broken .. "' '" .. none .. "'")
end

function M.everyCommandAnswersWithoutAManifestOrSaysWhy()
    local good, broken, none = failureProjects()
    for _, argv in ipairs({"check", "build", "clean", "task --list", "fixpoint"}) do
        holdsTheContract(none, argv, {code = "NUPP0002", where = "no manifest"})
    end
    holdsTheContract(none, "test", {runner = true, where = "no manifest"})
    -- A directory without `nupp.lua` is a supported configuration for these.
    for _, argv in ipairs({"lints", "lsp symbols", "check good.nupp"}) do
        holdsTheContract(none, argv, {expectOk = true, where = "no manifest"})
    end
    os.execute("rm -rf '" .. good .. "' '" .. broken .. "' '" .. none .. "'")
end

function M.everyCommandReportsAnUnknownNameAsACodedFailure()
    local good, broken, none = failureProjects()
    for _, argv in ipairs({
        "check --target nosuch",
        "build --target nosuch",
        "clean --target nosuch",
        "doc --target nosuch",
        "aot --triple nosuch-unknown-none kernel.nupp",
    }) do
        holdsTheContract(good, argv, {code = "NUPP0003", where = "a project"})
    end
    holdsTheContract(good, "task --list --json nosuch", {alreadyJson = true, schema = "task", code = "NUPP0003"})
    os.execute("rm -rf '" .. good .. "' '" .. broken .. "' '" .. none .. "'")
end

-- A usage error is decided from the arguments, before any format could be honoured, so
-- stdout stays empty even under `--json` and the status alone says what happened.
function M.aUsageErrorWritesNothingToStdout()
    local good, broken, none = failureProjects()
    for _, argv in ipairs({
        "check --json --nosuchflag",
        "explain --json NUPP9999",
        "reference --json --section nosuchsection",
        "lsp inspect --json good.nupp 0 1",
        "init --json nosuchtemplate x",
        "fmt --json --width 3 good.nupp",
    }) do
        local out, code = statusOf(good, argv)
        assert(code == 2, argv .. " is a usage error, status 2, not " .. code)
        assert(out == "", argv .. " writes nothing to stdout on a usage error: " .. out)
    end
    os.execute("rm -rf '" .. good .. "' '" .. broken .. "' '" .. none .. "'")
end

-- The shapes a failure document takes are the command's own, so a reader validates
-- it against the same schema as a success.
function M.everySchemaRequiresOk()
    local cli = require("nupp.tools.cli")
    local function requiresOk(schema, name)
        if schema.oneOf or schema.anyOf then
            for _, branch in ipairs(schema.oneOf or schema.anyOf) do
                requiresOk(branch, name)
            end
            return
        end
        local found = false
        for _, required in ipairs(schema.required or {}) do
            found = found or required == "ok"
        end
        assert(found, name .. " --schema does not require ok")
    end
    -- `run` is the exception: the program owns stdout, and its `--json` is the trace
    -- report it writes to a file.
    for _, name in ipairs(cli.names()) do
        if name ~= "help" and name ~= "lsp" and name ~= "run" then
            local help = capture(nil, "help " .. name)
            if help:find("--schema", 1, true) then
                requiresOk(json.decode(capture(nil, name .. " --schema")), name)
            end
        end
    end
    for _, operation in ipairs({
        "inspect", "definition", "implementation", "references", "symbols", "rename", "actions", "trace-check",
        "artifacts", "artifact",
    }) do
        requiresOk(json.decode(capture(nil, "lsp " .. operation .. " --schema")), "lsp " .. operation)
    end
end

function M.aRunReportsItsTraceAbortsInTheSharedShapes()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"."}}\n',
        ["loop.lua"] = "local t = 0\nfor i = 1, 200 do local f = function() return i end t = t + f() end\nreturn t\n",
    })
    local out, code = statusOf(dir, "run --jit-aborts=aborts.json --json loop.lua")
    assert(code == 0, out)
    local handle = assert(io.open(dir .. "/aborts.json", "rb"))
    local text = handle:read("*a")
    handle:close()
    local decoded = json.decode(text)
    local valid, err = validate(decoded, json.decode(capture(dir, "run --schema")))
    assert(valid, "the trace report matches run's --schema: " .. tostring(err) .. "\n" .. text)
    assert(decoded.durationMs and decoded.durationSec == nil, "the duration is in milliseconds")
    for _, site in ipairs(decoded.sites) do
        assert(site.severity == nil and site.class and type(site.blacklisted) == "boolean", "one severity vocabulary")
        assert(type(site.location) == "table" and site.location.file, "a location is a file and a range")
    end
    os.execute("rm -rf '" .. dir .. "'")
end

function M.reportEncodingSortsKeysWithoutChangingValues()
    local report = require("nupp.tools.cli.report")
    local first = {text = "line\nbreak", number = 1.25, flag = true, list = {3, 2}, nested = {z = "last", a = "first"},}
    local second = {
        nested = {a = "first", z = "last"},
        list = {3, 2},
        flag = true,
        number = 1.25,
        text = "line\nbreak",
    }
    local expected = [[{"flag":true,"list":[3,2],"nested":{"a":"first","z":"last"},"number":1.25,"text":"line\nbreak"}]]
    assert(report.encode(first) == expected, report.encode(first))
    assert(report.encode(second) == expected, report.encode(second))
end

function M.fileDiagnosticsAlwaysCarryAMessage()
    local report = require("nupp.tools.cli.report")
    local diagnostic = report.fileDiagnostic("missing.nupp", nil, "check the path")
    local value = report.diagnosticValues({diagnostic})[1]
    assert(value.message == "cannot access missing.nupp", "an absent OS error gets a useful message")
    assert(value.range == nil, "a diagnostic about a file rather than a place in it has no range")
    assert(value.code == "NUPP0001", "and carries the code for a file the run never got inside")

    diagnostic.related = {{filename = "other.nupp", offset = 1, length = 0, msg = "declared here"}}
    value = report.diagnosticValues({diagnostic})[1]
    assert(value.related[1].message == "declared here", "compiler related messages retain their text")
end

--- Every name a schema requires is one it also describes, at every depth. A
--- required name with no property is a field the validator above can never
--- check the type of, which is how a promise goes unkept without anything failing.
local function requiredAreDescribed(schema, path)
    if type(schema) ~= "table" then
        return
    end
    if schema.required then
        for _, name in ipairs(schema.required) do
            assert(
                schema.properties and schema.properties[name],
                ("%s requires %q without describing it"):format(path, name)
            )
        end
    end
    for key, child in pairs(schema) do
        if type(child) == "table" then
            requiredAreDescribed(child, path .. "." .. tostring(key))
        end
    end
end

function M.everySchemaDescribesWhatItRequires()
    local cli = require("nupp.tools.cli")
    for _, name in ipairs(cli.names()) do
        if name ~= "help" and name ~= "lsp" then
            local help = capture(nil, "help " .. name)
            if help:find("--schema", 1, true) then
                local text = capture(nil, name .. " --schema")
                requiredAreDescribed(json.decode(text), name)
            end
        end
    end
    local lspOperations = {"inspect", "definition", "references", "symbols", "rename", "actions", "trace-check"}
    for _, operation in ipairs(lspOperations) do
        local text = capture(nil, "lsp " .. operation .. " --schema")
        requiredAreDescribed(json.decode(text), "lsp " .. operation)
    end
end

function M.everyCommandThatWritesJsonAlsoDescribesIt()
    -- The pairing is the point: a command that can be asked for JSON can always
    -- be asked what that JSON will look like.
    local cli = require("nupp.tools.cli")
    for _, name in ipairs(cli.names()) do
        if name ~= "help" then
            local help = capture(nil, "help " .. name)
            if help:find("--json", 1, true) then
                assert(help:find("--schema", 1, true), name .. " offers --json without --schema")
            end
        end
    end
end

return M
