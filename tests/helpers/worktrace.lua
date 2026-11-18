-- Records the compiler work a test run repeats.
--
-- Installed by the runner when NUPP_TEST_WORKTRACE names a directory. Each
-- process appends one JSON line per call to the entry points suites reach --
-- parse, check, environment construction, lowering, graph compilation, and
-- the commands a case starts -- with a digest of what the call was given, its
-- wall and CPU time, and the case it ran in. Two lines with the same kind and
-- key are the same work done twice. Nothing reads these during the run.

local M = {}

local unpack = table.unpack or unpack

local function pack(...)
    return {n = select("#", ...), ...}
end

local out = nil
local hash = nil
local suiteName, caseName = "", ""
local depth = 0
local serial = 0
local processTag = ""
local textDigests = setmetatable({}, {__mode = "k"})

local function digest(text)
    return hash.digest(text)
end

local function wall()
    local clock = rawget(os, "monotonic")
    if clock then
        return clock()
    end

    return os.time() * 1000
end

local function escape(text)
    return (tostring(text):gsub('[%c"\\]', function(c)
        return string.format("\\u%04x", c:byte())
    end))
end

-- A deterministic rendering of an options table: keys sorted, tables nested,
-- functions and userdata by type, cycles cut.
local function render(value, seen, budget)
    local kind = type(value)
    if kind == "string" then
        return "s" .. #value .. ":" .. value
    elseif kind == "number" or kind == "boolean" or kind == "nil" then
        return tostring(value)
    elseif kind ~= "table" then
        return kind
    end
    seen = seen or {}
    budget = budget or {left = 4000}
    if seen[value] then
        return "<cycle>"
    end
    budget.left = budget.left - 1
    if budget.left < 0 then
        return "<deep>"
    end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = tostring(key) .. "=" .. render(value[key], seen, budget)
    end
    seen[value] = nil

    return "{" .. table.concat(parts, ",") .. "}"
end

local function readFile(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local text = file:read("*a")
    file:close()

    return text
end

local function emit(kind, key, label, began, cpu, extra)
    if not out then
        return
    end
    serial = serial + 1
    out:write(
        (
            '{"p":"%s","n":%d,"suite":"%s","case":"%s","kind":"%s","key":"%s","label":"%s","depth":%d,"wall":%.3f,"cpu":%.3f%s}\n'
        ):format(
            processTag,
            serial,
            escape(suiteName),
            escape(caseName),
            kind,
            key,
            escape(label),
            depth,
            wall() - began,
            (os.clock() - cpu) * 1000,
            extra or ""
        )
    )
    out:flush()
end

-- Wraps `module[name]` so each call is timed and recorded under `keyOf(...)`.
local function wrap(module, name, kind, keyOf)
    local original = module[name]
    if type(original) ~= "function" then
        return
    end
    module[name] = function(...)
        local ok, key, label = pcall(keyOf, ...)
        if not ok then
            key, label = "unkeyed", tostring(key)
        end
        local began, cpu = wall(), os.clock()
        depth = depth + 1
        local results = pack(pcall(original, ...))
        depth = depth - 1
        emit(kind, key, label or "", began, cpu)
        if not results[1] then
            error(results[2], 0)
        end

        return unpack(results, 2, results.n)
    end
end

local function tryRequire(name)
    local ok, module = pcall(require, name)
    return ok and type(module) == "table" and module or nil
end

-- Temporary names differ on every call; the work does not.
local function normalized(command)
    return (
        command:gsub("/private/var/folders/[^%s'\"]+", "<tmp>")
            :gsub("/var/folders/[^%s'\"]+", "<tmp>")
            :gsub("/tmp/lua_[%w_]+[^%s'\"]*", "<tmp>")
            :gsub("/tmp/[%w_.-]+", "<tmp>")
    )
end

local rawPopen = io.popen

-- The content of the project a command runs in, so two builds of identical
-- projects in different temporary directories share a key and two builds of
-- different projects in one directory do not.
local function treeDigest(directory)
    if not directory or directory == "" then
        return ""
    end
    local pipe = rawPopen(
        "cd '"
        .. directory
        .. "' 2>/dev/null && find . -type f ! -path './build/*' ! -path './.nupp*' ! -path './.git/*' 2>/dev/null"
        .. " | LC_ALL=C sort | xargs shasum 2>/dev/null | shasum 2>/dev/null"
    )
    if not pipe then
        return ""
    end
    local text = pipe:read("*a") or ""
    pipe:close()

    return text:match("^(%x+)") or ""
end

local function commandDirectory(command)
    return command:match("^%s*cd%s+'([^']+)'")
        or command:match('^%s*cd%s+"([^"]+)"')
        or command:match("^%s*cd%s+([^%s;&]+)")
end

function M.case(suite, case)
    suiteName, caseName = suite or "", case or ""
end

function M.install(directory)
    hash = require("nupp.compiler.hash")
    local pid = "?"
    local okPid, hostpid = pcall(require, "nupp.compiler.hostpid")
    if okPid then
        pid = tostring(hostpid.get())
    end
    processTag = pid .. "-" .. tostring(os.time())
    os.execute("mkdir -p '" .. directory .. "'")
    out = io.open(directory .. "/trace-" .. processTag .. "-" .. tostring({}):gsub("%W", "") .. ".jsonl", "ab")
    if not out then
        return
    end

    local parser = tryRequire("nupp.compiler.syntax.parser")
    if parser then
        local original = parser.parse
        parser.parse = function(text, path, ...)
            local key = type(text) == "string" and digest(text) or "?"
            local began, cpu = wall(), os.clock()
            depth = depth + 1
            local results = pack(pcall(original, text, path, ...))
            depth = depth - 1
            emit("parse", key, tostring(path), began, cpu)
            if not results[1] then
                error(results[2], 0)
            end
            if type(results[2]) == "table" then
                textDigests[results[2]] = key
            end

            return unpack(results, 2, results.n)
        end
    end

    local function envKey(env)
        if type(env) ~= "table" then
            return "noenv"
        end
        return digest(
            render({
                root = env.rootDir,
                config = env.config,
                cache = env.cacheDisabled,
                target = env.layoutTarget
            })
        )
    end

    local check = tryRequire("nupp.compiler.check")
    if check then
        wrap(check, "check", "check", function(parsed, path, env, opts)
            local source = textDigests[parsed] or "?"
            return digest(
                source .. "\0" .. tostring(path) .. "\0" .. envKey(env) .. "\0" .. render(opts)
            ), tostring(path)
        end)
    end

    local env = tryRequire("nupp.compiler.project.env")
    if env then
        wrap(env, "new", "env", function(root, opts)
            return digest(render({root = root, opts = opts})), tostring(root)
        end)
        wrap(env, "resolveModule", "resolve", function(self, name)
            return digest(tostring(name) .. "\0" .. envKey(self)), tostring(name)
        end)
    end

    local lower = tryRequire("nupp.compiler.clif.lower")
    if lower then
        local function pathsKey(root, paths, options)
            local parts = {tostring(root), render(options)}
            local names = {}
            for _, path in ipairs(paths or {}) do
                parts[#parts + 1] = path .. "\0" .. (readFile(path) or "?")
                names[#names + 1] = tostring(path):match("[^/]+$")
            end

            return digest(table.concat(parts, "\0")), table.concat(names, ",")
        end

        wrap(lower, "compile", "lower", pathsKey)
        wrap(lower, "compileRuntime", "lowerRuntime", function(root, layouts)
            return digest(tostring(root) .. "\0" .. (readFile(layouts) or "?")), "runtime"
        end)
    end

    local nativegraph = tryRequire("nupp.compiler.vm.nativegraph")
    if nativegraph then
        wrap(nativegraph, "compile", "nativegraph", function(fn, options)
            local scope = type(fn) == "table" and fn.scope or {}
            local label = tostring(scope.name) .. "." .. tostring(fn and fn.name)
            return digest(
                label .. "\0" .. render({
                    fn and fn.nativeABI,
                    fn and fn.paramKinds,
                    fn and fn.resultKind
                })
            ), label
        end)
    end

    local process = tryRequire("nupp.compiler.process")
    if process then
        wrap(process, "captureIsolated", "spawn", function(argv, opts)
            local text = normalized(table.concat(argv, " ") .. " @" .. tostring(opts and opts.cwd))
            return digest(text .. "\0" .. treeDigest(opts and opts.cwd)), text:sub(1, 400)
        end)
    end

    local originalPopen = io.popen
    io.popen = function(command, mode, ...)
        local key = digest(normalized(tostring(command)) .. "\0" .. treeDigest(commandDirectory(tostring(command))))
        local began, cpu = wall(), os.clock()
        local handle, problem = originalPopen(command, mode, ...)
        if not handle then
            return handle, problem
        end
        local label = normalized(tostring(command)):sub(1, 400)
        local closed = false
        local proxy = {}

        local function finish()
            if not closed then
                closed = true
                emit("popen", key, label, began, cpu)
            end
        end

        setmetatable(proxy, {
            __index = function(_, field)
                local value = handle[field]
                if type(value) ~= "function" then
                    return value
                end
                if field == "close" then
                    return function(_, ...)
                        local results = pack(handle:close(...))
                        finish()
                        return unpack(results, 1, results.n)
                    end
                end

                return function(self, ...)
                    if self == proxy then
                        return value(handle, ...)
                    end
                    return value(self, ...)
                end
            end,
            __gc = finish,
            __close = finish,
        })

        return proxy
    end

    local originalExecute = os.execute
    os.execute = function(command, ...)
        if command == nil then
            return originalExecute(command, ...)
        end
        local text = normalized(tostring(command))
        local trivial = text:match("^%s*mkdir ")
            or text:match("^%s*rm ")
            or text:match("^%s*kill ")
            or text:match("^%s*test ")
        local key = not trivial and digest(text .. "\0" .. treeDigest(commandDirectory(tostring(command)))) or nil
        local began, cpu = wall(), os.clock()
        local results = pack(originalExecute(command, ...))
        if key then
            emit("execute", key, text:sub(1, 400), began, cpu)
        end

        return unpack(results, 1, results.n)
    end
end

return M
