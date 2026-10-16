-- The differential programs' output: each line is its values joined by
-- spaces, error positions removed (chunk names differ between runtimes).
local mmout = {}

function mmout.new()
    local lines = {}
    local function show(v)
        if type(v) == "string" then
            return (v:gsub("^[^:\n]*:%d+: ", ""))
        end
        return tostring(v)
    end
    local function p(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = show((select(i, ...)))
        end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    local function done()
        return table.concat(lines, "\n") .. "\n"
    end
    return p, done
end

--- `v` as a value of unknown type, for the operations a checker would refuse
--- on a known one: the programs test what the runtime does with them.
function mmout.opaque(v)
    return rawget({v}, 1)
end

return mmout
