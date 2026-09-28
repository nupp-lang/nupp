use nupp::HostRuntime;

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

// A moved block handed to the push belongs to it whatever happens next, so a
// later entry the push refuses must not free that block twice: once with the
// partly built attachment list and once with the raw array.
#[test]
fn a_refused_region_after_a_moved_block_frees_the_block_once() {
    let mut runtime = runtime(b"return nil");
    run(
        &runtime,
        br#"
local workers = require("nupp.workers.native")
local bytes = require("nupp.mem.sharedbytes.native")
local ffi = require("ffi")
ffi.cdef[[void *malloc(size_t);]]

local function moved(size)
    local box = ffi.new("void *[1]", ffi.C.malloc(size))
    return ffi.string(box, ffi.sizeof("void *"))
end

local channel = assert(workers.channelCreate())
local region = assert(bytes.fromString("abc"))
for round = 1, 64 do
    -- Bytes 1..99 of a 3-byte block.
    assert(not workers.channelPushBufferTask(
        channel, round, "jobs", "run", 1, "frame", {moved(64), 1, 1, region, 1, 99}
    ))
    assert(not workers.channelPushBufferReply(
        channel, round, 1, "frame", {moved(64), 1, 1, region, 3, 2}
    ))
end
assert(workers.channelCount(channel) == 0)
-- The region the refusals borrowed is still the caller's.
assert(bytes.text(region, 1, 3) == "abc")
workers.channelDestroy(channel)
"#,
    );
    runtime.shutdown().expect("shutdown");
}

// Every builder and region entry point checks the handle's metatable, so one
// kind of handle is never read as the other's Rust object, and a channel or
// worker entry point takes only the light userdata those are.
#[test]
fn a_handle_of_the_wrong_kind_is_refused() {
    let mut runtime = runtime(b"return nil");
    run(
        &runtime,
        br#"
local workers = require("nupp.workers.native")
local bytes = require("nupp.mem.sharedbytes.native")

local region = assert(bytes.fromString("abc"))
local builder = assert(bytes.builderNew())
local accepted, problem = bytes.builderAppend(region, string.rep("x", 64))
assert(not accepted and problem == nil, "a region was appended to as a builder")
assert(bytes.builderReserve(region, 64) == nil)
assert(not bytes.builderCommit(region, 0))
assert(bytes.builderFreeze(region) == nil)
assert(bytes.text(builder, 1, 1) == nil)
assert(bytes.length(builder) == nil)
assert(bytes.text(region, 1, 3) == "abc")

assert(not workers.channelPush(region, "header", "body"))
assert(workers.channelPop(region, 0) == nil)
assert(workers.channelCount(region) == 0)
assert(workers.channelClosed(region))
assert(workers.channelDictRegister(region, "jobs.run") == nil)
assert(not workers.workerTaskCreate(region, 1))
assert(workers.workerTaskStatus(builder, 1) == 0)
local spawned, spawnProblem = workers.workerSpawn(region, builder)
assert(spawned == nil and type(spawnProblem) == "string")
workers.channelClose(region)
workers.channelDestroy(region)
workers.workerTaskRelease(region, 1)

assert(bytes.builderAppend(builder, "still a builder"))
assert(bytes.text(region, 1, 3) == "abc")
"#,
    );
    runtime.shutdown().expect("shutdown");
}

// A dropped builder gives its storage back when it is dropped, not whenever the
// collector next finalizes its userdata.
#[test]
fn releasing_a_builder_frees_it_before_any_collection() {
    let mut runtime = runtime(b"return nil");
    run(
        &runtime,
        br#"
local bytes = require("nupp.mem.sharedbytes.native")
collectgarbage("stop")
local builder = assert(bytes.builderNew())
assert(bytes.builderReserve(builder, 8 * 1048576))
assert(bytes.builderCommit(builder, 8 * 1048576))
bytes.builderRelease(builder)
local accepted = bytes.builderAppend(builder, "gone")
assert(not accepted, "a released builder still accepts bytes")
assert(bytes.builderFreeze(builder) == nil)
bytes.builderRelease(builder)
-- A region is not a builder, and releasing one as a builder does nothing.
local region = assert(bytes.fromString("abc"))
bytes.builderRelease(region)
assert(bytes.text(region, 1, 3) == "abc")
collectgarbage("restart")
"#,
    );
    runtime.shutdown().expect("shutdown");
}

// A list the shim refuses before the push hands every moved block it named
// back to the allocator, those after the entry it refused included.
#[cfg(target_os = "macos")]
#[test]
fn a_list_the_shim_refuses_frees_every_moved_block() {
    let mut runtime = runtime(b"return nil");
    run(
        &runtime,
        br#"
local workers = require("nupp.workers.native")
local ffi = require("ffi")
ffi.cdef[[
typedef struct { unsigned blocks_in_use; size_t size_in_use; size_t max_size_in_use; size_t size_allocated; } adapter_malloc_statistics_t;
void malloc_zone_statistics(void *zone, adapter_malloc_statistics_t *stats);
void *malloc(size_t);
]]
ffi.cdef[[void __asan_init(void);]]
-- AddressSanitizer's allocator quarantines freed blocks outside these
-- statistics, and reports a leak or double free itself.
if pcall(function() return ffi.C.__asan_init end) then
    return
end
local stats = ffi.new("adapter_malloc_statistics_t")
local function used()
    collectgarbage("collect")
    ffi.C.malloc_zone_statistics(nil, stats)
    return tonumber(stats.size_in_use)
end
local MB = 1048576
local function moved(size)
    local box = ffi.new("void *[1]", ffi.C.malloc(size))
    return ffi.string(box, ffi.sizeof("void *"))
end

local channel = assert(workers.channelCreate())
local before = used()
-- Large enough that other tests allocating in this process at the same time
-- cannot pass for, or hide, a leaked block.
local first, second = moved(256 * MB), moved(256 * MB)
assert(used() - before >= 384 * MB)
assert(not workers.channelPushBufferTask(
    channel, 1, "jobs", "run", 1, "frame", {first, 1, 1, false, 1, 1, second, 1, 1}
))
local held = (used() - before) / MB
assert(held < 128, ("%d MiB of the refused list's moved blocks are still allocated"):format(held))
workers.channelDestroy(channel)
"#,
    );
    runtime.shutdown().expect("shutdown");
}

// A lane's outbox makes its scheduler wait for room, so joining a lane whose
// replies nobody read must not wait on that scheduler forever; and joining at
// once must not refuse the scheduler its startup acknowledgement.
#[test]
fn joining_a_lane_neither_strands_nor_refuses_its_scheduler() {
    let payload = br#"
local workers = require("nupp.workers.native")
local _, outbox = workers.current()
assert(workers.channelPush(outbox, "ready", ""))
for index = 1, 1100 do
    assert(workers.channelPush(outbox, "reply", tostring(index)))
end
"#;
    let mut runtime = runtime(payload);
    run(
        &runtime,
        br#"
local workers = require("nupp.workers.native")
for _, wait in ipairs({true, false}) do
    local inbox = assert(workers.channelCreate())
    local outbox = assert(workers.channelCreate())
    local worker = assert(workers.workerSpawn(inbox, outbox))
    if wait then
        while workers.channelCount(outbox) < 1024 do end
    end
    workers.channelClose(inbox)
    local status, problem = workers.workerJoin(worker)
    assert(status == 0, problem)
    workers.channelDestroy(inbox)
    workers.channelDestroy(outbox)
end
"#,
    );
    runtime.shutdown().expect("shutdown");
}
