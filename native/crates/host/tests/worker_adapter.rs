use nupp_native_host::HostRuntime;

fn runtime(payload: &[u8]) -> HostRuntime {
    let mut runtime = HostRuntime::owned(true, None).expect("runtime");
    runtime.enable_workers(payload).expect("worker modules");
    runtime
}

fn run(runtime: &HostRuntime, chunk: &[u8]) {
    runtime
        .run_buffer(chunk, "=worker-adapter-test", &[])
        .expect("Lua adapter fixture");
}

#[test]
fn lua_modules_preserve_channels_regions_and_builder_errors() {
    let mut runtime = runtime(b"return nil");
    run(
        &runtime,
        br#"
local workers = require("nupp.workers.native")
local bytes = require("nupp.mem.sharedbytes.native")
local ffi = require("ffi")

local channel = assert(workers.channelCreate())
assert(workers.channelPush(channel, "header", "body"))
assert(workers.channelCount(channel) == 1)
local header, body = workers.channelPop(channel, 0)
assert(header == "header" and body == "body")

assert(workers.channelDictRegister(channel, "jobs.run") == 1)
assert(workers.channelDictRegister(channel, "jobs.run") == 1)
assert(workers.channelDictRegister(channel, "jobs.stop") == 2)
assert(workers.channelDictCount(channel) == 2)
assert(workers.channelDictAddress(channel, 2) == "jobs.stop")

local region, length = bytes.fromString("shared region")
assert(region and length == 13)
assert(bytes.text(region, 1, 6) == "shared")
assert(bytes.accounted() == 13)
assert(workers.channelPushBufferTask(
    channel, 9, "jobs", "inspect", 1, "frame", {region, 1, 6}
))
local _, _, kind, id, module, member, frame, count, attachments =
    workers.channelPop(channel, 0)
assert(kind == 7 and id == 9 and module == "jobs" and member == "inspect")
assert(frame == "frame" and count == 1 and #attachments == 3)
assert(bytes.text(attachments[1], attachments[2], attachments[2] + attachments[3] - 1)
    == "shared")

local builder = assert(bytes.builderNew())
assert(bytes.builderAppend(builder, "prefix"))
local pointer, problem = bytes.builderReserve(builder, 4)
assert(pointer and problem == nil)
local writer = ffi.cast("uint8_t *", pointer)
writer[0], writer[1], writer[2], writer[3] = 100, 97, 116, 97
local accepted, appendProblem = bytes.builderAppend(builder, "refused")
assert(not accepted and appendProblem == "open")
local second, reserveProblem = bytes.builderReserve(builder, 1)
assert(second == nil and reserveProblem == "open")
local frozen, freezeProblem = bytes.builderFreeze(builder)
assert(frozen == nil and freezeProblem == "open")
assert(bytes.builderCommit(builder, 4))
frozen, length = bytes.builderFreeze(builder)
assert(frozen and length == 10 and bytes.text(frozen, 1, length) == "prefixdata")

workers.channelClose(channel)
assert(workers.channelClosed(channel))
workers.channelDestroy(channel)
"#,
    );
    runtime.shutdown().expect("shutdown");
}

#[test]
fn malformed_adapter_values_fail_without_consuming_live_owners() {
    let mut runtime = runtime(b"return nil");
    run(
        &runtime,
        br#"
local workers = require("nupp.workers.native")
local bytes = require("nupp.mem.sharedbytes.native")

local channel = assert(workers.channelCreate())
assert(not workers.channelPush(nil, "header", "body"))
assert(not workers.channelPush(channel, {}, "body"))
assert(not workers.channelPushBufferTask(
    channel, 1, "jobs", "run", 1, "frame", {"not-a-pointer"}
))
assert(not workers.channelPushBufferTask(
    channel, 1, "jobs", "run", 1, "frame", {false, 1, 1}
))
assert(workers.channelCount(channel) == 0)
assert(workers.channelPop(nil, 0) == nil)
assert(workers.channelDictRegister(channel, {}) == nil)
assert(workers.channelDictAddress(nil, 1) == nil)

assert(bytes.text({}, 1, 1) == nil)
assert(bytes.pointer({}) == nil)
assert(bytes.length({}) == nil)
local accepted, problem = bytes.builderAppend({}, "data")
assert(not accepted and problem == nil)
local region, readProblem = bytes.readFile("/definitely/not/a/nupp/file")
assert(region == nil and type(readProblem) == "string")

do
    local first = assert(bytes.fromString("first"))
    local second = assert(bytes.fromString("second"))
    assert(bytes.accounted() == 11)
end
collectgarbage("collect")
collectgarbage("collect")
assert(bytes.accounted() == 0)

do
    local builder = assert(bytes.builderNew())
    assert(bytes.builderAppend(builder, "discarded"))
end
collectgarbage("collect")
collectgarbage("collect")

workers.channelClose(channel)
workers.channelDestroy(channel)
"#,
    );
    runtime.shutdown().expect("shutdown");
}

#[test]
fn cancellation_crosses_the_lua_worker_boundary_without_parent_state_entry() {
    let payload = br#"
local workers = require("nupp.workers.native")
local inbox, outbox = workers.current()
assert(inbox and outbox)
local id, mode = workers.channelPop(inbox, 5000)
assert(id and mode == "wait-for-cancel")
id = tonumber(id)
local shouldRun = workers.workerTaskStart(id)
assert(shouldRun)
assert(workers.channelPush(outbox, "started", id))
local cancelled, deadline
repeat
    cancelled, deadline = workers.workerTaskCheckpoint()
until cancelled
local finished = workers.workerTaskFinish(id)
assert(finished)
-- Match the production scheduler boundary: the task reaches its terminal
-- native state before the reply makes completion observable to the parent.
assert(workers.channelPush(outbox, "cancelled", tostring(deadline)))
"#;
    let mut runtime = runtime(payload);
    run(
        &runtime,
        br#"
local workers = require("nupp.workers.native")
assert(workers.current() == nil)
local inbox = assert(workers.channelCreate())
local outbox = assert(workers.channelCreate())
local worker, problem = workers.workerSpawn(inbox, outbox)
assert(worker, problem)
assert(workers.workerTaskCreate(worker, 41, nil))
assert(workers.workerTaskStatus(worker, 41) == 1)
assert(workers.channelPush(inbox, "41", "wait-for-cancel"))
local state, id = workers.channelPop(outbox, 5000)
assert(state == "started" and id == "41")
assert(workers.workerTaskStatus(worker, 41) == 2)
assert(workers.workerTaskCancel(worker, 41) == 2)
state = workers.channelPop(outbox, 5000)
assert(state == "cancelled")
assert(workers.workerTaskStatus(worker, 41) == 5)
workers.channelClose(inbox)
local status, joinProblem = workers.workerJoin(worker)
assert(status == 0, joinProblem)
workers.channelDestroy(inbox)
workers.channelDestroy(outbox)
"#,
    );
    runtime.shutdown().expect("shutdown");
}

#[test]
fn repeated_worker_teardown_closes_and_joins_every_lane() {
    let payload = br#"
local workers = require("nupp.workers.native")
local inbox, outbox = workers.current()
local header, body = workers.channelPop(inbox, 5000)
assert(header == "ping" and body == "request")
assert(workers.channelPush(outbox, "pong", "reply"))
"#;
    let mut runtime = runtime(payload);
    run(
        &runtime,
        br#"
local workers = require("nupp.workers.native")
for iteration = 1, 32 do
    local inbox = assert(workers.channelCreate())
    local outbox = assert(workers.channelCreate())
    local worker, problem = workers.workerSpawn(inbox, outbox)
    assert(worker, problem)
    assert(workers.channelPush(inbox, "ping", "request"))
    local header, body = workers.channelPop(outbox, 5000)
    assert(header == "pong" and body == "reply")
    workers.channelClose(inbox)
    local status, joinProblem = workers.workerJoin(worker)
    assert(status == 0, joinProblem)
    workers.channelDestroy(inbox)
    workers.channelDestroy(outbox)
end
"#,
    );
    runtime.shutdown().expect("shutdown");
}
