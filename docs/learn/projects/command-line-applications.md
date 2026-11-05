---
order: 570
---

# Command-line applications

`io.cli` parses raw option tokens or derives complete applications from typed
records. Types control argument conversion, while doc comments supply help text.

```nupp
local cli = io.cli

@derive(cli.arguments)
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

local options, problem = Options.fromcli(io.cli.args)
assert(options ~= nil, problem and problem.message)
```

## Parse option tokens

`optparser` is a mutable token cursor that does not allocate a token object on
each advance. Configure which options take values, then advance it until it
ends. `next` returns a token kind; the token's data remains on the parser until
the following `next` call.

```nupp
local cli = io.cli

local parser = cli.optparser(io.cli.args, {
    arity = {output = cli.required, verbose = cli.none},
})
while true do
    local kind, problem = parser:next()
    assert(problem == nil, problem and problem.message)
    if kind == nil then break end
    if kind == cli.shortoption or kind == cli.longoption then
        print(kind, parser:key(), parser:value() or "")
    else
        print(kind, parser:raw())
    end
end
```

`raw` and `index` are valid for every current token. `key`, `value`, `attached`,
and `pattern` are option-only and raise when the current token is another kind.
Every accessor raises before the first token and after the end. `cli.getopt`
exposes the token kind and current parser as an iterator, raising on syntax
errors. `--` makes every remaining word an argument.

## Derive typed arguments

`@derive(cli.arguments)` adds `fromcli`. Optional choice positionals are skipped
until an argument matches, so a required positional can follow them.

```nupp
local cli = io.cli

@derive(cli.arguments)
local record Input
    --- Execution mode.
    @cli(positional = "MODE", choices = {"fast", "thorough"})
    mode: string?

    --- Input file.
    @cli(positional = "FILE")
    file: string
end

local input = assert(Input.fromcli({"main.nupp"}))
assert(input.mode == nil and input.file == "main.nupp")
```

## Add commands

`@derive(cli.command)` adds typed parsing, metadata, help, and completion. A
parent returns its children from `subcommands`, so the tree reads from the top
down.

```nupp
local cli = io.cli

--- Search files.
@cli(name = "gmatch")
@derive(cli.command)
local record Gmatch
    --- Lua pattern to find.
    @cli(positional = "PATTERN")
    pattern: string

    --- Files to search.
    @cli(positional = "FILE")
    files: {string} = {}

    function run(self): integer
        for _, path in ipairs(self.files) do
            local file = assert(io.open(path))
            local text = file:read("*a")
            file:close()
            for match in text:gmatch(self.pattern) do
                print(path .. ": " .. match)
            end
        end
        return 0
    end
end

--- Project tools.
@cli(name = "tool", group = true)
@derive(cli.command)
local record Tool
end

function Tool.subcommands(): {cli.CommandType}
    return {Gmatch}
end

return cli.application(Tool):main(io.cli.args)
```

Any command can be an application root. `cli.application(Gmatch):main(io.cli.args)`
runs the same command without the `tool gmatch` prefix.

## Complete dynamic values

Literal choices complete automatically, and a value named `FILE`, `PATH`,
`HEADER`, `INPUT` or `ROCKSPEC` (or `DIR`, `DIRECTORY` or `ROOT`) is handed to
the shell's own file (or directory) completion. Use `@cli(complete = Provider)`
when candidates depend on the machine or current project.

```nupp:fragment
local record Files
    function complete(
        self,
        request: cli.CompletionRequest
    ): {cli.CompletionCandidate}
        local out: {cli.CompletionCandidate} = {}
        local entries = io.files.list(request.cwd) or {}
        for _, entry in ipairs(entries) do
            if entry.name:sub(1, #request.prefix) == request.prefix then
                out[#out + 1] = cli.CompletionCandidate(
                    value = entry.name,
                    kind = "file"
                )
            end
        end
        return out
    end
end

@derive(cli.arguments)
local record FileOptions
    --- File to open.
    @cli(positional = "FILE", complete = Files)
    file: string
end
```

Generate shell adapters with `application:completion("bash" | "zsh" | "fish")`.
Each adapter asks the program for the candidates at the cursor through its
hidden `__complete` command, so the answer is always the current grammar's.

## Use terminal colors

`io.cli.style(stream)` returns styles that become identity functions when
color is disabled.

```nupp:fragment
const terminal = io.cli

local styles = terminal.style(io.stderr)
io.stderr:write(styles.strong("error:") .. " bad input\n")
```

Automatic color respects the output stream, `NO_COLOR`, `CLICOLOR_FORCE`, and
`TERM=dumb`; override it with
`io.cli.setcolormode("always" | "never" | "auto")`.
