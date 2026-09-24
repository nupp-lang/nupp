-- Adapt and materialize the verified compiler without running its entry.
local source, runtime, destination, stamp = assert(arg[1]), assert(arg[2]), assert(arg[3]), assert(arg[4])
local identity = jit.version .. '/' .. jit.os .. '/' .. jit.arch
local prior = io.open(stamp, 'rb')
if prior then
    local recorded = prior:read('*a')
    prior:close()
    if recorded == identity then
        return
    end
end

local stopped = {}
local modules = {}
local environment = setmetatable({package = {preload = modules}}, {
    __index = function()
        error(stopped, 0)
    end,
})
local input = assert(io.open(source, 'rb'))
local stage0 = assert(input:read('*a'))
assert(input:close())

-- The pinned compiler predates the native ABI's permanent names. Adapt the
-- compiler modules materialized for this checkout while leaving the verified
-- release artifact itself byte-for-byte intact.
stage0 = stage0:gsub('NUPP_NATIVE_V2', 'NUPP_NATIVE')
stage0 = stage0:gsub('NuppNativeV2', 'NuppNative')
stage0 = stage0:gsub('nuppNativeV2', 'nuppNative')
stage0 = stage0:gsub('nupp_native_v2', 'nupp_native')
stage0 = stage0:gsub('native_runtime_v2', 'native_runtime')
stage0 = stage0:gsub('native_v2', 'native')

local runtimeOutput = assert(io.open(runtime, 'wb'))
assert(runtimeOutput:write(stage0))
assert(runtimeOutput:close())

local chunk = assert(loadstring(stage0, '@' .. runtime))
local ok, reason = pcall(setfenv(chunk, environment))
assert(not ok and reason == stopped, 'compiler artifact has no isolated entry boundary')
assert(
    type(modules['nupp.compiler.build.native']) == 'function'
        or type(modules['nupp.tools.build.native']) == 'function',
    'compiler artifact has no runtime module catalog'
)

local windows = package.config:sub(1, 1) == '\\'

local function quote(value)
    if windows then
        return '"' .. value:gsub('/', '\\') .. '"'
    end
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function mkdir(path)
    local command = windows and ('mkdir ' .. quote(path) .. ' >nul 2>nul') or ('mkdir -p ' .. quote(path))
    os.execute(command)
end

local names = {}
for name in pairs(modules) do
    names[#names + 1] = name
end
table.sort(names)
for _, name in ipairs(names) do
    assert(name:match('^[%w_.%-]+$') and not name:find('..', 1, true), 'invalid compiler module name')
    local loader = modules[name]
    assert(debug.getupvalue(loader, 1) == nil, 'compiler module captures an outer value: ' .. name)
    local path = destination .. '/build/' .. name:gsub('%.', '/') .. '.lua'
    mkdir(assert(path:match('^(.*)/[^/]+$')))
    local output = assert(io.open(path, 'wb'))
    assert(output:write(string.dump(loader)))
    assert(output:close())
end
local output = assert(io.open(stamp, 'wb'))
assert(output:write(identity))
assert(output:close())
