---
order: 655
---

# `nupp.cli`

`nupp.cli` provides incremental option parsing, typed argument records,
subcommands, help, shell completion, and terminal styles. The lower layers do
not require the higher ones: a program may use only `optParser`, derive an
argument record without an application, or assemble derived command types.

## Incremental parsing

`cli.optParser(argv, config)` is a Nim `parseopt`-style token stream. `next()`
returns a `shortOption`, `longOption`, `argument`, or `terminator` token with
its original word and one-based argv index. A token also says whether its value
was attached and whether a configured whole-word pattern matched it. The
configured arity decides whether an option consumes the following word.
Unknown names remain tokens; the primitive does not apply an application's
policy.

```nupp
local cli = require("nupp.cli")

local parser = cli.optParser(arg, {
    arity = {output = cli.required, verbose = cli.none},
})
while true do
    local token, problem = parser:next()
    assert(problem == nil, problem and problem.message)
    if token == nil then break end
    print(token.kind, token.key or token.raw, token.value or "")
end
```

`cli.getopt` returns the same stream as an iterator. Optional values are
attached-only, so a bare option never steals the next positional. `--`
preserves every later word as an argument.

## Typed arguments

`@derive(cli.Arguments)` adds `fromCLI(argv)` and makes the type available to
`cli.decodeAs(Type, argv)` and `cli.schema(Type)`. Field types provide
conversion and requiredness. Booleans are flags; strings, numbers, integers,
literal unions, optionals, arrays, and string-to-boolean sets are supported.

The `@cli` annotation is only for syntax that a type cannot express: names,
aliases, short forms, value labels, positionals, remainders, attached values,
whole-word patterns, constants, and completion providers. A member's `---`
documentation is its help text; there is no separate help string.

```nupp
local cli = require("nupp.cli")

@derive(cli.Arguments)
local record Options
    --- Print more detail.
    @cli(short = "v")
    verbose: boolean = false

    --- Output path.
    @cli(short = "o", value = "PATH")
    output: string?

    --- Input files.
    @cli(positional = "FILE")
    files: {string} = {}
end

local options, problem = Options.fromCLI(arg)
assert(options ~= nil, problem and problem.message)
```

## Commands and subcommands

`@derive(cli.Command)` adds the argument decoder and a command descriptor. The
record's documentation supplies its summary, `@cli(parent = Type)` places it
under another command, and its `run(self)` method executes the typed value.

```nupp
local cli = require("nupp.cli")

--- Example project tool.
@cli(name = "tool", group = true)
@derive(cli.Command)
local record Tool
end

--- Match text in files.
@cli(name = "gmatch", aliases = {"match"}, parent = Tool)
@derive(cli.Command)
local record Gmatch
    --- Lua pattern to find.
    @cli(positional = "PATTERN")
    pattern: string

    --- Files to search.
    @cli(positional = "FILE")
    files: {string} = {}

    function run(self): integer
        for _, path in ipairs(self.files) do
            for match in assert(io.open(path)):read("*a"):gmatch(self.pattern) do
                print(path .. ": " .. match)
            end
        end
        return 0
    end
end

local app = cli.application(Tool, {Gmatch}, {name = "tool"})
return app:main(arg)
```

The application derives command lookup, aliases, usage, help, and static
completion from these types. Groups may own nested children. Resolution and
typed decoding are available without I/O through `Application:resolve`.

## Dynamic completion

Literal choices are completed automatically. For values discovered at runtime,
attach a zero-argument provider type with `@cli(complete = Provider)`. Its
`complete(request)` method returns `cli.CompletionCandidate` records. It may
inspect the prefix, argv, command path, working directory, or environment; a
provider failure produces no candidates and never runs the command.

```nupp
local record Files
    function complete(self, request: cli.CompletionRequest): {cli.CompletionCandidate}
        local out: {cli.CompletionCandidate} = {}
        for _, entry in ipairs(require("nupp.io.files").list(request.cwd) or {}) do
            if entry.name:sub(1, #request.prefix) == request.prefix then
                out[#out + 1] = new cli.CompletionCandidate(value = entry.name, kind = "file")
            end
        end
        return out
    end
end
```

`Application:completion("bash" | "zsh" | "fish")` writes an adapter for one
shell. Commands, aliases, options, and closed choices are embedded in the
script. An application with a dynamic provider uses its private completion
query to reach that provider; a fully static application does not start the
executable during completion. `Application:complete(request)` exposes the same
shell-neutral candidates directly.

## Terminal styles

`cli.setColorMode("auto" | "always" | "never")`, `cli.withColorMode`,
`cli.colorEnabled(stream)`, `cli.isTerminal(stream)`, and `cli.style(stream)`
share one color policy. Automatic mode honors `NO_COLOR`, `CLICOLOR_FORCE`, and
`TERM=dumb` and decides independently for stdout and stderr. A plain style is
an identity operation and emits no escape bytes.
