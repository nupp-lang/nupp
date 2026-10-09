-- The `nupp.host` channel's contract.
--
-- The browser half runs end to end under Node: `hostchannel/browser.test.mjs`
-- answers frames with the real page dispatcher while `hostchannel/guest.lua`
-- runs the application the way the guest bridge does, with this process's
-- compiled runtime on its path.

local check = require("assert")

local M = {}

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE:match("^(.*)[/\\]tests$") or (HERE .. "/..")

local function shellQuote(text)
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function capture(command)
    local pipe = assert(io.popen(command .. " 2>&1"))
    local output = pipe:read("*a")
    local closed, _, status = pipe:close()
    return output, closed == true or status == 0
end

local function requireNode()
    local version = capture("node --version")
    if not version:match("^v%d+") then
        check.skip("node is not installed")
    end
end

local function luajit()
    local found = capture("command -v luajit"):match("([^\n]+)%s*$")
    check.assert(found ~= nil and found ~= "", "no luajit on PATH for the guest")
    return found
end

local function passesNodeSuite(label, file)
    requireNode()
    local environment = table.concat({
        "NUPP_ROOT=" .. shellQuote(ROOT),
        "NUPP_LUAJIT=" .. shellQuote(luajit()),
        "LUA_PATH=" .. shellQuote(package.path),
        "LUA_CPATH=" .. shellQuote(package.cpath),
    }, " ")
    local output, exited = capture(
        environment .. " node --test --test-reporter=tap " .. shellQuote(HERE .. "/" .. file)
    )
    local passed = tonumber(output:match("\n# pass (%d+)"))
    local failed = tonumber(output:match("\n# fail (%d+)"))
    check.assert(passed ~= nil and failed ~= nil, "node printed no test summary:\n" .. output)
    check.equal(failed, 0, label .. " failed:\n" .. output)
    check.assert(passed > 0, label .. " ran no test")
    check.assert(exited, "node exited unsuccessfully:\n" .. output)
end

function M.theBrowserChannelKeepsItsContract()
    passesNodeSuite("the browser host channel's contract", "hostchannel/browser.test.mjs")
end

return M
