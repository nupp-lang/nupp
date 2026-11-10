local json = require("serde.json")
local diagnosticSchema = require("nupp.tools.cli.report").DIAGNOSTICS
local M = {}

-- Use the CLI's own diagnostic schema, including nested fixes and locations.
local function matches(value, schema)
    local kind = schema.type
    if kind == "array" or kind == "object" then
        if type(value) ~= "table" then
            return false
        end
    elseif kind == "integer" then
        if type(value) ~= "number" or value % 1 ~= 0 then
            return false
        end
    elseif kind and type(value) ~= kind then
        return false
    end
    if schema.enum then
        local found = false
        for _, option in ipairs(schema.enum) do
            found = found or value == option
        end
        if not found then
            return false
        end
    end
    if kind == "array" then
        for index, item in pairs(value) do
            if type(index) ~= "number"
                or index % 1 ~= 0
                or index < 1
                or index > #value
                or not matches(item, schema.items)
            then
                return false
            end
        end
    elseif kind == "object" then
        for _, name in ipairs(schema.required or {}) do
            if value[name] == nil then
                return false
            end
        end
        for name, child in pairs(schema.properties or {}) do
            if value[name] ~= nil and not matches(value[name], child) then
                return false
            end
        end
    end

    return true
end

local function diagnosticsValid(diagnostics)
    if not matches(diagnostics, diagnosticSchema) then
        return false
    end
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity == "error" then
            return false
        end
    end

    return true
end

-- store.writeFailure prefixes the path/reason; native persist.save_plain and
-- plaincodec.encode refuse executable type-function cache payloads safely.
local CACHE_REASONS = {
    ["plain data must contain one non-executable root"] = true,
    ["runtime error: plain data must contain one non-executable root"] = true,
    ["plain data cannot contain a function"] = true,
    ["runtime error: plain data cannot contain a function"] = true,
}

local function cacheWarning(line)
    local path, reason = line:match("^nupp: cannot save compiler cache (.+/cache/type%-functions%.buf): (.+)$")
    if path and (path:sub(1, 1) == "/" or path:match("^%a:/")) and CACHE_REASONS[reason] then
        return {path = path, reason = reason, text = line}
    end

    return nil
end

function M.cacheWarnings(printed)
    local warnings = {}
    for line in printed:gsub("\r\n", "\n"):gmatch("[^\n]+") do
        local warning = cacheWarning(line)
        if warning then
            warnings[#warnings + 1] = warning
        end
    end

    return warnings
end

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

-- Success output retains non-error diagnostics and recognized cache warnings;
-- every other line must be the fixture's marks or the reporter's progress.
local function accepts(printed)
    printed = printed:gsub("\r\n", "\n")
    if printed:sub(-1) ~= "\n" then
        return false
    end
    local lines = {}
    for line in printed:gmatch("(.-)\n") do
        -- Kept in the original output, exposed by cacheWarnings, and counted
        -- in the milestone receipt instead of implying an incorrect image.
        if not cacheWarning(line) then
            lines[#lines + 1] = line
        end
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
        or not diagnosticsValid(report.diagnostics)
        or type(report.timing) ~= "table"
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
    for index = 2, #lines - 1 do
        local line = lines[index]
        local took, actualCounts = line:match("^built dist in (%S+): (.+)$")
        if index == reportAt then
            -- Retained in the complete output and the driver's warning receipt.
        elseif index > reportAt then
            return false
        elseif took then
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
