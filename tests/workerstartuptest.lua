local native = require("nupp.workers.native")
local M = {}

function M.idleWorkerStartsWithoutSetupReplay()
    local inbox, outbox = native.channelCreate(), native.channelCreate()
    local handle, problem = native.workerSpawn(inbox, outbox)
    if not handle then
        native.channelDestroy(inbox)
        native.channelDestroy(outbox)
        error(problem, 0)
    end
    native.channelClose(inbox)
    local status, failure = native.workerJoin(handle)
    native.channelDestroy(inbox)
    native.channelDestroy(outbox)
    assert(status == 0, tostring(failure))
end

return M
