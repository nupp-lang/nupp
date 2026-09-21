---
order: 570
---

# Command-line applications

`nupp.cli` can parse raw option tokens or derive a complete application from typed records.

## Parse option tokens

`optParser` is a mutable token cursor that does not allocate a token object on each advance. Configure which options take values, then advance it until it ends. `next` returns a token kind; the token's data remains on the parser until the following `next` call.

```nupp
local cli = require("nupp.cli")

local parser = cli.optParser(arg, {
    arity = {output = cli.required, verbose = cli.none},
})
while true do
    local kind, problem = parser:next()
    assert(problem == nil, problem and problem.message)
    if kind == nil then break end
    if kind == cli.shortOption or kind == cli.longOption then
        print(kind, parser:key(), parser:value() or "")
    else
        print(kind, parser:raw())
    end
end
```

`raw` and `index` are valid for every current token. `key`, `value`, `attached`, and `pattern` are option-only and raise when the current token is another kind. Every accessor raises before the first token and after the end. `cli.getopt` exposes the token kind and current parser as an iterator, raising on syntax errors. `--` makes every remaining word an argument.

## Derive typed arguments

`@derive(cli.Arguments)` adds `fromCLI`. Types control conversion and required values; documentation comments become help text.

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

## Add commands

`@derive(cli.Command)` adds typed parsing, metadata, help, and completion. A parent returns its children from `subcommands`, so the tree reads from the top down.

```nupp
local cli = require("nupp.cli")

--- Search files.
@cli(name = "gmatch")
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
            local text = assert(io.open(path)):read("*a")
            for match in text:gmatch(self.pattern) do
                print(path .. ": " .. match)
            end
        end
        return 0
    end
end

--- Project tools.
@cli(name = "tool", group = true)
@derive(cli.Command)
local record Tool
end

function Tool.subcommands(): {cli.CommandType}
    return {Gmatch}
end

return cli.application(Tool):main(arg)
```

Any command can be an application root. `cli.application(Gmatch):main(arg)` runs the same command without the `tool gmatch` prefix.

## Complete dynamic values

Literal choices complete automatically. Use `@cli(complete = Provider)` when candidates depend on the machine or current project.

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

@derive(cli.Arguments)
local record FileOptions
    --- File to open.
    @cli(positional = "FILE", complete = Files)
    file: string
end
```

Generate shell adapters with `application:completion("bash" | "zsh" | "fish")`.

## Use terminal colors

`cli.style(stream)` returns styles that become identity functions when color is disabled.

```nupp
local styles = cli.style(io.stderr)
io.stderr:write(styles.bold("error:") .. " bad input\n")
```

Automatic color respects the output stream, `NO_COLOR`, `CLICOLOR_FORCE`, and `TERM=dumb`; override it with `cli.setColorMode("always" | "never" | "auto")`.
