-- The native interpreter core end to end: the handler sources lowered and
-- compiled into an object by `scripts/vm-cli runtime`, then the runtime's
-- native contract tests run against that object. Slow: it builds the glue and
-- the runtime crate's tests with the object linked.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."

local M = {}

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function capture(command)
    local pipe = assert(io.popen(("cd %s && %s 2>&1; echo __exit__:$?"):format(quote(ROOT), command)))
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__exit__:(%d+)%s*$"))

    return status, (output:gsub("__exit__:%d+%s*$", ""))
end

local function read(path)
    local file = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = file:read("*a")
    file:close()
    return text
end

function M.theHandlerSourcesBuildIntoOneObjectAndPassTheContractTests()
    local status, output = capture("python3 scripts/vm-cli runtime")
    assert(status == 0, "scripts/vm-cli runtime failed: " .. output:sub(-6000))
    local object = assert(output:match("([^\r\n]+%.o)%s*$"), "vm-cli runtime named no object: " .. output:sub(-2000))
    local sidecar = read(object .. ".rs")
    assert(sidecar:find("assert!(Code::IAdd as u8 ==", 1, true), "the sidecar names no handlers")
    status, output = capture(
        (
            "NUPP_NATIVE_RUNTIME_OBJECT=%s CARGO_TARGET_DIR=build/rust/target cargo test --locked --release "
            .. "-p nupp-vm --features aot,native-runtime -j 4 --lib"
        ):format(quote(object))
    )
    assert(status == 0, "the native contract tests failed: " .. output:sub(-8000))
    local passed = tonumber(output:match("test result: ok%. (%d+) passed"))
    assert(passed and passed >= 18, "fewer native contract tests ran than expected: " .. output:sub(-3000))
end

return M
