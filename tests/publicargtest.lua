local test = require("assert")
local M = {}

function M.theArgumentLibraryKeepsTheActualRawArgv()
    local original = rawget(_G, "arg")
    local before, sequential = {}, {}
    for key, value in pairs(original) do
        before[key] = value
    end
    for key, value in ipairs(original) do
        sequential[key] = value
    end
    local count = #original
    local argv = require("arg")
    test.eq(argv, original)
    test.eq(argv, arg)
    test.eq(require("arg"), argv)
    test.eq(#argv, count)
    local after, traversed = {}, {}
    for key, value in pairs(argv) do
        after[key] = value
    end
    for key, value in ipairs(argv) do
        traversed[key] = value
    end
    test.deepeq(after, before)
    test.deepeq(traversed, sequential)
    for _, name in ipairs({"parse", "schema", "optparser", "getopt", "application", "descriptor"}) do
        test.eq(rawget(argv, name), nil, name)
        test.eq(type(argv[name]), "function", name)
        test.eq(argv[name], getmetatable(argv).__index[name])
    end
    test.eq(rawget(argv, "Arguments"), nil, "derive providers remain erased")
    test.eq(rawget(argv, "Command"), nil, "derive providers remain erased")
    test.eq(argv.decodeAs, nil)
    test.eq(argv.style, nil)
end

function M.theTypedFacadeKeepsProvidersAliasesAndShadowing()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("fragment")
    local program = require("program")
    local loadImage = assert(rawget(_G, "__nupp_load_image"))
    local environment = require("nupp.compiler.project.env").new(".")
    local runtime = require("nupp.compiler.runtime")

    local function compile(path, env, name, source)
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
        local ok, image = pcall(program.image, parsed, name, path)
        if not ok then
            return nil, tostring(image)
        end

        return image
    end

    local removeLoader = runtime.install(environment, compile, nil, nil, function(image)
        return loadImage(image)
    end)
    local ok, problem = pcall(function()
        local code, reason = compile("tests/fixtures/argfacade.nupp", environment)
        test(code, reason)
        assert(loadImage(code))()
        local acceptingSource = [[
local cli = require("arg")

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
]]
        local accepted, failure = compile(
            "tests/fixtures/arg_annotation_acceptor.nupp",
            environment,
            nil,
            acceptingSource
        )
        test(accepted, failure)
        assert(loadImage(accepted))()
    end)
    removeLoader()
    if not ok then
        error(problem, 0)
    end
end

return M
