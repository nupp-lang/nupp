-- Somebody writes one annotated local, a keystroke at a time. Almost every
-- state on the way is a file that does not parse: an annotation with no type
-- after the colon, a dotted path with nothing after the dot, a constructor with
-- an open brace. The server sees all of them and has to end up where a server
-- handed only the last one would be.
local SHAPES = table.concat({
    "local shapes = {}",
    "",
    "--- A point in the plane.",
    "record shapes.Point",
    "    x: number",
    "    y: number",
    "end",
    "",
    "return shapes",
}, "\n") .. "\n"

local HEAD = 'local shapes = require("shapes")\n\n'

local states = {}
for _, tail in ipairs({
    "",
    "l",
    "loc",
    "local",
    "local ",
    "local p",
    "local p:",
    "local p: ",
    "local p: sh",
    "local p: shapes",
    "local p: shapes.",
    "local p: shapes.Po",
    "local p: shapes.Point",
    "local p: shapes.Point =",
    "local p: shapes.Point = shapes.Point{",
    "local p: shapes.Point = shapes.Point{x = 1,",
    "local p: shapes.Point = shapes.Point{x = 1, y = 2}",
}) do
    states[#states + 1] = HEAD .. tail .. "\n"
end

return {
    files = {["shapes.nupp"] = SHAPES, ["use.nupp"] = states[1]},
    open = {"use.nupp"},
    document = "use.nupp",
    states = states,
    -- on `Point` of the annotation, which only exists in the last few states
    probes = {{file = "use.nupp", line = 2, character = 17}},
}
