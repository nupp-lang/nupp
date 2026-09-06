-- The repository's own Nupp scripts type-check.
--
-- `scripts/*.nupp` is run by CI through `nupp run`, which refuses a file that does
-- not check. Nothing else asks about them: they are outside the manifest's include
-- roots, so `nupp check` with nothing named does not reach them and neither does
-- `fmttreetest`, which takes its list from the same place.
--
-- That gap has cost a release. `scripts/release.nupp` imports a module internal to
-- the `nupp` namespace, the commit that made that an error changed nothing here,
-- and the first thing to notice was the tag: every packaging job failed on a script
-- no suite had ever compiled.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local pwd = assert(io.popen("pwd"))
    HERE = pwd:read("*l") .. "/" .. HERE
    pwd:close()
end
local ROOT = assert(HERE:match("^(.*)/[^/]+$"), "tests directory has no parent")
local NUPP = ROOT .. "/bin/nupp"

local M = {}

function M.everyRepositoryScriptChecks()
    local listing = assert(io.popen(("git -C '%s' ls-files 'scripts/*.nupp'"):format(ROOT)))
    local scripts = {}
    for path in listing:lines() do
        scripts[#scripts + 1] = ("'%s/%s'"):format(ROOT, path)
    end
    listing:close()
    assert(#scripts > 0, "no scripts to check; this suite is asking about nothing")

    local pipe = assert(
        io.popen(("cd '%s' && '%s' check %s 2>&1"):format(ROOT, NUPP, table.concat(scripts, " ")))
    )
    local out = pipe:read("*a")
    pipe:close()
    assert(out == "" or not out:find("error:", 1, true), "a repository script does not check:\n" .. out)
end

return M
