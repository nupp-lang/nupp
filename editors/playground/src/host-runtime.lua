--[[
What the browser Lua VM needs before bootstrap/nupp.lua will load and run: a
handful of LuaJIT-only pieces the compiler's own implementation leans on, not
just the code it generates for a checked program.

`bit` and `string.buffer` are real, working implementations — the checker's
C-declaration decoder and the project-index cache actually call them.  `ffi`
is a stub that fails loudly rather than silently-wrong: nothing here can offer
real C-ABI introspection, so code that declares or imports real C types is
the one thing this playground cannot check. `io.open`/`io.popen` are wired to
"not found" rather than left absent, so the project-index cache and manifest
lookups take the same "nothing here yet" path they take on a first-ever
build, per the project's own cache design: corrupt or missing costs one slow
recompute and changes no answer.
]]

arg = {}
os.exit = function(...) return ... end

-- Lua 5.1 and LuaJIT's `loadstring`, which 5.2 folded into `load` and 5.3 --
-- fengari's dialect -- does not define at all. nupp.optimize's constant folder
-- reaches for it to evaluate a numeric literal the lexer already accepted, so
-- without this the optimizer is not merely absent in the browser: turning it
-- on fails the compile with "attempt to call a nil value".
loadstring = loadstring or load

-- fengari only registers the "io" global when it thinks it's running under
-- Node (see the `typeof process` guard build.mjs folds away for the
-- browser), so there is no table here to patch yet.
io = io or {}

local realOpen = io.open
io.open = function(path, mode)
    if realOpen then
        local ok, f, err = pcall(realOpen, path, mode)
        if ok then return f, err end
    end
    return nil, (path or "?") .. ": no filesystem in the browser playground"
end
io.popen = function() return nil end

os.rename = function() return nil, "no filesystem in the browser playground" end
os.remove = function() return nil, "no filesystem in the browser playground" end

-- LuaJIT's "bit" library, reimplemented on Lua 5.3's native 64-bit bitwise
-- operators, wrapped to 32 bits the way LuaJIT's bit.* always did.
do
    local MASK = 0xFFFFFFFF
    local function wrap(n)
        n = math.floor(n) & MASK
        if n >= 0x80000000 then n = n - 0x100000000 end
        return n
    end
    local bitlib = {}
    function bitlib.tobit(n) return wrap(n | 0) end
    function bitlib.band(a, b, ...)
        a = wrap(a)
        local r = a & (b ~= nil and wrap(b) or -1)
        for _, v in ipairs({...}) do r = r & wrap(v) end
        return wrap(r)
    end
    function bitlib.bor(a, b, ...)
        a = wrap(a)
        local r = a | (b ~= nil and wrap(b) or 0)
        for _, v in ipairs({...}) do r = r | wrap(v) end
        return wrap(r)
    end
    function bitlib.bxor(a, b, ...)
        a = wrap(a)
        local r = a ~ (b ~= nil and wrap(b) or 0)
        for _, v in ipairs({...}) do r = r ~ wrap(v) end
        return wrap(r)
    end
    function bitlib.bnot(a) return wrap(~wrap(a)) end
    function bitlib.lshift(a, n) return wrap((wrap(a) & MASK) << (n & 31)) end
    function bitlib.rshift(a, n) return wrap((wrap(a) & MASK) >> (n & 31)) end
    function bitlib.arshift(a, n)
        a = wrap(a); n = n & 31
        if a >= 0 then return wrap(a >> n) end
        return wrap(~((~a) >> n))
    end
    function bitlib.rol(a, n)
        a = wrap(a) & MASK; n = n & 31
        if n == 0 then return wrap(a) end
        return wrap(((a << n) | (a >> (32 - n))) & MASK)
    end
    function bitlib.ror(a, n) return bitlib.rol(a, 32 - (n & 31)) end
    function bitlib.bswap(a)
        a = wrap(a) & MASK
        local b0, b1 = a & 0xFF, (a >> 8) & 0xFF
        local b2, b3 = (a >> 16) & 0xFF, (a >> 24) & 0xFF
        return wrap((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
    end
    function bitlib.tohex(a, n)
        n = n or 8
        a = wrap(a) & MASK
        if n < 0 then return string.format("%0" .. (-n) .. "X", a):sub(1, -n) end
        return string.format("%0" .. n .. "x", a):sub(-n)
    end
    package.preload["bit"] = function() return bitlib end
end

-- LuaJIT's "string.buffer": a growable byte buffer. The project-index cache
-- (nupp.build.store) builds and reads one; a plain string accumulator behaves
-- the same for every method it actually calls.
do
    local Buffer = {}
    Buffer.__index = Buffer
    local buflib = {}
    function buflib.new()
        return setmetatable({parts = {}, cached = nil}, Buffer)
    end
    function buflib.istype(v) return getmetatable(v) == Buffer end
    function Buffer:put(...)
        self.cached = nil
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            self.parts[#self.parts + 1] = tostring(v)
        end
        return self
    end
    Buffer.putf = function(self, fmt, ...) return self:put(string.format(fmt, ...)) end
    function Buffer:tostring()
        if not self.cached then
            self.cached = table.concat(self.parts)
            self.parts = {self.cached}
        end
        return self.cached
    end
    Buffer.get = Buffer.tostring
    function Buffer:set(str)
        self.parts = {tostring(str)}
        self.cached = nil
        return self
    end
    function Buffer:reset()
        self.parts = {}
        self.cached = nil
        return self
    end
    Buffer.free = Buffer.reset
    function Buffer:len() return #self:tostring() end
    Buffer.__len = Buffer.len
    Buffer.__tostring = Buffer.tostring
    Buffer.__concat = function(a, b)
        local as = (getmetatable(a) == Buffer) and a:tostring() or tostring(a)
        local bs = (getmetatable(b) == Buffer) and b:tostring() or tostring(b)
        return as .. bs
    end
    -- The cache's on-disk wire format doesn't need to round-trip through
    -- anything but this same VM, so encode/decode is a small self-consistent
    -- scheme (below) rather than LuaJIT's real MessagePack-ish binary format.
    function buflib.encode(value) return require("cjson").encode(value) end
    function buflib.decode(str) return require("cjson").decode(str) end
    package.preload["string.buffer"] = function() return buflib end
end

-- A tiny JSON codec, standing in for the "cjson" C extension that
-- nupp.build.store, nupp.cli.report, and nupp.cli.lsp use for cache blobs,
-- `--json` output, and LSP framing.
do
    local json = {}
    json.new = function() return json end
    local escapes = {['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n",
        ["\r"] = "\\r", ["\t"] = "\\t"}
    local function encodeValue(v, out)
        local t = type(v)
        if t == "string" then
            out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
                return escapes[c] or string.format("\\u%04x", c:byte())
            end) .. '"'
        elseif t == "number" then
            out[#out + 1] = (v ~= v or v == math.huge or v == -math.huge)
                and "null" or tostring(v)
        elseif t == "boolean" then
            out[#out + 1] = tostring(v)
        elseif t == "nil" then
            out[#out + 1] = "null"
        elseif t == "table" then
            local n = #v
            -- An empty table is ambiguous in Lua; every empty list this
            -- playground encodes (diagnostics, notes, related) should read
            -- back as [], so that's the default rather than {}.
            local isArray = true
            if n == 0 then
                for _ in pairs(v) do isArray = false break end
            end
            if isArray then
                out[#out + 1] = "["
                for i = 1, n do
                    if i > 1 then out[#out + 1] = "," end
                    encodeValue(v[i], out)
                end
                out[#out + 1] = "]"
            else
                out[#out + 1] = "{"
                local first = true
                for k, val in pairs(v) do
                    if not first then out[#out + 1] = "," end
                    first = false
                    encodeValue(tostring(k), out)
                    out[#out + 1] = ":"
                    encodeValue(val, out)
                end
                out[#out + 1] = "}"
            end
        else
            out[#out + 1] = "null"
        end
    end
    function json.encode(value)
        local out = {}
        encodeValue(value, out)
        return table.concat(out)
    end
    -- Nothing in the playground actually decodes a stored cache blob back
    -- (see the note on the top of this file): every load path treats a
    -- missing filesystem as a cache miss before decode would run.
    function json.decode(_str)
        error("cjson.decode is not implemented in the browser playground", 0)
    end
    package.preload["cjson"] = function() return json end
end

-- LuaJIT's "ffi": needs a real C compiler and a live process to back struct
-- and cdata introspection, which a browser Lua VM does not have. The checker
-- only reaches into it for programs that declare or import real C types
-- (`ffi.cdef`, `import-c`, struct field layout); ordinary Nupp/Lua source
-- never touches it, so this fails loudly and specifically instead of
-- returning wrong answers.
do
    local function unsupported(name)
        return function()
            error("ffi." .. name .. " is not available in the browser " ..
                "playground: no native C ABI to introspect. This only " ..
                "affects code that declares or imports real C types.", 0)
        end
    end
    local ffilib = setmetatable({
        os = "Browser",
        arch = "wasm",
        istype = function() return false end,
    }, {__index = function(_, key) return unsupported(key) end})
    package.preload["ffi"] = function() return ffilib end
end
