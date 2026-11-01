local test = require("assert")
local M = {}

function M.theFacadeExtendsTheOriginalIoTable()
    local original = rawget(_G, "io")
    local loaded = require("io")
    local write, stdout = original.write, original.stdout
    local terminal = require("nupp.runtime.standardio")
    test.equal(terminal.value, original)
    test.equal(require("io"), loaded)
    test.equal(loaded, original)
    test.equal(original.write, write)
    test.equal(original.stdout, stdout)
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
        test.equal(type(original[name]), "function", name)
        test.equal(original[name], terminal[name], name)
    end
end

function M.theFacadeSharesTheApplicationColorPolicy()
    local terminal = require("nupp.runtime.standardio")
    local implementation = require("nupp.cli.internal.terminal")
    terminal.withColorMode("always", function()
        test.equal(implementation.colorEnabled(io.stderr), true)
        test.equal(terminal.colorEnabled(io.stderr), true)
        test.equal(terminal.style(io.stderr).strong("value"), implementation.style(io.stderr).strong("value"))
        terminal.withColorMode("never", function()
            test.equal(implementation.colorEnabled(io.stderr), false)
            test.equal(terminal.style(io.stderr).strong("value"), "value")
        end)
        test.equal(implementation.colorEnabled(io.stderr), true)
    end)
end

return M
