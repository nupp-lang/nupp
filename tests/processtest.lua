-- S5: the platform-neutral process state machine.
--
-- Driven by a fake backend, on purpose. What is being checked here is the lifecycle,
-- the draining and the deadlines -- the policy above the libuv-backed provider -- so
-- the test supplies the platform and the module supplies the behaviour.
local process = require("nupp.io.process")
local suspension = require("nupp.suspension")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function assertTrue(cond, label)
   if not cond then error(label or "expected true", 2) end
end

-- A backend whose child is a script, with backpressure. Nothing here blocks, which is
-- the contract a real backend also has, and the interesting cases are the ones where an
-- operation makes *partial* progress or none:
--
--   inputChunk   how many bytes a write accepts per call, so stdin does not drain in
--                one go and the loop has to come back to it
--   outDelay     how many polls each output stays empty before its next chunk, so a
--                reader has to yield to the other streams rather than sitting on one
--
-- A script where every write is accepted whole and every read is immediately ready
-- cannot tell a combined step from a sequential one, which is what made the first
-- version of these tests pass against a deadlocking implementation.
local function fakeBackend(script)
   local clock = 0
   local self = {}
   local state = {
      polls = 0,
      reads = 0,
      exited = nil,
      killed = false,
      written = {},
      out = script.out or {},
      err = script.err or {},
      outAt = 0,
      errAt = 0,
      closed = {},
      pendingOut = 0,
      stdinClosed = false,
      waits = 0,
      lastWait = nil,
   }
   self.state = state
   function self:advance(ms) clock = clock + ms end
   function self:spawn(_options)
      return "child", "in", "out", "err", 4242
   end
   function self:now() return clock end
   function self:poll(_handle)
      state.polls = state.polls + 1
      -- A fake platform cannot hang, so a state machine that never converges spins here
      -- forever and the suite stops reporting instead of failing. This is the backstop:
      -- no honest test in this file comes near a thousand polls, so passing one means a
      -- loop is not making progress, and a named failure beats a wedged runner.
      if state.polls > 1000 then
         error("the state machine polled without converging; something is looping", 0)
      end
      if state.exited ~= nil then return state.exited end
      if state.killed then
         state.killPolls = (state.killPolls or 0) + 1
         if state.killPolls <= (state.killLag or 0) then
            return nil
         end
         state.exited = process.exited(137, true, false)
         return state.exited
      end
      -- Having stopped reading, it is done: the next poll is what notices.
      if script.stopsReadingAfter ~= nil and #state.written >= script.stopsReadingAfter then
         state.exited = process.exited(script.code or 0, false, false)

         return state.exited
      end
      -- A filter does not finish until its input has. Making the exit depend on stdin
      -- closing is what stops a test passing while stdin is never drained.
      if script.exitNeedsStdin and not state.stdinClosed then
         return nil
      end
      -- Exits once both output scripts are spent and the script says so.
      if script.exitAfter ~= nil and state.polls >= script.exitAfter then
         state.exited = process.exited(script.code or 0, false, false)
         return state.exited
      end
      return nil
   end
   function self:kill(_handle, _force)
      state.kills = (state.kills or 0) + 1
      -- Signalling a child that is already dying is not harmless here: `killPolls` starts
      -- again below, so a caller that re-signals every pump holds the child permanently
      -- one poll away from death. Real platforms absorb that quietly; this one does not,
      -- because a deadline enforced repeatedly is the bug this fake exists to catch.
      if state.kills > 4 then
         error("the child was signalled repeatedly while already terminating", 0)
      end
      state.killed = true
      -- Dying takes a few polls when the script says so, which is what tells a close
      -- that waits from one that reaps immediately.
      state.killPolls = 0
   end
   function self:read(handle, limit)
      state.lastReadLimit = limit
      local list, at
      if handle == "out" then list, at = state.out, "outAt" else list, at = state.err, "errAt" end
      if state.closed[handle] then return nil end
      state.reads = state.reads + 1
      -- Not ready yet: the caller must go and do something else and come back.
      if script.outDelay ~= nil and state.reads % (script.outDelay + 1) ~= 0 then
         return ""
      end
      if script.blockWritesWhileUnread and state.pendingOut > 0 then
         -- Draining is what unblocks the child's next read of stdin.
         state.pendingOut = state.pendingOut - 1
      end
      if state[at] >= #list then
         -- Only ends once the child has, so a reader cannot finish ahead of it.
         if script.eofWhenExited and state.exited == nil then return "" end
         return nil
      end
      -- Answers at most what was asked for, and keeps the rest for the next read --
      -- which is what a pipe does. A fake that returned everything regardless would let
      -- an adapter quietly buffer the surplus and still look correct.
      local chunk = list[state[at] + 1]
      if limit ~= nil and #chunk > limit then
         list[state[at] + 1] = chunk:sub(limit + 1)
         state.lastReadTruncated = true

         return chunk:sub(1, limit)
      end
      state[at] = state[at] + 1

      return chunk
   end
   function self:write(_handle, data)
      if #data == 0 then return 0, false end
      -- Nobody left to read it. A real pipe with no reader fails the write outright;
      -- taking the bytes and dropping them would let a caller believe input it sent
      -- after the child died had been delivered.
      -- Gone, not merely full: the second result is what lets a writer tell "wait for
      -- room" from "there will never be room again".
      if state.exited ~= nil then return 0, true end
      -- A child like `head`: it reads what it wants and stops, long before its input
      -- runs out. It has not exited yet -- nothing has polled it -- so as far as the
      -- pipe knows this is congestion, and only the exit that follows makes it final.
      if script.stopsReadingAfter ~= nil and #state.written >= script.stopsReadingAfter then
         return 0, false
      end
      -- A real pipe stops accepting when the child stops reading, and a child that is
      -- blocked writing output nobody drains has stopped reading. `pendingOut` is that
      -- condition: while output is waiting to be collected, writes take nothing.
      --
      -- This is what makes the deadlock real. A sequential implementation writes all
      -- the input first, gets zero, and never progresses; only one that also drains the
      -- outputs frees the child to accept more.
      if script.blockWritesWhileUnread and state.pendingOut > 0 then
         return 0, false
      end
      local limit = script.inputChunk or #data
      local taken = data:sub(1, limit)
      state.written[#state.written + 1] = taken
      -- Producing output is what the child does with input, and that output then
      -- blocks the next write until somebody reads it.
      if script.blockWritesWhileUnread then
         state.pendingOut = state.pendingOut + 1
      end
      return #taken, false
   end
   function self:closeStream(handle)
      -- A refusal that names no reason at all.
      if state.silentRefuseClose == handle then
         return false
      end
      -- Still ours: nothing was given up, so another attempt is right.
      if state.refuseClose == handle then
         return false, "the platform declined to close it"
      end
      state.closed[handle] = true
      if handle == "in" then state.stdinClosed = true end
      -- Given up, and complained anyway -- the combination POSIX really produces and
      -- the one a single boolean cannot express.
      if state.closeComplains == handle then
         return true, "the platform closed it and complained"
      end
      return true
   end
   function self:reap(_handle)
      if state.refuseReap then
         state.refuseReap = false
         return false, "the platform declined to reap it"
      end
      state.reaped = true
      -- Released the child and complained anyway. Not `waitpid` itself -- that answers
      -- the pid on success and reports an error separately -- but a seam-level case a
      -- native handle layer really produces, when it gives ownership up and has
      -- something to say about the cleanup around it.
      if state.reapComplains then
         state.reapComplains = false
         return true, "the platform reaped it and complained"
      end
      -- A refusal that names no reason at all.
      if state.reapSilentlyRefuses then
         state.reapSilentlyRefuses = false
         state.reaped = false
         return false
      end
      return true
   end
   function self:waitReady(interest, timeoutMs)
      -- Counted and recorded, because the two things worth knowing about this call are
      -- that it happens when there is no handler and that it never happens when there
      -- is. A fake that only returned 0 could not tell either.
      state.waits = state.waits + 1
      -- The same backstop `poll` has. A blocking wait that never converges would sit
      -- here advancing a fake clock forever, and the suite would stop reporting rather
      -- than fail; no honest test needs anything like this many sleeps.
      if state.waits > 1000 then
         error("the state machine waited without converging; something is looping", 0)
      end
      state.lastWait = {
         timeoutMs = timeoutMs,
         child = interest.child,
         reads = #interest.read,
         writes = #interest.write,
      }
      if suspension.handled() then
         error("waitReady was called with a handler installed; the frame should have parked", 0)
      end
      -- Sleeping is what the real one does, so the fake advances the clock by exactly
      -- what it was given. That is what lets a deadline arrive through waiting alone,
      -- and what would expose a budget that overshot the time remaining.
      clock = clock + timeoutMs

      return 0
   end
   return self
end

local M = {}

function M.drainsBothPipesAndWaits()
   local backend = fakeBackend({
      out = {"hello ", "world"},
      err = {"warning"},
      exitAfter = 1,
      code = 0,
   })
   local child = process.spawnOn(backend, {args = {"echo"}})
   local result = assert(child:communicate())
   child:close()
   assertEq(result.output, "hello world", "stdout was drained to the end")
   assertEq(result.errorOutput, "warning", "and stderr alongside it, not after it")
   assertEq(result.exit.exitCode, 0, "the exit came back")
   assertTrue(result:succeeded(), "and it succeeded")
end

function M.writesAndClosesStandardInput()
   local backend = fakeBackend({out = {"ok"}, exitAfter = 1})
   local child = process.spawnOn(backend, {args = {"cat"}})
   local result = assert(child:communicate({input = "payload"}))
   child:close()
   assertEq(backend.state.written[1], "payload", "the input went")
   assertTrue(backend.state.closed["in"], "and stdin was closed, which is how EOF is sent")
   assertEq(result.output, "ok", "the output came back")
end

function M.aKilledChildDidNotSucceed()
   local backend = fakeBackend({out = {}, exitAfter = nil})
   local child = process.spawnOn(backend, {args = {"sleep"}})
   assertTrue(child:isRunning(), "it is running")
   assertTrue(child:kill(true), "the kill was requested")
   local exit = child:wait()
   child:close()
   assertTrue(exit.killed, "it was killed")
   assertEq(exit:succeeded(), false,
      "a killed child never succeeded, whatever status was reported")
end

function M.aDeadlineIsMeasuredFromTheStart()
   local backend = fakeBackend({out = {}, exitAfter = nil})
   local child = process.spawnOn(backend, {args = {"sleep"}, timeoutMs = 100})
   -- Time passes before anything waits, which is the case a deadline measured from
   -- the first wait would get wrong.
   backend:advance(150)
   local exit = child:wait()
   child:close()
   assertTrue(exit.killed, "the deadline killed it")
   assertTrue(exit.timedOut, "and said that is why")
   assertEq(exit:succeeded(), false, "a timeout is not a success")
end

function M.aDeadlineThatHasNotPassedDoesNotFire()
   local backend = fakeBackend({out = {"done"}, exitAfter = 1})
   local child = process.spawnOn(backend, {args = {"quick"}, timeoutMs = 1000})
   backend:advance(10)
   local result = assert(child:communicate())
   child:close()
   assertEq(result.output, "done", "it finished on its own")
   assertEq(result.exit.timedOut, false, "well inside its deadline")
   assertTrue(result:succeeded(), "and succeeded")
end

function M.closingEndsAChildStillRunning()
   local backend = fakeBackend({out = {}, exitAfter = nil})
   local child = process.spawnOn(backend, {args = {"sleep"}})
   child:close()
   assertTrue(backend.state.killed,
      "a child outliving the scope that started it is a leak nobody sees")
   assertTrue(backend.state.reaped, "and it was released")
end

function M.closingIsIdempotent()
   local backend = fakeBackend({out = {}, exitAfter = 1})
   local child = process.spawnOn(backend, {args = {"true"}})
   child:wait()
   child:close()
   child:close()
   assertTrue(backend.state.reaped, "closed once, and again without complaint")
end

function M.readsAnswerNilAtEndOfStream()
   local backend = fakeBackend({out = {"only"}, exitAfter = 1})
   local child = process.spawnOn(backend, {args = {"echo"}})
   assertEq(child.stdout:read(65536), "only", "the one chunk")
   assertEq(child.stdout:read(65536), "", "then end of stream")
   assertTrue(child.stdout:isEOF(), "and it says so")
   child:close()
end

function M.waitingWorksUnderAHandler()
   -- The point of the whole exercise: the same call parks under a scheduler and
   -- blocks without one. Here a handler answers by driving the pumps itself.
   local drove = 0
   local handler = {
      park = function(_self, waiting)
         while not waiting:ready() do
            drove = drove + 1
            suspension.poll()
            if drove > 100 then error("handler gave up", 0) end
         end
      end,
   }
   local backend = fakeBackend({out = {"handled"}, exitAfter = 2})
   local installation = suspension.install(handler)
   local child = process.spawnOn(backend, {args = {"echo"}})
   local result = assert(child:communicate())
   child:close()
   installation:release()
   assertEq(result.output, "handled", "the output came back through a handled wait")
   assertTrue(drove > 0, "and the handler is what drove it")
end

function M.makesProgressOnAllThreeStreamsTogether()
   -- The case a sequential `communicate` deadlocks on. Input is taken four bytes at a
   -- time, so it cannot all be written up front; both outputs go quiet between chunks,
   -- so neither can be drained to the end before the other is touched; and neither
   -- reaches end of stream until the child exits, which it does not do until its input
   -- is closed. Only a loop that attempts all three every pass gets through it.
   local backend = fakeBackend({
      inputChunk = 4,
      outDelay = 1,
      blockWritesWhileUnread = true,
      exitNeedsStdin = true,
      out = {"one", "two", "three"},
      err = {"a", "b"},
      eofWhenExited = true,
      exitAfter = 6,
      code = 0,
   })
   local child = process.spawnOn(backend, {args = {"filter"}})
   local result = assert(child:communicate({input = "a longer payload than one chunk"}))
   child:close()
   assertEq(result.output, "onetwothree", "stdout arrived in full")
   assertEq(result.errorOutput, "ab", "and so did stderr, interleaved rather than after")
   assertEq(table.concat(backend.state.written), "a longer payload than one chunk",
      "every byte of input went, four at a time")
   assertTrue(#backend.state.written > 1,
      "and it took several writes, so backpressure was really exercised")
   assertTrue(result:succeeded(), "the child finished")
end

function M.drainingUnderAHandlerNeverBlocksThePlatform()
   -- `communicate` is the wait with its own path, and it needs the same guarantee as
   -- the others: under a scheduler it parks so the frame keeps running. Without this,
   -- removing the check in `awaitTick` broke nothing that anyone would notice.
   local backend = fakeBackend({
      inputChunk = 4,
      outDelay = 1,
      blockWritesWhileUnread = true,
      exitNeedsStdin = true,
      out = {"one", "two"},
      err = {"a"},
      eofWhenExited = true,
      exitAfter = 6,
      code = 0,
   })
   local child = process.spawnOn(backend, {args = {"filter"}})
   local handler = {
      park = function(_self, waiting)
         local spins = 0
         while not waiting:ready() do
            spins = spins + 1
            suspension.poll()
            if spins > 100 then error("the drain never resolved", 0) end
         end
      end,
   }
   local installation = suspension.install(handler)
   local result = assert(child:communicate({input = "a longer payload than one chunk"}))
   child:close()
   installation:release()
   assertEq(result.output, "onetwo", "everything arrived")
   assertEq(result.errorOutput, "a", "on both streams")
   assertTrue(result:succeeded(), "and the child finished")
   assertEq(backend.state.waits, 0, "without ever asking the platform to block")
end

function M.communicateClosesStdinWhenTheChildEndsEarly()
   -- A child that has already exited will never read again, so the rest of the input is
   -- undeliverable. Returning with its stdin still open would leave the pipe held by a
   -- caller who was told the conversation was over.
   local backend = fakeBackend({
      inputChunk = 4,
      stopsReadingAfter = 2,
      out = {"bye"},
      err = {},
      eofWhenExited = true,
      code = 0,
   })
   local child = process.spawnOn(backend, {args = {"quitter"}})
   local payload = "far more input than this child will ever read"
   local result = assert(child:communicate({input = payload}))
   -- Checked before `close`, which shuts every stream on its own account and would
   -- report success here however `communicate` had left things.
   local closedOnTheWayOut = backend.state.closed["in"]
   local delivered = #table.concat(backend.state.written)
   child:close()
   assertEq(result.output, "bye", "what it did say arrived")
   assertTrue(delivered < #payload,
      "the child really did end with input still undelivered")
   assertTrue(closedOnTheWayOut, "and communicate closed its stdin before returning")
end

function M.aGoneStdinIsLeftOutOfTheWriteInterest()
   -- A broken pipe polls permanently ready, so a gone stdin left in the write set
   -- would make every wait return instantly and the drain loop spin until the
   -- outputs reach their end. Once the far end has gone there is nothing left to
   -- wait for on that stream, and the interest must say so.
   local backend = fakeBackend({
      inputChunk = 1,
      stopsReadingAfter = 1,
      outDelay = 2,
      out = {"data"},
      err = {},
      eofWhenExited = true,
      code = 0,
   })
   local child
   local waitedOnGoneStdin = false
   local baseWait = backend.waitReady
   backend.waitReady = function(self, interest, timeoutMs)
      if child ~= nil and child.stdin ~= nil and child.stdin.gone and #interest.write > 0 then
         waitedOnGoneStdin = true
      end
      return baseWait(self, interest, timeoutMs)
   end
   child = process.spawnOn(backend, {args = {"head"}})
   local result = assert(child:communicate({input = "abc"}))
   child:close()
   assertEq(result.output, "data", "the outputs were still drained to the end")
   assertTrue(not waitedOnGoneStdin,
      "and no wait named a stdin whose far end had gone")
end

function M.aStepThatAnswersFailureIsNotMistakenForSuccess()
   -- There are two ways to fail in a teardown and `pcall` sees only one. A step that
   -- raises is caught; a step that answers `false` and a reason returns perfectly
   -- normally, and a teardown judging only the call would read it as success -- then
   -- go on to mark the child released with a stream or a handle still held.
   -- Through the declared contract, not around it: `Backend.reap` answers
   -- `(boolean, string?)`, so the fake declining is something a real platform can do
   -- too. A test that could only be written by ignoring the types would be proving
   -- behaviour no backend is able to produce.
   local backend = fakeBackend({out = {}, err = {}, exitAfter = 1, code = 0})
   backend.state.refuseReap = true
   local child = process.spawnOn(backend, {args = {"quiet"}})
   local ok, reported = pcall(function() child:close() end)
   assertTrue(not ok, "the answered failure was reported, not swallowed")
   assertTrue(tostring(reported):find("declined", 1, true) ~= nil,
      "and it said what the platform said, got: " .. tostring(reported))
   assertTrue(not backend.state.reaped, "nothing was marked released")
   child:close()
   assertTrue(backend.state.reaped, "and the retry finished it")
end

function M.pollTakesNoMoreThanItWasAskedForAndLosesNothing()
   -- The shared `nupp.io.Reader` promises "at most `count`", and the surplus has to
   -- survive somewhere. Keeping it in the pipe rather than in a buffer beside this
   -- record is what leaves end of stream and closedness with one home, so what matters
   -- is not that the argument was forwarded but that two small reads reconstruct what
   -- one large one would have given.
   local backend = fakeBackend({out = {"abcdefgh"}, err = {}, eofWhenExited = true, exitAfter = 9, code = 0})
   local child = process.spawnOn(backend, {args = {"talkative"}})
   local first = child.stdout:poll(4)
   assertEq(first, "abcd", "the first read took exactly its limit")
   local second = child.stdout:poll(4)
   assertEq(second, "efgh", "and the next took up where it left off")
   assertEq(first .. second, "abcdefgh", "losing nothing between them")
   child:close()
end

function M.aNonPositiveLimitReadsOneByte()
   -- What `nupp.io.Reader` says a non-positive count does, settled here so a zero or a
   -- minus one never reaches a native size conversion -- where it is either an empty
   -- read that reads as end of stream or an enormous one.
   local backend = fakeBackend({out = {"abcdefgh"}, err = {}, eofWhenExited = true, exitAfter = 9, code = 0})
   local child = process.spawnOn(backend, {args = {"talkative"}})
   assertEq(child.stdout:poll(0), "a", "zero read one byte")
   assertEq(backend.state.lastReadLimit, 1, "and the platform was asked for one")
   assertEq(child.stdout:poll(-5), "b", "a negative one did too")
   assertEq(backend.state.lastReadLimit, 1, "asking for one again")
   child:close()
end

function M.aComplainingStreamCloseStillReapsTheChild()
   -- The reason every step is attempted. A stream that released its descriptor and
   -- complained used to stop the teardown before the reap, leaving a child handle held
   -- by a process that had finished with it -- and under an automatic drop there is no
   -- binding left to retry through, so unreaped would have meant unreaped for good.
   local backend = fakeBackend({out = {}, err = {}, exitAfter = 1, code = 0})
   backend.state.closeComplains = "in"
   local child = process.spawnOn(backend, {args = {"quiet"}})
   local ok, reported = pcall(function() child:close() end)
   assertTrue(not ok, "the complaint was still reported")
   assertTrue(tostring(reported):find("complained", 1, true) ~= nil,
      "got: " .. tostring(reported))
   assertTrue(backend.state.reaped, "and the child was reaped anyway")
   assertTrue(child.childReleased, "which the child records as its handle being gone")
   assertTrue(child.reaped, "and with every piece released, the teardown is complete")
end

function M.aRunningChildIsNotReapedByAFailedTeardown()
   -- The one case where stopping short is right: a child that has not exited is not
   -- reapable, and asking would be the error rather than a leak. The kill below is
   -- refused, so the child never ends.
   local backend = fakeBackend({out = {}, err = {}, exitAfter = nil, code = 0})
   backend.state.killLag = 2
   local child = process.spawnOn(backend, {args = {"stubborn"}})
   local realKill = backend.kill
   function backend:kill(handle, force)
      error("the platform refused to signal it", 0)
   end
   local ok = pcall(function() child:close() end)
   assertTrue(not ok, "the refusal was reported")
   assertTrue(not backend.state.reaped, "and nothing reaped a child that never exited")
   assertTrue(not child.reaped, "so the teardown is not complete")
   -- Retrying with a platform that cooperates finishes the job.
   backend.kill = realKill
   backend.state.killLag = 0
   child:close()
   assertTrue(backend.state.reaped and child.reaped, "the retry finished it")
end

function M.aReapThatReleasedAndComplainedIsStillAReap()
   -- The pid is gone whatever the platform thought of the operation, and asking again
   -- would wait on whatever has since been given that number. So ownership decides
   -- `reaped`, exactly as it decides a stream's `closed`, and the complaint is carried.
   local backend = fakeBackend({out = {}, err = {}, exitAfter = 1, code = 0})
   backend.state.reapComplains = true
   local child = process.spawnOn(backend, {args = {"quiet"}})
   local ok, reported = pcall(function() child:close() end)
   assertTrue(not ok, "the complaint was reported")
   assertTrue(tostring(reported):find("complained", 1, true) ~= nil,
      "carrying the platform's words, got: " .. tostring(reported))
   assertTrue(child.reaped, "and the child counts as released, because it was")
   local calls = 0
   local realReap = backend.reap
   function backend:reap(handle)
      calls = calls + 1
      return realReap(self, handle)
   end
   child:close()
   assertEq(calls, 0, "a released child is never offered to the platform again")
end

function M.aRefusalWithNoReasonIsStillARefusal()
   -- The contract asks for a reason. A backend that gives none must not be read as
   -- success: returning quietly here leaves the caller believing a stream shut, or a
   -- child released, when neither happened.
   local backend = fakeBackend({out = {}, err = {}, exitAfter = 1, code = 0})
   backend.state.silentRefuseClose = "in"
   local child = process.spawnOn(backend, {args = {"quiet"}})
   local ok, reported = pcall(function() child.stdin:release() end)
   assertTrue(not ok, "the silent refusal was still an error")
   assertTrue(tostring(reported):find("did not say why", 1, true) ~= nil,
      "and said so, got: " .. tostring(reported))
   assertTrue(not child.stdin.closed, "with the stream still open, since it is still ours")

   local other = fakeBackend({out = {}, err = {}, exitAfter = 1, code = 0})
   other.state.reapSilentlyRefuses = true
   local second = process.spawnOn(other, {args = {"quiet"}})
   local reapOk, reapReported = pcall(function() second:close() end)
   assertTrue(not reapOk, "and the same for a reap")
   assertTrue(tostring(reapReported):find("did not say why", 1, true) ~= nil,
      "got: " .. tostring(reapReported))
   assertTrue(not second.reaped, "the child is not released")
   second:close()
end

function M.aStreamReleasedWithAComplaintStaysClosed()
   -- `close(2)` may report a problem having already given the descriptor up. Treating
   -- that as "still open" is not a harmless conservatism: the number is free for the
   -- next open in the process, so a retry closes whatever has since been given it.
   -- Ownership decides `closed`; the complaint is only reported.
   -- Both records carry the rule, and both are checked: a writer and a reader have
   -- separate `close` bodies, so one of them getting this right proves nothing about
   -- the other.
   for _, which in ipairs({"in", "out"}) do
      local backend = fakeBackend({out = {}, err = {}, exitAfter = 1, code = 0})
      backend.state.closeComplains = which
      local child = process.spawnOn(backend, {args = {"quiet"}})
      local stream = which == "in" and child.stdin or child.stdout
      local ok, reported = pcall(function() stream:release() end)
      assertTrue(not ok, which .. ": the complaint was reported")
      assertTrue(tostring(reported):find("complained", 1, true) ~= nil,
         which .. ": carrying the platform's words, got: " .. tostring(reported))
      assertTrue(stream.closed,
         which .. ": this end is shut, because the descriptor really was given up")
      -- The second call must do nothing at all: no second closeStream, no second raise.
      local calls = 0
      local realClose = backend.closeStream
      function backend:closeStream(handle)
         calls = calls + 1
         return realClose(self, handle)
      end
      stream:close()
      assertEq(calls, 0,
         which .. ": a released descriptor is never offered to the platform again")
      child:close()
   end
end

function M.aRefusedStreamCloseBecomesAnErrorAtTheStreamEdge()
   -- `Backend.closeStream` answers a status; `Reader.close` and `Writer.close` answer
   -- nothing, because those signatures are tecs's. The status has to become an error
   -- somewhere, and here is that seam -- a close that quietly returned would leave the
   -- descriptor open with the stream believing itself shut.
   local backend = fakeBackend({out = {}, err = {}, exitAfter = 1, code = 0})
   backend.state.refuseClose = "in"
   local child = process.spawnOn(backend, {args = {"quiet"}})
   local ok, reported = pcall(function() child.stdin:release() end)
   assertTrue(not ok, "the refusal was raised")
   assertTrue(tostring(reported):find("declined", 1, true) ~= nil,
      "carrying the platform's reason, got: " .. tostring(reported))
   assertTrue(not child.stdin.closed, "and this end is still open, not pretending")
   backend.state.refuseClose = nil
   child.stdin:close()
   assertTrue(child.stdin.closed, "the retry closed it for real")
   child:close()
end

function M.closeCanBeRetriedAfterItFails()
   -- `reaped` means the whole teardown finished. Setting it before the work is done
   -- makes a failed teardown indistinguishable from a finished one, and the retry that
   -- would have fixed it returns immediately instead.
   --
   -- The refusal is *returned*, not raised. `reap` is return-only precisely so that a
   -- caller can tell a child still theirs from one already gone; an error carries no
   -- release state, so asserting a retry is safe after one would be asserting something
   -- unknowable.
   local backend = fakeBackend({out = {}, err = {}, exitAfter = 1, code = 0})
   backend.state.refuseReap = true
   local child = process.spawnOn(backend, {args = {"quiet"}})
   local ok = pcall(function() child:close() end)
   assertTrue(not ok, "the failure was reported rather than swallowed")
   assertTrue(not backend.state.reaped, "and nothing was reaped")
   assertTrue(not child.childReleased, "the child is still ours, which is why a retry is safe")
   child:close()
   assertTrue(backend.state.reaped, "the retry went through and finished the job")
end

function M.aBackendThatRaisesIsReadAsHavingReleased()
   -- Breaking the return-only contract. An error says something went wrong and nothing
   -- about whether the handle is still ours, so the state machine takes the only
   -- reading that cannot do unbounded harm: gone. Leaking one descriptor or one pid is
   -- bounded; closing whatever has since been given that number is not.
   local backend = fakeBackend({out = {"x"}, err = {}, exitAfter = 1, code = 0})
   function backend:closeStream(handle)
      error("the platform threw instead of answering", 0)
   end
   local child = process.spawnOn(backend, {args = {"quiet"}})
   local ok, reported = pcall(function() child.stdin:release() end)
   assertTrue(not ok, "the broken contract was still reported")
   assertTrue(tostring(reported):find("raised", 1, true) ~= nil,
      "and named as a raise, got: " .. tostring(reported))
   assertTrue(child.stdin.closed,
      "with the descriptor treated as gone, since nothing said otherwise")

   local other = fakeBackend({out = {}, err = {}, exitAfter = 1, code = 0})
   function other:reap(handle)
      error("the platform threw instead of answering", 0)
   end
   local second = process.spawnOn(other, {args = {"quiet"}})
   local reapOk = pcall(function() second:close() end)
   assertTrue(not reapOk, "the same for a reap")
   assertTrue(second.childReleased, "the child is treated as gone too")
end

function M.aRaiseWithNothingToSayIsStillAFailure()
   -- `error(nil)` is a real thing to do, and it arrives as a failure carrying nothing.
   -- Stored as it comes, it reads as no failure at all, and a teardown that had just
   -- caught a broken backend would report a clean close.
   local backend = fakeBackend({out = {"x"}, err = {}, exitAfter = 1, code = 0})
   function backend:closeStream(handle)
      error(nil)
   end
   local child = process.spawnOn(backend, {args = {"quiet"}})
   local ok, reported = pcall(function() child.stdin:release() end)
   assertTrue(not ok, "the silent raise was still an error")
   assertTrue(tostring(reported):find("without saying why", 1, true) ~= nil,
      "and said so, got: " .. tostring(reported))

   -- And through the teardown, where a nil would have been stored as the first error
   -- and then compared against nil to decide whether anything went wrong at all.
   local other = fakeBackend({out = {}, err = {}, exitAfter = 1, code = 0})
   function other:reap(handle)
      error(nil)
   end
   local second = process.spawnOn(other, {args = {"quiet"}})
   local reapOk, reapReported = pcall(function() second:close() end)
   assertTrue(not reapOk, "a reap that raised nothing was reported")
   assertTrue(tostring(reapReported):find("without saying why", 1, true) ~= nil,
      "got: " .. tostring(reapReported))
   -- Complete, and rightly so: the conservative reading says the child was released,
   -- every stream was, and the pump is gone -- there is nothing left to hold. The
   -- failure is reported once and a retry has no work, which is the difference between
   -- an aggregate derived from the pieces and one that just tracks whether anything
   -- ever went wrong.
   assertTrue(second.childReleased, "the child is treated as gone")
   assertTrue(second.reaped, "so nothing is still held and the teardown is complete")

   -- And through the generic step judge, which is a separate path: a stream close
   -- synthesizes at its own edge, so only a step like the kill reaches `attempt` with
   -- nothing to say.
   local third = fakeBackend({out = {}, err = {}, exitAfter = nil, code = 0})
   third.state.killLag = 2
   function third:kill(handle, force)
      error(nil)
   end
   local running = process.spawnOn(third, {args = {"stubborn"}})
   local killOk, killReported = pcall(function() running:close() end)
   assertTrue(not killOk, "a step that raised nothing was still a failure")
   assertTrue(tostring(killReported):find("without saying why", 1, true) ~= nil,
      "got: " .. tostring(killReported))
end

function M.aWriteEndsWhenTheChildDoesRatherThanWaitingForever()
   -- Zero bytes written means two opposite things, and a writer that cannot tell them
   -- apart waits for room that will never come. When the child is gone the write stops
   -- and reports what actually went.
   local backend = fakeBackend({inputChunk = 4, out = {}, err = {}, exitAfter = 1, code = 0})
   local child = process.spawnOn(backend, {args = {"quitter"}})
   -- Polled first, so the child has genuinely exited before the write starts.
   child:wait()
   local payload = "input for a child that is no longer there"
   local sent = child.stdin:send(payload)
   assertEq(sent, 0, "nothing went, because nobody was reading")
   assertTrue(child.stdin.gone, "and the writer knows the far end has gone")
   assertTrue(not child.stdin.closed,
      "while this end is still open, since the descriptor is still ours to close")
   child:close()
   assertTrue(backend.state.closed["in"], "and closing the child does release it")
end

function M.genericWriterCodeCanTellNoRoomYetFromNoRoomEver()
   -- The loop every non-blocking writer is: offer, and on zero decide whether to come
   -- back. Without `isGone` the two zeroes -- no room yet, no reader ever -- are
   -- indistinguishable, and the only safe reading of them is "retry", forever.
   --
   -- This asserts the behaviour, not a contract, and cannot assert more from here:
   -- the suite is plain Lua, where there is nothing to annotate against, and the
   -- readiness-capable interface that `streams.Writer` would have become is not
   -- designed yet. So the claim is narrow -- these operations answer what a drain loop
   -- needs -- and when that interface exists this is the shape it has to require.
   local function drainInto(writer, data)
      local sent, spins = 0, 0
      while sent < #data do
         spins = spins + 1
         if spins > 200 then
            return sent, "spun"
         end
         if writer:isGone() or writer:isClosed() then
            return sent, "gone"
         end
         sent = sent + writer:offer(data:sub(sent + 1))
      end

      return sent, "complete"
   end

   local backend = fakeBackend({inputChunk = 4, out = {}, err = {}, exitAfter = 1, code = 0})
   local child = process.spawnOn(backend, {args = {"quitter"}})
   child:wait()
   local sent, how = drainInto(child.stdin, "input for a child that is no longer there")
   child:close()
   assertEq(how, "gone", "the loop ended because it was told to, not by giving up")
   assertEq(sent, 0, "having sent nothing to a child that had already left")
end

function M.aPartialWriteKeepsWhatWentBeforeTheChildLeft()
   -- The bytes accepted before the far end went are delivered, and must be reported.
   -- Losing them would make a caller resend what the child already acted on.
   local backend = fakeBackend({inputChunk = 4, stopsReadingAfter = 2, out = {}, err = {}, code = 0})
   local child = process.spawnOn(backend, {args = {"head"}})
   local sent = child.stdin:send("far more input than this child will ever read")
   child:close()
   assertEq(sent, 8, "the two chunks that landed before it stopped reading")
   assertEq(table.concat(backend.state.written), "far more",
      "and those are the bytes the child actually got")
end

function M.aRefusedStreamCloseCanBeRetried()
   -- `closed` is what the platform has done, not what was asked of it. Set on a refusal
   -- it would strand the descriptor, since every later attempt returns at once.
   --
   -- Returned rather than raised, for the reason `closeStream` is return-only: a raise
   -- carries no release state, so retrying after one would be guessing.
   local backend = fakeBackend({out = {"x"}, err = {}, exitAfter = 1, code = 0})
   backend.state.refuseClose = "in"
   local child = process.spawnOn(backend, {args = {"quiet"}})
   local ok = pcall(function() child.stdin:release() end)
   assertTrue(not ok, "the refusal was reported")
   backend.state.refuseClose = nil
   assertTrue(not child.stdin.closed, "and this end is still open, not pretending")
   child.stdin:close()
   assertTrue(child.stdin.closed and backend.state.closed["in"],
      "the retry closed it for real")
   child:close()
end

function M.closeReenteredFromItsOwnTeardownJustReturns()
   -- The teardown drives the pump, and something the pump drives can call back in. That
   -- is the same frame arriving twice, not two callers: it cannot wait for itself, and
   -- one teardown is enough, so the only right answer is to return.
   local backend = fakeBackend({out = {}, err = {}, exitAfter = nil, code = 0})
   backend.state.killLag = 3
   local child = process.spawnOn(backend, {args = {"slow"}})
   local reentries = 0
   local realPoll = backend.poll
   function backend:poll(handle)
      if child.closing and reentries < 3 then
         reentries = reentries + 1
         -- Straight back in, on this very coroutine.
         child:close()
      end
      return realPoll(self, handle)
   end
   -- Run inside a coroutine rather than on the main one. On the main thread
   -- `coroutine.running()` is nil, so a state machine that never recorded the owner at
   -- all would look identical to one that did; here the two differ.
   local frame = coroutine.create(function()
      child:close()
   end)
   local ok, err = coroutine.resume(frame)
   assertTrue(ok, "the teardown finished: " .. tostring(err))
   assertTrue(reentries > 0, "the teardown really was reentered")
   assertEq(backend.state.kills, 1, "and did not start over: one kill")
   assertTrue(backend.state.reaped, "one reap, and the child released")
end

function M.aSecondCloserWithNothingToScheduleItIsToldSoRatherThanHanging()
   -- Two coroutines, no scheduler. The second can only have reached here by being
   -- resumed from inside the first teardown, so the frame it would be waiting on is
   -- below it on the stack and cannot run until it returns. That is a hang, and a hang
   -- is the one answer a close must never give.
   local backend = fakeBackend({out = {}, err = {}, exitAfter = nil, code = 0})
   backend.state.killLag = 3
   local child = process.spawnOn(backend, {args = {"slow"}})
   local secondResult = nil
   local second = coroutine.create(function()
      secondResult = select(2, pcall(function() child:close() end))
   end)
   local realPoll = backend.poll
   function backend:poll(handle)
      -- Reached from inside the first close's wait, which is exactly the situation.
      if child.closing and coroutine.status(second) == "suspended" then
         assert(coroutine.resume(second))
      end
      return realPoll(self, handle)
   end
   child:close()
   assertTrue(backend.state.reaped, "the first caller finished its teardown")
   assertTrue(secondResult ~= nil and tostring(secondResult):find("another coroutine", 1, true) ~= nil,
      "and the second was told why it could not wait, got: " .. tostring(secondResult))
end

function M.aSecondCloserUnderASchedulerWaitsForTheTeardown()
   -- With something to run the other frame, waiting is right: reporting the child
   -- released while its teardown is still going would let the owner's scope end, and
   -- the scope ending runs structural drop -- leaving the next toucher on a handle that has
   -- already been given back.
   local backend = fakeBackend({out = {}, err = {}, exitAfter = nil, code = 0})
   backend.state.killLag = 3
   local child = process.spawnOn(backend, {args = {"slow"}})
   local order = {}
   -- A round-robin small enough to read: park yields, the driver resumes whoever is
   -- not finished, and `suspension.poll` drives the readiness pumps between rounds.
   local handler = {
      park = function(_self, waiting)
         while not waiting:ready() do
            coroutine.yield()
         end
      end,
   }
   local function closer(name)
      return coroutine.create(function()
         local installation = suspension.install(handler)
         order[#order + 1] = name .. " entered"
         order[name .. " sawTeardown"] = child.closing
         child:close()
         order[#order + 1] = name .. " returned"
         installation:release()
      end)
   end
   local first = closer("first")
   assert(coroutine.resume(first))
   -- Started only once the first is parked mid-teardown, which is the case worth
   -- testing; starting both at once would usually just serialise them.
   local second = closer("second")
   local rounds = 0
   while coroutine.status(first) ~= "dead" or coroutine.status(second) ~= "dead" do
      rounds = rounds + 1
      if rounds > 200 then
         error("the closers never finished; order so far: " .. table.concat(order, ", "), 0)
      end
      if coroutine.status(first) == "suspended" then assert(coroutine.resume(first)) end
      if coroutine.status(second) == "suspended" then assert(coroutine.resume(second)) end
      suspension.poll()
   end
   assertTrue(order["second sawTeardown"], "the second really did arrive mid-teardown")
   assertEq(backend.state.kills, 1, "the child was ended once, not once per caller")
   assertTrue(backend.state.reaped, "and released")
   assertEq(order[#order], "second returned",
      "with the second returning only after the teardown it waited on")
end

function M.waitingWithoutAHandlerAsksThePlatformToSleep()
   -- The point of `waitReady`. With nobody to yield to, a wait has to become a sleep in
   -- the kernel; a state machine that instead polled a non-blocking backend would get
   -- the same answer as fast as the CPU could ask for it.
   local backend = fakeBackend({out = {"done"}, err = {}, exitAfter = 3, code = 0})
   local child = process.spawnOn(backend, {args = {"quiet"}})
   local exit = child:wait()
   child:close()
   assertTrue(exit.exitCode == 0, "it finished")
   assertTrue(backend.state.waits > 0, "and got there by waiting, not by spinning")
   assertEq(backend.state.lastWait.child, "child", "the child is what it waited on")
   assertEq(backend.state.lastWait.reads, 0,
      "and not its output, which nobody is reading and which is therefore always ready")
end

function M.waitingUnderAHandlerNeverBlocksThePlatform()
   -- The other half, and the one that matters under a scheduler: the frame has to keep
   -- running, so the state machine parks and the handler decides when to come back. The
   -- fake raises if this is got wrong, so reaching the end is the assertion.
   local backend = fakeBackend({out = {"done"}, err = {}, exitAfter = 3, code = 0})
   local child = process.spawnOn(backend, {args = {"quiet"}})
   local handler = {
      park = function(_self, waiting)
         local spins = 0
         while not waiting:ready() do
            spins = spins + 1
            suspension.poll()
            if spins > 100 then error("the wait never resolved", 0) end
         end
      end,
   }
   local installation = suspension.install(handler)
   local exit = child:wait()
   child:close()
   installation:release()
   assertTrue(exit.exitCode == 0, "it finished")
   assertEq(backend.state.waits, 0, "and never asked the platform to block")
end

function M.aBlockingWaitNeverSleepsPastTheDeadline()
   -- A wait longer than what is left would report the timeout late by however much it
   -- overslept. The fake advances its clock by exactly the budget it is handed, so the
   -- deadline can only be honoured on time if every budget respected it.
   local backend = fakeBackend({out = {}, err = {}, exitAfter = nil})
   local child = process.spawnOn(backend, {args = {"stubborn"}, timeoutMs = 30})
   local exit = child:wait()
   -- Read before closing, which waits again on its own account.
   local whenItNoticed = backend:now()
   child:close()
   assertTrue(exit.timedOut, "the deadline fired")
   assertTrue(backend.state.waits > 1,
      "after several bounded sleeps rather than one long one")
   -- The clock only moves when this sleeps, so where it stopped is the sum of the
   -- budgets. A final sleep that ignored the time remaining would land past the
   -- deadline by up to a whole `BLOCKING_WAIT_MS`, and this is what notices.
   assertEq(whenItNoticed, 30, "and stopped exactly on it rather than overshooting")
end

function M.theBackpressureScriptReallyModelsTheDeadlock()
   -- Guards the guard. A script where every write lands and every read is ready cannot
   -- tell a combined step from a sequential one, and an earlier version of these tests
   -- passed against an implementation that deadlocks. So this drives the same backend
   -- the wrong way -- all the input first -- and asserts that it cannot get through.
   --
   -- If this ever stops stalling, `makesProgressOnAllThreeStreamsTogether` has stopped
   -- proving anything and both need looking at.
   local backend = fakeBackend({
      inputChunk = 4,
      outDelay = 1,
      blockWritesWhileUnread = true,
      exitNeedsStdin = true,
      out = {"one", "two", "three"},
      err = {"a", "b"},
      eofWhenExited = true,
      exitAfter = 6,
   })
   local child = process.spawnOn(backend, {args = {"filter"}})
   local payload = "a longer payload than one chunk"
   local sent, spins = 0, 0
   while sent < #payload and spins < 500 do
      spins = spins + 1
      sent = sent + child.stdin:offer(payload:sub(sent + 1))
   end
   child:close()
   assertTrue(sent < #payload,
      "writing stdin without draining the outputs must stall, not finish")
end

function M.aQuietChildStillHitsItsDeadline()
   -- The deadline case that a check made only before parking misses: a child producing
   -- nothing at all, so nothing else ever wakes the wait.
   local backend = fakeBackend({out = {}, err = {}, exitAfter = nil})
   local child = process.spawnOn(backend, {args = {"sleep"}, timeoutMs = 50})
   -- The clock moves while the wait is parked, not before it starts.
   local handler = {
      park = function(_self, waiting)
         local spins = 0
         while not waiting:ready() do
            spins = spins + 1
            backend:advance(20)
            suspension.poll()
            if spins > 50 then error("the deadline never fired", 0) end
         end
      end,
   }
   local installation = suspension.install(handler)
   local exit = child:wait()
   child:close()
   installation:release()
   assertTrue(exit.timedOut, "the deadline fired while suspended")
   assertTrue(exit.killed, "and killed it")
end

function M.aDeadlineSignalsOnlyOnceWhileTerminationTakesTime()
   -- Terminating takes several polls here. A deadline re-enforced every pump would keep
   -- signalling a process already dying, and a backend that treats each signal as a
   -- fresh request would never finish.
   local backend = fakeBackend({out = {}, err = {}, exitAfter = nil})
   backend.state.killLag = 4
   backend.state.kills = 0
   local child = process.spawnOn(backend, {args = {"stubborn"}, timeoutMs = 10})
   local handler = {
      park = function(_self, waiting)
         local spins = 0
         while not waiting:ready() do
            spins = spins + 1
            backend:advance(5)
            suspension.poll()
            if spins > 50 then error("the deadline never resolved", 0) end
         end
      end,
   }
   local installation = suspension.install(handler)
   local exit = child:wait()
   child:close()
   installation:release()
   assertTrue(exit.timedOut, "the deadline fired")
   assertEq(backend.state.kills, 1,
      "and asked exactly once, however many polls dying took")
end

function M.waitsKeepBlockingWhileAKilledChildTakesItsTimeToDie()
   -- Once the deadline has fired there is nothing left for it to bound: what
   -- remains of it is negative forever, and a budget still clamped to it would
   -- turn every wait into a non-blocking poll -- a busy loop until the killed
   -- child's exit is finally observed.
   local backend = fakeBackend({out = {}, err = {}, exitAfter = nil})
   backend.state.killLag = 3
   local zeroBudgets = 0
   local baseWait = backend.waitReady
   backend.waitReady = function(self, interest, timeoutMs)
      if timeoutMs == 0 then
         zeroBudgets = zeroBudgets + 1
      end
      return baseWait(self, interest, timeoutMs)
   end
   local child = process.spawnOn(backend, {args = {"stubborn"}, timeoutMs = 30})
   local exit = child:wait()
   child:close()
   assertTrue(exit.timedOut, "the deadline fired")
   assertEq(zeroBudgets, 0,
      "and the waits for the dying child kept their full budget")
end

function M.closeWaitsForAKilledChildToFinish()
   -- Terminating takes as long as it takes. Reaping something still dying is asking
   -- the platform about a state that is still changing.
   local backend = fakeBackend({out = {}, err = {}, exitAfter = nil})
   backend.state.killLag = 3
   local child = process.spawnOn(backend, {args = {"stubborn"}})
   child:close()
   assertTrue(backend.state.reaped, "it was reaped")
   assertTrue(backend.state.exited ~= nil,
      "and only after it had actually exited, not merely been asked to")
end

function M.readersAndWritersAreSeparateSurfaces()
   local backend = fakeBackend({out = {"x"}, exitAfter = 1})
   local child = process.spawnOn(backend, {args = {"echo"}})
   assertEq(child.stdout.write, nil, "stdout cannot be written")
   assertEq(child.stdin.read, nil, "stdin cannot be read")
   assertTrue(child.stdout.read ~= nil, "stdout reads")
   assertTrue(child.stdin.write ~= nil, "stdin writes")
   child:close()
end

function M.sharedViewsCompleteAndCloseTheBorrowedStreams()
   local backend = fakeBackend({out = {"abc"}, err = {}, exitAfter = 1})
   local child = process.spawnOn(backend, {args = {"filter"}})
   local reader = process.asReader(child.stdout)
   local writer = process.asWriter(child.stdin)

   assertEq(assert(reader:read(2)), "ab", "the reader honours its count")
   assertEq(assert(reader:read(2)), "c", "and keeps no adapter-side surplus")
   assertTrue(writer:write("payload"), "the writer completes its whole value")
   writer:close()
   assertTrue(backend.state.closed["in"], "and delivers EOF to the child")
   reader:close()
   assertTrue(backend.state.closed["out"], "through the one concrete stream")
   child:close()
end

return M
