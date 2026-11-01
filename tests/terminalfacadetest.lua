local test = require("assert")
local M = {}

function M.theFacadeExtendsTheOriginalIoTable()
    local original = rawget(_G, "io")
    local loaded = require("io")
    local write, stdout = original.write, original.stdout
    local terminal = require("nupp.runtime.standardio")
    test.eq(terminal.value, original)
    test.eq(require("io"), loaded)
    test.eq(loaded, original)
    test.eq(original.write, write)
    test.eq(original.stdout, stdout)
    for _, name in ipairs({
        "style",
        "table",
        "writeTable",
        "cell",
        "paintedCell",
        "annotatedCell",
        "severity",
        "setColorMode",
        "withColorMode",
        "colorEnabled",
        "isTerminal",
        "columns"
    }) do
        test.eq(type(original[name]), "function", name)
        test.eq(original[name], terminal[name], name)
    end
end

function M.theFacadeSharesTheApplicationColorPolicy()
    local terminal = require("nupp.runtime.standardio")
    local implementation = require("nupp.cli.internal.terminal")
    terminal.withColorMode("always", function()
        test.eq(implementation.colorEnabled(io.stderr), true)
        test.eq(terminal.colorEnabled(io.stderr), true)
        test.eq(terminal.style(io.stderr).strong("value"), implementation.style(io.stderr).strong("value"))
        terminal.withColorMode("never", function()
            test.eq(implementation.colorEnabled(io.stderr), false)
            test.eq(terminal.style(io.stderr).strong("value"), "value")
        end)
        test.eq(implementation.colorEnabled(io.stderr), true)
    end)
end

return M
