local test = require("assert")
local M = {}

function M.theCliLibraryKeepsTheRawArgvSeparate()
    local original = rawget(_G, "arg")
    local before, sequential = {}, {}
    local metatable = getmetatable(original)
    for key, value in pairs(original) do
        before[key] = value
    end
    for key, value in ipairs(original) do
        sequential[key] = value
    end
    local cli = require("io.cli")
    local argv = cli.args
    test.eq(argv, original)
    test.ne(cli, argv)
    test.eq(require("io.cli"), cli)
    test.eq(#argv, #original)
    test.eq(getmetatable(argv), metatable, "loading CLI helpers must not change argv's metatable")
    local after, traversed = {}, {}
    for key, value in pairs(argv) do
        after[key] = value
    end
    for key, value in ipairs(argv) do
        traversed[key] = value
    end
    test.deepeq(after, before)
    test.deepeq(traversed, sequential)
    for _, name in ipairs({"parse", "schema", "optparser", "getopt", "application", "descriptor", "style", "table"}) do
        test.eq(rawget(argv, name), nil, name)
        test.eq(argv[name], nil, "argv has no library helper " .. name)
        test.eq(type(cli[name]), "function", name)
    end
    test.eq(cli.arguments, nil, "derive providers remain erased")
    test.eq(cli.command, nil, "derive providers remain erased")
end

function M.embeddedHostsGetAnEmptyArgumentTable()
    local previousArgs, previousModule = rawget(_G, "arg"), package.loaded["io.cli"]
    rawset(_G, "arg", nil)
    package.loaded["io.cli"] = nil
    local ok, problem = pcall(function()
        local cli = require("io.cli")
        test.eq(type(cli.args), "table")
        test.eq(next(cli.args), nil)
        test.eq(rawget(_G, "arg"), nil, "loading CLI helpers must not create a global")
    end)
    rawset(_G, "arg", previousArgs)
    package.loaded["io.cli"] = previousModule
    assert(ok, problem)
end

function M.bareArgIsNotACheckedGlobal()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("helpers.fragment")
    local env = require("nupp.compiler.project.env").new(".")
    test.eq(env.globals.arg, nil, "arg must not remain an ambient library")
    test.eq(env.bundledImplementation("arg"), nil, "the old argument module must not remain carried")
    test.eq(env.bundledImplementation("io.terminal"), nil, "the old terminal facade must not remain carried")
    local source = parser.parse("return arg\n", "bare-arg.nupp")
    local diagnostics = checker.check(source, "bare-arg.nupp", env)
    local refused = false
    for _, diagnostic in ipairs(diagnostics) do
        refused = refused
            or diagnostic.code == "NUPP2105" and diagnostic.msg:find('unknown variable "arg"', 1, true) ~= nil
    end
    test(refused, "bare arg must not expose the CLI library or raw argv")
end

function M.theTypedFacadeKeepsProvidersAliasesAndShadowing()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("helpers.fragment")
    local gen = require("nupp.compiler.lua.gen")
    local environment = require("nupp.compiler.project.env").new(".")
    local runtime = require("nupp.compiler.runtime")

    local function compile(path, env, _, source)
        if source == nil then
            local file = assert(io.open(path, "rb"))
            source = file:read("*a")
            file:close()
        end
        local parsed = parser.parse(source, path)
        if #parsed.errors > 0 then
            return nil, parsed.errors[1].msg
        end
        local diags = checker.check(parsed, path, env)
        if #diags > 0 then
            return nil, diags[1].msg
        end
        local code, generated = gen.generate(parsed, path)
        if #generated > 0 then
            return nil, generated[1].msg
        end

        return code
    end

    local removeLoader = runtime.install(environment, compile)
    local ok, problem = pcall(function()
        local code, reason = compile("tests/fixtures/argfacade.nupp", environment)
        test(code, reason)
        assert(loadstring(code, "@tests/fixtures/argfacade.nupp"))()
        local acceptingSource = [[
local cli = require("io.cli")

@cli(preserveunknown = true)
@derive(cli.arguments)
local record Forwarded
    @cli(arity = "optionalattached", constant = "")
    profile: string?
    @cli(constantaliases = {json = "json"})
    format: "text" | "json" = "text"
    @cli(arity = "attachedonly")
    output: string?
    @cli(remainder = true)
    arguments: {string} = {}
end

local value, problem = cli.parse(Forwarded, {"--json", "--profile=fast", "--output=out", "--other", "value"})
assert(value ~= nil, problem and problem.message)
assert(value.format == "json" and value.profile == "fast" and value.output == "out")
assert(#value.arguments == 2 and value.arguments[1] == "--other" and value.arguments[2] == "value")
local bare = assert(cli.parse(Forwarded, {"--profile"}))
assert(bare.profile == "")
local separated, missingAttached = cli.parse(Forwarded, {"--output", "out"})
assert(separated == nil and missingAttached ~= nil)
local schema = assert(cli.schema(Forwarded))
assert(schema.preserveUnknown == true)
assert(schema.fields[1].arity == "optionalattached" and schema.fields[3].arity == "attachedonly")

@cli(stopatfirstargument = true)
@derive(cli.arguments)
local record Stopped
    flag: boolean = false
    @cli(remainder = true)
    arguments: {string} = {}
end
local stopped = assert(cli.parse(Stopped, {"program", "--flag"}))
assert(not stopped.flag and #stopped.arguments == 2 and stopped.arguments[2] == "--flag")
cli.withcolormode("never", function()
    local listing: cli.Table = cli.table(io.stdout)
        :column("count", align = "right", minimumwidth = 4)
        :column("description")
        :headings(false)
        :row()
        :cell("7")
        :cell("done", note = " (ok)")
    assert(listing:tostring() == "   7  done (ok)\n")
end)
]]
        local accepted, failure = compile(
            "tests/fixtures/arg_annotation_acceptor.nupp",
            environment,
            nil,
            acceptingSource
        )
        test(accepted, failure)
        assert(loadstring(accepted, "@tests/fixtures/arg_annotation_acceptor.nupp"))()
    end)
    removeLoader()
    if not ok then
        error(problem, 0)
    end
end

return M
