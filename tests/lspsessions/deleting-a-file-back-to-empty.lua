-- Select-all and delete, then start over. The buffer passes through empty,
-- through a lone `end` with nothing to close, and through a `with` scope
-- missing its body — states where every position a request could name has gone.
local FULL = table.concat({
    "local files = {}",
    "",
    "function files.readAll(path: string): string",
    "    with handle = io.open(path, 'r') do",
    "        return handle:read('*a')",
    "    end",
    "end",
    "",
    "return files",
}, "\n") .. "\n"

local states = {FULL}
-- Deleted from the bottom up, which is what backspacing out of a file does.
local lines = {}
for line in FULL:gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
for count = #lines - 1, 0, -1 do
    local kept = {}
    for index = 1, count do kept[index] = lines[index] end
    states[#states + 1] = table.concat(kept, "\n") .. (count > 0 and "\n" or "")
end
states[#states + 1] = FULL

return {
    files = {["files.nupp"] = FULL},
    open = {"files.nupp"},
    document = "files.nupp",
    states = states,
    -- on `readAll`, which exists again only because the last state restores it
    probes = {{file = "files.nupp", line = 2, character = 16}},
}
