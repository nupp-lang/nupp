-- The platform entries the classifier selected, as one matrix.
--
-- Three near-identical two-hundred-line jobs with an `if` on each is the other
-- way to do this, and it is the way that drifts: a step added to one and not
-- the others is invisible until the platform it was left off of stops being
-- tested. One job whose matrix is computed keeps a single copy of the steps and
-- makes the selection reviewable as data.
--
-- Writes `integration=<json>` to `$GITHUB_OUTPUT`, and the same document to
-- standard output so a run's log says what it decided.

local platforms = {
    {
        variable = "SELECTED_LINUX",
        entry = {name = "Linux x64", os = "ubuntu-24.04", timeout = 85, artifact = "linux-x64"},
    },
    {
        variable = "SELECTED_MACOS",
        entry = {name = "macOS arm64", os = "macos-15", timeout = 110, artifact = "macos-arm64"},
    },
    {
        variable = "SELECTED_WINDOWS",
        entry = {name = "Windows x64", os = "windows-2022", timeout = 95, artifact = "windows-x64"},
    },
}

local selected = {}
for _, platform in ipairs(platforms) do
    if os.getenv(platform.variable) == "true" then
        selected[#selected + 1] = platform.entry
    end
end

local encoded = {}
for index, entry in ipairs(selected) do
    encoded[index] = ('{"name":"%s","os":"%s","timeout":%d,"artifact":"%s"}'):format(
        entry.name,
        entry.os,
        entry.timeout,
        entry.artifact
    )
end
local document = "[" .. table.concat(encoded, ",") .. "]"

io.stdout:write(document, "\n")
local output = os.getenv("GITHUB_OUTPUT")
if output then
    local handle = assert(io.open(output, "a"))
    handle:write("integration=", document, "\n")
    handle:close()
end
