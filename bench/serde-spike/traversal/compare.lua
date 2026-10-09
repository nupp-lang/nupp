-- Approximate runtime traversal shapes, independent of the proposed Nupp API.
jit.off() -- Do not let schema construction or negative tests train the hot paths.
local buffer = require("string.buffer")
local util = require("jit.util")
local bit = require("bit")
local vmdef = require("jit.vmdef")
local workload, variant, mode = arg[1] or "small", arg[2] or "callback", arg[3] or "encode-checksum"
local seconds = tonumber(arg[4]) or 0.025
local diagnostic = arg[5] == "diagnostic"
local I, S, B, N, OBJ, ENDOBJ, ARR, ENDARR, KEY = 1, 2, 3, 4, 5, 6, 7, 8, 9
local quote = string.format
local Sink = {}
Sink.__index = Sink
function Sink:put(kind, value)
    if self.mode == "tokens" then
        self.count = self.count + 1
        self.kinds[self.count], self.values[self.count] = kind, value
    elseif self.mode == "encode-json" then
        local out = self.out
        if kind == I then
            out:put(tostring(value))
        elseif kind == S or kind == KEY then
            out:put(quote("%q", value))
            if kind == KEY then
                out:put(":")
            end
        elseif kind == B then
            out:put(value and "true" or "false")
        elseif kind == N then
            out:put("null")
        elseif kind == OBJ then
            out:put("{")
        elseif kind == ENDOBJ then
            out:put("}")
        elseif kind == ARR then
            out:put("[")
        else
            out:put("]")
        end
    else
        local n = kind
        if kind == I then
            n = n + value
        elseif kind == S or kind == KEY then
            n = n + #value + value:byte(#value)
        elseif kind == B then
            n = n + (value and 1 or 0)
        end
        self.sum = self.sum + n
    end
end

function Sink:separator(index)
    if index > 1 and self.mode == "encode-json" then
        self.out:put(",")
    end
end

function Sink:struct(node, value, emit)
    self:put(OBJ)
    emit(node, value, self)
    self:put(ENDOBJ)
end

function Sink:list(node, value, emit)
    self:put(ARR)
    emit(node, value, self)
    self:put(ENDARR)
end

local function sink(kind)
    return setmetatable({mode = kind, out = buffer.new(), sum = 0, count = 0, kinds = {}, values = {}}, Sink)
end

local function reset(out)
    out.out:reset()
    out.sum, out.count = 0, 0
end

local function scalar(node, value, out)
    out:put(value == nil and N or node.kind, value)
end

local function emitMembers(node, value, out)
    for index, field in ipairs(node.fields) do
        out:separator(index)
        out:put(KEY, field.wire)
        field.node.cb(field.node, value[field.key], out)
    end
end

local function emitElements(node, value, out)
    for index = 1, #value do
        out:separator(index)
        node.element.cb(node.element, value[index], out)
    end
end

local function callbackRecord(node, value, out)
    out:struct(node, value, node.emit)
end

local function callbackList(node, value, out)
    out:list(node, value, emitElements)
end

-- The cursor returns unboxed values and keeps iteration state in caller locals.
local function nextMember(node, value, index)
    index = index + 1
    local field = node.fields[index]
    if field then
        return index, field, value[field.key]
    end
end

local function nextElement(value, index)
    index = index + 1
    if index <= #value then
        return index, value[index]
    end
end

local function cursorEncode(node, value, out)
    if node.kind == OBJ then
        out:put(OBJ)
        local index = 0
        while true do
            local field, item
            index, field, item = nextMember(node, value, index)
            if not index then
                break
            end
            out:separator(index)
            out:put(KEY, field.wire)
            cursorEncode(field.node, item, out)
        end
        out:put(ENDOBJ)
    elseif node.kind == ARR then
        out:put(ARR)
        local index = 0
        while true do
            local item
            index, item = nextElement(value, index)
            if not index then
                break
            end
            out:separator(index)
            cursorEncode(node.element, item, out)
        end
        out:put(ENDARR)
    else
        scalar(node, value, out)
    end
end

local function loopEncode(node, value, out)
    if node.kind == OBJ then
        out:put(OBJ)
        for index = 1, #node.fields do
            local field = node.fields[index]
            out:separator(index)
            out:put(KEY, field.wire)
            loopEncode(field.node, value[field.key], out)
        end
        out:put(ENDOBJ)
    elseif node.kind == ARR then
        out:put(ARR)
        for index = 1, #value do
            out:separator(index)
            loopEncode(node.element, value[index], out)
        end
        out:put(ENDARR)
    else
        scalar(node, value, out)
    end
end

local Reader = {}
Reader.__index = Reader
function Reader:take(kind)
    local index = self.index
    assert(self.kinds[index] == kind, "wrong token kind")
    self.index = index + 1
    return self.values[index]
end

function Reader:key(field)
    assert(self:take(KEY) == field.wire, "wrong key")
end

function Reader:scalar(node)
    if self.kinds[self.index] == N then
        self:take(N)
        return nil
    end

    return self:take(node.kind)
end

function Reader:members(node, result, accept)
    for index = 1, #node.fields do
        local field = node.fields[index]
        self:key(field)
        accept(result, field, self)
    end
end

function Reader:elements(node, result, accept)
    local index = 1
    while self.kinds[self.index] ~= ENDARR do
        accept(result, node.element, index, self)
        index = index + 1
    end
end

local callbackDecode

local function acceptMember(result, field, reader)
    result[field.key] = callbackDecode(field.node, reader)
end

local function acceptElement(result, node, index, reader)
    result[index] = callbackDecode(node, reader)
end

callbackDecode = function(node, reader)
    if node.kind == OBJ then
        reader:take(OBJ)
        local result = {}
        reader:members(node, result, acceptMember)
        reader:take(ENDOBJ)
        return result
    elseif node.kind == ARR then
        reader:take(ARR)
        local result = {}
        reader:elements(node, result, acceptElement)
        reader:take(ENDARR)
        return result
    else
        return reader:scalar(node)
    end
end
function Reader:nextMember(node, index)
    index = index + 1
    local field = node.fields[index]
    if field then
        self:key(field);
        return index, field
    end
end

local function cursorDecode(node, reader)
    if node.kind == OBJ then
        reader:take(OBJ)
        local result, index = {}, 0
        while true do
            local field
            index, field = reader:nextMember(node, index)
            if not index then
                break
            end
            result[field.key] = cursorDecode(field.node, reader)
        end
        reader:take(ENDOBJ)
        return result
    elseif node.kind == ARR then
        reader:take(ARR)
        local result, index = {}, 1
        while reader.kinds[reader.index] ~= ENDARR do
            result[index] = cursorDecode(node.element, reader)
            index = index + 1
        end
        reader:take(ENDARR)
        return result
    else
        return reader:scalar(node)
    end
end

local function loopDecode(node, reader)
    if node.kind == OBJ then
        reader:take(OBJ)
        local result = {}
        for index = 1, #node.fields do
            local field = node.fields[index]
            reader:key(field)
            result[field.key] = loopDecode(field.node, reader)
        end
        reader:take(ENDOBJ)
        return result
    elseif node.kind == ARR then
        reader:take(ARR)
        local result, index = {}, 1
        while reader.kinds[reader.index] ~= ENDARR do
            result[index] = loopDecode(node.element, reader)
            index = index + 1
        end
        reader:take(ENDARR)
        return result
    else
        return reader:scalar(node)
    end
end

local generated = {}

local function compile(source, name)
    local fn = assert(loadstring(source, name))()
    generated[#generated + 1] = fn
    return fn
end

local function prepare(node, useGenerated)
    if node.kind == OBJ then
        local enc, dec, emit = {
            "return function(n,v,w) w:put(5)"
        }, {"return function(n,r) r:take(5); local v={}"}, {"return function(n,v,w)"}
        for index, field in ipairs(node.fields) do
            prepare(field.node, useGenerated)
            local key = type(field.key) == "number" and tostring(field.key) or quote("%q", field.key)
            enc[
                #enc + 1
            ] = (
                "w:separator(%d); w:put(9,n.fields[%d].wire); n.fields[%d].node.direct(n.fields[%d].node,v[%s],w)"
            ):format(index, index, index, index, key)
            emit[
                #emit + 1
            ] = (
                "w:separator(%d); w:put(9,n.fields[%d].wire); n.fields[%d].node.cb(n.fields[%d].node,v[%s],w)"
            ):format(index, index, index, index, key)
            dec[
                #dec + 1
            ] = (
                "r:key(n.fields[%d]); v[%s]=n.fields[%d].node.directRead(n.fields[%d].node,r)"
            ):format(index, key, index, index)
        end
        enc[#enc + 1], emit[#emit + 1], dec[#dec + 1] = "w:put(6) end", "end", "r:take(6); return v end"
        node.direct = compile(table.concat(enc, "\n"), "direct-encode")
        node.directRead = compile(table.concat(dec, "\n"), "direct-decode")
        node.emit = useGenerated and compile(table.concat(emit, "\n"), "callback-members") or emitMembers
        node.cb = callbackRecord
    elseif node.kind == ARR then
        prepare(node.element, useGenerated)
        node.cb = callbackList
        node.direct = compile(
            "return function(n,v,w) w:put(7); for i=1,#v do w:separator(i); n.element.direct(n.element,v[i],w) end; w:put(8) end",
            "direct-list"
        )
        node.directRead = compile(
            "return function(n,r) r:take(7); local v={}; local i=1; while r.kinds[r.index]~=8 do v[i]=n.element.directRead(n.element,r); i=i+1 end; r:take(8); return v end",
            "direct-read-list"
        )
    else
        node.cb, node.direct = scalar, scalar
        node.directRead = function(n, r)
            return r:scalar(n)
        end
    end
end

local function record(width, salt, slots)
    local node = {kind = OBJ, fields = {}}
    for i = 1, width do
        node.fields[
            i
        ] = {
            key = slots and i or ("f" .. i .. "_" .. salt),
            wire = "f" .. i .. "_" .. salt,
            node = {kind = (i % 3) + 1}
        }
    end

    return node
end

local function valueFor(node, seed)
    if node.kind == OBJ then
        local value = {}
        for i, field in ipairs(node.fields) do
            value[field.key] = valueFor(field.node, seed + i)
        end
        return value
    elseif node.kind == ARR then
        local value = {}
        for i = 1, node.length do
            value[i] = valueFor(node.element, seed + i)
        end
        return value
    elseif node.kind == I then
        return seed * 13
    elseif node.kind == S then
        return "value_" .. seed
    else
        return seed % 2 == 0
    end
end

local cases = {}
local count = workload == "mixed16" and 16 or 1
for i = 1, count do
    local node
    if workload == "small" then
        node = record(3, 1, false)
    elseif workload == "wide" then
        node = record(12, 1, false)
    elseif workload == "slots" then
        node = record(12, 1, true)
    elseif workload == "list" then
        node = {kind = ARR, length = 32, element = record(3, 1, false)}
    elseif workload == "nested" then
        node = record(3, 1, false)
        for depth = 1, 4 do
            node = {
                kind = OBJ,
                fields = {{key = "tag", wire = "tag", node = {kind = I}}, {key = "child", wire = "child", node = node}}
            }
        end
    elseif workload == "mixed16" then
        node = record(3 + (i % 4) * 3, i, false)
    else
        error("unknown workload")
    end
    prepare(node, variant == "generated-callback")
    for seed = 1, 8 do
        local value = valueFor(node, seed)
        -- Exercise explicit null in record fields while keeping array positions dense.
        if node.kind == OBJ and seed % 2 == 0 then
            value[node.fields[1].key] = nil
        end
        local tokens = sink("tokens")
        loopEncode(node, value, tokens)
        cases[
            #cases + 1
        ] = {
            node = node,
            value = value,
            reader = setmetatable({kinds = tokens.kinds, values = tokens.values, index = 1}, Reader),
            tokenCount = tokens.count
        }
    end
end
if count > 1 then
    local interleaved = {}
    for seed = 1, 8 do
        for schema = 1, count do
            interleaved[#interleaved + 1] = cases[(schema - 1) * 8 + seed]
        end
    end
    cases = interleaved
end
local encode, decode
if variant == "callback" or variant == "generated-callback" then
    encode = function(n, v, w)
        n.cb(n, v, w)
    end
    decode = callbackDecode
elseif variant == "cursor" then
    encode, decode = cursorEncode, cursorDecode
elseif variant == "prepared-loop" then
    encode, decode = loopEncode, loopDecode
elseif variant == "direct" then
    encode = function(n, v, w)
        n.direct(n, v, w)
    end
    decode = function(n, r)
        return n.directRead(n, r)
    end
else
    error("unknown variant")
end
-- generated-callback changes encode emitters only; decode is deliberately shared.
assert(not (variant == "generated-callback" and mode == "decode-tokens"), "duplicate decode variant")

local function equal(a, b)
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not equal(v, b[k]) then
            return false
        end
    end
    for k, v in pairs(b) do
        if not equal(v, a[k]) then
            return false
        end
    end

    return true
end

local out = sink(mode)
for _, case in ipairs(cases) do
    local expected, actual = sink("encode-json"), sink("encode-json")
    loopEncode(case.node, case.value, expected)
    encode(case.node, case.value, actual)
    assert(expected.out:get() == actual.out:get(), "encode mismatch")
    case.reader.index = 1
    assert(equal(decode(case.node, case.reader), case.value), "decode mismatch")
    assert(case.reader.index == case.tokenCount + 1, "unconsumed tokens")
    local first = case.reader.kinds[1]
    case.reader.kinds[1] = -1
    case.reader.index = 1
    assert(not pcall(decode, case.node, case.reader), "invalid token accepted")
    case.reader.kinds[1] = first
end
-- Vary data inside each schema, and use one shared hot call site for mixed schemas.
local retained = {}

local function run(iterations)
    local total = 0
    for index = 1, iterations do
        local case = cases[(index - 1) % #cases + 1]
        if mode == "decode-tokens" then
            case.reader.index = 1
            local value = decode(case.node, case.reader)
            -- Make complete outputs escape; a checksum of one field could let
            -- LuaJIT eliminate the rest of a specialized construction.
            retained[(index - 1) % 64 + 1] = value
            total = total + case.reader.index
        else
            reset(out)
            encode(case.node, case.value, out)
            total = total + (mode == "encode-json" and #out.out or out.sum)
        end
    end

    return total
end

jit.flush()
jit.on()
collectgarbage("collect")
local aborts, exits = 0, 0
if diagnostic then
    jit.attach(
        function(event)
            if event == "abort" then
                aborts = aborts + 1
            end
        end,
        "trace"
    )
    jit.attach(
        function()
            exits = exits + 1
        end,
        "texit"
    )
end
local consumed = run(2000)
local iterations = 128
while true do
    local start = os.clock()
    consumed = consumed + run(iterations)
    local elapsed = os.clock() - start
    if elapsed >= seconds then
        break
    end
    iterations = iterations * math.max(2, math.min(16, math.ceil(seconds / math.max(elapsed, 0.000001))))
end
local samples = {}
for i = 1, 3 do
    local start = os.clock()
    consumed = consumed + run(iterations)
    samples[i] = (os.clock() - start) * 1e9 / iterations
end
jit.off() -- Keep metadata inspection out of the trace count.
local traces, ir = 0, 0
for i = 1, 10000 do
    local info = util.traceinfo(i)
    if info then
        traces = traces + 1;
        ir = ir + info.nins
    end
end
jit.on()
-- Allocation diagnostic: approximate heap growth with GC paused, outside timing.
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
consumed = consumed + run(256)
local bytes = (collectgarbage("count") - before) * 1024 / 256
collectgarbage("restart")
local fnew = 0
for _, fn in ipairs(generated) do
    local pc = 1
    while true do
        local ins = util.funcbc(fn, pc)
        if not ins then
            break
        end
        local op = bit.band(ins, 255)
        if vmdef.bcnames:sub(op * 6 + 1, op * 6 + 6):match("FNEW") then
            fnew = fnew + 1
        end
        pc = pc + 1
    end
end
print(
    table.concat(
        {
            workload,
            variant,
            mode,
            iterations,
            samples[1],
            samples[2],
            samples[3],
            traces,
            ir,
            bytes,
            aborts,
            exits,
            fnew,
            consumed
        },
        "\t"
    )
)
