local test = require("assert")
local M = {}

function M.theCliModuleKeepsTerminalAndArgumentHelpersTogether()
    local original = rawget(_G, "io")
    local loaded = require("io")
    local write, stdout = original.write, original.stdout
    local terminal = require("io.cli")
    test.eq(terminal, require("io.cli"))
    test.eq(terminal.args, rawget(_G, "arg"))
    test.eq(type(terminal.parse), "function")
    test.eq(type(terminal.application), "function")
    test.eq(type(terminal.optparser), "function")
    test.eq(require("io"), loaded)
    test.eq(loaded, original)
    test.eq(original.write, write)
    test.eq(original.stdout, stdout)
    for _, name in ipairs({
        "style",
        "table",
        "writetable",
        "cell",
        "paintedcell",
        "annotatedcell",
        "severity",
        "setcolormode",
        "withcolormode",
        "colorenabled",
        "isterminal",
        "columns"
    }) do
        test.eq(type(terminal[name]), "function", name)
        test.eq(original[name], nil, name)
    end
end

function M.theFacadeSharesTheApplicationColorPolicy()
    local terminal = require("io.cli")
    local implementation = require("nupp.cli.internal.terminal")
    terminal.withcolormode("always", function()
        test.eq(implementation.colorEnabled(io.stderr), true)
        test.eq(terminal.colorenabled(io.stderr), true)
        test.eq(terminal.style(io.stderr).strong("value"), implementation.style(io.stderr).strong("value"))
        terminal.withcolormode("never", function()
            test.eq(implementation.colorEnabled(io.stderr), false)
            test.eq(terminal.style(io.stderr).strong("value"), "value")
        end)
        test.eq(implementation.colorEnabled(io.stderr), true)
    end)
end

return M
