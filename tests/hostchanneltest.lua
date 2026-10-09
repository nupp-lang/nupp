-- The `nupp.host` channel's contract.
--
-- The browser half runs end to end under Node: `hostchannel/browser.test.mjs`
-- answers frames with the real page dispatcher while `hostchannel/guest.lua`
-- runs the application the way the guest bridge does, with this process's
-- compiled runtime on its path.

local check = require("assert")

local M = {}

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local pipe = assert(io.popen("pwd"))
    HERE = pipe:read("*l") .. "/" .. HERE
    pipe:close()
end
local ROOT = HERE .. "/.."

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

----------------------------------------------------------------------------
-- The embedding half
----------------------------------------------------------------------------

-- The SDK features the hosted runtime needs: time for scope deadlines, and
-- nothing else the scenarios reach.
local SDK_FEATURES = "lpeg"

local function run(command)
    local pipe = assert(io.popen(command .. " 2>&1; printf '\n__status__:%s' $?"))
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__status__:(%d+)%s*$"))
    return status, output:gsub("\n__status__:%d+%s*$", "")
end

local function copy(from, to)
    local source = assert(io.open(from, "rb"))
    local bytes = source:read("*a")
    source:close()
    local target = assert(io.open(to, "wb"))
    target:write(bytes)
    target:close()
end

local native

-- Builds the SDK, the contract component and the driver once per run.
local function nativeDriver()
    if native then
        return native
    end
    if jit.os == "Windows" then
        check.skip("the contract driver uses POSIX clocks")
    end
    local status, output = run(("cd %s && ./scripts/toolchain host-library %s"):format(shellQuote(ROOT), SDK_FEATURES))
    if status ~= 0 then
        check.skip("the Rust embedding SDK could not be built: " .. output)
    end
    local library = assert(output:match("([^\r\n]+)%s*$"), "toolchain named no SDK")
    local directory = os.tmpname()
    os.remove(directory)
    local project = directory .. "/component"
    assert(os.execute(("mkdir -p %s"):format(shellQuote(project .. "/src"))) == 0)
    copy(HERE .. "/hostchannel/component/nupp.lua", project .. "/nupp.lua")
    copy(HERE .. "/hostchannel/component/src/contract.nupp", project .. "/src/contract.nupp")
    status, output = run(("cd %s && %s build"):format(shellQuote(project), shellQuote(ROOT .. "/bin/nupp")))
    check.equal(status, 0, "the contract component did not build:\n" .. output)
    local link = assert(io.open(library .. "/link.json", "rb"))
    local manifest = require("testjson").decode(link:read("*a"))
    link:close()
    local flags = {}
    for _, flag in ipairs(manifest.staticLinkFlags or {}) do
        flags[#flags + 1] = shellQuote(flag)
    end
    local executable = directory .. "/driver"
    status, output = run(
        ("%s -std=c11 -D_POSIX_C_SOURCE=200809L -I%s %s %s %s -lm -o %s"):format(
            shellQuote(os.getenv("NUPP_CC") or "cc"),
            shellQuote(library),
            shellQuote(HERE .. "/hostchannel/driver.c"),
            shellQuote(library .. "/libnupp.a"),
            table.concat(flags, " "),
            shellQuote(executable)
        )
    )
    check.equal(status, 0, "the contract driver did not compile:\n" .. output)
    native = {executable = executable, component = project .. "/build/component.nuppc"}
    return native
end

-- Runs one scenario in the embedded runtime; answers its decoded outcome, the
-- driver's own report and everything it printed.
local function embedded(name, direct)
    local driver = nativeDriver()
    local status, output = run(
        ("%s %s %s %s%s"):format(
            shellQuote(driver.executable),
            shellQuote(driver.component),
            shellQuote(HERE .. "/hostchannel/scenarios.lua"),
            shellQuote(name),
            direct and " direct" or ""
        )
    )
    check.equal(status, 0, name .. " did not run:\n" .. output)
    local line = assert(output:match("(%b{})%s*\ncancels="), name .. " printed no outcome:\n" .. output)
    local outcome = require("testjson").decode(line)
    check.assert(outcome.ok, name .. " failed:\n" .. tostring(outcome.error) .. "\n" .. output)
    local cancels, live = output:match("cancels=(%d+) live=(%d+)")
    return outcome.value, {cancels = tonumber(cancels), live = tonumber(live)}, output
end

function M.embeddedRequestsKeepEveryPosition()
    local value = embedded("arity")
    check.equal(value.echoed.n, 5)
    check.equal(value.echoed.a, 1)
    check.equal(value.echoed.b, nil)
    check.equal(value.echoed.c, "two")
    check.equal(value.echoed.d, true)
    check.equal(value.echoed.e, nil)
    check.equal(value.none, 0)
    check.equal(value.onlyNil, 1)
    check.equal(value.interior.n, 3)
    check.equal(value.interior.b, 2)
end

function M.embeddedRequestsRefuseWhatCannotCross()
    local value = embedded("refusals")
    check.assert(value.nan:find("argument 1 is not a finite number", 1, true), value.nan)
    check.assert(value.infinity:find("argument 2 is not a finite number", 1, true), value.infinity)
    check.assert(value.text:find("argument 1 is a string that is not UTF-8", 1, true), value.text)
    check.assert(value.long:find("argument 1 is a string longer than 64 KiB", 1, true), value.long)
    check.assert(value.table:find("argument 1 is a table, which cannot cross", 1, true), value.table)
    check.assert(value.handler:find("argument 1 is a function, which cannot cross", 1, true), value.handler)
    check.assert(value.reserved:find("reserved for the runtime", 1, true), value.reserved)
    check.assert(value.kind:find("must be dot-separated names", 1, true), value.kind)
    check.assert(value.unknown:find("no host answers test.nobody", 1, true), value.unknown)
    check.assert(value.failed:find("host test.fail failed: failed because why", 1, true), value.failed)
end

function M.embeddedBytesCrossBothWays()
    local value = embedded("bytes")
    for _, name in ipairs({"small", "large", "three", "made", "empty"}) do
        check.equal(value[name], true, name)
    end
end

function M.anEmbedderAnswersLaterFromItsLoop()
    local value = embedded("slowCallBesideADeadline")
    check.equal(value.slow, 4096)
    check.assert(value.firedAfter >= 50 and value.firedAfter < 400, "the deadline fired after " .. value.firedAfter)
end

function M.embeddedLateReleasesWhatItOpened()
    local value, host = embedded("lateReleases")
    check.assert(value.cancelled:find("deadline", 1, true), value.cancelled)
    check.equal(value.live, 0)
    check.equal(host.live, 0)
    check.assert(host.cancels >= 1, "the host heard no cancellation")
end

function M.embeddedLateCannotWait()
    local value, host, output = embedded("lateCannotWait")
    check.equal(value.echoed, "still answering")
    check.equal(value.live, 1)
    check.assert(output:find("late handler failed: .*cannot suspend"), output)
    check.equal(host.live, 1)
end

function M.embeddedManyCallsAllAnswer()
    check.equal(embedded("manySmallCalls").correct, 600)
end

function M.embeddedPostsReachTheirHandlers()
    check.equal(embedded("posts").notes, "1:100,2:100,3:100,4:100,5:100,6:100,7:100,8:100,9:100,10:100")
end

function M.anUnansweredCallWithoutAHandlerIsRefused()
    local value, host = embedded("unansweredWithoutAHandler", true)
    check.assert(value.problem:find("was not answered during the call", 1, true), value.problem)
    check.equal(value.echoed, "answered at once")
    check.equal(host.cancels, 1)
end

function M.anEmbedderAnswerIsCheckedBeforeItIsKept()
    local _, _, output = embedded("posts")
    check.assert(
        output:find("unknown=1 handle=1 nan=1 text=1 reserved=1 malformed=1", 1, true),
        "nupp_host_answer and nupp_host_register accepted what they refuse:\n" .. output
    )
end

return M
