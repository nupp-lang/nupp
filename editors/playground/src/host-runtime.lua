--[[
What the browser Lua VM needs before bootstrap/nupp.lua will load and run: a
handful of LuaJIT-only pieces the compiler's own implementation leans on, not
just the code it generates for a checked program.

`bit` and `string.buffer` are real, working implementations — the checker's
C-declaration decoder and the project-index cache actually call them. `lpeg`
supplies the no-op global setup needed to load the compiler; generated matchers
are not run by this compile-only playground. The `jit` identity and opcode
names let static trace metadata initialize without claiming a live recorder.
`ffi` implements the fixed-width byte and word storage the compiler itself uses
and fails loudly for real C-ABI introspection, so code that declares or imports
C types is the one thing this playground cannot check. `io.open`/`io.popen` and
`nupp.io.files` are wired to "not found" rather than left absent, so the
project index and manifest lookups take the same empty-filesystem path they
did before the compiler moved directory walks onto its native files API.
]]

arg = {}
os.exit = function(...) return ... end
-- Fengari exposes getenv only under Node. A browser cannot launch the
-- filesystem-backed comptime worker, so reporting no compiler-root variables
-- selects the evaluator's in-process path.
os.getenv = function() return nil end

-- Lua 5.1 and LuaJIT's `loadstring`, which 5.2 folded into `load` and 5.3 --
-- fengari's dialect -- does not define at all. nupp.compiler.optimize's constant folder
-- reaches for it to evaluate a numeric literal the lexer already accepted, so
-- without this the optimizer is not merely absent in the browser: turning it
-- on fails the compile with "attempt to call a nil value".
--
-- Its other caller is nupp.compiler.gen, which loads the Lua it just generated to
-- prove it parses and reports NUPP3005 ("generated code does not load", a
-- compiler bug) when it does not. That check reads the host VM's parser as
-- if it were the target's, which holds under LuaJIT and not here: this VM
-- rejects the same two LuaJIT-only constructs that
-- tools/patch-bootstrap-for-browser.lua rewrites out of the compiler's own
-- source at build time, and generated code carries both -- `const NAME =`
-- for every top-level `const` a program declares, and `0x..ULL` literals for
-- 64-bit constants. So a correct program compiled in the browser reported a
-- compiler bug against itself, at whichever line held its first `const`.
--
-- Rewriting those two to their plain-Lua equivalents before a retry answers
-- the question the caller is actually asking -- "would the target parse
-- this?" -- rather than dropping the check, which would leave real malformed
-- emissions silent here. Both spellings are the same length or shorter and
-- neither changes tokenization, so a syntax error in the retry names the
-- line the original would have.
do
    local realLoad = loadstring or load

    -- Same rules and same reasoning as the build-time patcher, including
    -- using the compiler's own lexer rather than a pattern over the raw
    -- text: `const` is a soft keyword, so only a `const NAME`/`const
    -- function` sequence is a declaration, and the five characters c-o-n-s-t
    -- inside a string literal (generated code embeds Lua source text, some
    -- of it holding `const`) must not be touched. The lexer is the bootstrap
    -- compiler's, already loaded by the time anything asks to load generated
    -- code; without it there is nothing to rewrite from and the original
    -- refusal stands.
    local function asPlainLua(source)
        local ok, lexer = pcall(require, "nupp.compiler.lexer")
        if not ok or type(lexer) ~= "table" then return nil end
        local lexed, errors = lexer.lex(source, "browser-load")
        if not lexed or (errors and #errors > 0) then return nil end
        local edits = {}
        for i, token in ipairs(lexed) do
            local following = lexed[i + 1]
            local declares = following and not following.missing
                and (following.text == "function" or following.kind == "name")
            if token.text == "const" and declares then
                edits[#edits + 1] = {offset = token.offset, length = 5, replacement = "local"}
            elseif token.kind == "number" and (token.text:match("^0[xX][0-9A-Fa-f]+U?LL$")
                or token.text:match("^[0-9]+U?LL$")) then
                edits[#edits + 1] = {offset = token.offset, length = #token.text,
                    replacement = (token.text:gsub("U?LL$", ""))}
            end
        end
        if #edits == 0 then return nil end
        local parts, position = {}, 1
        for _, edit in ipairs(edits) do
            parts[#parts + 1] = source:sub(position, edit.offset - 1)
            parts[#parts + 1] = edit.replacement
            position = edit.offset + edit.length
        end
        parts[#parts + 1] = source:sub(position)
        return table.concat(parts)
    end

    loadstring = function(chunk, ...)
        local loaded, reason = realLoad(chunk, ...)
        if loaded or type(chunk) ~= "string" then return loaded, reason end
        local plain = asPlainLua(chunk)
        if not plain then return loaded, reason end
        -- The retry's refusal is the one to report: it is what remains after
        -- the dialect gap is closed, so it describes the chunk as the
        -- runtime this code targets would see it.
        return realLoad(plain, ...)
    end
end

-- Lua 5.1 and LuaJIT also exposed this table helper globally. The comptime
-- evaluator calls allowlisted functions with an exact argument sequence, so
-- it needs the 5.1 spelling even though fengari only provides table.unpack.
unpack = unpack or table.unpack

-- Lua 5.3 removed LuaJIT's math.frexp spelling. The checker uses it to decide
-- whether a numeric literal is exactly representable as float32.
math.frexp = math.frexp or function(value)
    if value == 0 then return value, 0 end
    local magnitude = math.abs(value)
    local exponent = math.floor(math.log(magnitude, 2)) + 1
    local significand = value / 2 ^ exponent
    if math.abs(significand) < 0.5 then
        significand, exponent = significand * 2, exponent - 1
    elseif math.abs(significand) >= 1 then
        significand, exponent = significand / 2, exponent + 1
    end
    return significand, exponent
end

-- Static trace metadata is part of the checker even when no code will run. It
-- needs the target identity and LuaJIT's packed bytecode names, but never VM
-- introspection in this compile-only process. Present the standard 64-bit Linux
-- target, report the recorder disabled, and keep every mutating JIT control a
-- no-op. The packed names are stable for the LuaJIT snapshot Nupp targets.
do
    jit = {
        version = "LuaJIT 2.1.1785763465",
        version_num = 20199,
        os = "Linux",
        arch = "x64",
        status = function() return false end,
        on = function() end,
        off = function() end,
        flush = function() end,
        opt = {start = function() end},
    }
    local vmdef = {
        bcnames = "ISLT  ISGE  ISLE  ISGT  ISEQV ISNEV ISEQS ISNES ISEQN ISNEN ISEQP ISNEP ISTC  ISFC  IST   ISF   ISTYPEISNUM MOV   NOT   UNM   LEN   ADDVN SUBVN MULVN DIVVN MODVN ADDNV SUBNV MULNV DIVNV MODNV ADDVV SUBVV MULVV DIVVV MODVV POW   CAT   KSTR  KCDATAKSHORTKNUM  KPRI  KNIL  UGET  USETV USETS USETN USETP UCLO  FNEW  TNEW  TDUP  GGET  GSET  TGETV TGETS TGETB TGETR TSETV TSETS TSETB TSETM TSETR CALLM CALL  CALLMTCALLT ITERC ITERN VARG  ISNEXTRETM  RET   RET0  RET1  FORI  JFORI FORL  IFORL JFORL ITERL IITERLJITERLLOOP  ILOOP JLOOP JMP   BNOT  BAND  BOR   BXOR  BSHL  BSHR  BSAR  FUNCF IFUNCFJFUNCFFUNCV IFUNCVJFUNCVFUNCC FUNCCW",
        irnames = "",
        traceerr = {},
        ffnames = {},
        ircall = {},
        irfield = {},
        irfpm = {},
    }
    package.preload["jit"] = function() return jit end
    package.preload["jit.vmdef"] = function() return vmdef end
end

-- The compiler's project index now walks through nupp.io.files. Preinstalling
-- the empty browser implementation keeps bootstrap's lazy native installer
-- from replacing it, which would reach ffi.cdef just to discover that the
-- browser has no directory to list. The playground checks one in-memory
-- buffer, so every lookup correctly answers "not found"; mutation reports the
-- same unavailable filesystem as io.open below.
do
    local unavailable = "no filesystem in the browser playground"
    local function absent() return nil, unavailable end
    local function no() return false end
    local files = {
        info = absent,
        exists = no,
        isFile = no,
        isDirectory = no,
        isSymlink = no,
        readLink = absent,
        list = function() return {} end,
        glob = function() return {} end,
        read = absent,
        open = absent,
        lines = absent,
        currentDirectory = absent,
        userFolder = absent,
        createTemporaryFile = absent,
        createTemporaryDirectory = absent,
        pendingTransfers = function() return 0 end,
    }
    for _, name in ipairs({
        "createSymlink", "setReadOnly", "createDirectory", "remove",
        "rename", "write", "append", "writeAtomic", "copy",
    }) do
        files[name] = function() return false, unavailable end
    end
    nupp = nupp or {}
    nupp.io = nupp.io or {}
    nupp.io.files = files
    package.loaded["nupp.io.files"] = files
end

-- fengari only registers the "io" global when it thinks it's running under
-- Node (see the `typeof process` guard build.mjs folds away for the
-- browser), so there is no table here to patch yet.
io = io or {}

-- Compiler modules name the three standard streams while they initialize,
-- even though the playground never writes a CLI report. Browser Fengari omits
-- them with the rest of `io`; distinct inert handles preserve the stream keys
-- and make an accidental write harmless instead of crashing worker startup.
local function inertStream()
    local stream = {}
    function stream:write() return self end
    function stream:flush() return true end
    function stream:read() return nil end
    return stream
end
io.stdin = io.stdin or inertStream()
io.stdout = io.stdout or inertStream()
io.stderr = io.stderr or inertStream()

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
        -- Fengari's hexadecimal lexer routes these two boundary values
        -- through its signed 32-bit integer representation: 0x80000000 is
        -- negative and 0x100000000 becomes zero. Decimal arithmetic keeps the
        -- modulo well-defined before native bitwise operators see the value.
        n = math.floor(n) % 4294967296
        if n >= 2147483648 then n = n - 4294967296 end
        return n | 0
    end
    local bitlib = {}
    function bitlib.tobit(n) return wrap(n) end
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
    -- A global as well as a module, because LuaJIT registers it as one at
    -- startup and nupp.compiler.build.hash reads it that way on purpose (see the note
    -- above its own `local band, bxor = bit.band, bit.bxor`): requiring it into a
    -- local of the same name would shadow the declaration that types it. A shim
    -- that only answers `require` leaves that file indexing a nil global, which
    -- is a boot failure rather than a missing feature.
    bit = bitlib
    package.preload["bit"] = function() return bitlib end
end

-- LuaJIT's "string.buffer": a growable byte buffer. The project-index cache
-- (nupp.compiler.build.store) builds and reads one; a plain string accumulator behaves
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
    function buflib.encode(value) return require("jsonNative").encode(value) end
    function buflib.decode(str) return require("jsonNative").decode(str) end
    package.preload["string.buffer"] = function() return buflib end
end

-- A tiny JSON codec, standing in for the `jsonNative` extension that
-- nupp.compiler.build.store, nupp.compiler.cli.report, and nupp.compiler.cli.lsp use for cache blobs,
-- `--json` output, and LSP framing.
do
    local json = {}
    json.NULL = {}
    json.EMPTY_ARRAY = {}
    json.EMPTY_OBJECT = {}
    function json.asArray(value) return setmetatable(value, json.EMPTY_ARRAY) end
    function json.asObject(value) return setmetatable(value, json.EMPTY_OBJECT) end
    local ESCAPES = {['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n",
        ["\r"] = "\\r", ["\t"] = "\\t"}
    local function encodeValue(v, out)
        if v == json.NULL then out[#out + 1] = "null" return end
        if v == json.EMPTY_ARRAY then out[#out + 1] = "[]" return end
        if v == json.EMPTY_OBJECT then out[#out + 1] = "{}" return end
        local t = type(v)
        if t == "string" then
            out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
                return ESCAPES[c] or string.format("\\u%04x", c:byte())
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
            local marker = getmetatable(v)
            local isArray = marker == json.EMPTY_ARRAY or n > 0
            if marker == json.EMPTY_OBJECT then isArray = false end
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
    json.serialize = json.encode
    -- Nothing in the playground actually decodes a stored cache blob back
    -- (see the note on the top of this file): every load path treats a
    -- missing filesystem as a cache miss before decode would run.
    function json.decode(_str)
        error("jsonNative.decode is not implemented in the browser playground", 0)
    end
    package.preload["jsonNative"] = function() return json end
end

-- Loading a compiler built with PEG support installs nupp.peg and raises LPeg's
-- process-global backtrack limit. The playground checks and compiles programs;
-- it never executes the generated matchers, so the only LPeg operation driver
-- startup needs is that harmless setup call. Keep every pattern operation
-- unavailable rather than pretending Fengari has a native LPeg implementation.
do
    local function unavailable(name)
        return function()
            error("lpeg." .. name .. " is not available in the browser " ..
                "playground: generated programs are not executed here.", 0)
        end
    end
    local lpeg = setmetatable({
        setmaxstack = function() end,
    }, {__index = function(_, key) return unavailable(key) end})
    package.preload["lpeg"] = function() return lpeg end
end

-- LuaJIT's "ffi": needs a real C compiler and a live process to back struct
-- and cdata introspection, which a browser Lua VM does not have. Fixed-width
-- arrays are different: the compiler's lexer keeps trivia in a uint32_t block,
-- whose width and indexing are defined without asking a platform ABI. That
-- small exact subset is implemented here; programs that declare or import real
-- C types still fail loudly and specifically instead of getting wrong answers.
do
    local function unsupported(name)
        return function()
            error("ffi." .. name .. " is not available in the browser " ..
                "playground: no native C ABI to introspect. This only " ..
                "affects code that declares or imports real C types.", 0)
        end
    end
    -- `ffi.cast` has a real implementation for the four shapes
    -- nupp.compiler.build.hash's XXH64 asks for and nothing else. Reading
    -- little-endian words out of a Lua string is not C-ABI work -- no layout, no
    -- alignment, no offset the platform decides -- so unlike struct introspection
    -- it is something this VM can answer exactly, and Lua 5.3's own 64-bit
    -- integers wrap the way LuaJIT's uint64 does. Every other spelling still
    -- fails loudly, which is what keeps a real `struct` or an `import-c`
    -- honest.
    -- Eight bytes are read as two four-byte halves and put back together, not
    -- as one "<I8": Lua 5.3's unpack raises on an unsigned 64-bit value past the
    -- signed range rather than wrapping, and half of every hash word is past it.
    -- Shifting the halves together gives the same 64 bits, which is all the
    -- arithmetic downstream is: bitwise, and multiplication that wraps.
    local VIEWS = {
        ["const uint64_t *"] = {width = 8, format = "<I4", halves = true},
        ["const uint32_t *"] = {width = 4, format = "<I4"},
        ["const uint8_t *"] = {width = 1, format = "<I1"},
    }
    local function cast(spec, value)
        if spec == "uint64_t" then
            return math.tointeger(value) or math.floor(value)
        end
        local view = VIEWS[spec]
        if not view then return unsupported("cast")() end
        -- Zero-based, the way indexing a C pointer is. Out of range answers 0
        -- rather than raising: the hash never reads past its input, and a
        -- reinterpreting view is the wrong place to discover that it did.
        return setmetatable({}, {__index = function(_, index)
            local at = index * view.width + 1
            if at < 1 or at + view.width - 1 > #value then return 0 end
            if view.halves then
                local low = string.unpack("<I4", value, at)
                local high = string.unpack("<I4", value, at + 4)
                return (high << 32) | low
            end
            return (string.unpack(view.format, value, at))
        end})
    end

    -- The lossless lexer grows a zero-based uint32_t arena and copies the live
    -- prefix when it does. A Lua table is the same indexed word store here:
    -- uint32_t fixes the element width, every written value is already in range,
    -- and hidden length metadata lets copy reject an out-of-bounds request
    -- instead of silently standing in for any other cdata operation.
    local ARRAY_LENGTH = {}
    local ZEROED = {__index = function(_, index)
        if type(index) == "number" then return 0 end
    end}
    local function new(spec, count)
        count = math.tointeger(count)
        if spec ~= "uint32_t[?]" or count == nil or count < 0 then
            return unsupported("new")()
        end
        return setmetatable({[ARRAY_LENGTH] = count}, ZEROED)
    end
    local function copy(target, source, bytes)
        bytes = math.tointeger(bytes)
        local targetLength = type(target) == "table" and rawget(target, ARRAY_LENGTH)
        local sourceLength = type(source) == "table" and rawget(source, ARRAY_LENGTH)
        if bytes == nil or bytes < 0 or bytes % 4 ~= 0
            or targetLength == nil or sourceLength == nil
            or bytes > targetLength * 4 or bytes > sourceLength * 4 then
            return unsupported("copy")()
        end
        for index = 0, bytes / 4 - 1 do
            target[index] = source[index]
        end
    end

    local ffilib = setmetatable({
        os = "Browser",
        arch = "wasm",
        istype = function() return false end,
        cast = cast,
        new = new,
        copy = copy,
    }, {__index = function(_, key) return unsupported(key) end})
    -- Global too, for the same reason as `bit` above. This one matters less --
    -- reaching it at all is the error -- but a nil global reports "attempt to
    -- index a nil value" where the stub reports what is actually wrong.
    -- Global too, for the same reason as `bit` above. This one matters less --
    -- reaching it at all is the error -- but a nil global reports "attempt to
    -- index a nil value" where the stub reports what is actually wrong.
    ffi = ffilib
    package.preload["ffi"] = function() return ffilib end
end
