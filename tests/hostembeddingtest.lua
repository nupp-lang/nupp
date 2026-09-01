-- End-to-end gates for the artifacts scripts/toolchain hands to C consumers.

local test = require("assert")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local pipe = assert(io.popen("pwd"))
    HERE = pipe:read("*l") .. "/" .. HERE
    pipe:close()
end
local ROOT = HERE .. "/.."
local FEATURES = "lpeg,native-files,native-net,native-process,native-tls,workers"

local M = {}

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function run(command)
    local pipe = assert(io.popen(command .. " 2>&1; printf '\n__status__:%s' $?"))
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__status__:(%d+)%s*$"))

    return status, output:gsub("\n__status__:%d+%s*$", "")
end

local function write(path, bytes)
    local file = assert(io.open(path, "wb"))
    file:write(bytes)
    file:close()
end

local function temporary()
    local path = os.tmpname()
    os.remove(path)
    assert(os.execute("mkdir -p " .. quote(path)) == 0)
    return path
end

local cachedSdk
local function sdk()
    if cachedSdk then
        return cachedSdk
    end
    local status, output = run(("cd %s && ./scripts/toolchain host-library %s"):format(quote(ROOT), FEATURES))
    if status ~= 0 then
        test.skip("the Rust embedding SDK could not be built: " .. output)
    end
    cachedSdk = assert(output:match("([^\r\n]+)%s*$"), "toolchain named no SDK")

    return cachedSdk
end

local function fixture(directory)
    local component = directory .. "/fixture.nuppc"
    write(
        component,
        [[-- NUPP-COMPONENT 1
return {
  format = 1,
  hostAbi = 1,
  install = function()
    return {
      exports = {["game.answer"] = function(value) return value + 1 end},
      start = function() end,
    }
  end,
}
]]
    )

    return component
end

local function compiler()
    return os.getenv("NUPP_CC") or "cc"
end

local function platformLibraries()
    if jit.os == "OSX" then
        return "-lm -lpthread -framework CoreFoundation -framework Security"
    elseif jit.os == "Windows" then
        return table.concat(
            {
                "-lpthread",
                "-lpsapi",
                "-luser32",
                "-ladvapi32",
                "-liphlpapi",
                "-luserenv",
                "-lws2_32",
                "-ldbghelp",
                "-lole32",
                "-lshell32",
                "-lbcrypt",
                "-lcrypt32",
            },
            " "
        )
    end

    return "-lm -lpthread -ldl"
end

function M.staticSdkLinksAndRunsFromC()
    local directory, library = temporary(), sdk()
    local executable = directory .. "/embed"
    if jit.os == "Windows" then
        executable = executable .. ".exe"
    end
    local status, output = run(
        (
            "%s -std=c11 -I%s %s %s %s -o %s"
        ):format(
            quote(compiler()),
            quote(library),
            quote(ROOT .. "/host/examples/embed.c"),
            quote(library .. "/libnupp.a"),
            platformLibraries(),
            quote(executable)
        )
    )
    assert(status == 0, output)
    status, output = run(quote(executable) .. " " .. quote(fixture(directory)))
    assert(status == 0, output)
    assert(output:find("game.answer(41) = 42", 1, true), output)
end

function M.dynamicSdkLinksAndRunsFromC()
    local directory, library = temporary(), sdk()
    local executable = directory .. "/embed-dynamic"
    local link, environment
    if jit.os == "Windows" then
        executable = executable .. ".exe"
        link = quote(library .. "/libnupp.dll.a")
        environment = "PATH=" .. quote(library) .. ':"$PATH" '
    else
        link = "-L" .. quote(library) .. " -lnupp -Wl,-rpath," .. quote(library)
        environment = ""
    end
    local status, output = run(
        (
            "%s -std=c11 -I%s %s %s -o %s"
        ):format(quote(compiler()), quote(library), quote(ROOT .. "/host/examples/embed.c"), link, quote(executable))
    )
    assert(status == 0, output)
    status, output = run(environment .. quote(executable) .. " " .. quote(fixture(directory)))
    assert(status == 0, output)
    assert(output:find("game.answer(41) = 42", 1, true), output)
    if jit.os == "OSX" then
        status, output = run("otool -L " .. quote(library .. "/libnupp.dylib"))
        assert(status == 0, output)
        assert(
            not output:lower():find("luajit", 1, true),
            "the staged embedding library retains a LuaJIT cache dependency:\n" .. output
        )
    end
end

function M.staticApplicationHostLinksAndRuns()
    local directory = temporary()
    local executable = directory .. "/nupp"
    if jit.os == "Windows" then
        executable = executable .. ".exe"
    end
    local status, output = run(
        ("cd %s && ./scripts/toolchain host-link %s %s --"):format(quote(ROOT), FEATURES, quote(executable))
    )
    assert(status == 0, output)
    local source = directory .. "/fixture.lua"
    write(
        source,
        [[
assert(__nuppHost.hostFeatures.lpeg)
assert(__nuppHost.hostFeatures["native-net"])
assert(require("lpeg").P("x"):match("x") == 2)
]]
    )
    status, output = run(quote(executable) .. " " .. quote(source))
    assert(status == 0, output)
end

return M
