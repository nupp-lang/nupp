local function heap()
    collectgarbage("collect")
    collectgarbage("collect")
    return collectgarbage("count")
end

return function(jobs, tasks)
    local expected = os.getenv("EXPECT_THREAD") == "1" and "thread" or "table"
    local scope = tasks.scope(8)
    local localTask = scope:spawn(function()
        return coroutine.running()
    end)
    local pooled = scope:work(jobs.identity, 42)
    local dedicated = scope:worker(jobs.identity, 43)
    assert(type(localTask) == expected and type(pooled) == expected and type(dedicated) == expected)
    local self = localTask:await()
    if expected == "thread" then
        assert(self == localTask, "the cooperative handle is its running coroutine")
        local ok, problem = coroutine.resume(localTask)
        assert(not ok and tostring(problem):find("managed", 1, true), "manual resume is refused")
    end
    for _ = 1, 3 do
        heap()
        assert(localTask:await() == self)
        assert(pooled:await() == 42 and dedicated:await() == 43)
    end
    scope:close()
    local weak = setmetatable({localTask, pooled, dedicated}, {__mode = "v"})
    scope, localTask, pooled, dedicated, self = nil, nil, nil, nil, nil
    heap()
    assert(weak[1] == nil and weak[2] == nil and weak[3] == nil, "settled handle cycles collect")

    local compiledScope = tasks.scope()
    local compiledTask = compiledScope:spawn(function()
        return assert(loadstring("return 42"))
    end)
    local compiled = compiledTask:await()
    assert(compiled() == 42 and getfenv(compiled) == _G, "loaded chunks keep the original globals")
    local compiledWeak = setmetatable({compiledTask}, {__mode = "v"})
    compiledScope:close()
    compiledTask, compiledScope = nil, nil
    heap()
    assert(compiledWeak[1] == nil, "a returned loaded chunk does not retain its completed task")
    compiled = nil

    local cancelledScope = tasks.scope()
    local payload = {string.rep("x", 1048576)}
    local payloadWeak = setmetatable({payload}, {__mode = "v"})

    local function capturing(value)
        return function()
            return value
        end
    end

    local cancelled = cancelledScope:spawn(capturing(payload))
    payload = nil
    assert(cancelled:cancel())
    cancelledScope:close()
    heap()
    assert(payloadWeak[1] == nil, "queued cancellation drops captures while the handle is retained")
    assert(cancelled:status() == "cancelled")
    cancelled, cancelledScope = nil, nil

    local raw = coroutine.create(function(value)
        coroutine.yield(value);
        return 7
    end)
    local ok, value = coroutine.resume(raw, 3)
    assert(ok and value == 3)
    ok, value = coroutine.resume(raw)
    assert(ok and value == 7)

    local failedScope = tasks.scope()
    local failure = failedScope:work(jobs.fail)
    assert(not pcall(failure.await, failure))
    assert(not pcall(failedScope.close, failedScope))
    failure, failedScope = nil, nil
    print("correctness passed " .. expected)

    local ffi = require("ffi")
    ffi.cdef("uint64_t nuppNativeMonotonicNs(void);")

    local function now()
        return assert(tonumber(ffi.C.nuppNativeMonotonicNs())) / 1e6
    end

    local count = tonumber(os.getenv("HANDLE_CHILDREN")) or 50000
    local heldCount = tonumber(os.getenv("HANDLE_HELD")) or 10000
    local sum = 0

    local function body()
        return 1
    end

    local before = heap()
    local timedScope = tasks.scope(8)
    local start = now()
    for _ = 1, count do
        sum = sum + timedScope:spawn(body):await()
    end
    timedScope:close()
    local spawnMs = now() - start
    timedScope = nil
    local after = heap()

    local heldScope = tasks.scope(8)
    local held = {}
    before = heap()
    for index = 1, heldCount do
        local task = heldScope:spawn(body)
        sum = sum + task:await()
        held[index] = task
    end
    local retained = heap() - before
    heldScope:close()
    held, heldScope = nil, nil
    local dropped = heap() - after

    local workerScope = tasks.scope(8)
    local workers = 1000
    for index = 1, 100 do
        assert(workerScope:work(jobs.identity, index):await() == index)
    end
    start = now()
    for index = 1, workers do
        sum = sum + workerScope:work(jobs.identity, index):await()
    end
    local workerMs = now() - start
    workerScope:close()
    workerScope = nil

    local generator = coroutine.create(function()
        for index = 1, count do
            coroutine.yield(index)
        end
    end)
    start = now()
    for index = 1, count do
        local resumed, produced = coroutine.resume(generator)
        assert(resumed and produced == index)
    end
    local resumeMs = now() - start
    generator = nil

    local workerHeldScope = tasks.scope(8)
    held = {}
    before = heap()
    for index = 1, 1000 do
        local task = workerHeldScope:work(jobs.identity, index)
        sum = sum + task:await()
        held[index] = task
    end
    local workerRetained = heap() - before
    workerHeldScope:close()
    held, workerHeldScope = nil, nil
    local finalHeap = heap()
    print(
        string.format(
            "metrics %.6f %.6f %.6f %.6f %.6f %.6f %.6f %d",
            spawnMs * 1000 / count,
            workerMs * 1000 / workers,
            resumeMs * 1000 / count,
            retained * 1024 / heldCount,
            workerRetained * 1024 / 1000,
            dropped,
            finalHeap,
            sum
        )
    )
end
