-- An export is renamed by typing over it while a dependent file is open in
-- another tab. Every keystroke breaks the dependent and the last one fixes it —
-- but only if the dependent is rechecked against each state rather than against
-- the one the server first read.
local USE = table.concat({
    'local model = require("model")',
    "",
    "local t: model.Token",
}, "\n") .. "\n"

local function model(typeName)
    return table.concat({
        "local model = {}",
        "",
        "record model." .. typeName,
        "    id: uint32",
        "end",
        "",
        "return model",
    }, "\n") .. "\n"
end

-- `Token` typed over into `Tok`, then back out to `Token`: the dependent is
-- broken at every step but the first and the last.
local states = {}
for _, typeName in ipairs({
    "Token", "Toke", "Tok", "To", "T", "To", "Tok", "Toke", "Token",
}) do
    states[#states + 1] = model(typeName)
end

return {
    files = {["model.nupp"] = states[1], ["use.nupp"] = USE},
    open = {"model.nupp", "use.nupp"},
    document = "model.nupp",
    states = states,
    -- on `Token` in the dependent, which is not the document being edited
    probes = {{file = "use.nupp", line = 2, character = 17}},
}
