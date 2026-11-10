local json = require("serde.json")
local M = {}

local function duration(text)
    local milliseconds = text:match("^(%d+)ms$")
    if milliseconds then
        return tonumber(milliseconds)
    end
    local seconds = text:match("^(%d+%.%d)s$")

    return seconds and tonumber(seconds) * 1000 or nil
end

local function measured(text, milliseconds)
    local value = duration(text)
    return value ~= nil and type(milliseconds) == "number" and math.abs(value - milliseconds) <= 101
end

local function step(line)
    local label = line:match("^  (.*)$")
    if not label then
        return false
    end
    if label:sub(1, 1) == "[" then
        local percent, at, total, rest = label:match("^%[ *(%d+)%%%] %[(%d+)/(%d+)%] (.+)$")
        percent, at, total = tonumber(percent), tonumber(at), tonumber(total)
        if not total or total < 1 or at < 1 or at > total or percent ~= math.floor(at / total * 100) then
            return false
        end
        label = rest
    end

    return label == "resolving dependencies"
        or label == "running generators"
        or label == "saving what this run worked out"
        or label == "bundling dist"
        or label == "building the VM program runtime"
        or label:match("^checking [%w_./%-]+$") ~= nil
        or label:match("^generating [%w_./%-]+$") ~= nil
        or label:match("^[%w_.%-]+$") ~= nil
end

-- Success output is a complete build report surrounded only by the fixture's
-- marks and the reporter's progress. Diagnostics are never stripped to find it.
local function accepts(printed)
    printed = printed:gsub("\r\n", "\n")
    if printed:sub(-1) ~= "\n" then
        return false
    end
    local lines = {}
    for line in printed:gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    local began = lines[1] and lines[1]:match("^(%d+%.%d%d%d) compiler target dist: start core build$")
    local ended = lines[#lines] and lines[#lines]:match("^(%d+%.%d%d%d) compiler target dist: finished with status 0$")
    if not began or not ended or tonumber(ended) < tonumber(began) then
        return false
    end
    local report, reportAt
    for index = 2, #lines - 1 do
        if lines[index]:sub(1, 1) == "{" then
            local okay, value = pcall(json.decodevalue, lines[index])
            if not okay or report ~= nil then
                return false
            end
            report, reportAt = value, index
        end
    end
    if type(report) ~= "table"
        or report.ok ~= true
        or report.target ~= "dist"
        or type(report.diagnostics) ~= "table"
        or next(report.diagnostics) ~= nil
        or type(report.timing) ~= "table"
        or reportAt ~= #lines - 1
    then
        return false
    end
    local timing = report.timing
    local compiled, reused = timing.compiledModules, timing.reusedModules
    if type(compiled) ~= "number"
        or compiled < 0
        or compiled % 1 ~= 0
        or type(reused) ~= "number"
        or reused < 0
        or reused % 1 ~= 0
    then
        return false
    end
    local counts = compiled == 0 and ("%d module%s reused"):format(reused, reused == 1 and "" or "s")
        or ("%d compiled, %d reused"):format(compiled, reused)
    if timing.parallel and timing.parallel.mode == "parallel" then
        counts = counts .. (", %d workers"):format(timing.parallel.workers)
    elseif timing.parallel and timing.parallel.mode == "serial-fallback" then
        counts = counts .. ", serial fallback"
    end
    local phases, slowest = {}, {}
    for _, phase in ipairs(timing.phases or {}) do
        phases[phase.name] = phase.durationMs
    end
    for _, item in ipairs(timing.slowest or {}) do
        slowest[item.module] = item.durationMs
    end
    local summary, slowRows, slowHeading = false, 0, false
    for index = 2, reportAt - 1 do
        local line = lines[index]
        local took, actualCounts = line:match("^built dist in (%S+): (.+)$")
        if took then
            if summary or actualCounts ~= counts or not measured(took, timing.totalMs) then
                return false
            end
            summary = true
        elseif not summary then
            if not step(line) then
                return false
            end
        elseif line == "  slowest" then
            if slowHeading or next(slowest) == nil then
                return false
            end
            slowHeading = true
        elseif slowHeading then
            local name, elapsed = line:match("^    (%S+) +(%S+)$")
            if not name or not measured(elapsed, slowest[name]) then
                return false
            end
            slowest[name], slowRows = nil, slowRows + 1
        else
            if line:sub(1, 2) ~= "  " then
                return false
            end
            for part in (line:sub(3) .. "  "):gmatch("(.-)  ") do
                local name, elapsed = part:match("^(.-) (%S+)$")
                if not name or not measured(elapsed, phases[name]) then
                    return false
                end
            end
        end
    end

    return summary and (not slowHeading or slowRows > 0 and next(slowest) == nil)
end

function M.compilerselfbuild(printed)
    local okay, accepted = pcall(accepts, printed)
    return okay and accepted == true
end

return M
