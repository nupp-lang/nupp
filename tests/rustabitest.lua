local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."

local M = {}

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function read(path)
    local file = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = file:read("*a")
    file:close()
    return text
end

function M.publicHeaderLinksAndRunsAgainstTheSelectedCdylib()
    local pipe = assert(io.popen("'" .. ROOT:gsub("'", "'\\''") .. "/scripts/test-rust-abi' 2>&1; echo __exit__:$?"))
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__exit__:(%d+)%s*$"))
    assert(status == 0, output)
end

local function lastLine(command)
    local pipe = assert(io.popen(("cd %s && %s 2>/dev/null"):format(quote(ROOT), command)))
    local line = pipe:read("*a"):match("([^\r\n]+)%s*$")
    pipe:close()
    return line
end

-- A cold checkout runs the pinned stage-zero image on a runtime built from its
-- own sources, so that runtime has to keep loading the pinned image's format
-- until the pin moves past it. Verifying it is the whole of what loading asks:
-- every function decodes and passes the checks a run would make.
function M.theRuntimeLoadsThePinnedStageZeroImage()
    local image = lastLine("./scripts/toolchain stage0-image")
    assert(image, "no stage-zero image; run scripts/toolchain stage0-image")
    local runtime = lastLine("./scripts/toolchain vm-runtime ''")
    assert(runtime, "no VM runtime; run scripts/toolchain vm-runtime ''")
    local pipe = assert(io.popen(("%s verify %s 2>&1; echo __exit__:$?"):format(quote(runtime), quote(image))))
    local output = pipe:read("*a")
    pipe:close()
    assert(output:match("__exit__:0%s*$"), "this runtime refuses the pinned stage-zero image: " .. output)
end

-- The pinned stage-zero image binds this checkout's freshly built provider by
-- name, so the provider may only grow while it is pinned: every provider symbol
-- the image names is still declared. A deleted one breaks a cold build the
-- moment the image reaches it, and nothing but the image's own strings says
-- whether it can.
function M.theProviderKeepsWhatThePinnedStageZeroNames()
    local image = lastLine("./scripts/toolchain stage0-image")
    assert(image, "no stage-zero image; run scripts/toolchain stage0-image")
    local bytes = read(image)
    local header = read(ROOT .. "/native/include/nupp_native.h")
    local declared = {}
    for name in header:gmatch("NUPP_NATIVE_EXPORT[^;(]-([%w_]+)%s*%(") do
        declared[name] = true
    end
    local missing, seen = {}, {}
    -- A whole word, and not a doc comment's `nuppNativeGpu*` family: the image
    -- carries the compiler's resources as well as its code.
    for name, after in bytes:gmatch("%f[%w_](nuppNative[%w_]+)(.?)") do
        if after ~= "*" and not seen[name] then
            seen[name] = true
            if not declared[name] then
                missing[#missing + 1] = name
            end
        end
    end
    table.sort(missing)
    assert(next(seen), "the image names no provider symbol, so this check reads the wrong bytes")
    assert(#missing == 0, "the pinned stage zero names provider symbols the header lost: " .. table.concat(missing, ", "))
end

return M
