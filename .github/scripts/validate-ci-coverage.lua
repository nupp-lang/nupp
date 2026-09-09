-- Hold `.github/ci-coverage.json`, `.github/workflows/compiler.yml`,
-- `.github/scripts/classify-changes.lua` and `tests/groups.lua` to the same
-- account of what CI covers.
--
-- Four files describing one thing is how a step came to run a suite the later
-- broad step ran again, and how a guarantee came to be held by no job at all.
-- Nothing keeps four files agreeing except a check that reads all four, so this
-- runs in the cheap gate before any platform is provisioned.
--
-- Plain Lua 5.1 with no dependencies, for the same reason the classifier is.

local root = (arg and arg[0] or ""):match("^(.*)[/\\]%.github[/\\]") or "."

local function slurp(path)
    local handle = assert(io.open(root .. "/" .. path, "rb"), "cannot open " .. path)
    local text = handle:read("*a")
    handle:close()

    return text
end

-- A JSON reader for the subset this repository's own data files use: objects,
-- arrays, strings, numbers, and the three literals. Deliberately strict, so a
-- malformed map is a parse error rather than a silently truncated document.
local function decode(text)
    local position = 1

    local function fail(what)
        error(("%s at byte %d"):format(what, position), 0)
    end

    local function skip()
        local _, stop = text:find("^[ \t\r\n]*", position)
        position = stop + 1
    end

    local value

    local function string_()
        position = position + 1
        local parts = {}
        while true do
            local character = text:sub(position, position)
            if character == "" then
                fail("unterminated string")
            elseif character == '"' then
                position = position + 1

                return table.concat(parts)
            elseif character == "\\" then
                local escape = text:sub(position + 1, position + 1)
                local simple = {
                    ['"'] = '"',
                    ["\\"] = "\\",
                    ["/"] = "/",
                    b = "\b",
                    f = "\f",
                    n = "\n",
                    r = "\r",
                    t = "\t",
                }
                if simple[escape] then
                    parts[#parts + 1] = simple[escape]
                    position = position + 2
                elseif escape == "u" then
                    -- No file here needs one, and accepting it without
                    -- implementing it would be the kind of quiet wrong answer
                    -- this whole check exists to prevent.
                    fail("\\u escapes are not supported")
                else
                    fail("unknown escape")
                end
            else
                parts[#parts + 1] = character
                position = position + 1
            end
        end
    end

    function value()
        skip()
        local character = text:sub(position, position)
        if character == "{" then
            position = position + 1
            local object = {}
            skip()
            if text:sub(position, position) == "}" then
                position = position + 1

                return object
            end
            while true do
                skip()
                if text:sub(position, position) ~= '"' then
                    fail("expected a key")
                end
                local key = string_()
                skip()
                if text:sub(position, position) ~= ":" then
                    fail("expected ':'")
                end
                position = position + 1
                object[key] = value()
                skip()
                local separator = text:sub(position, position)
                position = position + 1
                if separator == "}" then
                    return object
                elseif separator ~= "," then
                    fail("expected ',' or '}'")
                end
            end
        elseif character == "[" then
            position = position + 1
            local array = {}
            skip()
            if text:sub(position, position) == "]" then
                position = position + 1

                return array
            end
            while true do
                array[#array + 1] = value()
                skip()
                local separator = text:sub(position, position)
                position = position + 1
                if separator == "]" then
                    return array
                elseif separator ~= "," then
                    fail("expected ',' or ']'")
                end
            end
        elseif character == '"' then
            return string_()
        elseif text:find("^true", position) then
            position = position + 4

            return true
        elseif text:find("^false", position) then
            position = position + 5

            return false
        elseif text:find("^null", position) then
            position = position + 4

            return nil
        end

        local number = text:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", position)
        if number and number ~= "" then
            position = position + #number

            return tonumber(number)
        end
        fail("unexpected character " .. ("%q"):format(character))
    end

    local decoded = value()
    skip()
    if position <= #text then
        fail("trailing content")
    end

    return decoded
end

local problems = {}
local function require_(condition, message)
    if not condition then
        problems[#problems + 1] = message
    end

    return condition
end

local map = decode(slurp(".github/ci-coverage.json"))
local workflowText = slurp(map.workflow)

-- The workflow's shape is fixed by `nupp fmt`-adjacent conventions and by this
-- repository's own YAML style: a job id is two spaces in under `jobs:`, and a
-- step name is `      - name: `. Reading those two lines is all this needs, and
-- it fails loudly rather than approximately if the shape ever changes.
local workflowJobs, jobOrder = {}, {}
local stepsByJob = {}
do
    local inJobs, current = false, nil
    for line in (workflowText .. "\n"):gmatch("(.-)\n") do
        if line:match("^jobs:%s*$") then
            inJobs = true
        elseif inJobs then
            local id = line:match("^  ([%w%-_]+):%s*$")
            if id then
                current = id
                workflowJobs[id] = true
                jobOrder[#jobOrder + 1] = id
                stepsByJob[id] = {}
            elseif current then
                local name = line:match("^      %- name: (.+)$")
                if name then
                    stepsByJob[current][name] = true
                end
            end
        end
    end
end
require_(#jobOrder > 0, "no jobs were found in " .. map.workflow)

for id in pairs(map.jobs) do
    require_(workflowJobs[id], ("ci-coverage.json describes job %q, which the workflow does not define"):format(id))
end
for _, id in ipairs(jobOrder) do
    require_(map.jobs[id] ~= nil, ("the workflow defines job %q, which ci-coverage.json does not describe"):format(id))
end

for id, job in pairs(map.jobs) do
    for _, step in ipairs(job.steps or {}) do
        require_(
            (stepsByJob[id] or {})[step.name],
            ("ci-coverage.json describes step %q of job %q, which the workflow does not define"):format(step.name, id)
        )
    end
end

-- Every job the classifier can select has to be claimed by a job in this map,
-- and every job in this map has to say what selects it. Otherwise a change
-- selects coverage nothing provides, or a job runs that nothing decided to run,
-- and either way the run is green for a reason nobody chose.
local classifier = dofile(root .. "/.github/scripts/classify-changes.lua")
local selectable = {}
for _, name in ipairs(classifier.jobs) do
    selectable[name] = true
end
local claimed = {}
for id, job in pairs(map.jobs) do
    require_(type(job.selectedBy) == "string", ("job %q does not say what selects it"):format(id))
    for token in tostring(job.selectedBy or ""):gmatch("[^,%s]+") do
        if token ~= "always" then
            require_(
                selectable[token],
                ("job %q says it is selected by %q, which the classifier cannot select"):format(id, token)
            )
            claimed[token] = id
        end
    end
end
for _, name in ipairs(classifier.jobs) do
    require_(claimed[name] ~= nil, ("the classifier can select %q, which no job in this map claims"):format(name))
end

-- Every group a step names must exist. A group renamed in tests/groups.lua and
-- not here would leave a step failing at the point it is finally reached, on
-- whichever platform reaches it first.
local groups = dofile(root .. "/tests/groups.lua")
for id, job in pairs(map.jobs) do
    for _, step in ipairs(job.steps or {}) do
        for _, group in ipairs(step.groups or {}) do
            require_(groups[group] ~= nil, ("step %q of job %q names group %q, which tests/groups.lua does not define"):format(
                step.name,
                id,
                group
            ))
        end
        for _, group in ipairs(((step.excludes or {}).groups) or {}) do
            require_(groups[group] ~= nil, ("step %q of job %q excludes group %q, which tests/groups.lua does not define"):format(
                step.name,
                id,
                group
            ))
        end
    end
end

-- The duplicate-execution check this file exists for. Two steps of one job that
-- run the same group on the same platform are the shape that made a focused
-- gate run again inside the later broad suite.
for id, job in pairs(map.jobs) do
    local seen = {}
    for _, step in ipairs(job.steps or {}) do
        local platforms = step.platforms or job.platforms or {"any"}
        for _, group in ipairs(step.groups or {}) do
            for _, platform in ipairs(platforms) do
                local key = platform .. "/" .. group
                require_(not seen[key], ("job %q runs group %q twice on %s: %q and %q"):format(
                    id,
                    group,
                    platform,
                    seen[key] or "",
                    step.name
                ))
                seen[key] = step.name
            end
        end
    end
end

if #problems > 0 then
    for _, problem in ipairs(problems) do
        io.stderr:write("ci-coverage: ", problem, "\n")
    end
    os.exit(1)
end

io.stdout:write(("ci-coverage: %d jobs, all named steps present\n"):format(#jobOrder))
