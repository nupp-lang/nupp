-- The order people actually write in: use the module first, add the require
-- once the editor complains. The file is wrong for most of the session and then
-- suddenly is not, and the diagnostic that was standing has to come down.
local GEOM = table.concat({
    "local geom = {}",
    "",
    "--- The distance between two points.",
    "function geom.distance(x: number, y: number): number",
    "    return math.sqrt(x * x + y * y)",
    "end",
    "",
    "return geom",
}, "\n") .. "\n"

local BODY = "local d = geom.distance(3, 4)\n"

local states = {BODY}
for _, prefix in ipairs({
    "l",
    "local g",
    "local geom =",
    'local geom = require(',
    'local geom = require("ge',
    'local geom = require("geom")',
}) do
    states[#states + 1] = prefix .. "\n" .. BODY
end

return {
    files = {["geom.nupp"] = GEOM, ["use.nupp"] = BODY},
    open = {"use.nupp"},
    document = "use.nupp",
    states = states,
    -- on `distance`, a plain module member, which resolves only once the
    -- require above it is complete
    probes = {{file = "use.nupp", line = 1, character = 17}},
}
