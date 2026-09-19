-- A retained compiler session driven through the guest's actual effect transport.
local encode = dofile("/nupp/json-encoder.lua")()
local decode = dofile("/nupp/json-decoder.lua")()
local now = assert(__qemuNow)
local config = assert(__qemuConfig)
if not config.nativeCompiler then
    package.loaded["nupp.runtime.bitops"] = require("bit")
end
local sequence = 0

local function phase(name)
    if config.timingProbe then
        io.stdout:write("@@NUPP_PHASE@@ " .. sequence .. " " .. name .. "\n")
        io.stdout:flush()
    end
end

local before = now()
local Browser = assert(loadfile(config.bundle or "/nupp/playground-compiler.ljbc"))()
local session = Browser.new()
local result = {loadedMs = now() - before}
while true do
    phase("encode-start")
    local request
    if config.compilerTransport then
        assert(__qemuTransport).write("/host/request.json", encode(result))
        phase("encode-end")
        io.stdout:write("\n@@NUPP_COMPILER_FRAME@@ " .. sequence .. "\n")
        io.stdout:flush()
        assert(tonumber(io.read("*l")) == sequence, "stale compiler reply")
        phase("decode-start")
        request = decode(__qemuTransport.read("/host/response.json"))
        if request.payloadField then
            assert(request.payloadField == "source" or request.payloadField == "padding")
            request[request.payloadField] = __qemuTransport.read("/host/writeback.bin")
        end
        sequence = sequence + 1
    else
        local packet = encode({kind = "effects", requests = {{id = 1, kind = "compiler-request", result = result}}})
        phase("encode-end")
        local responseText = coroutine.yield(packet)
        sequence = sequence + 1
        phase("decode-start")
        local response = decode(responseText)
        request = assert(response.responses[1].value)
    end
    phase("decode-end")
    if request.stop then
        return {ok = true}
    end
    phase("execute-start")
    local started = now()
    local cpu = os.clock()
    local answers = {}
    for i = 1, request.count do
        if request.kind == "noop" then
            answers[i] = {bytes = #(request.padding or "")}
        elseif request.kind == "busy" then
            print("COMPILER_BUSY_BEGIN")
            io.flush()
            while true do
            end
        else
            local source = request.source or "local value: number = 1; return value"
            if request.kind == "edit" then
                source = source:gsub("= 1", "= " .. i)
            end
            local kind = request.kind == "edit" and "check" or request.kind
            if config.direct then
                if kind == "hover" then
                    answers[i] = session:hover(7)
                else
                    answers[i] = session[kind](session, source, "latency.g.nupp", {dialect = "luajit"})
                end
            else
                answers[i] = decode(
                    session:request(
                        encode({
                            kind = kind,
                            source = source,
                            filename = "latency.g.nupp",
                            offset = 7,
                            options = {dialect = "luajit"}
                        })
                    )
                )
            end
        end
    end
    phase("execute-end")
    result = {
        sampledWallMs = now() - started,
        guestCpuMs = (os.clock() - cpu) * 1000,
        count = request.count,
        answers = answers
    }
end
