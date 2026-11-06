local parallel = require("nupp.tools.vm.emitparallel")
local process = require("nupp.tools.vm.emitprocess")

local M = {}

local function exercise(fail)
    local dir = os.tmpname()
    os.remove(dir)
    local original = process.start
    local children, starts = {}, {}
    process.start = function(args, options)
        starts[#starts + 1] = {args = args, options = options}
        if (fail == true or fail == "both") and #starts == 2 then
            return nil, "failed to start the second worker"
        end
        local child = {killed = false, closed = false}
        child.stdout = {
            poll = function()
                return nil
            end
        }
        child.stderr = child.stdout
        function child:isrunning()
            return (fail == true or fail == "both") and not self.killed
        end

        function child:wait()
            return {exitcode = 0}
        end

        function child:kill()
            self.killed = true
        end

        function child:close()
            self.closed = true
            if fail == "close" and self == children[1] or fail == "both" then
                error("cleanup failed")
            end
        end

        children[#children + 1] = child

        return child
    end
    local shared
    local ok, result = pcall(parallel.prepare, ".", dir, 4, function(path)
        shared = path
    end)
    process.start = original
    os.execute("rm -rf '" .. dir .. "'")

    return ok, result, starts, children, shared
end

function M.disjointWorkersShareOnlyCompletedCacheInputs()
    local ok, imports, starts, children, shared = exercise(false)
    assert(ok, imports)
    assert(#starts == 4 and #imports == 5 and imports[1] == shared, "four workers did not share one completed cache")
    local outputs = {}
    for index, started in ipairs(starts) do
        local env = started.options.env
        assert(env.NUPP_VM_EMIT_JOBS == "1", "a worker could recursively start more workers")
        assert(env.NUPP_VM_EMIT_IMPORTS == shared, "a worker read another worker's mutable cache")
        assert(not outputs[env.NUPP_VM_EMIT_CACHE], "two workers shared output")
        outputs[env.NUPP_VM_EMIT_CACHE] = true
        assert(children[index].closed and not children[index].killed, "a completed worker was not closed")
    end
end

function M.aSpawnFailureClosesTheWorkersAlreadyStarted()
    local ok, problem, starts, children = exercise(true)
    assert(not ok and tostring(problem):find("failed to start the second worker", 1, true), problem)
    assert(#starts == 2 and #children == 1, "the failure started additional workers")
    assert(children[1].killed and children[1].closed, "the failed session left a worker running")
end

function M.aCloseFailureStillClosesEveryOtherWorker()
    local ok, problem, _, children = exercise("close")
    assert(not ok and tostring(problem):find("cleanup failed", 1, true), problem)
    for _, child in ipairs(children) do
        assert(child.closed, "an earlier close failure skipped another worker")
    end
end

function M.cleanupDoesNotReplaceTheOriginalFailure()
    local ok, problem, _, children = exercise("both")
    assert(not ok and tostring(problem):find("failed to start the second worker", 1, true), problem)
    assert(children[1].killed and children[1].closed)
end

return M
